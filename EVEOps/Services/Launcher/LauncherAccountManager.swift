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

/// Orchestrates the separate `eveLauncherTQ` OAuth session used to verify/launch the game
/// client — mirrors `AccountManager`'s token lifecycle (refresh-with-dedup, reauth-on-expiry)
/// without any of its ESI character/corp/alliance fetch logic, since this account type only
/// exists to authorize game-client actions, not to read ESI data.
@MainActor
@Observable
final class LauncherAccountManager {
    var accounts: [LauncherAccount] = []
    var isLoading = false
    var error: String?

    private let modelContext: ModelContext
    private let authenticator: SSOAuthenticator
    private var refreshTasks: [Int: Task<SSOTokenResponse, Error>] = [:]

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
        self.authenticator = SSOAuthenticator(config: .launcher, presenter: EmbeddedWebAuthPresenter())
        loadAccounts()
    }

    func loadAccounts() {
        let descriptor = FetchDescriptor<LauncherAccount>(sortBy: [SortDescriptor(\.characterName)])
        accounts = (try? modelContext.fetch(descriptor)) ?? []
    }

    /// Runs the full launcher SSO flow and persists (or updates) the resulting account.
    @discardableResult
    func login() async throws -> LauncherAccount {
        isLoading = true
        error = nil
        defer { isLoading = false }

        let tokenResponse = try await authenticator.authenticate()
        let character = try decodeSSOJWT(tokenResponse.accessToken)

        if let existing = accounts.first(where: { $0.characterID == character.characterID }) {
            existing.accessToken = tokenResponse.accessToken
            existing.refreshToken = tokenResponse.refreshToken
            existing.tokenExpiry = Date().addingTimeInterval(TimeInterval(tokenResponse.expiresIn))
            existing.scopes = character.scopes
            existing.needsReauth = false
            try? modelContext.save()
            Logger.auth.info("Launcher auth: token updated for \(existing.characterName)")
            return existing
        }

        let account = LauncherAccount(
            characterID: character.characterID,
            characterName: character.characterName,
            accessToken: tokenResponse.accessToken,
            refreshToken: tokenResponse.refreshToken,
            tokenExpiry: Date().addingTimeInterval(TimeInterval(tokenResponse.expiresIn)),
            scopes: character.scopes
        )
        modelContext.insert(account)
        try modelContext.save()
        loadAccounts()
        Logger.auth.info("Launcher auth: account added — \(account.characterName)")
        return account
    }

    func logout(_ account: LauncherAccount) {
        modelContext.delete(account)
        try? modelContext.save()
        loadAccounts()
    }

    func validToken(for account: LauncherAccount) async throws -> String {
        if !account.isTokenExpired {
            return account.accessToken
        }

        let charID = account.characterID
        if let existing = refreshTasks[charID] {
            return try await existing.value.accessToken
        }

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
            try? modelContext.save()
            return tokenResponse.accessToken
        } catch SSOError.refreshTokenExpired {
            refreshTasks.removeValue(forKey: charID)
            account.needsReauth = true
            try? modelContext.save()
            throw SSOError.refreshTokenExpired
        } catch {
            refreshTasks.removeValue(forKey: charID)
            throw error
        }
    }
}
