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

struct DashboardView: View {
    @Environment(AccountManager.self) private var accountManager
    @Environment(DashboardPrefetcher.self) private var prefetcher
    @Environment(APIStatusMonitor.self) private var apiStatus
    @State private var summaries: [CharacterSummary] = []
    @State private var isLoading = false
    @State private var contactSummaries: [ContactSummary] = []
    @AppStorage("dashboard.contacts.playersExpanded") private var playersExpanded = true
    @AppStorage("dashboard.contacts.npcsExpanded")    private var npcsExpanded = true
    @AppStorage("dashboard.contacts.orgsExpanded")    private var orgsExpanded = true
    @State private var newsItems: [EVENewsItem] = []
    @State private var newsIsLoading = true
    @AppStorage("dashboard.news.expanded") private var newsExpanded = true

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("Dashboard")
                    .font(.largeTitle.bold())
                    .padding(.horizontal)

                // #6: Metric tile grid replacing the old horizontal summary bar
                if !summaries.isEmpty {
                    SummaryGridView(summaries: summaries)
                        .padding(.horizontal)
                }

                // Per-character cards
                let columns = [GridItem(.adaptive(minimum: 340, maximum: 480), spacing: 16)]
                LazyVGrid(columns: columns, spacing: 16) {
                    ForEach(accountManager.accounts, id: \.characterID) { account in
                        CharacterCardView(
                            account: account,
                            summary: summaries.first { $0.characterID == account.characterID }
                        )
                    }
                }
                .padding(.horizontal)

                EVENewsWidgetView(items: newsItems, isLoading: newsIsLoading, isExpanded: $newsExpanded)

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
            await loadContacts()
            await loadNews()
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

            let activeQueue = prefetched.skillQueue.filter { $0.finishDate ?? .distantPast > Date() }
            s.skillQueueCount = activeQueue.count
            s.currentSkillFinish = activeQueue.first?.finishDate
            s.currentSkillStart = activeQueue.first?.startDate
            s.queueEnd = activeQueue.last?.finishDate
            if let first = activeQueue.first { s.trainingSkillID = first.skillId }
            s.isQueueEmpty = activeQueue.isEmpty

            s.activeContractCount = prefetched.contracts.filter { $0.status == "outstanding" || $0.status == "in_progress" }.count

            let activeJobs = prefetched.industryJobs.filter { $0.status == "active" }
            s.activeIndustryJobCount = activeJobs.count
            s.nextJobFinish = activeJobs.map(\.endDate).min()
            s.colonyCount = prefetched.colonies.count

            if let sysInfo = prefetcher.resolvedSystems[prefetched.location.solarSystemId] {
                s.systemName = sysInfo.name
                s.securityStatus = sysInfo.securityStatus
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

            let (wallet, queue, skills, loc, ship, online) = try await (
                fetchWallet, fetchQueue, fetchSkills, fetchLocation, fetchShip, fetchOnline
            )
            let contracts = (try? await fetchContracts) ?? []
            let industry  = (try? await fetchIndustry) ?? []
            let colonies  = (try? await fetchColonies) ?? []

            summary.wallet = wallet
            summary.totalSP = skills.totalSp
            summary.online = online.online
            summary.ship = ship
            summary.location = loc

            let activeQueue = queue.filter { $0.finishDate ?? .distantPast > Date() }
            summary.skillQueueCount = activeQueue.count
            summary.currentSkillFinish = activeQueue.first?.finishDate
            summary.currentSkillStart = activeQueue.first?.startDate
            summary.queueEnd = activeQueue.last?.finishDate
            if let first = activeQueue.first {
                summary.trainingSkillID = first.skillId
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
                } catch {}
            }

