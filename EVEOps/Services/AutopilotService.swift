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

/// Outcome of an autopilot waypoint request, so each caller can phrase its own
/// user-facing message while sharing the ESI plumbing and error classification.
enum AutopilotResult: Sendable {
    case ok
    case notSignedIn
    /// The character is missing `esi-ui.write_waypoint.v1`.
    case missingScope
    case failed(String)
}

/// Single entry point for the in-game autopilot (`POST /ui/autopilot/waypoint/`).
///
/// Previously this call was hand-rolled in the Route Planner, both Galaxy Map
/// views, and the Incursions list. Centralising it keeps the query-parameter
/// contract and the "needs the write-waypoint scope" detection in one place.
@MainActor
enum AutopilotService {
    /// Clears any existing waypoints and sets `systemId` as the sole destination.
    static func setDestination(systemId: Int, accountManager: AccountManager) async -> AutopilotResult {
        await post(systemId: systemId, clearOthers: true, addToBeginning: false, accountManager: accountManager)
    }

    /// Appends `systemId` to the current route without clearing existing waypoints.
    static func addWaypoint(
        systemId: Int,
        addToBeginning: Bool = false,
        accountManager: AccountManager
    ) async -> AutopilotResult {
        await post(systemId: systemId, clearOthers: false, addToBeginning: addToBeginning, accountManager: accountManager)
    }

    // MARK:  Implementation

    private static func post(
        systemId: Int,
        clearOthers: Bool,
        addToBeginning: Bool,
        accountManager: AccountManager
    ) async -> AutopilotResult {
        guard let account = accountManager.selectedAccount else { return .notSignedIn }
        do {
            let token = try await accountManager.validToken(for: account)
            try await ESIClient.shared.postAction(
                "/ui/autopilot/waypoint/",
                token: token,
                queryItems: [
                    URLQueryItem(name: "add_to_beginning", value: addToBeginning ? "true" : "false"),
                    URLQueryItem(name: "clear_other_waypoints", value: clearOthers ? "true" : "false"),
                    URLQueryItem(name: "destination_id", value: "\(systemId)")
                ]
            )
            return .ok
        } catch ESIError.unauthorized, ESIError.forbidden {
            return .missingScope
        } catch ESIError.serverError(let code, _) where code == 401 || code == 403 {
            return .missingScope
        } catch {
            return .failed(error.localizedDescription)
        }
    }
}
