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
import SQLite3

/// Best-effort recovery of pilots from stores that `StoreBootstrap` (or the older
/// inline recovery code) moved aside as `EVEOps-store-corrupt-<timestamp>.store`.
///
/// Reads the SQLite file directly instead of going through SwiftData, because the whole
/// reason these files were set aside is that SwiftData refused to open them. Works on a
/// throwaway copy so the original is never modified, and tolerates older schemas that
/// lack newer columns.
enum LegacyStoreImporter {
    static let filePrefix = "EVEOps-store-corrupt-"

    /// Moved-aside stores in `directory`, newest first.
    static func candidateStores(in directory: URL) -> [URL] {
        let urls = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
        return urls
            .filter { $0.pathExtension == "store" && $0.lastPathComponent.hasPrefix(filePrefix) }
            // The suffix is a fixed-width epoch timestamp, so name order is age order.
            .sorted { $0.lastPathComponent > $1.lastPathComponent }
    }

    /// Pilots across all moved-aside stores. Where the same pilot appears in several,
    /// the newest store wins.
    static func pilots(in directory: URL) -> [ArchivedPilot] {
        var seen = Set<Int>()
        var result: [ArchivedPilot] = []
        for store in candidateStores(in: directory) {
            let found = readPilots(fromStore: store)
            if !found.isEmpty {
                Logger.app.notice("Legacy store import: \(found.count) pilot(s) readable in \(store.lastPathComponent)")
            }
            for pilot in found where seen.insert(pilot.characterID).inserted {
                result.append(pilot)
            }
        }
        return result
    }

    static func readPilots(fromStore store: URL) -> [ArchivedPilot] {
        let fm = FileManager.default
        let work = fm.temporaryDirectory.appendingPathComponent("EVEOps-legacy-\(UUID().uuidString)", isDirectory: true)
        do {
            try fm.createDirectory(at: work, withIntermediateDirectories: true,
                                   attributes: [.posixPermissions: 0o700])
        } catch {
            return []
        }
        // The copy holds login tokens — always remove it.
        defer { try? fm.removeItem(at: work) }

        let copy = work.appendingPathComponent("legacy.store")
        do { try fm.copyItem(at: store, to: copy) } catch { return [] }
        // A WAL/SHM next to the store carries the newest committed rows.
        for suffix in ["-wal", "-shm"] {
            let source = URL(fileURLWithPath: store.path + suffix)
            if fm.fileExists(atPath: source.path) {
                try? fm.copyItem(at: source, to: URL(fileURLWithPath: copy.path + suffix))
            }
        }

        var db: OpaquePointer?
        guard sqlite3_open_v2(copy.path, &db, SQLITE_OPEN_READWRITE, nil) == SQLITE_OK, let db else {
            sqlite3_close(db)
            return []
        }
        defer { sqlite3_close(db) }
        return query(db)
    }

    // MARK: - SQLite

    private static let table = "ZSTOREDACCOUNT"
    private static let requiredColumns: Set<String> = ["ZCHARACTERID", "ZCHARACTERNAME", "ZREFRESHTOKEN"]
    /// Selected in this order; columns missing from an older schema read as NULL.
    private static let wantedColumns = [
        "ZCHARACTERID", "ZCHARACTERNAME", "ZCORPORATIONID", "ZCORPORATIONNAME",
        "ZALLIANCEID", "ZALLIANCENAME", "ZACCESSTOKEN", "ZREFRESHTOKEN",
        "ZTOKENEXPIRY", "ZSCOPES", "ZADDEDDATE", "ZNEEDSREAUTH"
    ]

    private static func query(_ db: OpaquePointer) -> [ArchivedPilot] {
        let present = columns(in: db)
        guard requiredColumns.isSubset(of: present) else { return [] }

        let select = wantedColumns.map { present.contains($0) ? $0 : "NULL" }.joined(separator: ", ")
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, "SELECT \(select) FROM \(table)", -1, &statement, nil) == SQLITE_OK else {
            return []
        }
        defer { sqlite3_finalize(statement) }

        var pilots: [ArchivedPilot] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            let pilot = ArchivedPilot(
                characterID: int(statement, 0) ?? 0,
                characterName: text(statement, 1) ?? "",
                corporationID: int(statement, 2) ?? 0,
                corporationName: text(statement, 3) ?? "",
                allianceID: int(statement, 4),
                allianceName: text(statement, 5),
                accessToken: text(statement, 6) ?? "",
                refreshToken: text(statement, 7) ?? "",
                // SwiftData stores dates as seconds since 2001-01-01. A missing expiry
                // reads as long-expired, which simply forces a token refresh.
                tokenExpiry: real(statement, 8).map(Date.init(timeIntervalSinceReferenceDate:)) ?? .distantPast,
                scopes: scopes(statement, 9),
                addedDate: real(statement, 10).map(Date.init(timeIntervalSinceReferenceDate:)) ?? Date(),
                needsReauth: (int(statement, 11) ?? 0) != 0
            )
            if pilot.isRestorable { pilots.append(pilot) }
        }
        return pilots
    }

    private static func columns(in db: OpaquePointer) -> Set<String> {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, "PRAGMA table_info(\(table))", -1, &statement, nil) == SQLITE_OK else {
            return []
        }
        defer { sqlite3_finalize(statement) }
        var names = Set<String>()
        while sqlite3_step(statement) == SQLITE_ROW {
            if let name = sqlite3_column_text(statement, 1) { names.insert(String(cString: name)) }
        }
        return names
    }

    private static func isNull(_ s: OpaquePointer?, _ i: Int32) -> Bool {
        sqlite3_column_type(s, i) == SQLITE_NULL
    }

    private static func int(_ s: OpaquePointer?, _ i: Int32) -> Int? {
        isNull(s, i) ? nil : Int(sqlite3_column_int64(s, i))
    }

    private static func real(_ s: OpaquePointer?, _ i: Int32) -> Double? {
        isNull(s, i) ? nil : sqlite3_column_double(s, i)
    }

    private static func text(_ s: OpaquePointer?, _ i: Int32) -> String? {
        guard !isNull(s, i), let raw = sqlite3_column_text(s, i) else { return nil }
        return String(cString: raw)
    }

    /// SwiftData stores a `[String]` attribute as an `NSKeyedArchiver` archive (a binary
    /// plist with `$archiver`/`$objects` keys), so a plain plist read returns nothing.
    /// Fall back to a bare plist array, then JSON, in case an older build differed.
    private static func scopes(_ s: OpaquePointer?, _ i: Int32) -> [String] {
        guard !isNull(s, i), let bytes = sqlite3_column_blob(s, i) else { return [] }
        let data = Data(bytes: bytes, count: Int(sqlite3_column_bytes(s, i)))
        if let archived = try? NSKeyedUnarchiver.unarchivedObject(ofClasses: [NSArray.self, NSString.self], from: data) as? [String] {
            return archived
        }
        if let list = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String] {
            return list
        }
        return (try? JSONDecoder().decode([String].self, from: data)) ?? []
    }
}
