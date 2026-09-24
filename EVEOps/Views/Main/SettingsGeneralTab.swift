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
import ServiceManagement
import Sparkle

// MARK:  General Tab

struct GeneralTab: View {
    @Environment(AccountManager.self) private var accountManager
    @Environment(DashboardPrefetcher.self) private var prefetcher
    @Environment(AppUpdater.self) private var appUpdater
    @AppStorage("backgroundPollInterval") private var pollInterval: Double = 300
    @AppStorage("defaultCharacterMode") private var defaultCharacterMode: String = "last"
    @AppStorage("showDockIcon") private var showDockIcon: Bool = false
    @AppStorage(DockTileController.badgeKey) private var dockBadge = true
    @AppStorage(DockTileController.progressKey) private var dockProgress = false
    @State private var launchAtLogin = false
    @State private var isRefreshing = false

    private func refreshDockTile() {
        DockTileController.update(
            summaries: Array(prefetcher.menuBarSummaries.values),
            selectedCharacterID: accountManager.selectedCharacterID
        )
    }

    var body: some View {
        Form {
            Section("Startup") {
                Toggle("Launch at login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, newValue in
                        if newValue {
                            try? SMAppService.mainApp.register()
                        } else {
                            try? SMAppService.mainApp.unregister()
                        }
                    }
                Toggle("Show Dock Icon", isOn: $showDockIcon)
                    .onChange(of: showDockIcon) { _, newValue in
                        NSApp.setActivationPolicy(newValue ? .regular : .accessory)
                    }
                Text("Allows switching to EVEOps via Cmd-Tab and the Dock. Takes effect immediately.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if showDockIcon {
                    Toggle(isOn: $dockBadge) {
                        Text("Badge Dock icon when something needs attention")
                        Text("Counts idle skill queues and offline planetary extractors.")
                    }
                    Toggle(isOn: $dockProgress) {
                        Text("Show skill training progress on Dock icon")
                        Text("A ring around the icon tracks the current skill of the selected character.")
                    }
                }
            }
            .onChange(of: dockBadge) { _, _ in refreshDockTile() }
            .onChange(of: dockProgress) { _, _ in refreshDockTile() }

            Section("Background Refresh") {
                Picker("Check interval", selection: $pollInterval) {
                    Text("1 minute").tag(60.0)
                    Text("2 minutes").tag(120.0)
                    Text("5 minutes").tag(300.0)
                    Text("10 minutes").tag(600.0)
                    Text("15 minutes").tag(900.0)
                    Text("30 minutes").tag(1800.0)
                }
                .pickerStyle(.menu)
                Button(isRefreshing ? "Refreshing\u{2026}" : "Refresh Now") {
                    Task {
                        isRefreshing = true
                        await accountManager.refreshPublicInfo()
                        await prefetcher.prefetchAll(accountManager: accountManager)
                        isRefreshing = false
                    }
                }
                .disabled(isRefreshing || prefetcher.isLoading)
                Text("How often EVEOps checks for notifications and updates in the background.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Default Character") {
                Picker("On launch, select", selection: $defaultCharacterMode) {
                    Text("Last active character").tag("last")
                    Text("First character alphabetically").tag("first")
                }
                .pickerStyle(.radioGroup)
            }

            Section("Software Update") {
                if !appUpdater.notificationsAuthorized {
                    HStack(spacing: 12) {
                        Image(systemName: "bell.slash.fill")
                            .font(.title3)
                            .foregroundStyle(.orange)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Notifications Disabled")
                                .font(.subheadline.weight(.semibold))
                            Text("EVEOps can't alert you when an automatic background check finds an update — only manual checks will show one.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button("Open Settings\u{2026}") {
                            if let url = URL(string: "x-apple.systempreferences:com.apple.preference.notifications") {
                                NSWorkspace.shared.open(url)
                            }
                        }
                        .buttonStyle(.link)
                    }
                    .padding(.vertical, 4)
                }

                if appUpdater.updateAvailable {
                    HStack(spacing: 12) {
                        Image(systemName: "arrow.down.circle.fill")
                            .font(.title3)
                            .foregroundStyle(.green)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Update Available")
                                .font(.subheadline.weight(.semibold))
                            Text("A new version of EVEOps is ready to install.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button("Install Update") {
                            appUpdater.checkForUpdates()
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.green)
                    }
                    .padding(.vertical, 4)
                }

                Button {
                    appUpdater.checkForUpdates()
                } label: {
                    Label("Check for Updates\u{2026}", systemImage: "arrow.triangle.2.circlepath")
                }
                .disabled(!appUpdater.canCheckForUpdates)

                Toggle(isOn: Binding(
                    get: { appUpdater.updater.automaticallyChecksForUpdates },
                    set: { appUpdater.updater.automaticallyChecksForUpdates = $0 }
                )) {
                    Label("Automatically check for updates", systemImage: "clock.arrow.2.circlepath")
                }

                Toggle(isOn: Binding(
                    get: { appUpdater.updater.automaticallyDownloadsUpdates },
                    set: { appUpdater.updater.automaticallyDownloadsUpdates = $0 }
                )) {
                    Label("Automatically download updates", systemImage: "arrow.down.circle")
                }
            }
        }
        .formStyle(.grouped)
        .onAppear {
            launchAtLogin = SMAppService.mainApp.status == .enabled
        }
    }
}

// MARK:  Appearance Tab

struct AppearanceTab: View {
    @Environment(ThemeManager.self) private var themeManager
    @AppStorage("colorScheme") private var colorSchemePref: String = "system"
    @AppStorage("appearance.ambientBackground") private var ambientBackground = false

