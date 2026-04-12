import SwiftUI
import ServiceManagement

struct SettingsView: View {
    var body: some View {
        TabView {
            AccountsTab()
                .tabItem { Label("Accounts", systemImage: "person.2") }
            NotificationsTab()
                .tabItem { Label("Notifications", systemImage: "bell") }
            GeneralTab()
                .tabItem { Label("General", systemImage: "gearshape") }
            AppearanceTab()
                .tabItem { Label("Appearance", systemImage: "paintbrush") }
            CacheTab()
                .tabItem { Label("Cache & Data", systemImage: "internaldrive") }
            AdvancedTab()
                .tabItem { Label("Advanced", systemImage: "terminal") }
            AboutTab()
                .tabItem { Label("About", systemImage: "info.circle") }
        }
        .frame(width: 540, height: 460)
    }
}

// MARK: - Accounts Tab

private struct AccountsTab: View {
    @Environment(AccountManager.self) private var accountManager

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
                List(accountManager.accounts, id: \.characterID) { account in
                    AccountRowView(account: account)
                }
                .listStyle(.inset)
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

            if account.isTokenExpired {
                Label("Expired", systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.orange)
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

// MARK: - Notifications Tab

private struct NotificationsTab: View {
    @AppStorage("notificationsEnabled") private var notificationsEnabled = true
    @AppStorage("notifySkillQueueEmpty") private var notifySkillQueueEmpty = true
    @AppStorage("notifyExtractorsExpired") private var notifyExtractorsExpired = true
    @AppStorage("notifyIndustryFinished") private var notifyIndustryFinished = true
    @AppStorage("notifyContractsUpdated") private var notifyContractsUpdated = true
    @AppStorage("notifyStructureAlerts") private var notifyStructureAlerts = true

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

// MARK: - General Tab

private struct GeneralTab: View {
    @AppStorage("backgroundPollInterval") private var pollInterval: Double = 300
    @AppStorage("defaultCharacterMode") private var defaultCharacterMode: String = "last"
    @State private var launchAtLogin = false

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
        }
        .formStyle(.grouped)
        .onAppear {
            launchAtLogin = SMAppService.mainApp.status == .enabled
        }
    }
}

// MARK: - Appearance Tab

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

// MARK: - Cache & Data Tab

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

// MARK: - Advanced Tab

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

// MARK: - About Tab

private struct AboutTab: View {
    var body: some View {
        VStack(spacing: 20) {
            VStack(spacing: 8) {
                Image(nsImage: NSApp.applicationIconImage)
                    .resizable()
                    .frame(width: 96, height: 96)

                Text("EVEOps")
                    .font(.title)
                    .fontWeight(.bold)

                if let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String,
                   let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String {
                    Text("Version \(version) (\(build))")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }

            Divider()
                .padding(.horizontal, 40)

            VStack(spacing: 12) {
                Text("Legal Notices")
                    .font(.headline)

                VStack(spacing: 8) {
                    Text("EVE Online and the EVE logo are registered trademarks of CCP hf. All rights are reserved worldwide.")
                    Text("EVEOps is an independent third-party application and is not affiliated with, endorsed by, or sponsored by CCP hf.")
                    Text("All EVE Online related materials including images, characters, names, and game data are the intellectual property of CCP hf. and are used in accordance with the EVE Online Third-Party Developer License Agreement.")
                    Text("\u{201C}EVE\u{201D}, \u{201C}EVE Online\u{201D}, \u{201C}CCP\u{201D}, and all related logos and images are trademarks or registered trademarks of CCP hf.")
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            }

            Spacer()

            Text("\u{00A9} \(currentYear) EVEOps Contributors")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 24)
    }

    private var currentYear: String {
        Calendar.current.component(.year, from: Date()).description
    }
}
