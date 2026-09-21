//
//  PilotArchiveTests.swift
//  EVEOpsTests
//
//  Covers the pilot backup/restore mechanism: the Keychain-backed archive, launch-time
//  reconciliation after a store reset, moved-aside store recovery, store bootstrap on a
//  corrupt file, and the encrypted export file.
//
//  The archive is always backed by `FakeBacking` here — these tests must never touch
//  the real login keychain or the user's real pilot store.
//

import Foundation
import SwiftData
import Testing
@testable import EVEOps

// MARK: - Fixtures

private final class FakeBacking: PilotArchiveBacking {
    var slots: [String: Data] = [:]
    var writeCount = 0
    var failReads = false

    func read(slot: String) throws -> Data? {
        if failReads { throw KeychainError.unexpectedStatus(-25293) }
        return slots[slot]
    }

    func write(_ data: Data, slot: String) throws {
        writeCount += 1
        slots[slot] = data
    }
}

private let t1 = Date(timeIntervalSinceReferenceDate: 800_000_000)
private let t2 = Date(timeIntervalSinceReferenceDate: 800_001_000)
private let t3 = Date(timeIntervalSinceReferenceDate: 800_002_000)

private func pilot(
    _ id: Int,
    name: String? = nil,
    refresh: String = "refresh",
    expiry: Date = t1,
    needsReauth: Bool = false
) -> ArchivedPilot {
    ArchivedPilot(
        characterID: id,
        characterName: name ?? "Pilot \(id)",
        corporationID: 98_000_000 + id,
        corporationName: "Corp \(id)",
        allianceID: id.isMultiple(of: 2) ? 99_000_000 + id : nil,
        allianceName: id.isMultiple(of: 2) ? "Alliance \(id)" : nil,
        accessToken: "access-\(id)",
        refreshToken: "\(refresh)-\(id)",
        tokenExpiry: expiry,
        scopes: ["esi-skills.read_skills.v1", "esi-wallet.read_character_wallet.v1"],
        addedDate: t1,
        needsReauth: needsReauth
    )
}

private func memoryContainer() throws -> ModelContainer {
    try ModelContainer(
        for: StoredAccount.self,
        configurations: ModelConfiguration(isStoredInMemoryOnly: true)
    )
}

private func accounts(in context: ModelContext) throws -> [StoredAccount] {
    try context.fetch(FetchDescriptor<StoredAccount>(sortBy: [SortDescriptor(\.characterID)]))
}

