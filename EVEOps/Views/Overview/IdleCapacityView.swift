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

/// "What am I leaving unused?" — every pilot's skill queue, industry and market slots,
/// planets, extractors, clone jump timer and research agents on one board, the pilots
/// with the most idle capacity first.
struct IdleCapacityView: View {
    @Environment(AccountManager.self) private var accountManager
    @Environment(DashboardPrefetcher.self) private var prefetcher
    @Environment(ThemeManager.self) private var themeManager
    @AppStorage("backgroundPollInterval") private var pollInterval: Double = 300

    /// Character → earliest extractor expiry on each colony that has extractors.
    @State private var extractorExpiries: [Int: [Date]] = [:]
    /// Character → research agents; absent when the scope is missing or the read failed.
    @State private var researchAgents: [Int: [IdleCapacityAgent]] = [:]
    @State private var isRefreshing = false
    @State private var kindFilter: IdleCapacityKind?

    private var palette: EVEPalette { themeManager.palette }

    var body: some View {
        TimelineView(.periodic(from: .now, by: 60)) { context in
            content(pilots: pilots(now: context.date))
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
        var id: Int { account.characterID }
    }

    /// Pilots with prefetched data, most idle first.
    private func pilots(now: Date) -> [Pilot] {
        accountManager.accounts.compactMap { account -> Pilot? in
            guard let data = prefetcher.characterData[account.characterID] else { return nil }
            let input = IdleCapacityInput(
                skills: Dictionary(data.skills.skills.map { ($0.skillId, $0.activeSkillLevel) }, uniquingKeysWith: max),
                queueFinishDates: data.skillQueue.map(\.finishDate),
                jobs: data.industryJobs.map { IdleCapacityJob(activityID: $0.activityId, status: $0.status, endDate: $0.endDate) },
                orderCount: data.marketOrders.count,
                colonyCount: data.colonies.count,
                extractorExpiries: extractorExpiries[account.characterID],
                lastCloneJump: data.clones?.lastCloneJumpDate,
                jumpCloneCount: data.clones?.jumpClones.count ?? 0,
                researchAgents: researchAgents[account.characterID]
            )
            return Pilot(account: account, corporationName: data.corporationName,
                         report: IdleCapacityEngine.report(input, now: now))
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

    /// Extractor expiries (from each colony's layout) and research agents — the two things
    /// the prefetcher doesn't keep.
    private func loadExtras() async {
        let accounts = accountManager.accounts.filter { !$0.needsReauth }
        var tokens: [Int: String] = [:]
        for account in accounts {
            tokens[account.characterID] = try? await accountManager.validToken(for: account)
        }
        let colonies: [(characterID: Int, planetID: Int)] = accounts.flatMap { account in
            (prefetcher.characterData[account.characterID]?.colonies ?? []).map { (account.characterID, $0.planetId) }
        }
        let researchers = accounts.filter { $0.scopes.contains("esi-characters.read_agents_research.v1") }.map(\.characterID)

        let expiries = await withTaskGroup(of: (Int, Date?).self) { group in
            for (characterID, planetID) in colonies {
                guard let token = tokens[characterID] else { continue }
                group.addTask {
                    let layout: ESIColonyLayout? = try? await ESIClient.shared.fetch(
                        "/characters/\(characterID)/planets/\(planetID)/", token: token
                    )
                    return (characterID, layout.flatMap(ExtractorStatus.init(layout:))?.expiry)
                }
            }
            var out: [Int: [Date]] = [:]
            for await (characterID, expiry) in group {
                out[characterID, default: []].append(contentsOf: expiry.map { [$0] } ?? [])
            }
            return out
        }

        let agents = await withTaskGroup(of: (Int, [IdleCapacityAgent]?).self) { group in
            for characterID in researchers {
                guard let token = tokens[characterID] else { continue }
                group.addTask {
                    let raw: [ESIResearchAgent]? = try? await ESIClient.shared.fetch(
                        "/characters/\(characterID)/agents_research/", token: token
                    )
                    return (characterID, raw?.map {
                        IdleCapacityAgent(pointsPerDay: $0.pointsPerDay, remainderPoints: $0.remainderPoints, startedAt: $0.startedAt)
                    })
                }
            }
            var out: [Int: [IdleCapacityAgent]] = [:]
            for await (characterID, list) in group {
                if let list { out[characterID] = list }
            }
            return out
        }

        extractorExpiries = expiries
        researchAgents = agents
    }

    // MARK: Content

    @ViewBuilder
    private func content(pilots: [Pilot]) -> some View {
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
                                                 report: pilot.report, highlight: kindFilter)
                                    .eveScrollReveal()
                            }
                        }
                    }
                }
                .padding()
            }
        }
    }

    // MARK: Summary

    /// One tile per kind that any pilot has; clicking one shows only the pilots with that
    /// capacity idle (or freeing up within a day).
    private func summaryStrip(_ pilots: [Pilot]) -> some View {
        let tiles = IdleCapacityKind.allCases.compactMap { kind -> (IdleCapacityKind, String, String?)? in
            let lines = pilots.compactMap { $0.report.line(kind) }
            guard !lines.isEmpty, kind != .cloneJump, kind != .research else { return nil }
            switch kind {
            case .training:
                let idle = lines.filter { $0.status == .idle }.count
                let soon = lines.filter { $0.status == .soon }.count
                return (kind, "\(idle)", soon > 0 ? String(localized: "\(soon) end < 24h") : String(localized: "of \(lines.count) pilots"))
            case .manufacturing, .science, .reactions, .market, .planets:
                let free = lines.reduce(0) { $0 + $1.free }
                let limit = lines.reduce(0) { $0 + ($1.limit ?? 0) }
                return (kind, "\(free)", String(localized: "of \(limit)"))
            case .extractors:
                let stopped = lines.reduce(0) { $0 + $1.count }
                let soon = lines.filter { $0.status == .soon }.count
                return (kind, "\(stopped)", soon > 0 ? String(localized: "\(soon) stop < 24h") : nil)
            case .cloneJump, .research:
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
        case .manufacturing: "Manufacturing"
        case .science:       "Science"
        case .reactions:     "Reactions"
        case .market:        "Market"
        case .planets:       "Planets"
        case .extractors:    "Extractors"
        case .cloneJump:     "Clone Jump"
        case .research:      "Research"
        }
    }

    /// Label under a summary tile's number.
    var tileTitle: String {
        switch self {
        case .training:      String(localized: "Idle Queues")
        case .manufacturing: String(localized: "Factory Slots Free")
        case .science:       String(localized: "Lab Slots Free")
        case .reactions:     String(localized: "Reaction Slots Free")
        case .market:        String(localized: "Order Slots Free")
        case .planets:       String(localized: "Planets Unused")
        case .extractors:    String(localized: "Extractors Stopped")
        case .cloneJump:     String(localized: "Clone Jump")
        case .research:      String(localized: "Research")
        }
    }

    var systemImage: String {
        switch self {
        case .training:      "graduationcap.fill"
        case .manufacturing: "hammer.fill"
        case .science:       "flask.fill"
        case .reactions:     "atom"
        case .market:        "cart.fill"
        case .planets:       "globe.americas.fill"
        case .extractors:    "arrow.down.circle.fill"
        case .cloneJump:     "person.2.fill"
        case .research:      "book.closed.fill"
        }
    }

    /// The screen that deals with this capacity.
    var destination: NavigationSection {
        switch self {
        case .training:                             .training
        case .manufacturing, .science, .reactions:  .industry
        case .market:                               .finances
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
                        IdleCapacityLineRow(line: line)
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
            if let used = line.used, let limit = line.limit {
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
        switch line.kind {
        case .training:
            switch line.status {
            case .idle: return line.count > 0 ? String(localized: "Queue paused") : String(localized: "Queue empty")
            default:    return line.date.map { String(localized: "Ends in \(EVEFormatters.timeUntil($0))") } ?? ""
            }
        case .manufacturing, .science, .reactions:
            if line.status == .idle {
                let open = max((line.limit ?? 0) - (line.used ?? 0), 0)
                switch (open, line.count) {
                case (_, 0):    return String(localized: "\(open) free")
                case (0, let n): return String(localized: "\(n) ready to deliver")
                case let (o, n): return String(localized: "\(o) free · \(n) to deliver")
                }
            }
            return line.date.map { String(localized: "Frees in \(EVEFormatters.timeUntil($0))") } ?? String(localized: "Full")
        case .market, .planets:
            return line.status == .idle ? String(localized: "\(line.free) free") : String(localized: "All in use")
        case .extractors:
            if line.status == .idle { return String(localized: "\(line.count) stopped") }
            return line.date.map { String(localized: "Next stops in \(EVEFormatters.timeUntil($0))") } ?? ""
        case .cloneJump:
            let clones = String(localized: "\(line.count) jump clones")
            return line.date.map { String(localized: "\(clones) · ready in \(EVEFormatters.timeUntil($0))") }
                ?? String(localized: "\(clones) · ready")
        case .research:
            let points = (line.points ?? 0).formatted(.number.precision(.fractionLength(0)))
            return String(localized: "\(line.count) agents · \(points) RP")
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
