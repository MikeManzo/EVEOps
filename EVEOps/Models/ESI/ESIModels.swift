import Foundation

// MARK: - Character

struct ESICharacterPublic: Codable, Sendable {
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

struct ESICharacterPortrait: Codable, Sendable {
    let px64x64: String?
    let px128x128: String?
    let px256x256: String?
    let px512x512: String?
}

// MARK: - Location & Ship

struct ESICharacterLocation: Codable, Sendable {
    let solarSystemId: Int
    let stationId: Int?
    let structureId: Int?
}

struct ESICharacterShip: Codable, Sendable {
    let shipItemId: Int
    let shipName: String
    let shipTypeId: Int
}

struct ESICharacterOnline: Codable, Sendable {
    let lastLogin: Date?
    let lastLogout: Date?
    let logins: Int?
    let online: Bool
}

// MARK: - Skills

struct ESISkillQueue: Codable, Sendable {
    let finishDate: Date?
    let finishedLevel: Int
    let levelEndSp: Int?
    let levelStartSp: Int?
    let queuePosition: Int
    let skillId: Int
    let startDate: Date?
    let trainingStartSp: Int?
}

struct ESISkillsResponse: Codable, Sendable {
    let skills: [ESISkill]
    let totalSp: Int
    let unallocatedSp: Int?
}

struct ESISkill: Codable, Sendable {
    let activeSkillLevel: Int
    let skillId: Int
    let skillpointsInSkill: Int
    let trainedSkillLevel: Int
}

// MARK: - Wallet

struct ESIWalletJournalEntry: Codable, Sendable, Identifiable {
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

struct ESIWalletTransaction: Codable, Sendable, Identifiable {
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

// MARK: - Assets

struct ESIAsset: Codable, Sendable, Identifiable {
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

struct ESIAssetName: Codable, Sendable {
    let itemId: Int
    let name: String
}

// MARK: - Clones

struct ESIClonesResponse: Codable, Sendable {
    let homeLocation: ESIHomeLocation?
    let jumpClones: [ESIJumpClone]
    let lastCloneJumpDate: Date?
    let lastStationChangeDate: Date?
}

struct ESIHomeLocation: Codable, Sendable {
    let locationId: Int?
    let locationType: String?
}

struct ESIJumpClone: Codable, Sendable, Identifiable {
    let implants: [Int]
    let jumpCloneId: Int
    let locationId: Int
    let locationType: String
    let name: String?

    var id: Int { jumpCloneId }
}

struct ESIImplant: Codable, Sendable {
    let typeId: Int
}

// MARK: - Planetary Interaction (PI)

struct ESIColony: Codable, Sendable, Identifiable {
    let lastUpdate: Date
    let numPins: Int
    let ownerId: Int
    let planetId: Int
    let planetType: String
    let solarSystemId: Int
    let upgradeLevel: Int

    var id: Int { planetId }
}

struct ESIColonyLayout: Codable, Sendable {
    let links: [ESIPlanetLink]
    let pins: [ESIPlanetPin]
    let routes: [ESIPlanetRoute]
}

struct ESIPlanetLink: Codable, Sendable {
    let destinationPinId: Int
    let linkLevel: Int
    let sourcePinId: Int
}

struct ESIPlanetPin: Codable, Sendable, Identifiable {
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

struct ESIPinContent: Codable, Sendable {
    let amount: Int
    let typeId: Int
}

struct ESIExtractorDetails: Codable, Sendable {
    let cycleTime: Int?
    let headRadius: Double?
    let heads: [ESIExtractorHead]
    let productTypeId: Int?
    let qtyPerCycle: Int?
}

struct ESIExtractorHead: Codable, Sendable {
    let headId: Int
    let latitude: Double
    let longitude: Double
}

struct ESIFactoryDetails: Codable, Sendable {
    let schematicId: Int
}

struct ESIPlanetRoute: Codable, Sendable {
    let contentTypeId: Int
    let destinationPinId: Int
    let quantity: Double
    let routeId: Int
    let sourcePinId: Int
    let waypoints: [Int]?
}

// MARK: - Contracts

struct ESIContract: Codable, Sendable, Identifiable {
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

// MARK: - Industry

struct ESIIndustryJob: Codable, Sendable, Identifiable {
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

// MARK: - Mail

struct ESIMailHeader: Codable, Sendable, Identifiable {
    let from: Int?
    let isRead: Bool?
    let labels: [Int]?
    let mailId: Int?
    let recipients: [ESIMailRecipient]?
    let subject: String?
    let timestamp: Date?

    var id: Int { mailId ?? 0 }
}

struct ESIMailRecipient: Codable, Sendable {
    let recipientId: Int
    let recipientType: String
}

struct ESIMailBody: Codable, Sendable {
    let body: String?
    let from: Int?
    let labels: [Int]?
    let read: Bool?
    let subject: String?
    let timestamp: Date?
}

struct ESIMailLabel: Codable, Sendable, Identifiable {
    let color: String?
    let labelId: Int?
    let name: String?
    let unreadCount: Int?

    var id: Int { labelId ?? 0 }
}

struct ESIMailLabelsResponse: Codable, Sendable {
    let labels: [ESIMailLabel]?
    let totalUnreadCount: Int?
}

// MARK: - Notifications

struct ESINotification: Codable, Sendable, Identifiable {
    let isRead: Bool?
    let notificationId: Int
    let senderId: Int
    let senderType: String
    let text: String?
    let timestamp: Date
    let type: String

    var id: Int { notificationId }
}

// MARK: - Corporation

struct ESICorporationPublic: Codable, Sendable {
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

struct ESICorporationMember: Codable, Sendable {
    let characterId: Int
}

struct ESICorporationStructure: Codable, Sendable, Identifiable {
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

struct ESIStructureService: Codable, Sendable {
    let name: String
    let state: String
}

// MARK: - Universe Lookups

struct ESIType: Codable, Sendable {
    let capacity: Double?
    let description: String?
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

struct ESISolarSystem: Codable, Sendable {
    let constellationId: Int
    let name: String
    let securityClass: String?
    let securityStatus: Double
    let starId: Int?
    let systemId: Int
}

struct ESIStation: Codable, Sendable {
    let name: String
    let stationId: Int
    let systemId: Int
    let typeId: Int
}

struct ESIStructure: Codable, Sendable {
    let name: String
    let ownerId: Int
    let solarSystemId: Int
    let typeId: Int?
}

struct ESIConstellation: Codable, Sendable {
    let constellationId: Int
    let name: String
    let regionId: Int
}

struct ESIRegion: Codable, Sendable {
    let name: String
    let regionId: Int
}

// MARK: - Search / Names

struct ESIIDsResponse: Codable, Sendable {
    let characters: [ESIIDName]?
    let corporations: [ESIIDName]?
    let alliances: [ESIIDName]?
}

struct ESIIDName: Codable, Sendable, Identifiable {
    let id: Int
    let name: String
}

// MARK: - Token Verification (JWT)

struct ESITokenCharacter: Sendable {
    let characterID: Int
    let characterName: String
    let scopes: [String]
    let expiresOn: Date
}
