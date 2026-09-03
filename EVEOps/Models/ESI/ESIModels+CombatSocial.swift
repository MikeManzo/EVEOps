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

    /// ESI's flag enum differs between read (assets, GET fittings) and write (POST
    /// fittings) endpoints for Strategic Cruiser subsystem slots: reads use
    /// "SubSystem0".."SubSystem3", but POST /characters/{id}/fittings/ only accepts
    /// "SubSystemSlot0".."SubSystemSlot3". This app represents subsystem slots
    /// internally in the read-side form everywhere (SimSlotCategory, EFTSerializer,
    /// ESI asset locationFlag), so translate only when building a save request body.
    static func postFlag(_ internalFlag: String) -> String {
        guard internalFlag.hasPrefix("SubSystem"), !internalFlag.hasPrefix("SubSystemSlot") else {
            return internalFlag
        }
        return "SubSystemSlot" + internalFlag.dropFirst("SubSystem".count)
    }
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

