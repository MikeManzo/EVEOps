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

private enum SecurityClassFilter: String, CaseIterable {
    case all, highsec, lowsec, nullsec

    var title: LocalizedStringKey {
        switch self {
        case .all:     "All"
        case .highsec: "High"
        case .lowsec:  "Low"
        case .nullsec: "Null"
        }
    }

    func matches(_ security: Double) -> Bool {
        switch self {
        case .all:     return true
        case .highsec: return security >= 0.5
        case .lowsec:  return security > 0.0 && security < 0.5
        case .nullsec: return security <= 0.0
        }
    }
}

struct RegionStationBrowserView: View {
    var onNavigateToMarket: (() -> Void)? = nil

    @Environment(AccountManager.self) private var accountManager
    @Environment(DashboardPrefetcher.self) private var prefetcher
    @Environment(ThemeManager.self) private var themeManager
    private var palette: EVEPalette { themeManager.palette }

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

    var body: some View {
        HStack(spacing: 0) {
            VStack(spacing: 0) {
                filterBar
                Divider()
                contentArea
            }
            .frame(minWidth: 420)

            if let station = selectedStation {
                Divider()
                StationDetailView(entry: station, onNavigateToMarket: onNavigateToMarket)
                    .frame(width: 340)
                    .transition(.move(edge: .trailing).combined(with: .opacity))
            }
        }
        .animation(EVEMotion.snappy, value: selectedStation?.station.stationId)
        .eveScreenHeader("Station Browser", subtitle: stationSubtitle, section: .stationBrowser)
        .task { await loadRegions() }
        .task(id: selectedRegionId) {
            selectedStation = nil
            jumpCounts = [:]
            await loadStations()
            await loadJumpCounts()
        }
    }

    /// "Lonetrek · 449 stations" once the region has loaded.
    private var stationSubtitle: Text? {
        guard let region = selectedRegion?.name, !isLoading, !stations.isEmpty else { return nil }
        return Text("\(region) · \(stations.count) stations")
    }

    // MARK:  Filter Bar

    private var selectedRegion: (id: Int, name: String, factionId: Int?)? {
        availableRegions.first { $0.id == selectedRegionId }
    }

