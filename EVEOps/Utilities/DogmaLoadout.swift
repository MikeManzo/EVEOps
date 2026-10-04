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

/// What a saved fit would actually shoot with. ESI fittings list ammo and drones by hold
/// ("Cargo", "DroneBay"), not by the module they're loaded in, so this infers the loadout
/// the dogma engine needs for DPS: a compatible charge from cargo for each weapon, and the
/// drones that fit in the ship's bandwidth.
nonisolated enum DogmaLoadout {
    /// chargeGroup1…5 on a module: the item groups it accepts as charges.
    static let chargeGroupAttributes = [604, 605, 606, 609, 610]
    /// chargeSize — turrets only take ammo of their own size; launchers don't carry it.
    static let chargeSizeAttribute = 128
    /// droneBandwidth on the hull, droneBandwidthUsed on each drone.
    static let droneBandwidthAttribute = 1271
    static let droneBandwidthUsedAttribute = 1272
    /// Drones in space at once with Drones V — the usual case for a fit worth simulating.
    static let maxActiveDrones = 5

    /// The first cargo charge the module accepts, in fitting order; nil when the module
    /// takes no charges or nothing in cargo fits it.
    static func charge(for module: ESIType, cargo: [Int], types: [Int: ESIType]) -> Int? {
        let groups = Set(chargeGroupAttributes.compactMap { module.attribute($0) }.map { Int($0) }.filter { $0 > 0 })
        guard !groups.isEmpty else { return nil }
        let size = module.attribute(chargeSizeAttribute)
        return cargo.first { typeId in
            guard let charge = types[typeId], groups.contains(charge.groupId) else { return false }
            guard let size else { return true }
            return charge.attribute(chargeSizeAttribute) == size
        }
    }

    /// Drones to launch from the bay, in fitting order, while bandwidth and the active limit
    /// allow. A drone with unknown bandwidth is skipped rather than guessed at.
    static func activeDrones(bay: [(typeId: Int, quantity: Int)], ship: ESIType?, types: [Int: ESIType]) -> [Int] {
        var bandwidth = ship?.attribute(droneBandwidthAttribute) ?? 0
        var out: [Int] = []
        for (typeId, quantity) in bay {
            guard let used = types[typeId]?.attribute(droneBandwidthUsedAttribute), used > 0 else { continue }
            for _ in 0..<quantity {
                guard out.count < maxActiveDrones, used <= bandwidth else { break }
                out.append(typeId)
                bandwidth -= used
            }
        }
        return out
    }

    /// Loads charges into `slots` and picks drones, from a fit's cargo and drone bay items.
    static func apply(items: [ESIFittingItem], to slots: inout [SimSlot], ship: ESIType?,
                      types: [Int: ESIType]) -> [Int] {
        let cargo = items.filter { $0.flag == "Cargo" }.map(\.typeId)
        for index in slots.indices {
            guard let moduleID = slots[index].moduleTypeId, let module = types[moduleID] else { continue }
            slots[index].chargeTypeId = charge(for: module, cargo: cargo, types: types)
        }
        let bay = items.filter { $0.flag == "DroneBay" }.map { (typeId: $0.typeId, quantity: $0.quantity) }
        return activeDrones(bay: bay, ship: ship, types: types)
    }
}

nonisolated extension DogmaLoadout {
    /// A fitted ship's slot assets as module + loaded charge per slot flag. ESI lists a
    /// loaded charge as a separate asset with the module's flag; the charge is whichever
    /// one the other accepts, falling back to the non-singleton stack.
    static func splitSlotAssets(_ assets: [ESIAsset], types: [Int: ESIType]) -> [String: (module: Int, charge: Int?)] {
        var out: [String: (module: Int, charge: Int?)] = [:]
        for (flag, group) in Dictionary(grouping: assets, by: \.locationFlag) {
            guard group.count > 1 else {
                if let only = group.first { out[flag] = (only.typeId, nil) }
                continue
            }
            let pair = group.lazy.compactMap { module -> (Int, Int)? in
                guard let type = types[module.typeId] else { return nil }
                let others = group.filter { $0.itemId != module.itemId }.map(\.typeId)
                return charge(for: type, cargo: others, types: types).map { (module.typeId, $0) }
            }.first
            if let (module, loaded) = pair {
                out[flag] = (module, loaded)
            } else if let module = group.first(where: \.isSingleton) ?? group.first {
                out[flag] = (module.typeId, group.first { !$0.isSingleton && $0.itemId != module.itemId }?.typeId)
            }
        }
        return out
    }
}

// MARK:  Saved fit → engine fit

nonisolated extension DogmaFit {
    /// A saved fit as the engine sees it. `onlineOnly` sends every module as online and
    /// skips charges and drones — all a CPU/powergrid check needs. Otherwise modules with a
    /// capacitor cost run active, weapons load cargo ammo and drones launch, for combat stats.
    init(fitting: ESIFitting, types: [Int: ESIType], implants: [Int] = [], onlineOnly: Bool) {
        var slots = Self.slots(for: fitting)
        let moduleIDs = Set(slots.compactMap(\.moduleTypeId))
        var drones: [Int] = []
        let passive: Set<Int>
        if onlineOnly {
            passive = moduleIDs
        } else {
            drones = DogmaLoadout.apply(items: fitting.items, to: &slots, ship: types[fitting.shipTypeId], types: types)
            passive = moduleIDs.filter { (types[$0]?.attribute(6) ?? 0) == 0 }   // capacitorNeed
        }
        self.init(shipTypeID: fitting.shipTypeId, slots: slots, droneTypeIDs: drones,
                  implantTypeIDs: implants, passiveModuleTypeIDs: passive)
    }

    /// The fit's modules as simulator slots. Flags are "HiSlot0", "SubSystemSlot0", …; a flag
    /// without a parsable index gets the next free one in its group.
    static func slots(for fitting: ESIFitting) -> [SimSlot] {
        var next: [SimSlotCategory: Int] = [:]
        var result: [SimSlot] = []
        for item in fitting.items {
            guard let category = SimSlotCategory.allCases.first(where: { item.flag.hasPrefix($0.flagPrefix) }) else { continue }
            let suffix = item.flag.dropFirst(category.flagPrefix.count).replacingOccurrences(of: "Slot", with: "")
            let index = Int(suffix) ?? next[category, default: 0]
            next[category] = max(next[category, default: 0], index + 1)
            result.append(SimSlot(category: category, index: index, moduleTypeId: item.typeId))
        }
        return result
    }
}

nonisolated extension ESIType {
    /// A dogma attribute's value, if the type has it.
    func attribute(_ id: Int) -> Double? {
        dogmaAttributes?.first { $0.attributeId == id }?.value
    }
}
