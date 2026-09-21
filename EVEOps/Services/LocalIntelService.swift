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

/// One resolved pilot from a pasted Local member list, with corp/alliance
/// affiliation looked up from ESI's public endpoints.
nonisolated struct LocalIntelPilot: Identifiable, Sendable, Hashable {
    let characterId: Int
    let name: String
    let corporationId: Int
    let corporationName: String?
    let corporationTicker: String?
    let allianceId: Int?
    let allianceName: String?
    let allianceTicker: String?
    let securityStatus: Double?
    let birthday: Date
    /// When they joined their *current* corporation — the top entry of
    /// `/corporationhistory/`, not `birthday` (character creation date).
    let corporationJoinDate: Date?
    /// Total corporations this character has ever belonged to. A high count
    /// paired with a very recent `corporationJoinDate` is the classic
    /// corp-hopping/alt-scout tell — nil if the history lookup failed.
    let corporationCount: Int?
    /// zKillboard's aggregate PvP stats — nil if zKillboard has no record of
    /// this character or the lookup failed, not necessarily "zero activity".
    let zkbStats: ZKBCharacterStats?

    var id: Int { characterId }
}

/// Resolves a pasted Local chat member list into pilot affiliation data via ESI.
///
/// EVE's chat log files only record messages actually sent, not channel
/// membership, and ESI has no endpoint for "who is in this system" (the old
/// `/characters/{id}/chat_channels/` route was deprecated with no replacement).
/// The only way to get the real roster is the same one every established EVE
/// intel tool uses: the player selects the Local member list in the game client
/// and copies it, and that pasted text is resolved here — a manual, player-
/// triggered action rather than anything read automatically off disk.
actor LocalIntelService {
    static let shared = LocalIntelService()
    private init() {}

    struct Result: Sendable {
        let pilots: [LocalIntelPilot]
        let unresolvedNames: [String]
    }

    /// ESI's `/universe/ids/` rejects names shorter than 3 characters outright;
    /// filtering them out here keeps one stray short line from failing the batch.
    private static let minNameLength = 3

    private var corporationCache: [Int: ESICorporationPublic] = [:]
    private var allianceCache: [Int: ESIAlliancePublic] = [:]

    func resolve(pastedText: String) async -> Result {
        let names = Self.parseNames(pastedText)
        guard !names.isEmpty else { return Result(pilots: [], unresolvedNames: []) }

        struct IDResponse: Decodable { let characters: [ESIIDName]? }
        guard let response: IDResponse = try? await ESIClient.shared.post("/universe/ids/", body: names) else {
            return Result(pilots: [], unresolvedNames: names)
        }

        let matches = response.characters ?? []
        let matchedNames = Set(matches.map(\.name))
        let unresolvedNames = names.filter { !matchedNames.contains($0) }

        let pilots = await withTaskGroup(of: LocalIntelPilot?.self) { group in
            for match in matches {
                group.addTask { await self.fetchPilot(characterId: match.id, name: match.name) }
            }
            var out: [LocalIntelPilot] = []
            for await pilot in group {
                if let pilot { out.append(pilot) }
            }
            return out
        }

        return Result(pilots: pilots.sorted { $0.name < $1.name }, unresolvedNames: unresolvedNames)
    }

    private func fetchPilot(characterId: Int, name: String) async -> LocalIntelPilot? {
        guard let info: ESICharacterPublic = try? await ESIClient.shared.fetch("/characters/\(characterId)/") else {
            return nil
        }

        async let corporationTask = corporation(id: info.corporationId)
        async let allianceTask = allianceIfPresent(info.allianceId)
        async let historyTask = corporationHistory(characterId: characterId)
        async let statsTask = zkbStats(characterId: characterId)

        let corporation = await corporationTask
        let alliance = await allianceTask
        let history = await historyTask
        let stats = await statsTask

        return LocalIntelPilot(
            characterId: characterId,
            name: name,
            corporationId: info.corporationId,
            corporationName: corporation?.name,
            corporationTicker: corporation?.ticker,
            allianceId: info.allianceId,
            allianceName: alliance?.name,
            allianceTicker: alliance?.ticker,
            securityStatus: info.securityStatus,
            birthday: info.birthday,
            corporationJoinDate: history?.first?.startDate,
            corporationCount: history?.count,
            zkbStats: stats
        )
    }

    private func allianceIfPresent(_ allianceId: Int?) async -> ESIAlliancePublic? {
        guard let allianceId else { return nil }
        return await alliance(id: allianceId)
    }

    private func corporationHistory(characterId: Int) async -> [ESICorporationHistory]? {
        try? await ESIClient.shared.fetch("/characters/\(characterId)/corporationhistory/")
    }

    private func zkbStats(characterId: Int) async -> ZKBCharacterStats? {
        (try? await ZKillboardClient.shared.fetchCharacterStats(characterID: characterId)) ?? nil
    }

    private func corporation(id: Int) async -> ESICorporationPublic? {
        if let cached = corporationCache[id] { return cached }
        guard let corp: ESICorporationPublic = try? await ESIClient.shared.fetch("/corporations/\(id)/") else { return nil }
        corporationCache[id] = corp
        return corp
    }

    private func alliance(id: Int) async -> ESIAlliancePublic? {
        if let cached = allianceCache[id] { return cached }
        guard let alliance: ESIAlliancePublic = try? await ESIClient.shared.fetch("/alliances/\(id)/") else { return nil }
        allianceCache[id] = alliance
        return alliance
    }

    /// Splits pasted text into candidate pilot names, one per line — the shape
    /// produced by selecting and copying EVE's Local member list.
    private static func parseNames(_ text: String) -> [String] {
        var seen = Set<String>()
        var names: [String] = []
        for rawLine in text.split(whereSeparator: \.isNewline) {
            let name = rawLine.trimmingCharacters(in: .whitespaces)
            guard name.count >= minNameLength, seen.insert(name).inserted else { continue }
            names.append(name)
        }
        return names
    }
}
