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

// MARK:  Security Class Filter

private enum SecurityClassFilter: String, CaseIterable {
    case all      = "All"
    case highsec  = "Highsec"
    case lowsec   = "Lowsec"
    case nullsec  = "Null"

    func matches(_ security: Double) -> Bool {
        switch self {
        case .all:     return true
        case .highsec: return security >= 0.5
        case .lowsec:  return security > 0.0 && security < 0.5
        case .nullsec: return security <= 0.0
        }
    }
}

// MARK:  Region Station Browser

struct RegionStationBrowserView: View {
    var onNavigateToMarket: (() -> Void)? = nil

    @Environment(AccountManager.self) private var accountManager
    @Environment(DashboardPrefetcher.self) private var prefetcher

    @State private var selectedRegionId: Int = 10000002  // The Forge (Jita)
    @State private var availableRegions: [(id: Int, name: String, factionId: Int?)] = []
    @State private var stations: [StationEntry] = []
    @State private var isLoading = false
    @State private var loadingProgress = ""
    @State private var searchText = ""
    @State private var selectedServices: Set<String> = []
    @State private var securityFilter: SecurityClassFilter = .all
    @State private var selectedStation: StationEntry?
    @State private var jumpCounts: [Int: Int] = [:]   // systemId → jump count from character's location

    private let filterableServices: [(key: String, label: String, icon: String, color: Color)] = [
        ("market",             "Market",        "cart.fill",                    .blue),
        ("reprocessing-plant", "Reprocessing",  "arrow.3.trianglepath",         .orange),
        ("fitting",            "Fitting",       "gearshape.2.fill",             .purple),
        ("repair-facilities",  "Repair",        "wrench.and.screwdriver.fill",  .green),
        ("cloning",            "Cloning",       "person.2.fill",                .pink),
        ("factory",            "Manufacturing", "hammer.fill",                  .yellow),
        ("loyalty-point-store","LP Store",      "star.fill",                    Color(red: 0.9, green: 0.75, blue: 0.2)),
    ]

