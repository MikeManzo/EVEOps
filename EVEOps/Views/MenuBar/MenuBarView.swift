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

struct MenuBarView: View {
    @Environment(AccountManager.self) private var accountManager
    @Environment(DashboardPrefetcher.self) private var prefetcher
    @Environment(APIStatusMonitor.self) private var apiStatus
    @Environment(AppUpdater.self) private var appUpdater
    @AppStorage("backgroundPollInterval") private var pollInterval: Double = 300
    @State private var summaries: [Int: CharacterSummary] = [:]
    @State private var isLoading = false

    private var selectedSummary: CharacterSummary? {
        guard let id = accountManager.selectedCharacterID else { return nil }
        return summaries[id]
    }

    var body: some View {
        VStack(spacing: 0) {
            if appUpdater.updateAvailable {
                Button {
                    appUpdater.checkForUpdates()
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "arrow.down.circle.fill")
                            .foregroundStyle(.blue)
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
                            .font(.caption2)
                            .foregroundStyle(.blue)
                    }
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(.blue.opacity(0.1))

                Divider()
            }

            if !apiStatus.isReachable {
                HStack(spacing: 6) {
                    Image(systemName: "wifi.exclamationmark")
                        .foregroundStyle(.orange)
                        .font(.caption)
                    Text(apiStatus.statusMessage.isEmpty ? "Unable to reach EVE servers" : apiStatus.statusMessage)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(.orange.opacity(0.1))

                Divider()
            }

            if let account = accountManager.selectedAccount {
                CharacterCardView(account: account, summary: selectedSummary)
                    .overlay {
                        if isLoading && selectedSummary == nil {
                            ProgressView()
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                                .background(.ultraThinMaterial)
                        }
                    }
            } else if accountManager.accounts.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "person.crop.circle.badge.plus")
                        .font(.title)
                        .foregroundStyle(.secondary)
                    Text("No characters added")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 24)
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

            ZStack {
                HStack {
                    Button {
                        NSApplication.shared.keyWindow?.close()
                        WindowService.shared.showMain()
                        NSApplication.shared.activate(ignoringOtherApps: true)
                    } label: {
                        Label("EVEOps", systemImage: "macwindow")
                    }
                    .buttonStyle(.plain)

                    Spacer()

                    Button {
                        NSApplication.shared.terminate(nil)
                    } label: {
                        Label("Quit", systemImage: "power")
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                }

                Button {
                    NSApplication.shared.keyWindow?.close()
                    WindowService.shared.showSettings()
                    NSApplication.shared.activate(ignoringOtherApps: true)
                } label: {
                    Label("Settings", systemImage: "gear")
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
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
        .task(id: pollInterval) {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(pollInterval))
                await loadAllSummaries()
            }
        }
        .onChange(of: prefetcher.lastRefresh) { _, _ in
            // Prefetcher was refreshed externally (e.g. "Refresh Now" in Settings) — sync immediately
            Task { await loadAllSummaries() }
        }
    }

    private var characterSwitcher: some View {
        VStack(spacing: 2) {
            ForEach(accountManager.accounts.filter({ $0.characterID != accountManager.selectedCharacterID }), id: \.characterID) { account in
                Button {
                    accountManager.selectedCharacterID = account.characterID
                } label: {
                    HStack(spacing: 8) {
                        AsyncImage(url: EVEImageURL.characterPortrait(account.characterID, size: 128)) { image in
                            image.resizable()
                        } placeholder: {
                            RoundedRectangle(cornerRadius: 4).fill(.quaternary)
                        }
                        .frame(width: 24, height: 24)
                        .clipShape(RoundedRectangle(cornerRadius: 4))

                        Text(account.characterName)
                            .font(.caption)

                        Spacer()

                        Text("Switch")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 4)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.vertical, 4)
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

            if let err = firstFieldError {
                s.loadError = err.localizedDescription
            }

            s.wallet = wallet
            s.totalSP = skills?.totalSp ?? 0
            s.online = online?.online ?? false
            s.ship = ship
            s.location = loc

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
                } catch {}
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