    @AppStorage("sidebar.showPinned") private var showPinned = true
    @AppStorage("sidebar.showPilot") private var showPilot = true
    @AppStorage("sidebar.showEconomy") private var showEconomy = true
    @AppStorage("sidebar.showCombat") private var showCombat = true
    @AppStorage("sidebar.showSocial") private var showSocial = true
    @AppStorage("sidebar.showUniverse") private var showUniverse = true
    @AppStorage("sidebar.showCorp") private var showCorp = true
    @AppStorage("sidebar.showUtility") private var showUtility = true

    var body: some View {
        Form {
            Section("Theme") {
                Picker("Appearance", selection: $colorSchemePref) {
                    Text("System Default").tag("system")
                    Text("Light").tag("light")
                    Text("Dark").tag("dark")
                }
                .pickerStyle(.radioGroup)
                Toggle(isOn: $ambientBackground) {
                    Text("Ambient space background")
                    Text("A faint faction-tinted glow behind the main window, with a starfield in Dark appearance and a star-chart grid in Light.")
                }
            }

            Section("Faction Theme") {
                factionSwatchPicker
                Text(themeManager.faction.tagline)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("View / Hide Sidebar Sections") {
                Toggle("Pinned", isOn: $showPinned)
                Toggle("Pilot", isOn: $showPilot)
                Toggle("Economy", isOn: $showEconomy)
                Toggle("Combat & Fleet", isOn: $showCombat)
                Toggle("Social & Comms", isOn: $showSocial)
                Toggle("Universe", isOn: $showUniverse)
                Toggle("Corporation", isOn: $showCorp)
                Toggle("Utility", isOn: $showUtility)
            }
        }
        .formStyle(.grouped)
    }

    private var factionSwatchPicker: some View {
        HStack(spacing: 16) {
            ForEach(FactionTheme.allCases) { faction in
                let isSelected = themeManager.faction == faction
                Button {
                    themeManager.faction = faction
                } label: {
                    VStack(spacing: 6) {
                        FactionCrestSwatch(faction: faction, size: Self.crestSwatchSize)
                            .overlay(Circle().strokeBorder(faction.palette.accent, lineWidth: 2))
                            .overlay {
                                if isSelected {
                                    Circle()
                                        .fill(.black.opacity(0.35))
                                    Image(systemName: "checkmark")
                                        .font(.caption.bold())
                                        .foregroundStyle(.white)
                                }
                            }
                            .overlay {
                                if isSelected {
                                    Circle().strokeBorder(faction.palette.accent, lineWidth: 2)
                                        .padding(-3)
                                }
                            }
                        Text(faction.displayName)
                            .font(.caption2)
                            .foregroundStyle(isSelected ? .primary : .secondary)
                    }
                }
                .buttonStyle(.plain)
                .help(faction.tagline)
            }
            Spacer()
        }
        .padding(.vertical, 2)
    }

    private static let crestSwatchSize: CGFloat = 30 * 1.25

}

// MARK:  Faction Crest Swatch

/// The faction's own crest (from CCP's image server) clipped into the swatch circle,
/// with the theme accent as a ring around it — reads like a coin/medallion rather than
/// a flat color dot. EVEOps' own default isn't one of the four empires, so it falls
/// back to a plain accent-filled circle.
///
/// The served crest image bakes in a wordmark below the icon (e.g. a "CALDARI" label),
/// so this deliberately over-scales and shifts it to keep only the icon in frame — the
/// scale/offset were derived from a pixel row-density scan of all four crests (where the
/// icon glyph sits vs. where the text starts), not eyeballed, since the icon's exact
/// position varies a little faction to faction.
struct FactionCrestSwatch: View {
    let faction: FactionTheme
    let size: CGFloat

    var body: some View {
        if let factionID = faction.factionID {
            CachedAsyncImage(url: EVEImageURL.factionCrest(factionID, size: 128)) { image in
                image
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: size * 1.65, height: size * 1.65)
                    .offset(y: size * 0.2)
                    .frame(width: size, height: size)
                    .clipped()
            } placeholder: {
                Circle().fill(faction.palette.accent)
            }
            .frame(width: size, height: size)
            .clipShape(Circle())
        } else {
            Circle().fill(faction.palette.accent)
                .frame(width: size, height: size)
        }
    }
}
