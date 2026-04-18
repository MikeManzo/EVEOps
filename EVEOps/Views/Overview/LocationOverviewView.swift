import SwiftUI

struct LocationOverviewView: View {
    @Environment(AccountManager.self) private var accountManager
    @Environment(DashboardPrefetcher.self) private var prefetcher
    @AppStorage("backgroundPollInterval") private var pollInterval: Double = 300
    @State private var locations: [CharacterLocationInfo] = []
    @State private var isLoading = false
    @State private var error: String?
    @State private var lastRefresh: Date?
    @State private var refreshTick = 0
    @State private var stationsExpanded: [Int: Bool] = [:]

    var body: some View {
        LoadingStateView(isLoading: isLoading, error: error, isEmpty: locations.isEmpty, emptyMessage: "No location data") {
            ScrollView {
                VStack(spacing: 16) {
                    ForEach(locations, id: \.characterID) { info in
                        locationCard(info)
                    }
                }
                .padding()
            }
        }
        .navigationTitle("Location Overview")
        .toolbar {
            ToolbarItem(placement: .automatic) {
                if let lastRefresh {
                    Text("Updated \(lastRefresh, style: .relative) ago")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .task {
            if buildFromPrefetcher() { return }
            isLoading = true
            await loadLocations()
        }
        .task(id: pollInterval) {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(pollInterval))
                refreshTick += 1
                await loadLocations()
            }
        }
    }

    // MARK: - Location Card

    private func locationCard(_ info: CharacterLocationInfo) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 12) {
                // Character · Location · Ship — single row
                HStack(alignment: .top, spacing: 20) {

                    // Column 1: Character portrait (128×128) · name/corp
                    HStack(alignment: .top, spacing: 10) {

                        // 128×128 character portrait
                        AsyncImage(url: EVEImageURL.characterPortrait(info.characterID, size: 256)) { image in
                            image.resizable()
                        } placeholder: {
                            RoundedRectangle(cornerRadius: 10).fill(.quaternary)
                        }
                        .frame(width: 128, height: 128)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(.separator, lineWidth: 1))

                        // Name + corp + online status
                        VStack(alignment: .leading, spacing: 2) {
                            HStack(spacing: 6) {
                                Circle()
                                    .fill(info.isOnline ? .green : .gray)
                                    .frame(width: 8, height: 8)
                                Text(info.characterName)
                                    .font(.headline)
                                    .lineLimit(1)
                            }
                            Text(info.corporationName)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                            Text(info.isOnline ? "Online" : "Offline")
                                .font(.caption2.bold())
                                .foregroundStyle(info.isOnline ? .green : .secondary)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(
                                    (info.isOnline ? Color.green : Color.gray).opacity(0.15),
                                    in: Capsule()
                                )
                            if info.lastLogin != nil || info.lastLogout != nil || info.loginCount != nil {
                                VStack(alignment: .leading, spacing: 2) {
                                    if let login = info.lastLogin {
                                        HStack(spacing: 4) {
                                            Text("Login:")
                                                .font(.caption2)
                                                .foregroundStyle(.tertiary)
                                            Text(login, style: .relative)
                                                .font(.caption2.monospacedDigit())
                                                .foregroundStyle(.secondary)
                                            Text("ago")
                                                .font(.caption2)
                                                .foregroundStyle(.tertiary)
                                        }
                                    }
                                    if let logout = info.lastLogout {
                                        HStack(spacing: 4) {
                                            Text("Logout:")
                                                .font(.caption2)
                                                .foregroundStyle(.tertiary)
                                            Text(logout, style: .relative)
                                                .font(.caption2.monospacedDigit())
                                                .foregroundStyle(.secondary)
                                            Text("ago")
                                                .font(.caption2)
                                                .foregroundStyle(.tertiary)
                                        }
                                    }
                                    if let logins = info.loginCount {
                                        HStack(spacing: 4) {
                                            Text("Total:")
                                                .font(.caption2)
                                                .foregroundStyle(.tertiary)
                                            Text("\(logins) logins")
                                                .font(.caption2.monospacedDigit())
                                                .foregroundStyle(.secondary)
                                        }
                                    }
                                }
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    Divider().frame(height: 132)

                    // Column 2: Station image + location info
                    HStack(alignment: .top, spacing: 10) {
                        // 128×128 station render (ship render when in space)
                        AsyncImage(url: info.dockedStation.map { EVEImageURL.typeRender($0.typeId, size: 512) }
                                        ?? EVEImageURL.typeRender(info.shipTypeId, size: 512)) { phase in
                            if let image = phase.image {
                                image.resizable()
                                    .aspectRatio(contentMode: .fill)
                                    .frame(width: 128, height: 128)
                                    .clipShape(RoundedRectangle(cornerRadius: 10))
                            } else {
                                RoundedRectangle(cornerRadius: 10)
                                    .fill(.quaternary)
                                    .frame(width: 128, height: 128)
                            }
                        }

                        VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Image(systemName: "location.fill")
                                .foregroundStyle(.blue)
                            Text("Location")
                                .font(.subheadline.bold())
                        }

                        VStack(alignment: .leading, spacing: 4) {
                            HStack(spacing: 6) {
                                Text(info.systemName)
                                    .font(.body.bold())
                                securityBadge(info.securityValue)
                            }

                            if let constellation = info.constellationName {
                                infoRow(label: "Constellation", value: constellation)
                            }

                            if let region = info.regionName {
                                infoRow(label: "Region", value: region)
                            }

                            if let docked = info.dockedAt {
                                HStack(spacing: 4) {
                                    Image(systemName: "building.2.fill")
                                        .font(.caption)
                                        .foregroundStyle(.teal)
                                    Text(docked)
                                        .font(.caption)
                                        .foregroundStyle(.teal)
                                }
                            } else {
                                HStack(spacing: 4) {
                                    Image(systemName: "airplane")
                                        .font(.caption)
                                        .foregroundStyle(.orange)
                                    Text("In space")
                                        .font(.caption)
                                        .foregroundStyle(.orange)
                                }
                            }
                        }
                        }  // end location VStack
                    }  // end column 2 HStack
                    .frame(maxWidth: .infinity, alignment: .leading)

                    Divider().frame(height: 132)

                    // Column 3: Ship icon (128×128) + ship info
                    HStack(alignment: .top, spacing: 10) {
                        AsyncImage(url: EVEImageURL.typeIcon(info.shipTypeId, size: 256)) { phase in
                            if let image = phase.image {
                                image.resizable()
                                    .frame(width: 128, height: 128)
                                    .clipShape(RoundedRectangle(cornerRadius: 10))
                            } else {
                                RoundedRectangle(cornerRadius: 10)
                                    .fill(.quaternary)
                                    .frame(width: 128, height: 128)
                            }
                        }

                        VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Image(systemName: "airplane")
                                .foregroundStyle(.purple)
                            Text("Ship")
                                .font(.subheadline.bold())
                        }

                        VStack(alignment: .leading, spacing: 3) {
                            Text(info.shipName)
                                .font(.body.bold())
                                .lineLimit(1)
                            Text(info.shipTypeName)
                                .font(.caption)
                                .foregroundStyle(.secondary)

                            if let group = info.shipGroupName {
                                Text(group)
                                    .font(.caption2)
                                    .foregroundStyle(.tertiary)
                            }
                        }

                        // Ship attributes
                        if info.shipMass != nil || info.shipVolume != nil || info.shipCapacity != nil {
                            HStack(spacing: 12) {
                                if let mass = info.shipMass, mass > 0 {
                                    shipStat(label: "Mass", value: formatLarge(mass) + " kg")
                                }
                                if let volume = info.shipVolume, volume > 0 {
                                    shipStat(label: "Volume", value: String(format: "%.0f m\u{00B3}", volume))
                                }
                                if let capacity = info.shipCapacity, capacity > 0 {
                                    shipStat(label: "Cargo", value: String(format: "%.0f m\u{00B3}", capacity))
                                }
                            }
                        }
                        }  // end ship info VStack
                    }  // end column 3 HStack
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                // Docked station services
                if let station = info.dockedStation, let services = station.services, !services.isEmpty {
                    Divider()
                    stationServicesSection(station: station, services: services)
                }

