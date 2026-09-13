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

/// Observable connection status for `DiscordRichPresence`, so Settings can show the
/// user whether the app is actually talking to Discord right now — not just whether
/// the feature is toggled on.
@MainActor
@Observable
final class DiscordRichPresenceStatus {
    static let shared = DiscordRichPresenceStatus()
    private init() {}

    enum State: Equatable {
        case off              // feature disabled (or no character selected / app quitting)
        case searching        // enabled, but no working IPC connection yet
        case connected        // actively pushing activity to Discord
    }

    private(set) var state: State = .off

    fileprivate func setState(_ newState: State) {
        state = newState
    }
}

/// Publishes the currently selected character's ship and location as a Discord
/// Rich Presence status, using the local IPC protocol Discord's desktop client
/// exposes at `$TMPDIR/discord-ipc-N` (a Unix domain socket, not a network API —
/// this only works while the Discord desktop app is running on the same Mac).
///
/// Requires a Discord Application client ID (from the Discord Developer Portal,
/// configured in Settings) — Rich Presence always identifies itself as a specific
/// registered application, there is no generic "any app" identity.
actor DiscordRichPresence {
    static let shared = DiscordRichPresence()

    private enum Opcode: Int32 {
        case handshake = 0
        case frame = 1
    }

    private var socketFD: Int32 = -1
    private var connected = false
    private var readLoopTask: Task<Void, Never>?
    private var reconnectNotBefore: Date?
    /// Cached from the most recent `update()` call so `retryWithoutImage()` — triggered
    /// when Discord rejects an unrecognized asset key — can resend the same text without
    /// needing request/response correlation on every call.
    private var lastDetails: String?
    private var lastState: String?
    /// Resumed by the read loop when Discord's `DISPATCH READY` event arrives after
    /// the handshake — see `waitForReady()`.
    private var readyContinuation: CheckedContinuation<Bool, Never>?

    private init() {}

    /// Pushes the given ship/location as the user's Discord activity. `shipGroupID`
    /// is the EVE *ship group* ID (Frigate, Cruiser, Battleship, etc. — not the exact
    /// hull) for the currently flown ship. Discord's local Rich Presence can only
    /// display images pre-uploaded as named Art Assets on the Application (max 300),
    /// which isn't enough to cover every individual EVE hull, so this keys off ship
    /// group instead — see `largeImageAssetKey(forShipGroupID:)`. Pass `nil` if the
    /// group couldn't be resolved yet; that falls back to the generic EVEOps icon
    /// rather than showing nothing. No-ops silently if Rich Presence is disabled —
    /// callers don't need to check first. Safe to call repeatedly on a timer; it
    /// reuses the existing IPC connection when possible.
    func update(details: String, state: String, shipGroupID: Int?) async {
        guard UserDefaults.standard.bool(forKey: "discordRichPresenceEnabled"),
              !Self.clientID.hasPrefix("REPLACE_")
        else {
            await disconnect(reportAs: .off)
            return
        }

        if !connected {
            guard await connect() else {
                await DiscordRichPresenceStatus.shared.setState(.searching)
                return
            }
        }

        lastDetails = details
        lastState = state
        let imageKey = shipGroupID.map(Self.largeImageAssetKey(forShipGroupID:)) ?? Self.fallbackImageAssetKey
        await sendActivity(details: details, state: state, imageKey: imageKey)
    }

    /// Resends the last activity with no `large_image` at all — used when Discord
    /// reports the previously-sent asset key doesn't exist. An invalid key doesn't
    /// just omit the image: Discord silently drops the *entire* activity update, so
    /// falling back to text-only here is what keeps presence visible at all instead
    /// of showing nothing.
    private func retryWithoutImage() async {
        guard let details = lastDetails, let state = lastState else { return }
        await Logger.richPresence.warning("[RichPresence] Unrecognized asset key — retrying without an image")
        await sendActivity(details: details, state: state, imageKey: nil)
    }

    private func sendActivity(details: String, state: String, imageKey: String?) async {
        var activity: [String: Any] = ["state": state, "details": details]
        if let imageKey {
            activity["assets"] = ["large_image": imageKey, "large_text": details]
        }
        let payload: [String: Any] = [
            "cmd": "SET_ACTIVITY",
            "nonce": UUID().uuidString,
            "args": [
                "pid": ProcessInfo.processInfo.processIdentifier,
                "activity": activity
            ]
        ]

        if sendFrame(opcode: .frame, payload: payload) {
            await Logger.richPresence.info("[RichPresence] Sent SET_ACTIVITY: \"\(details)\" / \"\(state)\" image=\(imageKey ?? "none")")
            await DiscordRichPresenceStatus.shared.setState(.connected)
        } else {
            await Logger.richPresence.warning("[RichPresence] Write failed — dropping connection")
            await disconnect(reportAs: .searching)
        }
    }

    /// Clears the activity and drops the IPC connection — call when the feature is
    /// turned off or the app is quitting.
    func disconnect() async {
        await disconnect(reportAs: .off)
    }

    /// Like `disconnect()`, but reports `.searching` instead of `.off` — for callers
    /// that know the feature is enabled but have nothing to show yet (e.g. character
    /// data hasn't been prefetched), so the status badge doesn't read as "disabled".
    func disconnectPendingData() async {
        await disconnect(reportAs: .searching)
    }

    private func disconnect(reportAs status: DiscordRichPresenceStatus.State) async {
        if socketFD >= 0 {
            if connected {
                let payload: [String: Any] = [
                    "cmd": "SET_ACTIVITY",
                    "nonce": UUID().uuidString,
                    "args": ["pid": ProcessInfo.processInfo.processIdentifier, "activity": NSNull()]
                ]
                _ = sendFrame(opcode: .frame, payload: payload)
            }

            readLoopTask?.cancel()
            readLoopTask = nil
            close(socketFD)
            socketFD = -1
            connected = false
        }
        await DiscordRichPresenceStatus.shared.setState(status)
    }

    /// Suspends until the read loop reports Discord's `DISPATCH READY` event for the
    /// handshake just sent, or 2 seconds pass — whichever comes first. Returns false
    /// on timeout, in which case the caller should treat the connection as failed.
    private func waitForReady() async -> Bool {
        await withCheckedContinuation { (continuation: CheckedContinuation<Bool, Never>) in
            self.readyContinuation = continuation
            Task {
                try? await Task.sleep(for: .seconds(2))
                self.resumeReadyContinuation(success: false)
            }
        }
    }

    private func resumeReadyContinuation(success: Bool) {
        guard let readyContinuation else { return }
        self.readyContinuation = nil
        readyContinuation.resume(returning: success)
    }

    /// EVEOps' own Discord Application ID (from the Discord Developer Portal), fixed
    /// for every install so everyone's status shows the same "EVEOps" identity/art —
    /// not something an individual user registers or configures.
    private static let clientID = "1548332432858550372" // <--- If you are cloning this app for personal use, you MUST change this!!

    /// Discord's local Rich Presence only ever displays pre-uploaded Art Assets, keyed
    /// by name, capped at 300 per application — there is no way to hand it an arbitrary
    /// URL or in-app file at runtime, and EVE has 400+ individual ship hulls (too many
    /// for 1:1 coverage). Instead, one representative render is uploaded per *ship
    /// group* (Frigate, Cruiser, Battleship, etc. — comfortably under the cap), keyed
    /// by that group's EVE group ID. See `Scripts/upload-ship-group-icons`, sourced
    /// from CCP's public image server at images.evetech.net.
    private static func largeImageAssetKey(forShipGroupID shipGroupID: Int) -> String {
        "shipgroup_\(shipGroupID)"
    }

    /// Shown when the ship's group can't be resolved yet (e.g. name resolution still
    /// in flight) — the generic EVEOps icon, uploaded once under this fixed key.
    private static let fallbackImageAssetKey = "eveops_icon"

    // MARK: Connection

    private func connect() async -> Bool {
        if let reconnectNotBefore, Date() < reconnectNotBefore { return false }

        let tmpDir = ProcessInfo.processInfo.environment["TMPDIR"] ?? NSTemporaryDirectory()
        let base = tmpDir.hasSuffix("/") ? String(tmpDir.dropLast()) : tmpDir

        for i in 0..<10 {
            let path = "\(base)/discord-ipc-\(i)"
            guard FileManager.default.fileExists(atPath: path) else { continue }

            let fd = socket(AF_UNIX, SOCK_STREAM, 0)
            guard fd >= 0 else { continue }

            // Without this, writing to the socket after Discord closes its end (e.g.
            // it quits or restarts while we're connected) raises SIGPIPE — which by
            // default terminates the whole process, not just this actor. This is a
            // raw BSD socket we opened ourselves, so nothing else sets this for us.
            var noSigPipe: Int32 = 1
            setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &noSigPipe, socklen_t(MemoryLayout<Int32>.size))

            guard Self.connectSocket(fd, to: path) else {
                close(fd)
                continue
            }

            socketFD = fd
            guard sendFrame(opcode: .handshake, payload: ["v": 1, "client_id": Self.clientID]) else {
                close(fd)
                socketFD = -1
                continue
            }

            startReadLoop(fd: fd)

            // Discord's RPC protocol expects the handshake to be acknowledged with a
            // DISPATCH READY event before anything else is sent — sending SET_ACTIVITY
            // ahead of that isn't an error, Discord just silently ignores it, which is
            // exactly the "connected, sent, nothing shows" symptom this was causing.
            guard await waitForReady() else {
                await Logger.richPresence.warning("[RichPresence] Handshake timed out waiting for READY via \(path)")
                readLoopTask?.cancel()
                readLoopTask = nil
                close(fd)
                socketFD = -1
                continue
            }

            connected = true
            reconnectNotBefore = nil
            await Logger.richPresence.info("[RichPresence] Connected via \(path)")
            return true
        }

        // None of the candidate sockets worked — Discord probably isn't running.
        // Back off before trying again on the next update() call.
        reconnectNotBefore = Date().addingTimeInterval(30)
        return false
    }

    private static func connectSocket(_ fd: Int32, to path: String) -> Bool {
        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        addr.sun_len = UInt8(MemoryLayout<sockaddr_un>.size)

        let pathBytes = Array(path.utf8)
        guard pathBytes.count < MemoryLayout.size(ofValue: addr.sun_path) else { return false }

        withUnsafeMutableBytes(of: &addr.sun_path) { rawPtr in
            let buf = rawPtr.bindMemory(to: Int8.self)
            for (index, byte) in pathBytes.enumerated() {
                buf[index] = Int8(bitPattern: byte)
            }
            buf[pathBytes.count] = 0
        }

        let result = withUnsafePointer(to: &addr) { ptr -> Int32 in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockaddrPtr in
                Foundation.connect(fd, sockaddrPtr, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        return result == 0
    }

    // MARK: Framing
    // Discord's local RPC protocol: each message is an 8-byte little-endian header
    // (Int32 opcode, UInt32 payload length) followed by UTF-8 JSON.

    @discardableResult
    private func sendFrame(opcode: Opcode, payload: [String: Any]) -> Bool {
        guard socketFD >= 0,
              let json = try? JSONSerialization.data(withJSONObject: payload) else { return false }

        var frame = Data(capacity: 8 + json.count)
        let op = UInt32(bitPattern: opcode.rawValue).littleEndian
        let length = UInt32(json.count).littleEndian
        withUnsafeBytes(of: op) { frame.append(contentsOf: $0) }
        withUnsafeBytes(of: length) { frame.append(contentsOf: $0) }
        frame.append(json)

        let written = frame.withUnsafeBytes { ptr -> Int in
            write(socketFD, ptr.baseAddress, frame.count)
        }
        return written == frame.count
    }

    private func startReadLoop(fd: Int32) {
        readLoopTask = Task.detached {
            while !Task.isCancelled {
                var header = [UInt8](repeating: 0, count: 8)
                let headerRead = header.withUnsafeMutableBytes { ptr in
                    read(fd, ptr.baseAddress, 8)
                }
                guard headerRead == 8 else { break }

                let length = Int(UInt32(header[4]) | UInt32(header[5]) << 8
                                  | UInt32(header[6]) << 16 | UInt32(header[7]) << 24)
                var payload: [UInt8] = []
                if length > 0 {
                    var remaining = length
                    var buffer = [UInt8](repeating: 0, count: length)
                    var offset = 0
                    while remaining > 0 {
                        let n = buffer.withUnsafeMutableBytes { ptr -> Int in
                            read(fd, ptr.baseAddress!.advanced(by: offset), remaining)
                        }
                        guard n > 0 else { break }
                        offset += n
                        remaining -= n
                    }
                    guard remaining == 0 else { break }
                    payload = buffer
                }

                // Most of Discord's replies (plain ACKs) are just drained and
                // discarded — Rich Presence here is fire-and-forget. Two replies are
                // worth reacting to: the READY dispatch that acknowledges the
                // handshake (nothing else may be sent before this arrives), and a
                // SET_ACTIVITY error (e.g. an unrecognized asset key) — Discord
                // doesn't just drop the image in that case, it silently discards the
                // whole activity update.
                if let json = try? JSONSerialization.jsonObject(with: Data(payload)) as? [String: Any] {
                    if json["cmd"] as? String == "DISPATCH", json["evt"] as? String == "READY" {
                        await DiscordRichPresence.shared.resumeReadyContinuation(success: true)
                    } else if json["cmd"] as? String == "SET_ACTIVITY", json["evt"] as? String == "ERROR" {
                        let errorData = json["data"] as? [String: Any]
                        await Logger.richPresence.warning("[RichPresence] SET_ACTIVITY rejected: \(errorData?["message"] as? String ?? "unknown error") (code \(errorData?["code"].map { "\($0)" } ?? "?"))")
                        await DiscordRichPresence.shared.retryWithoutImage()
                    }
                }
            }
            await DiscordRichPresence.shared.handleDisconnect(fd: fd)
        }
    }

    private func handleDisconnect(fd: Int32) async {
        guard socketFD == fd else { return }  // already reconnected/disconnected since
        close(socketFD)
        socketFD = -1
        connected = false
        await DiscordRichPresenceStatus.shared.setState(.searching)
    }
}

extension DiscordRichPresence {
    /// Pushes the given account's current ship/system from already-prefetched
    /// dashboard data. Shared by `BackgroundMonitor`'s poll cycle and by Settings
    /// (to connect immediately when the user flips the toggle on, rather than
    /// waiting for the next poll).
    @MainActor
    static func refresh(accountManager: AccountManager, prefetcher: DashboardPrefetcher) async {
        guard UserDefaults.standard.bool(forKey: "discordRichPresenceEnabled") else {
            await DiscordRichPresence.shared.disconnect()
            return
        }
        guard let account = accountManager.selectedAccount else {
            // No character selected at all — genuinely nothing to show.
            await DiscordRichPresence.shared.disconnectPendingData()
            return
        }
        guard let data = prefetcher.data(for: account.characterID) else {
            // A character IS selected — this cycle just doesn't have fresh data for
            // it yet (its own prefetch can be skipped/delayed by a token refresh
            // without affecting other accounts). Leave whatever's already connected
            // and showing alone rather than tearing down a working connection and
            // forcing a full reconnect every time this happens — that churn was
            // exactly what kept Rich Presence from ever settling.
            return
        }

        let shipType = prefetcher.resolvedTypes[data.ship.shipTypeId]
        let shipName = shipType?.name ?? "Unknown Ship"
        let systemName = prefetcher.resolvedSystems[data.location.solarSystemId]?.name ?? "Unknown System"
        await DiscordRichPresence.shared.update(
            details: "Flying a \(shipName)",
            state: "\(systemName) — \(account.characterName)",
            shipGroupID: shipType?.groupId
        )
    }
}
