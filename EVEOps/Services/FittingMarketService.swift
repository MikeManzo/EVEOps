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

struct FittingShopItem: Identifiable, Sendable, Hashable {
    let typeId: Int
    let quantity: Int
    let name: String
    var id: Int { typeId }
}

struct ItemQuote: Sendable {
    let typeId: Int
    let name: String
    let quantity: Int
    let unitPrice: Double
    let totalPrice: Double
    let canFill: Bool
}

struct StationQuote: Identifiable, Sendable {
    let locationId: Int
    let stationName: String
    let systemName: String
    let regionName: String
    let securityStatus: Double
    let totalISK: Double
    let itemQuotes: [ItemQuote]

    var missingCount: Int { itemQuotes.filter { !$0.canFill }.count }
    var isComplete: Bool { missingCount == 0 }
    var id: Int { locationId }
}

// MARK:  Service

enum FittingMarketService {

    static let tradeHubs: [(name: String, stationId: Int, systemName: String, regionName: String, securityStatus: Double)] = [
        ("Jita IV - Moon 4 - Caldari Navy Assembly Plant",           60003760, "Jita",    "The Forge",    0.946),
        ("Amarr VIII (Oris) - Emperor Family Academy",               60008494, "Amarr",   "Domain",       1.0),
        ("Dodixie IX - Moon 20 - Federation Navy Assembly Plant",    60011866, "Dodixie", "Sinq Laison",  0.9),
        ("Rens VI - Moon 8 - Brutor Tribe Treasury",                 60004588, "Rens",    "Heimatar",     0.9),
        ("Hek VIII - Moon 12 - Boundless Creation Factory",          60005686, "Hek",     "Metropolis",   0.5),
    ]

    /// Quick search: Fuzzwork station aggregates for the 5 major trade hubs.
    /// Runs 5 parallel requests; typically completes in 1-2 seconds.
    static func quickSearch(items: [FittingShopItem]) async -> [StationQuote] {
        let typeIds = items.map(\.typeId)
        var results: [StationQuote] = []

        await withTaskGroup(of: StationQuote?.self) { group in
            for hub in tradeHubs {
                group.addTask {
                    guard let prices = try? await FuzzworkClient.shared.stationPrices(
                        stationId: hub.stationId, typeIds: typeIds
                    ) else { return nil }

                    var itemQuotes: [ItemQuote] = []
                    var total = 0.0
                    for item in items {
                        if let p = prices[item.typeId], p.sellMin > 0 {
                            let lineTotal = p.sellMin * Double(item.quantity)
                            total += lineTotal
                            itemQuotes.append(ItemQuote(typeId: item.typeId, name: item.name,
                                quantity: item.quantity, unitPrice: p.sellMin,
                                totalPrice: lineTotal, canFill: true))
                        } else {
                            itemQuotes.append(ItemQuote(typeId: item.typeId, name: item.name,
                                quantity: item.quantity, unitPrice: 0, totalPrice: 0, canFill: false))
                        }
                    }
                    return StationQuote(locationId: hub.stationId, stationName: hub.name,
                        systemName: hub.systemName, regionName: hub.regionName,
                        securityStatus: hub.securityStatus, totalISK: total, itemQuotes: itemQuotes)
                }
            }
            for await quote in group {
                if let quote { results.append(quote) }
            }
        }
        return results.sorted { $0.totalISK < $1.totalISK }
    }
}