            if let sysInfo = await UniverseCache.shared.solarSystem(id: loc.solarSystemId) {
                summary.systemName = sysInfo.name
                summary.securityStatus = sysInfo.securityStatus
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

    private nonisolated func buildSummary(from prefetched: DashboardPrefetcher.PrefetchedCharacterData, for account: StoredAccount) async -> CharacterSummary {
        var summary = CharacterSummary(characterID: account.characterID)
        summary.wallet = prefetched.wallet
        summary.totalSP = prefetched.skills.totalSp
        summary.online = prefetched.online.online
        summary.ship = prefetched.ship
        summary.location = prefetched.location

        let activeQueue = prefetched.skillQueue.filter { $0.finishDate ?? .distantPast > Date() }
        summary.skillQueueCount = activeQueue.count
        summary.currentSkillFinish = activeQueue.first?.finishDate
        summary.currentSkillStart = activeQueue.first?.startDate
        summary.queueEnd = activeQueue.last?.finishDate
        if let first = activeQueue.first {
            summary.trainingSkillID = first.skillId
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
    var securityStatus: Double?
    var skillQueueCount: Int = 0
    var currentSkillFinish: Date?
    var currentSkillStart: Date?
    var queueEnd: Date?
    var trainingSkillID: Int?
    var trainingSkillName: String?
    var isQueueEmpty: Bool = true
    var activeContractCount: Int = 0
    var activeIndustryJobCount: Int = 0
    var nextJobFinish: Date?
    var colonyCount: Int = 0
    var expiredExtractorCount: Int = 0
    var corporationName: String = ""
    var allianceName: String? = nil
    var loadError: String? = nil
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

// Mark:  Metric Tile Grid

struct SummaryGridView: View {
    let summaries: [CharacterSummary]

    private var totalWealth: Double    { summaries.reduce(0) { $0 + $1.wallet } }
    private var totalSP: Int           { summaries.reduce(0) { $0 + $1.totalSP } }
    private var emptyQueues: Int       { summaries.filter(\.isQueueEmpty).count }
    private var activeJobs: Int        { summaries.reduce(0) { $0 + $1.activeIndustryJobCount } }
    private var activeContracts: Int   { summaries.reduce(0) { $0 + $1.activeContractCount } }
    private var expiredExtractors: Int { summaries.reduce(0) { $0 + $1.expiredExtractorCount } }
    private var onlineCount: Int       { summaries.filter(\.online).count }
    private var nextSkillFinish: Date? { summaries.compactMap(\.currentSkillFinish).min() }
    private var nextJobFinish: Date?   { summaries.compactMap(\.nextJobFinish).min() }

    var body: some View {
        let columns = [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())]
        LazyVGrid(columns: columns, spacing: 8) {
            MetricTileView(
                icon: "creditcard.fill", color: .green,
                value: EVEFormatters.formatISKShort(totalWealth),
                label: "Total Wealth"
            )
            MetricTileView(
                icon: "brain.head.profile.fill", color: .cyan,
                value: formatSP(totalSP),
                label: "Skill Points"
            )
            MetricTileView(
                icon: "person.fill.checkmark", color: .blue,
                value: "\(onlineCount) / \(summaries.count)",
                label: onlineCount == summaries.count ? "All Online" : "Online"
            )
            // Training: show time remaining on current skill instead of a static count
            if emptyQueues > 0 {
                MetricTileView(
                    icon: "exclamationmark.triangle.fill", color: .orange,
                    value: "\(emptyQueues) empty",
                    label: "Queue Alert",
                    isAlert: true
                )
            } else if let finish = nextSkillFinish {
                MetricTileView(
                    icon: "graduationcap.fill", color: .green,
                    value: EVEFormatters.timeUntil(finish),
                    label: "Next Skill Done",
                    subLabel: "\(summaries.count == 1 ? "" : "\(summaries.count) queues · ")All training"
                )
            } else {
                MetricTileView(
                    icon: "graduationcap.fill", color: .green,
                    value: "All active",
                    label: "Training"
                )
            }
            // Industry: show time to next completion instead of a static count
            if activeJobs == 0 {
                MetricTileView(
                    icon: "hammer.fill", color: .secondary,
                    value: "None active",
                    label: "Industry"
                )
            } else if let next = nextJobFinish {
                MetricTileView(
                    icon: "hammer.fill", color: .purple,
                    value: EVEFormatters.timeUntil(next),
                    label: "Next Job Done",
                    subLabel: "\(activeJobs) job\(activeJobs == 1 ? "" : "s") active"
                )
            } else {
                MetricTileView(
                    icon: "hammer.fill", color: .purple,
                    value: "\(activeJobs) active",
                    label: "Industry"
                )
            }
            MetricTileView(
                icon: "doc.text.fill", color: .teal,
                value: activeContracts == 0 ? "None active" : "\(activeContracts) active",
                label: "Contracts"
            )
            if expiredExtractors > 0 {
                MetricTileView(
                    icon: "exclamationmark.triangle.fill", color: .red,
                    value: "\(expiredExtractors) offline",
                    label: "PI Extractors",
                    isAlert: true
                )
            }
        }
    }

    private func formatSP(_ sp: Int) -> String {
        if sp >= 1_000_000 { return String(format: "%.1fM", Double(sp) / 1_000_000) }
        if sp >= 1_000 { return String(format: "%.0fK", Double(sp) / 1_000) }
        return "\(sp)"
    }
}

struct MetricTileView: View {
    let icon: String
    let color: Color
    let value: String
    let label: String
    var subLabel: String? = nil
    var isAlert: Bool = false

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(color)
                .frame(width: 22, alignment: .center)

            VStack(alignment: .leading, spacing: 1) {
                Text(value)
                    .font(.subheadline.bold().monospacedDigit())
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Text(label)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                if let sub = subLabel {
                    Text(sub)
                        .font(.caption2)
                        .foregroundStyle(.secondary.opacity(0.65))
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(color.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(color.opacity(isAlert ? 0.45 : 0.15), lineWidth: 1)
        )
    }
}

// Mark:  Character Card

struct CharacterCardView: View {
    let account: StoredAccount
    let summary: CharacterSummary?

    @Environment(AccountManager.self) private var accountManager
    @Environment(APIStatusMonitor.self) private var apiStatus
    @Environment(DashboardPrefetcher.self) private var prefetcher

    @State private var liveCorpName: String?
    @State private var liveAllianceName: String?
    @State private var pulsing = false  // #4: drives the online pulse animation

    var body: some View {
        VStack(spacing: 0) {
            // #3: Status accent stripe — color signals state at a glance
            Rectangle()
                .fill(cardAccentColor)
                .frame(height: 3)

            // #1 + #2: Banner with gradient fade at bottom
            ZStack(alignment: .bottomTrailing) {
                Group {
                    if let ship = summary?.ship {
                        AsyncImage(url: EVEImageURL.typeRender(ship.shipTypeId, size: 1024)) { phase in
                            switch phase {
                            case .success(let image):
                                image
                                    .resizable()
                                    .aspectRatio(contentMode: .fill)
                                    .frame(height: 130)
                                    .clipped()
                            default:
                                bannerPlaceholder
                            }
                        }
                    } else {
                        bannerPlaceholder
                    }
                }

                // #2: Gradient vignette darkens the banner bottom for portrait overlap contrast
                LinearGradient(
                    colors: [.clear, Color.black.opacity(0.70)],
                    startPoint: .init(x: 0.5, y: 0.25),
                    endPoint: .bottom
                )
                .frame(height: 130)
                .allowsHitTesting(false)

                // Corp logo — slightly larger for visual weight
                AsyncImage(url: EVEImageURL.corporationLogo(account.corporationID, size: 256)) { phase in
                    if let image = phase.image {
                        image
                            .resizable()
                            .frame(width: 36, height: 36)
                            .clipShape(RoundedRectangle(cornerRadius: 5))
                            .shadow(color: .black.opacity(0.6), radius: 4)
                    }
                }
                .padding(8)
            }
            .frame(height: 130)

            // #1: Content pulled up to overlap the banner bottom
            VStack(alignment: .leading, spacing: 10) {
                // Identity row — portrait floats above the banner boundary
                HStack(spacing: 12) {
                    AsyncImage(url: EVEImageURL.characterPortrait(account.characterID, size: 512)) { image in
                        image.resizable()
                    } placeholder: {
                        RoundedRectangle(cornerRadius: 10).fill(.quaternary)
                    }
                    .frame(width: 60, height: 60)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(.white.opacity(0.18), lineWidth: 1))
                    .shadow(color: .black.opacity(0.55), radius: 7, y: 3)

                    VStack(alignment: .leading, spacing: 3) {
                        HStack(spacing: 6) {
                            Text(account.characterName)
                                .font(.headline)
                            Spacer()
                            onlineIndicator
                        }
                        Text(effectiveCorpName)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        if let name = effectiveAllianceName {
                            Text(name)
                                .font(.caption)
                                .foregroundStyle(.secondary.opacity(0.6))
                        }
                    }
                }

                Divider()

                // Location and ship
                HStack(spacing: 16) {
                    HStack(spacing: 6) {
                        Image(systemName: "mappin.circle.fill")
                            .foregroundStyle(.blue)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(summary?.systemName ?? "---")
                                .font(.caption)
                            if let sec = summary?.securityStatus {
                                Text(String(format: "%.1f", sec))
                                    .font(.caption2.monospacedDigit())
                                    .foregroundStyle(sec >= 0.5 ? .green : sec >= 0.0 ? .yellow : .red)
                            }
                        }
                    }

                    Spacer()

                    HStack(spacing: 6) {
                        if let ship = summary?.ship {
                            AsyncImage(url: EVEImageURL.typeIcon(ship.shipTypeId, size: 256)) { phase in
                                if let image = phase.image {
                                    image.resizable()
                                        .frame(width: 20, height: 20)
                                        .clipShape(RoundedRectangle(cornerRadius: 3))
                                } else {
                                    Image(systemName: "airplane")
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                        VStack(alignment: .trailing, spacing: 1) {
                            Text(summary?.ship?.shipName ?? "---")
                                .font(.caption)
                                .lineLimit(1)
                            Text(summary?.shipTypeName ?? "---")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }
                }

                Divider()

                // Wallet & SP
                HStack {
                    Label {
                        Text(EVEFormatters.formatISKShort(summary?.wallet ?? 0))
                            .font(.caption.monospacedDigit())
                    } icon: {
                        Image(systemName: "creditcard.fill")
                            .foregroundStyle(.green)
                            .font(.caption)
                    }

                    Spacer()

                    Label {
                        Text(formatSP(summary?.totalSP ?? 0))
                            .font(.caption.monospacedDigit())
                    } icon: {
                        Image(systemName: "brain.head.profile.fill")
                            .foregroundStyle(.cyan)
                            .font(.caption)
                    }
                }

                // #5: Skill queue with progress bar
                skillQueueRow

                // Industry & Contracts
                HStack {
                    if let s = summary, s.activeIndustryJobCount > 0 {
                        Label {
                            VStack(alignment: .leading, spacing: 1) {
                                Text("\(s.activeIndustryJobCount) job\(s.activeIndustryJobCount == 1 ? "" : "s")")
                                    .font(.caption)
                                if let next = s.nextJobFinish {
                                    Text("Next: \(EVEFormatters.timeUntil(next))")
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        } icon: {
                            Image(systemName: "hammer.fill")
                                .foregroundStyle(.purple)
                                .font(.caption)
                        }
                    } else {
                        Label {
                            Text("No jobs")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        } icon: {
                            Image(systemName: "hammer.fill")
                                .foregroundStyle(.secondary)
                                .font(.caption)
                        }
                    }

                    Spacer()

                    if let s = summary, s.activeContractCount > 0 {
                        Label {
                            Text("\(s.activeContractCount) active")
                                .font(.caption)
                        } icon: {
                            Image(systemName: "doc.text.fill")
                                .foregroundStyle(.teal)
                                .font(.caption)
                        }
                    } else {
                        Label {
                            Text("No contracts")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        } icon: {
                            Image(systemName: "doc.text.fill")
                                .foregroundStyle(.secondary)
                                .font(.caption)
                        }
                    }
                }

                // PI status
                if let s = summary, s.colonyCount > 0 {
                    HStack {
                        Label {
                            Text("\(s.colonyCount) colon\(s.colonyCount == 1 ? "y" : "ies")")
                                .font(.caption)
                        } icon: {
                            Image(systemName: "globe.americas.fill")
                                .foregroundStyle(.mint)
                                .font(.caption)
                        }

                        Spacer()

                        if s.expiredExtractorCount > 0 {
                            Label {
                                Text("\(s.expiredExtractorCount) offline")
                                    .font(.caption.bold())
                                    .foregroundStyle(.red)
                            } icon: {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .foregroundStyle(.red)
                                    .font(.caption)
                            }
                        } else {
                            Text("All running")
                                .font(.caption)
                                .foregroundStyle(.green)
                        }
                    }
                }

                // Load error banner — shown when the ESI fetch failed for this character
                if let err = summary?.loadError {
                    HStack(spacing: 6) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.caption2)
                            .foregroundStyle(.red)
                        Text(err)
                            .font(.caption2)
                            .foregroundStyle(.red.opacity(0.85))
                            .lineLimit(2)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(.red.opacity(0.08), in: RoundedRectangle(cornerRadius: 6))
                    .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(.red.opacity(0.2), lineWidth: 1))
                }
            }
            .padding(12)
            .padding(.top, -38)  // #1: portrait overlaps banner by ~28pt
        }
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .onAppear {
            Task { await fetchIdentity() }
            if summary?.online == true {
                withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true)) {
                    pulsing = true
                }
            }
        }
        .onChange(of: prefetcher.lastRefresh) { _, _ in Task { await fetchIdentity() } }
        .onChange(of: summary?.online) { _, online in
            if online == true {
                withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true)) {
                    pulsing = true
                }
            } else {
                withAnimation(.default) { pulsing = false }
            }
        }
    }

    // #3: Accent stripe color based on most critical state
    private var cardAccentColor: Color {
        guard let s = summary else { return Color(white: 0.25) }
        if s.loadError != nil { return .red }
        if s.expiredExtractorCount > 0 { return .red }
        if s.isQueueEmpty { return .orange }
        if s.online { return .green }
        return Color(white: 0.25)
    }

    // #4: Animated online indicator with pulsing glow
    @ViewBuilder
    private var onlineIndicator: some View {
        let isOnline = summary?.online == true
        HStack(spacing: 4) {
            ZStack {
                if isOnline {
                    Circle()
                        .fill(Color.green.opacity(0.35))
                        .frame(width: 16, height: 16)
                        .scaleEffect(pulsing ? 1.6 : 0.7)
                        .opacity(pulsing ? 0.0 : 0.5)
                        .animation(
                            .easeOut(duration: 0.9).repeatForever(autoreverses: false),
                            value: pulsing
                        )
                }
                Circle()
                    .fill(isOnline ? Color.green : Color.gray)
                    .frame(width: 8, height: 8)
                    .shadow(color: isOnline ? .green.opacity(0.7) : .clear, radius: 4)
            }
            Text(isOnline ? "Online" : "Offline")
                .font(.caption2)
                .foregroundStyle(isOnline ? .green : .secondary)
        }
    }

    private var effectiveCorpName: String {
        if let live = liveCorpName { return live }
        if let s = summary, !s.corporationName.isEmpty { return s.corporationName }
        return account.corporationName
    }

    private var effectiveAllianceName: String? {
        liveAllianceName ?? summary?.allianceName ?? account.allianceName
    }

    private func fetchIdentity() async {
        guard let charInfo: ESICharacterPublic = try? await ESIClient.shared.fetch(
            "/characters/\(account.characterID)/"
        ) else { return }
        if let corpInfo: ESICorporationPublic = try? await ESIClient.shared.fetch(
            "/corporations/\(charInfo.corporationId)/"
        ) {
            liveCorpName = corpInfo.name
        }
        if let allianceId = charInfo.allianceId,
           let allianceInfo: ESIAlliancePublic = try? await ESIClient.shared.fetch(
               "/alliances/\(allianceId)/"
           ) {
            liveAllianceName = allianceInfo.name
        } else {
            liveAllianceName = nil
        }
    }

    // #5: Skill queue row with training progress bar
    @ViewBuilder
    private var skillQueueRow: some View {
        if let s = summary {
            if s.isQueueEmpty {
                Label {
                    Text("Queue empty!")
                        .font(.caption.bold())
                        .foregroundStyle(.orange)
                } icon: {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                        .font(.caption)
                }
            } else {
                Label {
                    VStack(alignment: .leading, spacing: 3) {
                        HStack(spacing: 4) {
                            Text(s.trainingSkillName ?? "Training...")
                                .font(.caption)
                                .lineLimit(1)
                            if let finish = s.currentSkillFinish {
                                Spacer()
                                Text(EVEFormatters.timeUntil(finish))
                                    .font(.caption2.monospacedDigit())
                                    .foregroundStyle(.secondary)
                            }
                        }

                        // #5: Training progress bar
                        if let start = s.currentSkillStart, let finish = s.currentSkillFinish {
                            let total = finish.timeIntervalSince(start)
                            let progress = total > 0
                                ? min(1.0, max(0.0, Date().timeIntervalSince(start) / total))
                                : 0.0
                            ProgressView(value: progress)
                                .tint(.blue)
                                .frame(height: 3)
                        }

                        HStack(spacing: 4) {
                            Text("\(s.skillQueueCount) skill\(s.skillQueueCount == 1 ? "" : "s") in queue")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                            if let end = s.queueEnd {
                                Spacer()
                                Text("Ends: \(EVEFormatters.timeUntil(end))")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                } icon: {
                    Image(systemName: "graduationcap.fill")
                        .foregroundStyle(.blue)
                        .font(.caption)
                }
            }
        }
    }

    // #7: EVE-themed placeholder with subtle tech-grid aesthetic
    private var bannerPlaceholder: some View {
        ZStack {
            LinearGradient(
                colors: [Color(white: 0.09), Color(white: 0.04)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            Canvas { ctx, size in
                let spacing: CGFloat = 22
                var path = Path()
                var x: CGFloat = 0
                while x <= size.width {
                    path.move(to: CGPoint(x: x, y: 0))
                    path.addLine(to: CGPoint(x: x, y: size.height))
                    x += spacing
                }
                var y: CGFloat = 0
                while y <= size.height {
                    path.move(to: CGPoint(x: 0, y: y))
                    path.addLine(to: CGPoint(x: size.width, y: y))
                    y += spacing
                }
                ctx.stroke(path, with: .color(Color(red: 0, green: 0.75, blue: 1).opacity(0.07)), lineWidth: 0.5)
            }

            if !apiStatus.isReachable {
                VStack(spacing: 6) {
                    Image(systemName: "wifi.exclamationmark")
                        .font(.title2)
                        .foregroundStyle(.orange)
                    Text(apiStatus.statusMessage.isEmpty ? "No connection" : apiStatus.statusMessage)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 16)
                }
            } else if summary == nil {
                ProgressView().scaleEffect(0.7)
            }
        }
        .frame(height: 130)
    }

    private func formatSP(_ sp: Int) -> String {
        if sp >= 1_000_000 { return String(format: "%.1fM SP", Double(sp) / 1_000_000) }
        if sp >= 1_000 { return String(format: "%.0fK SP", Double(sp) / 1_000) }
        return "\(sp) SP"
    }
}

// Mark:  Contact Card

struct ContactCardView: View {
    let contact: ContactSummary
    @Environment(PresenceTracker.self) private var presenceTracker

    var body: some View {
        VStack(spacing: 0) {
            // Banner: standing-tinted gradient + overlay logo
            ZStack(alignment: .bottomTrailing) {
                LinearGradient(
                    colors: [standingColor.opacity(0.30), Color(white: 0.10)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .frame(height: 80)

                if let bannerURL = contact.bannerLogoURL {
                    AsyncImage(url: bannerURL) { phase in
                        if let image = phase.image {
                            image.resizable()
                                .frame(width: 32, height: 32)
                                .clipShape(RoundedRectangle(cornerRadius: 4))
                                .shadow(color: .black.opacity(0.5), radius: 3)
                        }
                    }
                    .padding(8)
                }
            }

            VStack(alignment: .leading, spacing: 10) {
                // Identity row
                HStack(spacing: 12) {
                    ZStack(alignment: .bottomTrailing) {
                        AsyncImage(url: contact.imageURL) { image in
                            image.resizable()
                        } placeholder: {
                            RoundedRectangle(cornerRadius: 8).fill(.quaternary)
                        }
                        .frame(width: 52, height: 52)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(.white.opacity(0.1), lineWidth: 1))

                        if contact.isPlayerCharacter {
                            PresenceBadge(score: presenceTracker.score(for: contact.contactID), size: 13)
                                .offset(x: 3, y: 3)
                        }
                    }

                    VStack(alignment: .leading, spacing: 3) {
                        HStack(spacing: 6) {
                            Text(contact.name.isEmpty ? "Loading..." : contact.name)
                                .font(.headline)
                            Spacer()
                            if let sec = contact.securityStatus {
                                Text(String(format: "%.1f", sec))
                                    .font(.caption2.monospacedDigit())
                                    .foregroundStyle(sec >= 0 ? .green : .red)
                            }
                        }
                        if let title = contact.title, !title.isEmpty {
                            Text(title)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                        if !contact.corporationName.isEmpty {
                            Text(contact.corporationName)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        if let alliance = contact.allianceName {
                            Text(alliance)
                                .font(.caption)
                                .foregroundStyle(.secondary.opacity(0.6))
                        }
                    }
                }

                Divider()

                // Type badge + flags + standing
                HStack(spacing: 8) {
                    Image(systemName: contactTypeIcon)
                        .foregroundStyle(.blue)
                        .font(.caption)
                    Text(contactTypeLabel)
                        .font(.caption.bold())
                        .foregroundStyle(.blue)

                    if contact.isWatched {
                        Image(systemName: "eye.fill")
                            .font(.caption)
                            .foregroundStyle(.orange)
                        Text("Watched")
                            .font(.caption2)
                            .foregroundStyle(.orange)
                    }

                    if contact.isBlocked {
                        Image(systemName: "slash.circle.fill")
                            .font(.caption)
                            .foregroundStyle(.red)
                        Text("Blocked")
                            .font(.caption2)
                            .foregroundStyle(.red)
                    }

                    Spacer()

                    HStack(spacing: 4) {
                        Image(systemName: standingIcon)
                            .foregroundStyle(standingColor)
                            .font(.caption)
                        Text(String(format: "%.1f", contact.standing))
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(standingColor)
                    }
                }

                // Label tags
                if !contact.labelNames.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 6) {
                            ForEach(contact.labelNames, id: \.self) { label in
                                Text(label)
                                    .font(.caption2)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(.quaternary, in: Capsule())
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
            .padding(12)
        }
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private var contactTypeIcon: String {
        switch contact.contactType {
        case "corporation":                                return "building.2.fill"
        case "alliance":                                   return "shield.fill"
        case "faction":                                    return "globe"
        case "character" where contact.isPlayerCharacter:  return "person.fill"
        default:                                           return "cpu"
        }
    }

    private var contactTypeLabel: String {
        switch contact.contactType {
        case "corporation":                                return "Corp"
        case "alliance":                                   return "Alliance"
        case "faction":                                    return "Faction"
        case "character" where contact.isPlayerCharacter:  return "Player"
        default:                                           return "NPC"
        }
    }

    private var standingColor: Color {
        if contact.standing >= 5 { return .blue }
        if contact.standing > 0 { return .cyan }
        if contact.standing == 0 { return .gray }
        if contact.standing > -5 { return .orange }
        return .red
    }

    private var standingIcon: String {
        if contact.standing >= 5 { return "star.fill" }
        if contact.standing > 0 { return "hand.thumbsup.fill" }
        if contact.standing == 0 { return "minus" }
        if contact.standing > -5 { return "hand.thumbsdown.fill" }
        return "xmark.circle.fill"
    }
}

// MARK:  EVE News Widget

struct EVENewsWidgetView: View {
    let items: [EVENewsItem]
    let isLoading: Bool
    @Binding var isExpanded: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                isExpanded.toggle()
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "newspaper.fill")
                        .foregroundStyle(.orange)
                        .font(.callout)
                    Text("EVE News")
                        .font(.title3.bold())
                    if !items.isEmpty {
                        Text("(\(items.count))")
                            .font(.title3)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.caption.bold())
                        .foregroundStyle(.tertiary)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(Color.orange.opacity(0.07), in: RoundedRectangle(cornerRadius: 10))
                .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Color.orange.opacity(0.15), lineWidth: 1))
            }
            .buttonStyle(.plain)

            if isExpanded {
                if isLoading {
                    HStack {
                        Spacer()
                        ProgressView("Loading news...")
                        Spacer()
                    }
                    .padding(.vertical, 20)
                } else if items.isEmpty {
                    HStack {
                        Spacer()
                        Text("Unable to load EVE news")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        Spacer()
                    }
                    .padding(.vertical, 20)
                } else {
                    let columns = [GridItem(.adaptive(minimum: 300, maximum: 480), spacing: 12)]
                    LazyVGrid(columns: columns, spacing: 12) {
                        ForEach(items) { item in
                            NewsCardView(item: item)
                        }
                    }
                    .padding(.top, 12)
                }
            }
        }
        .padding(.horizontal)
    }
}

struct NewsCardView: View {
    let item: EVENewsItem
    @Environment(\.openURL) private var openURL

    var body: some View {
        Button {
            if let url = item.link { openURL(url) }
        } label: {
            VStack(spacing: 0) {
                Rectangle()
                    .fill(categoryColor)
                    .frame(height: 3)

                bannerView
                    .frame(height: 60)
                    .clipped()

                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 8) {
                        Text(item.category.isEmpty ? "EVE News" : item.category)
                            .font(.caption2.bold())
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(categoryColor.opacity(0.15), in: Capsule())
                            .foregroundStyle(categoryColor)
                            .lineLimit(1)

                        Spacer()

                        if let date = item.pubDate {
                            Text(date, style: .relative)
                                .font(.caption2.monospacedDigit())
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }

                    Text(item.title)
                        .font(.headline)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)

                    let snippet = plainSummary
                    if !snippet.isEmpty {
                        Text(snippet)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(3)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Spacer(minLength: 8)

                    Divider()

                    HStack {
                        Label(item.author.isEmpty ? "CCP Games" : item.author, systemImage: "person.fill")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)

                        Spacer()

                        Image(systemName: "arrow.up.right.circle")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .topLeading)
            }
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var bannerView: some View {
        if let imageURL = bannerImageURL {
            AsyncImage(url: imageURL) { phase in
                switch phase {
                case .success(let image):
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .overlay(
                            LinearGradient(
                                colors: [.clear, Color.black.opacity(0.55)],
                                startPoint: .init(x: 0.5, y: 0.3),
                                endPoint: .bottom
                            )
                        )
                default:
                    categoryGradientBanner
                }
            }
        } else {
            categoryGradientBanner
        }
    }

    private var categoryGradientBanner: some View {
        ZStack {
            LinearGradient(
                colors: [categoryColor.opacity(0.35), Color(white: 0.08)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            Image(systemName: categoryIcon)
                .font(.system(size: 36))
                .foregroundStyle(categoryColor.opacity(0.25))
        }
    }

    private var bannerImageURL: URL? {
        let pattern = #"<img[^>]+src="(https[^"]+)""#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
              let match = regex.firstMatch(
                  in: item.summary,
                  range: NSRange(item.summary.startIndex..., in: item.summary)
              ),
              let srcRange = Range(match.range(at: 1), in: item.summary) else {
            return nil
        }
        return URL(string: String(item.summary[srcRange]))
    }

    private var categoryIcon: String {
        let lower = item.category.lowercased()
        if lower.contains("dev")   { return "wrench.and.screwdriver.fill" }
        if lower.contains("event") { return "calendar.badge.plus" }
        return "megaphone.fill"
    }

    private var categoryColor: Color {
        let lower = item.category.lowercased()
        if lower.contains("dev")    { return .purple }
        if lower.contains("event")  { return .orange }
        return .blue
    }

    private var plainSummary: String {
        var text = item.summary
        text = text.replacingOccurrences(
            of: "<div[^>]*class=\"lightbox-wrapper\"[^>]*>[\\s\\S]*?</div>",
            with: " ", options: [.regularExpression, .caseInsensitive]
        )
        text = text.replacingOccurrences(of: "<br[^>]*>", with: " ", options: [.regularExpression, .caseInsensitive])
        text = text.replacingOccurrences(of: "</p>", with: " ", options: .caseInsensitive)
        text = text.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
        let entities: [(String, String)] = [
            ("&amp;","&"), ("&lt;","<"), ("&gt;",">"),
            ("&quot;","\""), ("&#39;","'"), ("&nbsp;"," "), ("&#32;"," ")
        ]
        for (entity, replacement) in entities {
            text = text.replacingOccurrences(of: entity, with: replacement)
        }
        text = text.components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }.joined(separator: " ")
        if let range = text.range(of: #"\d+ posts? - \d+ participants?"#, options: .regularExpression) {
            text = String(text[..<range.lowerBound])
        }
        if text.count > 260 {
            text = String(text.prefix(260))
            if let last = text.lastIndex(of: ".") {
                text = String(text[...last])
            }
        }
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
