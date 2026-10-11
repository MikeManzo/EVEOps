//
// This file is part of EVEOps.
//
// EVEOps is free software: you can redistribute it and/or modify
// it under the terms of the GNU General Public License as published by
// the Free Software Foundation, version 3 or later.
//
// Copyright (c) 2026 CitizenCoder
//

import Foundation

// MARK: Model

/// Whether the pilot's current ship can slip past a gate camp: how fast it aligns and
/// warps, what that means against a camp, and what would help.
nonisolated struct EscapeCheck: Sendable, Equatable {
    var shipTypeID: Int
    var shipName: String?
    /// The hull's type name ("Badger"), filled in by the service.
    var shipTypeName: String?
    var alignTime: Double
    /// AU/s.
    var warpSpeed: Double
    /// False when ESI didn't report the fit (it omits a ship in space), so the numbers are
    /// for the bare hull with the pilot's skills.
    var fitKnown: Bool
    var isHauler: Bool
    var gear: EscapeGear
    var verdict: EscapeVerdict
    var suggestions: [EscapeSuggestion]

    /// Server ticks (one a second) before the ship enters warp. EVE rounds up.
    var alignTicks: Int { EscapeCheckEngine.ticks(alignTime) }
}

/// What's fitted that matters for getting away.
nonisolated struct EscapeGear: Sendable, Equatable {
    /// Covert ops cloak: the ship can warp while cloaked.
    var covertCloak = false
    /// Any other cloak.
    var cloak = false
    var microwarpdrive = false
    /// Inertial stabilizers, nanofibers, or agility rigs.
    var agilityModules = 0
}

nonisolated enum EscapeVerdict: Int, Sendable, Equatable, Comparable {
    /// Can cloak and warp cloaked: a camp never gets a lock.
    case warpsCloaked
    /// Two server ticks or fewer: in warp before nearly any camp can lock.
    case hardToCatch
    /// Three or four ticks: fast-locking camps can catch it.
    case catchableByFastLockers
    /// Five ticks or more: any camp that's paying attention catches it.
    case catchable

    static func < (lhs: Self, rhs: Self) -> Bool { lhs.rawValue < rhs.rawValue }
}

nonisolated enum EscapeSuggestion: Sendable, Equatable {
    /// Cloak and warp while cloaked.
    case warpCloaked
    /// Cloak and MWD are both fitted: use the trick.
    case useCloakTrick
    /// A cloak is fitted but no MWD.
    case addMicrowarpdrive
    /// An MWD is fitted but no cloak.
    case addCloak
    /// Inertial stabilizers, nanofibers, agility rigs. `cutNeeded` is the fraction of align
    /// time to shed to reach two ticks.
    case addAgility(cutNeeded: Double)
    /// Haulers with nothing else to try: send a scout, or move cargo another way.
    case scoutAhead
}

// MARK: Engine

