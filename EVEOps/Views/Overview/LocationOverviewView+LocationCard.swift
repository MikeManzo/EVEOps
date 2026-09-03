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

extension LocationOverviewView {
    /// Full re-fetch shared by the auto-refresh loop, the ⌘R / palette refresh,
    /// and the manual refresh button. Leaves existing content on screen while it runs.
    func refreshAll() async {
        isRefreshing = true
        defer { isRefreshing = false }
        refreshTick += 1
        async let loc: Void = loadLocations()
        async let act: Void = loadSystemActivity()
        _ = await (loc, act)
        for info in locations {
            await loadCargoValue(characterID: info.characterID)
        }
    }

    // MARK:  Location Card

    func locationCard(_ info: CharacterLocationInfo) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 12) {
                // Character · Location · Ship — single row
                HStack(alignment: .top, spacing: 20) {

                    // Column 1: Character portrait (128×128) · name/corp
                    HStack(alignment: .top, spacing: 10) {

                        // 128×128 character portrait
                        CachedAsyncImage(url: EVEImageURL.characterPortrait(info.characterID, size: 512)) { image in
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
                        CachedAsyncImage(url: info.dockedStation.map { EVEImageURL.typeRender($0.typeId, size: 512) }
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
                        CachedAsyncImage(url: EVEImageURL.typeRender(info.shipTypeId, size: 512)) { phase in
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

                        HStack(alignment: .top, spacing: 8) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(info.shipName)
                                    .font(.headline)
                                    .lineLimit(1)
                                Text(info.shipTypeName)
                                    .font(.callout)
                                    .foregroundStyle(.secondary)

                                if let group = info.shipGroupName {
                                    Text(group)
                                        .font(.caption)
                                        .foregroundStyle(.tertiary)
                                }
                            }

                            if info.shipMass != nil || info.shipVolume != nil || info.shipCapacity != nil {
                                VStack(alignment: .leading, spacing: 6) {
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
                        }
                        }  // end ship info VStack
                    }  // end column 3 HStack
                    .frame(maxWidth: .infinity, alignment: .leading)

                    Divider().frame(height: 132)

                    // Column 4: Cargo value (current ship's hold, priced at Jita)
                    cargoValueColumn(characterID: info.characterID)
                        .frame(width: 172, alignment: .leading)
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

                // Star · Connected Systems · Last Hour (combined row)
                Divider()
                starConnectionsActivitySection(info)

                // Wormhole intel (J-space only)
                if let whInfo = WHSpaceInfo.info(systemId: info.systemId, systemName: info.systemName, regionName: info.regionName) {
                    Divider()
                    wormholeSection(whInfo)
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

    // MARK:  Station Services

    func stationServicesSection(station: ESIStation, services: [String]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "building.2.fill")
                    .foregroundStyle(.teal)
                Text("Station Services")
                    .font(.subheadline.bold())
                if let efficiency = station.reprocessingEfficiency, services.contains("reprocessing-plant") {
                    Spacer()
                    Text("Reprocessing \(efficiency.formatted(.percent.precision(.fractionLength(0))))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            let columns = [GridItem(.adaptive(minimum: 130), alignment: .leading)]
            LazyVGrid(columns: columns, alignment: .leading, spacing: 6) {
                ForEach(services.sorted(), id: \.self) { service in
                    let (label, icon, color) = stationServiceInfo(service)
                    StationServiceBadge(service: service, label: label, icon: icon, color: color, station: station)
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

    func stationServiceInfo(_ service: String) -> (String, String, Color) {
        switch service {
        case "market":                return (String(localized: "Market"), "cart.fill", .blue)
        case "reprocessing-plant":    return (String(localized: "Reprocessing"), "arrow.3.trianglepath", .orange)
        case "repair-facilities":     return (String(localized: "Repair"), "wrench.and.screwdriver.fill", .green)
        case "fitting":               return (String(localized: "Fitting"), "gearshape.2.fill", .purple)
        case "cloning":               return (String(localized: "Cloning"), "person.2.fill", .pink)
        case "factory", "manufacturing": return (String(localized: "Manufacturing"), "hammer.fill", .yellow)
        case "labratory", "research": return (String(localized: "Research"), "flask.fill", .cyan)
        case "insurance":             return (String(localized: "Insurance"), "shield.fill", .mint)
        case "docking":               return (String(localized: "Docking"), "arrow.down.to.line", .teal)
        case "office-rental":         return (String(localized: "Offices"), "building.fill", .indigo)
        case "loyalty-point-store":   return (String(localized: "LP Store"), "star.fill", .yellow)
        case "navy-offices":          return (String(localized: "Navy"), "flag.fill", .red)
        case "security-offices":      return (String(localized: "Security"), "lock.shield.fill", .gray)
        case "bounty-missions":       return (String(localized: "Bounties"), "target", .red)
        case "assay-office":          return (String(localized: "Assay"), "scalemass.fill", .brown)
        case "storage":               return (String(localized: "Storage"), "archivebox.fill", .secondary.opacity(0.8) as Color)
        case "stock-exchange":        return (String(localized: "Exchange"), "arrow.left.arrow.right", .blue)
        default:
            let label = service.split(separator: "-").map { $0.capitalized }.joined(separator: " ")
            return (label, "circle.fill", .secondary)
        }
    }

    // MARK:  System Stations

    func systemStationsSection(_ stations: [ESIStation], characterID: Int) -> some View {
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

}