private func scratchDirectory() throws -> URL {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("EVEOpsTests-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}

private func isolatedDefaults() -> UserDefaults {
    let defaults = UserDefaults(suiteName: "EVEOpsTests-\(UUID().uuidString)")!
    return defaults
}

// MARK: - Archive

@MainActor
struct PilotArchiveTests {

    @Test func upsertAddsReplacesAndSkipsUnchangedWrites() {
        let backing = FakeBacking()
        let archive = PilotArchive(backing: backing)

        archive.upsert([pilot(1), pilot(2)])
        #expect(archive.load() == [pilot(1), pilot(2)])
        #expect(backing.writeCount == 1)

        archive.upsert([pilot(1), pilot(2)])
        #expect(backing.writeCount == 1, "identical data must not rewrite the keychain item")

        archive.upsert([pilot(1, refresh: "rotated")])
        #expect(archive.load()?.first?.refreshToken == "rotated-1")
        #expect(archive.load()?.count == 2)
    }

    @Test func recordsThatCannotBeRestoredAreNotArchived() {
        let archive = PilotArchive(backing: FakeBacking())
        var noToken = pilot(1)
        noToken.refreshToken = ""
        archive.upsert([noToken, pilot(2)])
        #expect(archive.load()?.map(\.characterID) == [2])
    }

    @Test func removeDeletesOnlyTheRequestedPilot() {
        let archive = PilotArchive(backing: FakeBacking())
        archive.upsert([pilot(1), pilot(2), pilot(3)])
        archive.remove(characterID: 2)
        #expect(archive.load()?.map(\.characterID) == [1, 3])
    }

    @Test func unreadableKeychainIsNotTreatedAsEmptyAndIsNeverWritten() {
        let backing = FakeBacking()
        let archive = PilotArchive(backing: backing)
        archive.upsert([pilot(1)])
        let writes = backing.writeCount

        backing.failReads = true
        #expect(archive.load() == nil)
        archive.upsert([pilot(2)])
        archive.remove(characterID: 1)
        #expect(backing.writeCount == writes, "a failed read must never lead to an overwrite")

        backing.failReads = false
        #expect(archive.load() == [pilot(1)])
    }

    @Test func undecodableArchiveIsKeptAsideAndReplaced() {
        let backing = FakeBacking()
        backing.slots[PilotArchive.slot] = Data("not json".utf8)
        let archive = PilotArchive(backing: backing)

        #expect(archive.load() == [])
        #expect(backing.slots[PilotArchive.unreadableSlot] == Data("not json".utf8))

        archive.upsert([pilot(1)])
        #expect(archive.load() == [pilot(1)])
    }

    // MARK: Launch reconciliation

    @Test func resetStoreIsRestoredFromArchiveWithTokensIntact() throws {
        let archive = PilotArchive(backing: FakeBacking())
        archive.upsert([pilot(1), pilot(2)])

        let container = try memoryContainer() // an empty, freshly reset store
        let restored = archive.reconcileOnLaunch(
            in: container.mainContext, legacyStoreDirectory: nil, defaults: isolatedDefaults()
        )

        #expect(restored == ["Pilot 1", "Pilot 2"])
        let rows = try accounts(in: container.mainContext)
        #expect(rows.map(\.characterID) == [1, 2])
        #expect(rows[0].refreshToken == "refresh-1")
        #expect(rows[0].scopes == pilot(1).scopes)
        #expect(rows[1].allianceName == "Alliance 2")
        #expect(archive.load()?.count == 2, "restoring must leave the archive intact")
    }

    @Test func emptyStoreNeverErasesTheArchive() throws {
        let backing = FakeBacking()
        let archive = PilotArchive(backing: backing)
        archive.upsert([pilot(1), pilot(2)])
        let writes = backing.writeCount

        // Keep the container alive: a context that outlives its container traps.
        let container = try memoryContainer()
        archive.mirror(container.mainContext)
        #expect(backing.writeCount == writes)
        #expect(archive.load() == [pilot(1), pilot(2)])
    }

    @Test func deliberatelyRemovedPilotIsNotResurrected() throws {
        let archive = PilotArchive(backing: FakeBacking())
        archive.upsert([pilot(1), pilot(2)])
        archive.remove(characterID: 1) // what AccountManager.removeAccount does

        let container = try memoryContainer()
        let restored = archive.reconcileOnLaunch(
            in: container.mainContext, legacyStoreDirectory: nil, defaults: isolatedDefaults()
        )
        #expect(restored == ["Pilot 2"])
        #expect(try accounts(in: container.mainContext).map(\.characterID) == [2])
    }

    @Test func existingPilotsAreMirroredOnFirstLaunch() throws {
        let archive = PilotArchive(backing: FakeBacking())
        let container = try memoryContainer()
        container.mainContext.insert(pilot(1).makeAccount())
        container.mainContext.insert(pilot(2).makeAccount())
        try container.mainContext.save()

        let restored = archive.reconcileOnLaunch(
            in: container.mainContext, legacyStoreDirectory: nil, defaults: isolatedDefaults()
        )
        #expect(restored.isEmpty)
        #expect(Set(archive.load()?.map(\.characterID) ?? []) == [1, 2])
    }

    @Test func liveStoreRowsWinOverStaleArchiveEntries() throws {
        let archive = PilotArchive(backing: FakeBacking())
        archive.upsert([pilot(1, refresh: "old", expiry: t1)])

        let container = try memoryContainer()
        container.mainContext.insert(pilot(1, refresh: "new", expiry: t2).makeAccount())
        try container.mainContext.save()

        _ = archive.reconcileOnLaunch(
            in: container.mainContext, legacyStoreDirectory: nil, defaults: isolatedDefaults()
        )
        #expect(try accounts(in: container.mainContext).first?.refreshToken == "new-1")
        #expect(archive.load()?.first?.refreshToken == "new-1")
    }

    // MARK: Import merge

    @Test func mergeNeverDowngradesALiveToken() throws {
        let archive = PilotArchive(backing: FakeBacking())
        let container = try memoryContainer()
        let context = container.mainContext
        context.insert(pilot(1, refresh: "live", expiry: t2).makeAccount())
        context.insert(pilot(2, refresh: "live", expiry: t2).makeAccount())
        try context.save()

        let result = try archive.merge(
            [
                pilot(1, refresh: "older", expiry: t1),   // stale: ignored
                pilot(2, refresh: "newer", expiry: t3),   // fresher: applied
                pilot(3)                                  // unknown: added
            ],
            into: context
        )

        #expect(result.updated == ["Pilot 2"])
        #expect(result.added == ["Pilot 3"])
        let rows = try accounts(in: context)
        #expect(rows.map(\.refreshToken) == ["live-1", "newer-2", "refresh-3"])
    }

    @Test func mergeAdoptsABackupLoginForAPilotThatNeedsReauth() throws {
        let archive = PilotArchive(backing: FakeBacking())
        let container = try memoryContainer()
        let broken = pilot(1, refresh: "dead", expiry: t2, needsReauth: true)
        container.mainContext.insert(broken.makeAccount())
        try container.mainContext.save()

        let result = try archive.merge([pilot(1, refresh: "good", expiry: t1)], into: container.mainContext)
        #expect(result.updated == ["Pilot 1"])
        let row = try #require(try accounts(in: container.mainContext).first)
        #expect(row.refreshToken == "good-1")
        #expect(row.needsReauth == false)
    }
}

// MARK: - Encrypted export file

struct PilotBackupFileTests {
    private let iterations = 1_000 // fast; the format records the count, so production uses 600k

    @Test func roundTrips() throws {
        let file = try PilotBackupFile.encrypt([pilot(1), pilot(2)], passphrase: "correct horse", iterations: iterations)
        #expect(try PilotBackupFile.decrypt(file, passphrase: "correct horse") == [pilot(1), pilot(2)])
    }

    @Test func fileNeverContainsTokensInThePlain() throws {
        let file = try PilotBackupFile.encrypt([pilot(1)], passphrase: "correct horse", iterations: iterations)
        let text = String(decoding: file, as: UTF8.self)
        #expect(!text.contains("refresh-1"))
        #expect(!text.contains("access-1"))
        #expect(!text.contains("Pilot 1"))
    }

    @Test func wrongPassphraseIsRejected() throws {
        let file = try PilotBackupFile.encrypt([pilot(1)], passphrase: "correct horse", iterations: iterations)
        #expect(throws: PilotBackupFile.Failure.wrongPassphraseOrDamaged) {
            try PilotBackupFile.decrypt(file, passphrase: "battery staple")
        }
    }

    @Test func tamperedFileIsRejected() throws {
        var file = try PilotBackupFile.encrypt([pilot(1)], passphrase: "correct horse", iterations: iterations)
        // Flip a byte inside the sealed payload (near the end, past the header fields).
        let index = file.index(file.endIndex, offsetBy: -40)
        file[index] = file[index] == UInt8(ascii: "A") ? UInt8(ascii: "B") : UInt8(ascii: "A")
        #expect(throws: (any Error).self) {
            try PilotBackupFile.decrypt(file, passphrase: "correct horse")
        }
    }

    @Test func nonBackupFileIsRejected() {
        #expect(throws: PilotBackupFile.Failure.notABackupFile) {
            try PilotBackupFile.decrypt(Data("hello".utf8), passphrase: "x")
        }
    }

    @Test func absurdIterationCountFromACraftedFileIsRefused() throws {
        let file = try PilotBackupFile.encrypt([pilot(1)], passphrase: "correct horse", iterations: iterations)
        var text = String(decoding: file, as: UTF8.self)
        text = text.replacingOccurrences(of: "\"iterations\" : \(iterations)", with: "\"iterations\" : 4000000000")
        #expect(throws: PilotBackupFile.Failure.notABackupFile) {
            try PilotBackupFile.decrypt(Data(text.utf8), passphrase: "correct horse")
        }
    }
}

