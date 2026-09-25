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
import OSLog

/// Icon-only toolbar button with a hover highlight, since the plain SF Symbol
/// buttons in the menu bar footer otherwise give no feedback until clicked.
private struct MenuBarIconButton: View {
    let systemName: String
    var tint: Color = .secondary
    var hoverTint: Color = .primary.opacity(0.1)
    let help: LocalizedStringKey
    let action: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 13))
                .foregroundStyle(tint)
                .frame(width: 26, height: 26)
                .background(isHovering ? hoverTint : .clear, in: Circle())
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .animation(.easeOut(duration: 0.1), value: isHovering)
        .help(help)
    }
}

struct MenuBarView: View {
    @Environment(AccountManager.self) private var accountManager
    @Environment(DashboardPrefetcher.self) private var prefetcher
    @Environment(APIStatusMonitor.self) private var apiStatus
    @Environment(AppUpdater.self) private var appUpdater
    @Environment(ThemeManager.self) private var themeManager
    private var palette: EVEPalette { themeManager.palette }
    @Environment(\.dismiss) private var dismiss
    @AppStorage("backgroundPollInterval") private var pollInterval: Double = 300
    @State private var summaries: [Int: CharacterSummary] = [:]
    @State private var isLoading = false
    @State private var now = Date()

    private var selectedSummary: CharacterSummary? {
        guard let id = accountManager.selectedCharacterID else { return nil }
        return summaries[id]
    }

    private var timeUntilDowntime: TimeInterval {
        EVEDowntime.next(from: now).timeIntervalSince(now)
    }

