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

/// Element of GET /fleets/{fleet_id}/members/
nonisolated struct ESIFleetMember: Codable, Sendable, Identifiable {
    let characterId: Int
    let joinTime: Date
    let role: String        // "fleet_commander", "wing_commander", "squad_commander", "squad_member"
    let roleName: String
    let shipTypeId: Int
    let solarSystemId: Int
    let squadId: Int
    let stationId: Int?
    let takesFleetWarp: Bool
    let wingId: Int

    var id: Int { characterId }
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

// MARK:  Medals

nonisolated struct ESIMedal: Codable, Sendable, Identifiable {
    let medalId: Int
    let title: String
    let description: String
    let corporationId: Int
    let issuerId: Int
    let date: Date
    let reason: String
    let status: String   // "public" | "private"
    let graphics: [ESIMedalGraphic]
    var id: Int { medalId }
}

nonisolated struct ESIMedalGraphic: Codable, Sendable {
    let color: Int?
    let graphic: String
    let layer: Int
    let part: Int
}

// MARK:  Faction Warfare

nonisolated struct ESIFWCharacterStats: Codable, Sendable {
    let enlistedOn: Date?
    let factionId: Int?
    let currentRank: Int?
    let highestRank: Int?
    let kills: ESIFWStatPeriod
    let victoryPoints: ESIFWStatPeriod
}

nonisolated struct ESIFWStatPeriod: Codable, Sendable {
    let yesterday: Int
    let lastWeek: Int
    let total: Int
}

nonisolated struct ESIFWSystem: Codable, Sendable {
    let contested: String
    let occupierFactionId: Int
    let ownerFactionId: Int
    let solarSystemId: Int
    let victoryPoints: Int
    let victoryPointsThreshold: Int
}

nonisolated struct ESIFWWar: Codable, Sendable {
    let againstId: Int
    let factionId: Int
}

nonisolated struct ESIFWLeaderboards: Codable, Sendable {
    let kills: ESIFWLeaderboardMetric
    let victoryPoints: ESIFWLeaderboardMetric
}

nonisolated struct ESIFWLeaderboardMetric: Codable, Sendable {
    let activeTotal: [ESIFWLeaderboardEntry]
    let lastWeek: [ESIFWLeaderboardEntry]
    let yesterday: [ESIFWLeaderboardEntry]
}

nonisolated struct ESIFWLeaderboardEntry: Codable, Sendable {
    let amount: Int
    let factionId: Int
}

// MARK:  Incursions

nonisolated struct ESIIncursion: Codable, Sendable, Identifiable {
    let constellationId: Int
    let factionId: Int
    let hasBoss: Bool
    let infestedSolarSystems: [Int]
    let influence: Double
    let stagingSolarSystemId: Int
    let state: String
    let type: String

    var id: Int { stagingSolarSystemId }
}

// MARK:  Universe Types

nonisolated struct ESIUniverseType: Decodable, Sendable {
    let typeId: Int
    let name: String
    let description: String
    let groupId: Int
    let marketGroupId: Int?
    let volume: Double?
    let packagedVolume: Double?
    let mass: Double?
    let capacity: Double?
    let portionSize: Int
    let published: Bool
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

// MARK:  Status

nonisolated struct ESIStatus: Codable, Sendable {
    let players: Int
    let serverVersion: String
    let startTime: Date
    let vip: Bool?
}

