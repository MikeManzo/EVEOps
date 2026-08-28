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

enum EVELaunchError: LocalizedError {
    case noLocalInstall

    var errorDescription: String? {
        switch self {
        case .noLocalInstall:
            return "Grant EVE Online access in Settings → Cache & Data → EVE Installation first."
        }
    }
}

/// Orchestrates the "Launch EVE" flow: log in via the separate launcher OAuth session, show
/// whether the local install is behind CCP's current manifest, then open the real EVE Online
/// launcher to actually update and play. See /Users/mike/.claude/plans/binary-inventing-shamir.md.
///
/// Deliberately does NOT download or write game files itself. An earlier version did (staging,
/// checksum-verifying, and committing missing files directly into the real SharedCache) and it
/// worked in testing, but a later real-world update through EVEOps was followed by the EVE
/// client reporting "Verification Failure" and recommending a reinstall. The specific file it
/// couldn't verify (`bin:/manifest.dat`) doesn't appear in any manifest this app reads — not the
/// remote resfileindex.txt, not the remote app manifest, not either local copy — so the true
/// root cause is something in the client's own native verification logic that EVEOps has no
/// legitimate way to inspect (doing so would mean reverse-engineering the client, which the EVE
/// EULA explicitly prohibits). Given the player already has to open the real launcher to log in
/// at all (direct client login is disabled server-side — see `GameLauncher`), and the real
/// launcher performs its own correct update pass before it allows Play, EVEOps writing into the
/// live install was redundant risk with no corresponding benefit. Now it only detects and
/// reports what's out of date; the real launcher does the actual patching.
@MainActor
@Observable
final class EVELaunchManager {
    enum State: Equatable {
        case notLoggedIn
        case loggingIn
        case idle
        case checkingForUpdates
        case updateAvailable(ManifestDiffer.DiffSummary)
        case upToDate
        case launching
        case launched
        case error(String)
    }

    var state: State = .notLoggedIn
    private(set) var account: LauncherAccount?

    private let accountManager: LauncherAccountManager
    private let manifestClient: EVEManifestFetching

    init(
        accountManager: LauncherAccountManager,
        manifestClient: EVEManifestFetching = EVEManifestClient.shared
    ) {
        self.accountManager = accountManager
        self.manifestClient = manifestClient
        self.account = accountManager.accounts.first
        if account != nil { state = .idle }
    }

    func login() async {
        state = .loggingIn
        do {
            let account = try await accountManager.login()
            self.account = account
            state = .idle
        } catch {
            state = .error(error.localizedDescription)
        }
    }

    func logout() {
        guard let account else { return }
        accountManager.logout(account)
        self.account = nil
        state = .notLoggedIn
    }

    /// Read-only: fetches the current remote manifest and diffs it against what's actually on
    /// disk. Never writes anything, and never will — see this type's doc comment.
    ///
    /// Only `resfileindex.txt` (game content — ships, sounds, scripts, static data, etc.) is
    /// diffed. `eveonline_{build}.txt` (the app-bundle-level manifest) is used solely to locate
    /// resfileindex.txt's hash, never compared directly: confirmed live that it mixes in
    /// Windows-only paths (`app:/bin64/*.dll`) alongside — or instead of — macOS ones
    /// (`app:/EVE.app/Contents/...`), so it isn't a valid 1:1 comparison against our
    /// macOS-specific local `index_tranquility.txt`. `resfileindex.txt`'s content, by contrast,
    /// is genuinely platform-shared and diffed correctly against the real install.
    func checkForUpdates() async {
        state = .checkingForUpdates
        do {
            let build = try await manifestClient.fetchCurrentBuild()
            let remoteAppManifest = try await manifestClient.fetchAppManifest(build: build)
            guard let hashPath = EVEManifestClient.resFileIndexHashPath(in: remoteAppManifest) else {
                state = .error("Could not locate resfileindex.txt in the remote manifest.")
                return
            }
            let remoteEntries = try await manifestClient.fetchResFileIndex(hashPath: hashPath)

            let localEntries = try loadLocalEntries()
            let localIndex = ManifestDiffer.indexByVirtualPath(localEntries)
            let summary = ManifestDiffer.diff(localEntries: localIndex, remoteEntries: remoteEntries)

            state = summary.filesToDownload.isEmpty ? .upToDate : .updateAvailable(summary)
        } catch {
            state = .error(error.localizedDescription)
        }
    }

    /// Reads the game-content index already on disk under the user's bookmarked SharedCache.
    private func loadLocalEntries() throws -> [ResourceManifestEntry] {
        guard let resIndexURL = EVEInstallLocator.shared.localResIndexURL(),
              let resText = try? String(contentsOf: resIndexURL, encoding: .utf8) else {
            throw EVELaunchError.noLocalInstall
        }
        return ResourceManifestEntry.parseIndex(resText)
    }

    /// Returns from `.updateAvailable`/`.upToDate`/`.error` back to the idle screen without
    /// taking any action.
    func dismiss() {
        state = .idle
    }

    /// Opens the real EVE Online launcher — not the game client, and EVEOps never writes into
    /// the install itself. Whether the local install is up to date or behind, the action is the
    /// same: the real launcher patches correctly (if needed) and handles login, since CCP
    /// requires all logins to go through it. See this type's and `GameLauncher`'s doc comments.
    func launch() async {
        switch state {
        case .upToDate, .updateAvailable:
            state = .launching
            do {
                try await GameLauncher.launchOfficialLauncher()
                state = .launched
            } catch {
                state = .error(error.localizedDescription)
            }
        default:
            break
        }
    }
}
