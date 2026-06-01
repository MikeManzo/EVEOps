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

// MARK:  Character

nonisolated struct ESICharacterPublic: Codable, Sendable {
    let allianceId: Int?
    let birthday: Date
    let bloodlineId: Int
    let corporationId: Int
    let description: String?
    let gender: String
    let name: String
    let raceId: Int
    let securityStatus: Double?
    let title: String?
}

nonisolated struct ESICharacterPortrait: Codable, Sendable {
    let px64x64: String?
    let px128x128: String?
    let px256x256: String?
    let px512x512: String?
}

// MARK:  Location & Ship

nonisolated struct ESICharacterLocation: Codable, Sendable {
    let solarSystemId: Int
    let stationId: Int?
    let structureId: Int?
}

nonisolated struct ESICharacterShip: Codable, Sendable {
    let shipItemId: Int
    let shipName: String
    let shipTypeId: Int
}

nonisolated struct ESICharacterOnline: Codable, Sendable {
    let lastLogin: Date?
    let lastLogout: Date?
    let logins: Int?
    let online: Bool
}

// MARK:  Skills

nonisolated struct ESISkillQueue: Codable, Sendable {
    let finishDate: Date?
    let finishedLevel: Int
    let levelEndSp: Int?
    let levelStartSp: Int?
    let queuePosition: Int
    let skillId: Int
    let startDate: Date?
    let trainingStartSp: Int?
}

nonisolated struct ESISkillsResponse: Codable, Sendable {
    let skills: [ESISkill]
    let totalSp: Int
    let unallocatedSp: Int?
}

nonisolated struct ESISkill: Codable, Sendable {
    let activeSkillLevel: Int
    let skillId: Int
    let skillpointsInSkill: Int
    let trainedSkillLevel: Int
}

// MARK:  Wallet

nonisolated struct ESIWalletJournalEntry: Codable, Sendable, Identifiable {
    let amount: Double?
    let balance: Double?
    let contextId: Int?
    let contextIdType: String?
    let date: Date
    let description: String
    let firstPartyId: Int?
    let id: Int
    let reason: String?
    let refType: String
    let secondPartyId: Int?
    let tax: Double?
    let taxReceiverId: Int?
}

nonisolated struct ESIWalletTransaction: Codable, Sendable, Identifiable {
    let clientId: Int
    let date: Date
    let isBuy: Bool
    let isPersonal: Bool
    let journalRefId: Int
    let locationId: Int
    let quantity: Int
    let transactionId: Int
    let typeId: Int
    let unitPrice: Double

    var id: Int { transactionId }
}

// MARK:  Assets

nonisolated struct ESIAsset: Codable, Sendable, Identifiable {
    let isBlueprintCopy: Bool?
    let isSingleton: Bool
    let itemId: Int
    let locationFlag: String
    let locationId: Int
    let locationType: String
    let quantity: Int
    let typeId: Int

    var id: Int { itemId }
}

nonisolated struct ESIAssetName: Codable, Sendable {
    let itemId: Int
    let name: String
}

// MARK:  Clones

nonisolated struct ESIClonesResponse: Codable, Sendable {
    let homeLocation: ESIHomeLocation?
    let jumpClones: [ESIJumpClone]
    let lastCloneJumpDate: Date?
    let lastStationChangeDate: Date?
}

nonisolated struct ESIHomeLocation: Codable, Sendable {
    let locationId: Int?
    let locationType: String?
}

nonisolated struct ESIJumpClone: Codable, Sendable, Identifiable {
    let implants: [Int]
    let jumpCloneId: Int
    let locationId: Int
    let locationType: String
    let name: String?

    var id: Int { jumpCloneId }
}

nonisolated struct ESIImplant: Codable, Sendable {
    let typeId: Int
}

// MARK:  Planetary Interaction (PI)

nonisolated struct ESIColony: Codable, Sendable, Identifiable {
    let lastUpdate: Date
    let numPins: Int
    let ownerId: Int
    let planetId: Int
    let planetType: String
    let solarSystemId: Int
    let upgradeLevel: Int

    var id: Int { planetId }
}

