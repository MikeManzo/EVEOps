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
import Charts
import OSLog

struct DashboardView: View {
    @Environment(AccountManager.self) private var accountManager
    @Environment(DashboardPrefetcher.self) private var prefetcher
    @Environment(APIStatusMonitor.self) private var apiStatus
    @State private var summaries: [CharacterSummary] = []
    @State private var isLoading = false
    @AppStorage("backgroundPollInterval") private var pollInterval: Double = 300
    @State private var contactSummaries: [ContactSummary] = []
    @AppStorage("dashboard.contacts.playersExpanded") private var playersExpanded = true
    @AppStorage("dashboard.contacts.npcsExpanded")    private var npcsExpanded = true
    @AppStorage("dashboard.contacts.orgsExpanded")    private var orgsExpanded = true
    @State private var newsItems: [EVENewsItem] = []
    @State private var newsIsLoading = true
    @AppStorage("dashboard.news.expanded") private var newsExpanded = true
    @AppStorage("dashboard.news.readIDs") private var readIDsRaw = ""
    @AppStorage("dashboard.serverStatus.expanded") private var serverStatusExpanded = true

    private var readIDs: Binding<Set<String>> {
        Binding(
            get: { Set(self.readIDsRaw.components(separatedBy: ",").filter { !$0.isEmpty }) },
            set: { self.readIDsRaw = Array($0).joined(separator: ",") }
        )
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("Dashboard")
                    .font(.largeTitle.bold())
                    .padding(.horizontal)

                // Character hero cards — full-width split layout
                let columns = [GridItem(.adaptive(minimum: 340, maximum: 480), spacing: 16)]
                LazyVGrid(columns: [GridItem(.flexible())], spacing: 16) {
                    ForEach(accountManager.accounts, id: \.characterID) { account in
                        CharacterHeroView(
                            account: account,
                            summary: summaries.first { $0.characterID == account.characterID }
                        )
                    }
                }
                .padding(.horizontal)

                ServerStatusWidgetView(isExpanded: $serverStatusExpanded)
                    .padding(.horizontal)

                EVENewsWidgetView(items: newsItems, isLoading: newsIsLoading, isExpanded: $newsExpanded, readIDs: readIDs)

                // Contacts — split into Players, NPCs, Organizations
                let playerContacts = contactSummaries.filter { $0.isPlayerCharacter }
                let npcContacts    = contactSummaries.filter { $0.contactType == "character" && !$0.isPlayerCharacter }
                let orgContacts    = contactSummaries.filter { $0.contactType != "character" }

                // #8: Styled collapsible section headers
                if !playerContacts.isEmpty {
                    contactSection(
                        icon: "person.2.fill", color: .blue,
                        title: "Players", count: playerContacts.count,
                        isExpanded: $playersExpanded,
                        contacts: playerContacts, columns: columns
                    )
                }
                if !npcContacts.isEmpty {
                    contactSection(
                        icon: "cpu", color: .indigo,
                        title: "NPCs", count: npcContacts.count,
                        isExpanded: $npcsExpanded,
                        contacts: npcContacts, columns: columns
                    )
                }
                if !orgContacts.isEmpty {
                    contactSection(
                        icon: "building.2.fill", color: .teal,
                        title: "Organizations", count: orgContacts.count,
                        isExpanded: $orgsExpanded,
                        contacts: orgContacts, columns: columns
                    )
                }
            }
            .padding(.vertical)
        }
        .overlay {
            if !apiStatus.isReachable && summaries.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "wifi.exclamationmark")
                        .font(.largeTitle)
                        .foregroundStyle(.orange)
                    Text(apiStatus.statusMessage.isEmpty ? "Unable to reach EVE servers" : apiStatus.statusMessage)
                        .font(.headline)
                    Text("Data will refresh automatically when the connection is restored.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
            } else if isLoading && summaries.isEmpty {
                ProgressView("Loading dashboard...")
            }
        }
        .task {
            if !buildFromPrefetcher() {
                isLoading = true
                await loadAllSummaries()
            }
            await refreshQueueFromESI()
            await loadContacts()
            await loadNews()
        }
        .task(id: "queuePoll") {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(pollInterval))
                await refreshQueueFromESI()
            }
        }
    }

    // #8: Reusable styled collapsible contact section header
    @ViewBuilder
    private func contactSection(
        icon: String,
        color: Color,
        title: String,
        count: Int,
        isExpanded: Binding<Bool>,
        contacts: [ContactSummary],
        columns: [GridItem]
    ) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                isExpanded.wrappedValue.toggle()
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: icon)
                        .foregroundStyle(color)
                        .font(.callout)
                    Text(title)
                        .font(.title3.bold())
                    Text("(\(count))")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Image(systemName: isExpanded.wrappedValue ? "chevron.down" : "chevron.right")
                        .font(.caption.bold())
                        .foregroundStyle(.tertiary)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(color.opacity(0.07), in: RoundedRectangle(cornerRadius: 10))
                .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(color.opacity(0.15), lineWidth: 1))
            }
            .buttonStyle(.plain)

            if isExpanded.wrappedValue {
                LazyVGrid(columns: columns, spacing: 16) {
                    ForEach(contacts) { contact in
                        ContactCardView(contact: contact)
                    }
                }
                .padding(.top, 12)
            }
        }
        .padding(.horizontal)
    }

    /// Build summaries synchronously from prefetcher data. Returns true if all accounts had data.
    private func buildFromPrefetcher() -> Bool {
        var built: [CharacterSummary] = []
        for account in accountManager.accounts {
            guard let prefetched = prefetcher.data(for: account.characterID) else { return false }
            var s = CharacterSummary(characterID: account.characterID)
            s.wallet = prefetched.wallet
            s.totalSP = prefetched.skills.totalSp
            s.online = prefetched.online.online
            s.ship = prefetched.ship
            s.location = prefetched.location
            let daily = prefetched.journal.todayISKSummary
            s.dailyISKMade = daily.made
            s.dailyISKSpent = daily.spent

            let sortedQueue = prefetched.skillQueue.sorted { $0.queuePosition < $1.queuePosition }
            let activeQueue = sortedQueue.filter { $0.finishDate ?? .distantPast > Date() }
            let currentlyTraining = activeQueue.first {
                ($0.startDate ?? .distantFuture) <= Date() && ($0.finishDate ?? .distantPast) > Date()
            } ?? activeQueue.first
            s.skillQueueCount = activeQueue.count
            s.currentSkillFinish = currentlyTraining?.finishDate
            s.currentSkillStart = currentlyTraining?.startDate
            s.queueEnd = activeQueue.last?.finishDate
            if let current = currentlyTraining {
                s.trainingSkillID = current.skillId
                s.trainingSkillLevel = current.finishedLevel
            }
            s.isQueueEmpty = activeQueue.isEmpty

            s.activeContractCount = prefetched.contracts.filter { $0.status == "outstanding" || $0.status == "in_progress" }.count

            let activeJobs = prefetched.industryJobs.filter { $0.status == "active" }
            s.activeIndustryJobCount = activeJobs.count
            s.nextJobFinish = activeJobs.map(\.endDate).min()
            s.colonyCount = prefetched.colonies.count

            if let sysInfo = prefetcher.resolvedSystems[prefetched.location.solarSystemId] {
                s.systemName = sysInfo.name
                s.securityStatus = sysInfo.securityStatus
                if let constInfo = prefetcher.resolvedConstellations[sysInfo.constellationId] {
                    s.regionName = prefetcher.resolvedRegions[constInfo.regionId]?.name
                }
            }
            if let typeInfo = prefetcher.resolvedTypes[prefetched.ship.shipTypeId] {
                s.shipTypeName = typeInfo.name
            }
            if let skillID = s.trainingSkillID {
                s.trainingSkillName = prefetcher.resolvedNames[skillID]
            }

            s.corporationName = prefetched.corporationName
            s.allianceName = prefetched.allianceName

            built.append(s)
        }
        summaries = built
        return true
    }

    private func loadAllSummaries() async {
        isLoading = true
        await withTaskGroup(of: CharacterSummary.self) { group in
            for account in accountManager.accounts {
                group.addTask {
                    await self.loadSummary(for: account)
                }
            }
            for await summary in group {
                summaries.removeAll { $0.characterID == summary.characterID }
                summaries.append(summary)
            }
        }
        isLoading = false
    }

    private func loadSummary(for account: StoredAccount) async -> CharacterSummary {
        var summary = CharacterSummary(characterID: account.characterID)

        if let prefetched = prefetcher.data(for: account.characterID) {
            return await buildSummary(from: prefetched, for: account)
        }

        do {
            let token = try await accountManager.validToken(for: account)

            async let fetchWallet: Double = ESIClient.shared.fetch(
                "/characters/\(account.characterID)/wallet/", token: token
            )
            async let fetchQueue: [ESISkillQueue] = ESIClient.shared.fetch(
                "/characters/\(account.characterID)/skillqueue/", token: token
            )
            async let fetchSkills: ESISkillsResponse = ESIClient.shared.fetch(
                "/characters/\(account.characterID)/skills/", token: token
            )
            async let fetchLocation: ESICharacterLocation = ESIClient.shared.fetch(
                "/characters/\(account.characterID)/location/", token: token
            )
            async let fetchShip: ESICharacterShip = ESIClient.shared.fetch(
                "/characters/\(account.characterID)/ship/", token: token
            )
            async let fetchOnline: ESICharacterOnline = ESIClient.shared.fetch(
                "/characters/\(account.characterID)/online/", token: token
            )
            async let fetchContracts: [ESIContract] = ESIClient.shared.fetch(
                "/characters/\(account.characterID)/contracts/", token: token
            )
            async let fetchIndustry: [ESIIndustryJob] = ESIClient.shared.fetch(
                "/characters/\(account.characterID)/industry/jobs/", token: token
            )
            async let fetchColonies: [ESIColony] = ESIClient.shared.fetch(
                "/characters/\(account.characterID)/planets/", token: token
            )
            async let fetchJournal: [ESIWalletJournalEntry] = ESIClient.shared.fetch(
                "/characters/\(account.characterID)/wallet/journal/", token: token
            )

            let (wallet, queue, skills, loc, ship, online) = try await (
                fetchWallet, fetchQueue, fetchSkills, fetchLocation, fetchShip, fetchOnline
            )
            let contracts = (try? await fetchContracts) ?? []
            let industry  = (try? await fetchIndustry) ?? []
            let colonies  = (try? await fetchColonies) ?? []
            let journal   = (try? await fetchJournal) ?? []

            summary.wallet = wallet
            summary.totalSP = skills.totalSp
            summary.online = online.online
            summary.ship = ship
            summary.location = loc
            let daily = journal.todayISKSummary
            summary.dailyISKMade = daily.made
            summary.dailyISKSpent = daily.spent

            let sortedQueue = queue.sorted { $0.queuePosition < $1.queuePosition }
            let activeQueue = sortedQueue.filter { $0.finishDate ?? .distantPast > Date() }
            let currentlyTraining = activeQueue.first {
                ($0.startDate ?? .distantFuture) <= Date() && ($0.finishDate ?? .distantPast) > Date()
            } ?? activeQueue.first
            summary.skillQueueCount = activeQueue.count
            summary.currentSkillFinish = currentlyTraining?.finishDate
            summary.currentSkillStart = currentlyTraining?.startDate
            summary.queueEnd = activeQueue.last?.finishDate
            if let current = currentlyTraining {
                summary.trainingSkillID = current.skillId
                summary.trainingSkillLevel = current.finishedLevel
            }
            summary.isQueueEmpty = activeQueue.isEmpty

            let activeContracts = contracts.filter { $0.status == "outstanding" || $0.status == "in_progress" }
            summary.activeContractCount = activeContracts.count

            let activeJobs = industry.filter { $0.status == "active" }
            summary.activeIndustryJobCount = activeJobs.count
            summary.nextJobFinish = activeJobs.map(\.endDate).min()

            summary.colonyCount = colonies.count
            for colony in colonies {
                do {
                    let layout: ESIColonyLayout = try await ESIClient.shared.fetch(
                        "/characters/\(account.characterID)/planets/\(colony.planetId)/", token: token
                    )
                    let expiredExtractors = layout.pins.filter { pin in
                        pin.extractorDetails != nil && (pin.expiryTime ?? .distantPast) < Date()
                    }
                    summary.expiredExtractorCount += expiredExtractors.count
                } catch {
                    logSuppressed(error, "Dashboard: colony \(colony.planetId) layout", category: Logger.prefetch)
                }
            }

            if let sysInfo = await UniverseCache.shared.solarSystem(id: loc.solarSystemId) {
                summary.systemName = sysInfo.name
                summary.securityStatus = sysInfo.securityStatus
                if let constInfo = await UniverseCache.shared.constellation(id: sysInfo.constellationId) {
                    summary.regionName = await UniverseCache.shared.region(id: constInfo.regionId)?.name
                }
            }
            if let typeInfo = await UniverseCache.shared.type(id: ship.shipTypeId) {
                summary.shipTypeName = typeInfo.name
            }
            if let skillID = summary.trainingSkillID {
                let resolved = await NameResolver.shared.resolve(ids: [skillID])
                summary.trainingSkillName = resolved[skillID]
            }
        } catch {
            summary.loadError = error.localizedDescription
        }
        return summary
    }

    private func loadContacts() async {
        let ourIDs = Set(accountManager.accounts.map { $0.characterID })

        var tokenMap: [Int: String] = [:]
        for account in accountManager.accounts {
            if let token = try? await accountManager.validToken(for: account) {
                tokenMap[account.characterID] = token
            }
        }
        guard !tokenMap.isEmpty else { return }

        var labelsByAccount: [Int: [Int: String]] = [:]
        for (charID, token) in tokenMap {
            let labels: [ESIContactLabel] = (try? await ESIClient.shared.fetch(
                "/characters/\(charID)/contacts/labels/", token: token
            )) ?? []
            labelsByAccount[charID] = Dictionary(uniqueKeysWithValues: labels.map { ($0.labelId, $0.labelName) })
        }

        var rawContacts: [(contact: ESIContact, sourceCharID: Int)] = []
        var seenIDs = Set<Int>()
        for (charID, token) in tokenMap {
            let contacts: [ESIContact] = (try? await ESIClient.shared.fetchPages(
                "/characters/\(charID)/contacts/", token: token
            )) ?? []
            for contact in contacts {
                guard !(contact.contactType == "character" && ourIDs.contains(contact.contactId)),
                      !seenIDs.contains(contact.contactId) else { continue }
                seenIDs.insert(contact.contactId)
                rawContacts.append((contact: contact, sourceCharID: charID))
            }
        }

        guard !rawContacts.isEmpty else { return }
        rawContacts.sort { $0.contact.standing > $1.contact.standing }

        var summaries = rawContacts.map { raw -> ContactSummary in
            let labelMap = labelsByAccount[raw.sourceCharID] ?? [:]
            let labelNames = (raw.contact.labelIds ?? []).compactMap { labelMap[$0] }
            return ContactSummary(
                contactID: raw.contact.contactId,
                contactType: raw.contact.contactType,
                standing: raw.contact.standing,
                isWatched: raw.contact.isWatched ?? false,
                isBlocked: raw.contact.isBlocked ?? false,
                labelNames: labelNames
            )
        }
        contactSummaries = summaries

        let nonCharIndices = summaries.indices.filter { summaries[$0].contactType != "character" }
        if !nonCharIndices.isEmpty {
            let ids = nonCharIndices.map { summaries[$0].contactID }
            let resolved = await NameResolver.shared.resolve(ids: ids)
            for i in nonCharIndices {
                summaries[i].name = resolved[summaries[i].contactID] ?? ""
            }
            contactSummaries = summaries
        }

        let charIndices = summaries.indices.filter { summaries[$0].contactType == "character" }
        for i in charIndices {
            let contactID = summaries[i].contactID
            if let info: ESICharacterPublic = try? await ESIClient.shared.fetch("/characters/\(contactID)/") {
                summaries[i].name = info.name
                summaries[i].corporationID = info.corporationId
                summaries[i].allianceID = info.allianceId
                summaries[i].securityStatus = info.securityStatus
                summaries[i].title = info.title
            }
        }

        var corpAllianceIDs: [Int] = []
        for i in charIndices {
            if let id = summaries[i].corporationID { corpAllianceIDs.append(id) }
            if let id = summaries[i].allianceID { corpAllianceIDs.append(id) }
        }
        if !corpAllianceIDs.isEmpty {
            let resolved = await NameResolver.shared.resolve(ids: corpAllianceIDs)
            for i in charIndices {
                if let corpID = summaries[i].corporationID {
                    summaries[i].corporationName = resolved[corpID] ?? ""
                }
                if let allianceID = summaries[i].allianceID {
                    summaries[i].allianceName = resolved[allianceID]
                }
            }
        }

        contactSummaries = summaries
    }

    private func loadNews() async {
        newsIsLoading = true
        newsItems = (try? await EVENewsClient.shared.fetchNews()) ?? []
        newsIsLoading = false
    }

    /// Fetches the skill queue directly from ESI (bypassing the prefetcher cache) and patches
    /// the training fields in each summary — exactly the way TrainingOverviewView.loadTraining() works.
    private func refreshQueueFromESI() async {
        await withTaskGroup(of: (Int, ESISkillQueue?, Date?, Date?, Date?, Int, Int?, String?, Bool).self) { group in
            for account in accountManager.accounts {
                group.addTask {
                    guard let token = try? await self.accountManager.validToken(for: account),
                          let queue: [ESISkillQueue] = try? await ESIClient.shared.fetch(
                              "/characters/\(account.characterID)/skillqueue/",
                              token: token,
                              bypassCache: true
                          )
                    else {
                        return (account.characterID, nil, nil, nil, nil, 0, nil, nil, true)
                    }

                    let sorted = queue.sorted { $0.queuePosition < $1.queuePosition }
                    let active = sorted.filter { $0.finishDate ?? .distantPast > Date() }
                    let current = active.first {
                        ($0.startDate ?? .distantFuture) <= Date() && ($0.finishDate ?? .distantPast) > Date()
                    } ?? active.first

                    var skillName: String? = nil
                    if let skillID = current?.skillId {
                        let resolved = await NameResolver.shared.resolve(ids: [skillID])
                        skillName = resolved[skillID]
                    }

                    return (
                        account.characterID,
                        current,
                        current?.startDate,
                        current?.finishDate,
                        active.last?.finishDate,
                        active.count,
                        current?.finishedLevel,
                        skillName,
                        active.isEmpty
                    )
                }
            }

            for await (charID, current, start, finish, queueEnd, count, level, name, isEmpty) in group {
                guard let idx = summaries.firstIndex(where: { $0.characterID == charID }) else { continue }
                summaries[idx].trainingSkillID = current?.skillId
                summaries[idx].trainingSkillName = name
                summaries[idx].trainingSkillLevel = level
                summaries[idx].currentSkillStart = start
                summaries[idx].currentSkillFinish = finish
                summaries[idx].queueEnd = queueEnd
                summaries[idx].skillQueueCount = count
                summaries[idx].isQueueEmpty = isEmpty
            }
        }
    }

    private nonisolated func buildSummary(from prefetched: DashboardPrefetcher.PrefetchedCharacterData, for account: StoredAccount) async -> CharacterSummary {
        var summary = CharacterSummary(characterID: account.characterID)
        summary.wallet = prefetched.wallet
        summary.totalSP = prefetched.skills.totalSp
        summary.online = prefetched.online.online
        summary.ship = prefetched.ship
        summary.location = prefetched.location
        let daily = prefetched.journal.todayISKSummary
        summary.dailyISKMade = daily.made
        summary.dailyISKSpent = daily.spent

        let sortedQueue = prefetched.skillQueue.sorted { $0.queuePosition < $1.queuePosition }
        let activeQueue = sortedQueue.filter { $0.finishDate ?? .distantPast > Date() }
        let currentlyTraining = activeQueue.first {
            ($0.startDate ?? .distantFuture) <= Date() && ($0.finishDate ?? .distantPast) > Date()
        } ?? activeQueue.first
        summary.skillQueueCount = activeQueue.count
        summary.currentSkillFinish = currentlyTraining?.finishDate
        summary.currentSkillStart = currentlyTraining?.startDate
        summary.queueEnd = activeQueue.last?.finishDate
        if let current = currentlyTraining {
            summary.trainingSkillID = current.skillId
            summary.trainingSkillLevel = current.finishedLevel
        }
        summary.isQueueEmpty = activeQueue.isEmpty

        let activeContracts = prefetched.contracts.filter { $0.status == "outstanding" || $0.status == "in_progress" }
        summary.activeContractCount = activeContracts.count

        let activeJobs = prefetched.industryJobs.filter { $0.status == "active" }
        summary.activeIndustryJobCount = activeJobs.count
        summary.nextJobFinish = activeJobs.map(\.endDate).min()

        summary.colonyCount = prefetched.colonies.count

        if !prefetched.colonies.isEmpty, !account.isTokenExpired {
            let token = account.accessToken
            for colony in prefetched.colonies {
                if let layout: ESIColonyLayout = try? await ESIClient.shared.fetch(
                    "/characters/\(account.characterID)/planets/\(colony.planetId)/", token: token
                ) {
                    let expired = layout.pins.filter { $0.extractorDetails != nil && ($0.expiryTime ?? .distantPast) < Date() }
                    summary.expiredExtractorCount += expired.count
                }
            }
        }

        if let sysInfo = await UniverseCache.shared.solarSystem(id: prefetched.location.solarSystemId) {
            summary.systemName = sysInfo.name
            summary.securityStatus = sysInfo.securityStatus
            if let constInfo = await UniverseCache.shared.constellation(id: sysInfo.constellationId) {
                summary.regionName = await UniverseCache.shared.region(id: constInfo.regionId)?.name
            }
        }
        if let typeInfo = await UniverseCache.shared.type(id: prefetched.ship.shipTypeId) {
            summary.shipTypeName = typeInfo.name
        }
        if let skillID = summary.trainingSkillID {
            let resolved = await NameResolver.shared.resolve(ids: [skillID])
            summary.trainingSkillName = resolved[skillID]
        }

        summary.corporationName = prefetched.corporationName
        summary.allianceName = prefetched.allianceName

        return summary
    }
}

