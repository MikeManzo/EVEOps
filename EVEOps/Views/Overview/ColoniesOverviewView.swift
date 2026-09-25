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

struct ColoniesOverviewView: View {
    @Environment(AccountManager.self) private var accountManager
    @Environment(DashboardPrefetcher.self) private var prefetcher
    @AppStorage("backgroundPollInterval") private var pollInterval: Double = 300
    @State private var colonies: [CharacterColonyGroup] = []
    @State private var isLoading = false
    @State private var isRefreshing = false
    @State private var lastRefresh: Date?
    @State private var error: String?
    @State private var selectedEntry: ColonyDetailEntry?
    /// Real extractor state per planet, from each colony's layout.
    @State private var extractors: [Int: ExtractorStatus] = [:]
    @Environment(ThemeManager.self) private var themeManager

    var body: some View {
        LoadingStateView(
            isLoading: isLoading,
            error: error,
            isEmpty: colonies.isEmpty,
            hasContent: !colonies.isEmpty,
            emptyMessage: "No Planetary Colonies",
            emptySystemImage: "globe",
            onRetry: { Task { await refresh() } }
        ) {
            ScrollView {
                VStack(alignment: .leading, spacing: EVESpacing.xl) {
                    summaryStrip
                    ForEach(colonies, id: \.characterName) { group in
                        VStack(alignment: .leading, spacing: EVESpacing.md) {
                            if colonies.count > 1 {
                                EVESectionTitle(verbatim: group.characterName)
                            }
                            LazyVGrid(columns: [GridItem(.adaptive(minimum: 280), spacing: EVESpacing.md)],
                                      spacing: EVESpacing.md) {
                                ForEach(sortedByUrgency(group.colonies), id: \.planetId) { colony in
                                    Button {
                                        selectedEntry = ColonyDetailEntry(characterID: group.characterID, colony: colony)
                                    } label: {
                                        ColonyCard(colony: colony, status: extractors[colony.planetId],
                                                   accent: themeManager.palette.colonies)
                                    }
                                    .buttonStyle(.plain)
                                    .eveHoverable()
                                }
                            }
                        }
                    }
                }
                .padding()
            }
        }
        .task(id: colonies.flatMap(\.colonies).map(\.planetId)) { await loadExtractorStatus() }
        .eveScreenHeader("Colonies Overview", section: .colonies) {
            RelativeTimestamp(date: lastRefresh)
            RefreshButton(isRefreshing: isRefreshing) {
                Task { await refresh() }
            }
        }
        .sheet(item: $selectedEntry) { entry in
            ColonyDetailView(characterID: entry.characterID, colony: entry.colony)
        }
        .task {
            if buildFromPrefetcher() { return }
            isLoading = true
            await loadColonies()
        }
        .autoRefresh(every: pollInterval) { await refresh() }
        .onChange(of: AppRouter.shared.refreshTick) { _, _ in
            Task { await refresh() }
        }
    }

    // MARK: Extractors

    private var summaryStrip: some View {
        let all = colonies.flatMap(\.colonies)
        let statuses = all.compactMap { extractors[$0.planetId] }
        let running = statuses.filter { $0.state(at: .now) == .running }.count
        let soon = statuses.filter { $0.state(at: .now) == .expiringSoon }.count
        let expired = statuses.filter { $0.state(at: .now) == .expired }.count
        return HStack(spacing: EVESpacing.md) {
            MetricTileView(icon: "globe.americas.fill", color: themeManager.palette.colonies,
                           value: "\(all.count)", label: String(localized: "Colonies"))
            MetricTileView(icon: "arrow.down.circle.fill", color: .green,
                           value: "\(running)", label: String(localized: "Extracting"))
            MetricTileView(icon: "clock.badge.exclamationmark", color: soon > 0 ? .orange : .secondary,
                           value: "\(soon)", label: String(localized: "Expire < 24h"), isAlert: soon > 0)
            MetricTileView(icon: "exclamationmark.triangle.fill", color: expired > 0 ? .red : .secondary,
                           value: "\(expired)", label: String(localized: "Restart Needed"), isAlert: expired > 0)
        }
    }

    /// Planets needing attention first: expired, then soonest to expire, then the rest.
    private func sortedByUrgency(_ list: [ResolvedColony]) -> [ResolvedColony] {
        list.sorted { a, b in
            let ea = extractors[a.planetId]?.expiry ?? .distantFuture
            let eb = extractors[b.planetId]?.expiry ?? .distantFuture
            return ea < eb
        }
    }

