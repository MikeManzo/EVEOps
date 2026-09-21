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
import SwiftUI

/// A one-line status the main window shows above the content (pilots restored from
/// backup, storage reset, …). Dismissed by the user.
struct AccountNotice: Identifiable, Equatable {
    let id = UUID()
    let message: String
    let isWarning: Bool
}

@MainActor
@Observable
final class AccountManager {
    var accounts: [StoredAccount] = []
    var selectedCharacterID: Int?
    var isLoading = false
    var error: String?
    // Increments whenever any account token is updated, allowing views to re-fire
    // tasks after a re-authenticate even when selectedCharacterID hasn't changed.
    var tokenVersion: Int = 0
    var notices: [AccountNotice] = []

    private let modelContext: ModelContext
    private let archive: PilotArchive
    private let authenticator: SSOAuthenticator
    // Tracks in-flight refresh tasks keyed by character ID to prevent duplicate
    // concurrent refreshes from consuming a single-use refresh token twice.
    private var refreshTasks: [Int: Task<SSOTokenResponse, Error>] = [:]

    /// Where a previous version left a moved-aside store — the store lives directly in
    /// Application Support (unsandboxed), and so do the `EVEOps-store-corrupt-*` copies.
    private nonisolated static var defaultLegacyStoreDirectory: URL? {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
    }

    init(
        modelContext: ModelContext,
        archive: PilotArchive? = nil,
        legacyStoreDirectory: URL? = AccountManager.defaultLegacyStoreDirectory,
        defaults: UserDefaults = .standard
    ) {
        self.modelContext = modelContext
        // Resolved here, not as a default argument: `.shared` is main-actor isolated.
        self.archive = archive ?? .shared
        self.authenticator = SSOAuthenticator(config: .default)
        loadAccounts()
        recoverPilotsOnLaunch(legacyStoreDirectory: legacyStoreDirectory, defaults: defaults)
    }

    /// Brings back pilots lost to a store reset, then mirrors what's present into the
    /// Keychain archive so the next reset can't lose them.
    private func recoverPilotsOnLaunch(legacyStoreDirectory: URL?, defaults: UserDefaults) {
        let restored = archive.reconcileOnLaunch(
            in: modelContext,
            legacyStoreDirectory: legacyStoreDirectory,
            defaults: defaults
        )
        if !restored.isEmpty { loadAccounts() }

        let outcome = StoreBootstrap.lastOutcome
        if !restored.isEmpty {
            let noun = restored.count == 1 ? "pilot" : "pilots"
            let cause = outcome == .healthy ? "" : "Local storage was reset. "
            notices.append(AccountNotice(
                message: "\(cause)Restored \(restored.count) \(noun) from backup: \(restored.joined(separator: ", ")).",
                isWarning: false
            ))
        } else if case .resetToEmpty = outcome, accounts.isEmpty {
            notices.append(AccountNotice(
                message: "Local storage was reset and no pilot backup was found. Add your characters again in Settings.",
                isWarning: true
            ))
        }
        if outcome == .inMemoryFallback {
            notices.append(AccountNotice(
                message: "Local storage couldn't be opened, so changes won't be saved this session. Your pilot backup is unaffected.",
                isWarning: true
            ))
        }
    }

    /// Saves the context and mirrors the account into the archive. The archive is written
    /// even if the store save fails — it is the copy that has to survive the store.
    private func persist(_ account: StoredAccount) {
        do {
            try modelContext.save()
        } catch {
            Logger.auth.error("Store: saving \(account.characterName) failed (\(error.localizedDescription)) — Keychain backup is still updated")
        }
        archive.upsert([ArchivedPilot(account)])
    }

    func dismissNotice(_ notice: AccountNotice) {
        notices.removeAll { $0.id == notice.id }
    }

    var selectedAccount: StoredAccount? {
        accounts.first { $0.characterID == selectedCharacterID }
    }

    var hasAccountsNeedingReauth: Bool {
        accounts.contains { $0.needsReauth }
    }

    var reauthNeededCharacterNames: [String] {
        accounts.filter { $0.needsReauth }.map { $0.characterName }
    }

    var uniqueCorporations: [(id: Int, name: String)] {
        let corps = Set(accounts.map { $0.corporationID })
        return corps.compactMap { corpID in
            guard let account = accounts.first(where: { $0.corporationID == corpID }) else { return nil }
            return (id: corpID, name: account.corporationName)
        }.sorted { $0.name < $1.name }
    }

    func loadAccounts() {
        let descriptor = FetchDescriptor<StoredAccount>(sortBy: [SortDescriptor(\.characterName)])
        accounts = (try? modelContext.fetch(descriptor)) ?? []
        if selectedCharacterID == nil {
            selectedCharacterID = accounts.first?.characterID
        }
    }

