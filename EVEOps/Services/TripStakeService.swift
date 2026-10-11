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

/// One hull's insurance levels from ESI's public `/insurance/prices/`.
nonisolated struct ESIInsurancePrice: Codable, Sendable {
    struct Level: Codable, Sendable {
        let cost: Double
        let name: String
        let payout: Double
    }
    let typeId: Int
    let levels: [Level]
}

/// Gathers what a pilot would lose on a trip in their current ship. Everything but the ship
/// itself is best-effort: a missing scope or failed call leaves that part out and the
/// estimate says so.
enum TripStakeService {
    static func estimate(characterID: Int, token: String, routeIsRisky: Bool) async throws -> TripStake {
        let base = "/characters/\(characterID)"
        let ship: ESICharacterShip = try await ESIClient.shared.fetch("\(base)/ship/", token: token, bypassCache: true)

        async let assetsFetch: [ESIAsset]? = try? ESIClient.shared.fetchPages("\(base)/assets/", token: token)
        async let implantsFetch: [Int]? = try? ESIClient.shared.fetch("\(base)/implants/", token: token)
        async let clonesFetch: ESIClonesResponse? = try? ESIClient.shared.fetch("\(base)/clones/", token: token)
        async let skillsFetch: ESISkillsResponse? = try? ESIClient.shared.fetch("\(base)/skills/", token: token)
        async let insuranceFetch: [ESIInsurancePrice]? = try? ESIClient.shared.fetch("/insurance/prices/")

        var assets = await assetsFetch
        if let raw = assets {
            var seen = Set<Int>()
            assets = raw.filter { seen.insert($0.itemId).inserted }
        }
        let implants = await implantsFetch
        let clones = await clonesFetch

        var typeIDs: Set<Int> = [ship.shipTypeId]
        if let assets {
            let (fit, cargo) = TripStakeEngine.contents(of: ship.shipItemId, in: assets)
            typeIDs.formUnion((fit + cargo).map(\.typeId))
        }
        typeIDs.formUnion(implants ?? [])
        let fuzzwork = (try? await FuzzworkClient.shared.prices(typeIds: Array(typeIDs))) ?? [:]
        let prices = fuzzwork.compactMapValues { $0.sellMin > 0 ? $0.sellMin : nil }

        var insurance: [String: Double] = [:]
        for level in await insuranceFetch?.first(where: { $0.typeId == ship.shipTypeId })?.levels ?? [] {
            insurance[level.name] = level.payout
        }

        let readyAt = IdleCapacityEngine.cloneJumpReadyAt(
            lastJump: clones?.lastCloneJumpDate,
            infomorphSynchronizing: IdleCapacityEngine.infomorphSynchronizing(in: await skillsFetch)
        )

        var stake = TripStakeEngine.stake(
            shipTypeID: ship.shipTypeId, shipItemID: ship.shipItemId, shipName: ship.shipName,
            assets: assets, implants: implants, clones: clones,
            prices: prices, insurance: insurance,
            routeIsRisky: routeIsRisky, cloneJumpReadyAt: readyAt
        )
        stake.shipTypeName = await UniverseCache.shared.type(id: ship.shipTypeId)?.name
        if case let .jumpToEmptyClone(locationID, _) = stake.cloneAdvice {
            stake.cloneLocationName = await NameResolver.shared.resolveLocation(id: locationID, token: token)
        }
        return stake
    }
}