nonisolated struct ESIColonyLayout: Codable, Sendable {
    let links: [ESIPlanetLink]
    let pins: [ESIPlanetPin]
    let routes: [ESIPlanetRoute]
}

nonisolated struct ESIPlanetLink: Codable, Sendable {
    let destinationPinId: Int
    let linkLevel: Int
    let sourcePinId: Int
}

nonisolated struct ESIPlanetPin: Codable, Sendable, Identifiable {
    let contents: [ESIPinContent]?
    let expiryTime: Date?
    let extractorDetails: ESIExtractorDetails?
    let factoryDetails: ESIFactoryDetails?
    let installTime: Date?
    let lastCycleStart: Date?
    let latitude: Double
    let longitude: Double
    let pinId: Int
    let schematicId: Int?
    let typeId: Int

    var id: Int { pinId }
}

nonisolated struct ESIPinContent: Codable, Sendable {
    let amount: Int
    let typeId: Int
}

nonisolated struct ESIExtractorDetails: Codable, Sendable {
    let cycleTime: Int?
    let headRadius: Double?
    let heads: [ESIExtractorHead]
    let productTypeId: Int?
    let qtyPerCycle: Int?
}

nonisolated struct ESIExtractorHead: Codable, Sendable {
    let headId: Int
    let latitude: Double
    let longitude: Double
}

nonisolated struct ESIFactoryDetails: Codable, Sendable {
    let schematicId: Int
}

nonisolated struct ESIPlanetRoute: Codable, Sendable {
    let contentTypeId: Int
    let destinationPinId: Int
    let quantity: Double
    let routeId: Int
    let sourcePinId: Int
    let waypoints: [Int]?
}

// MARK:  Contracts

nonisolated struct ESIContract: Codable, Sendable, Identifiable {
    let acceptorId: Int
    let assigneeId: Int
    let availability: String
    let buyout: Double?
    let collateral: Double?
    let contractId: Int
    let dateAccepted: Date?
    let dateCompleted: Date?
    let dateExpired: Date
    let dateIssued: Date
    let daysToComplete: Int?
    let endLocationId: Int?
    let forCorporation: Bool
    let issuerId: Int
    let issuerCorporationId: Int
    let price: Double?
    let reward: Double?
    let startLocationId: Int?
    let status: String
    let title: String?
    let type: String
    let volume: Double?

    var id: Int { contractId }
}

// MARK:  Industry

nonisolated struct ESIIndustryJob: Codable, Sendable, Identifiable {
    let activityId: Int
    let blueprintId: Int
    let blueprintLocationId: Int
    let blueprintTypeId: Int
    let completedCharacterId: Int?
    let completedDate: Date?
    let cost: Double?
    let duration: Int
    let endDate: Date
    let facilityId: Int
    let installerId: Int
    let jobId: Int
    let licensedRuns: Int?
    let outputLocationId: Int
    let pauseDate: Date?
    let probability: Double?
    let productTypeId: Int?
    let runs: Int
    let startDate: Date
    let stationId: Int
    let status: String
    let successfulRuns: Int?

    var id: Int { jobId }
}

// MARK:  Mail

nonisolated struct ESIMailHeader: Codable, Sendable, Identifiable, Hashable, Equatable {
    let from: Int?
    let isRead: Bool?
    let labels: [Int]?
    let mailId: Int?
    let recipients: [ESIMailRecipient]?
    let subject: String?
    let timestamp: Date?

    var id: Int { mailId ?? 0 }
}

nonisolated struct ESIMailRecipient: Codable, Sendable, Hashable {
    let recipientId: Int
    let recipientType: String
}

nonisolated struct ESIMailBody: Codable, Sendable {
    let body: String?
    let from: Int?
    let labels: [Int]?
    let read: Bool?
    let subject: String?
    let timestamp: Date?
}

nonisolated struct ESIMailLabel: Codable, Sendable, Identifiable {
    let color: String?
    let labelId: Int?
    let name: String?
    let unreadCount: Int?

    var id: Int { labelId ?? 0 }
}

nonisolated struct ESIMailLabelsResponse: Codable, Sendable {
    let labels: [ESIMailLabel]?
    let totalUnreadCount: Int?
}

// MARK:  Notifications

