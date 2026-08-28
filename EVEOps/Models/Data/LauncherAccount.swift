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
import SwiftData

/// A CCP launcher-auth session (client_id `eveLauncherTQ`) — deliberately separate from
/// `StoredAccount`, which is shaped for ESI's character/corp/alliance data. This only needs
/// enough to verify/launch the game client for one character.
@Model
final class LauncherAccount {
    @Attribute(.unique) var characterID: Int
    var characterName: String
    var accessToken: String
    var refreshToken: String
    var tokenExpiry: Date
    var scopes: [String]
    var addedDate: Date
    var needsReauth: Bool = false

    init(
        characterID: Int,
        characterName: String,
        accessToken: String,
        refreshToken: String,
        tokenExpiry: Date,
        scopes: [String] = [],
        addedDate: Date = Date()
    ) {
        self.characterID = characterID
        self.characterName = characterName
        self.accessToken = accessToken
        self.refreshToken = refreshToken
        self.tokenExpiry = tokenExpiry
        self.scopes = scopes
        self.addedDate = addedDate
    }

    var isTokenExpired: Bool {
        Date() >= tokenExpiry.addingTimeInterval(-30)
    }

    var portraitImageURL: URL? {
        URL(string: "https://images.evetech.net/characters/\(characterID)/portrait?size=128")
    }
}
