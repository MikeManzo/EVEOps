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

// MARK:  Agent Type Filter

enum AgentTypeFilter: String, CaseIterable, Identifiable {
    case career      = "Career"
    case basic       = "Basic Mission"
    case research    = "R&D Research"
    case storyline   = "Storyline"
    case factWarfare = "Faction Warfare"
    case epicArc     = "Epic Arc"
    case locator     = "Locator"

    var id: String { rawValue }

    var agentTypeID: Int? {
        switch self {
        case .career:      return 12
        case .basic:       return 2
        case .research:    return 4
        case .storyline:   return 7
        case .factWarfare: return 9
        case .epicArc:     return 10
        case .locator:     return nil
        }
    }

    var isLocatorMode: Bool { self == .locator }

    var iconName: String {
        switch self {
        case .career:      return "graduationcap.fill"
        case .basic:       return "shield.fill"
        case .research:    return "atom"
        case .storyline:   return "book.fill"
        case .factWarfare: return "flag.fill"
        case .epicArc:     return "sparkles"
        case .locator:     return "magnifyingglass.circle.fill"
        }
    }

    var color: Color {
        switch self {
        case .career:      return .cyan
        case .basic:       return .blue
        case .research:    return .purple
        case .storyline:   return .orange
        case .factWarfare: return .red
        case .epicArc:     return .yellow
        case .locator:     return .green
        }
    }
}

// MARK:  Security Range Filter

enum SecurityRangeFilter: String, CaseIterable, Identifiable {
    case any  = "Any"
    case high = "High Sec"
    case low  = "Low Sec"
    case null = "Null Sec"

    var id: String { rawValue }

    var title: LocalizedStringKey {
        switch self {
        case .any:  "Any"
        case .high: "High Sec"
        case .low:  "Low Sec"
        case .null: "Null Sec"
        }
    }

    func matches(_ status: Double?) -> Bool {
        guard let s = status else { return self == .any }
        switch self {
        case .any:  return true
        case .high: return s >= 0.5
        case .low:  return s >= 0.1 && s < 0.5
        case .null: return s < 0.1
        }
    }
}

// MARK:  Agent Sort Order

enum AgentSortOrder: String, CaseIterable, Identifiable {
    case jumps = "Jumps"
    case level = "Level"
    var id: String { rawValue }
    var title: LocalizedStringKey {
        switch self {
        case .jumps: "Jumps"
        case .level: "Level"
        }
    }
}

// MARK:  Resolved Agent

struct ResolvedAgent: Identifiable {
    let agent: AgentDataManager.SDEAgent
    var name: String?
    var corpName: String?
    var systemID: Int?
    var systemName: String?
    var securityStatus: Double?
    var jumpCount: Int?
    var constellationName: String?
    var regionName: String?
    var id: Int { agent.agentID }

    var displayName: String   { name     ?? "Agent \(agent.agentID)" }
    var displayCorp: String   { corpName ?? "Corp \(agent.corporationID)" }
    var displaySystem: String { systemName ?? "Station \(agent.locationID)" }
}

// MARK:  Agent Finder View

struct AgentFinderView: View {
    @Environment(AccountManager.self) private var accountManager

    // Filters
    @State private var typeFilter: AgentTypeFilter    = .career
    @State private var levelFilter: Int?              = nil
    @State private var secFilter: SecurityRangeFilter = .any
    @State private var divisionFilter: Int?           = nil
    @State private var factionFilter: Int?            = nil

    // Database state
    @State private var dbLoaded  = false
    @State private var dbLoading = false
    @State private var dbError: String? = nil
    @State private var availableDivisions: [(id: Int, name: String)] = []
    @State private var availableFactions: [(id: Int, name: String, shortName: String)] = []

    // Faction logo cache (pre-loaded so Picker can use them synchronously)
    @State private var factionImages: [Int: NSImage] = [:]

    // Results
    @State private var resolvedAgents: [ResolvedAgent] = []
    @State private var totalFiltered   = 0
    @State private var isResolvingResults = false
    @State private var searchTask: Task<Void, Never>? = nil

