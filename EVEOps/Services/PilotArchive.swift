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

// MARK: - Archived record

/// Everything needed to bring a pilot back after the SwiftData store is lost —
/// identity for display, plus the tokens so the user is not sent through SSO again.
nonisolated struct ArchivedPilot: Codable, Equatable, Sendable {
    var characterID: Int
    var characterName: String
    var corporationID: Int
    var corporationName: String
    var allianceID: Int?
    var allianceName: String?
    var accessToken: String
    var refreshToken: String
    var tokenExpiry: Date
    var scopes: [String]
    var addedDate: Date
    var needsReauth: Bool

    /// A record without an identity or refresh token cannot be brought back to life.
    var isRestorable: Bool {
        characterID > 0 && !characterName.isEmpty && !refreshToken.isEmpty
    }
}

extension ArchivedPilot {
    @MainActor
    init(_ account: StoredAccount) {
        self.init(
            characterID: account.characterID,
            characterName: account.characterName,
            corporationID: account.corporationID,
            corporationName: account.corporationName,
            allianceID: account.allianceID,
            allianceName: account.allianceName,
            accessToken: account.accessToken,
            refreshToken: account.refreshToken,
            tokenExpiry: account.tokenExpiry,
            scopes: account.scopes,
            addedDate: account.addedDate,
            needsReauth: account.needsReauth
        )
    }

    @MainActor
    func makeAccount() -> StoredAccount {
        let account = StoredAccount(
            characterID: characterID,
            characterName: characterName,
            corporationID: corporationID,
            corporationName: corporationName,
            allianceID: allianceID,
            allianceName: allianceName,
            accessToken: accessToken,
            refreshToken: refreshToken,
            tokenExpiry: tokenExpiry,
            scopes: scopes,
            addedDate: addedDate
        )
        account.needsReauth = needsReauth
        return account
    }

    @MainActor
    func apply(to account: StoredAccount) {
        account.characterName = characterName
        account.corporationID = corporationID
        account.corporationName = corporationName
        account.allianceID = allianceID
        account.allianceName = allianceName
        account.accessToken = accessToken
        account.refreshToken = refreshToken
        account.tokenExpiry = tokenExpiry
        account.scopes = scopes
        account.needsReauth = needsReauth
    }

    /// Whether this record carries a better login than what the store already has —
    /// used when merging a backup so an old file can never downgrade a live token.
    @MainActor
    func isFresher(than account: StoredAccount) -> Bool {
        (account.needsReauth && !needsReauth) || tokenExpiry > account.tokenExpiry
    }
}

// MARK: - Backing storage

/// Where the archive bytes live. The Keychain in production; swapped for an
/// in-memory fake in tests so they never touch the real login keychain.
protocol PilotArchiveBacking {
    func read(slot: String) throws -> Data?
    func write(_ data: Data, slot: String) throws
}

struct KeychainPilotArchiveBacking: PilotArchiveBacking {
    func read(slot: String) throws -> Data? {
        try KeychainHelper.loadOptional(for: slot)
    }

    func write(_ data: Data, slot: String) throws {
        try KeychainHelper.save(data, for: slot)
    }
}

// MARK: - Archive

/// A durable second copy of every pilot, kept in the Keychain — outside the SwiftData
/// store — so a store reset (failed migration after an update, corruption after a
/// crash) cannot take the pilots' logins with it.
///
/// The archive is deliberately *additive*: it only ever gains or replaces entries, and
/// an entry leaves only through `remove(characterID:)` (the user deleting the pilot).
/// It is never rewritten from "whatever the store currently holds" — that is exactly
/// how an empty, freshly reset store would erase the backup.
final class PilotArchive {
    static let shared = PilotArchive(backing: KeychainPilotArchiveBacking())

    nonisolated static let slot = "pilot-archive.v1"
    /// Holds the previous bytes if the archive ever turns out to be undecodable.
    nonisolated static let unreadableSlot = "pilot-archive.v1.unreadable"
    /// One-time gate for the automatic scan of moved-aside stores from older versions.
    nonisolated static let legacyScanKey = "pilotArchive.legacyScanDone"

    private struct Envelope: Codable {
        var version: Int
        var pilots: [ArchivedPilot]
    }
    private static let currentVersion = 1

    private let backing: PilotArchiveBacking

    init(backing: PilotArchiveBacking) {
        self.backing = backing
    }

    /// The archived pilots, or nil when the archive could not be read at all (keychain
    /// locked or access denied). nil means "don't know" — callers must not treat it as
    /// empty and must not write, or a transient failure would overwrite a good archive.
    func load() -> [ArchivedPilot]? {
        let data: Data?
        do {
            data = try backing.read(slot: Self.slot)
        } catch {
            Logger.auth.error("Pilot archive: keychain read failed (\(error))")
            return nil
        }
        guard let data else { return [] }

        if let envelope = try? JSONDecoder().decode(Envelope.self, from: data),
           envelope.version <= Self.currentVersion {
            return envelope.pilots
        }

        // Undecodable (damaged, or written by a newer version). Keep the bytes aside,
        // then start over so future writes aren't blocked forever.
        try? backing.write(data, slot: Self.unreadableSlot)
        Logger.auth.error("Pilot archive: contents unreadable — kept a copy and starting fresh")
        return []
    }

