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

// MARK:  Models

/// One solar system as needed by the 3-D galaxy map: position, security and the
/// region / constellation it belongs to. Positions are the raw ESI/SDE metres.
nonisolated struct TopoSystem: Sendable, Codable {
    let id: Int
    let name: String
    let x: Double
    let y: Double
    let z: Double
    let security: Double
    let regionID: Int
    let constellationID: Int
}

/// The full known-space topology: every k-space system plus the stargate graph.
nonisolated struct GalaxyTopology: Sendable {
    let systems: [TopoSystem]
    /// Deduplicated stargate links as ordered `(a, b)` system-id pairs with `a < b`.
    let jumps: [(Int, Int)]
    let generatedAt: Date

    var systemsByID: [Int: TopoSystem] {
        Dictionary(uniqueKeysWithValues: systems.map { ($0.id, $0) })
    }
}

// MARK:  UniverseTopology

/// Downloads and caches the bulk solar-system + stargate topology used by the 3-D
/// galaxy map. ESI exposes no bulk endpoint for this (only ~5,400 individual system
/// fetches + ~13,900 stargate fetches), so a prebuilt static snapshot is pulled once
/// from Fuzzwork's SDE CSV dump and cached on disk.
///
/// On every `load()` a `HEAD` request reads each CSV's `ETag` / `Last-Modified`; the
/// files are re-downloaded only when those change. If Fuzzwork is unreachable a
/// 30-day TTL keeps the cached snapshot valid so the map still works offline. A stale
/// cache is always preferred over failing outright.
actor UniverseTopology {
    static let shared = UniverseTopology()

    // MARK: Sources

    private static let base = "https://www.fuzzwork.co.uk/dump/latest/csv/"
    private static let systemsCSV = "mapSolarSystems.csv"
    private static let jumpsCSV   = "mapSolarSystemJumps.csv"

    /// k-space (+ Pochven) only. Wormhole space starts at 11000001, abyssal at 12000000.
    private static let maxKnownSpaceRegionID = 11_000_000

    private static let fallbackTTL: TimeInterval = 30 * 24 * 3600

    // MARK: Cache location

    private static let cacheDir: URL = {
        let dir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("EVEOps/topology", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()
    private static let dataFile = cacheDir.appendingPathComponent("topology.json")
    private static let metaFile = cacheDir.appendingPathComponent("meta.json")

    // MARK: State

    private var inMemory: GalaxyTopology?
    private var loadTask: Task<GalaxyTopology?, Never>?

    private let session: URLSession = {
        let cfg = URLSessionConfiguration.default
        cfg.timeoutIntervalForRequest  = 60
        cfg.timeoutIntervalForResource = 300
        cfg.httpAdditionalHeaders = ["User-Agent": HTTPClientInfo.userAgent]
        return URLSession(configuration: cfg)
    }()

    private init() {}

    // MARK: Meta

    private struct Meta: Codable {
        let systemsVersion: String
        let jumpsVersion: String
        let savedAt: Date
    }

    /// Disk payload. Jump pairs are flattened `[a, b, a, b, …]` to stay `Codable` and compact.
    private struct Payload: Codable {
        let systems: [TopoSystem]
        let jumpPairs: [Int]
        let generatedAt: Date
    }

    // MARK: Public API

    /// Returns the cached topology, downloading and parsing it on first use.
    /// Safe to call concurrently — callers share a single in-flight load.
    func load() async -> GalaxyTopology? {
        if let inMemory { return inMemory }
        if let loadTask { return await loadTask.value }

        let task = Task<GalaxyTopology?, Never> { [weak self] in
            await self?.performLoad() ?? nil
        }
        loadTask = task
        let result = await task.value
        loadTask = nil
        if let result { inMemory = result }
        return result
    }

    // MARK: Load pipeline

    private func performLoad() async -> GalaxyTopology? {
        let remote = await fetchRemoteVersions()

        // 1. Try the on-disk cache.
        if let cached = loadCachedPayload(), let meta = loadMeta() {
            let versionsMatch = remote.map {
                $0.systems == meta.systemsVersion && $0.jumps == meta.jumpsVersion
            } ?? false
            let withinTTL = Date().timeIntervalSince(meta.savedAt) < Self.fallbackTTL

            if versionsMatch {
                await Logger.universe.info("UniverseTopology cache current — \(cached.systems.count) systems")
                return topology(from: cached)
            }
            if remote == nil && withinTTL {
                await Logger.universe.info("UniverseTopology Fuzzwork unreachable — using cached snapshot")
                return topology(from: cached)
            }
        }

        // 2. Download + parse a fresh snapshot.
        if let fresh = await downloadAndParse(versions: remote) {
            return fresh
        }

        // 3. Last resort: any cache we have, however stale.
        if let cached = loadCachedPayload() {
            await Logger.universe.warning("UniverseTopology download failed — serving stale cache")
            return topology(from: cached)
        }

        await Logger.universe.error("UniverseTopology no snapshot available (download failed, no cache)")
        return nil
    }

    private func downloadAndParse(versions: (systems: String, jumps: String)?) async -> GalaxyTopology? {
        guard let systemsURL = URL(string: Self.base + Self.systemsCSV),
              let jumpsURL = URL(string: Self.base + Self.jumpsCSV) else { return nil }

        do {
            async let systemsData = fetchData(systemsURL)
            async let jumpsData = fetchData(jumpsURL)
            let (sysRaw, jumpRaw) = try await (systemsData, jumpsData)

            let systems = Self.parseSystems(sysRaw)
            guard systems.count > 1000 else {
                await Logger.universe.error("UniverseTopology parsed only \(systems.count) systems — treating as failure")
                return nil
            }
            let keptIDs = Set(systems.map(\.id))
            let jumps = Self.parseJumps(jumpRaw, keeping: keptIDs)

            let payload = Payload(
                systems: systems,
                jumpPairs: jumps.flatMap { [$0.0, $0.1] },
                generatedAt: Date()
            )
            persist(payload: payload, meta: Meta(
                systemsVersion: versions?.systems ?? "\(sysRaw.count)",
                jumpsVersion: versions?.jumps ?? "\(jumpRaw.count)",
                savedAt: Date()
            ))

            await Logger.universe.info("UniverseTopology downloaded \(systems.count) systems, \(jumps.count) jumps")
            return topology(from: payload)
        } catch {
            await Logger.universe.error("UniverseTopology download failed: \(error.localizedDescription)")
            return nil
        }
    }

    // MARK: Networking

    private func fetchData(_ url: URL) async throws -> Data {
        let (data, response) = try await session.data(for: URLRequest(url: url))
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw URLError(.badServerResponse)
        }
        return data
    }

    /// `HEAD`s both CSVs and folds `ETag` (or `Last-Modified`, or `Content-Length`)
    /// into a per-file version string. Returns `nil` if either request fails.
    private func fetchRemoteVersions() async -> (systems: String, jumps: String)? {
        func version(_ name: String) async -> String? {
            guard let url = URL(string: Self.base + name) else { return nil }
            var req = URLRequest(url: url)
            req.httpMethod = "HEAD"
            guard let (_, response) = try? await session.data(for: req),
                  let http = response as? HTTPURLResponse, http.statusCode == 200 else { return nil }
            return http.value(forHTTPHeaderField: "ETag")
                ?? http.value(forHTTPHeaderField: "Last-Modified")
                ?? http.value(forHTTPHeaderField: "Content-Length")
        }
        async let s = version(Self.systemsCSV)
        async let j = version(Self.jumpsCSV)
        guard let sv = await s, let jv = await j else { return nil }
        return (sv, jv)
    }

    // MARK: Disk

    private func loadMeta() -> Meta? {
        guard let data = try? Data(contentsOf: Self.metaFile) else { return nil }
        return try? JSONDecoder().decode(Meta.self, from: data)
    }

    private func loadCachedPayload() -> Payload? {
        guard let data = try? Data(contentsOf: Self.dataFile) else { return nil }
        return try? JSONDecoder().decode(Payload.self, from: data)
    }

    private func persist(payload: Payload, meta: Meta) {
        let encoder = JSONEncoder()
        if let d = try? encoder.encode(payload) { try? d.write(to: Self.dataFile, options: .atomic) }
        if let d = try? encoder.encode(meta)    { try? d.write(to: Self.metaFile, options: .atomic) }
    }

    private func topology(from payload: Payload) -> GalaxyTopology {
        var jumps: [(Int, Int)] = []
        jumps.reserveCapacity(payload.jumpPairs.count / 2)
        var i = 0
        while i + 1 < payload.jumpPairs.count {
            jumps.append((payload.jumpPairs[i], payload.jumpPairs[i + 1]))
            i += 2
        }
        return GalaxyTopology(systems: payload.systems, jumps: jumps, generatedAt: payload.generatedAt)
    }

    // MARK: Parsing

    /// Decodes CSV bytes to lines, stripping a leading UTF-8 BOM and skipping blank lines.
    private static func csvLines(_ data: Data) -> [Substring] {
        guard var text = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1) else { return [] }
        if text.first == "\u{FEFF}" { text.removeFirst() }
        // Fuzzwork uses CRLF; `\r\n` is a single `Character`, so split on `isNewline`
        // rather than comparing against "\n" / "\r" (which never match the CRLF grapheme).
        return text.split(omittingEmptySubsequences: true, whereSeparator: \.isNewline)
    }

    private static func headerColumn(_ name: String, in header: [String]) -> Int? {
        header.firstIndex { $0.caseInsensitiveCompare(name) == .orderedSame }
    }

    private static func parseSystems(_ data: Data) -> [TopoSystem] {
        var lines = csvLines(data)[...]
        guard let headerLine = lines.first else { return [] }
        lines = lines.dropFirst()
        let header = splitCSVLine(String(headerLine))
        func col(_ name: String) -> Int? { headerColumn(name, in: header) }
        guard let cRegion = col("regionID"), let cCons = col("constellationID"),
              let cID = col("solarSystemID"), let cName = col("solarSystemName"),
              let cX = col("x"), let cY = col("y"), let cZ = col("z"),
              let cSec = col("security") else { return [] }
        let maxNeeded = [cRegion, cCons, cID, cName, cX, cY, cZ, cSec].max()!

        var out: [TopoSystem] = []
        out.reserveCapacity(6000)
        for line in lines {
            let f = splitCSVLine(String(line))
            guard f.count > maxNeeded,
                  let region = Int(f[cRegion]), region < maxKnownSpaceRegionID,
                  let cons = Int(f[cCons]),
                  let id = Int(f[cID]),
                  let x = Double(f[cX]), let y = Double(f[cY]), let z = Double(f[cZ]),
                  let sec = Double(f[cSec]) else { continue }
            out.append(TopoSystem(
                id: id,
                name: f[cName].trimmingCharacters(in: CharacterSet(charactersIn: "\"")),
                x: x, y: y, z: z,
                security: sec,
                regionID: region,
                constellationID: cons
            ))
        }
        return out
    }

    private static func parseJumps(_ data: Data, keeping ids: Set<Int>) -> [(Int, Int)] {
        var lines = csvLines(data)[...]
        guard let headerLine = lines.first else { return [] }
        lines = lines.dropFirst()
        let header = splitCSVLine(String(headerLine))
        func col(_ name: String) -> Int? { headerColumn(name, in: header) }
        guard let cFrom = col("fromSolarSystemID"), let cTo = col("toSolarSystemID") else { return [] }
        let maxNeeded = max(cFrom, cTo)

        var seen = Set<Int64>()
        var out: [(Int, Int)] = []
        out.reserveCapacity(15000)
        for line in lines {
            let f = splitCSVLine(String(line))
            guard f.count > maxNeeded, let a = Int(f[cFrom]), let b = Int(f[cTo]),
                  a != b, ids.contains(a), ids.contains(b) else { continue }
            let lo = min(a, b), hi = max(a, b)
            let key = Int64(lo) << 32 | Int64(hi)
            if seen.insert(key).inserted { out.append((lo, hi)) }
        }
        return out
    }

    /// Minimal RFC-4180-ish splitter: handles double-quoted fields and escaped `""`.
    private static func splitCSVLine(_ line: String) -> [String] {
        var fields: [String] = []
        var current = ""
        var inQuotes = false
        let chars = Array(line)
        var i = 0
        while i < chars.count {
            let c = chars[i]
            if inQuotes {
                if c == "\"" {
                    if i + 1 < chars.count && chars[i + 1] == "\"" { current.append("\""); i += 1 }
                    else { inQuotes = false }
                } else { current.append(c) }
            } else {
                switch c {
                case "\"": inQuotes = true
                case ",":  fields.append(current); current = ""
                default:   current.append(c)
                }
            }
            i += 1
        }
        fields.append(current)
        return fields
    }
}
