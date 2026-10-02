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

/// "What am I leaving unused?" — every pilot's skill queue, unallocated SP and remaps,
/// industry, market and contract slots, planets, extractors, jump clones and research
/// agents on one board, the pilots with the most idle capacity first. Above it: account
/// totals and what frees up over the next 24 hours.
struct IdleCapacityView: View {
    @Environment(AccountManager.self) private var accountManager
    @Environment(DashboardPrefetcher.self) private var prefetcher
    @Environment(ThemeManager.self) private var themeManager
    @AppStorage("backgroundPollInterval") private var pollInterval: Double = 300

    @State private var isRefreshing = false
    @State private var kindFilter: IdleCapacityKind?

    private var palette: EVEPalette { themeManager.palette }
    private var service: IdleCapacityService { .shared }

    var body: some View {
        TimelineView(.periodic(from: .now, by: 60)) { context in
            content(pilots: pilots(now: context.date), now: context.date)
        }
        .eveScreenHeader("Idle Capacity", subtitle: subtitle, section: .idleCapacity) {
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

    private struct Pilot: Identifiable {
        let account: StoredAccount
        let corporationName: String
        let report: IdleCapacityReport
        /// What frees up or runs out within the next day.
        let events: [IdleCapacityEvent]
        var id: Int { account.characterID }
    }

    /// Pilots with prefetched data, most idle first.
    private func pilots(now: Date) -> [Pilot] {
        accountManager.accounts.compactMap { account -> Pilot? in
            guard let data = prefetcher.characterData[account.characterID] else { return nil }
            let input = service.input(characterID: account.characterID, data: data)
            return Pilot(account: account, corporationName: data.corporationName,
                         report: IdleCapacityEngine.report(input, now: now),
                         events: IdleCapacityEngine.events(input, now: now))
        }
        .sorted { a, b in
            if a.report.idleCount != b.report.idleCount { return a.report.idleCount > b.report.idleCount }
            if a.report.soonCount != b.report.soonCount { return a.report.soonCount > b.report.soonCount }
            return a.account.characterName.localizedStandardCompare(b.account.characterName) == .orderedAscending
        }
    }

    private var subtitle: Text? {
        let all = pilots(now: .now)
        guard !all.isEmpty else { return nil }
        let idle = all.reduce(0) { $0 + $1.report.idleCount }
        return Text("\(idle) idle across \(all.count) pilots")
    }

    private func refresh() async {
        isRefreshing = true
        defer { isRefreshing = false }
        await prefetcher.prefetchAll(accountManager: accountManager)
        await loadExtras()
    }

    private func loadExtras() async {
        await service.loadExtras(accountManager: accountManager, prefetcher: prefetcher, includeHistory: true)
    }

    // MARK: Content

    @ViewBuilder
    private func content(pilots: [Pilot], now: Date) -> some View {
        if pilots.isEmpty {
            if prefetcher.isLoading || accountManager.accounts.isEmpty == false && prefetcher.lastRefresh == nil {
                LoadingSkeleton()
            } else {
                EVEEmptyState("No Pilots Loaded", systemImage: "gauge.with.dots.needle.0percent",
                              message: Text("Add a character in Settings → Accounts, or refresh to load your pilots.")) {
                    Button("Refresh", systemImage: "arrow.clockwise") { Task { await refresh() } }
                        .buttonStyle(.borderedProminent)
                        .tint(palette.accent)
                }
            }
        } else {
            ScrollView {
                VStack(alignment: .leading, spacing: EVESpacing.xl) {
                    totalsBand(pilots, now: now)
                    let upcoming = pilots.flatMap { pilot in pilot.events.map { (account: pilot.account, event: $0) } }
                    if !upcoming.isEmpty {
                        IdleTimelineView(entries: upcoming, now: now)
                    }
                    summaryStrip(pilots)
                    let shown = kindFilter.map { kind in
                        pilots.filter { [.idle, .soon].contains($0.report.line(kind)?.status) }
                    } ?? pilots
                    if shown.isEmpty {
                        EVEEmptyState("Nothing Idle Here", systemImage: "checkmark.circle",
                                      message: Text("No pilot has this capacity idle or freeing up soon.")) {
                            Button("Show All Pilots") { withAnimation(EVEMotion.snappy) { kindFilter = nil } }
                        }
                        .frame(minHeight: 240)
                    } else {
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 340), spacing: EVESpacing.md)],
                                  spacing: EVESpacing.md) {
                            ForEach(shown) { pilot in
                                IdleCapacityCard(account: pilot.account, corporationName: pilot.corporationName,
                                                 report: pilot.report, now: now, highlight: kindFilter)
                                    .eveScrollReveal()
                            }
                        }
                    }
                }
                .padding()
            }
        }
    }

    // MARK: Totals

    /// Account-wide: industry slots free now, slot time idled this past week, the capacity
    /// idle longest, and what frees up next.
    private func totalsBand(_ pilots: [Pilot], now: Date) -> some View {
        let industry: Set<IdleCapacityKind> = [.manufacturing, .science, .reactions]
        let industryLines = pilots.flatMap { $0.report.lines.filter { industry.contains($0.kind) } }
        let free = industryLines.reduce(0) { $0 + $1.free }
        let limit = industryLines.reduce(0) { $0 + ($1.limit ?? 0) }
        let idleTimes = pilots.compactMap(\.report.idleSlotTime)
        let longest = pilots
            .flatMap { pilot in pilot.report.lines.compactMap { line in line.idleSince.map { (pilot.account, line.kind, $0) } } }
            .min { $0.2 < $1.2 }
        let next = pilots
            .flatMap { pilot in pilot.events.map { (pilot.account, $0) } }
            .min { $0.1.date < $1.1.date }

        return LazyVGrid(columns: [GridItem(.adaptive(minimum: 180), spacing: EVESpacing.md)], spacing: EVESpacing.md) {
            totalStat(String(localized: "Industry Slots Free"), value: "\(free)",
                      detail: limit > 0 ? String(localized: "of \(limit) across all pilots") : String(localized: "No industry slots"),
                      tint: free > 0 ? IdleCapacityStatus.idle.color : .secondary)
            totalStat(String(localized: "Slot-Days Idle · 7d"),
                      value: idleTimes.isEmpty ? "—" : (idleTimes.reduce(0, +) / 86400).formatted(.number.precision(.fractionLength(1))),
                      detail: idleTimes.isEmpty ? String(localized: "Loading job history…") : String(localized: "Industry slot time unused"),
                      tint: idleTimes.reduce(0, +) > 0 ? IdleCapacityStatus.idle.color : .secondary)
            totalStat(String(localized: "Idle Longest"),
                      value: longest.map { idleDuration(since: $0.2, now: now) } ?? "—",
                      detail: longest.map { "\($0.0.characterName) · \(String(localized: $0.1.titleResource))" }
                        ?? String(localized: "Nothing idle"),
                      tint: longest == nil ? .secondary : IdleCapacityStatus.idle.color)
            totalStat(String(localized: "Next Up"),
                      value: next.map { EVEFormatters.formatDuration(Int($0.1.date.timeIntervalSince(now))) } ?? "—",
                      detail: next.map { "\($0.0.characterName) · \(String(localized: $0.1.kind.titleResource))" }
                        ?? String(localized: "Nothing in the next 24h"),
                      tint: next == nil ? .secondary : IdleCapacityStatus.soon.color)
        }
    }

    private func totalStat(_ label: String, value: String, detail: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: EVESpacing.xs) {
            Text(verbatim: label)
                .font(.eveCaptionMedium)
                .foregroundStyle(.secondary)
            Text(verbatim: value)
                .font(.eveStat)
                .foregroundStyle(tint)
                .contentTransition(.numericText())
            Text(verbatim: detail)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(EVESpacing.lg)
        .eveCard(cornerRadius: EVERadius.xl)
        .accessibilityElement(children: .combine)
    }

    // MARK: Summary

    /// One tile per kind that any pilot has; clicking one shows only the pilots with that
    /// capacity idle (or freeing up within a day).
    private func summaryStrip(_ pilots: [Pilot]) -> some View {
        let tiles = IdleCapacityKind.allCases.compactMap { kind -> (IdleCapacityKind, String, String?)? in
            let lines = pilots.compactMap { $0.report.line(kind) }
            guard !lines.isEmpty else { return nil }
            let free = lines.reduce(0) { $0 + $1.free }
            let limit = lines.reduce(0) { $0 + ($1.limit ?? 0) }
            switch kind {
            case .training:
                let idle = lines.filter { $0.status == .idle }.count
                let soon = lines.filter { $0.status == .soon }.count
                return (kind, "\(idle)", soon > 0 ? String(localized: "\(soon) end < 24h") : String(localized: "of \(lines.count) pilots"))
            case .skillPoints:
                let sp = lines.reduce(0) { $0 + $1.count }
                return (kind, EVEFormatters.formatSP(sp, unit: false), String(localized: "\(lines.count) pilots"))
            case .manufacturing, .science, .reactions, .planets:
                return (kind, "\(free)", String(localized: "of \(limit)"))
            case .market, .contracts:
                let expiring = lines.reduce(0) { $0 + $1.expiring }
                return (kind, "\(free)", expiring > 0 ? String(localized: "\(expiring) expire < 24h") : String(localized: "of \(limit)"))
            case .extractors:
                let stopped = lines.reduce(0) { $0 + $1.count }
                let soon = lines.filter { $0.status == .soon }.count
                return (kind, "\(stopped)", soon > 0 ? String(localized: "\(soon) stop < 24h") : nil)
            case .cloneJump:
                return limit > 0 ? (kind, "\(free)", String(localized: "of \(limit)")) : nil
            case .remap, .research:
                return nil
            }
        }
        return LazyVGrid(columns: [GridItem(.adaptive(minimum: 128), spacing: EVESpacing.md)], spacing: EVESpacing.md) {
            ForEach(tiles, id: \.0) { kind, value, subLabel in
                filterTile(kind, value: value, subLabel: subLabel)
            }
        }
    }

    private func filterTile(_ kind: IdleCapacityKind, value: String, subLabel: String?) -> some View {
        let isActive = kindFilter == kind
        let hasIdle = value != "0"
        return Button {
            withAnimation(EVEMotion.snappy) { kindFilter = isActive ? nil : kind }
        } label: {
            MetricTileView(icon: kind.systemImage,
                           color: hasIdle ? IdleCapacityStatus.idle.color : .secondary,
                           value: value,
                           label: kind.tileTitle,
                           subLabel: subLabel)
                .eveSelectionGlow(isActive: isActive, cornerRadius: EVERadius.xl)
        }
        .buttonStyle(.plain)
        .eveHoverable(cornerRadius: EVERadius.xl)
        .help(isActive ? Text("Show all pilots") : Text("Show only pilots with \(Text(kind.title)) to use"))
        .accessibilityAddTraits(isActive ? .isSelected : [])
    }
}

