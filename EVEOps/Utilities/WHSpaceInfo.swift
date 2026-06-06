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

// MARK: WHClass

enum WHClass: Int, CaseIterable, Sendable {
    case c1 = 1, c2, c3, c4, c5, c6
    case thera        = 12
    case c13          = 13  // shattered frigates-only
    case sentinel     = 14  // Drifter
    case barbican     = 15
    case vidette      = 16
    case conflux      = 17
    case redoubt      = 18

    var shortName: String {
        switch self {
        case .c1: "C1"
        case .c2: "C2"
        case .c3: "C3"
        case .c4: "C4"
        case .c5: "C5"
        case .c6: "C6"
        case .thera: "Thera"
        case .c13: "C13"
        case .sentinel, .barbican, .vidette, .conflux, .redoubt: "Drifter"
        }
    }

    var displayName: String {
        switch self {
        case .c1: "Class 1"
        case .c2: "Class 2"
        case .c3: "Class 3"
        case .c4: "Class 4"
        case .c5: "Class 5"
        case .c6: "Class 6"
        case .thera: "Thera"
        case .c13: "Class 13 — Shattered"
        case .sentinel: "Sentinel (Drifter)"
        case .barbican: "Barbican (Drifter)"
        case .vidette: "Vidette (Drifter)"
        case .conflux: "Conflux (Drifter)"
        case .redoubt: "Redoubt (Drifter)"
        }
    }

    /// Rough NPC difficulty / typical use
    var description: String {
        switch self {
        case .c1: "Solo-friendly anomalies, frigate/cruiser statics"
        case .c2: "Dual statics, mixed-use space"
        case .c3: "Cruiser-scale combat, common nullsec/lowsec statics"
        case .c4: "Corp-scale combat, C3/C4 statics — no direct k-space"
        case .c5: "Capital-escalation sites, C5/C6 statics"
        case .c6: "Hardest WH content, capital escalations only"
        case .thera: "Public WH hub, no stations — massive connections network"
        case .c13: "Frigate-restricted shattered wormhole"
        case .sentinel, .barbican, .vidette, .conflux, .redoubt: "Drifter wormhole — extremely hostile"
        }
    }

    var color: Color {
        switch self {
        case .c1: .green
        case .c2: .mint
        case .c3: .yellow
        case .c4: .orange
        case .c5: .red
        case .c6: .purple
        case .thera: .cyan
        case .c13: .secondary
        case .sentinel, .barbican, .vidette, .conflux, .redoubt: .indigo
        }
    }

    var isDrifter: Bool {
        switch self {
        case .sentinel, .barbican, .vidette, .conflux, .redoubt: true
        default: false
        }
    }
}

// MARK: WHEffect

enum WHEffect: String, CaseIterable, Sendable {
    case pulsar
    case blackHole
    case wolfRayet
    case redGiant
    case magnetar
    case cataclysmicVariable

    var displayName: String {
        switch self {
        case .pulsar:               "Pulsar"
        case .blackHole:            "Black Hole"
        case .wolfRayet:            "Wolf-Rayet"
        case .redGiant:             "Red Giant"
        case .magnetar:             "Magnetar"
        case .cataclysmicVariable:  "Cataclysmic Variable"
        }
    }

    var systemImage: String {
        switch self {
        case .pulsar:               "sparkles"
        case .blackHole:            "circle.fill"
        case .wolfRayet:            "flame.fill"
        case .redGiant:             "sun.max.fill"
        case .magnetar:             "bolt.fill"
        case .cataclysmicVariable:  "tornado"
        }
    }

    var color: Color {
        switch self {
        case .pulsar:               .cyan
        case .blackHole:            .indigo
        case .wolfRayet:            .orange
        case .redGiant:             .red
        case .magnetar:             .yellow
        case .cataclysmicVariable:  .teal
        }
    }

    /// One-line description of what this effect boosts and penalises.
    var mechanic: String {
        switch self {
        case .pulsar:
            return "+Shield HP · +Capacitor — but −Armor resists · −EM damage"
        case .blackHole:
            return "+Velocity · +Targeting range — but −Lock speed · −Web strength"
        case .wolfRayet:
            return "+Armor HP · +Small weapon damage — but −Shield HP · −Signature radius"
        case .redGiant:
            return "+Heat damage · +Bomb damage — but −ECM strength"
        case .magnetar:
            return "+All weapon damage · +Explosion velocity — but −Drone damage · −Missile radius"
        case .cataclysmicVariable:
            return "+Energy transfer · +Cap recharge — but −Neutralizers · −Remote & local reps"
        }
    }
}

// MARK: WHSystemInfo

struct WHSystemInfo: Sendable {
    let whClass: WHClass
    let effect: WHEffect?
}

// MARK: Lookup

/// Wormhole space class and effect lookup using static SDE-derived data.
///
/// **Class detection** uses the J-space region naming convention from the SDE where
/// region names follow the pattern "X-R00NNN" and the leading letter maps directly
/// to wormhole class: A→C1, B→C2, C→C3, D→C4, E→C5, F→C6, H→C13 (shattered).
/// Thera is identified by system name.
///
/// **Effect lookup** uses `effectDatabase`, keyed by solar system ID. Entries are
/// sourced from `mapSolarSystems.effectBeaconTypeID` in the SDE. Systems absent
/// from the table have no system effect.
enum WHSpaceInfo {

    // MARK: Public

    static func isWormholeSystem(_ systemId: Int) -> Bool {
        systemId >= 31_000_001
    }

    /// Returns wormhole metadata for `systemId`, or nil if the system is not J-space.
    static func info(systemId: Int, systemName: String?, regionName: String?) -> WHSystemInfo? {
        guard isWormholeSystem(systemId) else { return nil }

        if systemName == "Thera" {
            return WHSystemInfo(whClass: .thera, effect: effectDatabase[systemId])
        }

        guard let cls = whClass(fromRegionName: regionName) else { return nil }
        return WHSystemInfo(whClass: cls, effect: effectDatabase[systemId])
    }

    // MARK: Private

    /// Derives WH class from the SDE region naming convention (A-R=C1 through F-R=C6).
    private static func whClass(fromRegionName name: String?) -> WHClass? {
        guard let name, name.count >= 2 else { return nil }
        switch name.prefix(2) {
        case "A-": return .c1
        case "B-": return .c2
        case "C-": return .c3
        case "D-": return .c4
        case "E-": return .c5
        case "F-": return .c6
        case "H-": return .c13
        default:   return nil
        }
    }

    /// Per-system effect lookup keyed by solar system ID.
    ///
    /// To populate: extract `mapSolarSystems` from the EVE SDE and emit entries
    /// for every row where `effectBeaconTypeID` is not null. Effect type IDs:
    ///   30669 = Pulsar          30671 = Black Hole
    ///   30672 = Wolf-Rayet      30673 = Red Giant
    ///   30670 = Magnetar        30674 = Cataclysmic Variable
    private static let effectDatabase: [Int: WHEffect] = [:]
    // Populate from SDE extraction — see comment above for method.
}