// Mark:  Summary Data

struct CharacterSummary {
    let characterID: Int
    var wallet: Double = 0
    var totalSP: Int = 0
    var online: Bool = false
    var ship: ESICharacterShip?
    var shipTypeName: String = ""
    var location: ESICharacterLocation?
    var systemName: String = ""
    var regionName: String? = nil
    var securityStatus: Double?
    var skillQueueCount: Int = 0
    var currentSkillFinish: Date?
    var currentSkillStart: Date?
    var queueEnd: Date?
    var trainingSkillID: Int?
    var trainingSkillName: String?
    var trainingSkillLevel: Int? = nil
    var isQueueEmpty: Bool = true
    var activeContractCount: Int = 0
    var activeIndustryJobCount: Int = 0
    var nextJobFinish: Date?
    var colonyCount: Int = 0
    var expiredExtractorCount: Int = 0
    var corporationName: String = ""
    var allianceName: String? = nil
    var loadError: String? = nil
    var dailyISKMade: Double = 0
    var dailyISKSpent: Double = 0
    var dailyISKNet: Double { dailyISKMade - dailyISKSpent }
}

// Mark:  Contact Summary

struct ContactSummary: Identifiable {
    let contactID: Int
    var id: Int { contactID }
    var contactType: String = "character"
    var name: String = ""
    var corporationID: Int?
    var corporationName: String = ""
    var allianceID: Int?
    var allianceName: String?
    var standing: Double = 0
    var securityStatus: Double? = nil
    var isWatched: Bool = false
    var isBlocked: Bool = false
    var labelNames: [String] = []
    var title: String? = nil

    var isPlayerCharacter: Bool { contactType == "character" && contactID >= 90_000_000 }

    var imageURL: URL? {
        switch contactType {
        case "character":   return EVEImageURL.characterPortrait(contactID, size: 512)
        case "corporation": return EVEImageURL.corporationLogo(contactID, size: 256)
        case "alliance":    return EVEImageURL.allianceLogo(contactID, size: 256)
        case "faction":     return EVEImageURL.corporationLogo(contactID, size: 256)
        default:            return nil
        }
    }

    var bannerLogoURL: URL? {
        switch contactType {
        case "character":
            guard let id = corporationID else { return nil }
            return EVEImageURL.corporationLogo(id, size: 256)
        case "corporation":
            guard let id = allianceID else { return nil }
            return EVEImageURL.allianceLogo(id, size: 256)
        default:
            return nil
        }
    }
}
