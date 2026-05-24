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
import FoundationModels

struct SettingsView: View {
    var body: some View {
        TabView {
            AccountsTab()
                .tabItem { Label("Accounts", systemImage: "person.2") }
            GeneralTab()
                .tabItem { Label("General", systemImage: "gearshape") }
            AppearanceTab()
                .tabItem { Label("Appearance", systemImage: "paintbrush") }
            NotificationsTab()
                .tabItem { Label("Notifications", systemImage: "bell") }
            CacheTab()
                .tabItem { Label("Cache & Data", systemImage: "internaldrive") }
            AdvancedTab()
                .tabItem { Label("Advanced", systemImage: "terminal") }
            IntelligenceTab()
                .tabItem { Label("Intelligence", systemImage: "brain") }
            AboutTab()
                .tabItem { Label("About", systemImage: "info.circle") }
        }
        .frame(width: 580, height: 460)
    }
}

// MARK:  Accounts Tab

private struct AccountsTab: View {
    @Environment(AccountManager.self) private var accountManager
    @Environment(DashboardPrefetcher.self) private var prefetcher

    var body: some View {
        VStack(spacing: 0) {
            if accountManager.accounts.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "person.crop.circle.badge.plus")
                        .font(.system(size: 48))
                        .foregroundStyle(.secondary)
                    Text("No Characters Added")
                        .font(.headline)
                    Text("Add your EVE Online characters to get started.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                    Button("Add Character") {
                        Task { await accountManager.addAccount() }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(accountManager.isLoading)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding()
            } else {
                if let selected = accountManager.selectedAccount {
                    CharacterDossierCard(
                        account: selected,
                        summary: prefetcher.menuBarSummaries[selected.characterID],
                        onDelete: { accountManager.removeAccount(selected) }
                    )
                }
                let others = accountManager.accounts.filter {
                    $0.characterID != accountManager.selectedCharacterID
                }
                if !others.isEmpty {
                    List(others, id: \.characterID) { account in
                        AccountRowView(account: account)
                    }
                    .listStyle(.inset)
                } else {
                    Spacer()
                }
            }

            Divider()

            HStack {
                Button {
                    Task { await accountManager.addAccount() }
                } label: {
                    Label("Add Character", systemImage: "plus")
                }
                .disabled(accountManager.isLoading)

                if accountManager.isLoading {
                    ProgressView()
                        .controlSize(.small)
                        .padding(.leading, 4)
                }

                Spacer()

                if let error = accountManager.error {
                    Text(error)
                        .foregroundStyle(.red)
                        .font(.caption)
                        .lineLimit(1)
                }
            }
            .padding(8)
        }
    }
}

private struct AccountRowView: View {
    @Environment(AccountManager.self) private var accountManager
    let account: StoredAccount
    @State private var showDeleteConfirm = false

