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

/// Measures how fast the pilot's current ship aligns and warps, with their skills, implants
/// and (when docked) fit, and turns it into an escape verdict.
enum EscapeCheckService {
    enum Failure: LocalizedError {
        case engineUnavailable, noStats
        var errorDescription: String? {
            switch self {
            case .engineUnavailable: "The fitting engine isn't ready yet. It loads once ship data has downloaded."
            case .noStats: "The fitting engine couldn't work out this ship's align time."
            }
        }
    }

    static func check(characterID: Int, token: String) async throws -> EscapeCheck {
        let base = "/characters/\(characterID)"
        let ship: ESICharacterShip = try await ESIClient.shared.fetch("\(base)/ship/", token: token, bypassCache: true)

        async let assetsFetch: [ESIAsset]? = try? ESIClient.shared.fetchPages("\(base)/assets/", token: token)
        async let implantsFetch: [Int]? = try? ESIClient.shared.fetch("\(base)/implants/", token: token)
        async let skillsFetch: ESISkillsResponse? = try? ESIClient.shared.fetch("\(base)/skills/", token: token)
        async let engineReady = ReadyRoomFittingChecker.prepareEngine(allowLoad: true)

        let assets = await assetsFetch
        let implants = await implantsFetch ?? []
        let skills = Dictionary((await skillsFetch)?.skills.map { ($0.skillId, $0.activeSkillLevel) } ?? [],
                                uniquingKeysWith: max)
        guard await engineReady else { throw Failure.engineUnavailable }

        // ESI leaves the piloted ship out of the asset list while it's in space.
        let fitKnown = assets?.contains { $0.itemId == ship.shipItemId } ?? false
        let slots = fitKnown ? EscapeCheckEngine.slots(shipItemID: ship.shipItemId, assets: assets ?? []) : []
        let moduleIDs = slots.compactMap(\.moduleTypeId)
        let types = await UniverseCache.shared.types(ids: Array(Set(moduleIDs + [ship.shipTypeId])))

        // Every module online, none running: align is measured before the MWD lights up,
        // and a running MWD's added mass would make it look slower than it is.
        let fit = DogmaFit(shipTypeID: ship.shipTypeId, slots: slots, implantTypeIDs: implants,
                           passiveModuleTypeIDs: Set(moduleIDs))
        let stats = await Task.detached(priority: .userInitiated) {
            DogmaEngine.shared.calculate(fit, skills: skills)
        }.value
        guard stats.alignTime > 0 else { throw Failure.noStats }

        var check = EscapeCheckEngine.check(
            shipTypeID: ship.shipTypeId, shipName: ship.shipName,
            alignTime: stats.alignTime, warpSpeed: stats.warpSpeed, fitKnown: fitKnown,
            shipGroupID: types[ship.shipTypeId]?.groupId, modules: moduleIDs, types: types
        )
        check.shipTypeName = types[ship.shipTypeId]?.name
        return check
    }
}
