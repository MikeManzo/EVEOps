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

struct LogEntry: Identifiable, Sendable, Codable {
    let id: UUID
    let date: Date
    let category: String
    let level: Level
    let message: String

    init(date: Date = Date(), category: String, level: Level, message: String) {
        self.id = UUID()
        self.date = date
        self.category = category
        self.level = level
        self.message = message
    }

    enum Level: Int, Comparable, Sendable, Codable {
        case debug = 1, info = 2, notice = 3, error = 4, fault = 5
        static func < (lhs: Self, rhs: Self) -> Bool { lhs.rawValue < rhs.rawValue }
    }
}

@Observable @MainActor
final class DiagnosticLogStore {
    static let shared = DiagnosticLogStore()

    private(set) var entries: [LogEntry] = []
    private var unsavedCount = 0

    static let maxEntriesKey = "diagMaxEntries"
    static let maxDaysKey    = "diagMaxDays"

    private static let flushThreshold = 25

    private static let storageURL: URL = {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return base.appendingPathComponent("EVEOps/diagnostics.json")
    }()

    private init() {}

    // MARK:  Startup

    func load() {
        let url = Self.storageURL
        let maxDaysKey = Self.maxDaysKey
        Task { [weak self] in
            let filtered: [LogEntry] = await Task.detached(priority: .utility) {
                guard let data = try? Data(contentsOf: url),
                      let decoded = try? JSONDecoder().decode([LogEntry].self, from: data)
                else { return [] }
                let rawDays = UserDefaults.standard.integer(forKey: maxDaysKey)
                let days = rawDays > 0 ? max(1, min(30, rawDays)) : 7
                let cutoff = Date().addingTimeInterval(-Double(days) * 86400)
                return decoded.filter { $0.date > cutoff }
            }.value
            self?.entries = filtered
        }
    }

    // MARK:  Write

    func write(date: Date, category: String, level: LogEntry.Level, message: String) {
        let rawMax = UserDefaults.standard.integer(forKey: Self.maxEntriesKey)
        let maxEntries = rawMax > 0 ? max(100, min(5000, rawMax)) : 1000

        entries.append(LogEntry(date: date, category: category, level: level, message: message))
        if entries.count > maxEntries {
            entries.removeFirst(entries.count - maxEntries)
        }

        unsavedCount += 1
        if unsavedCount >= Self.flushThreshold {
            unsavedCount = 0
            flush()
        }
    }

    // MARK:  Persistence

    func flushNow() {
        guard !entries.isEmpty else { return }
        unsavedCount = 0
        flush()
    }

    func clear() {
        entries.removeAll()
        unsavedCount = 0
        let url = Self.storageURL
        Task.detached(priority: .background) {
            try? FileManager.default.removeItem(at: url)
        }
    }

    private func flush() {
        let snapshot = entries
        let url = Self.storageURL
        Task.detached(priority: .background) {
            do {
                try FileManager.default.createDirectory(
                    at: url.deletingLastPathComponent(),
                    withIntermediateDirectories: true
                )
                let data = try JSONEncoder().encode(snapshot)
                try data.write(to: url, options: .atomic)
            } catch {}
        }
    }
}
