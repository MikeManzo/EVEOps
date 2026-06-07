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

    private let modelContext: ModelContext
    private let authenticator: SSOAuthenticator
    // Tracks in-flight refresh tasks keyed by character ID to prevent duplicate
    // concurrent refreshes from consuming a single-use refresh token twice.
    private var refreshTasks: [Int: Task<SSOTokenResponse, Error>] = [:]

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
        self.authenticator = SSOAuthenticator(config: .default)
        loadAccounts()
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
            let character = try decodeJWT(tokenResponse.accessToken)

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
            loadAccounts()
        } catch {
            self.error = error.localizedDescription
        }
        isLoading = false
    }

    func removeAccount(_ account: StoredAccount) {
        Logger.auth.info("Auth: Account removed — \(account.characterName) (ID: \(account.characterID))")
        modelContext.delete(account)
        try? modelContext.save()
        loadAccounts()
        if selectedCharacterID == account.characterID {
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
            try? modelContext.save()
            return tokenResponse.accessToken
        } catch SSOError.refreshTokenExpired {
            // Refresh token is permanently invalid — user must log in again manually.
            refreshTasks.removeValue(forKey: charID)
            account.needsReauth = true
            Logger.auth.error("Auth: Refresh token permanently expired for \(account.characterName) — manual reauth required")
            try? modelContext.save()
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
            try? modelContext.save()
            Logger.auth.info("Auth: Forced refresh succeeded for \(account.characterName) after ESI 401")
        } catch {
            account.needsReauth = true
            try? modelContext.save()
            Logger.auth.error("Auth: Could not recover from ESI 401 for \(account.characterName) — reauth required")
        }
    }

    /// Re-runs the full SSO browser flow for an account whose refresh token has expired.
    /// On success clears needsReauth and updates all tokens. On wrong character, sets error.
    func reauthorize(_ account: StoredAccount) async {
        isLoading = true
        error = nil
        do {
            let tokenResponse = try await authenticator.authenticate()
            let character = try decodeJWT(tokenResponse.accessToken)
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
            try? modelContext.save()
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
    }

    private func decodeJWT(_ token: String) throws -> ESITokenCharacter {
        let parts = token.split(separator: ".")
        guard parts.count == 3 else { throw SSOError.invalidToken }

        var base64 = String(parts[1])
        while base64.count % 4 != 0 {
            base64.append("=")
        }
        base64 = base64.replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")

        guard let data = Data(base64Encoded: base64) else { throw SSOError.invalidToken }

        struct JWTPayload: Codable {
            let sub: String
            let name: String
            let scp: ScopeValue?
            let exp: Int

            enum ScopeValue: Codable {
                case single(String)
                case multiple([String])

                init(from decoder: Decoder) throws {
                    let container = try decoder.singleValueContainer()
                    if let array = try? container.decode([String].self) {
                        self = .multiple(array)
                    } else if let string = try? container.decode(String.self) {
                        self = .single(string)
                    } else {
                        self = .multiple([])
                    }
                }

                func encode(to encoder: Encoder) throws {
                    var container = encoder.singleValueContainer()
                    switch self {
                    case .single(let s): try container.encode(s)
                    case .multiple(let a): try container.encode(a)
                    }
                }

                var scopes: [String] {
                    switch self {
                    case .single(let s): return [s]
                    case .multiple(let a): return a
                    }
                }
            }
        }

        let payload = try JSONDecoder().decode(JWTPayload.self, from: data)
        let characterIDString = payload.sub.replacingOccurrences(of: "CHARACTER:EVE:", with: "")
        guard let characterID = Int(characterIDString) else { throw SSOError.invalidToken }

        return ESITokenCharacter(
            characterID: characterID,
            characterName: payload.name,
            scopes: payload.scp?.scopes ?? [],
            expiresOn: Date(timeIntervalSince1970: TimeInterval(payload.exp))
        )
    }
}