    // Sort
    @State private var sortOrder: AgentSortOrder = .jumps

    // Selection
    @State private var selectedAgent: ResolvedAgent? = nil

    var body: some View {
        HStack(spacing: 0) {
            leftPanel
            if let agent = selectedAgent {
                Divider()
                AgentDetailView(
                    agent: agent,
                    onDestinationSet: { msg in
                        if let idx = resolvedAgents.firstIndex(where: { $0.id == agent.id }) {
                            // detail view handles its own message state
                            _ = idx
                        }
                    }
                )
                .frame(width: 300)
                .id(agent.id)
            }
        }
        .safeAreaInset(edge: .top, spacing: 0) {
            HStack {
                Text("Agent Finder")
                    .font(.largeTitle.bold())
                Spacer()
                if dbLoading || isResolvingResults {
                    ProgressView().scaleEffect(0.7)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(.background)
        }
        .navigationTitle("")
        .task {
            await startDatabase()
        }
        .onChange(of: typeFilter)     { _, _ in divisionFilter = nil; triggerSearch() }
        .onChange(of: levelFilter)    { _, _ in triggerSearch() }
        .onChange(of: secFilter)      { _, _ in triggerSearch() }
        .onChange(of: divisionFilter) { _, _ in triggerSearch() }
        .onChange(of: factionFilter)  { _, _ in triggerSearch() }
        .onChange(of: sortOrder)      { _, _ in resolvedAgents = sortedAgents(resolvedAgents) }
    }

    // MARK: Left Panel

    private var leftPanel: some View {
        VStack(spacing: 0) {
            filterPanel
            Divider()
            resultsPanel
        }
    }

    // MARK: Filter Panel

    private var filterPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Agent type row
            VStack(alignment: .leading, spacing: 6) {
                Text("Agent Type")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(AgentTypeFilter.allCases) { type_ in
                            filterChip(
                                label: type_.rawValue,
                                icon: type_.iconName,
                                color: type_.color,
                                isSelected: typeFilter == type_
                            ) { typeFilter = type_ }
                        }
                    }
                }
            }

