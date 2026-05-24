//
// SDEDataManager.swift
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
import OSLog

// MARK:  SDE Data Manager

/// Downloads and caches the four EVE SDE protobuf binary files required by the
/// dogma engine. Files are sourced from data.eveship.fit (Cloudflare R2 bucket
/// maintained by EVEShipFit) and cached locally with a 7-day TTL.
///
/// Replaces SDEClient.swift — the dogma engine handles all modifier/groupId
/// resolution internally, so the Fuzzwork MySQL dump is no longer needed.
actor SDEDataManager {
    static let shared = SDEDataManager()

    private static let ttl: TimeInterval = 7 * 24 * 3600
    private static let pb2Files = [
        "dogmaAttributes.pb2",
        "dogmaEffects.pb2",
        "typeDogma.pb2",
        "types.pb2",
    ]

    private static let cacheDir: URL = {
        let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        let dir  = base.appendingPathComponent("EVEOps/sde2", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()

    private static let metaURL: URL = cacheDir.appendingPathComponent(".meta")

    // Set after a successful load; consumed by DogmaEngine.prepare(pbDirPath:)
    private(set) var pbDirPath: String?

    private init() {}

    // MARK: Public API

    /// Ensures the four .pb2 files are present and fresh, downloading if needed.
    /// Safe to call from any actor. Sets `pbDirPath` on success.
    func ensureLoaded() async {
        if isFresh() {
            pbDirPath = Self.cacheDir.path
            await Logger.sdeData.info("[SDEDataManager] Cache is fresh — using cached SDE data")
            return
        }
        await download()
        if allFilesPresent() {
            pbDirPath = Self.cacheDir.path
        } else {
            await Logger.dogmaEngine.error("[SDEDataManager] SDE data unavailable — dogma engine will not load")
        }
    }

    // MARK: Freshness

    private func isFresh() -> Bool {
        guard let data = try? Data(contentsOf: Self.metaURL),
              let date = try? JSONDecoder().decode(Date.self, from: data),
              Date().timeIntervalSince(date) < Self.ttl
        else { return false }
        return allFilesPresent()
    }

    private func allFilesPresent() -> Bool {
        Self.pb2Files.allSatisfy {
            FileManager.default.fileExists(
                atPath: Self.cacheDir.appendingPathComponent($0).path
            )
        }
    }

    // MARK: Download

    private func download() async {
        guard let tag = await fetchLatestTag() else {
            await Logger.sdeData.error("[SDEDataManager] Could not determine latest EVEShipFit/data release tag")
            return
        }

        // URL pattern: https://data.eveship.fit/{tag}/sde/{file}.pb2
        let baseURLString = "https://data.eveship.fit/\(tag)/sde/"
        await Logger.sdeData.info("[SDEDataManager] Downloading SDE protobuf data (tag: \(tag))…")

        let session = makeSession()
        var allSucceeded = true

        await withTaskGroup(of: Bool.self) { group in
            for file in Self.pb2Files {
                group.addTask {
                    guard let url = URL(string: baseURLString + file) else { return false }
                    var req = URLRequest(url: url)
                    req.setValue("EVEOps macOS", forHTTPHeaderField: "User-Agent")

                    do {
                        let (data, response) = try await session.data(for: req)
                        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                            let code = (response as? HTTPURLResponse)?.statusCode ?? -1
                            await Logger.sdeData.info("[SDEDataManager] HTTP \(code) for \(file)")
                            return false
                        }
                        let dest = Self.cacheDir.appendingPathComponent(file)
                        try data.write(to: dest, options: .atomic)
                        await Logger.sdeData.info("[SDEDataManager] ✓ \(file) (\(data.count / 1024) KB)")
                        return true
                    } catch {
                        await Logger.sdeData.error("[SDEDataManager] Download failed for \(file): \(error.localizedDescription)")
                        return false
                    }
                }
            }

            for await result in group where !result {
                allSucceeded = false
            }
        }

        if allSucceeded {
            if let meta = try? JSONEncoder().encode(Date()) {
                try? meta.write(to: Self.metaURL, options: .atomic)
            }
            await Logger.sdeData.info("[SDEDataManager] All SDE files downloaded successfully")
        } else {
            await Logger.sdeData.error("[SDEDataManager] One or more SDE files failed to download")
        }
    }

    // MARK: Release Discovery

    private func fetchLatestTag() async -> String? {
        guard let url = URL(string: "https://api.github.com/repos/EVEShipFit/data/releases/latest") else {
            return nil
        }
        var req = URLRequest(url: url)
        req.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        req.setValue("EVEOps macOS", forHTTPHeaderField: "User-Agent")

        guard let (data, _) = try? await URLSession.shared.data(for: req),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let tag  = json["tag_name"] as? String
        else {
            await Logger.sdeData.error("[SDEDataManager] GitHub releases API fetch failed")
            return nil
        }
        return tag
    }

    // MARK: Session

    private func makeSession() -> URLSession {
        let cfg = URLSessionConfiguration.default
        cfg.timeoutIntervalForRequest  = 60
        cfg.timeoutIntervalForResource = 300
        return URLSession(configuration: cfg)
    }
}