                // Stations in system (when in space)
                if info.dockedAt == nil && !info.systemStations.isEmpty {
                    Divider()
                    systemStationsSection(info.systemStations, characterID: info.characterID)
                }

                // Star info
                if info.starName != nil {
                    Divider()
                    starInfoSection(info)
                }

                // Nearby systems
                if !info.nearbySystems.isEmpty {
                    Divider()
                    nearbySystemsSection(info)
                }

                // Constellation star map
                Divider()

                ConstellationMapView(
                    constellationId: info.constellationId,
                    currentSystemId: info.systemId,
                    constellationName: info.constellationName ?? "Constellation"
                )
            }
            .padding(12)
        }
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - Station Services

    private func stationServicesSection(station: ESIStation, services: [String]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "building.2.fill")
                    .foregroundStyle(.teal)
                Text("Station Services")
                    .font(.subheadline.bold())
                if let efficiency = station.reprocessingEfficiency, services.contains("reprocessing-plant") {
                    Spacer()
                    Text(String(format: "Reprocessing %.0f%%", efficiency * 100))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            let columns = [GridItem(.adaptive(minimum: 130), alignment: .leading)]
            LazyVGrid(columns: columns, alignment: .leading, spacing: 6) {
                ForEach(services.sorted(), id: \.self) { service in
                    stationServiceBadge(service)
                }
            }

            if let cost = station.officeRentalCost, cost > 0 {
                HStack(spacing: 4) {
                    Text("Office Rental:")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                    Text(EVEFormatters.iskFormatter.string(from: NSNumber(value: cost)) ?? "\(Int(cost))")
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.secondary)
                    Text("ISK/wk")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
        }
    }

    private func stationServiceBadge(_ service: String) -> some View {
        let (label, icon, color) = stationServiceInfo(service)
        return HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.caption2)
                .foregroundStyle(color)
            Text(label)
                .font(.caption)
                .foregroundStyle(.primary)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(color.opacity(0.12), in: Capsule())
    }

    private func stationServiceInfo(_ service: String) -> (String, String, Color) {
        switch service {
        case "market":                return ("Market", "cart.fill", .blue)
        case "reprocessing-plant":    return ("Reprocessing", "arrow.3.trianglepath", .orange)
        case "repair-facilities":     return ("Repair", "wrench.and.screwdriver.fill", .green)
        case "fitting":               return ("Fitting", "gearshape.2.fill", .purple)
        case "cloning":               return ("Cloning", "person.2.fill", .pink)
        case "factory", "manufacturing": return ("Manufacturing", "hammer.fill", .yellow)
        case "labratory", "research": return ("Research", "flask.fill", .cyan)
        case "insurance":             return ("Insurance", "shield.fill", .mint)
        case "docking":               return ("Docking", "arrow.down.to.line", .teal)
        case "office-rental":         return ("Offices", "building.fill", .indigo)
        case "loyalty-point-store":   return ("LP Store", "star.fill", .yellow)
        case "navy-offices":          return ("Navy", "flag.fill", .red)
        case "security-offices":      return ("Security", "lock.shield.fill", .gray)
        case "bounty-missions":       return ("Bounties", "target", .red)
        case "assay-office":          return ("Assay", "scalemass.fill", .brown)
        case "storage":               return ("Storage", "archivebox.fill", .secondary.opacity(0.8) as Color)
        case "stock-exchange":        return ("Exchange", "arrow.left.arrow.right", .blue)
        default:
            let label = service.split(separator: "-").map { $0.capitalized }.joined(separator: " ")
            return (label, "circle.fill", .secondary)
        }
    }

    // MARK: - System Stations

    private func systemStationsSection(_ stations: [ESIStation], characterID: Int) -> some View {
        let isExpanded = Binding(
            get: { stationsExpanded[characterID, default: false] },
            set: { stationsExpanded[characterID] = $0 }
        )
        return DisclosureGroup(isExpanded: isExpanded) {
            VStack(alignment: .leading, spacing: 6) {
                ForEach(stations, id: \.stationId) { station in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(station.name)
                            .font(.caption.bold())
                            .lineLimit(1)
                        if let services = station.services, !services.isEmpty {
                            let columns = [GridItem(.adaptive(minimum: 120), alignment: .leading)]
                            LazyVGrid(columns: columns, alignment: .leading, spacing: 4) {
                                ForEach(services.sorted(), id: \.self) { service in
                                    let (label, icon, color) = stationServiceInfo(service)
                                    HStack(spacing: 3) {
                                        Image(systemName: icon)
                                            .font(.system(size: 9))
                                            .foregroundStyle(color)
                                        Text(label)
                                            .font(.system(size: 10))
                                            .foregroundStyle(.secondary)
                                    }
                                }
                            }
                        }
                    }
                    .padding(.vertical, 4)
                    if station.stationId != stations.last?.stationId {
                        Divider()
                    }
                }
            }
            .padding(.top, 4)
        } label: {
            HStack {
                Image(systemName: "building.2.fill")
                    .foregroundStyle(.teal)
                Text("Stations in System")
                    .font(.subheadline.bold())
                Text("(\(stations.count))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Star Info

    private func starInfoSection(_ info: CharacterLocationInfo) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "sun.max.fill")
                    .foregroundStyle(starColor(info.starSpectralClass))
                Text("Star")
                    .font(.subheadline.bold())
            }

            HStack(spacing: 16) {
                // Star icon glow
                ZStack {
                    Circle()
                        .fill(starColor(info.starSpectralClass).opacity(0.2))
                        .frame(width: 48, height: 48)
                    Circle()
                        .fill(starColor(info.starSpectralClass))
                        .frame(width: 28, height: 28)
                }

                VStack(alignment: .leading, spacing: 4) {
                    if let name = info.starName {
                        Text(name)
                            .font(.body.bold())
                    }
                    if let spectral = info.starSpectralClass {
                        HStack(spacing: 6) {
                            Text("Class \(spectral)")
                                .font(.caption.bold())
                                .foregroundStyle(starColor(spectral))
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(starColor(spectral).opacity(0.15), in: Capsule())
                            Text(spectralDescription(spectral))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 4) {
                    if let temp = info.starTemperature {
                        starStat(label: "Temperature", value: "\(temp.formatted()) K")
                    }
                    if let radius = info.starRadius {
                        starStat(label: "Radius", value: formatLarge(Double(radius)) + " km")
                    }
                    if let lum = info.starLuminosity {
                        starStat(label: "Luminosity", value: String(format: "%.4f L☉", lum))
                    }
                    if let age = info.starAge {
                        starStat(label: "Age", value: formatLarge(Double(age)) + " yrs")
                    }
                }
            }
        }
    }

    private func starStat(label: String, value: String) -> some View {
        HStack(spacing: 4) {
            Text(label)
                .font(.caption2)
                .foregroundStyle(.tertiary)
            Text(value)
                .font(.caption2.monospacedDigit())
                .foregroundStyle(.secondary)
        }
    }

    private func starColor(_ spectralClass: String?) -> Color {
        guard let sc = spectralClass?.prefix(1).uppercased() else { return .yellow }
        switch sc {
        case "O": return .blue
        case "B": return Color(red: 0.6, green: 0.7, blue: 1.0)
        case "A": return .white
        case "F": return Color(red: 1.0, green: 1.0, blue: 0.8)
        case "G": return .yellow
        case "K": return .orange
        case "M": return .red
        default: return .yellow
        }
    }

    private func spectralDescription(_ spectralClass: String) -> String {
        switch spectralClass.prefix(1).uppercased() {
        case "O": return "Blue giant"
        case "B": return "Blue-white"
        case "A": return "White"
        case "F": return "Yellow-white"
        case "G": return "Yellow (Sun-like)"
        case "K": return "Orange"
        case "M": return "Red dwarf"
        default: return ""
        }
    }

    // MARK: - Nearby Systems

    private func nearbySystemsSection(_ info: CharacterLocationInfo) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "arrow.triangle.branch")
                    .foregroundStyle(.purple)
                Text("Connected Systems")
                    .font(.subheadline.bold())
                Text("(\(info.nearbySystems.count) gate\(info.nearbySystems.count == 1 ? "" : "s"))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            let columns = [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())]
            LazyVGrid(columns: columns, alignment: .leading, spacing: 6) {
                ForEach(info.nearbySystems, id: \.systemId) { sys in
                    HStack(spacing: 6) {
                        Circle()
                            .fill(securityColor(sys.securityStatus))
                            .frame(width: 8, height: 8)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(sys.name)
                                .font(.caption.bold())
                                .lineLimit(1)
                            HStack(spacing: 4) {
                                Text(String(format: "%.1f", sys.securityStatus))
                                    .font(.caption2.monospacedDigit())
                                    .foregroundStyle(securityColor(sys.securityStatus))
                                if sys.isExternal {
                                    Text("ext")
                                        .font(.system(size: 8))
                                        .foregroundStyle(.orange)
                                        .padding(.horizontal, 3)
                                        .padding(.vertical, 1)
                                        .background(.orange.opacity(0.15), in: Capsule())
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    // MARK: - Helpers

    private func securityBadge(_ value: Double) -> some View {
        Text(String(format: "%.1f", value))
            .font(.caption.bold().monospacedDigit())
            .foregroundStyle(securityColor(value))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(securityColor(value).opacity(0.15), in: Capsule())
    }

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

    private func infoRow(label: String, value: String) -> some View {
        HStack(spacing: 6) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.tertiary)
                .frame(width: 80, alignment: .trailing)
            Text(value)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func shipStat(label: String, value: String) -> some View {
        VStack(spacing: 1) {
            Text(label)
                .font(.caption2)
                .foregroundStyle(.tertiary)
            Text(value)
                .font(.caption2.monospacedDigit())
                .foregroundStyle(.secondary)
        }
    }

    private func formatLarge(_ value: Double) -> String {
        if value >= 1_000_000_000 {
            return String(format: "%.1fB", value / 1_000_000_000)
        } else if value >= 1_000_000 {
            return String(format: "%.1fM", value / 1_000_000)
        } else if value >= 1_000 {
            return String(format: "%.1fK", value / 1_000)
        }
        return String(format: "%.0f", value)
    }

    // MARK: - Prefetcher Fast Path

    private func buildFromPrefetcher() -> Bool {
        var data: [CharacterLocationInfo] = []
        for account in accountManager.accounts {
            guard let prefetched = prefetcher.data(for: account.characterID) else { return false }
            guard let systemInfo = prefetcher.resolvedSystems[prefetched.location.solarSystemId] else { return false }

            let constellation = prefetcher.resolvedConstellations[systemInfo.constellationId]
            let shipType = prefetcher.resolvedTypes[prefetched.ship.shipTypeId]
            var regionName: String?
            if let cId = constellation?.regionId {
                regionName = prefetcher.resolvedRegions[cId]?.name
            }
            var shipGroupName: String?
            if let gId = shipType?.groupId {
                shipGroupName = prefetcher.resolvedGroups[gId]?.name
            }

            data.append(CharacterLocationInfo(
                characterID: account.characterID,
                characterName: account.characterName,
                corporationName: account.corporationName,
                isOnline: prefetched.online.online,
                lastLogin: prefetched.online.lastLogin,
                lastLogout: prefetched.online.lastLogout,
                loginCount: prefetched.online.logins,
                systemId: prefetched.location.solarSystemId,
                constellationId: systemInfo.constellationId,
                systemName: systemInfo.name,
                securityValue: systemInfo.securityStatus,
                constellationName: constellation?.name,
                regionName: regionName,
                dockedAt: nil,  // Resolved in background refresh
                dockedStation: nil,
                systemStations: [],
                shipName: prefetched.ship.shipName,
                shipTypeName: shipType?.name ?? "Unknown",
                shipTypeId: prefetched.ship.shipTypeId,
                shipGroupName: shipGroupName,
                shipMass: shipType?.mass,
                shipVolume: shipType?.volume,
                shipCapacity: shipType?.capacity,
                starName: nil,
                starSpectralClass: nil,
                starTemperature: nil,
                starRadius: nil,
                starLuminosity: nil,
                starAge: nil,
                starTypeId: nil,
                nearbySystems: []  // Resolved in background refresh
            ))
        }
        locations = data
        lastRefresh = Date()
        // Kick off background enrichment for star/nearby/docked data
        Task { await loadLocations() }
        return !data.isEmpty
    }

    // MARK: - Data Loading

    private func loadLocations() async {
        if locations.isEmpty { isLoading = true }
        error = nil
        var data: [CharacterLocationInfo] = []
        var lastError: Error?
        for account in accountManager.accounts {
            do {
                let token = try await accountManager.validToken(for: account)

                async let fetchLocation: ESICharacterLocation = ESIClient.shared.fetch(
                    "/characters/\(account.characterID)/location/", token: token
                )
                async let fetchShip: ESICharacterShip = ESIClient.shared.fetch(
                    "/characters/\(account.characterID)/ship/", token: token
                )
                async let fetchOnline: ESICharacterOnline = ESIClient.shared.fetch(
                    "/characters/\(account.characterID)/online/", token: token
                )

                let (location, ship, online) = try await (fetchLocation, fetchShip, fetchOnline)

                // System → Constellation → Region chain (via UniverseCache)
                guard let systemInfo = await UniverseCache.shared.solarSystem(id: location.solarSystemId) else {
                    continue
                }

                async let fetchConstellation = UniverseCache.shared.constellation(id: systemInfo.constellationId)
                async let fetchShipType = UniverseCache.shared.type(id: ship.shipTypeId)

                let constellation = await fetchConstellation
                let shipType = await fetchShipType

                var region: ESIRegion?
                if let cId = constellation?.regionId {
                    region = await UniverseCache.shared.region(id: cId)
                }

                // Ship group name
                var shipGroup: ESIGroup?
                if let gId = shipType?.groupId {
                    shipGroup = await UniverseCache.shared.group(id: gId)
                }

                // Star info
                var star: ESIStar?
                if let starId = systemInfo.starId {
                    star = await UniverseCache.shared.star(id: starId)
                }

                // Nearby systems via stargates (ESIClient cache handles repeat fetches)
                var nearbySystems: [NearbySystem] = []
                if let gateIds = systemInfo.stargates, !gateIds.isEmpty {
                    let gates = await withTaskGroup(of: ESIStargate?.self) { group in
                        for gateId in gateIds {
                            group.addTask {
                                try? await ESIClient.shared.fetch("/universe/stargates/\(gateId)/") as ESIStargate
                            }
                        }
                        var results: [ESIStargate] = []
                        for await gate in group {
                            if let g = gate { results.append(g) }
                        }
                        return results
                    }
                    let destIds = gates.map(\.destination.systemId)
                    let constellationSystems = Set(constellation?.systems ?? [])
                    // Batch-fetch destination systems via UniverseCache
                    let destSystems = await withTaskGroup(of: ESISolarSystem?.self) { group in
                        for destId in destIds {
                            group.addTask {
                                await UniverseCache.shared.solarSystem(id: destId)
                            }
                        }
                        var results: [ESISolarSystem] = []
                        for await sys in group {
                            if let s = sys { results.append(s) }
                        }
                        return results
                    }
                    for dest in destSystems {
                        nearbySystems.append(NearbySystem(
                            systemId: dest.systemId,
                            name: dest.name,
                            securityStatus: dest.securityStatus,
                            isExternal: !constellationSystems.contains(dest.systemId)
                        ))
                    }
                    nearbySystems.sort { $0.securityStatus > $1.securityStatus }
                }

                // Docked location
                var dockedAt: String?
                var dockedStation: ESIStation?
                if let stationId = location.stationId {
                    let station = await UniverseCache.shared.station(id: stationId)
                    dockedStation = station
                    dockedAt = station?.name
                } else if let structureId = location.structureId {
                    if let structure: ESIStructure = try? await ESIClient.shared.fetch(
                        "/universe/structures/\(structureId)/", token: token
                    ) {
                        dockedAt = structure.name
                    } else {
                        dockedAt = "Player Structure"
                    }
                }

                // Stations in current system
                let systemStations: [ESIStation]
                if let stationIds = systemInfo.stations, !stationIds.isEmpty {
                    systemStations = await withTaskGroup(of: ESIStation?.self) { group in
                        for sid in stationIds {
                            group.addTask { await UniverseCache.shared.station(id: sid) }
                        }
                        var results: [ESIStation] = []
                        for await s in group { if let s { results.append(s) } }
                        return results.sorted { $0.name < $1.name }
                    }
                } else {
                    systemStations = []
                }

                data.append(CharacterLocationInfo(
                    characterID: account.characterID,
                    characterName: account.characterName,
                    corporationName: account.corporationName,
                    isOnline: online.online,
                    lastLogin: online.lastLogin,
                    lastLogout: online.lastLogout,
                    loginCount: online.logins,
                    systemId: location.solarSystemId,
                    constellationId: systemInfo.constellationId,
                    systemName: systemInfo.name,
                    securityValue: systemInfo.securityStatus,
                    constellationName: constellation?.name,
                    regionName: region?.name,
                    dockedAt: dockedAt,
                    dockedStation: dockedStation,
                    systemStations: systemStations,
                    shipName: ship.shipName,
                    shipTypeName: shipType?.name ?? "Unknown",
                    shipTypeId: ship.shipTypeId,
                    shipGroupName: shipGroup?.name,
                    shipMass: shipType?.mass,
                    shipVolume: shipType?.volume,
                    shipCapacity: shipType?.capacity,
                    starName: star?.name,
                    starSpectralClass: star?.spectralClass,
                    starTemperature: star?.temperature,
                    starRadius: star?.radius,
                    starLuminosity: star?.luminosity,
                    starAge: star?.age,
                    starTypeId: star?.typeId,
                    nearbySystems: nearbySystems
                ))
            } catch {
                lastError = error
            }
        }
        locations = data
        if data.isEmpty, let lastError {
            self.error = lastError.localizedDescription
        }
        lastRefresh = Date()
        isLoading = false
    }
}

// MARK: - Data Model

struct CharacterLocationInfo {
    let characterID: Int
    let characterName: String
    let corporationName: String
    let isOnline: Bool
    let lastLogin: Date?
    let lastLogout: Date?
    let loginCount: Int?
    let systemId: Int
    let constellationId: Int
    let systemName: String
    let securityValue: Double
    let constellationName: String?
    let regionName: String?
    let dockedAt: String?
    let dockedStation: ESIStation?
    let systemStations: [ESIStation]
    let shipName: String
    let shipTypeName: String
    let shipTypeId: Int
    let shipGroupName: String?
    let shipMass: Double?
    let shipVolume: Double?
    let shipCapacity: Double?
    // Star info
    let starName: String?
    let starSpectralClass: String?
    let starTemperature: Int?
    let starRadius: Int?
    let starLuminosity: Double?
    let starAge: Int?
    let starTypeId: Int?
    // Nearby connected systems
    let nearbySystems: [NearbySystem]
}

struct NearbySystem {
    let systemId: Int
    let name: String
    let securityStatus: Double
    let isExternal: Bool // outside current constellation
}
