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

// MARK:  Universe Lookups

nonisolated struct ESIDogmaAttribute: Codable, Sendable {
    let attributeId: Int
    let value: Double
}

nonisolated struct ESIDogmaEffect: Codable, Sendable {
    let effectId: Int
    let isDefault: Bool
}

// Full modifier record returned by /dogma/effects/{id}/
// `func` and `operator` are Swift keywords, so they use custom CodingKeys.
nonisolated struct ESIDogmaModifier: Codable, Sendable {
    let domain: String?
    let function: String?
    let modifiedAttributeId: Int?
    let modifyingAttributeId: Int?
    let operatorId: Int?
    var groupId: Int?

    // Primary CodingKeys. `groupId` uses the camelCase raw value "groupID" because the live
    // ESI endpoint returns "groupID" (capital D), not the snake_case "group_id" documented
    // in the Swagger spec. The custom init below also tries a fallback lookup for the
    // snake_case-converted form ("groupId") in case ESI behaviour changes.
    enum CodingKeys: String, CodingKey {
        case domain
        case function = "func"
        case modifiedAttributeId
        case modifyingAttributeId
        case operatorId = "operator"
        case groupId = "groupID"
    }

    init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        domain               = try c.decodeIfPresent(String.self, forKey: .domain)
        function             = try c.decodeIfPresent(String.self, forKey: .function)
        modifiedAttributeId  = try c.decodeIfPresent(Int.self,    forKey: .modifiedAttributeId)
        modifyingAttributeId = try c.decodeIfPresent(Int.self,    forKey: .modifyingAttributeId)
        operatorId           = try c.decodeIfPresent(Int.self,    forKey: .operatorId)

        // Try the primary typed key ("groupID") first.  If the decoder's convertFromSnakeCase
        // strategy transformed the JSON key "group_id" → "groupId" (lowercase d) rather than
        // leaving the camelCase "groupID" alone, the primary lookup will miss; the fallback
        // AnyKey container catches both spellings regardless of the active key strategy.
        if let gid = try c.decodeIfPresent(Int.self, forKey: .groupId) {
            groupId = gid
        } else {
            struct AnyKey: CodingKey {
                let stringValue: String
                var intValue: Int? { nil }
                init(stringValue s: String) { stringValue = s }
                init?(intValue: Int) { nil }
            }
            let ac = (try? decoder.container(keyedBy: AnyKey.self))
            groupId = (try? ac?.decodeIfPresent(Int.self, forKey: AnyKey(stringValue: "groupId")))
                   ?? (try? ac?.decodeIfPresent(Int.self, forKey: AnyKey(stringValue: "group_id")))
        }
    }
}

nonisolated struct ESIDogmaEffectDetail: Codable, Sendable {
    let effectId: Int
    // 0=passive, 1=active, 2=target, 3=area, 4=online, 5=overload
    let effectCategory: Int?
    var modifiers: [ESIDogmaModifier]
}

nonisolated struct ESIType: Codable, Sendable {
    let capacity: Double?
    let description: String?
    let dogmaAttributes: [ESIDogmaAttribute]?
    let dogmaEffects: [ESIDogmaEffect]?
    let groupId: Int
    let iconId: Int?
    let marketGroupId: Int?
    let mass: Double?
    let name: String
    let packagedVolume: Double?
    let portionSize: Int?
    let published: Bool
    let radius: Double?
    let typeId: Int
    let volume: Double?
}

nonisolated struct ESIGroup: Codable, Sendable {
    let categoryId: Int
    let groupId: Int
    let name: String
    let published: Bool
    let types: [Int]
}

nonisolated struct ESICategory: Codable, Sendable {
    let categoryId: Int
    let groups: [Int]
    let name: String
    let published: Bool
}

nonisolated struct ESIMarketGroup: Codable, Sendable {
    let description: String
    let marketGroupId: Int
    let name: String
    let parentGroupId: Int?
    let types: [Int]
}

nonisolated struct ESIPosition: Codable, Sendable {
    let x: Double
    let y: Double
    let z: Double
}

nonisolated struct ESISolarSystem: Codable, Sendable {
    let constellationId: Int
    let name: String
    let planets: [ESISystemPlanet]?
    let position: ESIPosition?
    let securityClass: String?
    let securityStatus: Double
    let starId: Int?
    let stargates: [Int]?
    let stations: [Int]?
    let systemId: Int
}

/// A planet entry as returned inline by `/universe/systems/{id}/` — just the id plus
/// its moon and asteroid-belt ids. Planet type requires `/universe/planets/{id}/`.
nonisolated struct ESISystemPlanet: Codable, Sendable {
    let planetId: Int
    let asteroidBelts: [Int]?
    let moons: [Int]?
}

/// `/universe/planets/{id}/` — static, cached in `UniverseCache`.
nonisolated struct ESIPlanet: Codable, Sendable {
    let name: String
    let planetId: Int
    let systemId: Int
    let typeId: Int
}

