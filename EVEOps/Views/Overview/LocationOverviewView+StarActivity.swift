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
    // MARK:  Cargo Value

    func cargoValueColumn(characterID: Int) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "shippingbox.fill")
                    .foregroundStyle(.yellow)
                Text("Cargo Value")
                    .font(.subheadline.bold())
                Button {
                    showCargoValueInfo = true
                } label: {
                    Image(systemName: "info.circle")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .popover(isPresented: $showCargoValueInfo, arrowEdge: .bottom) {
                    cargoValueInfoPopover
                }
                Spacer(minLength: 0)
                if cargoValues[characterID] != nil && !cargoLoading.contains(characterID) {
                    Button {
                        Task { await loadCargoValue(characterID: characterID) }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }

            cargoValueColumnContent(characterID: characterID)
        }
        .task(id: characterID) {
            if cargoValues[characterID] == nil { await loadCargoValue(characterID: characterID) }
        }
    }

    var cargoValueInfoPopover: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "shippingbox.fill")
                    .font(.title3)
                    .foregroundStyle(.yellow)
                Text("How Cargo Value Is Calculated")
                    .font(.headline)
            }

            Divider()

            VStack(alignment: .leading, spacing: 8) {
                cargoInfoBullet("Scope", "Only items in the current ship's Cargo Hold — fitted modules, drone bay, ore hold, and other bays aren't included.")
                cargoInfoBullet("Pricing source", "Jita (The Forge) market aggregates via Fuzzwork, cached for 10 minutes.")
                cargoInfoBullet("Sell Value", "Lowest active sell order × quantity, summed across items — roughly what it'd cost to replace the cargo.")
                cargoInfoBullet("Buy Value", "Highest active buy order × quantity, summed across items — roughly what you'd get selling instantly.")
                cargoInfoBullet("Unpriced items", "Items with no active Jita orders are valued at 0 ISK and counted separately.")
                cargoInfoBullet("Docked required", "CCP's servers don't report your active ship's cargo contents while it's undocked — dock up, then refresh.")
            }

            Divider()

            Text("Quote-based, not depth-weighted — dumping a large stack could realize less than shown. Prices are Jita-only and may not reflect your local market.")
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .frame(minWidth: 260, maxWidth: 320)
    }

    func cargoInfoBullet(_ title: String, _ body: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.caption.bold())
            Text(body)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    @ViewBuilder
    func cargoValueColumnContent(characterID: Int) -> some View {
        if cargoLoading.contains(characterID) && cargoValues[characterID] == nil {
            HStack(spacing: 6) {
                ProgressView().controlSize(.small)
                Text("Pricing…")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        } else if let error = cargoErrors[characterID], cargoValues[characterID] == nil {
            Text(error)
                .font(.caption2)
                .foregroundStyle(.red)
                .lineLimit(3)
        } else if let summary = cargoValues[characterID] {
            if summary.dataUnavailable {
                HStack(alignment: .top, spacing: 4) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.caption2)
                        .foregroundStyle(.orange)
                    Text("Undocked — dock and refresh to view")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            } else if summary.items.isEmpty {
                Text("Cargo hold is empty")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                VStack(alignment: .leading, spacing: 6) {
                    cargoStat(label: "Sell Value", value: EVEFormatters.formatISKShort(summary.totalSellValue), color: .green)
                    cargoStat(label: "Buy Value", value: EVEFormatters.formatISKShort(summary.totalBuyValue), color: .orange)
                    HStack(spacing: 4) {
                        Text("\(summary.items.count) item\(summary.items.count == 1 ? "" : "s")")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                        if summary.unpricedCount > 0 {
                            Text("· \(summary.unpricedCount) unpriced")
                                .font(.caption2)
                                .foregroundStyle(.red.opacity(0.85))
                        }
                    }
                }
            }
        } else {
            Text("—")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
    }

    func cargoStat(label: String, value: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.caption2)
                .foregroundStyle(.tertiary)
            Text(value)
                .font(.caption.bold().monospacedDigit())
                .foregroundStyle(color)
        }
    }

    func loadCargoValue(characterID: Int) async {
        guard let account = accountManager.selectedAccount, account.characterID == characterID else { return }
        cargoLoading.insert(characterID)
        cargoErrors[characterID] = nil
        do {
            let token = try await accountManager.validToken(for: account)
            cargoValues[characterID] = try await CargoValueService.cargoValue(characterID: characterID, token: token)
        } catch {
            cargoErrors[characterID] = error.localizedDescription
        }
        cargoLoading.remove(characterID)
    }

    func starStat(label: String, value: String) -> some View {
        VStack(alignment: .center, spacing: 2) {
            Text(label)
                .font(.caption2)
                .foregroundStyle(.tertiary)
            Text(value)
                .font(.caption2.monospacedDigit())
                .foregroundStyle(.secondary)
        }
    }

    func starColor(_ spectralClass: String?) -> Color {
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

    func spectralDescription(_ spectralClass: String) -> String {
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

    // MARK:  Star · Connected Systems · Last Hour (combined)

    func starConnectionsActivitySection(_ info: CharacterLocationInfo) -> some View {
        // Three equal-width columns: Star · Connected Systems · Last Hour.
        HStack(alignment: .top, spacing: 0) {
            starColumn(info)
                .frame(maxWidth: .infinity, alignment: .topLeading)

            Divider().padding(.horizontal, 14)

            if !info.nearbySystems.isEmpty {
                connectedSystemsTable(info)
                    .frame(maxWidth: .infinity, alignment: .topLeading)
            } else {
                Spacer().frame(maxWidth: .infinity)
            }

            Divider().padding(.horizontal, 14)

            lastHourColumn(info)
                .frame(maxWidth: .infinity, alignment: .topLeading)
        }
    }

    @ViewBuilder
    func starColumn(_ info: CharacterLocationInfo) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "sun.max.fill")
                    .foregroundStyle(starColor(info.starSpectralClass))
                Text("Star")
                    .font(.subheadline.bold())
            }

            if info.starName != nil {
                HStack(spacing: 12) {
                    ZStack {
                        Circle()
                            .fill(starColor(info.starSpectralClass).opacity(0.2))
                            .frame(width: 44, height: 44)
                        Circle()
                            .fill(starColor(info.starSpectralClass))
                            .frame(width: 24, height: 24)
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
                    Spacer(minLength: 0)
                }

                // Astrophysics — own row so it reads cleanly at one-third width
                HStack(alignment: .top, spacing: 18) {
                    if let temp = info.starTemperature {
                        starStat(label: "Temp", value: "\(temp.formatted()) K")
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
                    Spacer(minLength: 0)
                }
            }

            if info.planetCount > 0 {
                Divider().padding(.vertical, 1)
                systemCompositionView(info)
            }

            situationalStrip(info)
        }
    }

    // MARK:  System Composition

    @ViewBuilder
    func systemCompositionView(_ info: CharacterLocationInfo) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 14) {
                starStat(label: "Planets", value: "\(info.planetCount)")
                if info.moonCount > 0 {
                    starStat(label: "Moons", value: "\(info.moonCount)")
                }
                if info.asteroidBeltCount > 0 {
                    starStat(label: "Belts", value: "\(info.asteroidBeltCount)")
                }
                starStat(label: "Stations", value: "\(info.stationCountInSystem)")
                starStat(label: "Gates", value: "\(info.nearbySystems.count)")
            }

            if !info.planetTypes.isEmpty {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 78), spacing: 4, alignment: .leading)],
                          alignment: .leading, spacing: 4) {
                    ForEach(info.planetTypes) { pt in
                        HStack(spacing: 3) {
                            Text("\(pt.count)×")
                                .font(.caption2.bold().monospacedDigit())
                                .foregroundStyle(.secondary)
                            Text(pt.type)
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                        }
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(.secondary.opacity(0.10), in: Capsule())
                    }
                }
            }
        }
    }

    // MARK:  Situational Status Strip

    @ViewBuilder
    func situationalStrip(_ info: CharacterLocationInfo) -> some View {
        let fw = fwSystems[info.systemId]
        let incursion = incursions.first { $0.infestedSolarSystems.contains(info.systemId) }
        if fw != nil || incursion != nil {
            HStack(spacing: 8) {
                if let fw {
                    situationalPill(
                        icon: "shield.lefthalf.filled",
                        color: .red,
                        title: "FW",
                        detail: fwDetail(fw)
                    )
                }
                if let incursion {
                    situationalPill(
                        icon: "hurricane",
                        color: .purple,
                        title: "Incursion",
                        detail: incursionDetail(incursion)
                    )
                }
            }
            .padding(.top, 1)
        }
    }

    func fwDetail(_ fw: ESIFWSystem) -> String {
        let owner = situationalFactionNames[fw.ownerFactionId] ?? "Faction #\(fw.ownerFactionId)"
        var parts = [owner, fw.contested.capitalized]
        if fw.victoryPointsThreshold > 0 {
            let pct = Int((Double(fw.victoryPoints) / Double(fw.victoryPointsThreshold) * 100).rounded())
            parts.append("\(pct)% VP")
        }
        if fw.occupierFactionId != fw.ownerFactionId {
            let occ = situationalFactionNames[fw.occupierFactionId] ?? "Faction #\(fw.occupierFactionId)"
            parts.append("occupied by \(occ)")
        }
        return parts.joined(separator: " · ")
    }

    func incursionDetail(_ inc: ESIIncursion) -> String {
        var parts = [inc.state.capitalized, "\(Int((inc.influence * 100).rounded()))% influence"]
        if inc.hasBoss { parts.append("boss up") }
        return parts.joined(separator: " · ")
    }

    func situationalPill(icon: String, color: Color, title: String, detail: String) -> some View {
        HStack(spacing: 5) {
            Image(systemName: icon)
                .font(.system(size: 10))
                .foregroundStyle(color)
            Text(title)
                .font(.caption2.bold())
                .foregroundStyle(color)
            Text(detail)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 3)
        .background(color.opacity(0.12), in: Capsule())
    }

    // MARK:  Connected Systems Table

    func connectedSystemsTable(_ info: CharacterLocationInfo) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "arrow.triangle.branch")
                    .foregroundStyle(.purple)
                Text("Connected Systems")
                    .font(.subheadline.bold())
                Text("(\(info.nearbySystems.count) gate\(info.nearbySystems.count == 1 ? "" : "s"))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 7) {
                GridRow {
                    tableHeader("System")
                    tableHeader("Sec").gridColumnAlignment(.trailing)
                    tableHeader("K").gridColumnAlignment(.trailing)
                    tableHeader("J").gridColumnAlignment(.trailing)
                    tableHeader("Sta").gridColumnAlignment(.trailing)
                    tableHeader("Leads to")
                }
                Divider().gridCellUnsizedAxes(.horizontal).gridCellColumns(6)
                ForEach(info.nearbySystems, id: \.systemId) { sys in
                    connectedSystemRow(sys)
                }
            }

            Text("K / J = player kills / jumps in the last hour")
                .font(.system(size: 9))
                .foregroundStyle(.tertiary)
        }
    }

    func tableHeader(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 9.5, weight: .bold))
            .tracking(0.6)
            .foregroundStyle(.tertiary)
    }

    @ViewBuilder
    func connectedSystemRow(_ sys: NearbySystem) -> some View {
        let act = systemActivity[sys.systemId]
        let playerKills = (act?.shipKills ?? 0) + (act?.podKills ?? 0)
        GridRow {
            HStack(spacing: 6) {
                Circle()
                    .fill(securityColor(sys.securityStatus))
                    .frame(width: 9, height: 9)
                Text(sys.name)
                    .font(.footnote.bold())
                    .lineLimit(1)
            }
            Text(String(format: "%.2f", sys.securityStatus))
                .font(.caption.monospacedDigit())
                .foregroundStyle(securityColor(sys.securityStatus))
            Text(act == nil ? "—" : "\(playerKills)")
                .font(.caption.monospacedDigit())
                .foregroundStyle(playerKills > 0 ? Color.red : Color.secondary.opacity(0.4))
            Text(act.map { "\($0.jumps)" } ?? "—")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
            Text("\(sys.stationCount)")
                .font(.caption.monospacedDigit())
                .foregroundStyle(sys.stationCount > 0 ? Color.secondary : Color.secondary.opacity(0.4))
            connectedLeadsToCell(sys)
        }
    }

    @ViewBuilder
    func connectedLeadsToCell(_ sys: NearbySystem) -> some View {
        if let region = sys.leadsToRegion {
            Text("→ \(region)")
                .font(.caption)
                .foregroundStyle(.orange)
                .lineLimit(1)
        } else if let constellation = sys.leadsToConstellation {
            Text("→ \(constellation)")
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        } else {
            Text("·")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
    }

}
