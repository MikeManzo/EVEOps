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

// Mark:  Models

struct ZKBRef: Decodable, Sendable {
    let killmailId: Int
    let zkb: ZKBMeta
}

struct ZKBMeta: Decodable, Sendable {
    let hash: String
    let locationID: Int?
    let totalValue: Double?
    let fittedValue: Double?
    let droppedValue: Double?
    let destroyedValue: Double?
    let npc: Bool?
    let solo: Bool?
    let awox: Bool?
    let points: Int?

    var isNPC: Bool  { npc  ?? false }
    var isSolo: Bool { solo ?? false }
    var isAWOX: Bool { awox ?? false }
}

/// A subset of zKillboard's aggregate character stats — the rest of the payload
/// (top ships/systems, monthly breakdowns, trophy history, etc.) isn't needed here,
/// and `Decodable` just ignores keys this struct doesn't declare. All optional
/// because a character with no killboard history at all returns a much smaller
/// payload missing every one of these fields, rather than zeros.
nonisolated struct ZKBCharacterStats: Decodable, Sendable, Hashable {
    let shipsDestroyed: Int?
    let shipsLost: Int?
    let iskDestroyed: Double?
    let iskLost: Double?
    /// zKillboard's own 0–100 "how much of a threat" score, derived from their
    /// kill/loss/gang history — not an ESI/CCP value.
    let dangerRatio: Double?
    /// 0–100: how often they fight in a gang vs. alone.
    let gangRatio: Double?
    let soloRatio: Double?
}

// Mark:  Client

actor ZKillboardClient {
    static let shared = ZKillboardClient()

    private let session: URLSession

    private init() {
        let config = URLSessionConfiguration.default
        config.httpAdditionalHeaders = [
            "Accept": "application/json",
            "User-Agent": HTTPClientInfo.userAgent
        ]
        session = URLSession(configuration: config)
    }

    /// Fetches the first page of recent kills for a given region from zKillboard.
    func fetchRecentKillRefs(regionId: Int) async throws -> [ZKBRef] {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let url = URL(string: "https://zkillboard.com/api/kills/regionID/\(regionId)/page/1/")!
        let (data, response) = try await session.data(for: URLRequest(url: url))
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else { return [] }
        return (try? decoder.decode([ZKBRef].self, from: data)) ?? []
    }

    /// Fetches the first page of loss refs for a ship type from zKillboard (community losses).
    func fetchLossRefs(shipTypeID: Int) async throws -> [ZKBRef] {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let url = URL(string: "https://zkillboard.com/api/losses/shipTypeID/\(shipTypeID)/page/1/")!
        let (data, response) = try await session.data(for: URLRequest(url: url))
        guard let http = response as? HTTPURLResponse else { return [] }
        if http.statusCode == 429 {
            try await Task.sleep(nanoseconds: 5_000_000_000)
            return try await fetchLossRefs(shipTypeID: shipTypeID)
        }
        guard http.statusCode == 200 else { return [] }
        return (try? decoder.decode([ZKBRef].self, from: data)) ?? []
    }

    /// Fetches all killmail refs for a character from zKillboard, page by page.
    /// Returns newest-first, matching ESI ordering. Stops on empty page.
    func fetchKillRefs(characterID: Int) async throws -> [ZKBRef] {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase

        var allRefs: [ZKBRef] = []
        var page = 1

        while true {
            let url = URL(string: "https://zkillboard.com/api/characterID/\(characterID)/page/\(page)/")!
            let (data, response) = try await session.data(for: URLRequest(url: url))
            guard let httpResponse = response as? HTTPURLResponse else { break }

            if httpResponse.statusCode == 429 {
                try await Task.sleep(nanoseconds: 5_000_000_000)
                continue
            }
            guard httpResponse.statusCode == 200 else { break }

            let refs = try decoder.decode([ZKBRef].self, from: data)
            if refs.isEmpty { break }

            allRefs.append(contentsOf: refs)
            page += 1

            // Respect zKillboard's rate limit between pages
            try await Task.sleep(nanoseconds: 200_000_000)
        }

        return allRefs
    }

    /// Fetches zKillboard's aggregate PvP stats for a character (kills/losses,
    /// ISK destroyed/lost, danger/gang/solo ratios). Public JSON API, no key
    /// required. Returns `nil` for a character zKillboard has no data for, or
    /// on any request failure — callers treat this the same as "unknown", not
    /// an error worth surfacing.
    func fetchCharacterStats(characterID: Int) async throws -> ZKBCharacterStats? {
        let url = URL(string: "https://zkillboard.com/api/stats/characterID/\(characterID)/")!
        let (data, response) = try await session.data(for: URLRequest(url: url))
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else { return nil }
        return try? JSONDecoder().decode(ZKBCharacterStats.self, from: data)
    }
}
