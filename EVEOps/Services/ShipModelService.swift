// ShipModelService.swift
// EVEOps
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

// MARK:  ShipModelService

/// On-demand downloader and disk cache for EVE ship 3D models and albedo textures.
///
/// Models (.obj) come from puffingprie/GetEveModels on GitHub.
///
/// Textures come from CCP's live resource CDN via a three-step lookup:
///   1. GET eveclient_TQ.json  → current build number
///   2. GET eveonline_{build}.txt  → hash path for resfileindex.txt itself
///   3. Stream-parse the live resfileindex, keeping only ship _a.dds albedo lines
/// The raw DDS bytes are cached as-is; MTKTextureLoader in the view handles all
/// formats (BC1–BC7) natively. The filtered ID→hash map is cached alongside the
/// build number and re-fetched only when the build number changes.
actor ShipModelService {
    static let shared = ShipModelService()

    // MARK: Cache directory

    private static let cacheDir: URL = {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let dir  = base.appendingPathComponent("EVEOps/ModelCache", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()

    // MARK: Remote sources

    private static let modelApiURL       = "https://api.github.com/repos/puffingprie/GetEveModels/contents/obj_models"
    private static let modelRawBase      = "https://raw.githubusercontent.com/puffingprie/GetEveModels/main/obj_models/"
    private static let assocURL          = "https://raw.githubusercontent.com/puffingprie/GetEveModels/main/associated_file_names.txt"
    private static let buildVersionURL   = "https://binaries.eveonline.com/eveclient_TQ.json"
    private static let buildManifestBase = "https://binaries.eveonline.com/eveonline_"
    private static let binaryBase        = "https://binaries.eveonline.com/"
    private static let resourceBase      = "https://resources.eveonline.com/"

    // MARK: Disk cache paths

    private static let modelIndexFile = cacheDir.appendingPathComponent(".model_index")
    private static let assocFile      = cacheDir.appendingPathComponent(".assoc_names")
    private static let resIndexFile   = cacheDir.appendingPathComponent(".res_index_v2")
    private static let resBuildFile   = cacheDir.appendingPathComponent(".res_build")

    // MARK: In-memory caches

    private var modelIndex: [String]?
    private var nameToId:   [String: String]?
    private var idToHash:   [String: String]?

    private init() {}

    // MARK:  Public: model

    func modelURL(for shipName: String) async throws -> URL? {
        guard let filename = try await resolveModelFilename(for: shipName) else { return nil }
        return try await ensureModelCached(filename: filename)
    }

    // MARK:  Public: texture

    /// Returns raw DDS bytes for the ship's albedo texture, decompressing any HTTP
    /// zlib layer if present. The caller (ShipSceneKitView) passes these to
    /// MTKTextureLoader, which natively decodes BC1–BC7.
    /// Throws `AlbedoError` with a human-readable reason on failure.
    /// Downloads and caches the ship's albedo DDS texture, then returns the local file URL.
    /// MTKTextureLoader.newTexture(URL:) uses ModelIO which decodes BC1–BC7 natively;
    /// passing raw Data via newTexture(data:) routes through ImageIO which doesn't support DDS.
    func localAlbedoURL(for shipName: String) async throws -> URL {
        let cacheKey  = shipName.filter { $0.isLetter || $0.isNumber }
        let cachedDDS = Self.cacheDir.appendingPathComponent(cacheKey + "_albedo.dds")

        if FileManager.default.fileExists(atPath: cachedDDS.path) { return cachedDDS }

        let hashPath = try await resolveAlbedoHash(for: shipName)
        guard let cdnURL = URL(string: Self.resourceBase + hashPath) else {
            throw AlbedoError.downloadFailed(0)
        }

        var req = URLRequest(url: cdnURL)
        req.setValue("EVEOps macOS", forHTTPHeaderField: "User-Agent")
        let (rawData, resp) = try await URLSession.shared.data(for: req)
        guard let http = resp as? HTTPURLResponse, http.statusCode == 200 else {
            throw AlbedoError.downloadFailed((resp as? HTTPURLResponse)?.statusCode ?? -1)
        }

        // CCP CDN may serve an extra zlib layer on top of BC compression.
        var ddsData = rawData
        let isDDS = rawData.count >= 4
            && rawData[0] == 0x44 && rawData[1] == 0x44
            && rawData[2] == 0x53 && rawData[3] == 0x20
        if !isDDS, let decompressed = try? (rawData as NSData).decompressed(using: .zlib) {
            ddsData = decompressed as Data
        }

        guard ddsData.count >= 4,
              ddsData[0] == 0x44, ddsData[1] == 0x44,
              ddsData[2] == 0x53, ddsData[3] == 0x20 else {
            throw AlbedoError.decodeFailed
        }

        try ddsData.write(to: cachedDDS, options: .atomic)
        return cachedDDS
    }

    // MARK:  Model index

    private func resolveModelFilename(for shipName: String) async throws -> String? {
        let index  = try await ensureModelIndex()
        let target = shipName.lowercased().filter { $0.isLetter || $0.isNumber }
        return index.first { filename in
            let base  = String(filename.dropLast(4))
            let parts = base.components(separatedBy: "_")
            guard parts.count >= 3 else { return false }
            let normalized = parts.dropFirst(2).joined().lowercased()
                              .filter { $0.isLetter || $0.isNumber }
            return normalized == target
        }
    }

    private func ensureModelIndex() async throws -> [String] {
        if let c = modelIndex { return c }
        if let disk = loadLines(from: Self.modelIndexFile) { modelIndex = disk; return disk }
        let fresh = try await fetchModelIndex()
        modelIndex = fresh
        saveLines(fresh, to: Self.modelIndexFile)
        return fresh
    }

    private func fetchModelIndex() async throws -> [String] {
        guard let url = URL(string: Self.modelApiURL) else { throw ShipModelError.badURL }
        var req = URLRequest(url: url)
        req.setValue("EVEOps macOS", forHTTPHeaderField: "User-Agent")
        req.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        let (data, resp) = try await URLSession.shared.data(for: req)
        guard let http = resp as? HTTPURLResponse, http.statusCode == 200 else {
            throw ShipModelError.http((resp as? HTTPURLResponse)?.statusCode ?? -1)
        }
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            throw ShipModelError.parseFailure
        }
        return json.compactMap { $0["name"] as? String }.filter { $0.hasSuffix(".obj") }
    }

    private func ensureModelCached(filename: String) async throws -> URL {
        let dest = Self.cacheDir.appendingPathComponent(filename)
        if FileManager.default.fileExists(atPath: dest.path) { return dest }
        guard let url = URL(string: Self.modelRawBase + filename) else { throw ShipModelError.badURL }
        var req = URLRequest(url: url)
        req.setValue("EVEOps macOS", forHTTPHeaderField: "User-Agent")
        let (data, resp) = try await URLSession.shared.data(for: req)
        guard let http = resp as? HTTPURLResponse, http.statusCode == 200 else {
            throw ShipModelError.http((resp as? HTTPURLResponse)?.statusCode ?? -1)
        }
        try data.write(to: dest, options: .atomic)
        return dest
    }

    // MARK:  Texture lookup

    private func resolveAlbedoHash(for shipName: String) async throws -> String {
        let nameMap = try await ensureNameToId()
        let hashMap = try await ensureIdToHash()
        let key     = shipName.lowercased()
        guard let id = nameMap[key] else { throw AlbedoError.notInNameIndex }
        if let hash = hashMap[id] { return hash }
        let baseParts = id.components(separatedBy: "_")
        if baseParts.count >= 2,
           let hash = hashMap[baseParts.dropLast().joined(separator: "_") + "_t1"] { return hash }
        throw AlbedoError.notInTextureIndex(id)
    }

    // MARK: associated_file_names.txt

    private func ensureNameToId() async throws -> [String: String] {
        if let c = nameToId { return c }
        let map = try await buildNameToId()
        nameToId = map
        return map
    }

    private func buildNameToId() async throws -> [String: String] {
        let text: String
        if let disk = loadText(from: Self.assocFile) {
            text = disk
        } else {
            guard let url = URL(string: Self.assocURL) else { throw ShipModelError.badURL }
            var req = URLRequest(url: url)
            req.setValue("EVEOps macOS", forHTTPHeaderField: "User-Agent")
            let (data, resp) = try await URLSession.shared.data(for: req)
            guard let http = resp as? HTTPURLResponse, http.statusCode == 200,
                  let str = String(data: data, encoding: .utf8) else {
                throw ShipModelError.http((resp as? HTTPURLResponse)?.statusCode ?? -1)
            }
            text = str
            try? text.data(using: .utf8)?.write(to: Self.assocFile, options: .atomic)
        }
        var result: [String: String] = [:]
        for line in text.components(separatedBy: "\n") {
            let parts = line.components(separatedBy: ": ")
            guard parts.count >= 2 else { continue }
            let id   = parts[0].trimmingCharacters(in: .whitespaces)
            let name = parts[1...].joined(separator: ": ").trimmingCharacters(in: .whitespaces)
            result[name.lowercased()] = id
        }
        return result
    }

    // MARK: Live resfileindex

    private func ensureIdToHash() async throws -> [String: String] {
        if let c = idToHash { return c }
        let currentBuild = try? await fetchCurrentBuild()
        if let disk = loadText(from: Self.resIndexFile),
           let cachedBuild = loadText(from: Self.resBuildFile)?.trimmingCharacters(in: .whitespacesAndNewlines),
           currentBuild == nil || cachedBuild == currentBuild {
            let map = parseResCache(disk)
            if !map.isEmpty { idToHash = map; return map }
        }
        guard currentBuild != nil else { throw AlbedoError.downloadFailed(0) }
        let map = try await fetchLiveResIndex()
        idToHash = map
        return map
    }

    private func fetchCurrentBuild() async throws -> String {
        guard let url = URL(string: Self.buildVersionURL) else { throw ShipModelError.badURL }
        var req = URLRequest(url: url)
        req.setValue("EVEOps macOS", forHTTPHeaderField: "User-Agent")
        let (data, resp) = try await URLSession.shared.data(for: req)
        guard let http = resp as? HTTPURLResponse, http.statusCode == 200,
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { throw ShipModelError.http((resp as? HTTPURLResponse)?.statusCode ?? -1) }
        if let s = json["buildNumber"] as? String { return s }
        if let i = json["buildNumber"] as? Int    { return String(i) }
        if let s = json["build"]       as? String { return s }
        if let i = json["build"]       as? Int    { return String(i) }
        throw ShipModelError.parseFailure
    }

    private func fetchLiveResIndex() async throws -> [String: String] {
        let build = try await fetchCurrentBuild()

        guard let manifestURL = URL(string: Self.buildManifestBase + build + ".txt") else {
            throw ShipModelError.badURL
        }
        var manifestReq = URLRequest(url: manifestURL)
        manifestReq.setValue("EVEOps macOS", forHTTPHeaderField: "User-Agent")
        let (manifestData, manifestResp) = try await URLSession.shared.data(for: manifestReq)
        guard let mHttp = manifestResp as? HTTPURLResponse, mHttp.statusCode == 200,
              let manifestText = String(data: manifestData, encoding: .utf8)
        else { throw AlbedoError.downloadFailed((manifestResp as? HTTPURLResponse)?.statusCode ?? -1) }

        var resIndexHash: String?
        for line in manifestText.components(separatedBy: "\n") {
            guard line.hasPrefix("app:/resfileindex.txt,") else { continue }
            let fields = line.components(separatedBy: ",")
            if fields.count >= 2 { resIndexHash = fields[1] }
            break
        }
        guard let hash = resIndexHash else { throw ShipModelError.parseFailure }

        guard let resURL = URL(string: Self.binaryBase + hash) else { throw ShipModelError.badURL }
        var resReq = URLRequest(url: resURL)
        resReq.setValue("EVEOps macOS", forHTTPHeaderField: "User-Agent")
        let (bytes, resResp) = try await URLSession.shared.bytes(for: resReq)
        guard let rHttp = resResp as? HTTPURLResponse, rHttp.statusCode == 200 else {
            throw AlbedoError.downloadFailed((resResp as? HTTPURLResponse)?.statusCode ?? -1)
        }

        var result:     [String: String] = [:]
        var cacheLines: [String]         = []
        for try await line in bytes.lines {
            guard line.contains("/model/ship/"),
                  line.contains("_a.dds,") || line.hasSuffix("_a.dds") else { continue }
            let fields   = line.components(separatedBy: ",")
            guard fields.count >= 2 else { continue }
            let filename = fields[0].components(separatedBy: "/").last ?? ""
            guard filename.hasSuffix("_a.dds") else { continue }
            let id = String(filename.dropLast("_a.dds".count))
            guard !id.isEmpty else { continue }
            result[id] = fields[1]
            cacheLines.append("\(id)=\(fields[1])")
        }

        let cacheText = cacheLines.joined(separator: "\n")
        try? cacheText.data(using: .utf8)?.write(to: Self.resIndexFile, options: .atomic)
        try? build.data(using: .utf8)?.write(to: Self.resBuildFile, options: .atomic)
        return result
    }

    private func parseResCache(_ text: String) -> [String: String] {
        var result: [String: String] = [:]
        for line in text.components(separatedBy: "\n") where !line.isEmpty {
            guard let eq = line.firstIndex(of: "=") else { continue }
            let id   = String(line[line.startIndex..<eq])
            let hash = String(line[line.index(after: eq)...])
            if !id.isEmpty, !hash.isEmpty { result[id] = hash }
        }
        return result
    }

    // MARK:  Disk helpers

    private func loadLines(from url: URL) -> [String]? {
        guard let text = loadText(from: url) else { return nil }
        let lines = text.components(separatedBy: "\n").filter { !$0.isEmpty }
        return lines.isEmpty ? nil : lines
    }

    private func loadText(from url: URL) -> String? {
        guard let data = try? Data(contentsOf: url),
              let text = String(data: data, encoding: .utf8) else { return nil }
        return text
    }

    private func saveLines(_ lines: [String], to url: URL) {
        try? lines.joined(separator: "\n").data(using: .utf8)?.write(to: url, options: .atomic)
    }
}

// MARK:  Errors

enum ShipModelError: LocalizedError {
    case badURL, http(Int), parseFailure
    var errorDescription: String? {
        switch self {
        case .badURL:        return "Invalid URL"
        case .http(let c):  return "HTTP \(c)"
        case .parseFailure: return "Parse error"
        }
    }
}

enum AlbedoError: LocalizedError {
    case notInNameIndex
    case notInTextureIndex(String)
    case downloadFailed(Int)
    case decodeFailed

    var errorDescription: String? {
        switch self {
        case .notInNameIndex:            return "Ship not in texture index"
        case .notInTextureIndex(let id): return "No texture indexed for \(id)"
        case .downloadFailed(let c):     return c > 0 ? "Texture download failed (HTTP \(c))"
                                                      : "Texture download failed (offline?)"
        case .decodeFailed:              return "Texture data unreadable"
        }
    }
}