// MARK:  Presentation

extension IdleCapacityKind {
    var title: LocalizedStringKey {
        switch self {
        case .training:      "Training"
        case .skillPoints:   "Skill Points"
        case .remap:         "Remap"
        case .manufacturing: "Manufacturing"
        case .science:       "Science"
        case .reactions:     "Reactions"
        case .market:        "Market"
        case .contracts:     "Contracts"
        case .planets:       "Planets"
        case .extractors:    "Extractors"
        case .cloneJump:     "Jump Clones"
        case .research:      "Research"
        }
    }

    /// `title` for plain-string contexts.
    var titleResource: LocalizedStringResource {
        switch self {
        case .training:      "Training"
        case .skillPoints:   "Skill Points"
        case .remap:         "Remap"
        case .manufacturing: "Manufacturing"
        case .science:       "Science"
        case .reactions:     "Reactions"
        case .market:        "Market"
        case .contracts:     "Contracts"
        case .planets:       "Planets"
        case .extractors:    "Extractors"
        case .cloneJump:     "Jump Clones"
        case .research:      "Research"
        }
    }

    /// Label under a summary tile's number.
    var tileTitle: String {
        switch self {
        case .training:      String(localized: "Idle Queues")
        case .skillPoints:   String(localized: "Unallocated SP")
        case .remap:         String(localized: "Remaps")
        case .manufacturing: String(localized: "Factory Slots Free")
        case .science:       String(localized: "Lab Slots Free")
        case .reactions:     String(localized: "Reaction Slots Free")
        case .market:        String(localized: "Order Slots Free")
        case .contracts:     String(localized: "Contract Slots Free")
        case .planets:       String(localized: "Planets Unused")
        case .extractors:    String(localized: "Extractors Stopped")
        case .cloneJump:     String(localized: "Clone Slots Free")
        case .research:      String(localized: "Research")
        }
    }