nonisolated struct ESINotification: Codable, Sendable, Identifiable, Hashable {
    let isRead: Bool?
    let notificationId: Int
    let senderId: Int
    let senderType: String
    let text: String?
    let timestamp: Date
    let type: String

    var id: Int { notificationId }
}

// MARK:  Corporation

nonisolated struct ESIAlliancePublic: Codable, Sendable {
    let name: String
    let ticker: String
    let executorCorporationId: Int?
    let creatorId: Int
    let creatorCorporationId: Int
    let dateFounded: Date?
    let factionId: Int?
}

nonisolated struct ESICorporationPublic: Codable, Sendable {
    let allianceId: Int?
    let ceoId: Int
    let creatorId: Int
    let dateFounded: Date?
    let description: String?
    let homeStationId: Int?
    let memberCount: Int
    let name: String
    let shares: Int?
    let taxRate: Double
    let ticker: String
    let url: String?
    let warEligible: Bool?
}

nonisolated struct ESICorporationMember: Codable, Sendable {
    let characterId: Int
}

nonisolated struct ESIMemberTracking: Codable, Sendable {
    let characterId: Int
    let locationId: Int?
    let logoffDate: Date?
    let logonDate: Date?
    let shipTypeId: Int?
    let startDate: Date?
    let systemId: Int?
}

nonisolated struct ESICorporationTitle: Codable, Sendable {
    let name: String?
    let titleId: Int
}

nonisolated struct ESIMemberTitle: Codable, Sendable {
    let characterId: Int
    let titles: [ESIMemberTitleEntry]
}

nonisolated struct ESIMemberTitleEntry: Codable, Sendable {
    let titleId: Int
    let name: String?
}

nonisolated struct ESIMemberRoles: Codable, Sendable {
    let characterId: Int
    let roles: [String]?
    let rolesAtHq: [String]?
    let rolesAtBase: [String]?
    let rolesAtOther: [String]?
}

nonisolated struct ESICorporationHistory: Codable, Sendable {
    let corporationId: Int
    let isDeleted: Bool?
    let recordId: Int
    let startDate: Date
}

nonisolated struct ESICorporationDivisions: Codable, Sendable {
    let hangar: [ESIDivisionEntry]?
    let wallet: [ESIDivisionEntry]?
}

nonisolated struct ESIDivisionEntry: Codable, Sendable {
    let division: Int
    let name: String?
}

nonisolated struct ESICorporationStructure: Codable, Sendable, Identifiable {
    let corporationId: Int
    let fuelExpires: Date?
    let name: String
    let nextReinforceApply: Date?
    let nextReinforceHour: Int?
    let profileId: Int
    let reinforceHour: Int?
    let services: [ESIStructureService]?
    let state: String
    let stateTimerEnd: Date?
    let stateTimerStart: Date?
    let structureId: Int
    let systemId: Int
    let typeId: Int
    let unanchorsAt: Date?

    var id: Int { structureId }
}

nonisolated struct ESIStructureService: Codable, Sendable {
    let name: String
    let state: String
}

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
    let position: ESIPosition?
    let securityClass: String?
    let securityStatus: Double
    let starId: Int?
    let stargates: [Int]?
    let stations: [Int]?
    let systemId: Int
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

// MARK:  Kill Mails

nonisolated struct ESIKillmailRef: Codable, Sendable, Identifiable {
    let killmailHash: String
    let killmailId: Int
    var id: Int { killmailId }
}

nonisolated struct ESIKillmail: Codable, Sendable, Identifiable {
    let attackers: [ESIKillmailAttacker]
    let killmailId: Int
    let killmailTime: Date
    let moonId: Int?
    let solarSystemId: Int
    let victim: ESIKillmailVictim
    let warId: Int?
    var id: Int { killmailId }
}

nonisolated struct ESIKillmailAttacker: Codable, Sendable {
    let allianceId: Int?
    let characterId: Int?
    let corporationId: Int?
    let damageDone: Int
    let finalBlow: Bool
    let securityStatus: Double
    let shipTypeId: Int?
    let weaponTypeId: Int?
}