    private var filterBar: some View {
        VStack(alignment: .leading, spacing: EVESpacing.md) {
            HStack(spacing: EVESpacing.md) {
                EVEMenuPicker("Region", selection: $selectedRegionId,
                              options: availableRegions.map { EVEMenuOption($0.id, verbatim: $0.name, systemImage: "map") })
                .disabled(availableRegions.isEmpty)
                .help("Region")

                Picker("Security", selection: $securityFilter) {
                    ForEach(SecurityClassFilter.allCases, id: \.self) { filter in
                        Text(filter.title).tag(filter)
                    }
                }
                .labelsHidden()
                .eveSegmentedPicker()
                .fixedSize()
                .help("Filter by security class")

                searchField
                    .frame(maxWidth: 260)

                Spacer(minLength: 0)

                if !isLoading && !stations.isEmpty {
                    Text("\(filteredStations.count) of \(stations.count)")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                        .help("Stations shown")
                }
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: EVESpacing.sm) {
                    ForEach(StationService.filterKeys.compactMap(StationService.named)) { service in
                        serviceChip(service)
                    }
                    if !selectedServices.isEmpty {
                        Button("Clear") { selectedServices.removeAll() }
                            .buttonStyle(.borderless)
                            .font(.caption)
                    }
                }
            }
            .eveEdgeFade()
        }
        .padding(.horizontal, EVESpacing.xl)
        .padding(.vertical, EVESpacing.md + 2)
        .background(EVESurface.bar)
    }

    private var searchField: some View {
        HStack(spacing: EVESpacing.sm) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField("Search stations or systems", text: $searchText)
                .textFieldStyle(.plain)
            if !searchText.isEmpty {
                Button { searchText = "" } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .accessibilityLabel("Clear")
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, EVESpacing.md)
        .padding(.vertical, 5)
        .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: EVERadius.sm))
    }

    private func serviceChip(_ service: StationService) -> some View {
        let isSelected = selectedServices.contains(service.key)
        return Button {
            if isSelected { selectedServices.remove(service.key) } else { selectedServices.insert(service.key) }
        } label: {
            Label(service.label, systemImage: service.symbol)
                .font(.caption)
                .padding(.horizontal, EVESpacing.md + 2)
                .padding(.vertical, 5)
                .foregroundStyle(isSelected ? AnyShapeStyle(.white) : AnyShapeStyle(.secondary))
                .background(
                    isSelected ? AnyShapeStyle(palette.accent) : AnyShapeStyle(Color.primary.opacity(0.06)),
                    in: Capsule()
                )
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .help(isSelected ? "Remove filter" : "Only stations with this service")
    }

    // MARK:  Content Area

    @ViewBuilder
    private var contentArea: some View {
        if isLoading {
            VStack(spacing: 0) {
                LoadingSkeleton(rows: 8)
                if !loadingProgress.isEmpty {
                    Text(loadingProgress)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.bottom, EVESpacing.lg)
                }
            }
        } else if filteredStations.isEmpty {
            if stations.isEmpty {
                EVEEmptyState("No NPC Stations in This Region", systemImage: "building.2")
            } else if !searchText.isEmpty {
                ContentUnavailableView.search(text: searchText)
            } else {
                EVEEmptyState("No Matching Stations", systemImage: "line.3.horizontal.decrease.circle", message: "Try loosening your filters.")
            }
        } else {
            // No `selection:` binding — see `eveSelectableListRow`: a native List selection
            // is drawn in the static AccentColor, not the faction theme.
            ScrollViewReader { proxy in
                List {
                    ForEach(groupedSystems) { system in
                        Section {
                            ForEach(system.stations, id: \.station.stationId) { entry in
                                StationRow(entry: entry, isSelected: entry == selectedStation)
                                    .eveSelectableListRow(isSelected: entry == selectedStation, palette: palette) {
                                        selectedStation = entry
                                    }
                                    .eveContextMenu(.system(id: entry.systemId, name: entry.systemName))
                                    .id(entry.station.stationId)
                            }
                        } header: {
                            systemHeader(system)
                        }
                    }
                }
                .focusable()
                .focusEffectDisabled()
                .onKeyPress(.downArrow) { moveSelection(by: 1, proxy: proxy) }
                .onKeyPress(.upArrow) { moveSelection(by: -1, proxy: proxy) }
                .onKeyPress(.escape) {
                    guard selectedStation != nil else { return .ignored }
                    selectedStation = nil
                    return .handled
                }
                .listStyle(.inset)
            }
        }
    }

    /// ↑/↓ through the visible stations in display order, keeping the selection on screen.
    private func moveSelection(by delta: Int, proxy: ScrollViewProxy) -> KeyPress.Result {
        let ordered = groupedSystems.flatMap(\.stations)
        guard !ordered.isEmpty else { return .ignored }
        let next: StationEntry
        if let current = selectedStation, let index = ordered.firstIndex(of: current) {
            next = ordered[min(max(index + delta, 0), ordered.count - 1)]
        } else {
            next = delta > 0 ? ordered[0] : ordered[ordered.count - 1]
        }
        selectedStation = next
        proxy.scrollTo(next.station.stationId)
        return .handled
    }

    private func systemHeader(_ system: SystemGroup) -> some View {
        HStack(spacing: EVESpacing.sm) {
            EVESecurityBadge(status: system.securityStatus, compact: true)
            Text(system.systemName)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.primary)
            Text(system.constellationName)
                .font(.caption)
                .foregroundStyle(.tertiary)
            Spacer()
            if let jumps = jumpCounts[system.systemId] {
                if jumps == 0 {
                    Label("You are here", systemImage: "location.fill")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(palette.accent)
                } else {
                    Text("\(jumps) \(jumps == 1 ? "jump" : "jumps")")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }
        }
        .textCase(nil)
        .padding(.vertical, 2)
        .eveContextMenu(.system(id: system.systemId, name: system.systemName))
    }

    // MARK:  Computed filtered/grouped data

    private var filteredStations: [StationEntry] {
        stations.filter { entry in
            let matchesSearch = searchText.isEmpty
                || entry.station.name.localizedCaseInsensitiveContains(searchText)
                || entry.systemName.localizedCaseInsensitiveContains(searchText)
                || (entry.ownerName?.localizedCaseInsensitiveContains(searchText) ?? false)
            let matchesServices = selectedServices.isEmpty
                || selectedServices.isSubset(of: Set(entry.station.services ?? []))
            let matchesSecurity = securityFilter.matches(entry.securityStatus)
            return matchesSearch && matchesServices && matchesSecurity
        }
    }

    /// Stations grouped by system, nearest first once jump counts are known, otherwise
    /// safest first.
    private var groupedSystems: [SystemGroup] {
        let bySystem = Dictionary(grouping: filteredStations, by: \.systemId)
        let groups = bySystem.map { systemId, entries in
            SystemGroup(
                systemId: systemId,
                systemName: entries[0].systemName,
                constellationName: entries[0].constellationName,
                securityStatus: entries[0].securityStatus,
                stations: entries.sorted { $0.station.name < $1.station.name }
            )
        }
        return groups.sorted { a, b in
            switch (jumpCounts[a.systemId], jumpCounts[b.systemId]) {
            case let (ja?, jb?) where ja != jb: return ja < jb
            case (.some, nil): return true
            case (nil, .some): return false
            default:
                if a.securityStatus != b.securityStatus { return a.securityStatus > b.securityStatus }
                return a.systemName < b.systemName
            }
        }
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

        let ownerIds = Array(Set(entries.compactMap(\.station.owner)))
        let owners = ownerIds.isEmpty ? [:] : await NameResolver.shared.resolve(ids: ownerIds)
        for i in entries.indices {
            entries[i].ownerName = entries[i].station.owner.flatMap { owners[$0] }
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

}

// MARK:  Station Row

/// A station in the browser list: the owning corporation's logo as the anchor, the facility
/// as the title, its orbit and owner as the subtitle, and its key services as a quiet
/// trailing glyph strip.
private struct StationRow: View {
    let entry: StationEntry
    let isSelected: Bool

    var body: some View {
        let parts = StationNameParts(stationName: entry.station.name, systemName: entry.systemName)
        HStack(spacing: EVESpacing.md + 2) {
            ownerLogo

            VStack(alignment: .leading, spacing: 1) {
                Text(parts.facility)
                    .font(.body.weight(.medium))
                    .lineLimit(1)
                    .eveTruncationHelp(parts.facility)
                Text(subtitle(orbit: parts.orbit))
                    .font(.caption)
                    .foregroundStyle(isSelected ? AnyShapeStyle(.white.opacity(0.8)) : AnyShapeStyle(.secondary))
                    .lineLimit(1)
                    .eveTruncationHelp(subtitle(orbit: parts.orbit))
            }

            Spacer(minLength: EVESpacing.md)

            HStack(spacing: EVESpacing.sm) {
                ForEach(StationService.keyServices(of: entry.station.services)) { service in
                    Image(systemName: service.symbol)
                        .font(.eveCaption)
                        .frame(width: 14)
                        .help(Text(service.label))
                }
            }
            .foregroundStyle(isSelected ? AnyShapeStyle(.white.opacity(0.85)) : AnyShapeStyle(.tertiary))
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text("Services"))
        }
        .eveRowPadding()
        .accessibilityElement(children: .combine)
    }

    private func subtitle(orbit: String) -> String {
        [orbit, entry.ownerName ?? ""].filter { !$0.isEmpty }.joined(separator: " · ")
    }

    @ViewBuilder
    private var ownerLogo: some View {
        let url = entry.station.owner.flatMap { EVEImageURL.corporationLogo($0, size: 64) }
            ?? EVEImageURL.typeIcon(entry.station.typeId, size: 64)
        CachedAsyncImage(url: url) { image in
            image.resizable().interpolation(.high)
        } placeholder: {
            RoundedRectangle(cornerRadius: EVERadius.sm).fill(.quaternary)
        }
        .frame(width: 30, height: 30)
        .clipShape(RoundedRectangle(cornerRadius: EVERadius.sm))
        .overlay(RoundedRectangle(cornerRadius: EVERadius.sm).strokeBorder(.primary.opacity(0.08), lineWidth: 0.5))
        .accessibilityHidden(true)
    }
}

// MARK:  Data Models

struct StationEntry: Hashable, Equatable {
    let station: ESIStation
    let systemName: String
    let systemId: Int
    let securityStatus: Double
    let constellationName: String
    /// Resolved name of the owning NPC corporation, filled in after load.
    var ownerName: String? = nil

    func hash(into hasher: inout Hasher) { hasher.combine(station.stationId) }
    static func == (lhs: StationEntry, rhs: StationEntry) -> Bool {
        lhs.station.stationId == rhs.station.stationId
    }
}

struct SystemGroup: Identifiable {
    let systemId: Int
    let systemName: String
    let constellationName: String
    let securityStatus: Double
    let stations: [StationEntry]

    var id: Int { systemId }
}