    /// Fetches every colony's layout in parallel and reduces its extractor pins to one
    /// status per planet (the earliest expiry is the one that matters).
    private func loadExtractorStatus() async {
        var tokens: [Int: String] = [:]
        for account in accountManager.accounts {
            tokens[account.characterID] = try? await accountManager.validToken(for: account)
        }
        let requests = colonies.flatMap { group in group.colonies.map { (group.characterID, $0.planetId) } }
        let results = await withTaskGroup(of: (Int, ExtractorStatus?).self) { taskGroup in
            for (characterID, planetID) in requests {
                guard let token = tokens[characterID] else { continue }
                taskGroup.addTask {
                    let layout: ESIColonyLayout? = try? await ESIClient.shared.fetch(
                        "/characters/\(characterID)/planets/\(planetID)/", token: token
                    )
                    return (planetID, layout.flatMap(ExtractorStatus.init(layout:)))
                }
            }
            var out: [Int: ExtractorStatus] = [:]
            for await (planetID, status) in taskGroup {
                if let status { out[planetID] = status }
            }
            return out
        }
        extractors = results
    }

    private func refresh() async {
        isRefreshing = true
        defer { isRefreshing = false }
        await loadColonies()
    }

    private func buildFromPrefetcher() -> Bool {
        var groups: [CharacterColonyGroup] = []
        for account in accountManager.accounts {
            guard let prefetched = prefetcher.data(for: account.characterID) else { return false }
            var resolved: [ResolvedColony] = []
            for colony in prefetched.colonies {
                let systemName = prefetcher.resolvedNames[colony.solarSystemId]
                    ?? prefetcher.resolvedSystems[colony.solarSystemId]?.name
                    ?? "System #\(colony.solarSystemId)"
                resolved.append(ResolvedColony(
                    planetId: colony.planetId,
                    planetType: colony.planetType,
                    systemName: systemName,
                    numPins: colony.numPins,
                    upgradeLevel: colony.upgradeLevel,
                    lastUpdate: colony.lastUpdate
                ))
            }
            if !resolved.isEmpty {
                groups.append(CharacterColonyGroup(
                    characterID: account.characterID,
                    characterName: account.characterName,
                    colonies: resolved
                ))
            }
        }
        colonies = groups
        return true
    }

    private func loadColonies() async {
        if colonies.isEmpty { isLoading = true }
        error = nil
        var groups: [CharacterColonyGroup] = []
        var lastError: Error?
        for account in accountManager.accounts {
            do {
                let token = try await accountManager.validToken(for: account)
                let rawColonies: [ESIColony] = try await ESIClient.shared.fetch(
                    "/characters/\(account.characterID)/planets/", token: token
                )

                var resolved: [ResolvedColony] = []
                for colony in rawColonies {
                    let systemName = await NameResolver.shared.resolve(id: colony.solarSystemId)
                    resolved.append(ResolvedColony(
                        planetId: colony.planetId,
                        planetType: colony.planetType,
                        systemName: systemName,
                        numPins: colony.numPins,
                        upgradeLevel: colony.upgradeLevel,
                        lastUpdate: colony.lastUpdate
                    ))
                }

                if !resolved.isEmpty {
                    groups.append(CharacterColonyGroup(
                        characterID: account.characterID,
                        characterName: account.characterName,
                        colonies: resolved
                    ))
                }
            } catch {
                lastError = error
            }
        }
        colonies = groups
        if groups.isEmpty, let lastError {
            self.error = lastError.localizedDescription
        }
        lastRefresh = Date()
        isLoading = false
    }
}

struct ColonyDetailEntry: Identifiable {
    let characterID: Int
    let colony: ResolvedColony
    var id: Int { colony.planetId }
}

struct CharacterColonyGroup {
    let characterID: Int
    let characterName: String
    let colonies: [ResolvedColony]
}

struct ResolvedColony {
    let planetId: Int
    let planetType: String
    let systemName: String
    let numPins: Int
    let upgradeLevel: Int
    let lastUpdate: Date

    var isStale: Bool {
        Date().timeIntervalSince(lastUpdate) > 86400
    }
}

