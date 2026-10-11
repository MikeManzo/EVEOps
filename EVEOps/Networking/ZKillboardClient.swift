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

/// One entry from zKillboard's killmail search (`/api/kills/...`). zKillboard now
/// inlines the ESI killmail body, but older or trimmed responses may carry only
/// `killmail_id` + `zkb`, so the ESI fields are optional and callers fall back to
/// `/killmails/{id}/{hash}/` when `attackers` is missing.
nonisolated struct ZKBSystemKill: Decodable, Sendable {
    let killmailId: Int
    let killmailTime: Date?
    let solarSystemId: Int?
    let attackers: [ESIKillmailAttacker]?
    let zkb: ZKBMeta
}

// Mark:  Client

actor ZKillboardClient {
    static let shared = ZKillboardClient()

    private let session: URLSession

    /// Per-system kill searches, keyed by "systemID/pastSeconds". zKillboard asks clients
    /// to cache searches; a few minutes keeps re-plotting a route cheap without hiding a
    /// camp that formed since.
    private var systemKillCache: [String: (fetchedAt: Date, kills: [ZKBSystemKill])] = [:]
    static let systemKillCacheTTL: TimeInterval = 5 * 60
    /// Time of the last uncached search, for spacing requests out as zKillboard asks.
    private var lastSystemRequest: Date?
    private static let minRequestSpacing: TimeInterval = 0.5

    private static let killDecoder: JSONDecoder = {
        let d = JSONDecoder()
        d.keyDecodingStrategy = .convertFromSnakeCase
        d.dateDecodingStrategy = .iso8601
        return d
    }()

    private init() {
        let config = URLSessionConfiguration.default
        config.httpAdditionalHeaders = [
            "Accept": "application/json",
            "Accept-Encoding": "gzip",
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

    /// Kills in one solar system over the last `pastSeconds` (a multiple of 3600, at most
    /// 604 800), newest first, with when they were fetched. Served from a short local cache;
    /// requests are spaced out and a 429 is retried once after a pause. Throws on any other
    /// failure so callers can tell "no kills" from "couldn't ask".
    func fetchSystemKills(systemID: Int, pastSeconds: Int = 10_800) async throws -> (kills: [ZKBSystemKill], fetchedAt: Date) {
        let seconds = min(604_800, max(3600, pastSeconds / 3600 * 3600))
        let key = "\(systemID)/\(seconds)"
        if let hit = systemKillCache[key], Date().timeIntervalSince(hit.fetchedAt) < Self.systemKillCacheTTL {
            return (hit.kills, hit.fetchedAt)
        }

        if let last = lastSystemRequest {
            let wait = Self.minRequestSpacing - Date().timeIntervalSince(last)
            if wait > 0 { try await Task.sleep(nanoseconds: UInt64(wait * 1_000_000_000)) }
        }

        let url = URL(string: "https://zkillboard.com/api/kills/solarSystemID/\(systemID)/pastSeconds/\(seconds)/")!
        var request = URLRequest(url: url)
        // The local cache above decides freshness; zKillboard's hour-long client cache
        // would hide a camp that formed minutes ago.
        request.cachePolicy = .reloadIgnoringLocalCacheData

        for attempt in 0..<2 {
            lastSystemRequest = Date()
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else { throw URLError(.badServerResponse) }
            if http.statusCode == 429, attempt == 0 {
                try await Task.sleep(nanoseconds: 5_000_000_000)
                continue
            }
            guard http.statusCode == 200 else { throw URLError(.badServerResponse) }
            let kills = try Self.killDecoder.decode([ZKBSystemKill].self, from: data)
            let fetchedAt = Date()
            systemKillCache[key] = (fetchedAt, kills)
            return (kills, fetchedAt)
        }
        throw URLError(.resourceUnavailable)
    }
}
