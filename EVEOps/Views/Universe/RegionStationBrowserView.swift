import SwiftUI

struct RegionStationBrowserView: View {
    @Environment(AccountManager.self) private var accountManager
    @Environment(DashboardPrefetcher.self) private var prefetcher

    @State private var selectedRegionId: Int = 10000002  // The Forge (Jita)
    @State private var availableRegions: [(id: Int, name: String, factionId: Int?)] = []
    @State private var stations: [StationEntry] = []
    @State private var isLoading = false
    @State private var loadingProgress = ""
    @State private var searchText = ""
    @State private var selectedServices: Set<String> = []

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
        VStack(spacing: 0) {
            filterBar
            Divider()
            contentArea
        }
        .navigationTitle("Station Browser")
        .task { await loadRegions() }
        .task(id: selectedRegionId) { await loadStations() }
    }

    // MARK: - Filter Bar

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
                .frame(maxWidth: 300)

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

    // MARK: - Content Area

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
            List {
                ForEach(groupedStations, id: \.constellationName) { group in
                    Section {
                        ForEach(group.systems, id: \.systemName) { sys in
                            systemBlock(sys)
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

    // MARK: - System Block

    private func systemBlock(_ sys: SystemGroup) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            // System header
            HStack(spacing: 6) {
                Circle()
                    .fill(securityColor(sys.securityStatus))
                    .frame(width: 8, height: 8)
                Text(sys.systemName)
                    .font(.subheadline.bold())
                Text(String(format: "%.1f", sys.securityStatus))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(securityColor(sys.securityStatus))
                Spacer()
                Text("\(sys.stations.count) station\(sys.stations.count == 1 ? "" : "s")")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }

            // Station rows
            ForEach(sys.stations, id: \.station.stationId) { entry in
                stationRow(entry.station)
                    .padding(.leading, 14)
            }
        }
        .padding(.vertical, 4)
    }

    private func stationRow(_ station: ESIStation) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(station.name)
                .font(.body)
                .lineLimit(1)

            if let services = station.services, !services.isEmpty {
                let columns = [GridItem(.adaptive(minimum: 115), alignment: .leading)]
                LazyVGrid(columns: columns, alignment: .leading, spacing: 4) {
                    ForEach(services.sorted(), id: \.self) { service in
                        let info = serviceInfo(service)
                        HStack(spacing: 3) {
                            Image(systemName: info.icon)
                                .font(.system(size: 9))
                                .foregroundStyle(info.color)
                            Text(info.label)
                                .font(.system(size: 10))
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }

            HStack(spacing: 12) {
                if let efficiency = station.reprocessingEfficiency,
                   station.services?.contains("reprocessing-plant") == true {
                    Text(String(format: "Reprocessing %.0f%%", efficiency * 100))
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
                if let cost = station.officeRentalCost, cost > 0 {
                    Text(String(format: "Office %.0f ISK/wk", cost))
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .padding(.vertical, 2)
    }

    // MARK: - Computed filtered/grouped data

    private var filteredStations: [StationEntry] {
        stations.filter { entry in
            let matchesSearch = searchText.isEmpty ||
                entry.station.name.localizedCaseInsensitiveContains(searchText)
            let matchesServices = selectedServices.isEmpty ||
                selectedServices.isSubset(of: Set(entry.station.services ?? []))
            return matchesSearch && matchesServices
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

    // MARK: - Data Loading

    private func loadRegions() async {
        guard availableRegions.isEmpty else { return }
        availableRegions = await UniverseCache.shared.knownSpaceRegions()

        // Default to character's current region
        if let account = accountManager.selectedAccount,
           let data = prefetcher.data(for: account.characterID),
           let system = await UniverseCache.shared.solarSystem(id: data.location.solarSystemId),
           let constellation = await UniverseCache.shared.constellation(id: system.constellationId) {
            let regionId = constellation.regionId
            if availableRegions.contains(where: { $0.id == regionId }) {
                selectedRegionId = regionId
            }
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

    // MARK: - Helpers

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
        case "market":                return ("Market",         "cart.fill",                   .blue)
        case "reprocessing-plant":    return ("Reprocessing",   "arrow.3.trianglepath",        .orange)
        case "repair-facilities":     return ("Repair",         "wrench.and.screwdriver.fill", .green)
        case "fitting":               return ("Fitting",        "gearshape.2.fill",            .purple)
        case "cloning":               return ("Cloning",        "person.2.fill",               .pink)
        case "factory", "manufacturing": return ("Manufacturing","hammer.fill",                .yellow)
        case "labratory", "research": return ("Research",       "flask.fill",                  .cyan)
        case "insurance":             return ("Insurance",      "shield.fill",                 .mint)
        case "docking":               return ("Docking",        "arrow.down.to.line",          .teal)
        case "office-rental":         return ("Offices",        "building.fill",               .indigo)
        case "loyalty-point-store":   return ("LP Store",       "star.fill",                   Color(red: 0.9, green: 0.75, blue: 0.2))
        case "navy-offices":          return ("Navy",           "flag.fill",                   .red)
        case "security-offices":      return ("Security",       "lock.shield.fill",            .gray)
        case "bounty-missions":       return ("Bounties",       "target",                      .red)
        case "assay-office":          return ("Assay",          "scalemass.fill",              .brown)
        case "storage":               return ("Storage",        "archivebox.fill",             .gray)
        default:
            let label = service.split(separator: "-").map { $0.capitalized }.joined(separator: " ")
            return (label, "circle.fill", .gray)
        }
    }
}

// MARK: - Data Models

private struct StationEntry {
    let station: ESIStation
    let systemName: String
    let systemId: Int
    let securityStatus: Double
    let constellationName: String
}

private struct SystemGroup {
    let systemName: String
    let securityStatus: Double
    let stations: [StationEntry]
}

private struct ConstellationGroup {
    let constellationName: String
    let systems: [SystemGroup]
}