            // Division sub-filter (only for Basic Mission)
            if typeFilter == .basic && !availableDivisions.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Division")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 6) {
                            filterChip(label: "Any", icon: "square.grid.2x2", color: .secondary, isSelected: divisionFilter == nil) {
                                divisionFilter = nil
                            }
                            ForEach(availableDivisions, id: \.id) { div in
                                filterChip(label: div.name, icon: divisionIcon(div.name), color: divisionColor(div.name), isSelected: divisionFilter == div.id) {
                                    divisionFilter = div.id
                                }
                            }
                        }
                    }
                }
            }

            // Level + Security + Faction row
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Level")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Picker("Level", selection: $levelFilter) {
                        Text("Any").tag(Optional<Int>.none)
                        ForEach(1...5, id: \.self) { l in Text("L\(l)").tag(Optional<Int>.some(l)) }
                    }
                    .pickerStyle(.menu)
                    .labelsHidden()
                    .controlSize(.small)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text("Security")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Picker("Security", selection: $secFilter) {
                        ForEach(SecurityRangeFilter.allCases) { s in Text(s.title).tag(s) }
                    }
                    .pickerStyle(.menu)
                    .labelsHidden()
                    .controlSize(.small)
                }

                if !availableFactions.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Faction")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                        Picker("Faction", selection: $factionFilter) {
                            Label("All", systemImage: "globe").tag(Optional<Int>.none)
                            ForEach(availableFactions, id: \.id) { f in
                                Label {
                                    Text(f.shortName)
                                } icon: {
                                    if let img = factionImages[f.id] {
                                        Image(nsImage: img)
                                            .resizable()
                                            .interpolation(.high)
                                            .frame(width: 16, height: 16)
                                            .clipShape(RoundedRectangle(cornerRadius: 3))
                                    } else {
                                        Image(systemName: "shield.fill")
                                            .foregroundStyle(Self.factionColor(f.id))
                                    }
                                }
                                .tag(Optional<Int>.some(f.id))
                            }
                        }
                        .pickerStyle(.menu)
                        .labelsHidden()
                        .controlSize(.small)
                    }
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(.bar)
    }

    private func filterChip(
        label: String, icon: String, color: Color,
        isSelected: Bool, action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: icon).font(.caption2)
                Text(label).font(.caption.weight(.semibold))
            }
            .padding(.horizontal, 9).padding(.vertical, 5)
            .background(isSelected ? color.opacity(0.2) : Color.secondary.opacity(0.08), in: Capsule())
            .foregroundStyle(isSelected ? color : .secondary)
            .overlay(Capsule().strokeBorder(isSelected ? color.opacity(0.5) : Color.clear, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    // MARK: Results Panel

    private var resultsPanel: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                // Status row
                HStack {
                    if dbLoading {
                        Label("Downloading agent database…", systemImage: "arrow.down.circle")
                            .font(.caption).foregroundStyle(.secondary)
                    } else if let err = dbError {
                        Label(err, systemImage: "exclamationmark.triangle.fill")
                            .font(.caption).foregroundStyle(.orange)
                    } else if !dbLoaded {
                        ProgressView("Loading…").font(.caption)
                    } else {
                        Text("\(totalFiltered) agents found")
                            .font(.caption).foregroundStyle(.secondary)
                        if isResolvingResults {
                            ProgressView().scaleEffect(0.6).padding(.leading, 4)
                        }
                    }
                    Spacer()
                    HStack(spacing: 8) {
                        if resolvedAgents.count < totalFiltered && totalFiltered > 0 {
                            Text("Showing top \(resolvedAgents.count)")
                                .font(.caption2).foregroundStyle(.tertiary)
                        }
                        Picker("Sort", selection: $sortOrder) {
                            ForEach(AgentSortOrder.allCases) { order in
                                Text(order.title).tag(order)
                            }
                        }
                        .pickerStyle(.segmented)
                        .controlSize(.mini)
                        .frame(width: 110)
                        .labelsHidden()
                        .disabled(!dbLoaded || resolvedAgents.isEmpty)
                    }
                }
                .padding(.horizontal, 16).padding(.vertical, 8)

                if resolvedAgents.isEmpty && dbLoaded && !isResolvingResults {
                    Text("No agents match the current filters.")
                        .font(.callout).foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity).padding(32)
                } else {
                    ForEach(Array(resolvedAgents.enumerated()), id: \.element.id) { _, agent in
                        agentRow(agent)
                        Divider().padding(.leading, 56)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func agentRow(_ agent: ResolvedAgent) -> some View {
        let isSelected = selectedAgent?.id == agent.id
        Button {
            selectedAgent = agent
        } label: {
            HStack(spacing: 10) {
                // Portrait
                AsyncImage(url: characterPortraitURL(agent.agent.agentID)) { phase in
                    if let img = phase.image {
                        img.resizable().frame(width: 48, height: 48).clipShape(RoundedRectangle(cornerRadius: 6))
                    } else {
                        RoundedRectangle(cornerRadius: 6)
                            .fill(typeFilter.color.opacity(0.2))
                            .frame(width: 48, height: 48)
                            .overlay(Image(systemName: typeFilter.iconName).font(.callout).foregroundStyle(typeFilter.color))
                    }
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(agent.displayName).font(.subheadline.weight(.medium)).foregroundStyle(.primary).lineLimit(1)
                    HStack(spacing: 6) {
                        Text(agent.displaySystem).font(.caption).foregroundStyle(.secondary)
                        if let sec = agent.securityStatus {
                            agentSecBadge(sec)
                        }
                    }
                    Text(agent.displayCorp).font(.caption2).foregroundStyle(.tertiary).lineLimit(1)
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 3) {
                    levelBadge(agent.agent.level)
                    if let jumps = agent.jumpCount {
                        agentJumpBadge(jumps)
                    } else if isResolvingResults {
                        ProgressView().scaleEffect(0.45)
                    }
                }

                Image(systemName: "chevron.right").font(.caption2).foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 16).padding(.vertical, 8)
            .background(isSelected ? typeFilter.color.opacity(0.08) : Color.clear)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func levelBadge(_ level: Int) -> some View {
        let colors: [Color] = [.secondary, .gray, .blue, .green, .purple, .orange]
        let c = colors[min(level, 5)]
        return Text("L\(level)")
            .font(.caption2.bold().monospacedDigit())
            .foregroundStyle(c)
            .padding(.horizontal, 5).padding(.vertical, 2)
            .background(c.opacity(0.15), in: Capsule())
    }

    // MARK: Division Helpers

    private func divisionIcon(_ name: String) -> String {
        let l = name.lowercased()
        if l.contains("security") || l.contains("combat") { return "shield.lefthalf.filled" }
        if l.contains("distribution") || l.contains("courier") { return "shippingbox.fill" }
        if l.contains("mining") { return "cylinder.fill" }
        if l.contains("research") || l.contains("r&d") { return "atom" }
        if l.contains("internal") { return "lock.fill" }
        return "person.fill"
    }

    private func divisionColor(_ name: String) -> Color {
        let l = name.lowercased()
        if l.contains("security") { return .blue }
        if l.contains("distribution") { return .green }
        if l.contains("mining") { return .orange }
        if l.contains("research") { return .purple }
        return .secondary
    }

    // MARK: Faction Color

    static func factionColor(_ id: Int) -> Color {
        switch id {
        case 500001: return .cyan      // Caldari
        case 500002: return .orange    // Minmatar
        case 500003: return .yellow    // Amarr
        case 500004: return .teal      // Gallente
        case 500006: return .white     // CONCORD
        case 500008: return .purple    // Khanid
        case 500014: return .red       // Sisters of EVE
        case 500016: return .blue      // Mordu's Legion
        default:     return .secondary
        }
    }

    // MARK: Portrait URL

    private func characterPortraitURL(_ id: Int) -> URL? {
        URL(string: "https://images.evetech.net/characters/\(id)/portrait?size=64")
    }

    // MARK: Data Loading

    private func startDatabase() async {
        dbLoading = true
        await AgentDataManager.shared.ensureLoaded()
        let loaded   = await AgentDataManager.shared.isLoaded
        let error    = await AgentDataManager.shared.loadError
        let divs     = await AgentDataManager.shared.availableBasicDivisions()
        let factions = await AgentDataManager.shared.availableFactions()
        dbLoaded           = loaded
        dbError            = error
        dbLoading          = false
        availableDivisions = divs
        availableFactions  = factions
        if loaded {
            triggerSearch()
            Task { await loadFactionImages() }
        }
    }

    private func loadFactionImages() async {
        // ESI /universe/factions/ gives each faction's corporation_id,
        // which is the correct key for the EVE image server logo.
        guard let esiFactions: [ESIFaction] = try? await ESIClient.shared.fetch("/universe/factions/") else { return }
        let corpByFaction = esiFactions.reduce(into: [Int: Int]()) { dict, f in
            if let cid = f.corporationId { dict[f.factionId] = cid }
        }

        await withTaskGroup(of: (Int, NSImage?).self) { group in
            for faction in availableFactions where factionImages[faction.id] == nil {
                let fid = faction.id
                guard let corpID = corpByFaction[fid],
                      let url   = EVEImageURL.corporationLogo(corpID, size: 32)
                else { continue }
                group.addTask {
                    guard let (data, response) = try? await URLSession.shared.data(from: url),
                          (response as? HTTPURLResponse)?.statusCode == 200,
                          let image = NSImage(data: data)
                    else { return (fid, nil) }
                    return (fid, image)
                }
            }
            for await (fid, image) in group {
                if let image { factionImages[fid] = image }
            }
        }
    }

    private func sortedAgents(_ agents: [ResolvedAgent]) -> [ResolvedAgent] {
        switch sortOrder {
        case .jumps:
            return agents.sorted {
                switch ($0.jumpCount, $1.jumpCount) {
                case (nil, nil):        return $0.agent.level > $1.agent.level
                case (nil, _):          return false
                case (_, nil):          return true
                case (let a?, let b?):  return a == b ? $0.agent.level > $1.agent.level : a < b
                }
            }
        case .level:
            return agents.sorted {
                if $0.agent.level != $1.agent.level { return $0.agent.level > $1.agent.level }
                switch ($0.jumpCount, $1.jumpCount) {
                case (nil, nil):        return false
                case (nil, _):          return false
                case (_, nil):          return true
                case (let a?, let b?):  return a < b
                }
            }
        }
    }

    private func triggerSearch() {
        searchTask?.cancel()
        searchTask = Task {
            await runSearch()
        }
    }

    private func runSearch() async {
        guard dbLoaded else { return }
        isResolvingResults = true
        defer { isResolvingResults = false }

        // 1. Filter in memory
        let filtered = await AgentDataManager.shared.filteredAgents(
            typeID: typeFilter.agentTypeID,
            divisionID: divisionFilter,
            level: levelFilter,
            factionID: factionFilter,
            locatorOnly: typeFilter.isLocatorMode
        )
        totalFiltered = filtered.count

        // Take top 50 by level descending (highest quality first before jump sort)
        let candidates = Array(filtered.sorted { $0.level > $1.level }.prefix(50))
        var working = candidates.map { ResolvedAgent(agent: $0) }
        resolvedAgents = working

        // 2. Resolve station → system in parallel
        await withTaskGroup(of: (Int, Int?).self) { group in
            for a in candidates {
                group.addTask {
                    let station = await UniverseCache.shared.station(id: a.locationID)
                    return (a.agentID, station?.systemId)
                }
            }
            for await (aid, sysID) in group {
                if let i = working.firstIndex(where: { $0.id == aid }) {
                    working[i].systemID = sysID
                }
            }
        }
        if Task.isCancelled { return }
        resolvedAgents = working

        // 3a. Resolve system details — each task returns its result; mutations happen
        //     only in the sequential for-await loop, eliminating the data race.
        struct SysInfo { let sysID: Int; let name: String; let sec: Double; let con: String?; let reg: String? }
        let systemIDs = Set(working.compactMap(\.systemID))
        await withTaskGroup(of: SysInfo?.self) { group in
            for sysID in systemIDs {
                group.addTask {
                    guard let sys = await UniverseCache.shared.solarSystem(id: sysID) else { return nil }
                    var con: String? = nil
                    var reg: String? = nil
                    if let c = await UniverseCache.shared.constellation(id: sys.constellationId) {
                        con = c.name
                        if let r = await UniverseCache.shared.region(id: c.regionId) { reg = r.name }
                    }
                    return SysInfo(sysID: sysID, name: sys.name, sec: sys.securityStatus, con: con, reg: reg)
                }
            }
            for await info in group {
                guard let info else { continue }
                for i in working.indices where working[i].systemID == info.sysID {
                    working[i].systemName        = info.name
                    working[i].securityStatus    = info.sec
                    working[i].constellationName = info.con
                    working[i].regionName        = info.reg
                }
            }
        }
        if Task.isCancelled { return }

        // 3b. Resolve agent + corp names concurrently, then apply sequentially.
        let agentIDs = candidates.map(\.agentID)
        let corpIDs  = Array(Set(candidates.map(\.corporationID)))
        async let agentNamesFetch = NameResolver.shared.resolve(ids: agentIDs)
        async let corpNamesFetch  = NameResolver.shared.resolve(ids: corpIDs)
        let (aN, cN) = await (agentNamesFetch, corpNamesFetch)
        for i in working.indices {
            working[i].name     = aN[working[i].agent.agentID]
            working[i].corpName = cN[working[i].agent.corporationID]
        }
        if Task.isCancelled { return }

        // 4. Apply security filter now that we have security status
        working = working.filter { secFilter.matches($0.securityStatus) }
        totalFiltered = secFilter == .any ? filtered.count : working.count
        resolvedAgents = working

        // 5. Calculate jump counts
        guard let account = accountManager.selectedAccount,
              let token = try? await accountManager.validToken(for: account),
              let location: ESICharacterLocation = try? await ESIClient.shared.fetch(
                  "/characters/\(account.characterID)/location/", token: token
              )
        else {
            resolvedAgents = sortedAgents(working)
            return
        }

        let fromID = location.solarSystemId
        await withTaskGroup(of: (Int, Int?).self) { group in
            for a in working {
                guard let destID = a.systemID else { continue }
                let aid = a.id
                group.addTask {
                    if fromID == destID { return (aid, 0) }
                    guard let route: [Int] = try? await ESIClient.shared.fetch(
                        "/route/\(fromID)/\(destID)/",
                        queryItems: [URLQueryItem(name: "flag", value: "shortest")]
                    ) else { return (aid, nil) }
                    return (aid, max(0, route.count - 1))
                }
            }
            for await (aid, jumps) in group {
                if let i = working.firstIndex(where: { $0.id == aid }) {
                    working[i].jumpCount = jumps
                }
            }
        }
        if Task.isCancelled { return }

        resolvedAgents = sortedAgents(working)

        // Refresh selected agent detail if it's in the updated list
        if let sel = selectedAgent, let updated = working.first(where: { $0.id == sel.id }) {
            selectedAgent = updated
        }
    }
}

// MARK:  Agent Detail View

struct AgentDetailView: View {
    let agent: ResolvedAgent
    var onDestinationSet: (String) -> Void = { _ in }

    @Environment(AccountManager.self) private var accountManager

    @State private var isSetting        = false
    @State private var autopilotMessage: String? = nil

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                header
                Divider()
                actionBar
                Divider()
                infoSection
                    .padding(16)
            }
        }
        .background(.regularMaterial)
    }

    // MARK: Header

    private var header: some View {
        ZStack(alignment: .bottomLeading) {
            LinearGradient(
                colors: [Color.blue.opacity(0.4), Color.blue.opacity(0.1)],
                startPoint: .topLeading, endPoint: .bottomTrailing
            )
            .frame(height: 90)

            HStack(spacing: 10) {
                AsyncImage(url: URL(string: "https://images.evetech.net/characters/\(agent.agent.agentID)/portrait?size=64")) { phase in
                    if let img = phase.image {
                        img.resizable().frame(width: 64, height: 64).clipShape(RoundedRectangle(cornerRadius: 8))
                    } else {
                        RoundedRectangle(cornerRadius: 8).fill(.blue.opacity(0.3)).frame(width: 64, height: 64)
                    }
                }
                VStack(alignment: .leading, spacing: 3) {
                    Text(agent.displayName).font(.headline).foregroundStyle(.primary)
                    Text(agent.displayCorp).font(.caption).foregroundStyle(.secondary)
                }
            }
            .padding(12)
        }
    }

    // MARK: Action Bar

    private var actionBar: some View {
        HStack(spacing: 8) {
            if accountManager.selectedAccount != nil {
                Button {
                    Task { await setDestination() }
                } label: {
                    Label(isSetting ? "Setting…" : "Set Destination", systemImage: "paperplane.fill")
                        .font(.caption.weight(.semibold))
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .disabled(agent.systemID == nil || isSetting)
            }
            Spacer()
            if let msg = autopilotMessage {
                Label(msg, systemImage: msg.hasPrefix("Destination") ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(msg.hasPrefix("Destination") ? .green : .orange)
                    .lineLimit(1)
            }
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
        .background(.bar)
    }

    // MARK: Info

    private var infoSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("Details", systemImage: "person.text.rectangle.fill")
                .font(.subheadline.bold())

            infoRow("Level",       "L\(agent.agent.level)")
            infoRow("Agent ID",    "\(agent.agent.agentID)")
            infoRow("Corp ID",     "\(agent.agent.corporationID)")

            Divider()
            Label("Location", systemImage: "location.fill")
                .font(.subheadline.bold()).foregroundStyle(.blue)

            HStack(spacing: 6) {
                if let sec = agent.securityStatus {
                    Circle().fill(agentSecColor(sec)).frame(width: 8, height: 8)
                }
                Text(agent.displaySystem).font(.body.bold())
                if let sec = agent.securityStatus {
                    agentSecBadge(sec)
                }
                if let j = agent.jumpCount { agentJumpBadge(j) }
            }
            if let c = agent.constellationName { infoRow("Constellation", c) }
            if let r = agent.regionName        { infoRow("Region", r) }
        }
    }

    private func infoRow(_ label: String, _ value: String) -> some View {
        HStack(spacing: 6) {
            Text(label).font(.caption).foregroundStyle(.tertiary).frame(width: 90, alignment: .trailing)
            Text(value).font(.caption).foregroundStyle(.secondary)
        }
    }

    // MARK: Autopilot

    private func setDestination() async {
        guard let account = accountManager.selectedAccount, let sysID = agent.systemID else { return }
        isSetting = true; autopilotMessage = nil
        do {
            let token = try await accountManager.validToken(for: account)
            try await ESIClient.shared.postAction(
                "/ui/autopilot/waypoint/", token: token,
                queryItems: [
                    URLQueryItem(name: "add_to_beginning",      value: "false"),
                    URLQueryItem(name: "clear_other_waypoints", value: "true"),
                    URLQueryItem(name: "destination_id",        value: "\(sysID)"),
                ]
            )
            autopilotMessage = "Destination set to \(agent.displaySystem)."
        } catch ESIError.unauthorized {
            autopilotMessage = "Needs esi-ui.write_waypoint.v1 scope."
        } catch {
            autopilotMessage = error.localizedDescription
        }
        isSetting = false
    }
}

// MARK:  Shared Badges

func agentSecBadge(_ status: Double) -> some View {
    Text(String(format: "%.1f", max(0.0, status)))
        .font(.caption.bold().monospacedDigit())
        .foregroundStyle(agentSecColor(status))
        .padding(.horizontal, 7).padding(.vertical, 3)
        .background(agentSecColor(status).opacity(0.15), in: Capsule())
}

func agentJumpBadge(_ jumps: Int) -> some View {
    Group {
        if jumps == 0 {
            Text("here").font(.caption.bold()).foregroundStyle(.green)
                .padding(.horizontal, 6).padding(.vertical, 2)
                .background(.green.opacity(0.12), in: Capsule())
        } else {
            Text("\(jumps) jumps").font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                .padding(.horizontal, 6).padding(.vertical, 2)
                .background(.secondary.opacity(0.1), in: Capsule())
        }
    }
}

func agentSecColor(_ status: Double) -> Color {
    switch status {
    case 0.9...:    return Color(red: 0.3, green: 0.9, blue: 1.0)
    case 0.8..<0.9: return Color(red: 0.0, green: 0.9, blue: 0.8)
    case 0.7..<0.8: return Color(red: 0.0, green: 0.9, blue: 0.4)
    case 0.6..<0.7: return Color(red: 0.4, green: 0.9, blue: 0.0)
    case 0.5..<0.6: return Color(red: 0.9, green: 0.9, blue: 0.0)
    case 0.4..<0.5: return Color(red: 1.0, green: 0.6, blue: 0.0)
    case 0.3..<0.4: return Color(red: 1.0, green: 0.4, blue: 0.0)
    case 0.2..<0.3: return Color(red: 1.0, green: 0.2, blue: 0.0)
    case 0.1..<0.2: return Color(red: 0.9, green: 0.0, blue: 0.0)
    default:        return Color(red: 0.6, green: 0.0, blue: 0.0)
    }
}
