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

