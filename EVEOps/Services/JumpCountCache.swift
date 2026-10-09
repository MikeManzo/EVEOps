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

/// Persistent jump counts from ESI's `/route/`, keyed by origin system and route flag.
/// Stargate topology only changes with game patches, so counts survive relaunches and
/// expire with the same 7-day TTL as `UniverseCache`. Destinations ESI has no route to
/// are remembered as `unreachable` so they aren't asked for again — every such request
/// is a 404 that spends ESI's shared error budget.
actor JumpCountCache {
    static let shared = JumpCountCache()

    /// Stored count for a destination ESI returned no route to.
    nonisolated static let unreachable = -1

    private static let ttl: TimeInterval = 7 * 24 * 3600

    private nonisolated struct Entry: Codable, Sendable {
        var counts: [Int: Int]
        let created: Date
    }

    private var entries: [String: Entry]
    private var saveTask: Task<Void, Never>?

    private static let fileURL: URL = {
        let dir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
            .appendingPathComponent("EVEOps", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("jump_counts.json")
    }()

    private init() {
        let now = Date()
        let loaded = (try? Data(contentsOf: Self.fileURL))
            .flatMap { try? JSONDecoder().decode([String: Entry].self, from: $0) } ?? [:]
        entries = loaded.filter { now.timeIntervalSince($0.value.created) < Self.ttl }
    }

    private static func key(origin: Int, flag: String) -> String { "\(origin)-\(flag)" }

    /// Known counts from `origin` with `flag`, destination → jumps (or `unreachable`).
    func counts(origin: Int, flag: String) -> [Int: Int] {
        let key = Self.key(origin: origin, flag: flag)
        guard let entry = entries[key] else { return [:] }
        guard Date().timeIntervalSince(entry.created) < Self.ttl else {
            entries[key] = nil
            return [:]
        }
        return entry.counts
    }

    func record(origin: Int, flag: String, _ counts: [Int: Int]) {
        guard !counts.isEmpty else { return }
        let key = Self.key(origin: origin, flag: flag)
        var entry = entries[key] ?? Entry(counts: [:], created: Date())
        entry.counts.merge(counts) { _, new in new }
        entries[key] = entry
        scheduleSave()
    }

    private func scheduleSave() {
        saveTask?.cancel()
        saveTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled else { return }
            await self?.save()
        }
    }

    private func save() {
        let snapshot = entries
        let url = Self.fileURL
        Task.detached(priority: .background) {
            guard let data = try? JSONEncoder().encode(snapshot) else { return }
            try? data.write(to: url, options: .atomic)
        }
    }
}