    var systemImage: String {
        switch self {
        case .training:      "graduationcap.fill"
        case .skillPoints:   "sparkles"
        case .remap:         "arrow.triangle.2.circlepath"
        case .manufacturing: "hammer.fill"
        case .science:       "flask.fill"
        case .reactions:     "atom"
        case .market:        "cart.fill"
        case .contracts:     "doc.text.fill"
        case .planets:       "globe.americas.fill"
        case .extractors:    "arrow.down.circle.fill"
        case .cloneJump:     "person.2.fill"
        case .research:      "book.closed.fill"
        }
    }

    /// The screen that deals with this capacity.
    var destination: NavigationSection {
        switch self {
        case .training, .skillPoints:               .training
        case .remap:                                .remapAdvisor
        case .manufacturing, .science, .reactions:  .industry
        case .market:                               .finances
        case .contracts:                            .contracts
        case .planets, .extractors:                 .colonies
        case .cloneJump:                            .clones
        case .research:                             .research
        }
    }
}

extension IdleCapacityStatus {
    var color: Color {
        switch self {
        case .idle: .orange
        case .soon: .yellow
        case .busy: .green
        case .info: .secondary
        }
    }
}

// MARK:  Card

/// One pilot: portrait, how much is idle, then a line per capacity. Clicking a line
/// switches to the pilot and opens the screen that deals with it.
struct IdleCapacityCard: View {
    let account: StoredAccount
    let corporationName: String
    let report: IdleCapacityReport
    var now: Date = .now
    var highlight: IdleCapacityKind?