    func addAccount() async {
        isLoading = true
        error = nil
        do {
            let tokenResponse = try await authenticator.authenticate()
            let character = try decodeSSOJWT(tokenResponse.accessToken)

            // Check if already exists
            if let existing = accounts.first(where: { $0.characterID == character.characterID }) {
                existing.accessToken = tokenResponse.accessToken
                existing.refreshToken = tokenResponse.refreshToken
                existing.tokenExpiry = Date().addingTimeInterval(TimeInterval(tokenResponse.expiresIn))
                existing.scopes = character.scopes
                tokenVersion += 1
                Logger.auth.info("Auth: Token updated for \(existing.characterName) (ID: \(existing.characterID))")
            } else {
                let charInfo: ESICharacterPublic = try await ESIClient.shared.fetch(
                    "/characters/\(character.characterID)/"
                )

                let corpInfo: ESICorporationPublic = try await ESIClient.shared.fetch(
                    "/corporations/\(charInfo.corporationId)/"
                )

                var allianceName: String? = nil
                if let allianceId = charInfo.allianceId {
                    let resolved = await NameResolver.shared.resolve(ids: [allianceId])
                    allianceName = resolved[allianceId]
                }

                let account = StoredAccount(
                    characterID: character.characterID,
                    characterName: character.characterName,
                    corporationID: charInfo.corporationId,
                    corporationName: corpInfo.name,
                    allianceID: charInfo.allianceId,
                    allianceName: allianceName,
                    accessToken: tokenResponse.accessToken,
                    refreshToken: tokenResponse.refreshToken,
                    tokenExpiry: Date().addingTimeInterval(TimeInterval(tokenResponse.expiresIn)),
                    scopes: character.scopes
                )
                modelContext.insert(account)
                Logger.auth.info("Auth: Account added — \(account.characterName) (ID: \(account.characterID))")
            }

            try modelContext.save()
            archive.mirror(modelContext)
            loadAccounts()
        } catch {
            self.error = error.localizedDescription
        }
        isLoading = false
    }

    func removeAccount(_ account: StoredAccount) {
        let characterID = account.characterID
        Logger.auth.info("Auth: Account removed — \(account.characterName) (ID: \(characterID))")
        modelContext.delete(account)
        try? modelContext.save()
        // A pilot the user removed on purpose must not be resurrected from the backup.
        archive.remove(characterID: characterID)
        loadAccounts()
        if selectedCharacterID == characterID {
            selectedCharacterID = accounts.first?.characterID
        }
    }

    func validToken(for account: StoredAccount) async throws -> String {
        if !account.isTokenExpired {
            return account.accessToken
        }

        let charID = account.characterID

        // If a refresh is already in-flight for this account, reuse it rather than
        // sending a second request with the same (single-use) refresh token.
        if let existing = refreshTasks[charID] {
            let tokenResponse = try await existing.value
            return tokenResponse.accessToken
        }

        Logger.auth.info("Auth: Token expired for \(account.characterName) — refreshing")
        let task = Task<SSOTokenResponse, Error> {
            try await self.authenticator.refreshToken(account.refreshToken)
        }
        refreshTasks[charID] = task

        do {
            let tokenResponse = try await task.value
            refreshTasks.removeValue(forKey: charID)
            account.accessToken = tokenResponse.accessToken
            account.refreshToken = tokenResponse.refreshToken
            account.tokenExpiry = Date().addingTimeInterval(TimeInterval(tokenResponse.expiresIn))
            account.needsReauth = false
            tokenVersion += 1
            Logger.auth.info("Auth: Token refreshed successfully for \(account.characterName)")
            persist(account)
            return tokenResponse.accessToken
        } catch SSOError.refreshTokenExpired {
            // Refresh token is permanently invalid — user must log in again manually.
            refreshTasks.removeValue(forKey: charID)
            account.needsReauth = true
            Logger.auth.error("Auth: Refresh token permanently expired for \(account.characterName) — manual reauth required")
            persist(account)
            throw SSOError.refreshTokenExpired
        } catch {
            refreshTasks.removeValue(forKey: charID)
            throw error
        }
    }

    /// Called when ESI rejects a locally-valid token with 401 (e.g. server-side revocation).
    /// Attempts an immediate forced refresh; if that also fails, marks the account for reauth
    /// so the ReauthBanner surfaces to the user.
    func handleUnauthorized(for account: StoredAccount) async {
        Logger.auth.warning("Auth: ESI 401 for \(account.characterName) — attempting forced refresh")
        do {
            let tokenResponse = try await authenticator.refreshToken(account.refreshToken)
            account.accessToken = tokenResponse.accessToken
            account.refreshToken = tokenResponse.refreshToken
            account.tokenExpiry = Date().addingTimeInterval(TimeInterval(tokenResponse.expiresIn))
            account.needsReauth = false
            tokenVersion += 1
            persist(account)
            Logger.auth.info("Auth: Forced refresh succeeded for \(account.characterName) after ESI 401")
        } catch {
            account.needsReauth = true
            persist(account)
            Logger.auth.error("Auth: Could not recover from ESI 401 for \(account.characterName) — reauth required")
        }
    }