    var body: some View {
        HStack(spacing: 12) {
            AsyncImage(url: EVEImageURL.characterPortrait(account.characterID, size: 128)) { image in
                image.resizable()
            } placeholder: {
                RoundedRectangle(cornerRadius: 6).fill(.quaternary)
            }
            .frame(width: 40, height: 40)
            .clipShape(RoundedRectangle(cornerRadius: 6))

            VStack(alignment: .leading, spacing: 2) {
                Text(account.characterName)
                    .fontWeight(.medium)
                Text(account.corporationName)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if account.needsReauth {
                Button {
                    Task { await accountManager.reauthorize(account) }
                } label: {
                    Label("Re-authenticate", systemImage: "exclamationmark.triangle.fill")
                        .font(.caption)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .tint(.orange)
                .disabled(accountManager.isLoading)
            } else {
                Label("Active", systemImage: "checkmark.circle.fill")
                    .font(.caption)
                    .foregroundStyle(.green)
            }

            Button {
                showDeleteConfirm = true
            } label: {
                Image(systemName: "trash")
                    .foregroundStyle(.red)
            }
            .buttonStyle(.plain)
            .confirmationDialog(
                "Remove \(account.characterName)?",
                isPresented: $showDeleteConfirm,
                titleVisibility: .visible
            ) {
                Button("Remove", role: .destructive) {
                    accountManager.removeAccount(account)
                }
            }
        }
        .padding(.vertical, 2)
    }
}

// MARK: Character Dossier Card

private struct CharacterDossierCard: View {
    @Environment(AccountManager.self) private var accountManager
    let account: StoredAccount
    let summary: CharacterSummary?
    let onDelete: () -> Void

    @State private var showDeleteConfirm = false

    var body: some View {
        VStack(spacing: 10) {
            // Header: portrait + identity + online badge only
            HStack(spacing: 12) {
                AsyncImage(url: EVEImageURL.characterPortrait(account.characterID, size: 128)) { image in
                    image.resizable()
                } placeholder: {
                    RoundedRectangle(cornerRadius: 10).fill(.quaternary)
                }
                .frame(width: 56, height: 56)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .shadow(color: .black.opacity(0.2), radius: 4, x: 0, y: 2)

                VStack(alignment: .leading, spacing: 2) {
                    Text(account.characterName)
                        .font(.system(size: 14, weight: .bold))
                        .lineLimit(1)
                    Text(summary?.corporationName.isEmpty == false ? summary!.corporationName : account.corporationName)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    if let alliance = summary?.allianceName ?? account.allianceName {
                        Text(alliance)
                            .font(.system(size: 11))
                            .foregroundStyle(.tertiary)
                            .lineLimit(1)
                    }
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 5) {
                    if let online = summary?.online {
                        HStack(spacing: 4) {
                            Circle()
                                .fill(online ? Color.green : Color.secondary.opacity(0.4))
                                .frame(width: 6, height: 6)
                            Text(online ? "Online" : "Offline")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(online ? .green : .secondary)
                        }
                    }
                    if account.needsReauth {
                        Button {
                            Task { await accountManager.reauthorize(account) }
                        } label: {
                            Label("Re-authenticate", systemImage: "exclamationmark.triangle.fill")
                                .font(.system(size: 10, weight: .medium))
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.mini)
                        .tint(.orange)
                        .disabled(accountManager.isLoading)
                    } else {
                        Label("Active", systemImage: "checkmark.circle.fill")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(.green)
                    }
                }
            }

            // Stats strip — includes token status and remove action
            HStack(spacing: 0) {
                statCell(
                    icon: "banknote",
                    color: .green,
                    label: "WALLET",
                    value: summary.map { EVEFormatters.formatISKShort($0.wallet) } ?? "--"
                )
                stripDivider
                statCell(
                    icon: "chart.bar.fill",
                    color: .blue,
                    label: "SKILL PTS",
                    value: summary.map { formatSP($0.totalSP) } ?? "--"
                )
                stripDivider
                statCell(
                    icon: "graduationcap.fill",
                    color: .purple,
                    label: "IN QUEUE",
                    value: summary.map { "\($0.skillQueueCount)" } ?? "--"
                )
                stripDivider
                statCell(
                    icon: "location.fill",
                    color: securityColor(summary?.securityStatus),
                    label: "SYSTEM",
                    value: summary.map { $0.systemName.isEmpty ? "--" : $0.systemName } ?? "--"
                )
                stripDivider
                statCell(
                    icon: "diamond.fill",
                    color: .cyan,
                    label: "SHIP",
                    value: summary.map { $0.shipTypeName.isEmpty ? "--" : $0.shipTypeName } ?? "--"
                )
                stripDivider
                // Remove action cell
                Button {
                    showDeleteConfirm = true
                } label: {
                    VStack(spacing: 3) {
                        Image(systemName: "trash")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(.red)
                        Text("Remove")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(.red)
                        Text("CHARACTER")
                            .font(.system(size: 8, weight: .bold))
                            .tracking(0.5)
                            .foregroundStyle(.tertiary)
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.plain)
                .confirmationDialog(
                    "Remove \(account.characterName)?",
                    isPresented: $showDeleteConfirm,
                    titleVisibility: .visible
                ) {
                    Button("Remove", role: .destructive, action: onDelete)
                }
            }
            .padding(.vertical, 8)
            .background(.primary.opacity(0.03), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(.primary.opacity(0.06)))
        }
        .padding(14)
        .background(.background.secondary, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(.primary.opacity(0.07)))
        .fixedSize(horizontal: false, vertical: true)
        .padding(.horizontal, 8)
        .padding(.top, 8)
    }

    private func statCell(icon: String, color: Color, label: String, value: String) -> some View {
        VStack(spacing: 3) {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(color)
            Text(value)
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .lineLimit(1)
                .minimumScaleFactor(0.75)
            Text(label)
                .font(.system(size: 8, weight: .bold))
                .tracking(0.5)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity)
    }

    private var stripDivider: some View {
        Rectangle()
            .fill(.primary.opacity(0.08))
            .frame(width: 0.5)
            .padding(.vertical, 6)
    }

    private func formatSP(_ sp: Int) -> String {
        if sp >= 1_000_000 { return String(format: "%.1fM", Double(sp) / 1_000_000) }
        if sp >= 1_000 { return String(format: "%.0fK", Double(sp) / 1_000) }
        return "\(sp)"
    }

    private func securityColor(_ sec: Double?) -> Color {
        guard let sec else { return .orange }
        if sec >= 0.5 { return .green }
        if sec > 0.0 { return .yellow }
        return .red
    }
}

// MARK:  Notifications Tab

private struct NotificationsTab: View {
    @AppStorage("notificationsEnabled") private var notificationsEnabled = true
    @AppStorage("notifySkillQueueEmpty") private var notifySkillQueueEmpty = true
    @AppStorage("notifyExtractorsExpired") private var notifyExtractorsExpired = true
    @AppStorage("notifyIndustryFinished") private var notifyIndustryFinished = true
    @AppStorage("notifyContractsUpdated") private var notifyContractsUpdated = true
    @AppStorage("notifyStructureAlerts") private var notifyStructureAlerts = true
    @AppStorage("notifyWarAlerts") private var notifyWarAlerts = true
    @AppStorage("notifyContactPresence") private var notifyContactPresence = true

    var body: some View {
        Form {
            Section {
                Toggle("Enable Notifications", isOn: $notificationsEnabled)
            }

            Section("Categories") {
                Toggle("Skill queue becomes empty", isOn: $notifySkillQueueEmpty)
                    .disabled(!notificationsEnabled)
                Toggle("PI extractors expired", isOn: $notifyExtractorsExpired)
                    .disabled(!notificationsEnabled)
                Toggle("Industry jobs finished", isOn: $notifyIndustryFinished)
                    .disabled(!notificationsEnabled)
                Toggle("Contracts updated", isOn: $notifyContractsUpdated)
                    .disabled(!notificationsEnabled)
                Toggle("Structure alerts", isOn: $notifyStructureAlerts)
                    .disabled(!notificationsEnabled)
                Toggle("War declarations", isOn: $notifyWarAlerts)
                    .disabled(!notificationsEnabled)
                Toggle("Contact comes online / goes offline", isOn: $notifyContactPresence)
                    .disabled(!notificationsEnabled)
            }

            Section {
                Button("Open System Notification Settings\u{2026}") {
                    if let url = URL(string: "x-apple.systempreferences:com.apple.preference.notifications") {
                        NSWorkspace.shared.open(url)
                    }
                }
                .buttonStyle(.link)
            }
        }
        .formStyle(.grouped)
    }
}

// MARK:  General Tab

private struct GeneralTab: View {
    @Environment(AccountManager.self) private var accountManager
    @Environment(DashboardPrefetcher.self) private var prefetcher
    @Environment(AppUpdater.self) private var appUpdater
    @AppStorage("backgroundPollInterval") private var pollInterval: Double = 300
    @AppStorage("defaultCharacterMode") private var defaultCharacterMode: String = "last"
    @State private var launchAtLogin = false
    @State private var isRefreshing = false

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
            }

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

private struct AppearanceTab: View {
    @AppStorage("colorScheme") private var colorSchemePref: String = "system"
    @AppStorage("menuBarShowWallet") private var menuBarShowWallet = true
    @AppStorage("menuBarShowSP") private var menuBarShowSP = true
    @AppStorage("menuBarShowLocation") private var menuBarShowLocation = true
    @AppStorage("menuBarShowShip") private var menuBarShowShip = true
    @AppStorage("menuBarCompact") private var menuBarCompact = false

    var body: some View {
        Form {
            Section("Theme") {
                Picker("Appearance", selection: $colorSchemePref) {
                    Text("System Default").tag("system")
                    Text("Light").tag("light")
                    Text("Dark").tag("dark")
                }
                .pickerStyle(.radioGroup)
            }

            Section("Menu Bar Card") {
                Toggle("Show wallet balance", isOn: $menuBarShowWallet)
                Toggle("Show skill points", isOn: $menuBarShowSP)
                Toggle("Show current location", isOn: $menuBarShowLocation)
                Toggle("Show current ship", isOn: $menuBarShowShip)
                Divider()
                Toggle("Compact layout", isOn: $menuBarCompact)
            }
        }
        .formStyle(.grouped)
    }
}

// MARK:  Cache & Data Tab

private struct CacheTab: View {
    @Environment(AccountManager.self) private var accountManager
    @Environment(DashboardPrefetcher.self) private var prefetcher

    @State private var universeCacheSize: String = "Calculating\u{2026}"
    @State private var nameCacheSize: String = "Calculating\u{2026}"
    @State private var isClearingUniverse = false
    @State private var isClearingNames = false
    @State private var isRefreshing = false

    var body: some View {
        Form {
            Section("Universe Cache") {
                LabeledContent("Size", value: universeCacheSize)
                Button(isClearingUniverse ? "Clearing\u{2026}" : "Clear Universe Cache") {
                    Task {
                        isClearingUniverse = true
                        await UniverseCache.shared.clearDiskCache()
                        isClearingUniverse = false
                        await recalculateSizes()
                    }
                }
                .disabled(isClearingUniverse)
                Text("Stores solar system, type, group, constellation, and region data. Auto-expires after 7 days.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Name Cache") {
                LabeledContent("Size", value: nameCacheSize)
                Button(isClearingNames ? "Clearing\u{2026}" : "Clear Name Cache") {
                    Task {
                        isClearingNames = true
                        await NameResolver.shared.clearCache()
                        isClearingNames = false
                        await recalculateSizes()
                    }
                }
                .disabled(isClearingNames)
                Text("Stores resolved names for characters, corporations, systems, and skills.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Dashboard Data") {
                LabeledContent("Last refreshed") {
                    if let lastRefresh = prefetcher.lastRefresh {
                        Text(lastRefresh, style: .relative)
                    } else {
                        Text("Never")
                    }
                }
                Button(isRefreshing ? "Refreshing\u{2026}" : "Refresh All Data Now") {
                    Task {
                        isRefreshing = true
                        await prefetcher.prefetchAll(accountManager: accountManager)
                        isRefreshing = false
                    }
                }
                .disabled(isRefreshing || prefetcher.isLoading)
            }
        }
        .formStyle(.grouped)
        .task {
            await recalculateSizes()
        }
    }

    private func recalculateSizes() async {
        let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
        let universeDir = base.appendingPathComponent("EVEOps/universe")
        let nameCacheURL = base.appendingPathComponent("EVEOps/name_cache.json")
        universeCacheSize = formatBytes(directorySize(universeDir))
        nameCacheSize = formatBytes(fileSize(nameCacheURL))
    }

    private func directorySize(_ url: URL) -> Int64 {
        guard let enumerator = FileManager.default.enumerator(
            at: url, includingPropertiesForKeys: [.fileSizeKey], options: .skipsHiddenFiles
        ) else { return 0 }
        var total: Int64 = 0
        for case let fileURL as URL in enumerator {
            let size = (try? fileURL.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
            total += Int64(size)
        }
        return total
    }

    private func fileSize(_ url: URL) -> Int64 {
        Int64((try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
    }

    private func formatBytes(_ bytes: Int64) -> String {
        guard bytes > 0 else { return "Empty" }
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }
}

// MARK:  Advanced Tab

private struct AdvancedTab: View {
    @AppStorage("esiServer") private var esiServer: String = "tranquility"
    @AppStorage("debugMode") private var debugMode = false

    var body: some View {
        Form {
            Section("ESI Server") {
                Picker("Server", selection: $esiServer) {
                    Text("Tranquility (Live)").tag("tranquility")
                    Text("Singularity (Test)").tag("singularity")
                }
                .pickerStyle(.radioGroup)
                Text("Changing the server requires a restart to take effect.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("SSO Configuration") {
                LabeledContent("Client ID", value: "YOUR_CLIENT_ID")
                LabeledContent("Callback URL", value: "eveops://callback")
            }

            Section("Developer") {
                Toggle("Debug mode", isOn: $debugMode)
                Text("Logs additional diagnostic information to the console.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}

// MARK:  About Tab

private struct AboutTab: View {
    @State private var glowPulse = false
    @State private var ringRotation: Double = 0
    @State private var legalExpanded = false
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        ZStack {
            // Background
            if colorScheme == .dark {
                LinearGradient(
                    colors: [
                        Color(red: 0.03, green: 0.05, blue: 0.14),
                        Color(red: 0.07, green: 0.04, blue: 0.11)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)

                // Deterministic starfield
                Canvas { context, size in
                    let w = max(Int(size.width), 1)
                    let h = max(Int(size.height), 1)
                    for i in 0..<60 {
                        let x = CGFloat((i * 137 + 73) % w)
                        let y = CGFloat((i * 239 + 41) % h)
                        let r: CGFloat = (i % 4 == 0) ? 1.1 : 0.55
                        let opacity = Double(i % 8) / 22.0 + 0.1
                        context.fill(
                            Path(ellipseIn: CGRect(x: x - r, y: y - r, width: r * 2, height: r * 2)),
                            with: .color(Color.white.opacity(opacity))
                        )
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                LinearGradient(
                    colors: [
                        Color(red: 0.93, green: 0.95, blue: 1.0),
                        Color(red: 0.87, green: 0.90, blue: 0.97)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }

            // Content
            ScrollView {
                VStack(spacing: 0) {
                    // Hero: icon + title + version
                    VStack(spacing: 10) {
                        iconHero
                        Text("EVEOps")
                            .font(.system(size: 26, weight: .bold))
                            .tracking(0.5)
                        versionPill
                    }
                    .padding(.top, 28)

                    // Gradient rule
                    Rectangle()
                        .fill(
                            LinearGradient(
                                colors: [.clear, .primary.opacity(0.12), .clear],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(height: 0.5)
                        .padding(.horizontal, 44)
                        .padding(.top, 18)

                    // Feature chips
                    HStack(spacing: 8) {
                        chip("antenna.radiowaves.left.and.right", "ESI API")
                        chip("lock.shield", "PKCE Auth")
                        chip("internaldrive", "Smart Cache")
                        chip("bell", "Notifications")
                        chip("apple.intelligence", "Intelligence")
                    }
                    .padding(.top, 16)

                    // Developer links
                    HStack(spacing: 10) {
                        linkButton("doc.text.magnifyingglass", "ESI Reference") {
                            if let url = URL(string: "https://esi.evetech.net/ui/") {
                                NSWorkspace.shared.open(url)
                            }
                        }
                        linkButton("globe", "EVE Developers") {
                            if let url = URL(string: "https://developers.eveonline.com") {
                                NSWorkspace.shared.open(url)
                            }
                        }
                    }
                    .padding(.top, 12)

                    // EVE Buddy standing card
                    eveBuddyCard
                        .padding(.top, 14)

                    // zKillboard attribution card
                    zkillboardCard
                        .padding(.top, 8)

                    // Fuzzwork attribution card
                    fuzzworkCard
                        .padding(.top, 8)
                    
                    // EVEShipFit dogmaEngine card
                    dogmaEngineCard
                        .padding(.top, 8)
                    
                    // Claude Code attribution card
                    claudeCodeCard
                        .padding(.top, 8)

                    // Collapsible legal
                    DisclosureGroup(isExpanded: $legalExpanded) {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("EVE Online and the EVE logo are registered trademarks of Fenris Creations. All rights reserved worldwide.")
                            Text("EVEOps is an independent third-party application not affiliated with, endorsed by, or sponsored by Fenris Creations.")
                            Text("All EVE Online related materials are used in accordance with the EVE Online Third-Party Developer License Agreement.")
                            Text("\"EVE\", \"EVE Online\", \"Fenris\", and all related logos are trademarks of Fenris Creations.")
                        }
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 8)
                    } label: {
                        Label("Legal Notices", systemImage: "doc.text")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 44)
                    .padding(.top, 14)

                    Text("\u{00A9} \(currentYear) CitizenCoder  ·  Not affiliated with Fenris Creations.")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .padding(.top, 20)
                        .padding(.bottom, 20)
                }
                .frame(maxWidth: .infinity)
            }
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 2.5).repeatForever(autoreverses: true)) {
                glowPulse = true
            }
            withAnimation(.linear(duration: 12).repeatForever(autoreverses: false)) {
                ringRotation = 360
            }
        }
    }

    // Mark:  Icon hero

    private var iconHero: some View {
        ZStack {
            // Pulsing ambient glow
            Circle()
                .fill(
                    RadialGradient(
                        colors: [
                            Color(hue: 0.62, saturation: 0.8, brightness: 1.0)
                                .opacity(glowPulse ? 0.28 : 0.08),
                            .clear
                        ],
                        center: .center,
                        startRadius: 0,
                        endRadius: 68
                    )
                )
                .frame(width: 136, height: 136)

            // Rotating comet-sweep ring
            Circle()
                .strokeBorder(
                    AngularGradient(
                        gradient: Gradient(stops: [
                            .init(color: .blue.opacity(0), location: 0.0),
                            .init(color: .blue, location: 0.3),
                            .init(color: .cyan, location: 0.55),
                            .init(color: .purple, location: 0.75),
                            .init(color: .blue.opacity(0), location: 1.0)
                        ]),
                        center: .center
                    ),
                    lineWidth: 2.5
                )
                .frame(width: 104, height: 104)
                .rotationEffect(.degrees(ringRotation))

            // App icon
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 84, height: 84)
                .clipShape(RoundedRectangle(cornerRadius: 19, style: .continuous))
                .shadow(color: .black.opacity(0.25), radius: 8, x: 0, y: 4)
        }
    }

    // Mark:  Version pill

    @ViewBuilder
    private var versionPill: some View {
        if let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String,
           let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String {
            HStack(spacing: 6) {
                Circle()
                    .fill(.green)
                    .frame(width: 5, height: 5)
                Text("v\(version)  ·  Build \(build)")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 5)
            .background(.primary.opacity(0.05), in: Capsule())
            .overlay(Capsule().strokeBorder(.primary.opacity(0.1)))
        }
    }

    // Mark:  EVE Buddy acknowledgement

    private var eveBuddyCard: some View {
        HStack(spacing: 14) {
            // Max-standing gold star badge
            ZStack {
                Circle()
                    .fill(Color(hue: 0.12, saturation: 0.85, brightness: 1.0).opacity(0.15))
                    .frame(width: 38, height: 38)
                Image(systemName: "star.fill")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(Color(hue: 0.12, saturation: 0.9, brightness: 1.0))
            }

            VStack(alignment: .leading, spacing: 2) {
                Text("EVE Buddy")
                    .font(.system(size: 13, weight: .semibold))
                Text("ACKNOWLEDGED INSPIRATION")
                    .font(.system(size: 9, weight: .bold))
                    .tracking(1.2)
                    .foregroundStyle(.tertiary)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 1) {
                Text("+10.0")
                    .font(.system(size: 15, weight: .bold, design: .monospaced))
                    .foregroundStyle(Color(hue: 0.33, saturation: 0.65, brightness: 0.80))
                Text("STANDING")
                    .font(.system(size: 8, weight: .bold))
                    .tracking(1.2)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 11)
        .background(.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(
                    LinearGradient(
                        colors: [
                            Color(hue: 0.12, saturation: 0.85, brightness: 1.0).opacity(0.35),
                            Color(hue: 0.12, saturation: 0.85, brightness: 1.0).opacity(0.10)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
        )
        .padding(.horizontal, 44)
    }

    // Mark:  zKillboard attribution card

    private var zkillboardCard: some View {
        HStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(Color.red.opacity(0.12))
                    .frame(width: 38, height: 38)
                Image(systemName: "heart.badge.bolt.slash")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(.red)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text("zKillboard")
                    .font(.system(size: 13, weight: .semibold))
                Text("COMMUNITY FIT DATA SOURCE")
                    .font(.system(size: 9, weight: .bold))
                    .tracking(1.2)
                    .foregroundStyle(.tertiary)
            }

            Spacer()

            Button("zkillboard.com") {
                if let url = URL(string: "https://zkillboard.com") {
                    NSWorkspace.shared.open(url)
                }
            }
            .buttonStyle(.link)
            .font(.system(size: 11, weight: .medium))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 11)
        .background(.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(
                    LinearGradient(
                        colors: [
                            Color.red.opacity(0.30),
                            Color.red.opacity(0.08)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
        )
        .padding(.horizontal, 44)
    }

    // Mark:  dogmaEngine attribution card

    private var dogmaEngineCard: some View {
        HStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(Color.red.opacity(0.12))
                    .frame(width: 38, height: 38)
                Image(systemName: "esim")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(.red)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text("EVEShip.fit's Dogma Engine")
                    .font(.system(size: 13, weight: .semibold))
                Text("SHIP FIT SIM ENGINE")
                    .font(.system(size: 9, weight: .bold))
                    .tracking(1.2)
                    .foregroundStyle(.tertiary)
            }

            Spacer()

            Button("EVEShip.fit") {
                if let url = URL(string: "https://eveship.fit") {
                    NSWorkspace.shared.open(url)
                }
            }
            .buttonStyle(.link)
            .font(.system(size: 11, weight: .medium))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 11)
        .background(.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(
                    LinearGradient(
                        colors: [
                            Color.orange.opacity(0.30),
                            Color.orange.opacity(0.08)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
        )
        .padding(.horizontal, 44)
    }
    
    // Mark:  Fuzzwork attribution card

    private var fuzzworkCard: some View {
        HStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(Color.green.opacity(0.12))
                    .frame(width: 38, height: 38)
                Image(systemName: "chart.bar.fill")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(.green)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text("Fuzzwork Enterprises")
                    .font(.system(size: 13, weight: .semibold))
                Text("MARKET PRICE DATA SOURCE")
                    .font(.system(size: 9, weight: .bold))
                    .tracking(1.2)
                    .foregroundStyle(.tertiary)
            }

            Spacer()

            Button("market.fuzzwork.co.uk") {
                if let url = URL(string: "https://market.fuzzwork.co.uk") {
                    NSWorkspace.shared.open(url)
                }
            }
            .buttonStyle(.link)
            .font(.system(size: 11, weight: .medium))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 11)
        .background(.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(
                    LinearGradient(
                        colors: [
                            Color.green.opacity(0.30),
                            Color.green.opacity(0.08)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
        )
        .padding(.horizontal, 44)
    }

    // Mark:  Claude Code attribution card

    private var claudeCodeCard: some View {
        HStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(Color.purple.opacity(0.12))
                    .frame(width: 38, height: 38)
                Image(systemName: "wand.and.stars")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(.purple)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text("Claude Code")
                    .font(.system(size: 13, weight: .semibold))
                Text("AI DEVELOPMENT ASSISTANT")
                    .font(.system(size: 9, weight: .bold))
                    .tracking(1.2)
                    .foregroundStyle(.tertiary)
            }

            Spacer()

            Button("claude.ai/code") {
                if let url = URL(string: "https://claude.ai/code") {
                    NSWorkspace.shared.open(url)
                }
            }
            .buttonStyle(.link)
            .font(.system(size: 11, weight: .medium))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 11)
        .background(.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(
                    LinearGradient(
                        colors: [
                            Color.purple.opacity(0.30),
                            Color.purple.opacity(0.08)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
        )
        .padding(.horizontal, 44)
    }

    // Mark:  Helpers

    private func chip(_ icon: String, _ label: String) -> some View {
        HStack(spacing: 5) {
            Image(systemName: icon)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.blue)
            Text(label)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(.primary.opacity(0.08)))
    }

    private func linkButton(_ icon: String, _ label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: icon)
                    .font(.system(size: 11))
                Text(label)
                    .font(.system(size: 12, weight: .medium))
            }
            .foregroundStyle(.blue)
            .padding(.horizontal, 14)
            .padding(.vertical, 7)
            .background(.blue.opacity(0.08), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(.blue.opacity(0.18)))
        }
        .buttonStyle(.plain)
    }

    private var currentYear: String {
        Calendar.current.component(.year, from: Date()).description
    }
}

// Mark:  Intelligence Tab

private struct IntelligenceTab: View {
    @AppStorage("aiInsightsEnabled") private var aiInsightsEnabled = false

    var body: some View {
        if #available(macOS 26.0, *) {
            IntelligenceTabContent(aiInsightsEnabled: $aiInsightsEnabled)
        } else {
            VStack(spacing: 16) {
                Image(systemName: "brain")
                    .font(.system(size: 44))
                    .foregroundStyle(.tertiary)
                Text("Apple Intelligence requires macOS 26 or later.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

@available(macOS 26.0, *)
private struct IntelligenceTabContent: View {
    @Binding var aiInsightsEnabled: Bool
    private var model: SystemLanguageModel { .default }

    @AppStorage("aiInsightFinances")          private var aiInsightFinances          = true
    @AppStorage("aiInsightSkills")            private var aiInsightSkills            = true
    @AppStorage("aiInsightKillmails")         private var aiInsightKillmails         = true
    @AppStorage("aiInsightIndustry")          private var aiInsightIndustry          = true
    @AppStorage("aiInsightAssets")            private var aiInsightAssets            = true
    @AppStorage("aiInsightFittings")          private var aiInsightFittings          = true
    @AppStorage("aiInsightCommunityFittings") private var aiInsightCommunityFittings = true
    @AppStorage("aiInsightMarket")            private var aiInsightMarket            = true
    @AppStorage("aiInsightClones")            private var aiInsightClones            = true

    var body: some View {
        Form {
            Section("Apple Intelligence") {
                switch model.availability {
                case .available:
                    Toggle("Enable AI Insights", isOn: $aiInsightsEnabled)
                    Text("Uses the on-device Apple Intelligence to analyze your financial and skill training data. All processing is local — no data leaves your Mac.")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                case .unavailable(.appleIntelligenceNotEnabled):
                    Label {
                        VStack(alignment: .leading, spacing: 3) {
                            Text("Apple Intelligence Not Enabled")
                                .fontWeight(.medium)
                            Text("Turn on Apple Intelligence in System Settings to use AI Insights.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    } icon: {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                    }
                    Button("Open System Settings\u{2026}") {
                        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.siri") {
                            NSWorkspace.shared.open(url)
                        }
                    }
                    .buttonStyle(.link)

                case .unavailable(.deviceNotEligible):
                    Label {
                        VStack(alignment: .leading, spacing: 3) {
                            Text("Device Not Eligible")
                                .fontWeight(.medium)
                            Text("Apple Intelligence requires Apple Silicon. This Mac is not supported.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    } icon: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.red)
                    }

                case .unavailable(.modelNotReady):
                    Label {
                        VStack(alignment: .leading, spacing: 3) {
                            Text("Model Downloading")
                                .fontWeight(.medium)
                            Text("The on-device model is still initializing. Check back shortly.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    } icon: {
                        Image(systemName: "arrow.down.circle.fill")
                            .foregroundStyle(.blue)
                    }

                default:
                    Text("Apple Intelligence is not available on this device.")
                        .foregroundStyle(.secondary)
                }
            }

            if aiInsightsEnabled, case .available = model.availability {
                Section("Individual Insights") {
                    Toggle(isOn: $aiInsightFinances) {
                        Label("Finances", systemImage: "banknote")
                    }
                    Toggle(isOn: $aiInsightSkills) {
                        Label("Skill Planner", systemImage: "graduationcap")
                    }
                    Toggle(isOn: $aiInsightKillmails) {
                        Label("Kill/Loss Mails", systemImage: "flame")
                    }
                    Toggle(isOn: $aiInsightIndustry) {
                        Label("Industry", systemImage: "hammer")
                    }
                    Toggle(isOn: $aiInsightAssets) {
                        Label("Assets", systemImage: "cube.box")
                    }
                    Toggle(isOn: $aiInsightFittings) {
                        Label("Fittings", systemImage: "cpu")
                    }
                    Toggle(isOn: $aiInsightCommunityFittings) {
                        Label("Community Fittings", systemImage: "person.2.wave.2")
                    }
                    Toggle(isOn: $aiInsightMarket) {
                        Label("Market Browser", systemImage: "chart.xyaxis.line")
                    }
                    Toggle(isOn: $aiInsightClones) {
                        Label("Clones & Implants", systemImage: "brain.head.profile")
                    }
                }
            }
        }
        .formStyle(.grouped)
    }
}
