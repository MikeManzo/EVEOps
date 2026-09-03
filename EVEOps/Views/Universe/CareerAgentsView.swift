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

    // Standing-based access (from the selected character's standings + social skills)
    @State private var standingsLoaded = false
    @State private var standingSkills = StandingSkills()
    @State private var factionStandings: [Int: Double] = [:]
    @State private var corpStandings: [Int: Double] = [:]
    @State private var agentStandings: [Int: Double] = [:]
    @State private var onlyAccessible = false

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
        .task(id: accountManager.selectedCharacterID) {
            await loadStandings()
        }
        .onChange(of: typeFilter)      { _, _ in divisionFilter = nil; triggerSearch() }
        .onChange(of: levelFilter)     { _, _ in triggerSearch() }
        .onChange(of: secFilter)       { _, _ in triggerSearch() }
        .onChange(of: divisionFilter)  { _, _ in triggerSearch() }
        .onChange(of: factionFilter)   { _, _ in triggerSearch() }
        .onChange(of: onlyAccessible)  { _, _ in triggerSearch() }
        .onChange(of: sortOrder)       { _, _ in resolvedAgents = sortedAgents(resolvedAgents) }
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

                if standingsLoaded {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Standing")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                        Toggle(isOn: $onlyAccessible) {
                            Text("Accessible only").font(.caption)
                        }
                        .toggleStyle(.checkbox)
                        .controlSize(.small)
                        .help("Show only agents your current effective standing lets you talk to")
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
                CachedAsyncImage(url: characterPortraitURL(agent.agent.agentID)) { phase in
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
                        if let access = agent.access {
                            agentAccessBadge(access)
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

    // MARK: Standings

    private func loadStandings() async {
        guard let account = accountManager.selectedAccount,
              let token = try? await accountManager.validToken(for: account) else {
            standingsLoaded = false
            return
        }
        let charID = account.characterID

        let standings: [ESIStanding]? = try? await ESIClient.shared.fetch(
            "/characters/\(charID)/standings/", token: token)
        let skillsResp: ESISkillsResponse? = try? await ESIClient.shared.fetch(
            "/characters/\(charID)/skills/", token: token)

        guard let standings else { standingsLoaded = false; return }

        var fac: [Int: Double] = [:]
        var corp: [Int: Double] = [:]
        var agent: [Int: Double] = [:]
        for s in standings {
            switch s.fromType {
            case "faction":  fac[s.fromId]  = s.standing
            case "npc_corp": corp[s.fromId] = s.standing
            case "agent":    agent[s.fromId] = s.standing
            default: break
            }
        }
        factionStandings = fac
        corpStandings    = corp
        agentStandings   = agent
        standingSkills   = skillsResp.map { StandingSkills(skills: $0.skills) } ?? StandingSkills()
        standingsLoaded  = true
        triggerSearch()
    }

    private func computeAccess(
        for agent: AgentDataManager.SDEAgent,
        corpFactions: [Int: Int]
    ) -> AgentAccessResult {
        let factionID = corpFactions[agent.corporationID]
        return AgentAccess.evaluate(
            level: agent.level,
            factionBase: factionID.flatMap { factionStandings[$0] },
            corpBase: corpStandings[agent.corporationID],
            agentBase: agentStandings[agent.agentID],
            skills: standingSkills,
            pirateFaction: factionID.map { AgentAccess.pirateFactionIDs.contains($0) } ?? false
        )
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

        // 1b. Standing-based access (needs the character's standings + social skills)
        let corpFactions = standingsLoaded ? await AgentDataManager.shared.corpFactions : [:]
        var accessByAgent: [Int: AgentAccessResult] = [:]
        if standingsLoaded {
            for a in filtered {
                accessByAgent[a.agentID] = computeAccess(for: a, corpFactions: corpFactions)
            }
        }
        let visible = (onlyAccessible && standingsLoaded)
            ? filtered.filter { accessByAgent[$0.agentID]?.canAccess ?? false }
            : filtered
        totalFiltered = visible.count

        // Take top 50 by level descending (highest quality first before jump sort)
        let candidates = Array(visible.sorted { $0.level > $1.level }.prefix(50))
        var working = candidates.map { a -> ResolvedAgent in
            var r = ResolvedAgent(agent: a)
            r.access = accessByAgent[a.agentID]
            return r
        }
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
        totalFiltered = secFilter == .any ? visible.count : working.count
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