// MARK: - Moved-aside stores and store bootstrap (real SQLite files)

@MainActor
struct StoreRecoveryTests {

    /// A real on-disk SwiftData store holding one pilot — the same shape earlier versions
    /// produced — plus its live container (kept open so the WAL is still present).
    private func makeRealStore(at url: URL, pilot p: ArchivedPilot) throws -> ModelContainer {
        let container = try ModelContainer(
            for: StoredAccount.self,
            configurations: ModelConfiguration(schema: Schema([StoredAccount.self]), url: url)
        )
        container.mainContext.insert(p.makeAccount())
        try container.mainContext.save()
        return container
    }

    private func copyStore(_ url: URL, toAsideNamed name: String, in directory: URL) throws {
        let fm = FileManager.default
        for suffix in ["", "-wal", "-shm"] {
            let source = URL(fileURLWithPath: url.path + suffix)
            if fm.fileExists(atPath: source.path) {
                try fm.copyItem(at: source, to: directory.appendingPathComponent(name + suffix))
            }
        }
    }

    @Test func legacyImporterReadsAllFieldsFromARealSwiftDataStore() throws {
        let dir = try scratchDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }

        let original = pilot(2, expiry: t2, needsReauth: true) // even id → has an alliance
        let live = try makeRealStore(at: dir.appendingPathComponent("default.store"), pilot: original)
        try copyStore(dir.appendingPathComponent("default.store"),
                      toAsideNamed: "EVEOps-store-corrupt-1700000000.store", in: dir)
        _ = live

