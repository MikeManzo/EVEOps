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

// MARK:  Notifications Tab

struct NotificationsTab: View {
    @Environment(AccountManager.self) private var accountManager
    @Environment(DashboardPrefetcher.self) private var prefetcher

    @AppStorage("notificationsEnabled") private var notificationsEnabled = true
    @AppStorage("notifySkillQueueEmpty") private var notifySkillQueueEmpty = true
    @AppStorage("notifyExtractorsExpired") private var notifyExtractorsExpired = true
    @AppStorage("notifyIndustryFinished") private var notifyIndustryFinished = true
    @AppStorage("notifyContractsUpdated") private var notifyContractsUpdated = true
    @AppStorage("notifyStructureAlerts") private var notifyStructureAlerts = true
    @AppStorage("notifyStructureFuel") private var notifyStructureFuel = true
    @AppStorage("notifyWarAlerts") private var notifyWarAlerts = true
    @AppStorage("notifyContactPresence") private var notifyContactPresence = true
    @AppStorage("notifyStandingsChanged") private var notifyStandingsChanged = true
    @AppStorage("notifyServerStatus") private var notifyServerStatus = true
    @AppStorage("discordNotificationsEnabled") private var discordNotificationsEnabled = false
    @AppStorage("discordRichPresenceEnabled") private var discordRichPresenceEnabled = false

    @State private var discordWebhookURL: String = ""
    @State private var testState: DiscordTestState = .idle
    @State private var showDiscordInfo = false
    @State private var showRichPresenceInfo = false

    private enum DiscordTestState: Equatable {
        case idle, sending, success, failure
    }

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
                Toggle("Structure fuel running low", isOn: $notifyStructureFuel)
                    .disabled(!notificationsEnabled)
                Toggle("War declarations", isOn: $notifyWarAlerts)
                    .disabled(!notificationsEnabled)
                Toggle("Contact comes online / goes offline", isOn: $notifyContactPresence)
                    .disabled(!notificationsEnabled)
                Toggle("Standing increases or decreases", isOn: $notifyStandingsChanged)
                    .disabled(!notificationsEnabled)
                Toggle("Servers back online after downtime", isOn: $notifyServerStatus)
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

