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
import UserNotifications

// MARK:  Exploration Site Codex
//
// A planning aid for Ghost Sites (Covert Research Facilities) and Sleeper
// Caches. ESI has no scan-probe data, so this is a curated catalogue
// (`ExplorationCatalog`) cross-referenced at runtime with live Jita prices,
// the signed-in character's hacking skills / implants, and a response-fleet
// countdown with an optional Discord ping.

struct ExplorationCodexView: View {
    @Environment(AccountManager.self) private var accountManager

    @State private var kind: ExplorationSiteKind = .ghostSite
    @State private var selectedID: String?

    @State private var lootTypeIDs: [String: Int] = [:]
    @State private var lootSeries: [String: MarketHistoryService.Series] = [:]
    @State private var pricesLoading = false
    @State private var pricesFetchedAt: Date?

    @State private var skillProfile = ExplorationSkillProfile()

    // Detail-pane width. Persisted on drag end only (see MarketBrowserView) to
    // avoid 60 Hz UserDefaults writes; the live @State is seeded straight from
    // UserDefaults so the first frame is already the right size.
    @AppStorage("exploration.detailPaneWidth") private var savedDetailWidth: Double = 340
    @State private var detailWidth: CGFloat = {
        let v = UserDefaults.standard.double(forKey: "exploration.detailPaneWidth")
        return CGFloat(v > 0 ? v : 340)
    }()
    private let detailMinWidth: CGFloat = 300
    private let detailMaxWidth: CGFloat = 640

    private var rows: [ExplorationSite] { ExplorationCatalog.sites(for: kind) }
    private var selected: ExplorationSite? {
        ExplorationCatalog.sites.first { $0.id == selectedID }
    }