nonisolated enum EscapeCheckEngine {
    /// Hauler, Deep Space Transport, Blockade Runner, Freighter, Jump Freighter, Mining
    /// Barge, Exhumer, Industrial Command Ship, Capital Industrial Ship.
    static let haulerGroups: Set<Int> = [28, 380, 1202, 513, 902, 463, 543, 941, 883]
    static let cloakGroup = 330
    static let propulsionGroup = 46
    /// Inertial Stabilizer, Nanofiber Internal Structure.
    static let agilityModuleGroups: Set<Int> = [762, 763]
    /// canFitShipGroup01 — only the covert ops cloak restricts the hulls it fits.
    static let covertCloakAttribute = 1298
    /// signatureRadiusBonus — microwarpdrives bloom signature, afterburners don't.
    static let microwarpdriveAttribute = 554
    /// agilityBonus on Rig Navigation (Low Friction Nozzle Joints, Polycarbon Engine
    /// Housing) — the rigs that cut align time.
    static let agilityRigAttribute = 151
    static let navigationRigGroup = 782

    /// Align at or under this many ticks and most camps can't lock in time.
    static let safeTicks = 2
    /// At or under this, fast lockers can still catch you.
    static let riskyTicks = 4

    static func ticks(_ alignTime: Double) -> Int {
        guard alignTime > 0 else { return 0 }
        // A hair of tolerance so 2.0000001 s from floating-point math still counts as two.
        return Int((alignTime - 0.001).rounded(.up))
    }

    static func gear(modules: [Int], types: [Int: ESIType]) -> EscapeGear {
        var gear = EscapeGear()
        for id in modules {
            guard let type = types[id] else { continue }
            switch type.groupId {
            case cloakGroup:
                if type.attribute(covertCloakAttribute) != nil { gear.covertCloak = true } else { gear.cloak = true }
            case propulsionGroup where type.attribute(microwarpdriveAttribute) != nil:
                gear.microwarpdrive = true
            case let group where agilityModuleGroups.contains(group):
                gear.agilityModules += 1
            case navigationRigGroup where (type.attribute(agilityRigAttribute) ?? 0) < 0:
                gear.agilityModules += 1
            default:
                break
            }
        }
        return gear
    }

    static func verdict(alignTime: Double, gear: EscapeGear) -> EscapeVerdict {
        if gear.covertCloak { return .warpsCloaked }
        let ticks = ticks(alignTime)
        if ticks <= safeTicks { return .hardToCatch }
        if ticks <= riskyTicks { return .catchableByFastLockers }
        return .catchable
    }

    /// What would help, most effective first. Nothing when the ship is already hard to catch.
    static func suggestions(alignTime: Double, gear: EscapeGear, verdict: EscapeVerdict,
                            isHauler: Bool) -> [EscapeSuggestion] {
        switch verdict {
        case .warpsCloaked: return [.warpCloaked]
        case .hardToCatch: return []
        case .catchableByFastLockers, .catchable: break
        }
        var out: [EscapeSuggestion] = []
        switch (gear.cloak, gear.microwarpdrive) {
        case (true, true): out.append(.useCloakTrick)
        case (true, false): out.append(.addMicrowarpdrive)
        case (false, true): out.append(.addCloak)
        case (false, false): break
        }
        let target = Double(safeTicks)
        if alignTime > target {
            out.append(.addAgility(cutNeeded: 1 - target / alignTime))
        }
        if isHauler && !gear.cloak { out.append(.scoutAhead) }
        return out
    }

    static func check(shipTypeID: Int, shipName: String?, alignTime: Double, warpSpeed: Double,
                      fitKnown: Bool, shipGroupID: Int?, modules: [Int], types: [Int: ESIType]) -> EscapeCheck {
        let gear = gear(modules: modules, types: types)
        let isHauler = shipGroupID.map(haulerGroups.contains) ?? false
        let verdict = verdict(alignTime: alignTime, gear: gear)
        return EscapeCheck(
            shipTypeID: shipTypeID, shipName: shipName, alignTime: alignTime, warpSpeed: warpSpeed,
            fitKnown: fitKnown, isHauler: isHauler, gear: gear, verdict: verdict,
            suggestions: suggestions(alignTime: alignTime, gear: gear, verdict: verdict, isHauler: isHauler)
        )
    }

    /// The ship's fitted modules as engine slots, from its slot assets. Charges are left
    /// out: they don't change how fast a ship aligns.
    static func slots(shipItemID: Int, assets: [ESIAsset]) -> [SimSlot] {
        assets.compactMap { asset -> SimSlot? in
            guard asset.locationId == shipItemID, asset.isSingleton,
                  let category = SimSlotCategory.allCases.first(where: { asset.locationFlag.hasPrefix($0.flagPrefix) })
            else { return nil }
            let suffix = asset.locationFlag.dropFirst(category.flagPrefix.count).replacingOccurrences(of: "Slot", with: "")
            guard let index = Int(suffix) else { return nil }
            return SimSlot(category: category, index: index, moduleTypeId: asset.typeId)
        }
    }
}
