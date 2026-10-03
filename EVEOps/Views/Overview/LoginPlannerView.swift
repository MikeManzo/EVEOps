//
// This file is part of EVEOps.
//
// EVEOps is free software: you can redistribute it and/or modify
// it under the terms of the GNU General Public License as published by
// the Free Software Foundation, version 3 or later.
//
// Copyright (c) 2026 CitizenCoder
//

import SwiftUI

// MARK:  Main View

/// "When do I actually need to log in?" — every pilot's queues, industry slots, PI
/// extractors and expiring listings folded into the fewest logins that keep them working,
/// within how long you'll let things sit idle and the hours you can play.
struct LoginPlannerView: View {
    @Environment(AccountManager.self) private var accountManager
    @Environment(DashboardPrefetcher.self) private var prefetcher
    @Environment(ThemeManager.self) private var themeManager
    @AppStorage("backgroundPollInterval") private var pollInterval: Double = 300

    @AppStorage("loginPlan.toleranceHours") private var toleranceHours: Double = 4
    @AppStorage("loginPlan.horizonDays") private var horizonDays: Double = 3
    @AppStorage("loginPlan.dayStart") private var dayStart = 8
    @AppStorage("loginPlan.dayEnd") private var dayEnd = 23
    @AppStorage("loginPlan.excludedKinds") private var excludedRaw = ""

    @State private var isRefreshing = false

    private var palette: EVEPalette { themeManager.palette }
    private var service: IdleCapacityService { .shared }

    private var settings: LoginPlanSettings {
        LoginPlanSettings(tolerance: toleranceHours * 3600, horizon: horizonDays * 86400,
                          dayStartHour: dayStart, dayEndHour: dayEnd)
    }

    private var excluded: Set<IdleCapacityKind> {
        Set(excludedRaw.split(separator: ",").compactMap { IdleCapacityKind(rawValue: String($0)) })
    }

    private var kinds: Set<IdleCapacityKind> { LoginPlanEngine.plannableKinds.subtracting(excluded) }

    var body: some View {
        TimelineView(.periodic(from: .now, by: 60)) { context in
            content(plan: plan(now: context.date), now: context.date)
        }
        .eveScreenHeader("Login Planner", subtitle: subtitle, section: .loginPlanner) {
            RelativeTimestamp(date: prefetcher.lastRefresh)
            RefreshButton(isRefreshing: isRefreshing || prefetcher.isLoading) {
                Task { await refresh() }
            }
        }
        .task(id: accountManager.accounts.map(\.characterID)) {
            if prefetcher.characterData.isEmpty { await prefetcher.prefetchAll(accountManager: accountManager) }
            await loadExtras()
        }
        .autoRefresh(every: pollInterval) { await loadExtras() }
        .onChange(of: prefetcher.lastRefresh) { _, _ in Task { await loadExtras() } }
        .onChange(of: AppRouter.shared.refreshTick) { _, _ in Task { await refresh() } }
    }

    // MARK: Data

    private func plan(now: Date) -> LoginPlan? {
        let settings = settings
        let kinds = kinds
        var items: [LoginPlanItem] = []
        var loaded = false
        for account in accountManager.accounts {
            guard let data = prefetcher.characterData[account.characterID] else { continue }
            loaded = true
            let input = service.input(characterID: account.characterID, data: data)
            items += LoginPlanEngine.items(
                characterID: account.characterID,
                report: IdleCapacityEngine.report(input, now: now),
                events: IdleCapacityEngine.events(input, now: now, window: settings.horizon),
                kinds: kinds, now: now
            )
        }
        return loaded ? LoginPlanEngine.plan(items, settings: settings, now: now) : nil
    }

    private var subtitle: Text? {
        guard let plan = plan(now: .now), !plan.sessions.isEmpty else { return nil }
        return Text("\(plan.sessions.count) logins over the next \(horizonLabel(horizonDays))")
    }

    private func refresh() async {
        isRefreshing = true
        defer { isRefreshing = false }
        await prefetcher.prefetchAll(accountManager: accountManager)
        await loadExtras()
    }

    private func loadExtras() async {
        await service.loadExtras(accountManager: accountManager, prefetcher: prefetcher, includeHistory: false)
    }

    private func account(_ id: Int) -> StoredAccount? {
        accountManager.accounts.first { $0.characterID == id }
    }

    // MARK: Content

