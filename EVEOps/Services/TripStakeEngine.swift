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

/// What a pilot stands to lose on a trip: the ship they're in, everything aboard it, and
/// the implants in their head. Prices are Jita sell.
nonisolated struct TripStake: Sendable, Equatable {
    var shipTypeID: Int
    var shipName: String?
    /// The hull's type name ("Rifter"), filled in by the service.
    var shipTypeName: String?
    var hull: Double = 0
    /// Fitted modules, rigs, subsystems, loaded charges and drones.
    var fit: Double = 0
    /// Cargo and every other hold, including what's inside containers.
    var cargo: Double = 0
    var implants: Double = 0
    var implantCount = 0
    /// Items with no Jita price (and blueprint copies), left out of the totals.
    var unpricedCount = 0
    /// False when ESI didn't report what's aboard the ship (it omits a ship in space), so
    /// `fit` and `cargo` are unknown rather than zero.
    var contentsKnown = true
    var implantsKnown = true
    /// Insurance payouts for the hull, by level name ("Basic" … "Platinum"); empty when the
    /// hull can't be insured or the prices didn't load.
    var insurancePayouts: [String: Double] = [:]
    var cloneAdvice: CloneAdvice?
    /// Where the implant-free clone is parked, filled in by the service.
    var cloneLocationName: String?

    /// Lost when the ship is destroyed.
    var shipLoss: Double { hull + fit + cargo }
    /// Lost when the ship is destroyed and the pod is too.
    var totalLoss: Double { shipLoss + implants }

    /// The best payout insurance can give: Platinum.
    var platinumPayout: Double? { insurancePayouts["Platinum"] }

    /// Ship loss after a Platinum payout. Insurance only ever covers the hull.
    var shipLossIfInsured: Double? {
        platinumPayout.map { max(shipLoss - $0, 0) }
    }
}

/// Whether to leave implants at home before a risky trip.
nonisolated enum CloneAdvice: Sendable, Equatable {
    /// An implant-free jump clone exists. `readyAt` is set while the clone jump is on cooldown.
    case jumpToEmptyClone(locationID: Int, readyAt: Date?)
    /// Valuable implants and nowhere implant-free to jump to.
    case noEmptyClone
}

// MARK: Engine

nonisolated enum TripStakeEngine {
    /// Implants worth less than this aren't worth a clone jump.
    static let valuableImplants: Double = 20_000_000

    /// `locationFlag` prefixes for what's fitted to the ship rather than carried in it.
    private static let fitFlagPrefixes = ["HiSlot", "MedSlot", "LoSlot", "RigSlot", "SubSystemSlot",
                                          "ServiceSlot", "DroneBay", "FighterBay", "FighterTube"]

    static func isFitted(flag: String) -> Bool {
        fitFlagPrefixes.contains { flag.hasPrefix($0) }
    }

    /// Everything aboard the ship, sorted into fit and cargo. Items inside a container keep
    /// the side of the container they're in.
    static func contents(of shipItemID: Int, in assets: [ESIAsset]) -> (fit: [ESIAsset], cargo: [ESIAsset]) {
        let byParent = Dictionary(grouping: assets, by: \.locationId)
        var fit: [ESIAsset] = []
        var cargo: [ESIAsset] = []
        var stack: [(ESIAsset, Bool)] = (byParent[shipItemID] ?? []).map { ($0, isFitted(flag: $0.locationFlag)) }
        var seen = Set<Int>()
        while let (item, fitted) = stack.popLast() {
            guard seen.insert(item.itemId).inserted else { continue }
            if fitted { fit.append(item) } else { cargo.append(item) }
            for child in byParent[item.itemId] ?? [] { stack.append((child, fitted)) }
        }
        return (fit, cargo)
    }

    /// Prices a set of items. Blueprint copies and unpriced types count as unpriced.
    static func value(_ items: [ESIAsset], prices: [Int: Double]) -> (total: Double, unpriced: Int) {
        var total = 0.0
        var unpriced = 0
        for item in items {
            guard item.isBlueprintCopy != true, let price = prices[item.typeId], price > 0 else {
                unpriced += 1
                continue
            }
            total += price * Double(item.quantity)
        }
        return (total, unpriced)
    }

    /// - Parameters:
    ///   - assets: the pilot's assets, or nil when they couldn't be read.
    ///   - implants: the active clone's implant type IDs, or nil when they couldn't be read.
    ///   - routeIsRisky: the route crosses lowsec, nullsec or a Danger system.
    static func stake(shipTypeID: Int, shipItemID: Int, shipName: String?,
                      assets: [ESIAsset]?, implants: [Int]?, clones: ESIClonesResponse?,
                      prices: [Int: Double], insurance: [String: Double],
                      routeIsRisky: Bool, cloneJumpReadyAt: Date?) -> TripStake {
        var stake = TripStake(shipTypeID: shipTypeID, shipName: shipName, insurancePayouts: insurance)
        stake.hull = prices[shipTypeID] ?? 0
        if stake.hull == 0 { stake.unpricedCount += 1 }

        // ESI leaves the piloted ship out of the asset list while it's in space.
        if let assets, assets.contains(where: { $0.itemId == shipItemID }) {
            let (fit, cargo) = contents(of: shipItemID, in: assets)
            let fitValue = value(fit, prices: prices)
            let cargoValue = value(cargo, prices: prices)
            stake.fit = fitValue.total
            stake.cargo = cargoValue.total
            stake.unpricedCount += fitValue.unpriced + cargoValue.unpriced
        } else {
            stake.contentsKnown = false
        }

        if let implants {
            stake.implantCount = implants.count
            for id in implants {
                if let price = prices[id], price > 0 { stake.implants += price } else { stake.unpricedCount += 1 }
            }
        } else {
            stake.implantsKnown = false
        }

        stake.cloneAdvice = cloneAdvice(implantValue: stake.implants, clones: clones,
                                        routeIsRisky: routeIsRisky, cloneJumpReadyAt: cloneJumpReadyAt)
        return stake
    }

    /// Advice only when the route is risky and the implants are worth protecting. Without
    /// the clone list we can't say either way, so no advice.
    static func cloneAdvice(implantValue: Double, clones: ESIClonesResponse?,
                            routeIsRisky: Bool, cloneJumpReadyAt: Date?) -> CloneAdvice? {
        guard routeIsRisky, implantValue >= valuableImplants, let clones else { return nil }
        guard let empty = clones.jumpClones.first(where: { $0.implants.isEmpty }) else { return .noEmptyClone }
        return .jumpToEmptyClone(locationID: empty.locationId, readyAt: cloneJumpReadyAt)
    }
}