    var body: some View {
        HStack(spacing: 0) {
            VStack(spacing: 0) {
                filterBar
                Divider()
                contentArea
            }

            if let station = selectedStation {
                Divider()
                StationDetailView(entry: station, onNavigateToMarket: onNavigateToMarket)
                    .frame(width: 320)
            }
        }
        .safeAreaInset(edge: .top, spacing: 0) {
            HStack {
                Text("Station Browser")
                    .font(.largeTitle.bold())
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(.background)
        }
        .navigationTitle("Station Browser")
        .task { await loadRegions() }
        .task(id: selectedRegionId) {
            selectedStation = nil
            jumpCounts = [:]
            await loadStations()
            await loadJumpCounts()
        }
    }

    // MARK:  Filter Bar

    private var filterBar: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                // Region picker
                Menu {
                    ForEach(availableRegions, id: \.id) { region in
                        Button {
                            selectedRegionId = region.id
                        } label: {
                            Text(region.name)
                        }
                    }
                } label: {
                    HStack(spacing: 6) {
                        Circle()
                            .fill(factionColor(availableRegions.first(where: { $0.id == selectedRegionId })?.factionId))
                            .frame(width: 8, height: 8)
                        Text(availableRegions.first(where: { $0.id == selectedRegionId })?.name ?? "Region")
                            .font(.subheadline.bold())
                        Image(systemName: "chevron.down")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
                }
                .disabled(availableRegions.isEmpty)

                // Security class filter
                Picker("Security", selection: $securityFilter) {
                    ForEach(SecurityClassFilter.allCases, id: \.self) { filter in
                        Text(filter.rawValue).tag(filter)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 220)

                // Search
                HStack {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.secondary)
                    TextField("Search stations...", text: $searchText)
                        .textFieldStyle(.plain)
                    if !searchText.isEmpty {
                        Button { searchText = "" } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
                .frame(maxWidth: 260)

                Spacer()

                if !isLoading && !stations.isEmpty {
                    Text("\(filteredStations.count) of \(stations.count) station\(stations.count == 1 ? "" : "s")")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            // Service filter chips
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(filterableServices, id: \.key) { svc in
                        let isSelected = selectedServices.contains(svc.key)
                        Button {
                            if isSelected { selectedServices.remove(svc.key) }
                            else { selectedServices.insert(svc.key) }
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: svc.icon).font(.caption2)
                                Text(svc.label).font(.caption)
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(isSelected ? svc.color.opacity(0.25) : Color.primary.opacity(0.06), in: Capsule())
                            .overlay(Capsule().strokeBorder(isSelected ? svc.color : Color.clear, lineWidth: 1))
                            .foregroundStyle(isSelected ? svc.color : .secondary)
                        }
                        .buttonStyle(.plain)
                    }

                    if !selectedServices.isEmpty {
                        Button {
                            selectedServices.removeAll()
                        } label: {
                            Text("Clear")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.bar)
    }

    // MARK:  Content Area

    @ViewBuilder
    private var contentArea: some View {
        if isLoading {
            VStack(spacing: 12) {
                ProgressView()
                Text(loadingProgress.isEmpty ? "Loading stations..." : loadingProgress)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if filteredStations.isEmpty {
            VStack(spacing: 8) {
                Image(systemName: "building.2.fill")
                    .font(.system(size: 40))
                    .foregroundStyle(.secondary)
                Text(stations.isEmpty ? "No NPC stations in this region" : "No stations match your filters")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            List(selection: $selectedStation) {
                ForEach(groupedStations, id: \.constellationName) { group in
                    Section {
                        ForEach(group.systems, id: \.systemName) { sys in
                            // System sub-header — no .tag(), so not selectable
                            systemHeader(sys)
                                .listRowBackground(Color.primary.opacity(0.04))

                            // Individual station rows — selectable
                            ForEach(sys.stations, id: \.station.stationId) { entry in
                                compactStationRow(entry)
                                    .tag(entry)
                            }
                        }
                    } header: {
                        HStack(spacing: 6) {
                            Image(systemName: "map")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                            Text(group.constellationName)
                                .font(.subheadline.bold())
                        }
                    }
                }
            }
            .listStyle(.sidebar)
        }
    }

    // MARK:  List Rows

    private func systemHeader(_ sys: SystemGroup) -> some View {
        HStack(spacing: 6) {
            Circle()
                .fill(securityColor(sys.securityStatus))
                .frame(width: 7, height: 7)
            Text(sys.systemName)
                .font(.caption.bold())
                .foregroundStyle(.secondary)
            Text(String(format: "%.1f", sys.securityStatus))
                .font(.caption2.monospacedDigit())
                .foregroundStyle(securityColor(sys.securityStatus))
            Spacer()
            // Jump count badge
            if let systemId = sys.stations.first?.systemId,
               let jumps = jumpCounts[systemId] {
                Text(jumps == 0 ? "current" : "\(jumps)j")
                    .font(.caption2.bold().monospacedDigit())
                    .foregroundStyle(jumps == 0 ? .green : .secondary)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(jumps == 0 ? Color.green.opacity(0.12) : Color.secondary.opacity(0.08), in: Capsule())
            }
            Text("\(sys.stations.count) station\(sys.stations.count == 1 ? "" : "s")")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 2)
    }

    private func compactStationRow(_ entry: StationEntry) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(entry.station.name)
                .font(.body)
                .lineLimit(1)

            if let services = entry.station.services, !services.isEmpty {
                HStack(spacing: 6) {
                    ForEach(services.sorted(), id: \.self) { service in
                        let info = serviceInfo(service)
                        Image(systemName: info.icon)
                            .font(.system(size: 10))
                            .foregroundStyle(info.color)
                    }
                }
            }
        }
        .padding(.vertical, 2)
        .padding(.leading, 10)
    }

    // MARK:  Computed filtered/grouped data

    private var filteredStations: [StationEntry] {
        stations.filter { entry in
            let matchesSearch = searchText.isEmpty ||
                entry.station.name.localizedCaseInsensitiveContains(searchText)
            let matchesServices = selectedServices.isEmpty ||
                selectedServices.isSubset(of: Set(entry.station.services ?? []))
            let matchesSecurity = securityFilter.matches(entry.securityStatus)
            return matchesSearch && matchesServices && matchesSecurity
        }
    }

    private var groupedStations: [ConstellationGroup] {
        var byConstellation: [String: [StationEntry]] = [:]
        for entry in filteredStations {
            byConstellation[entry.constellationName, default: []].append(entry)
        }
        return byConstellation.map { name, entries in
            var bySys: [String: [StationEntry]] = [:]
            for e in entries { bySys[e.systemName, default: []].append(e) }
            let systems = bySys.map { sysName, sysEntries in
                SystemGroup(
                    systemName: sysName,
                    securityStatus: sysEntries.first?.securityStatus ?? 0,
                    stations: sysEntries.sorted { $0.station.name < $1.station.name }
                )
            }.sorted { $0.securityStatus > $1.securityStatus }
            return ConstellationGroup(constellationName: name, systems: systems)
        }.sorted { $0.constellationName < $1.constellationName }
    }

    // MARK:  Data Loading

    private func loadRegions() async {
        guard availableRegions.isEmpty else { return }
        availableRegions = await UniverseCache.shared.knownSpaceRegions()

        // Default to character's current region and system
        if let account = accountManager.selectedAccount,
           let data = prefetcher.data(for: account.characterID),
           let system = await UniverseCache.shared.solarSystem(id: data.location.solarSystemId),
           let constellation = await UniverseCache.shared.constellation(id: system.constellationId) {
            let regionId = constellation.regionId
            if availableRegions.contains(where: { $0.id == regionId }) {
                selectedRegionId = regionId
            }
            searchText = system.name
        }
    }

    private func loadStations() async {
        guard !availableRegions.isEmpty else { return }
        isLoading = true
        stations = []

        guard let region = await UniverseCache.shared.region(id: selectedRegionId),
              let constellationIds = region.constellations, !constellationIds.isEmpty else {
            isLoading = false
            return
        }

        loadingProgress = "Loading constellations..."
        let constellations: [ESIConstellation] = await withTaskGroup(of: ESIConstellation?.self) { group in
            for cid in constellationIds {
                group.addTask { await UniverseCache.shared.constellation(id: cid) }
            }
            var results: [ESIConstellation] = []
            for await c in group { if let c { results.append(c) } }
            return results
        }

        loadingProgress = "Loading systems..."
        let systemIds = constellations.flatMap { $0.systems ?? [] }
        let allSystems: [ESISolarSystem] = await withTaskGroup(of: ESISolarSystem?.self) { group in
            for sid in systemIds {
                group.addTask { await UniverseCache.shared.solarSystem(id: sid) }
            }
            var results: [ESISolarSystem] = []
            for await s in group { if let s { results.append(s) } }
            return results
        }

        // Build lookup maps
        var systemToConstellation: [Int: String] = [:]
        for c in constellations {
            for sid in c.systems ?? [] { systemToConstellation[sid] = c.name }
        }
        var stationToSystem: [Int: ESISolarSystem] = [:]
        for sys in allSystems {
            for sid in sys.stations ?? [] { stationToSystem[sid] = sys }
        }

        let stationIds = allSystems.flatMap { $0.stations ?? [] }
        guard !stationIds.isEmpty else {
            isLoading = false
            loadingProgress = ""
            return
        }

        loadingProgress = "Loading \(stationIds.count) stations..."
        let stationDetails: [ESIStation] = await withTaskGroup(of: ESIStation?.self) { group in
            for sid in stationIds {
                group.addTask { await UniverseCache.shared.station(id: sid) }
            }
            var results: [ESIStation] = []
            for await s in group { if let s { results.append(s) } }
            return results
        }

        var entries: [StationEntry] = []
        for station in stationDetails {
            guard let sys = stationToSystem[station.stationId] else { continue }
            entries.append(StationEntry(
                station: station,
                systemName: sys.name,
                systemId: sys.systemId,
                securityStatus: sys.securityStatus,
                constellationName: systemToConstellation[sys.systemId] ?? "Unknown"
            ))
        }

        stations = entries
        isLoading = false
        loadingProgress = ""
    }

    private func loadJumpCounts() async {
        guard let account = accountManager.selectedAccount,
              let data = prefetcher.data(for: account.characterID) else { return }
        let originSystemId = data.location.solarSystemId
        let uniqueSystemIds = Set(stations.map(\.systemId))

        await withTaskGroup(of: (Int, Int?).self) { group in
            for systemId in uniqueSystemIds {
                group.addTask {
                    if systemId == originSystemId { return (systemId, 0) }
                    do {
                        let route: [Int] = try await ESIClient.shared.fetch(
                            "/route/\(originSystemId)/\(systemId)/",
                            queryItems: [URLQueryItem(name: "flag", value: "shortest")]
                        )
                        return (systemId, max(0, route.count - 1))
                    } catch {
                        return (systemId, nil)
                    }
                }
            }
            for await (systemId, jumps) in group {
                if let jumps {
                    jumpCounts[systemId] = jumps
                }
            }
        }
    }

    // MARK:  Helpers

    private func securityColor(_ value: Double) -> Color {
        switch value {
        case 0.9...: return .cyan
        case 0.7..<0.9: return .green
        case 0.5..<0.7: return .yellow
        case 0.3..<0.5: return .orange
        case 0.1..<0.3: return Color(red: 1, green: 0.5, blue: 0)
        default: return .red
        }
    }

    private func factionColor(_ factionId: Int?) -> Color {
        switch factionId {
        case 500001: return Color(red: 0.35, green: 0.65, blue: 0.90)  // Caldari
        case 500002: return Color(red: 0.85, green: 0.35, blue: 0.25)  // Minmatar
        case 500003: return Color(red: 0.90, green: 0.75, blue: 0.20)  // Amarr
        case 500004: return Color(red: 0.25, green: 0.70, blue: 0.35)  // Gallente
        default: return Color.gray
        }
    }

    private func serviceInfo(_ service: String) -> (label: String, icon: String, color: Color) {
        switch service {
        case "market":                   return ("Market",         "cart.fill",                   .blue)
        case "reprocessing-plant":       return ("Reprocessing",   "arrow.3.trianglepath",        .orange)
        case "repair-facilities":        return ("Repair",         "wrench.and.screwdriver.fill", .green)
        case "fitting":                  return ("Fitting",        "gearshape.2.fill",            .purple)
        case "cloning":                  return ("Cloning",        "person.2.fill",               .pink)
        case "factory", "manufacturing": return ("Manufacturing",  "hammer.fill",                 .yellow)
        case "labratory", "research":    return ("Research",       "flask.fill",                  .cyan)
        case "insurance":                return ("Insurance",      "shield.fill",                 .mint)
        case "docking":                  return ("Docking",        "arrow.down.to.line",          .teal)
        case "office-rental":            return ("Offices",        "building.fill",               .indigo)
        case "loyalty-point-store":      return ("LP Store",       "star.fill",                   Color(red: 0.9, green: 0.75, blue: 0.2))
        case "navy-offices":             return ("Navy",           "flag.fill",                   .red)
        case "security-offices":         return ("Security",       "lock.shield.fill",            .gray)
        case "bounty-missions":          return ("Bounties",       "target",                      .red)
        case "assay-office":             return ("Assay",          "scalemass.fill",              .brown)
        case "storage":                  return ("Storage",        "archivebox.fill",             .gray)
        default:
            let label = service.split(separator: "-").map { $0.capitalized }.joined(separator: " ")
            return (label, "circle.fill", .gray)
        }
    }
}

// MARK:  Data Models

struct StationEntry: Hashable, Equatable {
    let station: ESIStation
    let systemName: String
    let systemId: Int
    let securityStatus: Double
    let constellationName: String

    func hash(into hasher: inout Hasher) { hasher.combine(station.stationId) }
    static func == (lhs: StationEntry, rhs: StationEntry) -> Bool {
        lhs.station.stationId == rhs.station.stationId
    }
}

struct SystemGroup {
    let systemName: String
    let securityStatus: Double
    let stations: [StationEntry]
}

struct ConstellationGroup {
    let constellationName: String
    let systems: [SystemGroup]
}
