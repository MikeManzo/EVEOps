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

// MARK:  Models

/// Why an asset is (or isn't) dead stock.
nonisolated enum DeadStockUse: Int, CaseIterable, Sendable, Comparable {
    /// Not part of any saved fitting, not in a ship, not a blueprint — just sitting there.
    case dead
    /// An assembled ship, or fitted to / carried in one.
    case inUse
    case blueprint
    /// Minerals, PI, salvage, datacores and the like, kept by a pilot who does industry.
    case material
    /// A container or ship holding other items — what's inside is judged on its own.
    case container

    static func < (a: Self, b: Self) -> Bool { a.rawValue < b.rawValue }
}

nonisolated struct DeadStockPrice: Sendable, Hashable {
    /// Highest buy order — what selling right now pays.
    let buy: Double
    /// Lowest sell order — what listing it competes with.
    let sell: Double
}

/// A dead portion of one asset stack.
nonisolated struct DeadStockStack: Sendable, Hashable {
    let characterID: Int
    let itemID: Int
    let placeID: Int
    let quantity: Int
    /// When EVEOps first saw this stack: `.distantPast` when it was already there when
    /// tracking began, nil without any history.
    let firstSeen: Date?
}

/// One item type's dead stock across every pilot and place.
nonisolated struct DeadStockLine: Sendable, Identifiable, Hashable {
    let typeID: Int
    let name: String
    let categoryID: Int?
    /// Units not covered by anything.
    let quantity: Int
    /// Loose units owned in all (dead plus reserved by fittings).
    let owned: Int
    /// Units the saved fittings claim.
    let reserved: Int
    let stacks: [DeadStockStack]
    let price: DeadStockPrice?
    /// Packaged volume of one unit, m³.
    let unitVolume: Double?

    var id: Int { typeID }
    /// ISK from selling to buy orders now.
    var value: Double { (price?.buy ?? 0) * Double(quantity) }
    /// ISK if listed at the lowest sell order.
    var listValue: Double { (price?.sell ?? 0) * Double(quantity) }
    var volume: Double? { unitVolume.map { $0 * Double(quantity) } }
    var placeIDs: [Int] {
        var seen = Set<Int>()
        return stacks.sorted { $0.quantity > $1.quantity }.map(\.placeID).filter { seen.insert($0).inserted }
    }
    var characterIDs: Set<Int> { Set(stacks.map(\.characterID)) }
    /// How long it has gone untouched: the newest stack's first sighting (`.distantPast`
    /// when every stack predates tracking). Nil without history for any stack.
    var untouchedSince: Date? {
        let dates = stacks.map(\.firstSeen)
        guard !dates.isEmpty, !dates.contains(where: { $0 == nil }) else { return nil }
        return dates.compactMap { $0 }.max()
    }
}

nonisolated struct DeadStockReport: Sendable {
    let lines: [DeadStockLine]
    /// Asset stacks set aside, by reason.
    let excluded: [DeadStockUse: Int]
    /// Distinct fittings whose parts were reserved.
    let fitCount: Int
    /// Item types with some units claimed by a fitting.
    let reservedTypes: Int

    var totalValue: Double { lines.reduce(0) { $0 + $1.value } }
    var totalListValue: Double { lines.reduce(0) { $0 + $1.listValue } }

    /// Dead stock ISK by place, largest first.
    var valueByPlace: [(placeID: Int, value: Double)] {
        var totals: [Int: Double] = [:]
        for line in lines {
            let unit = line.price?.buy ?? 0
            for stack in line.stacks { totals[stack.placeID, default: 0] += unit * Double(stack.quantity) }
        }
        return totals.map { ($0.key, $0.value) }.sorted { $0.value > $1.value }
    }
}

/// Everything the engine reads, across every pilot.
nonisolated struct DeadStockInput: Sendable {
    /// Character → their asset list.
    var assets: [Int: [ESIAsset]]
    /// Character → the ship they're in (ESI leaves it out of assets while in space).
    var pilotedShips: [Int: ESICharacterShip] = [:]
    /// Every pilot's saved fittings.
    var fittings: [ESIFitting] = []
    /// Type → category.
    var categories: [Int: Int] = [:]
    var typeNames: [Int: String] = [:]
    var volumes: [Int: Double] = [:]
    var prices: [Int: DeadStockPrice] = [:]
    /// Item → when first seen.
    var firstSeen: [Int: Date] = [:]
    /// Pilots who do industry; their materials aren't dead stock.
    var industrialists: Set<Int> = []
}

// MARK:  Engine