    /// Scopes the app currently requests that this account's last-granted token is missing.
    /// Surfaces when CCP's SSO didn't include a newly-added scope on a routine re-authentication.
    func missingScopes(for account: StoredAccount) -> [String] {
        SSOConfiguration.default.scopes.filter { !account.scopes.contains($0) }
    }

    /// Re-runs the full SSO browser flow for an account whose refresh token has expired.
    /// On success clears needsReauth and updates all tokens. On wrong character, sets error.
    func reauthorize(_ account: StoredAccount, forceFreshSession: Bool = false) async {
        isLoading = true
        error = nil
        do {
            let tokenResponse = try await authenticator.authenticate(forceFreshSession: forceFreshSession)
            let character = try decodeSSOJWT(tokenResponse.accessToken)
            guard character.characterID == account.characterID else {
                Logger.auth.warning("Auth: Reauth failed — wrong character (expected \(account.characterName))")
                self.error = "Wrong character. Please log in as \(account.characterName)."
                isLoading = false
                return
            }
            account.accessToken = tokenResponse.accessToken
            account.refreshToken = tokenResponse.refreshToken
            account.tokenExpiry = Date().addingTimeInterval(TimeInterval(tokenResponse.expiresIn))
            account.scopes = character.scopes
            account.needsReauth = false
            persist(account)
            tokenVersion += 1
            Logger.auth.info("Auth: Reauthorized \(account.characterName) successfully")
        } catch {
            Logger.auth.error("Auth: Reauth error for \(account.characterName): \(error.localizedDescription)")
            self.error = error.localizedDescription
        }
        isLoading = false
    }

    /// Fetches current public ESI data for all accounts and unconditionally updates
    /// corporation and alliance fields. Clears all response caches first so no layer
    /// of HTTP or in-memory caching can serve stale data.
    func refreshPublicInfo() async {
        guard !accounts.isEmpty else { return }
        await ESIClient.shared.clearAllCaches()
        for account in accounts {
            guard let charInfo: ESICharacterPublic = try? await ESIClient.shared.fetch(
                "/characters/\(account.characterID)/", bypassCache: true
            ) else { continue }

            account.corporationID = charInfo.corporationId
            if let corpInfo: ESICorporationPublic = try? await ESIClient.shared.fetch(
                "/corporations/\(charInfo.corporationId)/", bypassCache: true
            ) {
                account.corporationName = corpInfo.name
            }

            account.allianceID = charInfo.allianceId
            if let allianceId = charInfo.allianceId {
                if let allianceInfo: ESIAlliancePublic = try? await ESIClient.shared.fetch(
                    "/alliances/\(allianceId)/", bypassCache: true
                ) {
                    account.allianceName = allianceInfo.name
                }
            } else {
                account.allianceName = nil
            }
        }

        try? modelContext.save()
        archive.mirror(modelContext)
    }

    // MARK: Backup & restore

    /// Re-inserts pilots missing from the store — from the Keychain archive and from any
    /// moved-aside stores left by earlier versions. Returns the names restored.
    @discardableResult
    func restoreMissingPilots() -> [String] {
        let restored = archive.restoreMissing(
            into: modelContext,
            legacyStoreDirectory: Self.defaultLegacyStoreDirectory
        )
        if !restored.isEmpty {
            archive.mirror(modelContext)
            loadAccounts()
            tokenVersion += 1
        } else {
            Logger.auth.info("Backup: manual restore found no missing pilots")
        }
        return restored
    }

    /// A passphrase-encrypted file holding every pilot's login. Key derivation is slow
    /// by design, so it runs off the main actor.
    func makeBackup(passphrase: String) async throws -> Data {
        let pilots = accounts.map { ArchivedPilot($0) }
        return try await Task.detached {
            try PilotBackupFile.encrypt(pilots, passphrase: passphrase)
        }.value
    }

    func importBackup(_ file: Data, passphrase: String) async throws -> PilotArchive.MergeResult {
        let pilots = try await Task.detached {
            try PilotBackupFile.decrypt(file, passphrase: passphrase)
        }.value
        let result = try archive.merge(pilots, into: modelContext)
        loadAccounts()
        tokenVersion += 1
        Logger.auth.info("Backup: imported file — added \(result.added.count), updated \(result.updated.count), \(pilots.count) in file")
        return result
    }
}