/// A planet's extraction state, reduced from its layout's extractor pins.
nonisolated struct ExtractorStatus: Sendable {
    let count: Int
    /// Earliest extractor expiry on the planet.
    let expiry: Date
    /// When that extractor's current program was installed (for the progress ring).
    let installed: Date?

    enum State { case running, expiringSoon, expired }

    init?(layout: ESIColonyLayout) {
        let pins = layout.pins.filter { $0.extractorDetails != nil }
        guard let soonest = pins.compactMap({ pin in pin.expiryTime.map { (pin, $0) } }).min(by: { $0.1 < $1.1 }) else {
            return nil
        }
        count = pins.count
        expiry = soonest.1
        installed = soonest.0.installTime
    }

    func state(at now: Date) -> State {
        if expiry <= now { return .expired }
        return expiry.timeIntervalSince(now) < 24 * 3600 ? .expiringSoon : .running
    }

    /// Fraction of the extraction program still to run (1 → just installed, 0 → expired).
    func remaining(at now: Date) -> Double {
        guard let installed, expiry > installed else { return expiry > now ? 1 : 0 }
        return min(max(expiry.timeIntervalSince(now) / expiry.timeIntervalSince(installed), 0), 1)
    }
}

/// A colony as a card: planet, pins/level, and a countdown ring for its extractors — or a
/// red "Restart needed" once they've expired, since that's the moment PI needs attention.
struct ColonyCard: View {
    let colony: ResolvedColony
    let status: ExtractorStatus?
    let accent: Color

    var body: some View {
        TimelineView(.periodic(from: .now, by: 60)) { context in
            let now = context.date
            HStack(spacing: EVESpacing.lg) {
                ring(now: now)
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: EVESpacing.sm) {
                        Circle().fill(planetColor).frame(width: 9, height: 9)
                        Text(colony.planetType.capitalized)
                            .font(.subheadline.weight(.semibold))
                    }
                    Text(colony.systemName)
                        .font(.callout)
                        .lineLimit(1)
                        .eveTruncationHelp(colony.systemName)
                    Text("\(colony.numPins) pins · Level \(colony.upgradeLevel)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    statusLine(now: now)
                }
                Spacer(minLength: 0)
            }
            .padding(EVESpacing.lg)
            .frame(maxWidth: .infinity, alignment: .leading)
            .eveCard()
            .overlay {
                if status?.state(at: now) == .expired {
                    RoundedRectangle(cornerRadius: EVERadius.xl).strokeBorder(.red.opacity(0.6), lineWidth: 1.5)
                }
            }
        }
        .contentShape(Rectangle())
    }

    private func ring(now: Date) -> some View {
        let state = status?.state(at: now)
        let color: Color = switch state {
        case .expired: .red
        case .expiringSoon: .orange
        case .running: accent
        case nil: .secondary
        }
        return ZStack {
            Circle().stroke(Color.primary.opacity(0.08), lineWidth: 5)
            if let status {
                Circle()
                    .trim(from: 0, to: status.remaining(at: now))
                    .stroke(color, style: StrokeStyle(lineWidth: 5, lineCap: .round))
                    .rotationEffect(.degrees(-90))
            }
            Image(systemName: state == .expired ? "exclamationmark" : "arrow.down")
                .font(.caption.weight(.bold))
                .foregroundStyle(status == nil ? Color.secondary : color)
        }
        .frame(width: 42, height: 42)
        .accessibilityHidden(true)
    }

    @ViewBuilder
    private func statusLine(now: Date) -> some View {
        if let status {
            switch status.state(at: now) {
            case .expired:
                Label("Restart needed", systemImage: "exclamationmark.triangle.fill")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.red)
            case .expiringSoon, .running:
                Text("\(status.count) extractor\(status.count == 1 ? "" : "s") · \(EVEFormatters.timeUntil(status.expiry)) left")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(status.state(at: now) == .expiringSoon ? AnyShapeStyle(.orange) : AnyShapeStyle(.secondary))
                    .help("Expires \(EVEDates.full(status.expiry))")
            }
        } else {
            Text("No extractors")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
    }

    private var planetColor: Color {
        switch colony.planetType.lowercased() {
        case "temperate": return .green
        case "barren": return .brown
        case "oceanic": return .blue
        case "ice": return .cyan
        case "gas": return .orange
        case "lava": return .red
        case "storm": return .purple
        case "plasma": return .pink
        default: return .gray
        }
    }
}
