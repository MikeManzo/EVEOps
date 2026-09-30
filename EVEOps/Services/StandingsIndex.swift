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
import Observation

/// The selected pilot's standings toward other characters, corporations and alliances,
/// so any screen can color a portrait friend-or-foe the way EVE does. Built from the
/// pilot's own contact list (the only contacts scope the app requests), plus the pilot's
/// own corporation and alliance, which EVE always shows as +10.
@MainActor
@Observable
final class StandingsIndex {
    static let shared = StandingsIndex()

    private var standings: [Int: Double] = [:]
    private var loadedCharacterID: Int?
    private var loadedAt: Date?

    private init() {}

    /// The most specific standing that applies: the character itself, then its
    /// corporation, then its alliance. `nil` when none of them are known.
    func standing(character: Int?, corporation: Int? = nil, alliance: Int? = nil) -> Double? {
        for id in [character, corporation, alliance] {
            if let id, let value = standings[id] { return value }
        }
        return nil
    }

    /// Loads (or refreshes after 10 minutes) the standings for `account`.
    func load(for account: StoredAccount, token: String) async {
        if loadedCharacterID == account.characterID,
           let loadedAt, Date().timeIntervalSince(loadedAt) < 600 { return }

        var result: [Int: Double] = [:]
        let contacts: [ESIContact] = (try? await ESIClient.shared.fetchPages(
            "/characters/\(account.characterID)/contacts/", token: token
        )) ?? []
        for contact in contacts { result[contact.contactId] = contact.standing }

        // Your own corporation and alliance read as blue, like in game.
        result[account.corporationID] = 10
        if let info: ESICharacterPublic = try? await ESIClient.shared.fetch("/characters/\(account.characterID)/"),
           let allianceID = info.allianceId {
            result[allianceID] = 10
        }

        standings = result
        loadedCharacterID = account.characterID
        loadedAt = Date()
    }
}