    var body: some View {
        HStack(spacing: 0) {
            VStack(spacing: 0) {
                Picker("Site family", selection: $kind) {
                    ForEach(ExplorationSiteKind.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                Divider()

                List(rows) { site in
                    Button { selectedID = site.id } label: {
                        ExplorationSiteRow(
                            site: site,
                            readiness: SiteReadiness.evaluate(site: site, profile: skillProfile)
                        )
                    }
                    .buttonStyle(.plain)
                    .listRowBackground(selectedID == site.id ? Color.accentColor.opacity(0.12) : Color.clear)
                }
            }

            if let selected {
                // The resizable pane is on the right, so a rightward drag must
                // *shrink* it — feed SplitDivider the negated width and flip it
                // back in the callbacks. Bounds negate and swap accordingly.
                SplitDivider(direction: .horizontal,
                             value: -detailWidth,
                             minValue: -detailMaxWidth,
                             maxValue: -detailMinWidth,
                             onChange: { detailWidth = -$0 },
                             onEnd: { savedDetailWidth = Double(detailWidth) })

                ExplorationSiteDetailPane(
                    site: selected,
                    signal: marketSignal(for: selected),
                    pricesFetchedAt: pricesFetchedAt,
                    readiness: SiteReadiness.evaluate(site: selected, profile: skillProfile),
                    onClose: { selectedID = nil }
                )
                .frame(width: detailWidth)
                .id(selected.id)
            }
        }
        .safeAreaInset(edge: .top, spacing: 0) { header }
        .navigationTitle("")
        .task {
            await loadPrices()
            await loadSkills()
        }
        .onChange(of: kind) { _, _ in selectedID = nil }
        .onChange(of: accountManager.selectedAccount?.characterID) { _, _ in
            Task { await loadSkills() }
        }
    }

    // MARK: Header

    private var header: some View {
        HStack(spacing: 12) {
            Text("Exploration Codex")
                .font(.largeTitle.bold())
            Spacer()
            RelativeTimestamp(date: pricesFetchedAt, prefix: "Prices")
            RefreshButton(isRefreshing: pricesLoading) {
                Task { await loadPrices(force: true); await loadSkills() }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(.background)
    }

    // MARK: Data

    /// Builds the Tier-2 market read for a site from the cached Jita history.
    private func marketSignal(for site: ExplorationSite) -> SiteMarketSignal {
        let stats = site.loot.map { entry -> LootMarketStat in
            let series = lootSeries[entry.name]
            return LootMarketStat(
                name: entry.name,
                typeID: lootTypeIDs[entry.name],
                isJackpot: entry.isJackpot,
                current: series?.latest?.average,
                median30: series?.median(days: 30)
            )
        }
        return SiteMarketSignal(stats: stats)
    }

    private func loadPrices(force: Bool = false) async {
        if pricesLoading { return }
        if !force, !lootSeries.isEmpty { return }
        pricesLoading = true
        defer { pricesLoading = false }

        let names = ExplorationCatalog.allLootNames

        // Resolve names -> type IDs once.
        if lootTypeIDs.isEmpty || force {
            struct IDResp: Decodable { let inventoryTypes: [ESIIDName]? }
            if let resp: IDResp = try? await ESIClient.shared.post("/universe/ids/", body: names) {
                var map: [String: Int] = [:]
                for entry in resp.inventoryTypes ?? [] {
                    if let match = names.first(where: { $0.caseInsensitiveCompare(entry.name) == .orderedSame }) {
                        map[match] = entry.id
                    }
                }
                lootTypeIDs = map
            }
        }

        // Pull Jita history for each resolved type, concurrently.
        let ids = lootTypeIDs
        let fetched = await withTaskGroup(of: (String, MarketHistoryService.Series?).self) { group in
            for (name, typeID) in ids {
                group.addTask {
                    let series = try? await MarketHistoryService.shared.series(typeId: typeID, forceRefresh: force)
                    return (name, series)
                }
            }
            var out: [String: MarketHistoryService.Series] = [:]
            for await (name, value) in group {
                if let value { out[name] = value }
            }
            return out
        }
        lootSeries = fetched
        pricesFetchedAt = Date()
    }

    private func loadSkills() async {
        guard let account = accountManager.selectedAccount,
              let token = try? await accountManager.validToken(for: account) else {
            skillProfile = ExplorationSkillProfile()
            return
        }
        let charID = account.characterID

        async let skillsResp: ESISkillsResponse? = try? await ESIClient.shared.fetch(
            "/characters/\(charID)/skills/", token: token)
        async let implantIDs: [Int]? = try? await ESIClient.shared.fetch(
            "/characters/\(charID)/implants/", token: token)

        struct IDResp: Decodable { let inventoryTypes: [ESIIDName]? }
        async let skillIDResp: IDResp? = try? await ESIClient.shared.post(
            "/universe/ids/", body: ["Hacking", "Archaeology", "Astrometrics"])

        let (skills, implants, skillIDs) = await (skillsResp, implantIDs, skillIDResp)

        guard let skills else {
            skillProfile = ExplorationSkillProfile()
            return
        }

        let nameToID = Dictionary(
            uniqueKeysWithValues: (skillIDs?.inventoryTypes ?? []).map { ($0.name, $0.id) }
        )
        let levelByID = Dictionary(
            uniqueKeysWithValues: skills.skills.map { ($0.skillId, $0.activeSkillLevel) }
        )
        func level(_ skillName: String) -> Int {
            guard let id = nameToID[skillName] else { return 0 }
            return levelByID[id] ?? 0
        }

        var profile = ExplorationSkillProfile()
        profile.hacking = level("Hacking")
        profile.archaeology = level("Archaeology")
        profile.astrometrics = level("Astrometrics")

        if let implants, !implants.isEmpty {
            let types = await UniverseCache.shared.types(ids: implants)
            profile.relevantImplants = implants
                .compactMap { types[$0]?.name }
                .filter { ExplorationSkillProfile.classifyImplant(name: $0) }
        }
        profile.loaded = true
        skillProfile = profile
    }
}

// MARK:  List Row

private struct ExplorationSiteRow: View {
    let site: ExplorationSite
    let readiness: SiteReadiness

    private var iconName: String { site.isGhostSite ? "timer" : "cpu" }
    private var iconTint: Color { site.isGhostSite ? .orange : .teal }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            RoundedRectangle(cornerRadius: 8)
                .fill(iconTint.opacity(0.15))
                .frame(width: 44, height: 44)
                .overlay(
                    Image(systemName: iconName)
                        .font(.title3)
                        .foregroundStyle(iconTint)
                )

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text(site.name)
                        .font(.subheadline.bold())
                        .lineLimit(1)
                    Spacer(minLength: 0)
                    ReadinessBadge(verdict: readiness.verdict)
                }
                Text(site.space)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                HStack(spacing: 6) {
                    Label(site.hackingDifficulty.label, systemImage: "lock.shield")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                    if let blast = site.blastDamage {
                        Label("\(blast.formatted()) blast", systemImage: "burst")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                }
            }

            Spacer(minLength: 0)
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
    }
}

private struct ReadinessBadge: View {
    let verdict: ReadinessVerdict

    private var color: Color {
        switch verdict {
        case .ready: return .green
        case .marginal: return .yellow
        case .underSkilled: return .red
        case .unknown: return .secondary
        }
    }

    var body: some View {
        Text(verdict.label)
            .font(.system(size: 9).bold())
            .foregroundStyle(color)
            .padding(.horizontal, 6).padding(.vertical, 2)
            .background(color.opacity(0.15), in: Capsule())
    }
}

// MARK:  Detail Pane

private struct ExplorationSiteDetailPane: View {
    let site: ExplorationSite
    let signal: SiteMarketSignal
    let pricesFetchedAt: Date?
    let readiness: SiteReadiness
    var onClose: () -> Void = {}

    /// name -> current Jita average, for the haul logger.
    private var unitPrices: [String: Double] {
        Dictionary(uniqueKeysWithValues: signal.stats.compactMap { s in
            s.current.map { (s.name, $0) }
        })
    }
    private var statByName: [String: LootMarketStat] {
        Dictionary(uniqueKeysWithValues: signal.stats.map { ($0.name, $0) })
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Text(site.name).font(.headline).lineLimit(2)
                Spacer()
                Button { onClose() } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .keyboardShortcut(.escape)
            }
            .padding(.horizontal, 14).padding(.vertical, 10)
            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    metaBox

                    Text(site.summary)
                        .font(.callout)
                        .fixedSize(horizontal: false, vertical: true)

                    section("MECHANICS") {
                        ForEach(site.mechanics, id: \.self) { bullet($0) }
                    }

                    section("HAZARDS") {
                        ForEach(site.hazards) { HazardRow(hazard: $0) }
                    }

                    section("HACKING") {
                        HStack(spacing: 6) {
                            Text(site.hackingDifficulty.label)
                                .font(.caption.bold())
                                .padding(.horizontal, 6).padding(.vertical, 2)
                                .background(.quaternary, in: Capsule())
                            Text(site.hackingDifficulty.blurb)
                                .font(.caption).foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        ReadinessPanel(readiness: readiness)
                    }

                    if site.isGhostSite {
                        section("RESPONSE TIMER") {
                            GhostSiteTimer(site: site)
                        }
                        section("BLAST SURVIVABILITY") {
                            BlastCheck(site: site)
                        }
                    }

                    section("LOOT & VALUE") {
                        ForEach(site.loot) { entry in
                            LootRow(entry: entry, stat: statByName[entry.name])
                        }
                        LootFooter(signal: signal)
                    }

                    section("MARKET SIGNAL") {
                        MarketSignalView(signal: signal, fetchedAt: pricesFetchedAt)
                    }

                    section("RUN LEDGER") {
                        RunLedgerView(site: site, unitPrices: unitPrices)
                    }

                    section("SCOUTING") {
                        ScoutingView(site: site)
                    }

                    linksRow

                    Text("Timers, blast figures and loot tables are community estimates and shift with balance passes — verify in-game before you commit a ship.")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .frame(maxHeight: .infinity)
        .background(.regularMaterial)
    }

    private var metaBox: some View {
        VStack(alignment: .leading, spacing: 6) {
            metaRow("Space", site.space)
            metaRow("Recommended", site.recommendedShips)
            VStack(alignment: .leading, spacing: 2) {
                Text("DEFENSES").font(.caption2.bold()).foregroundStyle(.tertiary)
                Text(site.rats).font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 10))
    }

    private var linksRow: some View {
        HStack(spacing: 8) {
            let wiki = site.isGhostSite
                ? "https://wiki.eveuniversity.org/Ghost_Sites"
                : "https://wiki.eveuniversity.org/Sleeper_Cache"
            if let url = URL(string: wiki) {
                Link(destination: url) {
                    Label("EVE University wiki", systemImage: "arrow.up.right.square").font(.caption)
                }
                .buttonStyle(.bordered).controlSize(.small)
            }
        }
    }

    @ViewBuilder
    private func section<Content: View>(_ title: String, @ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.caption2.bold()).foregroundStyle(.tertiary)
            content()
        }
    }