            Section {
                Toggle("Send alerts to Discord", isOn: $discordNotificationsEnabled)
                    .disabled(!notificationsEnabled)

                SecureField("Webhook URL", text: $discordWebhookURL)
                    .disabled(!notificationsEnabled || !discordNotificationsEnabled)
                    .onChange(of: discordWebhookURL) { _, newValue in
                        let trimmed = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
                        if trimmed.isEmpty {
                            try? KeychainHelper.delete(for: DiscordNotifier.webhookURLKeychainAccount)
                        } else {
                            try? KeychainHelper.saveString(trimmed, for: DiscordNotifier.webhookURLKeychainAccount)
                        }
                    }

                HStack {
                    Button("Send Test Message") {
                        testState = .sending
                        Task {
                            let ok = await DiscordNotifier.shared.sendTest()
                            testState = ok ? .success : .failure
                        }
                    }
                    .disabled(!notificationsEnabled || !discordNotificationsEnabled
                              || discordWebhookURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                              || testState == .sending)

                    switch testState {
                    case .idle: EmptyView()
                    case .sending:
                        ProgressView().controlSize(.small)
                    case .success:
                        Label("Sent", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green).font(.caption)
                    case .failure:
                        Label("Failed — check the URL", systemImage: "xmark.circle.fill")
                            .foregroundStyle(.red).font(.caption)
                    }
                }

            } header: {
                HStack(spacing: 4) {
                    Text("Discord")
                    Button {
                        showDiscordInfo.toggle()
                    } label: {
                        Image(systemName: "info.circle")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    .accessibilityLabel("More Info")
                    .buttonStyle(.plain)
                    .popover(isPresented: $showDiscordInfo, arrowEdge: .top) {
                        discordInfoPopover
                    }
                }
            }

            Section {
                HStack {
                    Toggle("Show current character in Discord status", isOn: $discordRichPresenceEnabled)
                        .onChange(of: discordRichPresenceEnabled) { _, enabled in
                            if enabled {
                                Task { await DiscordRichPresence.refresh(accountManager: accountManager, prefetcher: prefetcher) }
                            } else {
                                Task { await DiscordRichPresence.shared.disconnect() }
                            }
                        }
                    Spacer()
                    richPresenceStatusBadge
                }

                Text("Requires the Discord desktop app running on this Mac. Status updates on the same interval as background polling.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } header: {
                HStack(spacing: 4) {
                    Text("Rich Presence")
                    Button {
                        showRichPresenceInfo.toggle()
                    } label: {
                        Image(systemName: "info.circle")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    .accessibilityLabel("More Info")
                    .buttonStyle(.plain)
                    .popover(isPresented: $showRichPresenceInfo, arrowEdge: .top) {
                        richPresenceInfoPopover
                    }
                }
            }
        }
        .formStyle(.grouped)
        .task {
            discordWebhookURL = (try? KeychainHelper.loadString(for: DiscordNotifier.webhookURLKeychainAccount)) ?? ""
            // Rich Presence's status badge only updates from the toggle's onChange or the
            // next background poll (up to several minutes away) — if the feature was left
            // on from a previous session, reflect its real status as soon as this pane opens
            // instead of showing nothing until one of those fires.
            if discordRichPresenceEnabled {
                await DiscordRichPresence.refresh(accountManager: accountManager, prefetcher: prefetcher)
            }
        }
    }

    private var discordInfoPopover: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Discord Notifications")
                .font(.headline)
            Text("Send the same alerts you get as native macOS notifications to a channel in your Discord server \u{2014} handy for corp leadership watching for structure or war alerts without the app open.")
                .font(.callout)
                .fixedSize(horizontal: false, vertical: true)
            Divider()
            VStack(alignment: .leading, spacing: 8) {
                discordStep(number: 1, text: "In Discord, open the channel's settings \u{2192} Integrations \u{2192} Webhooks \u{2192} New Webhook, then Copy Webhook URL.")
                discordStep(number: 2, text: "Paste the URL into the Webhook URL field here and turn on “Send alerts to Discord.”")
                discordStep(number: 3, text: "Click “Send Test Message” to confirm it arrives in the channel.")
            }
            .font(.caption)
            Divider()
            HStack(spacing: 4) {
                Image(systemName: "bell.badge")
                    .foregroundStyle(.secondary)
                Text("The Categories above decide which events fire — Discord receives the same ones as your native notifications.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(16)
        .frame(width: 320)
    }

    @ViewBuilder
    private var richPresenceStatusBadge: some View {
        if discordRichPresenceEnabled {
            switch DiscordRichPresenceStatus.shared.state {
            case .off:
                EmptyView()
            case .searching:
                Label("Waiting for Discord…", systemImage: "circle.dotted")
                    .foregroundStyle(.secondary)
                    .font(.caption)
            case .connected:
                Label("Connected", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                    .font(.caption)
            }
        }
    }

    private var richPresenceInfoPopover: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Discord Rich Presence")
                .font(.headline)
            Text("Shows your current ship and system as your Discord activity status — visible to anyone who can see your Discord profile.")
                .font(.callout)
                .fixedSize(horizontal: false, vertical: true)
            Divider()
            VStack(alignment: .leading, spacing: 8) {
                discordStep(number: 1, text: "Make sure the Discord desktop app is running on this Mac.")
                discordStep(number: 2, text: "Turn on \u{201c}Show current character in Discord status.\u{201d}")
            }
            .font(.caption)
            Divider()
            HStack(spacing: 4) {
                Image(systemName: "person.crop.circle")
                    .foregroundStyle(.secondary)
                Text("Uses whichever character is currently selected in EVEOps.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(16)
        .frame(width: 320)
    }

    private func discordStep(number: Int, text: LocalizedStringKey) -> some View {
        HStack(alignment: .top, spacing: 6) {
            Image(systemName: "\(number).circle.fill")
                .foregroundStyle(.secondary)
                .frame(width: 14)
            Text(text)
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
