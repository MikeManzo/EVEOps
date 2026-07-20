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

struct CargoValueItem: Identifiable, Sendable {
    let typeId: Int
    let typeName: String
    let quantity: Int
    let unitSellPrice: Double
    let unitBuyPrice: Double
    var totalSellValue: Double { unitSellPrice * Double(quantity) }
    var totalBuyValue: Double { unitBuyPrice * Double(quantity) }
    var hasPrice: Bool { unitSellPrice > 0 || unitBuyPrice > 0 }
    var id: Int { typeId }
}

struct CargoValueSummary: Sendable {
    let shipTypeId: Int
    let items: [CargoValueItem]
    let totalSellValue: Double
    let totalBuyValue: Double
    let unpricedCount: Int

    static let empty = CargoValueSummary(shipTypeId: 0, items: [], totalSellValue: 0, totalBuyValue: 0, unpricedCount: 0)
}

// MARK:  Service

enum CargoValueService {

    /// Values the cargo hold of the character's currently piloted ship, priced at Jita.
    static func cargoValue(characterID: Int, token: String) async throws -> CargoValueSummary {
        let ship: ESICharacterShip = try await ESIClient.shared.fetch(
            "/characters/\(characterID)/ship/", token: token
        )

        let rawAssets: [ESIAsset] = try await ESIClient.shared.fetchPages(
            "/characters/\(characterID)/assets/", token: token
        )
        var seenItemIds = Set<Int>()
        let assets = rawAssets.filter { seenItemIds.insert($0.itemId).inserted }

        let cargo = assets.filter { $0.locationId == ship.shipItemId && $0.locationFlag == "Cargo" }
        guard !cargo.isEmpty else {
            return CargoValueSummary(shipTypeId: ship.shipTypeId, items: [], totalSellValue: 0, totalBuyValue: 0, unpricedCount: 0)
        }

        // Aggregate quantity by typeId — cargo can hold multiple stacks of the same item.
        var quantityByType: [Int: Int] = [:]
        for asset in cargo {
            quantityByType[asset.typeId, default: 0] += asset.quantity
        }

        let typeIds = Array(quantityByType.keys)
        async let fetchTypes = UniverseCache.shared.types(ids: typeIds)
        async let fetchPrices = (try? await FuzzworkClient.shared.prices(typeIds: typeIds)) ?? [:]
        let (types, prices) = await (fetchTypes, fetchPrices)

        var items: [CargoValueItem] = []
        var totalSell = 0.0
        var totalBuy = 0.0
        var unpriced = 0
        for (typeId, quantity) in quantityByType {
            let price = prices[typeId]
            let sell = price?.sellMin ?? 0
            let buy = price?.buyMax ?? 0
            if sell == 0 && buy == 0 { unpriced += 1 }
            let item = CargoValueItem(
                typeId: typeId,
                typeName: types[typeId]?.name ?? "Type #\(typeId)",
                quantity: quantity,
                unitSellPrice: sell,
                unitBuyPrice: buy
            )
            items.append(item)
            totalSell += item.totalSellValue
            totalBuy += item.totalBuyValue
        }
        items.sort { $0.totalSellValue > $1.totalSellValue }

        return CargoValueSummary(
            shipTypeId: ship.shipTypeId,
            items: items,
            totalSellValue: totalSell,
            totalBuyValue: totalBuy,
            unpricedCount: unpriced
        )
    }
}