    @Environment(AccountManager.self) private var accountManager

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
                .padding(EVESpacing.lg)
            Divider().opacity(0.5)
            VStack(alignment: .leading, spacing: EVESpacing.xs) {
                ForEach(report.lines) { line in
                    Button {
                        accountManager.selectedCharacterID = account.characterID
                        AppRouter.shared.pendingSection = line.kind.destination
                    } label: {
                        IdleCapacityLineRow(line: line, now: now)
                            .padding(.horizontal, EVESpacing.sm)
                            .padding(.vertical, EVESpacing.xs)
                            .background(highlight == line.kind ? line.status.color.opacity(EVEOpacity.faint) : .clear,
                                        in: RoundedRectangle(cornerRadius: EVERadius.sm))
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .eveHoverable(cornerRadius: EVERadius.sm)
                    .help(Text("Open \(Text(line.kind.destination.title)) for \(account.characterName)"))
                }
            }
            .padding(EVESpacing.md)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .eveCard(cornerRadius: EVERadius.xl)
    }

    private var header: some View {
        HStack(spacing: EVESpacing.lg) {
            CachedAsyncImage(url: EVEImageURL.characterPortrait(account.characterID, size: 128)) { image in
                image.resizable().aspectRatio(contentMode: .fill)
            } placeholder: {
                Circle().fill(.quaternary)
            }
            .frame(width: 44, height: 44)
            .clipShape(Circle())
            .overlay(Circle().strokeBorder(.primary.opacity(0.08), lineWidth: 0.5))

            VStack(alignment: .leading, spacing: 3) {
                Text(verbatim: account.characterName)
                    .font(.subheadline.bold())
                    .lineLimit(1)
                if !corporationName.isEmpty {
                    Text(verbatim: corporationName)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: EVESpacing.sm)
            summaryBadge
        }
    }

    private var summaryBadge: some View {
        let idle = report.idleCount
        let soon = report.soonCount
        let (text, tint): (Text, Color) =
            idle > 0 ? (Text("\(idle) idle"), IdleCapacityStatus.idle.color)
            : soon > 0 ? (Text("\(soon) soon"), IdleCapacityStatus.soon.color)
            : (Text("All busy"), IdleCapacityStatus.busy.color)
        return text
            .font(.eveCaptionBold)
            .foregroundStyle(tint)
            .padding(.horizontal, EVESpacing.md)
            .padding(.vertical, 3)
            .background(tint.opacity(EVEOpacity.soft), in: Capsule())
    }
}

// MARK:  Line

private struct IdleCapacityLineRow: View {
    let line: IdleCapacityLine
    let now: Date