nonisolated enum DeadStockEngine {
    enum Category {
        static let ship = 6
        static let blueprint = 9
        /// Material, Commodity, Asteroid, Ancient Relics, Decryptors, Planetary Resources,
        /// Planetary Commodities.
        static let materials: Set<Int> = [4, 17, 25, 34, 35, 42, 43]
    }

    static func report(_ input: DeadStockInput) -> DeadStockReport {
        var excluded: [DeadStockUse: Int] = [:]
        // type → loose stacks that could be dead.
        var candidates: [Int: [DeadStockStack]] = [:]

        for (characterID, assets) in input.assets {
            let byID = Dictionary(assets.map { ($0.itemId, $0) }, uniquingKeysWith: { a, _ in a })
            let parents = Set(assets.map(\.locationId))
            let roots = ReadyRoomEngine.RootResolver(byID: byID)
            let pilotedShip = input.pilotedShips[characterID]?.shipItemId

            for asset in assets {
                let use = classify(asset, byID: byID, parents: parents, pilotedShip: pilotedShip,
                                   categories: input.categories,
                                   keepMaterials: input.industrialists.contains(characterID))
                guard use == .dead else {
                    excluded[use, default: 0] += 1
                    continue
                }
                candidates[asset.typeId, default: []].append(DeadStockStack(
                    characterID: characterID, itemID: asset.itemId, placeID: roots.root(of: asset.locationId),
                    quantity: asset.quantity, firstSeen: input.firstSeen[asset.itemId]
                ))
            }
        }

        let fits = distinctFits(input.fittings)
        let reserve = reservations(fits)
        var lines: [DeadStockLine] = []
        var reservedTypes = 0
        for (typeID, stacks) in candidates {
            let owned = stacks.reduce(0) { $0 + $1.quantity }
            let reserved = min(reserve[typeID] ?? 0, owned)
            if reserved > 0 { reservedTypes += 1 }
            let dead = deadPortions(stacks, reserving: reserved)
            guard !dead.isEmpty else { continue }
            lines.append(DeadStockLine(
                typeID: typeID,
                name: input.typeNames[typeID] ?? "Type #\(typeID)",
                categoryID: input.categories[typeID],
                quantity: dead.reduce(0) { $0 + $1.quantity },
                owned: owned,
                reserved: reserved,
                stacks: dead,
                price: input.prices[typeID],
                unitVolume: input.volumes[typeID]
            ))
        }
        lines.sort { $0.value != $1.value ? $0.value > $1.value : $0.name < $1.name }
        return DeadStockReport(lines: lines, excluded: excluded, fitCount: fits.count, reservedTypes: reservedTypes)
    }

    /// Why an asset isn't dead stock — or `.dead` when nothing claims it.
    static func classify(_ asset: ESIAsset, byID: [Int: ESIAsset], parents: Set<Int>, pilotedShip: Int?,
                         categories: [Int: Int], keepMaterials: Bool) -> DeadStockUse {
        let category = categories[asset.typeId]
        if category == Category.blueprint { return .blueprint }
        if category == Category.ship && asset.isSingleton { return .inUse }
        if parents.contains(asset.itemId) { return .container }
        // Fitted to, or carried anywhere inside, an assembled ship — including the one the
        // pilot sits in when ESI leaves it out of the list.
        var location = asset.locationId
        var hops = 0
        while hops < 16 {
            if location == pilotedShip { return .inUse }
            guard let parent = byID[location] else { break }
            if parent.isSingleton && categories[parent.typeId] == Category.ship { return .inUse }
            location = parent.locationId
            hops += 1
        }
        if keepMaterials, let category, Category.materials.contains(category) { return .material }
        return .dead
    }

    /// Saved fittings with duplicates (the same fit saved by several pilots) removed.
    static func distinctFits(_ fittings: [ESIFitting]) -> [ESIFitting] {
        var seen = Set<String>()
        return fittings.filter { seen.insert(HangarMatrixEngine.signature($0)).inserted }
    }

    /// Units each type the fits claim: the hull and every item, summed over fits — every
    /// fit you keep could want its own set.
    static func reservations(_ fits: [ESIFitting]) -> [Int: Int] {
        var out: [Int: Int] = [:]
        for fit in fits {
            out[fit.shipTypeId, default: 0] += 1
            for item in fit.items { out[item.typeId, default: 0] += item.quantity }
        }
        return out
    }

    /// The parts of `stacks` left once `reserving` units are set aside. The newest stacks
    /// are reserved first — recently bought or moved is more likely in use — so what's
    /// left is the stock that's sat longest.
    static func deadPortions(_ stacks: [DeadStockStack], reserving: Int) -> [DeadStockStack] {
        let newestFirst = stacks.sorted {
            let a = $0.firstSeen ?? .distantPast, b = $1.firstSeen ?? .distantPast
            return a != b ? a > b : $0.itemID > $1.itemID
        }
        var toReserve = reserving
        var out: [DeadStockStack] = []
        for stack in newestFirst {
            let reserved = min(stack.quantity, toReserve)
            toReserve -= reserved
            let left = stack.quantity - reserved
            guard left > 0 else { continue }
            out.append(DeadStockStack(characterID: stack.characterID, itemID: stack.itemID, placeID: stack.placeID,
                                      quantity: left, firstSeen: stack.firstSeen))
        }
        return out
    }

    // MARK: Liquidity

    nonisolated enum Liquidity: Int, Comparable, Sendable {
        /// Under a tenth of a day's Jita volume — sells without moving the price.
        case high
        /// Up to a day's volume.
        case medium
        /// More than a day's volume — selling it all would push the price down.
        case low
        /// Nothing traded recently.
        case none

        static func < (a: Self, b: Self) -> Bool { a.rawValue < b.rawValue }
    }

    static func liquidity(quantity: Int, averageDailyVolume: Double?) -> Liquidity? {
        guard let averageDailyVolume else { return nil }
        guard averageDailyVolume > 0 else { return Liquidity.none }
        let days = Double(quantity) / averageDailyVolume
        return days < 0.1 ? .high : days <= 1 ? .medium : .low
    }

    /// EVE's clipboard format ("Name<TAB>Qty" per line) — pastes into Janice, Evepraisal,
    /// or the in-game multisell window's search.
    static func clipboardText(_ lines: [DeadStockLine]) -> String {
        lines.map { "\($0.name)\t\($0.quantity)" }.joined(separator: "\n")
    }
}
