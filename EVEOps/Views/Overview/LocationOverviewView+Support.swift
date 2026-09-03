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

// MARK:  Station Service Badge

struct StationServiceBadge: View {
    let service: String
    let label: String
    let icon: String
    let color: Color
    let station: ESIStation
    @State private var showPopover = false

    var body: some View {
        Button { showPopover = true } label: {
            HStack(spacing: 4) {
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
        .buttonStyle(.plain)
        .popover(isPresented: $showPopover, arrowEdge: .bottom) {
            StationServicePopover(service: service, label: label, icon: icon, color: color, station: station)
        }
    }
}

struct StationServicePopover: View {
    let service: String
    let label: String
    let icon: String
    let color: Color
    let station: ESIStation

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.title3)
                    .foregroundStyle(color)
                VStack(alignment: .leading, spacing: 2) {
                    Text(label)
                        .font(.headline)
                    Text(station.name)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            Divider()

            Text(serviceDescription)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            stationDetails
        }
        .padding(14)
        .frame(minWidth: 240, maxWidth: 300)
    }

    private var serviceDescription: String {
        switch service {
        case "market":               return "Buy and sell items on the regional market. Orders are visible to all players in the region."
        case "reprocessing-plant":   return "Refine ore, ice, and salvage into base minerals and materials."
        case "repair-facilities":    return "Repair hull, armor, and module damage on your docked ship."
        case "fitting":              return "Install, remove, and rearrange modules, rigs, and subsystems while docked."
        case "cloning":              return "Create and manage jump clones, and swap implant sets without traveling."
        case "factory", "manufacturing": return "Manufacture ships, modules, ammunition, and other items from blueprints."
        case "labratory", "research": return "Research blueprint ME/TE efficiency, copy blueprints, and run invention jobs."
        case "insurance":            return "Purchase insurance for your ship. Compensation is paid if destroyed in combat."
        case "docking":              return "Dock your ship to access station facilities and services."
        case "office-rental":        return "Rent a corporation office for item storage, hangar access, and operations."
        case "loyalty-point-store":  return "Exchange loyalty points from missions for faction ships, modules, and implants."
        case "navy-offices":         return "Interact with the empire faction navy for missions and faction standings."
        case "security-offices":     return "File crime reports and interact with CONCORD and security agencies."
        case "bounty-missions":      return "Accept combat and bounty hunting missions from faction agents."
        case "assay-office":         return "Compress ore, run reactions, and process moon mining materials."
        case "storage":              return "Rent additional hangar space beyond your standard personal storage."
        case "stock-exchange":       return "Access a specialized commodity exchange for bulk trading."
        default:
            return service.split(separator: "-").map { $0.capitalized }.joined(separator: " ") + " services available at this station."
        }
    }

    @ViewBuilder
    private var stationDetails: some View {
        if service == "reprocessing-plant" {
            let hasData = station.reprocessingEfficiency != nil || station.reprocessingStationsTake != nil
            if hasData {
                Divider()
                VStack(alignment: .leading, spacing: 6) {
                    if let eff = station.reprocessingEfficiency, eff > 0 {
                        detailRow("Base Efficiency", value: eff.formatted(.percent.precision(.fractionLength(1))), color: .green)
                    }
                    if let take = station.reprocessingStationsTake, take > 0 {
                        detailRow("Station Tax", value: take.formatted(.percent.precision(.fractionLength(1))), color: .orange)
                    }
                }
            }
        } else if service == "docking" || service == "repair-facilities" {
            if let vol = station.maxDockableShipVolume, vol > 0 {
                Divider()
                detailRow("Max Ship Volume", value: volumeString(vol), color: .blue)
            }
        } else if service == "office-rental" {
            if let cost = station.officeRentalCost, cost > 0 {
                Divider()
                detailRow("Weekly Cost", value: EVEFormatters.formatISKShort(cost) + " ISK", color: .yellow)
            }
        } else if service == "insurance" {
            Divider()
            VStack(alignment: .leading, spacing: 5) {
                Text("Coverage Tiers")
                    .font(.caption2.bold())
                    .foregroundStyle(.tertiary)
                insuranceTier("Bronze",   premium: 20, payout: 50)
                insuranceTier("Silver",   premium: 30, payout: 60)
                insuranceTier("Gold",     premium: 40, payout: 75)
                insuranceTier("Platinum", premium: 50, payout: 85)
                insuranceTier("Titanium", premium: 60, payout: 97)
            }
        }
    }

    private func detailRow(_ label: String, value: String, color: Color) -> some View {
        HStack {
            Text(label).font(.caption).foregroundStyle(.tertiary)
            Spacer()
            Text(value).font(.caption.monospacedDigit().bold()).foregroundStyle(color)
        }
    }

    private func insuranceTier(_ name: String, premium: Int, payout: Int) -> some View {
        HStack(spacing: 0) {
            Text(name)
                .font(.caption2)
                .frame(width: 58, alignment: .leading)
            Text("\((Double(premium) / 100).formatted(.percent.precision(.fractionLength(0)))) premium")
                .font(.caption2.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
            Text("\((Double(payout) / 100).formatted(.percent.precision(.fractionLength(0)))) payout")
                .font(.caption2.monospacedDigit().bold())
                .foregroundStyle(.green)
        }
    }

    private func volumeString(_ vol: Double) -> String {
        if vol >= 1_000_000_000 { return String(format: "%.1fB m³", vol / 1_000_000_000) }
        if vol >= 1_000_000 { return String(format: "%.1fM m³", vol / 1_000_000) }
        if vol >= 1_000 { return String(format: "%.1fK m³", vol / 1_000) }
        return String(format: "%.0f m³", vol)
    }
}

// MARK:  Data Model

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
    // System composition (from /universe/systems + /universe/planets)
    let planetCount: Int
    let moonCount: Int
    let asteroidBeltCount: Int
    let planetTypes: [PlanetTypeCount]
    let stationCountInSystem: Int
    // Nearby connected systems
    let nearbySystems: [NearbySystem]
}

struct PlanetTypeCount: Sendable, Identifiable {
    let type: String   // e.g. "Barren", "Gas", "Temperate"
    let count: Int
    var id: String { type }
}

struct NearbySystem {
    let systemId: Int
    let name: String
    let securityStatus: Double
    let isExternal: Bool // outside current constellation
    let stationCount: Int
    let leadsToRegion: String?        // set when the gate crosses a region boundary
    let leadsToConstellation: String? // set when the gate leaves the constellation (same region)
}

struct SystemActivityData {
    let shipKills: Int
    let podKills: Int
    let npcKills: Int
    let jumps: Int
}