nonisolated struct ESIKillmailVictim: Codable, Sendable {
    let allianceId: Int?
    let characterId: Int?
    let corporationId: Int?
    let damageTaken: Int
    let items: [ESIKillmailItem]?
    let position: ESIPosition?
    let shipTypeId: Int
}

nonisolated struct ESIKillmailItem: Codable, Sendable {
    let flag: Int
    let itemTypeId: Int
    let quantityDestroyed: Int?
    let quantityDropped: Int?
    let singleton: Int
}

// MARK:  Fittings

nonisolated struct ESIFitting: Codable, Sendable, Identifiable, Hashable {
    let description: String
    let fittingId: Int
    let items: [ESIFittingItem]
    let name: String
    let shipTypeId: Int
    var id: Int { fittingId }
}

nonisolated struct ESIFittingItem: Codable, Sendable, Identifiable, Hashable {
    let flag: String
    let quantity: Int
    let typeId: Int
    var id: String { "\(flag)-\(typeId)" }
}

/// Body for POST /characters/{id}/fittings/
nonisolated struct ESIFittingSaveRequest: Encodable, Sendable {
    let description: String
    let items: [ESIFittingItemSave]
    let name: String
    let shipTypeId: Int
}

nonisolated struct ESIFittingItemSave: Encodable, Sendable {
    let flag: String
    let quantity: Int
    let typeId: Int
}

/// Response from POST /characters/{id}/fittings/ — returns the new fitting's ID
nonisolated struct ESIFittingCreatedResponse: Decodable, Sendable {
    let fittingId: Int
}

// MARK:  Calendar

nonisolated struct ESICalendarEvent: Codable, Sendable, Identifiable {
    let eventDate: Date?
    let eventId: Int
    let eventResponse: String?
    let importance: Int?
    let title: String?
    var id: Int { eventId }
}

nonisolated struct ESICalendarEventDetail: Codable, Sendable {
    let date: Date
    let duration: Int
    let eventId: Int
    let importance: Int
    let ownerId: Int?
    let ownerName: String?
    let ownerType: String?
    let response: String
    let text: String
    let title: String
}

// MARK:  Contacts

nonisolated struct ESIContact: Codable, Sendable, Identifiable {
    let contactId: Int
    let contactType: String
    let isBlocked: Bool?
    let isWatched: Bool?
    let labelIds: [Int]?
    let standing: Double

    var id: Int { contactId }

    /// Player characters have IDs >= 90,000,000; anything below is an NPC (agent, etc.)
    var isPlayerCharacter: Bool { contactType == "character" && contactId >= 90_000_000 }

    var displayTypeLabel: String {
        switch contactType {
        case "character":   return isPlayerCharacter ? "Player" : "NPC"
        case "corporation": return "Corporation"
        case "alliance":    return "Alliance"
        case "faction":     return "Faction"
        default:            return contactType.capitalized
        }
    }

    var imageURL: URL? {
        switch contactType {
        case "character":   return EVEImageURL.characterPortrait(contactId, size: 64)
        case "corporation": return EVEImageURL.corporationLogo(contactId, size: 64)
        case "alliance":    return EVEImageURL.allianceLogo(contactId, size: 64)
        case "faction":     return EVEImageURL.corporationLogo(contactId, size: 64)
        default:            return nil
        }
    }
}

nonisolated struct ESIContactLabel: Codable, Sendable, Identifiable {
    let labelId: Int
    let labelName: String
    var id: Int { labelId }
}

// MARK:  Factions

nonisolated struct ESIFaction: Codable, Sendable, Identifiable {
    let factionId: Int
    let name: String
    let description: String
    let solarSystemId: Int?
    let corporationId: Int?
    let militiaCorporationId: Int?
    let stationCount: Int?
    let stationSystemCount: Int?
    let sizeFactor: Double?
    let isUnique: Bool?
    var id: Int { factionId }
}

// MARK:  Standings

nonisolated struct ESIStanding: Codable, Sendable, Identifiable {
    let fromId: Int
    let fromType: String
    let standing: Double
    var id: Int { fromId }
}

// MARK:  Mining

nonisolated struct ESIMiningObserver: Codable, Sendable, Identifiable {
    let lastUpdated: Date
    let observerId: Int
    let observerType: String
    var id: Int { observerId }
}