    var body: some View {
        HStack(spacing: EVESpacing.md) {
            Image(systemName: line.kind.systemImage)
                .font(.caption)
                .foregroundStyle(line.status == .info ? Color.secondary : line.status.color)
                .frame(width: 16)
                .accessibilityHidden(true)
            Text(line.kind.title)
                .font(.eveCaptionMedium)
                .foregroundStyle(.secondary)
                .frame(width: 92, alignment: .leading)
            if let used = line.used, let limit = line.limit, limit > 0 {
                CapacityBar(used: used, limit: limit, tint: line.status.color)
                    .frame(width: 70, height: 6)
                Text(verbatim: "\(used)/\(limit)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: EVESpacing.xs)
            Text(detail)
                .font(.caption.monospacedDigit())
                .foregroundStyle(line.status == .busy || line.status == .info ? Color.secondary : line.status.color)
                .lineLimit(1)
        }
        .accessibilityElement(children: .combine)
    }

    private var detail: String {
        let idleFor = line.idleSince.map { String(localized: " · idle \(idleDuration(since: $0, now: now))") } ?? ""
        switch line.kind {
        case .training:
            switch line.status {
            case .idle: return line.count > 0 ? String(localized: "Queue paused") : String(localized: "Queue empty")
            default:    return line.date.map { String(localized: "Ends in \(EVEFormatters.timeUntil($0))") } ?? ""
            }
        case .skillPoints:
            return String(localized: "\(EVEFormatters.formatSP(line.count)) unallocated")
        case .remap:
            return line.count > 0 ? String(localized: "\(line.count) bonus remaps") : String(localized: "Yearly remap available")
        case .manufacturing, .science, .reactions:
            if line.status == .idle {
                let open = max((line.limit ?? 0) - (line.used ?? 0), 0)
                switch (open, line.count) {
                case (_, 0):    return String(localized: "\(open) free") + idleFor
                case (0, let n): return String(localized: "\(n) ready to deliver") + idleFor
                case let (o, n): return String(localized: "\(o) free · \(n) to deliver") + idleFor
                }
            }
            return line.date.map { String(localized: "Frees in \(EVEFormatters.timeUntil($0))") } ?? String(localized: "Full")
        case .market, .contracts:
            let expiring = line.expiring > 0 ? String(localized: "\(line.expiring) expire < 24h") : nil
            switch line.status {
            case .idle: return [String(localized: "\(line.free) free"), expiring].compactMap { $0 }.joined(separator: " · ")
            case .soon: return expiring ?? ""
            default:    return line.date.map { String(localized: "Next expires in \(EVEFormatters.timeUntil($0))") } ?? String(localized: "All in use")
            }
        case .planets:
            return line.status == .idle ? String(localized: "\(line.free) free") : String(localized: "All in use")
        case .extractors:
            if line.status == .idle { return String(localized: "\(line.count) stopped") + idleFor }
            return line.date.map { String(localized: "Next stops in \(EVEFormatters.timeUntil($0))") } ?? ""
        case .cloneJump:
            let jump = line.date.map { String(localized: "Jump in \(EVEFormatters.timeUntil($0))") } ?? String(localized: "Jump ready")
            if line.status == .idle { return String(localized: "\(line.free) free · \(jump)") }
            return (line.limit ?? 0) > 0 ? jump : String(localized: "\(line.used ?? 0) clones · \(jump)")
        case .research:
            let points = (line.points ?? 0).formatted(.number.precision(.fractionLength(0)))
            return String(localized: "\(line.count) agents · \(points) RP")
        }
    }
}

/// How long something has sat idle: "3d 4h", "5h 12m", "40m"; "90d+" when it's older
/// than the job history.
private func idleDuration(since: Date, now: Date) -> String {
    if since == .distantPast { return String(localized: "90d+") }
    let seconds = max(Int(now.timeIntervalSince(since)), 0)
    let days = seconds / 86400
    let hours = (seconds % 86400) / 3600
    let minutes = (seconds % 3600) / 60
    if days > 0 { return "\(days)d \(hours)h" }
    if hours > 0 { return "\(hours)h \(minutes)m" }
    return "\(minutes)m"
}

// MARK:  Timeline

/// The next 24 hours across every pilot: a lane per kind, each mark a pilot's portrait
/// at the moment their slot frees, queue ends, extractor stops, jump comes ready or
/// listing expires. Clicking a mark opens that pilot's screen for it.
private struct IdleTimelineView: View {
    let entries: [(account: StoredAccount, event: IdleCapacityEvent)]
    let now: Date

    @Environment(AccountManager.self) private var accountManager

    private let labelWidth: CGFloat = 104
    private let markSize: CGFloat = 20
    private var window: TimeInterval { IdleCapacityEngine.soonWindow }

    private var lanes: [IdleCapacityKind] {
        let kinds = Set(entries.map(\.event.kind))
        return IdleCapacityKind.allCases.filter(kinds.contains)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: EVESpacing.sm) {
            HStack {
                Text("Next 24 Hours")
                    .font(.eveRowTitle)
                Spacer()
                Text("\(entries.count) upcoming")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            HStack(spacing: EVESpacing.sm) {
                Color.clear.frame(width: labelWidth, height: 1)
                axis
            }
            ForEach(lanes, id: \.self) { kind in
                HStack(spacing: EVESpacing.sm) {
                    Label(kind.title, systemImage: kind.systemImage)
                        .font(.eveCaptionMedium)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .frame(width: labelWidth, alignment: .leading)
                    lane(entries.filter { $0.event.kind == kind })
                        .frame(height: markSize + 4)
                }
            }
        }
        .padding(EVESpacing.lg)
        .eveCard(cornerRadius: EVERadius.xl)
    }

    /// "Now", then clock times every six hours.
    private var axis: some View {
        GeometryReader { proxy in
            let usable = proxy.size.width - markSize
            ForEach(0..<5, id: \.self) { step in
                tickLabel(step)
                    .font(.eveMicro)
                    .foregroundStyle(.tertiary)
                    .fixedSize()
                    .position(x: markSize / 2 + usable * CGFloat(step) / 4, y: 6)
            }
        }
        .frame(height: 12)
    }

    private func tickLabel(_ step: Int) -> Text {
        guard step > 0 else { return Text("Now") }
        return Text(now.addingTimeInterval(Double(step) * window / 4), format: .dateTime.hour().minute())
    }

    private func mark(_ account: StoredAccount, _ event: IdleCapacityEvent) -> some View {
        let remaining = EVEFormatters.formatDuration(Int(event.date.timeIntervalSince(now)))
        return Button {
            accountManager.selectedCharacterID = account.characterID
            AppRouter.shared.pendingSection = event.kind.destination
        } label: {
            CachedAsyncImage(url: EVEImageURL.characterPortrait(account.characterID, size: 64)) { image in
                image.resizable().aspectRatio(contentMode: .fill)
            } placeholder: {
                Circle().fill(.quaternary)
            }
            .frame(width: markSize, height: markSize)
            .clipShape(Circle())
            .overlay(Circle().strokeBorder(IdleCapacityStatus.soon.color, lineWidth: 1.5))
        }
        .buttonStyle(.plain)
        .help(Text("\(account.characterName) · \(Text(event.kind.title)) in \(remaining)"))
    }

    private func lane(_ marks: [(account: StoredAccount, event: IdleCapacityEvent)]) -> some View {
        GeometryReader { proxy in
            let usable = proxy.size.width - markSize
            let midY = proxy.size.height / 2
            ZStack(alignment: .topLeading) {
                Capsule()
                    .fill(.quaternary)
                    .frame(width: proxy.size.width, height: 2)
                    .position(x: proxy.size.width / 2, y: midY)
                ForEach(Array(marks.enumerated()), id: \.offset) { _, entry in
                    let fraction = CGFloat(min(max(entry.event.date.timeIntervalSince(now) / window, 0), 1))
                    mark(entry.account, entry.event)
                        .position(x: markSize / 2 + usable * fraction, y: midY)
                }
            }
        }
    }
}

private struct CapacityBar: View {
    let used: Int
    let limit: Int
    let tint: Color

    var body: some View {
        GeometryReader { proxy in
            let fraction = limit > 0 ? min(Double(used) / Double(limit), 1) : 0
            ZStack(alignment: .leading) {
                Capsule().fill(.quaternary)
                Capsule().fill(tint).frame(width: proxy.size.width * fraction)
            }
        }
        .accessibilityHidden(true)
    }
}