    private func bullet(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 6) {
            Text("•").foregroundStyle(.secondary)
            Text(text).font(.caption).fixedSize(horizontal: false, vertical: true)
        }
    }

    private func metaRow(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label.uppercased()).font(.caption2.bold()).foregroundStyle(.tertiary)
            Text(value).font(.caption).fixedSize(horizontal: false, vertical: true)
        }
    }
}

// MARK:  Hazard Row

private struct HazardRow: View {
    let hazard: SiteHazard

    private var color: Color {
        switch hazard.severity {
        case .info: return .secondary
        case .caution: return .yellow
        case .severe: return .orange
        case .lethal: return .red
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 6) {
                Text(hazard.severity.label)
                    .font(.system(size: 9).bold())
                    .foregroundStyle(color)
                    .padding(.horizontal, 5).padding(.vertical, 1)
                    .background(color.opacity(0.15), in: Capsule())
                Text(hazard.name).font(.caption.bold())
            }
            Text(hazard.detail).font(.caption2).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK:  Readiness Panel

private struct ReadinessPanel: View {
    let readiness: SiteReadiness

    private var color: Color {
        switch readiness.verdict {
        case .ready: return .green
        case .marginal: return .yellow
        case .underSkilled: return .red
        case .unknown: return .secondary
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: readiness.verdict == .ready ? "checkmark.seal.fill" : "exclamationmark.triangle.fill")
                    .foregroundStyle(color)
                Text(readiness.verdict.label).font(.caption.bold()).foregroundStyle(color)
                Spacer()
                if readiness.verdict != .unknown {
                    Text("\(readiness.coreSkillName) \(romanNumeral(readiness.coreSkillLevel)) / \(romanNumeral(readiness.recommendedLevel))")
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }
            ForEach(readiness.notes, id: \.self) { note in
                HStack(alignment: .top, spacing: 6) {
                    Text("›").foregroundStyle(.tertiary)
                    Text(note).font(.caption2).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(color.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
    }
}

// MARK:  Blast Survivability Check

private struct BlastCheck: View {
    let site: ExplorationSite

    @AppStorage("explorationShipEHP") private var shipEHP: Double = 0

    private var survivability: BlastSurvivability {
        BlastSurvivability.evaluate(ehp: shipEHP > 0 ? shipEHP : nil, blast: site.blastDamage)
    }

    private var color: Color {
        switch survivability {
        case .safe: return .green
        case .risky: return .yellow
        case .lethal: return .red
        case .unknown: return .secondary
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let blast = site.blastDamage {
                Text("A failed hack detonates the container for ≈ \(blast.formatted()) omni damage.")
                    .font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack(spacing: 8) {
                Text("Your worst-case EHP")
                    .font(.caption)
                TextField("EHP", value: $shipEHP, format: .number)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 90)
                    .multilineTextAlignment(.trailing)
                Text(survivability.label)
                    .font(.caption.bold())
                    .foregroundStyle(color)
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(color.opacity(0.15), in: Capsule())
            }
            Text("Use the minimum-resist EHP from the Fitting Simulator's Defense panel. 'Survivable' means at least double the blast — headroom for rat fire while you warp.")
                .font(.caption2).foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(color.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
    }
}

// MARK:  Ghost Site Response Timer

private struct GhostSiteTimer: View {
    let site: ExplorationSite

    @AppStorage("explorationTimerPingDiscord") private var pingDiscord = false

    @State private var deadline: Date?
    @State private var now = Date()
    @State private var firedResponse = false
    @State private var firedWarning = false

    private var window: ClosedRange<Int> { site.responseWindow ?? 60...120 }

    private var remaining: TimeInterval? {
        guard let deadline else { return nil }
        return deadline.timeIntervalSince(now)
    }

    private var color: Color {
        guard let r = remaining else { return .secondary }
        if r <= 0 { return .red }
        if r <= 30 { return .red }
        if r <= 60 { return .yellow }
        return .green
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                if let r = remaining {
                    Text(r <= 0 ? "RESPONSE FLEET INBOUND" : timeString(r))
                        .font(.system(.title2, design: .rounded).bold().monospacedDigit())
                        .foregroundStyle(color)
                } else {
                    Text("Not started")
                        .font(.title3.bold())
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button(deadline == nil ? "Start" : "Reset") { start() }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                if deadline != nil {
                    Button("Stop") { deadline = nil }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                }
            }

            Text("Counts down \(window.lowerBound)s — the short end of the observed response window. Hit Start the moment you land. Treat 0:30 as your hard bail-out.")
                .font(.caption2).foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)

            Toggle(isOn: $pingDiscord) {
                Text("Also ping Discord at the warning and at zero")
                    .font(.caption2)
            }
            .toggleStyle(.checkbox)
            .help("Requires a Discord webhook configured in Settings.")
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(color.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
        .periodicTick(every: 1) {
            now = Date()
            evaluateAlerts()
        }
    }

    private func start() {
        deadline = Date().addingTimeInterval(TimeInterval(window.lowerBound))
        now = Date()
        firedResponse = false
        firedWarning = false
    }

    private func timeString(_ interval: TimeInterval) -> String {
        let total = Int(interval.rounded())
        return String(format: "%d:%02d", total / 60, total % 60)
    }

    private func evaluateAlerts() {
        guard let r = remaining else { return }
        if r <= 30, !firedWarning {
            firedWarning = true
            notify(
                title: "Ghost site — 30 seconds",
                body: "\(site.name): response fleet almost here. Finish this hack or warp."
            )
        }
        if r <= 0, !firedResponse {
            firedResponse = true
            notify(
                title: "Ghost site — response fleet inbound",
                body: "\(site.name): the containers are self-destructing. Get out now."
            )
        }
    }

    private func notify(title: String, body: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        let request = UNNotificationRequest(
            identifier: "exploration.ghosttimer.\(site.id).\(UUID().uuidString)",
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(request)
        if pingDiscord {
            Task { await DiscordNotifier.shared.enqueue(title: title, body: body) }
        }
    }
}

// MARK:  Loot Rows

private struct LootRow: View {
    let entry: SiteLootEntry
    let stat: LootMarketStat?

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            CachedAsyncImage(url: stat?.typeID.flatMap { EVEImageURL.typeIcon($0, size: 64) }) { image in
                image.resizable().scaledToFit()
            } placeholder: {
                RoundedRectangle(cornerRadius: 6).fill(.quaternary)
            }
            .frame(width: 32, height: 32)
            .clipShape(RoundedRectangle(cornerRadius: 6))

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 5) {
                    Text(entry.name).font(.caption.bold())
                    if entry.isJackpot {
                        Image(systemName: "star.fill").font(.system(size: 8)).foregroundStyle(.yellow)
                    }
                }
                Text(entry.note).font(.caption2).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)

            VStack(alignment: .trailing, spacing: 2) {
                Text(priceText)
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(stat?.current == nil ? .tertiary : .primary)
                if let delta = stat?.deltaPct {
                    DeltaBadge(deltaPct: delta)
                }
            }
        }
    }

    private var priceText: String {
        guard let price = stat?.current else { return "—" }
        return "\(ISKFormat.compact(price)) /u"
    }
}

private struct LootFooter: View {
    let signal: SiteMarketSignal

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if signal.consumableFloor > 0 {
                HStack {
                    Text("Indicative consumable value").font(.caption2).foregroundStyle(.secondary)
                    Spacer()
                    Text(ISKFormat.compact(signal.consumableFloor)).font(.caption2.monospacedDigit().bold())
                }
            }
            Text("Unit prices are Jita daily averages. Loot is probabilistic — starred items are the jackpot rolls and are not summed. A full site is worth far more than the floor when it drops well.")
                .font(.caption2).foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.top, 2)
    }
}

// MARK:  Market Signal (Tier 2 #4)

private struct DeltaBadge: View {
    let deltaPct: Double

    private var color: Color {
        switch deltaPct {
        case 8...: return .green
        case ..<(-8): return .orange
        default: return .secondary
        }
    }
    private var arrow: String {
        deltaPct >= 1 ? "arrow.up" : (deltaPct <= -1 ? "arrow.down" : "minus")
    }

    var body: some View {
        HStack(spacing: 2) {
            Image(systemName: arrow).font(.system(size: 7).bold())
            Text("\(abs(deltaPct), format: .number.precision(.fractionLength(0)))%")
                .font(.system(size: 9).monospacedDigit().bold())
        }
        .foregroundStyle(color)
        .padding(.horizontal, 4).padding(.vertical, 1)
        .background(color.opacity(0.15), in: Capsule())
        .help("Current Jita average vs its 30-day median")
    }
}

private struct MarketSignalView: View {
    let signal: SiteMarketSignal
    var fetchedAt: Date?

    private var color: Color {
        switch signal.aggregateSignal {
        case .spiking, .elevated: return .green
        case .soft: return .orange
        case .normal: return .secondary
        case .unknown: return .secondary
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: "chart.line.uptrend.xyaxis").foregroundStyle(color)
                Text(signal.aggregateSignal.label).font(.caption.bold()).foregroundStyle(color)
                Spacer()
                RelativeTimestamp(date: fetchedAt, prefix: "Jita")
                if let d = signal.aggregateDeltaPct {
                    DeltaBadge(deltaPct: d)
                }
            }

            Text(aggregateSentence)
                .font(.caption2).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if !pricedStats.isEmpty {
                VStack(spacing: 4) {
                    ForEach(pricedStats) { LootSignalRow(stat: $0) }
                }
            }

            if let typeID = signal.featuredJackpotTypeID {
                MarketMiniHistory(typeId: typeID, regionLabel: "Jita")
                    .padding(.top, 2)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(color.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
    }

    private var pricedStats: [LootMarketStat] {
        signal.stats.filter { $0.deltaPct != nil }
    }

    private var aggregateSentence: String {
        switch signal.aggregateSignal {
        case .unknown:
            return "No recent Jita history for this site's loot yet — refresh once prices load."
        default:
            let pct = signal.aggregateDeltaPct.map { String(format: "%.0f%%", abs($0)) } ?? ""
            let dir = (signal.aggregateDeltaPct ?? 0) >= 0 ? "up \(pct)" : "down \(pct)"
            return "This site's drops are \(dir) against their 30-day norm on average — \(signal.aggregateSignal.advice)."
        }
    }
}

private struct LootSignalRow: View {
    let stat: LootMarketStat

    var body: some View {
        HStack(spacing: 8) {
            Text(stat.name)
                .font(.caption2)
                .lineLimit(1)
            if stat.isJackpot {
                Image(systemName: "star.fill").font(.system(size: 7)).foregroundStyle(.yellow)
            }
            Spacer(minLength: 0)
            if let current = stat.current {
                Text(ISKFormat.compact(current))
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            if let d = stat.deltaPct {
                DeltaBadge(deltaPct: d)
            }
        }
    }
}

// MARK:  Run Ledger (Tier 2 #6)

private struct RunLedgerView: View {
    let site: ExplorationSite
    let unitPrices: [String: Double]

    @State private var runs: [ExplorationRun] = []
    @State private var showingLogger = false

    private var summary: RunLedgerSummary { ExplorationRunStore.summary(forSite: site.id) }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if summary.count == 0 {
                Text("No runs logged for this site yet. Log a haul after you run one to start tracking ISK per run and ISK per hour.")
                    .font(.caption2).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                HStack(spacing: 14) {
                    stat("Runs", "\(summary.count)")
                    stat("Total", ISKFormat.compact(summary.total))
                    stat("Best", ISKFormat.compact(summary.best))
                    if let perHour = summary.avgPerHour {
                        stat("ISK/hr", ISKFormat.compact(perHour))
                    }
                }

                VStack(spacing: 3) {
                    ForEach(runs.prefix(6)) { run in
                        HStack(spacing: 8) {
                            Text(run.date, format: .dateTime.month(.abbreviated).day().hour().minute())
                                .font(.caption2).foregroundStyle(.secondary)
                            Spacer()
                            if let m = run.minutes {
                                Text("\(m)m").font(.caption2).foregroundStyle(.tertiary)
                            }
                            Text(ISKFormat.compact(run.iskValue))
                                .font(.caption2.monospacedDigit())
                            Button {
                                ExplorationRunStore.remove(id: run.id)
                            } label: {
                                Image(systemName: "trash").font(.system(size: 9))
                            }
                            .buttonStyle(.plain)
                            .foregroundStyle(.tertiary)
                        }
                    }
                }
            }

            Button {
                showingLogger = true
            } label: {
                Label("Log a run", systemImage: "plus.circle")
                    .font(.caption)
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary.opacity(0.3), in: RoundedRectangle(cornerRadius: 8))
        .onAppear(perform: reload)
        .onReceive(NotificationCenter.default.publisher(for: ExplorationRunStore.didChange)) { _ in reload() }
        .sheet(isPresented: $showingLogger) {
            HaulLogSheet(site: site, unitPrices: unitPrices) { run in
                ExplorationRunStore.add(run)
            }
        }
    }

    private func reload() { runs = ExplorationRunStore.runs(forSite: site.id) }

    private func stat(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(label.uppercased()).font(.system(size: 8).bold()).foregroundStyle(.tertiary)
            Text(value).font(.caption.monospacedDigit().bold())
        }
    }
}

private struct HaulLogSheet: View {
    let site: ExplorationSite
    let unitPrices: [String: Double]
    var onSave: (ExplorationRun) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var quantities: [String: Int] = [:]
    @State private var minutesText = ""

    private var total: Double {
        site.loot.reduce(0) { sum, entry in
            let qty = quantities[entry.name] ?? 0
            let price = unitPrices[entry.name] ?? 0
            return sum + Double(qty) * price
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Log a \(site.name) run")
                .font(.headline)

            ScrollView {
                VStack(spacing: 6) {
                    ForEach(site.loot) { entry in
                        HStack(spacing: 8) {
                            VStack(alignment: .leading, spacing: 1) {
                                Text(entry.name).font(.caption)
                                if let p = unitPrices[entry.name] {
                                    Text("\(ISKFormat.compact(p)) /u").font(.caption2).foregroundStyle(.tertiary)
                                } else {
                                    Text("unpriced").font(.caption2).foregroundStyle(.tertiary)
                                }
                            }
                            Spacer()
                            Stepper(
                                value: Binding(
                                    get: { quantities[entry.name] ?? 0 },
                                    set: { quantities[entry.name] = max(0, $0) }
                                ),
                                in: 0...9999
                            ) {
                                Text("\(quantities[entry.name] ?? 0)")
                                    .font(.caption.monospacedDigit())
                                    .frame(width: 34, alignment: .trailing)
                            }
                            .labelsHidden()
                        }
                    }
                }
                .padding(.vertical, 2)
            }
            .frame(maxHeight: 240)

            HStack(spacing: 8) {
                Text("Duration").font(.caption).foregroundStyle(.secondary)
                TextField("minutes", text: $minutesText)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 70)
                Spacer()
                Text("Haul value").font(.caption).foregroundStyle(.secondary)
                Text(ISKFormat.compact(total)).font(.callout.monospacedDigit().bold())
            }

            HStack {
                Button("Cancel") { dismiss() }
                Spacer()
                Button("Save run") {
                    let minutes = Int(minutesText.trimmingCharacters(in: .whitespaces))
                    onSave(ExplorationRun(siteID: site.id, date: Date(), iskValue: total, minutes: minutes))
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .disabled(total <= 0)
            }
        }
        .padding(16)
        .frame(width: 380)
    }
}

// MARK:  Scouting (Tier 2 #5)

private struct ScoutingView: View {
    let site: ExplorationSite

    @Environment(AccountManager.self) private var accountManager
    @State private var systemName: String?
    @State private var danger: SystemDanger?
    @State private var checked = false

    private var level: DangerLevel? { danger.map { DangerLevel(combatKills: $0.combatKills) } }
    private var color: Color {
        switch level {
        case .quiet: return .green
        case .elevated: return .yellow
        case .high: return .orange
        case .extreme: return .red
        case nil: return .secondary
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("These are scannable signatures in \(site.space.lowercased()). Pick a quiet pocket — the Galaxy Map's Kills mode and the Route Planner's ‘route around recent kills’ toggle shade systems by ship and pod kills in the last hour.")
                .font(.caption2).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if checked, let systemName {
                HStack(spacing: 6) {
                    Circle().fill(color).frame(width: 8, height: 8)
                    Text("You are in \(systemName)").font(.caption)
                    Spacer()
                    if let danger, let level {
                        Text("\(level.label) · \(danger.combatKills) kills/h")
                            .font(.caption2.monospacedDigit())
                            .foregroundStyle(color)
                    }
                }
            } else if checked {
                Text("Sign in with a character to see live activity where you are.")
                    .font(.caption2).foregroundStyle(.tertiary)
            }

            Button {
                AppRouter.shared.pendingSection = .galaxyMap
            } label: {
                Label("Open Galaxy Map", systemImage: "globe").font(.caption)
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(color.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
        .task { await checkLocation() }
    }

    private func checkLocation() async {
        defer { checked = true }
        guard let account = accountManager.selectedAccount,
              let token = try? await accountManager.validToken(for: account) else { return }
        struct Loc: Decodable { let solarSystemId: Int }
        guard let loc: Loc = try? await ESIClient.shared.fetch(
            "/characters/\(account.characterID)/location/", token: token) else { return }
        systemName = await UniverseCache.shared.solarSystem(id: loc.solarSystemId)?.name
        danger = try? await SystemDangerService.shared.snapshot().danger(for: loc.solarSystemId)
    }
}

// MARK:  ISK formatting

private enum ISKFormat {
    static func compact(_ value: Double) -> String {
        switch value {
        case 1_000_000_000...:
            return String(format: "%.2fB", value / 1_000_000_000)
        case 1_000_000...:
            return String(format: "%.1fM", value / 1_000_000)
        case 1_000...:
            return String(format: "%.0fk", value / 1_000)
        default:
            return String(format: "%.0f", value)
        }
    }
}
