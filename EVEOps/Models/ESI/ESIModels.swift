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

nonisolated extension Array where Element == ESIWalletJournalEntry {
    /// ISK made/spent since local midnight (today's calendar day, resets at midnight in the user's time zone).
    var todayISKSummary: (made: Double, spent: Double) {
        let startOfDay = Calendar.current.startOfDay(for: Date())
        var made = 0.0
        var spent = 0.0
        for entry in self where entry.date >= startOfDay {
            guard let amount = entry.amount else { continue }
            if amount > 0 { made += amount } else { spent += -amount }
        }
        return (made, spent)
    }
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