    func upsert(_ incoming: [ArchivedPilot]) {
        guard !incoming.isEmpty, var pilots = load() else { return }
        var added: [String] = []
        var updated: [String] = []
        for pilot in incoming where pilot.isRestorable {
            if let index = pilots.firstIndex(where: { $0.characterID == pilot.characterID }) {
                if pilots[index] != pilot {
                    pilots[index] = pilot
                    updated.append(pilot.characterName)
                }
            } else {
                pilots.append(pilot)
                added.append(pilot.characterName)
            }
        }
        guard !added.isEmpty || !updated.isEmpty, store(pilots) else { return }

        // New pilots are worth a visible line. Routine token refreshes recur every ~20
        // minutes per pilot, so they log at debug to avoid pushing real events out of the
        // diagnostic log's fixed-size window.
        if !added.isEmpty {
            Logger.auth.info("Pilot archive: backed up \(added.joined(separator: ", ")) to Keychain (\(pilots.count) total)")
        }
        if !updated.isEmpty {
            Logger.auth.debug("Pilot archive: saved refreshed login for \(updated.joined(separator: ", "))")
        }
    }

    /// Only for a pilot the user deliberately removed.
    func remove(characterID: Int) {
        guard var pilots = load() else { return }
        guard let name = pilots.first(where: { $0.characterID == characterID })?.characterName else { return }
        pilots.removeAll { $0.characterID == characterID }
        if store(pilots) {
            Logger.auth.info("Pilot archive: removed \(name) from Keychain backup (\(pilots.count) remaining)")
        }
    }

    /// Returns whether the write succeeded, so callers only report saves that happened.
    private func store(_ pilots: [ArchivedPilot]) -> Bool {
        do {
            let data = try JSONEncoder().encode(Envelope(version: Self.currentVersion, pilots: pilots))
            try backing.write(data, slot: Self.slot)
            return true
        } catch {
            Logger.auth.error("Pilot archive: write failed (\(error))")
            return false
        }
    }
}

// MARK: - Syncing with the SwiftData store

extension PilotArchive {
    struct MergeResult: Equatable {
        var added: [String] = []
        var updated: [String] = []
    }

    /// Re-inserts every archived pilot the store lacks — and, when `legacyStoreDirectory`
    /// is given, pilots found in moved-aside stores from earlier versions. Returns the
    /// names brought back. Existing store rows are never touched.
    @discardableResult
    func restoreMissing(into context: ModelContext, legacyStoreDirectory: URL? = nil) -> [String] {
        let existing = (try? context.fetch(FetchDescriptor<StoredAccount>())) ?? []
        var known = Set(existing.map(\.characterID))
        var restored: [String] = []

        for pilot in load() ?? [] where pilot.isRestorable && !known.contains(pilot.characterID) {
            context.insert(pilot.makeAccount())
            known.insert(pilot.characterID)
            restored.append(pilot.characterName)
        }

        if let directory = legacyStoreDirectory {
            for pilot in LegacyStoreImporter.pilots(in: directory)
            where pilot.isRestorable && !known.contains(pilot.characterID) {
                context.insert(pilot.makeAccount())
                known.insert(pilot.characterID)
                restored.append(pilot.characterName)
            }
        }

        if !restored.isEmpty {
            try? context.save()
            Logger.auth.notice("Pilot archive: restored \(restored.count) pilot(s): \(restored.joined(separator: ", "))")
        }
        return restored
    }

    /// Copies whatever the store holds into the archive. Safe on an empty store: it adds
    /// nothing and removes nothing.
    func mirror(_ context: ModelContext) {
        let accounts = (try? context.fetch(FetchDescriptor<StoredAccount>())) ?? []
        upsert(accounts.map { ArchivedPilot($0) })
    }

    /// The launch-time pass: bring back anything lost, then protect what's there.
    ///
    /// Moved-aside stores from versions that shipped before this archive are scanned
    /// only once, and only when both the store and the archive are empty — that's the
    /// signature of someone who just lost their pilots, and it can never resurrect a
    /// pilot the user removed on purpose (that would need an empty archive *and* an
    /// empty store *and* the first launch of this feature).
    func reconcileOnLaunch(
        in context: ModelContext,
        legacyStoreDirectory: URL?,
        defaults: UserDefaults = .standard
    ) -> [String] {
        let storeIsEmpty = ((try? context.fetchCount(FetchDescriptor<StoredAccount>())) ?? 0) == 0
        let archived = load()

        var scanDirectory: URL?
        if let archived {
            if storeIsEmpty, archived.isEmpty, !defaults.bool(forKey: Self.legacyScanKey) {
                scanDirectory = legacyStoreDirectory
            }
            defaults.set(true, forKey: Self.legacyScanKey)
        }

        let restored = restoreMissing(into: context, legacyStoreDirectory: scanDirectory)
        mirror(context)

        // One line per launch saying whether the safety net is actually in place.
        if let total = load()?.count {
            Logger.auth.info("Pilot archive: \(total) pilot(s) backed up in Keychain")
        } else {
            Logger.auth.warning("Pilot archive: Keychain unavailable — pilots are NOT backed up this session")
        }
        return restored
    }

    /// Merges pilots from an imported backup file. An existing pilot is only replaced
    /// when the backup's login is fresher, so importing an old file can't downgrade a
    /// live token. Saves the context; the caller refreshes its view of the accounts.
    func merge(_ pilots: [ArchivedPilot], into context: ModelContext) throws -> MergeResult {
        let existing = (try? context.fetch(FetchDescriptor<StoredAccount>())) ?? []
        var byID = Dictionary(existing.map { ($0.characterID, $0) }, uniquingKeysWith: { first, _ in first })
        var result = MergeResult()

        for pilot in pilots where pilot.isRestorable {
            if let account = byID[pilot.characterID] {
                if pilot.isFresher(than: account) {
                    pilot.apply(to: account)
                    result.updated.append(pilot.characterName)
                }
            } else {
                let account = pilot.makeAccount()
                context.insert(account)
                byID[pilot.characterID] = account
                result.added.append(pilot.characterName)
            }
        }

        try context.save()
        mirror(context)
        return result
    }
}
