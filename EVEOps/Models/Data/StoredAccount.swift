import Foundation
import SwiftData

@Model
final class StoredAccount {
    @Attribute(.unique) var characterID: Int
    var characterName: String
    var corporationID: Int
    var corporationName: String
    var allianceID: Int?
    var allianceName: String?
    var portraitURL: String?
    var accessToken: String
    var refreshToken: String
    var tokenExpiry: Date
    var scopes: [String]
    var addedDate: Date
    var lastRefresh: Date?

    init(
        characterID: Int,
        characterName: String,
        corporationID: Int,
        corporationName: String = "",
        allianceID: Int? = nil,
        allianceName: String? = nil,
        portraitURL: String? = nil,
        accessToken: String,
        refreshToken: String,
        tokenExpiry: Date,
        scopes: [String] = [],
        addedDate: Date = Date()
    ) {
        self.characterID = characterID
        self.characterName = characterName
        self.corporationID = corporationID
        self.corporationName = corporationName
        self.allianceID = allianceID
        self.allianceName = allianceName
        self.portraitURL = portraitURL
        self.accessToken = accessToken
        self.refreshToken = refreshToken
        self.tokenExpiry = tokenExpiry
        self.scopes = scopes
        self.addedDate = addedDate
    }

    var isTokenExpired: Bool {
        // Treat token as expired 30 seconds early to guard against clock skew
        // and the latency of sending a nearly-expired token to ESI.
        Date() >= tokenExpiry.addingTimeInterval(-30)
    }

    var portraitImageURL: URL? {
        URL(string: "https://images.evetech.net/characters/\(characterID)/portrait?size=128")
    }
}