nonisolated struct ESIStation: Codable, Sendable {
    let name: String
    let stationId: Int
    let systemId: Int
    let typeId: Int
    let owner: Int?
    let services: [String]?
    let reprocessingEfficiency: Double?
    let reprocessingStationsTake: Double?
    let maxDockableShipVolume: Double?
    let officeRentalCost: Double?
}

nonisolated struct ESIStructure: Codable, Sendable {
    let name: String
    let ownerId: Int
    let solarSystemId: Int
    let typeId: Int?
}

nonisolated struct ESIConstellation: Codable, Sendable {
    let constellationId: Int
    let name: String
    let position: ESIPosition?
    let regionId: Int
    let systems: [Int]?
}

nonisolated struct ESIStargate: Codable, Sendable {
    let destination: ESIStargateDestination
    let name: String
    let position: ESIPosition?
    let stargateId: Int
    let systemId: Int
    let typeId: Int
}

nonisolated struct ESIStargateDestination: Codable, Sendable {
    let stargateId: Int
    let systemId: Int
}

nonisolated struct ESIRegion: Codable, Sendable {
    let name: String
    let regionId: Int
    let factionId: Int?
    let constellations: [Int]?
}

nonisolated struct ESIStar: Codable, Sendable {
    let age: Int?
    let luminosity: Double?
    let name: String
    let radius: Int?
    let solarSystemId: Int
    let spectralClass: String?
    let temperature: Int?
    let typeId: Int
}

nonisolated struct ESISystemKills: Codable, Sendable {
    let npcKills: Int
    let podKills: Int
    let shipKills: Int
    let systemId: Int
}

nonisolated struct ESISystemJumps: Codable, Sendable {
    let shipJumps: Int
    let systemId: Int
}

// MARK:  Sovereignty

/// One entry from GET /sovereignty/map/ — who holds a given solar system.
nonisolated struct ESISovereigntyMapEntry: Codable, Sendable {
    let systemId: Int
    let allianceId: Int?
    let corporationId: Int?
    let factionId: Int?
}

/// An active or upcoming sovereignty campaign from GET /sovereignty/campaigns/.
nonisolated struct ESISovereigntyCampaign: Codable, Sendable, Identifiable {
    let campaignId: Int
    let structureId: Int
    let solarSystemId: Int
    let constellationId: Int
    let eventType: String        // tcu_defense | ihub_defense | station_defense | station_freeport
    let startTime: Date
    let defenderId: Int?
    let defenderScore: Double?
    let attackersScore: Double?
    let participants: [Participant]?

    struct Participant: Codable, Sendable, Identifiable {
        let allianceId: Int
        let score: Double
        var id: Int { allianceId }
    }

    var id: Int { campaignId }
}

/// A claimed sovereignty structure (TCU / Infrastructure Hub) from GET /sovereignty/structures/.
nonisolated struct ESISovereigntyStructure: Codable, Sendable, Identifiable {
    let structureId: Int
    let structureTypeId: Int
    let allianceId: Int
    let solarSystemId: Int
    /// Activity Defense Multiplier, 1.0–6.0. Higher = harder to attack.
    let vulnerabilityOccupancyLevel: Double?
    let vulnerableStartTime: Date?
    let vulnerableEndTime: Date?

    var id: Int { structureId }
}

// MARK:  Market Orders

nonisolated struct ESIMarketOrder: Codable, Sendable, Identifiable {
    let duration: Int
    let escrow: Double?
    let isBuyOrder: Bool?
    let isCorporation: Bool
    let issued: Date
    let locationId: Int
    let minVolume: Int?
    let orderId: Int
    let price: Double
    let range: String
    let regionId: Int
    let typeId: Int
    let volumeRemain: Int
    let volumeTotal: Int
    let walletDivision: Int?

    var id: Int { orderId }
}

// MARK:  Loyalty Points

nonisolated struct ESILoyaltyPoints: Codable, Sendable {
    let corporationId: Int
    let loyaltyPoints: Int
}

// MARK:  LP Store

nonisolated struct ESILPStoreOffer: Codable, Sendable, Identifiable {
    let akCost: Int?
    let iskCost: Int
    let lpCost: Int
    let offerId: Int
    let quantity: Int
    let requiredItems: [ESILPStoreRequiredItem]
    let typeId: Int

    var id: Int { offerId }
}

nonisolated struct ESILPStoreRequiredItem: Codable, Sendable {
    let quantity: Int
    let typeId: Int
}

// MARK:  Search / Names

nonisolated struct ESIIDsResponse: Codable, Sendable {
    let characters: [ESIIDName]?
    let corporations: [ESIIDName]?
    let alliances: [ESIIDName]?
    let solarSystems: [ESIIDName]?
    let inventoryTypes: [ESIIDName]?

    enum CodingKeys: String, CodingKey {
        case characters, corporations, alliances
        case solarSystems = "systems"
        case inventoryTypes = "inventory_types"
    }
}

nonisolated struct ESIIDName: Codable, Sendable, Identifiable {
    let id: Int
    let name: String
}

nonisolated struct ESISearchResponse: Codable, Sendable {
    // convertFromSnakeCase on ESIClient's decoder maps "solar_system" → solarSystem automatically
    let solarSystem: [Int]?
}

