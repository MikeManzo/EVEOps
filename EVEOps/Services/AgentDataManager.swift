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
import OSLog

// MARK:  Agent Data Manager

/// Downloads and caches agent data from the Fuzzwork SDE CSV dumps.
/// Source: https://www.fuzzwork.co.uk/dump/latest/
/// Files: agtAgents.csv (~425 KB), agtAgentTypes.csv, crpNPCDivisions.csv,
///        crpNPCCorporations.csv (for corp→faction mapping)
/// Refreshes every 7 days.
actor AgentDataManager {
    static let shared = AgentDataManager()

    private static let baseURL  = "https://www.fuzzwork.co.uk/dump/latest/csv/"
    private static let cacheTTL: TimeInterval = 7 * 24 * 3600

    private static let cacheDir: URL = {
        let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        let dir  = base.appendingPathComponent("EVEOps/agents", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()

    // MARK:  Model

    struct SDEAgent: Codable, Sendable, Identifiable {
        let agentID: Int
        let divisionID: Int
        let corporationID: Int
        let locationID: Int      // NPC station ID
        let level: Int
        let agentTypeID: Int
        let isLocator: Bool
        var id: Int { agentID }
    }

    private struct CachedData: Codable {
        let downloadedAt: Date
        let agents: [SDEAgent]
        let agentTypes: [String: String]
        let divisions: [String: String]
        let corpFactions: [String: Int]   // corpID (string key) → factionID
    }

    // MARK:  Public State

    private(set) var agents: [SDEAgent] = []
    private(set) var agentTypes: [Int: String] = [:]    // agentTypeID → name
    private(set) var divisions: [Int: String] = [:]     // divisionID  → name
    private(set) var corpFactions: [Int: Int] = [:]     // corporationID → factionID
    private(set) var isLoaded  = false
    private(set) var isLoading = false
    private(set) var loadError: String? = nil

    private init() {}

    // MARK:  Public API

    func ensureLoaded() async {
        guard !isLoaded && !isLoading else { return }
        isLoading = true
        defer { isLoading = false }

        if let cached = loadFromDisk(), !isExpired(cached.downloadedAt) {
            apply(cached); isLoaded = true
            await Logger.sdeData.info("AgentDataManager loaded \(self.agents.count) agents from cache")
            return
        }

        do {
            try await downloadAll()
            isLoaded = true; loadError = nil
            await Logger.sdeData.info("AgentDataManager downloaded \(self.agents.count) agents")
        } catch {
            loadError = "Could not load agent data: \(error.localizedDescription)"
            await Logger.sdeData.error("AgentDataManager download failed: \(error.localizedDescription)")
            if let stale = loadFromDisk() {
                apply(stale); isLoaded = true
            }
        }
    }

    /// Returns agents matching all supplied criteria (nil = no filter for that dimension).
    func filteredAgents(
        typeID: Int?,
        divisionID: Int?,
        level: Int?,
        factionID: Int?,
        locatorOnly: Bool
    ) -> [SDEAgent] {
        agents.filter { a in
            if a.agentTypeID == 1 { return false }
            if let t = typeID,     a.agentTypeID != t { return false }
            if let d = divisionID, a.divisionID  != d { return false }
            if let l = level,      a.level       != l { return false }
            if let f = factionID,  corpFactions[a.corporationID] != f { return false }
            if locatorOnly  && !a.isLocator { return false }
            if !locatorOnly && typeID == nil && a.isLocator { return false }
            return true
        }
    }

    /// Division IDs present in BasicAgent (type 2) data, sorted by name.
    func availableBasicDivisions() -> [(id: Int, name: String)] {
        let ids = Set(agents.filter { $0.agentTypeID == 2 }.map(\.divisionID))
        return ids.compactMap { id -> (Int, String)? in
            guard let name = divisions[id] else { return nil }
            return (id, name)
        }.sorted { $0.1 < $1.1 }
    }

    /// Faction IDs present in the loaded agent data, with display names, sorted by name.
    func availableFactions() -> [(id: Int, name: String, shortName: String)] {
        let ids = Set(agents.compactMap { corpFactions[$0.corporationID] })
        return ids.map { id in
            let info = Self.factionInfo(id)
            return (id, info.name, info.shortName)
        }.sorted { $0.1 < $1.1 }
    }

    // MARK:  Faction Metadata

    struct FactionInfo {
        let name: String
        let shortName: String
    }

    static func factionInfo(_ id: Int) -> FactionInfo {
        switch id {
        case 500001: return FactionInfo(name: "Caldari State",              shortName: "Caldari")
        case 500002: return FactionInfo(name: "Minmatar Republic",          shortName: "Minmatar")
        case 500003: return FactionInfo(name: "Amarr Empire",               shortName: "Amarr")
        case 500004: return FactionInfo(name: "Gallente Federation",        shortName: "Gallente")
        case 500005: return FactionInfo(name: "Jove Empire",                shortName: "Jove")
        case 500006: return FactionInfo(name: "CONCORD Assembly",           shortName: "CONCORD")
        case 500007: return FactionInfo(name: "The Syndicate",              shortName: "Syndicate")
        case 500008: return FactionInfo(name: "Khanid Kingdom",             shortName: "Khanid")
        case 500009: return FactionInfo(name: "Ammatar Mandate",            shortName: "Ammatar")
        case 500010: return FactionInfo(name: "Intaki Syndicate",           shortName: "Intaki")
        case 500011: return FactionInfo(name: "The InterBus",               shortName: "InterBus")
        case 500012: return FactionInfo(name: "Outer Ring Excavations",     shortName: "ORE")
        case 500013: return FactionInfo(name: "Thukker Mix",                shortName: "Thukker")
        case 500014: return FactionInfo(name: "Servant Sisters of EVE",     shortName: "Sisters")
        case 500015: return FactionInfo(name: "Society of Conscious Thought", shortName: "SoCT")
        case 500016: return FactionInfo(name: "Mordu's Legion Command",     shortName: "Mordu's")
        case 500017: return FactionInfo(name: "Sansha's Nation",            shortName: "Sansha")
        case 500018: return FactionInfo(name: "Blood Raider Covenant",      shortName: "Blood Raiders")
        case 500019: return FactionInfo(name: "Guristas Pirates",           shortName: "Guristas")
        case 500020: return FactionInfo(name: "Angel Cartel",               shortName: "Angels")
        case 500021: return FactionInfo(name: "Serpentis",                  shortName: "Serpentis")
        case 500022: return FactionInfo(name: "Rogue Drones",               shortName: "Rogue Drones")
        default:     return FactionInfo(name: "Faction \(id)",              shortName: "\(id)")
        }
    }

    // MARK:  Download

    private func downloadAll() async throws {
        let session = makeSession()
        async let a = fetchCSV("agtAgents.csv",          session: session)
        async let t = fetchCSV("agtAgentTypes.csv",      session: session)
        async let d = fetchCSV("crpNPCDivisions.csv",    session: session)
        async let c = fetchCSV("crpNPCCorporations.csv", session: session)
        let (agentsData, typesData, divsData, corpsData) = try await (a, t, d, c)

        agents      = parseAgents(agentsData)
        agentTypes  = parseKV(typesData)
        divisions   = parseKV(divsData)
        corpFactions = parseCorpFactions(corpsData)
        saveToDisk()
    }

    private func fetchCSV(_ filename: String, session: URLSession) async throws -> Data {
        guard let url = URL(string: Self.baseURL + filename) else { throw URLError(.badURL) }
        var req = URLRequest(url: url)
        req.setValue("EVEOps macOS", forHTTPHeaderField: "User-Agent")
        let (data, response) = try await session.data(for: req)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw URLError(.badServerResponse) }
        return data
    }

    // MARK:  Parsing

    private func parseAgents(_ data: Data) -> [SDEAgent] {
        guard let text = String(data: data, encoding: .utf8) else { return [] }
        var result: [SDEAgent] = []
        result.reserveCapacity(6000)
        for line in text.components(separatedBy: "\n").dropFirst() {
            let f = line.trimmingCharacters(in: .whitespaces).components(separatedBy: ",")
            guard f.count >= 8,
                  let agentID       = Int(unquote(f[0])),
                  let divisionID    = Int(unquote(f[1])),
                  let corporationID = Int(unquote(f[2])),
                  let locationID    = Int(unquote(f[3])),
                  let level         = Int(unquote(f[4])),
                  let agentTypeID   = Int(unquote(f[6]))   // f[5] = quality (deprecated)
            else { continue }
            let isLocator = unquote(f[7]) == "1"
            result.append(SDEAgent(
                agentID: agentID, divisionID: divisionID,
                corporationID: corporationID, locationID: locationID,
                level: level, agentTypeID: agentTypeID, isLocator: isLocator
            ))
        }
        return result
    }

    /// Parses a CSV where column 0 = id and column 1 = name → Int→String.
    private func parseKV(_ data: Data) -> [Int: String] {
        guard let text = String(data: data, encoding: .utf8) else { return [:] }
        var result: [Int: String] = [:]
        for line in text.components(separatedBy: "\n").dropFirst() {
            let f = line.trimmingCharacters(in: .whitespaces).components(separatedBy: ",")
            guard f.count >= 2, let id = Int(unquote(f[0])) else { continue }
            result[id] = unquote(f[1])
        }
        return result
    }

    /// Parses crpNPCCorporations.csv: column 0 = corporationID, column 22 = factionID.
    private func parseCorpFactions(_ data: Data) -> [Int: Int] {
        guard let text = String(data: data, encoding: .utf8) else { return [:] }
        var result: [Int: Int] = [:]
        for line in text.components(separatedBy: "\n").dropFirst() {
            let f = line.trimmingCharacters(in: .whitespaces).components(separatedBy: ",")
            guard f.count > 22,
                  let corpID    = Int(unquote(f[0])),
                  let factionID = Int(unquote(f[22]))
            else { continue }
            result[corpID] = factionID
        }
        return result
    }

    private func unquote(_ s: String) -> String {
        let t = s.trimmingCharacters(in: .whitespaces)
        guard t.count >= 2, t.hasPrefix("\""), t.hasSuffix("\"") else { return t }
        return String(t.dropFirst().dropLast())
    }

    // MARK:  Cache (v3 — csv/ subdirectory, quoted field parsing)

    private static var cacheFile: URL { cacheDir.appendingPathComponent("agents-v3.json") }

    private func loadFromDisk() -> CachedData? {
        guard let data = try? Data(contentsOf: Self.cacheFile) else { return nil }
        return try? JSONDecoder().decode(CachedData.self, from: data)
    }

    private func saveToDisk() {
        let cache = CachedData(
            downloadedAt: Date(),
            agents:       agents,
            agentTypes:   agentTypes.reduce(into: [:])  { $0["\($1.key)"] = $1.value },
            divisions:    divisions.reduce(into: [:])   { $0["\($1.key)"] = $1.value },
            corpFactions: corpFactions.reduce(into: [:]) { $0["\($1.key)"] = $1.value }
        )
        if let data = try? JSONEncoder().encode(cache) {
            try? data.write(to: Self.cacheFile, options: .atomic)
        }
    }

    private func isExpired(_ date: Date) -> Bool {
        Date().timeIntervalSince(date) > Self.cacheTTL
    }

    private func apply(_ cached: CachedData) {
        agents       = cached.agents
        agentTypes   = cached.agentTypes.reduce(into: [:])  { $0[Int($1.key) ?? 0] = $1.value }
        divisions    = cached.divisions.reduce(into: [:])   { $0[Int($1.key) ?? 0] = $1.value }
        corpFactions = cached.corpFactions.reduce(into: [:]) { $0[Int($1.key) ?? 0] = $1.value }
    }

    private func makeSession() -> URLSession {
        let cfg = URLSessionConfiguration.default
        cfg.timeoutIntervalForRequest  = 60
        cfg.timeoutIntervalForResource = 300
        return URLSession(configuration: cfg)
    }
}