        let found = LegacyStoreImporter.pilots(in: dir)
        #expect(found.count == 1)
        let recovered = try #require(found.first)
        #expect(recovered.characterID == original.characterID)
        #expect(recovered.characterName == original.characterName)
        #expect(recovered.corporationID == original.corporationID)
        #expect(recovered.corporationName == original.corporationName)
        #expect(recovered.allianceID == original.allianceID)
        #expect(recovered.allianceName == original.allianceName)
        #expect(recovered.accessToken == original.accessToken)
        #expect(recovered.refreshToken == original.refreshToken)
        #expect(recovered.scopes == original.scopes)
        #expect(recovered.needsReauth == true)
        #expect(abs(recovered.tokenExpiry.timeIntervalSince(original.tokenExpiry)) < 0.001)
    }

    @Test func legacyImporterLeavesTheOriginalUntouchedAndCleansUpItsCopy() throws {
        let dir = try scratchDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let storeURL = dir.appendingPathComponent("default.store")
        let live = try makeRealStore(at: storeURL, pilot: pilot(1))
        try copyStore(storeURL, toAsideNamed: "EVEOps-store-corrupt-1700000000.store", in: dir)
        _ = live

        let aside = dir.appendingPathComponent("EVEOps-store-corrupt-1700000000.store")
        let before = try Data(contentsOf: aside)
        let tempBefore = try FileManager.default.contentsOfDirectory(atPath: FileManager.default.temporaryDirectory.path)
            .filter { $0.hasPrefix("EVEOps-legacy-") }

        _ = LegacyStoreImporter.pilots(in: dir)

        #expect(try Data(contentsOf: aside) == before)
        let tempAfter = try FileManager.default.contentsOfDirectory(atPath: FileManager.default.temporaryDirectory.path)
            .filter { $0.hasPrefix("EVEOps-legacy-") }
        #expect(tempAfter.count == tempBefore.count, "the temporary token copy must be removed")
    }

    @Test func legacyImporterToleratesGarbageAndForeignFiles() throws {
        let dir = try scratchDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        try Data("garbage".utf8).write(to: dir.appendingPathComponent("EVEOps-store-corrupt-1700000001.store"))
        try Data("unrelated".utf8).write(to: dir.appendingPathComponent("other.store"))

        #expect(LegacyStoreImporter.pilots(in: dir).isEmpty)
    }

    @Test func aStoreResetBeforeThisFeatureExistedIsRecoveredOnFirstLaunch() throws {
        let dir = try scratchDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let storeURL = dir.appendingPathComponent("default.store")
        let live = try makeRealStore(at: storeURL, pilot: pilot(1))
        try copyStore(storeURL, toAsideNamed: "EVEOps-store-corrupt-1700000000.store", in: dir)
        _ = live

        // Fresh, empty store + empty archive = someone who just lost their pilots.
        let archive = PilotArchive(backing: FakeBacking())
        let defaults = isolatedDefaults()
        let container = try memoryContainer()

        let restored = archive.reconcileOnLaunch(in: container.mainContext, legacyStoreDirectory: dir, defaults: defaults)
        #expect(restored == ["Pilot 1"])
        #expect(try accounts(in: container.mainContext).first?.refreshToken == "refresh-1")
        #expect(archive.load()?.map(\.characterID) == [1], "recovered pilots are protected from now on")

        // The scan is one-time: after the user removes everyone, nothing comes back.
        container.mainContext.delete(try #require(try accounts(in: container.mainContext).first))
        try container.mainContext.save()
        archive.remove(characterID: 1)
        let again = archive.reconcileOnLaunch(in: container.mainContext, legacyStoreDirectory: dir, defaults: defaults)
        #expect(again.isEmpty)
        #expect(try accounts(in: container.mainContext).isEmpty)
    }

    @Test func healthyStoreOpensAndPersistsAcrossLaunches() throws {
        let dir = try scratchDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appendingPathComponent("test.store")
        let schema = Schema([StoredAccount.self])

        let first = StoreBootstrap.makeContainer(schema: schema, storeURL: url)
        #expect(first.outcome == .healthy)
        first.container.mainContext.insert(pilot(1).makeAccount())
        try first.container.mainContext.save()

        let second = StoreBootstrap.makeContainer(schema: schema, storeURL: url)
        #expect(second.outcome == .healthy)
        #expect(try accounts(in: second.container.mainContext).map(\.characterID) == [1])
    }

    @Test func corruptStoreIsMovedAsideWithItsWalAndAFreshOneOpens() throws {
        let dir = try scratchDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appendingPathComponent("test.store")
        try Data("this is not a sqlite database".utf8).write(to: url)
        try Data("wal bytes".utf8).write(to: URL(fileURLWithPath: url.path + "-wal"))
        try Data("shm bytes".utf8).write(to: URL(fileURLWithPath: url.path + "-shm"))

        let now = Date(timeIntervalSince1970: 1_700_000_123)
        let result = StoreBootstrap.makeContainer(schema: Schema([StoredAccount.self]), storeURL: url, now: now)

        let aside = dir.appendingPathComponent("EVEOps-store-corrupt-1700000123.store")
        #expect(result.outcome == .resetToEmpty(previousStore: aside))
        #expect(try Data(contentsOf: aside) == Data("this is not a sqlite database".utf8))
        // The sidecars travel with the store — they used to be deleted.
        #expect(try Data(contentsOf: URL(fileURLWithPath: aside.path + "-wal")) == Data("wal bytes".utf8))
        #expect(try Data(contentsOf: URL(fileURLWithPath: aside.path + "-shm")) == Data("shm bytes".utf8))

        // The replacement is a working, empty store.
        #expect(try accounts(in: result.container.mainContext).isEmpty)
        result.container.mainContext.insert(pilot(1).makeAccount())
        try result.container.mainContext.save()
        #expect(try accounts(in: result.container.mainContext).count == 1)
    }

    @Test func aCrashedStoreEndToEndPilotsComeBackFromTheArchive() throws {
        let dir = try scratchDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appendingPathComponent("test.store")

        // Before the crash: the archive was mirroring the pilots.
        let archive = PilotArchive(backing: FakeBacking())
        archive.upsert([pilot(1, refresh: "r1"), pilot(2, refresh: "r2")])

        // The crash leaves a damaged store behind.
        try Data("torn write".utf8).write(to: url)

        let result = StoreBootstrap.makeContainer(schema: Schema([StoredAccount.self]), storeURL: url)
        guard case .resetToEmpty = result.outcome else {
            Issue.record("expected the damaged store to be reset, got \(result.outcome)")
            return
        }
        #expect(try accounts(in: result.container.mainContext).isEmpty, "this is the state users reported")

        let restored = archive.reconcileOnLaunch(
            in: result.container.mainContext, legacyStoreDirectory: dir, defaults: isolatedDefaults()
        )
        #expect(restored == ["Pilot 1", "Pilot 2"])
        let rows = try accounts(in: result.container.mainContext)
        #expect(rows.map(\.refreshToken) == ["r1-1", "r2-2"])

        // And it is durable: reopening the new store shows them without any restore.
        let reopened = StoreBootstrap.makeContainer(schema: Schema([StoredAccount.self]), storeURL: url)
        #expect(reopened.outcome == .healthy)
        #expect(try accounts(in: reopened.container.mainContext).count == 2)
    }
}