    var body: some View {
        VStack(spacing: 0) {
            if !apiStatus.isReachable {
                HStack(spacing: 6) {
                    Image(systemName: "clock.badge.exclamationmark")
                        .foregroundStyle(.orange)
                        .font(.caption)
                    Text(apiStatus.statusMessage.isEmpty ? "Downtime in progress" : apiStatus.statusMessage)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(.orange.opacity(0.1))

                Divider()
            } else if timeUntilDowntime <= 15 * 60 {
                HStack(spacing: 6) {
                    Image(systemName: "clock.badge.exclamationmark")
                        .foregroundStyle(.orange)
                        .font(.caption)
                    Text("Downtime in \(max(Int(timeUntilDowntime) / 60, 0))m")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(.orange.opacity(0.1))

                Divider()
            }

            if appUpdater.updateAvailable {
                Button {
                    dismiss()
                    appUpdater.checkForUpdates()
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "arrow.down.circle.fill")
                            .foregroundStyle(palette.accent)
                            .font(.caption)
                        if let version = appUpdater.availableVersion {
                            Text("Update available — v\(version)")
                                .font(.caption)
                        } else {
                            Text("Update available")
                                .font(.caption)
                        }
                        Spacer()
                        Text("Install")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 2)
                            .background(palette.accent, in: Capsule())
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(palette.accent.opacity(0.1))
                .help("Install the available update")
                .accessibilityLabel(
                    appUpdater.availableVersion.map { "Install update version \($0)" } ?? "Install available update"
                )

                Divider()
            }

            if let account = accountManager.selectedAccount {
                if isLoading && selectedSummary == nil {
                    LoadingSkeleton(rows: 3)
                        .frame(height: 170)
                } else {
                    CharacterCardView(account: account, summary: selectedSummary)
                }
            } else if accountManager.accounts.isEmpty {
                EVEEmptyState(
                    "No Characters Yet",
                    systemImage: "person.crop.circle.badge.plus",
                    message: Text("Add an EVE character to see training, wallet and alerts here.")
                ) {
                    Button("Add Character", systemImage: "plus") {
                        dismiss()
                        WindowService.shared.showMain()
                        AppRouter.shared.requestAddCharacter()
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(palette.accent)
                    .controlSize(.small)
                }
                .frame(height: 220)
            } else {
                Text("Select a character")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding()
            }

            Divider()

            // Character switcher (if multiple)
            if accountManager.accounts.count > 1 {
                characterSwitcher
                Divider()
            }

            HStack(spacing: 10) {
                // Routine actions, evenly spaced
                HStack {
                    MenuBarIconButton(systemName: "macwindow", tint: .primary, help: "EVEOps") {
                        dismiss()
                        WindowService.shared.showMain()
                    }

                    Spacer()

                    MenuBarIconButton(systemName: "gamecontroller.fill", help: "Launch EVE") {
                        dismiss()
                        Task { try? await GameLauncher.launchOfficialLauncher() }
                    }

                    Spacer()

                    discordStatusIndicator

                    Spacer()

                    MenuBarIconButton(systemName: "gear", help: "Settings") {
                        dismiss()
                        WindowService.shared.showSettings()
                    }

                    Spacer()

                    // Help lives here too: as a menu-bar app, EVEOps usually has no main menu
                    // (and so no Help menu) unless the Dock icon is turned on.
                    Menu {
                        Button("What’s New in EVEOps", systemImage: "sparkles") {
                            dismiss()
                            WindowService.shared.showMain()
                            AppRouter.shared.showWhatsNew()
                        }
                        Button("Keyboard Shortcuts", systemImage: "keyboard") {
                            dismiss()
                            WindowService.shared.showMain()
                            AppRouter.shared.showKeyboardShortcuts()
                        }
                        Divider()
                        if let url = URL(string: "https://github.com/MikeManzo/EVEOps") {
                            Link(destination: url) {
                                Label("EVEOps on GitHub", systemImage: "arrow.up.right.square")
                            }
                        }
                    } label: {
                        Image(systemName: "questionmark.circle")
                            .font(.system(size: 13))
                            .foregroundStyle(.secondary)
                            .frame(width: 26, height: 26)
                            .contentShape(Circle())
                    }
                    .menuStyle(.button)
                    .buttonStyle(.plain)
                    .menuIndicator(.hidden)
                    .fixedSize()
                    .help("Help")
                    .accessibilityLabel("Help")
                }

                Divider()
                    .frame(height: 14)

                // Quit set apart from routine actions — it's the one irreversible control here
                MenuBarIconButton(
                    systemName: "power",
                    tint: .red.opacity(0.8),
                    hoverTint: .red.opacity(0.18),
                    help: "Quit"
                ) {
                    NSApplication.shared.terminate(nil)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
        .frame(width: 330)
        .task {
            await apiStatus.checkNow()
            // Show prebuilt summaries immediately if available, then always refresh
            if !prefetcher.menuBarSummaries.isEmpty {
                summaries = prefetcher.menuBarSummaries
            }
            isLoading = summaries.isEmpty
            await loadAllSummaries()
        }
        .autoRefresh(every: pollInterval) { await loadAllSummaries() }
        .onChange(of: prefetcher.lastRefresh) { _, _ in
            // Prefetcher was refreshed externally (e.g. "Refresh Now" in Settings) — sync immediately
            Task { await loadAllSummaries() }
        }
        .periodicTick(every: 30) { now = Date() }
    }

    /// Static status glyph (not a button — Rich Presence is configured from Settings,
    /// this just answers "is it actually working right now"). Discord's brand blurple
    /// when connected, the same secondary gray as the other icons otherwise — covers
    /// both "disabled" and "enabled but not reaching Discord" as one glyph, matching
    /// what was asked for: connected vs. not, not a three-state breakdown.
    private var discordStatusIndicator: some View {
        let isConnected = DiscordRichPresenceStatus.shared.state == .connected
        return Image("DiscordGlyph")
            .resizable()
            .scaledToFit()
            .frame(width: 14, height: 14)
            .foregroundStyle(isConnected ? Color(red: 0x58/255, green: 0x65/255, blue: 0xF2/255) : .secondary)
            .help(isConnected ? "Discord: Connected" : "Discord: Not connected")
    }

    private var characterSwitcher: some View {
        VStack(spacing: 1) {
            ForEach(accountManager.accounts.filter({ $0.characterID != accountManager.selectedCharacterID }), id: \.characterID) { account in
                PilotSwitcherRow(account: account, summary: summaries[account.characterID], accent: palette.accent) {
                    accountManager.selectedCharacterID = account.characterID
                }
            }
        }
        .padding(.vertical, EVESpacing.xs)
        .padding(.horizontal, EVESpacing.xs)
    }

    // MARK:  Data Loading

    private func loadAllSummaries() async {
        // Show available prefetcher data immediately (within 2-min freshness window)
        for account in accountManager.accounts {
            if let prefetched = prefetcher.data(for: account.characterID) {
                let summary = await buildSummary(from: prefetched, for: account)
                summaries[account.characterID] = summary
            }
        }

        if !summaries.isEmpty {
            isLoading = false
        }

        // Fetch fresh ESI data for accounts whose prefetcher entry is stale or absent
        for account in accountManager.accounts where prefetcher.data(for: account.characterID) == nil {
            summaries[account.characterID] = await loadSummary(for: account)
        }

        isLoading = false
    }

    private nonisolated func buildSummary(from prefetched: DashboardPrefetcher.PrefetchedCharacterData, for account: StoredAccount) async -> CharacterSummary {
        var s = CharacterSummary(characterID: account.characterID)
        s.wallet = prefetched.wallet
        s.totalSP = prefetched.skills.totalSp
        s.online = prefetched.online.online
        s.ship = prefetched.ship
        s.location = prefetched.location
        let daily = prefetched.journal.todayISKSummary
        s.dailyISKMade = daily.made
        s.dailyISKSpent = daily.spent

        let activeQueue = prefetched.skillQueue.filter { $0.finishDate ?? .distantPast > Date() }
        s.skillQueueCount = activeQueue.count
        s.currentSkillFinish = activeQueue.first?.finishDate
        s.queueEnd = activeQueue.last?.finishDate
        if let first = activeQueue.first { s.trainingSkillID = first.skillId }
        s.isQueueEmpty = activeQueue.isEmpty

        s.activeContractCount = prefetched.contracts.filter { $0.status == "outstanding" || $0.status == "in_progress" }.count

        let activeJobs = prefetched.industryJobs.filter { $0.status == "active" }
        s.activeIndustryJobCount = activeJobs.count
        s.nextJobFinish = activeJobs.map(\.endDate).min()

        s.colonyCount = prefetched.colonies.count

        // PI extractor checks
        if !prefetched.colonies.isEmpty, !account.isTokenExpired {
            let token = account.accessToken
            for colony in prefetched.colonies {
                if let layout: ESIColonyLayout = try? await ESIClient.shared.fetch(
                    "/characters/\(account.characterID)/planets/\(colony.planetId)/", token: token
                ) {
                    s.expiredExtractorCount += layout.pins.filter { $0.extractorDetails != nil && ($0.expiryTime ?? .distantPast) < Date() }.count
                }
            }
        }

        // Universe lookups (cached on disk)
        if let sysInfo = await UniverseCache.shared.solarSystem(id: prefetched.location.solarSystemId) {
            s.systemName = sysInfo.name
            s.securityStatus = sysInfo.securityStatus
        }
        if let typeInfo = await UniverseCache.shared.type(id: prefetched.ship.shipTypeId) {
            s.shipTypeName = typeInfo.name
        }
        if let skillID = s.trainingSkillID {
            let resolved = await NameResolver.shared.resolve(ids: [skillID])
            s.trainingSkillName = resolved[skillID]
        }

        // Fetch corp/alliance name bypassing all caches to get the current corp ID from ESI
        if let charInfo: ESICharacterPublic = try? await ESIClient.shared.fetch("/characters/\(account.characterID)/", bypassCache: true) {
            if let corpInfo: ESICorporationPublic = try? await ESIClient.shared.fetch("/corporations/\(charInfo.corporationId)/", bypassCache: true) {
                s.corporationName = corpInfo.name
            }
            if let allianceId = charInfo.allianceId,
               let allianceInfo: ESIAlliancePublic = try? await ESIClient.shared.fetch("/alliances/\(allianceId)/", bypassCache: true) {
                s.allianceName = allianceInfo.name
            }
        }

        return s
    }

    private func loadSummary(for account: StoredAccount) async -> CharacterSummary {
        var s = CharacterSummary(characterID: account.characterID)
        do {
            let token = try await accountManager.validToken(for: account)
            let charID = account.characterID

            var wallet: Double = 0
            var queue: [ESISkillQueue] = []
            var skills: ESISkillsResponse?
            var loc: ESICharacterLocation?
            var ship: ESICharacterShip?
            var online: ESICharacterOnline?
            var contracts: [ESIContract] = []
            var industry: [ESIIndustryJob] = []
            var colonies: [ESIColony] = []
            var journal: [ESIWalletJournalEntry] = []
            var firstFieldError: Error? = nil

            do { wallet = try await ESIClient.shared.fetch("/characters/\(charID)/wallet/", token: token) } catch { if firstFieldError == nil { firstFieldError = error } }
            do { queue = try await ESIClient.shared.fetch("/characters/\(charID)/skillqueue/", token: token) } catch { if firstFieldError == nil { firstFieldError = error } }
            do { skills = try await ESIClient.shared.fetch("/characters/\(charID)/skills/", token: token) } catch { if firstFieldError == nil { firstFieldError = error } }
            do { loc = try await ESIClient.shared.fetch("/characters/\(charID)/location/", token: token) } catch { if firstFieldError == nil { firstFieldError = error } }
            do { ship = try await ESIClient.shared.fetch("/characters/\(charID)/ship/", token: token) } catch { if firstFieldError == nil { firstFieldError = error } }
            do { online = try await ESIClient.shared.fetch("/characters/\(charID)/online/", token: token) } catch { if firstFieldError == nil { firstFieldError = error } }
            do { contracts = try await ESIClient.shared.fetch("/characters/\(charID)/contracts/", token: token) } catch { if firstFieldError == nil { firstFieldError = error } }
            do { industry = try await ESIClient.shared.fetch("/characters/\(charID)/industry/jobs/", token: token) } catch { if firstFieldError == nil { firstFieldError = error } }
            do { colonies = try await ESIClient.shared.fetch("/characters/\(charID)/planets/", token: token) } catch { if firstFieldError == nil { firstFieldError = error } }
            do { journal = try await ESIClient.shared.fetch("/characters/\(charID)/wallet/journal/", token: token) } catch { if firstFieldError == nil { firstFieldError = error } }

            if let err = firstFieldError {
                s.loadError = err.localizedDescription
            }

            s.wallet = wallet
            s.totalSP = skills?.totalSp ?? 0
            s.online = online?.online ?? false
            s.ship = ship
            s.location = loc
            let daily = journal.todayISKSummary
            s.dailyISKMade = daily.made
            s.dailyISKSpent = daily.spent

            let activeQueue = queue.filter { $0.finishDate ?? .distantPast > Date() }
            s.skillQueueCount = activeQueue.count
            s.currentSkillFinish = activeQueue.first?.finishDate
            s.queueEnd = activeQueue.last?.finishDate
            if let first = activeQueue.first { s.trainingSkillID = first.skillId }
            s.isQueueEmpty = activeQueue.isEmpty

            s.activeContractCount = contracts.filter({ $0.status == "outstanding" || $0.status == "in_progress" }).count

            let activeJobs = industry.filter { $0.status == "active" }
            s.activeIndustryJobCount = activeJobs.count
            s.nextJobFinish = activeJobs.map(\.endDate).min()

            s.colonyCount = colonies.count
            for colony in colonies {
                do {
                    let layout: ESIColonyLayout = try await ESIClient.shared.fetch(
                        "/characters/\(charID)/planets/\(colony.planetId)/", token: token
                    )
                    s.expiredExtractorCount += layout.pins.filter { pin in
                        pin.extractorDetails != nil && (pin.expiryTime ?? .distantPast) < Date()
                    }.count
                } catch {
                    logSuppressed(error, "MenuBar: colony \(colony.planetId) layout", category: Logger.prefetch)
                }
            }

            if let sysId = loc?.solarSystemId {
                if let sysInfo = await UniverseCache.shared.solarSystem(id: sysId) {
                    s.systemName = sysInfo.name
                    s.securityStatus = sysInfo.securityStatus
                }
            }
            if let shipId = ship?.shipTypeId {
                if let typeInfo = await UniverseCache.shared.type(id: shipId) {
                    s.shipTypeName = typeInfo.name
                }
            }
            if let skillID = s.trainingSkillID {
                let resolved = await NameResolver.shared.resolve(ids: [skillID])
                s.trainingSkillName = resolved[skillID]
            }

            // Fetch corp/alliance name bypassing all caches to get the current corp ID from ESI
            if let charInfo: ESICharacterPublic = try? await ESIClient.shared.fetch("/characters/\(charID)/", bypassCache: true) {
                if let corpInfo: ESICorporationPublic = try? await ESIClient.shared.fetch("/corporations/\(charInfo.corporationId)/", bypassCache: true) {
                    s.corporationName = corpInfo.name
                }
                if let allianceId = charInfo.allianceId,
                   let allianceInfo: ESIAlliancePublic = try? await ESIClient.shared.fetch("/alliances/\(allianceId)/", bypassCache: true) {
                    s.allianceName = allianceInfo.name
                }
            }
        } catch {
            s.loadError = error.localizedDescription
        }

        return s
    }
}

/// A non-selected pilot in the menu bar popover: portrait, name, one-line status (what
/// they're training, or what needs attention) and wallet — so the popover doubles as an
/// at-a-glance check on every character, not just the selected one.
private struct PilotSwitcherRow: View {
    let account: StoredAccount
    let summary: CharacterSummary?
    let accent: Color
    let onSelect: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: EVESpacing.md + 2) {
                CachedAsyncImage(url: EVEImageURL.characterPortrait(account.characterID, size: 64)) { image in
                    image.resizable()
                } placeholder: {
                    Circle().fill(.quaternary)
                }
                .frame(width: 28, height: 28)
                .clipShape(Circle())
                .overlay(alignment: .bottomTrailing) {
                    if summary?.online == true {
                        Circle().fill(.green)
                            .frame(width: 8, height: 8)
                            .overlay(Circle().strokeBorder(.background, lineWidth: 1.5))
                            .offset(x: 1, y: 1)
                    }
                }

                VStack(alignment: .leading, spacing: 1) {
                    Text(account.characterName)
                        .font(.callout.weight(.medium))
                        .lineLimit(1)
                    status
                        .font(.caption)
                        .lineLimit(1)
                }

                Spacer(minLength: EVESpacing.sm)

                if let wallet = summary?.wallet {
                    Text(EVEFormatters.formatISKShort(wallet))
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, EVESpacing.md)
            .padding(.vertical, EVESpacing.sm)
            .background(
                RoundedRectangle(cornerRadius: EVERadius.md)
                    .fill(isHovering ? accent.opacity(0.12) : .clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .animation(.easeOut(duration: 0.12), value: isHovering)
        .help("Switch to \(account.characterName)")
    }

    @ViewBuilder
    private var status: some View {
        if let s = summary {
            if s.expiredExtractorCount > 0 {
                Label("\(s.expiredExtractorCount) extractors offline", systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.red)
            } else if s.isQueueEmpty && s.totalSP > 0 {
                Label("Skill queue empty", systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
            } else if let name = s.trainingSkillName, let finish = s.currentSkillFinish {
                Text("\(name) · \(EVEFormatters.timeUntil(finish))")
                    .foregroundStyle(.secondary)
            } else {
                Text(s.systemName.isEmpty ? "" : s.systemName)
                    .foregroundStyle(.secondary)
            }
        } else {
            Text("Loading…").foregroundStyle(.tertiary)
        }
    }
}
