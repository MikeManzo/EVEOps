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
import AppKit
import OSLog

enum GameLaunchError: LocalizedError {
    case appNotFound
    case launchFailed(String)

    var errorDescription: String? {
        switch self {
        case .appNotFound:
            return "Could not find the EVE Online launcher — make sure it's installed."
        case .launchFailed(let reason):
            return "Failed to open the EVE Online launcher: \(reason)"
        }
    }
}

/// Opens CCP's own EVE Online launcher app — not the game client directly.
///
/// Two things were investigated and disproven live before landing here, both worth keeping on
/// record so they aren't retried:
///
/// 1. **Auto-login handoff.** Captured the real launcher's own spawn of `EVE.app` via `ps -ww`
///    and found it passes the session as plain command-line arguments — no local socket or IPC —
///    including `/ssoToken=<JWT>` (structurally identical to what `LauncherAccountManager
///    .validToken(for:)` already produces) and `/machineHash=<deviceID, dashes stripped>`. But
///    passing that reproducible subset (omitting only the opaque, almost-certainly-encrypted
///    `/refreshToken=`/`/LauncherData=`/`/journeyID=` fields, which would require
///    reverse-engineering the real launcher's private encryption scheme to reproduce) was tested
///    live three times and the client sat at its own login screen every time — confirmed via
///    EVE's own `cache/closed<pid>_*.session` files (`login`/user_id `0` for every attempt vs.
///    `charsel`/the real character ID for a manual login through the real launcher).
/// 2. **Direct client login.** Launching `EVE.app` itself (no launcher involved at all) does show
///    a plain username/password form — but CCP has explicitly disabled it server-side: "Login
///    through the EVE Online Client front end is disabled. Please use the EVE Launcher to log in
///    at all times." This isn't a missing feature to work around; it's a stated restriction, so
///    there's no legitimate path into the game that doesn't go through the real launcher.
///
/// Given that, the only thing EVEOps can honestly do is open the real launcher for the player,
/// the same as double-clicking it themselves — no UI automation, no reconstructed session, no
/// stored credentials. The player logs in and clicks Play there.
enum GameLauncher {
    private static let log = Logger(subsystem: "CitizenCoder.EVEOps", category: "GameLauncher")
    private static let officialLauncherBundleID = "com.ccpgames.eve-online-launcher"

    static func launchOfficialLauncher() async throws {
        guard let launcherURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: officialLauncherBundleID) else {
            throw GameLaunchError.appNotFound
        }
        do {
            _ = try await NSWorkspace.shared.openApplication(at: launcherURL, configuration: NSWorkspace.OpenConfiguration())
            log.info("Opened the official EVE Online launcher")
        } catch {
            log.error("Failed to open the official EVE Online launcher: \(error.localizedDescription, privacy: .public)")
            throw GameLaunchError.launchFailed(error.localizedDescription)
        }
    }
}
