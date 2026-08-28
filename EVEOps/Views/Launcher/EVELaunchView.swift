//
// This file is part of EVEOps.
//
// EVEOps is free software: you can redistribute it and/or modify
// it under the terms of the GNU General Public License as published by
// the Free Software Foundation, version 3 or later.
//
// Copyright (c) 2026 CitizenCoder
//

import SwiftUI

/// The "Launch EVE" section embedded in Settings → Cache & Data. Used to live in its own
/// standalone window opened from the sidebar; moved into Settings since it's a settings-adjacent,
/// occasional-use feature (login + update-check status), not something that needs its own
/// always-available window.
struct EVELaunchView: View {
    @Environment(EVELaunchManager.self) private var manager

    var body: some View {
        Section("Launch EVE") {
            switch manager.state {
            case .notLoggedIn:
                Text("Log in with your EVE Online account to check your install for updates.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Button("Log In with EVE Online") {
                    Task { await manager.login() }
                }

            case .loggingIn:
                HStack {
                    ProgressView().controlSize(.small)
                    Text("Waiting for login…")
                }
                .foregroundStyle(.secondary)

            case .idle:
                if let account = manager.account {
                    LabeledContent("Account", value: account.characterName)
                }
                Button("Check for Updates") {
                    Task { await manager.checkForUpdates() }
                }
                Button("Log Out") { manager.logout() }
                    .foregroundStyle(.secondary)

            case .checkingForUpdates:
                HStack {
                    ProgressView().controlSize(.small)
                    Text("Checking for updates…")
                }
                .foregroundStyle(.secondary)

            case .updateAvailable(let summary):
                LabeledContent("Update available") {
                    Text("\(summary.filesToDownload.count) files, \(ByteCountFormatter.string(fromByteCount: Int64(summary.totalDownloadBytes), countStyle: .file))")
                }
                Button("Open EVE Launcher to Update") { Task { await manager.launch() } }
                Text("EVEOps only checks for updates — the real launcher does the actual patching.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Button("Not Now") { manager.dismiss() }
                    .foregroundStyle(.secondary)

            case .upToDate:
                Label("Up to date", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                Button("Open EVE Launcher") { Task { await manager.launch() } }
                Text("CCP requires logging in through their own launcher — this just opens it for you.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

            case .launching:
                HStack {
                    ProgressView().controlSize(.small)
                    Text("Opening EVE Launcher…")
                }
                .foregroundStyle(.secondary)

            case .launched:
                Label("EVE Launcher Opened", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                Text("Log in and click Play there.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

            case .error(let message):
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.red)
                if manager.account != nil {
                    Button("Try Again") { Task { await manager.checkForUpdates() } }
                } else {
                    Button("Log In with EVE Online") { Task { await manager.login() } }
                }
            }
        }
    }
}
