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

enum EVEManifestError: LocalizedError {
    case badURL, http(Int), parseFailure

    var errorDescription: String? {
        switch self {
        case .badURL: return "Invalid URL"
        case .http(let code): return "HTTP \(code)"
        case .parseFailure: return "Could not parse manifest"
        }
    }
}

protocol EVEManifestFetching: Sendable {
    func fetchCurrentBuild() async throws -> String
    func fetchAppManifest(build: String) async throws -> [ResourceManifestEntry]
    func fetchResFileIndex(hashPath: String) async throws -> [ResourceManifestEntry]
}

/// Generalizes the build-check → app-manifest → resfileindex pipeline confirmed both by capturing
/// the real CCP launcher's own log output (`[server-manager]`/`[manifest]`/`[download-from-manifest]`)
/// and by `ShipModelService`, which already runs this exact pipeline successfully in production
/// for ship textures. All three calls are unauthenticated.
actor EVEManifestClient: EVEManifestFetching {
    static let shared = EVEManifestClient()

    private nonisolated static let buildVersionURL   = "https://binaries.eveonline.com/eveclient_TQ.json"
    private nonisolated static let buildManifestBase = "https://binaries.eveonline.com/eveonline_"
    private nonisolated static let binaryBase        = "https://binaries.eveonline.com/"

    func fetchCurrentBuild() async throws -> String {
        guard let url = URL(string: Self.buildVersionURL) else { throw EVEManifestError.badURL }
        var request = URLRequest(url: url)
        request.setValue(HTTPClientInfo.userAgent, forHTTPHeaderField: "User-Agent")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200,
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { throw EVEManifestError.http((response as? HTTPURLResponse)?.statusCode ?? -1) }
        if let s = json["buildNumber"] as? String { return s }
        if let i = json["buildNumber"] as? Int    { return String(i) }
        if let s = json["build"]       as? String { return s }
        if let i = json["build"]       as? Int    { return String(i) }
        throw EVEManifestError.parseFailure
    }

    /// `eveonline_{build}.txt` — the small CSV manifest covering the EVE.app bundle itself
    /// (matches the local `index_tranquility.txt` in shape and scope).
    func fetchAppManifest(build: String) async throws -> [ResourceManifestEntry] {
        guard let url = URL(string: Self.buildManifestBase + build + ".txt") else {
            throw EVEManifestError.badURL
        }
        var request = URLRequest(url: url)
        request.setValue(HTTPClientInfo.userAgent, forHTTPHeaderField: "User-Agent")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200,
              let text = String(data: data, encoding: .utf8)
        else { throw EVEManifestError.http((response as? HTTPURLResponse)?.statusCode ?? -1) }
        return ResourceManifestEntry.parseIndex(text)
    }

    /// The full, ~175k-entry resfileindex.txt covering actual game content, fetched by its
    /// content hash (the app manifest's own `app:/resfileindex.txt` entry gives this hash — see
    /// `resFileIndexHashPath(in:)`). Streamed line-by-line since the body is tens of MB.
    func fetchResFileIndex(hashPath: String) async throws -> [ResourceManifestEntry] {
        guard let url = URL(string: Self.binaryBase + hashPath) else { throw EVEManifestError.badURL }
        var request = URLRequest(url: url)
        request.setValue(HTTPClientInfo.userAgent, forHTTPHeaderField: "User-Agent")
        let (bytes, response) = try await URLSession.shared.bytes(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw EVEManifestError.http((response as? HTTPURLResponse)?.statusCode ?? -1)
        }
        var entries: [ResourceManifestEntry] = []
        entries.reserveCapacity(200_000)
        for try await line in bytes.lines {
            if let entry = ResourceManifestEntry.parseLine(line) {
                entries.append(entry)
            }
        }
        return entries
    }

    /// Looks up the resfileindex.txt's own content-address within a parsed app manifest.
    nonisolated static func resFileIndexHashPath(in appManifest: [ResourceManifestEntry]) -> String? {
        appManifest.first { $0.virtualPath == "app:/resfileindex.txt" }?.hashPath
    }
}
