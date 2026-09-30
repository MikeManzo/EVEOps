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
            VStack(alignment: .leading, spacing: EVESpacing.lg) {
                // Character · Location · Ship — single row
                HStack(alignment: .top, spacing: 20) {

                    // Column 1: Character portrait (128×128) · name/corp
                    HStack(alignment: .top, spacing: 10) {

                        // 128×128 character portrait
                        CachedAsyncImage(url: EVEImageURL.characterPortrait(info.characterID, size: 512)) { image in
                            image.resizable()
                        } placeholder: {
                            RoundedRectangle(cornerRadius: EVERadius.lg).fill(.quaternary)
                        }
                        .frame(width: 128, height: 128)
                        .clipShape(RoundedRectangle(cornerRadius: EVERadius.lg))
                        .evePortraitRing(cornerRadius: EVERadius.lg, accent: palette.location)

                        // Name + corp + online status
                        VStack(alignment: .leading, spacing: EVESpacing.xxs) {
                            HStack(spacing: EVESpacing.sm) {
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
                                .padding(.horizontal, EVESpacing.sm)
                                .padding(.vertical, EVESpacing.xxs)
                                .background(
                                    (info.isOnline ? Color.green : Color.gray).opacity(0.15),
                                    in: Capsule()
                                )
                            if info.lastLogin != nil || info.lastLogout != nil || info.loginCount != nil {
                                VStack(alignment: .leading, spacing: EVESpacing.xxs) {
                                    if let login = info.lastLogin {
                                        HStack(spacing: EVESpacing.xs) {
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
                                        HStack(spacing: EVESpacing.xs) {
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
                                        HStack(spacing: EVESpacing.xs) {
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
                                    .clipShape(RoundedRectangle(cornerRadius: EVERadius.lg))
                            } else {
                                RoundedRectangle(cornerRadius: EVERadius.lg)
                                    .fill(.quaternary)
                                    .frame(width: 128, height: 128)
                            }
                        }

                        VStack(alignment: .leading, spacing: EVESpacing.md) {
                        HStack {
                            Image(systemName: "location.fill")
                                .foregroundStyle(palette.location)
                            Text("Location")
                                .font(.subheadline.bold())
                        }

                        VStack(alignment: .leading, spacing: EVESpacing.xs) {
                            HStack(spacing: EVESpacing.sm) {
                                Text(info.systemName)
                                    .eveContextMenu(.system(id: info.systemId, name: info.systemName))
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
                                HStack(spacing: EVESpacing.xs) {
                                    Image(systemName: "building.2.fill")
                                        .font(.caption)
                                        .foregroundStyle(.teal)
                                    Text(docked)
                                        .font(.caption)
                                        .foregroundStyle(.teal)
                                }
                            } else {
                                HStack(spacing: EVESpacing.xs) {
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
                                    .clipShape(RoundedRectangle(cornerRadius: EVERadius.lg))
                            } else {
                                RoundedRectangle(cornerRadius: EVERadius.lg)
                                    .fill(.quaternary)
                                    .frame(width: 128, height: 128)
                            }
                        }

                        VStack(alignment: .leading, spacing: EVESpacing.md) {
                        HStack {
                            Image(systemName: "airplane")
                                .foregroundStyle(.purple)
                            Text("Ship")
                                .font(.subheadline.bold())
                        }

                        VStack(alignment: .leading, spacing: EVESpacing.xs) {
                            Text(info.shipName)
                                .font(.headline)
                                .lineLimit(1)
                                .eveTruncationHelp(info.shipName)
                            let typeLine = [info.shipTypeName, info.shipGroupName].compactMap { $0 }.joined(separator: " · ")
                            Text(typeLine)
                                .font(.callout)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .eveTruncationHelp(typeLine)
                        }

                        // Label/value pairs that never break mid-word: one row when the
                        // column is wide enough, otherwise stacked.
                        let stats = shipStats(info)
                        if !stats.isEmpty {
                            ViewThatFits(in: .horizontal) {
                                HStack(spacing: EVESpacing.lg) {
                                    ForEach(stats) { shipStat(label: $0.label, value: $0.value) }
                                }
                                Grid(alignment: .leading, horizontalSpacing: EVESpacing.sm, verticalSpacing: EVESpacing.xxs) {
                                    ForEach(stats) { stat in
                                        GridRow {
                                            Text(stat.label)
                                                .font(.caption)
                                                .foregroundStyle(.tertiary)
                                            Text(stat.value)
                                                .font(.caption.monospacedDigit())
                                                .foregroundStyle(.secondary)
                                        }
                                        .lineLimit(1)
                                        .fixedSize()
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
            .padding(EVESpacing.lg)
        }
        // The pilot's ship, blurred, under a light wash of the system's security color,
        // plus a security strip along the top edge. Both are drawn behind or over the
        // card, never in it. (The star's icon is only 64 px; blurred across the card it
        // reads as a flat gradient, so the ship render is used instead.)
        .eveHeroBackdrop(EVEImageURL.typeRender(info.shipTypeId, size: 512),
                         height: 180, tint: eveSecurityColor(info.securityValue), intensity: 0.5)
        .eveCard()
        .overlay(alignment: .top) {
            Rectangle()
                .fill(eveSecurityColor(info.securityValue))
                .frame(height: 3)
                .accessibilityHidden(true)
        }
        .clipShape(RoundedRectangle(cornerRadius: EVERadius.xl))
    }

    struct ShipStat: Identifiable {
        let id: String
        let label: LocalizedStringKey
        let value: String
    }

    /// Mass, volume and cargo for the Ship column, skipping any the type doesn't have.
    func shipStats(_ info: CharacterLocationInfo) -> [ShipStat] {
        var stats: [ShipStat] = []
        if let mass = info.shipMass, mass > 0 {
            stats.append(ShipStat(id: "mass", label: "Mass", value: formatLarge(mass) + " kg"))
        }
        if let volume = info.shipVolume, volume > 0 {
            stats.append(ShipStat(id: "volume", label: "Volume",
                                  value: volume.formatted(.number.precision(.fractionLength(0))) + " m\u{00B3}"))
        }
        if let capacity = info.shipCapacity, capacity > 0 {
            stats.append(ShipStat(id: "cargo", label: "Cargo",
                                  value: capacity.formatted(.number.precision(.fractionLength(0))) + " m\u{00B3}"))
        }
        return stats
    }

    // MARK:  Station Services

    func stationServicesSection(station: ESIStation, services: [String]) -> some View {
        VStack(alignment: .leading, spacing: EVESpacing.md) {
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
                // Key services first, then the rest alphabetically.
                let ordered = services.sorted().sorted {
                    Self.keyStationServices.contains($0) && !Self.keyStationServices.contains($1)
                }
                ForEach(ordered, id: \.self) { service in
                    let (label, icon, color) = stationServiceInfo(service)
                    StationServiceBadge(service: service, label: label, icon: icon, color: color, station: station,
                                        isKey: Self.keyStationServices.contains(service))
                }
            }

            if let cost = station.officeRentalCost, cost > 0 {
                HStack(spacing: EVESpacing.xs) {
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

    /// The services a pilot actually docks for. They're listed first and drawn in the
    /// theme accent; everything else is a neutral pill, so the row isn't a rainbow.
    static let keyStationServices: Set<String> = [
        "market", "repair-facilities", "fitting", "cloning", "reprocessing-plant", "loyalty-point-store"
    ]

    func stationServiceInfo(_ service: String) -> (String, String, Color) {
        let (label, icon): (String, String) = switch service {
        case "market":                  (String(localized: "Market"), "cart.fill")
        case "reprocessing-plant":      (String(localized: "Reprocessing"), "arrow.3.trianglepath")
        case "repair-facilities":       (String(localized: "Repair"), "wrench.and.screwdriver.fill")
        case "fitting":                 (String(localized: "Fitting"), "gearshape.2.fill")
        case "cloning":                 (String(localized: "Cloning"), "person.2.fill")
        case "factory", "manufacturing": (String(localized: "Manufacturing"), "hammer.fill")
        case "labratory", "research":   (String(localized: "Research"), "flask.fill")
        case "insurance":               (String(localized: "Insurance"), "shield.fill")
        case "docking":                 (String(localized: "Docking"), "arrow.down.to.line")
        case "office-rental":           (String(localized: "Offices"), "building.fill")
        case "loyalty-point-store":     (String(localized: "LP Store"), "star.fill")
        case "navy-offices":            (String(localized: "Navy"), "flag.fill")
        case "security-offices":        (String(localized: "Security"), "lock.shield.fill")
        case "bounty-missions":         (String(localized: "Bounties"), "target")
        case "assay-office":            (String(localized: "Assay"), "scalemass.fill")
        case "storage":                 (String(localized: "Storage"), "archivebox.fill")
        case "stock-exchange":          (String(localized: "Exchange"), "arrow.left.arrow.right")
        default:
            (service.split(separator: "-").map { $0.capitalized }.joined(separator: " "), "circle.fill")
        }
        return (label, icon, Self.keyStationServices.contains(service) ? palette.accent : .secondary)
    }

    // MARK:  System Stations

    func systemStationsSection(_ stations: [ESIStation], characterID: Int) -> some View {
        let isExpanded = Binding(
            get: { stationsExpanded[characterID, default: false] },
            set: { stationsExpanded[characterID] = $0 }
        )
        return DisclosureGroup(isExpanded: isExpanded) {
            VStack(alignment: .leading, spacing: EVESpacing.sm) {
                ForEach(stations, id: \.stationId) { station in
                    VStack(alignment: .leading, spacing: EVESpacing.xs) {
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
                                            .font(.eveMicro)
                                            .foregroundStyle(color)
                                        Text(label)
                                            .font(.eveLabel)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                            }
                        }
                    }
                    .padding(.vertical, EVESpacing.xs)
                    if station.stationId != stations.last?.stationId {
                        Divider()
                    }
                }
            }
            .padding(.top, EVESpacing.xs)
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