nonisolated struct ESIMiningLedgerEntry: Codable, Sendable {
    let characterId: Int
    let lastUpdated: Date
    let quantity: Int
    let recordedCorporationId: Int
    let typeId: Int
}

// MARK:  Write Request Models

/// Body for sending a new mail via POST /characters/{id}/mail/
nonisolated struct ESIMailSendRequest: Encodable, Sendable {
    let body: String
    let recipients: [ESIMailRecipient]
    let subject: String
}

/// Body for responding to a calendar event via PUT /characters/{id}/calendar/{event_id}/
nonisolated struct ESICalendarResponseRequest: Encodable, Sendable {
    let response: String // "accepted", "declined", "tentative"
}

// MARK:  Fleet

nonisolated struct ESIFleetInfo: Codable, Sendable {
    let fleetId: Int
    let role: String   // "fleet_commander", "wing_commander", "squad_commander", "squad_member"
    let squadId: Int
    let wingId: Int
}

/// Body for POST /fleets/{fleet_id}/members/
nonisolated struct ESIFleetInvite: Encodable, Sendable {
    let characterId: Int
    let role: String
}

// MARK:  Token Verification (JWT)

nonisolated struct ESITokenCharacter: Sendable {
    let characterID: Int
    let characterName: String
    let scopes: [String]
    let expiresOn: Date
}

// MARK:  Market (Region)

/// Market order from GET /markets/{region_id}/orders/ — different from character orders (ESIMarketOrder)
nonisolated struct ESIRegionMarketOrder: Codable, Sendable, Identifiable {
    let duration: Int
    let isBuyOrder: Bool
    let issued: Date
    let locationId: Int
    let minVolume: Int
    let orderId: Int
    let price: Double
    let range: String
    let systemId: Int
    let typeId: Int
    let volumeRemain: Int
    let volumeTotal: Int

    var id: Int { orderId }
}

/// One day of price history from GET /markets/{region_id}/history/
nonisolated struct ESIMarketHistory: Codable, Sendable, Identifiable {
    let average: Double
    let date: String   // "YYYY-MM-DD"
    let highest: Double
    let lowest: Double
    let orderCount: Int
    let volume: Int

    var id: String { date }
}

/// Adjusted and average prices from GET /markets/prices/
nonisolated struct ESIMarketPrice: Codable, Sendable {
    let adjustedPrice: Double?
    let averagePrice: Double?
    let typeId: Int
}

// MARK:  Character Attributes (Remap Advisor)

nonisolated struct ESICharacterAttributes: Codable, Sendable {
    let charisma: Int
    let intelligence: Int
    let memory: Int
    let perception: Int
    let willpower: Int
    let bonusRemaps: Int?
    let accruedRemapCooldownDate: Date?
    let lastRemapDate: Date?
}

// MARK:  Research Agents

nonisolated struct ESIResearchAgent: Codable, Sendable, Identifiable {
    let agentId: Int
    let remainderPoints: Double
    let pointsPerDay: Double
    let skillTypeId: Int
    let startedAt: Date
    var id: Int { agentId }
}

// MARK:  Wars

nonisolated struct ESIWar: Codable, Sendable, Identifiable {
    let aggressor: ESIWarParty
    let allies: [ESIWarAlly]?
    let declared: Date
    let defender: ESIWarParty
    let finished: Date?
    let id: Int
    let mutual: Bool
    let openForAllies: Bool
    let retracted: Date?
    let started: Date?

    var isActive: Bool { finished == nil && retracted == nil }
}

nonisolated struct ESIWarParty: Codable, Sendable {
    let allianceId: Int?
    let corporationId: Int?
    let iskDestroyed: Double
    let shipsKilled: Int
}

nonisolated struct ESIWarAlly: Codable, Sendable {
    let allianceId: Int?
    let corporationId: Int?
}

// MARK:  Bookmarks

nonisolated struct ESIBookmarkFolder: Codable, Sendable, Identifiable {
    let folderId: Int?
    let name: String?
    var id: Int { folderId ?? 0 }
}

