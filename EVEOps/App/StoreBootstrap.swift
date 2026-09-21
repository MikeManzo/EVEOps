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
import SwiftData

/// What happened when the SwiftData store was opened at launch.
enum StoreRecovery: Equatable {
    case healthy
    /// The store couldn't be opened; it was moved aside and a new empty one created.
    case resetToEmpty(previousStore: URL?)
    /// Even a fresh store failed; running in memory, nothing persists this session.
    case inMemoryFallback
}

enum StoreBootstrap {
    /// Set once at launch so `AccountManager` can tell the user what happened.
    static var lastOutcome: StoreRecovery = .healthy

    /// Opens the store, recovering instead of crashing when it is corrupt or
    /// schema-incompatible: move the old store aside and retry once, then fall back to
    /// an in-memory store so the app still launches.
    ///
    /// The moved-aside copy is complete — store, `-wal` and `-shm` together — so it stays a
    /// valid SQLite database that `LegacyStoreImporter` can read. Pilots themselves are
    /// protected by `PilotArchive`, which lives in the Keychain and survives this reset.
    static func makeContainer(
        schema: Schema,
        storeURL: URL? = nil,
        now: Date = Date()
    ) -> (container: ModelContainer, outcome: StoreRecovery) {
        let config = storeURL.map { ModelConfiguration(schema: schema, url: $0) }
            ?? ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)

        do {
            return (try ModelContainer(for: schema, configurations: [config]), .healthy)
        } catch {
            Logger.app.error("ModelContainer creation failed: \(error.localizedDescription) — resetting local store")
        }

        let fm = FileManager.default
        let original = config.url
        let stamp = Int(now.timeIntervalSince1970)
        let aside = original.deletingLastPathComponent()
            .appendingPathComponent("\(LegacyStoreImporter.filePrefix)\(stamp).store")

        var previousStore: URL?
        do {
            try fm.moveItem(at: original, to: aside)
            previousStore = aside
            for suffix in ["-wal", "-shm"] {
                let sidecar = URL(fileURLWithPath: original.path + suffix)
                guard fm.fileExists(atPath: sidecar.path) else { continue }
                try? fm.moveItem(at: sidecar, to: URL(fileURLWithPath: aside.path + suffix))
            }
        } catch {
            Logger.app.error("Could not move the local store aside: \(error.localizedDescription)")
        }

        if let recovered = try? ModelContainer(for: schema, configurations: [config]) {
            Logger.app.notice("ModelContainer recovered after resetting the local store")
            return (recovered, .resetToEmpty(previousStore: previousStore))
        }

        Logger.app.fault("ModelContainer falling back to an in-memory store — data will not persist this session")
        let memoryConfig = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        // An in-memory container effectively never fails; if it does the
        // process genuinely cannot run.
        return (try! ModelContainer(for: schema, configurations: [memoryConfig]), .inMemoryFallback)
    }
}