    @ViewBuilder
    private func content(plan: LoginPlan?, now: Date) -> some View {
        if let plan {
            ScrollView {
                VStack(alignment: .leading, spacing: EVESpacing.xl) {
                    controls
                    totals(plan, now: now)
                    if plan.sessions.isEmpty {
                        EVEEmptyState("Nothing to Log In For", systemImage: "moon.zzz",
                                      message: Text("Nothing comes due in this window. Start some jobs or queue skills and the plan fills in."))
                            .frame(minHeight: 240)
                    } else {
                        LoginScheduleStrip(plan: plan, settings: settings, now: now)
                        ForEach(Array(plan.sessions.enumerated()), id: \.element.id) { index, session in
                            sessionCard(session, number: index + 1, now: now)
                                .eveScrollReveal()
                        }
                        Text("New jobs and queues you start at a login add their own timers — the plan updates as they appear.")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                }
                .padding()
            }
        } else if prefetcher.isLoading || !accountManager.accounts.isEmpty {
            LoadingSkeleton()
        } else {
            EVEEmptyState("No Pilots Loaded", systemImage: "calendar.badge.clock",
                          message: Text("Add a character in Settings → Accounts, or refresh to load your pilots.")) {
                Button("Refresh", systemImage: "arrow.clockwise") { Task { await refresh() } }
                    .buttonStyle(.borderedProminent)
                    .tint(palette.accent)
            }
        }
    }

    // MARK: Controls

    private var controls: some View {
        VStack(alignment: .leading, spacing: EVESpacing.md) {
            HStack(spacing: EVESpacing.lg) {
                labeled("Idle up to") {
                    EVEMenuPicker("Idle up to", selection: $toleranceHours, options: [1, 2, 4, 8, 12, 24].map {
                        EVEMenuOption(Double($0), verbatim: String(localized: "\($0)h"))
                    })
                }
                labeled("Plan ahead") {
                    EVEMenuPicker("Plan ahead", selection: $horizonDays, options: [1, 3, 7].map {
                        EVEMenuOption(Double($0), verbatim: horizonLabel(Double($0)))
                    })
                }
                labeled("Available") {
                    HStack(spacing: EVESpacing.xs) {
                        EVEMenuPicker("From", selection: $dayStart, options: hourOptions)
                        Text(verbatim: "–").foregroundStyle(.secondary)
                        EVEMenuPicker("Until", selection: $dayEnd, options: hourOptions)
                    }
                }
                .help("Logins are only planned between these hours. Pick the same hour twice for any time.")
                Spacer()
            }
            HStack(spacing: EVESpacing.sm) {
                Text("Plan for")
                    .font(.eveCaptionMedium)
                    .foregroundStyle(.secondary)
                ForEach(IdleCapacityKind.allCases.filter(LoginPlanEngine.plannableKinds.contains), id: \.self) { kind in
                    InsightToggleChip(title: Text(kind.title), systemImage: kind.systemImage,
                                      isOn: !excluded.contains(kind), tint: palette.accent) {
                        toggle(kind)
                    }
                }
            }
        }
    }

    private func labeled<Content: View>(_ title: LocalizedStringKey, @ViewBuilder content: () -> Content) -> some View {
        HStack(spacing: EVESpacing.sm) {
            Text(title)
                .font(.eveCaptionMedium)
                .foregroundStyle(.secondary)
            content()
        }
    }

    private var hourOptions: [EVEMenuOption<Int>] {
        (0..<24).map { hour in
            let date = Calendar.current.date(bySettingHour: hour, minute: 0, second: 0, of: .now) ?? .now
            return EVEMenuOption(hour, verbatim: date.formatted(.dateTime.hour().minute()))
        }
    }

    private func toggle(_ kind: IdleCapacityKind) {
        var set = excluded
        if set.contains(kind) { set.remove(kind) } else { set.insert(kind) }
        withAnimation(EVEMotion.snappy) {
            excludedRaw = set.map(\.rawValue).sorted().joined(separator: ",")
        }
    }

    private func horizonLabel(_ days: Double) -> String {
        days == 1 ? String(localized: "24 hours") : String(localized: "\(Int(days)) days")
    }

    // MARK: Totals

    private func totals(_ plan: LoginPlan, now: Date) -> some View {
        let next = plan.sessions.first
        let pilots = Set(plan.sessions.flatMap(\.characterIDs)).count
        let saved = plan.reactiveLogins - plan.sessions.count
        return InsightStatRow {
            InsightStat(label: String(localized: "Logins Needed"), value: "\(plan.sessions.count)",
                        detail: saved > 0
                            ? String(localized: "instead of \(plan.reactiveLogins) chasing every timer")
                            : String(localized: "over the next \(horizonLabel(horizonDays))"),
                        tint: palette.accent)
            InsightStat(label: String(localized: "Next Login"),
                        value: next.map { sessionTime($0.date, now: now) } ?? "—",
                        detail: next.map { $0.date <= now.addingTimeInterval(60) ? String(localized: "Things are idle now")
                                                                                 : String(localized: "in \(EVEFormatters.timeUntil($0.date))") }
                            ?? String(localized: "Nothing due"),
                        tint: next.map { $0.overdueCount(now: now) > 0 ? IdleCapacityStatus.idle.color : IdleCapacityStatus.soon.color }
                            ?? .secondary)
            InsightStat(label: String(localized: "Idle Accepted"),
                        value: hours(plan.totalWait),
                        detail: String(localized: "item-hours waiting for a login"),
                        tint: .secondary)
            InsightStat(label: String(localized: "Covered"), value: "\(plan.itemCount)",
                        detail: String(localized: "timers across \(pilots) pilots"))
        }
    }

    private func hours(_ seconds: TimeInterval) -> String {
        let h = seconds / 3600
        return h < 10 ? String(localized: "\(h.formatted(.number.precision(.fractionLength(1))))h")
                      : String(localized: "\(Int(h.rounded()))h")
    }

    private func sessionTime(_ date: Date, now: Date) -> String {
        if date <= now.addingTimeInterval(60) { return String(localized: "Now") }
        let calendar = Calendar.current
        if calendar.isDateInToday(date) { return date.formatted(.dateTime.hour().minute()) }
        return date.formatted(.dateTime.weekday(.abbreviated).hour().minute())
    }

    // MARK: Session

    private func sessionCard(_ session: LoginSession, number: Int, now: Date) -> some View {
        let byPilot = Dictionary(grouping: session.items, by: \.characterID)
        let overdue = session.overdueCount(now: now)
        let longestWait = session.items.map { session.date.timeIntervalSince(max($0.date, now)) }.max() ?? 0
        return HStack(alignment: .top, spacing: EVESpacing.xl) {
            VStack(alignment: .leading, spacing: EVESpacing.xs) {
                Text("Login \(number)")
                    .font(.eveCaptionMedium)
                    .foregroundStyle(.secondary)
                Text(verbatim: sessionTime(session.date, now: now))
                    .font(.eveStatCompact)
                    .foregroundStyle(overdue > 0 ? IdleCapacityStatus.idle.color : .primary)
                if session.date > now.addingTimeInterval(60) {
                    Text("in \(EVEFormatters.timeUntil(session.date))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if overdue > 0 {
                    EVEChip(Text("\(overdue) idle now"), tint: IdleCapacityStatus.idle.color)
                }
            }
            .frame(width: 120, alignment: .leading)

            VStack(alignment: .leading, spacing: EVESpacing.sm) {
                ForEach(session.characterIDs, id: \.self) { characterID in
                    pilotRow(characterID, items: byPilot[characterID] ?? [])
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            VStack(alignment: .trailing, spacing: EVESpacing.xs) {
                if longestWait > 60 {
                    Text("Longest wait \(EVEFormatters.formatDuration(Int(longestWait)))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if let skip = session.skipCost, skip > 0 {
                    Text("Skip it: +\(hours(skip)) idle")
                        .font(.eveCaptionBold)
                        .foregroundStyle(IdleCapacityStatus.idle.color)
                        .help("If you skip this login, its \(session.items.count) items wait for the next one.")
                }
            }
        }
        .padding(EVESpacing.lg)
        .eveCard(cornerRadius: EVERadius.xl)
    }

    private func pilotRow(_ characterID: Int, items: [LoginPlanItem]) -> some View {
        let counts = Dictionary(grouping: items, by: \.kind).mapValues(\.count)
        let ordered = IdleCapacityKind.allCases.filter { counts[$0] != nil }
        return HStack(spacing: EVESpacing.md) {
            PilotPortrait(characterID: characterID, size: 24)
            Text(verbatim: account(characterID)?.characterName ?? "#\(characterID)")
                .font(.eveCalloutSemibold)
                .lineLimit(1)
                .frame(minWidth: 120, alignment: .leading)
            ForEach(ordered, id: \.self) { kind in
                Button {
                    accountManager.selectedCharacterID = characterID
                    AppRouter.shared.pendingSection = kind.destination
                } label: {
                    HStack(spacing: EVESpacing.xs) {
                        Image(systemName: kind.systemImage)
                        Text(kind.title)
                        if let n = counts[kind], n > 1 { Text(verbatim: "×\(n)").monospacedDigit() }
                    }
                }
                .buttonStyle(.plain)
                .modifier(ReadyRoomChipStyle(tint: IdleCapacityStatus.soon.color))
                .help(Text("Open \(Text(kind.destination.title))"))
            }
            Spacer(minLength: 0)
        }
    }
}

// MARK:  Schedule strip

/// The whole horizon on one line: available hours shaded, a numbered pin at each login,
/// and a tick under it for every timer it covers.
private struct LoginScheduleStrip: View {
    let plan: LoginPlan
    let settings: LoginPlanSettings
    let now: Date

    @Environment(ThemeManager.self) private var themeManager

    private var span: TimeInterval { max(plan.horizonEnd.timeIntervalSince(now), 1) }

    var body: some View {
        VStack(alignment: .leading, spacing: EVESpacing.sm) {
            HStack {
                Text("Schedule")
                    .font(.eveRowTitle)
                Spacer()
                Label("Available", systemImage: "square.fill")
                    .font(.caption)
                    .foregroundStyle(themeManager.palette.accent.opacity(0.5))
            }
            GeometryReader { proxy in
                let width = proxy.size.width
                ZStack(alignment: .topLeading) {
                    // Available windows.
                    ForEach(Array(availableRanges().enumerated()), id: \.offset) { _, range in
                        let x0 = x(range.lowerBound, width), x1 = x(range.upperBound, width)
                        RoundedRectangle(cornerRadius: 3)
                            .fill(themeManager.palette.accent.opacity(0.14))
                            .frame(width: max(x1 - x0, 1), height: 22)
                            .offset(x: x0, y: 18)
                    }
                    // Day boundaries.
                    ForEach(dayStarts(), id: \.self) { day in
                        Rectangle().fill(.quaternary).frame(width: 1, height: 40).offset(x: x(day, width), y: 10)
                        Text(day, format: .dateTime.weekday(.abbreviated))
                            .font(.eveMicro)
                            .foregroundStyle(.tertiary)
                            .offset(x: x(day, width) + 3, y: 44)
                    }
                    // Timers.
                    ForEach(Array(plan.sessions.flatMap(\.items).enumerated()), id: \.offset) { _, item in
                        Capsule()
                            .fill(IdleCapacityStatus.soon.color.opacity(0.7))
                            .frame(width: 2, height: 10)
                            .offset(x: x(max(item.date, now), width), y: 24)
                    }
                    // Logins.
                    ForEach(Array(plan.sessions.enumerated()), id: \.offset) { index, session in
                        Text(verbatim: "\(index + 1)")
                            .font(.eveMicroBold)
                            .foregroundStyle(.white)
                            .frame(width: 16, height: 16)
                            .background(themeManager.palette.accent, in: Circle())
                            .offset(x: x(session.date, width) - 8, y: 0)
                            .help(Text(session.date, format: .dateTime.weekday().hour().minute()))
                    }
                }
            }
            .frame(height: 58)
        }
        .padding(EVESpacing.lg)
        .eveCard(cornerRadius: EVERadius.xl)
    }

    private func x(_ date: Date, _ width: CGFloat) -> CGFloat {
        CGFloat(min(max(date.timeIntervalSince(now) / span, 0), 1)) * width
    }

    private func dayStarts() -> [Date] {
        let calendar = Calendar.current
        var out: [Date] = []
        var day = calendar.startOfDay(for: now)
        while day < plan.horizonEnd {
            day = calendar.date(byAdding: .day, value: 1, to: day) ?? plan.horizonEnd
            if day < plan.horizonEnd { out.append(day) }
        }
        return out
    }

    /// Available stretches within the horizon, sampled every 15 minutes.
    private func availableRanges() -> [Range<Date>] {
        let availability = LoginPlanEngine.Availability(settings: settings, calendar: .current)
        var ranges: [Range<Date>] = []
        var start: Date?
        var t = now
        while t <= plan.horizonEnd {
            if availability.contains(t) {
                if start == nil { start = t }
            } else if let s = start {
                ranges.append(s..<t)
                start = nil
            }
            t = t.addingTimeInterval(LoginPlanEngine.grid)
        }
        if let s = start { ranges.append(s..<plan.horizonEnd) }
        return ranges
    }
}