nonisolated struct ESIBookmark: Codable, Sendable, Identifiable {
    let bookmarkId: Int
    let created: Date
    let creatorId: Int
    let folderId: Int?
    let item: ESIBookmarkItem?
    let label: String?
    let locationId: Int
    let memo: String?
    let coordinates: ESIBookmarkCoordinates?
    var id: Int { bookmarkId }
}

nonisolated struct ESIBookmarkItem: Codable, Sendable {
    let itemId: Int
    let typeId: Int
}

nonisolated struct ESIBookmarkCoordinates: Codable, Sendable {
    let x: Double
    let y: Double
    let z: Double
}

// MARK:  PI Schematics

nonisolated struct ESIPlanetSchematic: Codable, Sendable {
    let cycleTime: Int
    let schematicName: String
    let pins: [ESISchematicPin]
}

nonisolated struct ESISchematicPin: Codable, Sendable {
    let isInput: Bool
    let quantity: Int
    let typeId: Int
}

// MARK:  Character Year Stats

nonisolated struct ESICharacterYearStats: Codable, Sendable, Identifiable {
    let year: Int
    let character: ESIYearStatsSession?
    let combat: ESIYearStatsCombat?
    let industry: ESIYearStatsIndustry?
    let isk: ESIYearStatsISK?
    let market: ESIYearStatsMarket?
    let mining: ESIYearStatsMining?
    let pve: ESIYearStatsPVE?
    let social: ESIYearStatsSocial?
    let travel: ESIYearStatsTravel?
    var id: Int { year }
}

nonisolated struct ESIYearStatsSession: Codable, Sendable {
    let daysOfActivity: Int?
    let minutes: Int?
    let sessionsStarted: Int?
}

nonisolated struct ESIYearStatsCombat: Codable, Sendable {
    let pvpKills: Int?
    let npcKills: Int?
    let killsHighSec: Int?
    let killsLowSec: Int?
    let killsNullSec: Int?
    let lossesHighSec: Int?
    let lossesLowSec: Int?
    let lossesNullSec: Int?
    let damageToPlayersAmountDealt: Int?
    let damageFromPlayersAmountReceived: Int?
    let damageToNpcsAmountDealt: Int?
}

nonisolated struct ESIYearStatsIndustry: Codable, Sendable {
    let hackingSuccesses: Int?
    let jobsCompletedManufacture: Int?
    let jobsStartedManufacture: Int?
    let jobsCompletedCopyBlueprint: Int?
    let jobsStartedCopyBlueprint: Int?
    let jobsStartedReaction: Int?
    let jobsCancelled: Int?
}

nonisolated struct ESIYearStatsISK: Codable, Sendable {
    let iskIn: Int?
    let iskOut: Int?

    enum CodingKeys: String, CodingKey {
        case iskIn = "in"
        case iskOut = "out"
    }
}

nonisolated struct ESIYearStatsMarket: Codable, Sendable {
    let buyOrdersPlaced: Int?
    let sellOrdersPlaced: Int?
    let buyOrdersCancelled: Int?
    let sellOrdersCancelled: Int?
}

nonisolated struct ESIYearStatsMining: Codable, Sendable {
    let oreMined: Int?
    let wasteQuantity: Int?
}

nonisolated struct ESIYearStatsPVE: Codable, Sendable {
    let dungeonsCompletedAgent: Int?
    let dungeonsCompletedDistribution: Int?
    let missionsSucceeded: Int?
    let missionsSucceededEpicArc: Int?
}

nonisolated struct ESIYearStatsSocial: Codable, Sendable {
    let fleetJoins: Int?
    let mailsSent: Int?
    let mailsReceived: Int?
    let corporationApplicationAccepted: Int?
    let addedAsContactHigh: Int?
    let addedAsContactGood: Int?
}

nonisolated struct ESIYearStatsTravel: Codable, Sendable {
    let jumps: Int?
    let warps: Int?
    let docks: Int?
    let wormholesVisited: Int?
    let accelerationGateActivations: Int?
}

// MARK:  Moon Extractions

nonisolated struct ESIMoonExtraction: Codable, Sendable, Identifiable {
    let chunkArrivalTime: Date
    let extractionStartTime: Date
    let moonId: Int
    let naturalDecayTime: Date
    let structureId: Int

    var id: Int { structureId }
}

