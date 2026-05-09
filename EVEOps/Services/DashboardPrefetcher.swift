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

/// Prefetches all character data at app startup so every view loads instantly.
/// Views check `data(for:)` and `resolvedName(_:)` before making their own API calls.
@MainActor
@Observable
final class DashboardPrefetcher {
    private(set) var characterData: [Int: PrefetchedCharacterData] = [:]
    private(set) var isLoading = false
    private(set) var lastRefresh: Date?
    private(set) var menuBarSummaries: [Int: CharacterSummary] = [:]

    // Pre-resolved names and universe data available synchronously on MainActor
    private(set) var resolvedNames: [Int: String] = [:]
    private(set) var resolvedSystems: [Int: ESISolarSystem] = [:]
    private(set) var resolvedTypes: [Int: ESIType] = [:]
    private(set) var resolvedGroups: [Int: ESIGroup] = [:]
    private(set) var resolvedConstellations: [Int: ESIConstellation] = [:]
    private(set) var resolvedRegions: [Int: ESIRegion] = [:]

    struct PrefetchedCharacterData {
        let wallet: Double
        let skills: ESISkillsResponse
        let skillQueue: [ESISkillQueue]
        let location: ESICharacterLocation
        let ship: ESICharacterShip
        let online: ESICharacterOnline
        let contracts: [ESIContract]
        let industryJobs: [ESIIndustryJob]
        let colonies: [ESIColony]
        // Additional data for detail views
        let journal: [ESIWalletJournalEntry]
        let transactions: [ESIWalletTransaction]
        let marketOrders: [ESIMarketOrder]
        let loyaltyPoints: [ESILoyaltyPoints]
        // Clone status — used to detect recent jumps that affect training speed
        let clones: ESIClonesResponse?
        // Fresh public info — always fetched with cache cleared
        let corporationName: String
        let allianceName: String?
        let fetchedAt: Date
    }

    /// How long prefetched data is considered fresh (2 minutes)
    private let freshness: TimeInterval = 120

    func data(for characterID: Int) -> PrefetchedCharacterData? {
        guard let d = characterData[characterID],
              Date().timeIntervalSince(d.fetchedAt) < freshness else { return nil }
        return d
    }

    /// Look up a pre-resolved name by ID (type, character, corporation, system, etc.)
    func resolvedName(_ id: Int) -> String? {
        resolvedNames[id]
    }

    func prefetchAll(accountManager: AccountManager) async {
        guard !isLoading else { return }
        isLoading = true
        await ESIClient.shared.clearAllCaches()

        await withTaskGroup(of: (Int, PrefetchedCharacterData?).self) { group in
            for account in accountManager.accounts {
                group.addTask {
                    let data = await self.prefetch(account: account, accountManager: accountManager)
                    return (account.characterID, data)
                }
            }
            for await (charID, data) in group {
                if let data {
                    characterData[charID] = data
                }
            }
        }

        // Pre-resolve all names and universe data from the fetched data
        await resolveAllCachedData(accountManager: accountManager)

        lastRefresh = Date()
        isLoading = false
    }

    private nonisolated func prefetch(account: StoredAccount, accountManager: AccountManager) async -> PrefetchedCharacterData? {
        do {
            let token = try await accountManager.validToken(for: account)
            let charID = account.characterID

            async let fetchWallet: Double = ESIClient.shared.fetch(
                "/characters/\(charID)/wallet/", token: token)
            async let fetchSkills: ESISkillsResponse = ESIClient.shared.fetch(
                "/characters/\(charID)/skills/", token: token)
            async let fetchQueue: [ESISkillQueue] = ESIClient.shared.fetch(
                "/characters/\(charID)/skillqueue/", token: token)
            async let fetchLocation: ESICharacterLocation = ESIClient.shared.fetch(
                "/characters/\(charID)/location/", token: token)
            async let fetchShip: ESICharacterShip = ESIClient.shared.fetch(
                "/characters/\(charID)/ship/", token: token)
            async let fetchOnline: ESICharacterOnline = ESIClient.shared.fetch(
                "/characters/\(charID)/online/", token: token)
            async let fetchContracts: [ESIContract] = ESIClient.shared.fetch(
                "/characters/\(charID)/contracts/", token: token)
            async let fetchIndustry: [ESIIndustryJob] = ESIClient.shared.fetch(
                "/characters/\(charID)/industry/jobs/", token: token)
            async let fetchColonies: [ESIColony] = ESIClient.shared.fetch(
                "/characters/\(charID)/planets/", token: token)
            async let fetchJournal: [ESIWalletJournalEntry] = ESIClient.shared.fetch(
                "/characters/\(charID)/wallet/journal/", token: token)
            async let fetchTransactions: [ESIWalletTransaction] = ESIClient.shared.fetch(
                "/characters/\(charID)/wallet/transactions/", token: token)
            async let fetchOrders: [ESIMarketOrder] = ESIClient.shared.fetch(
                "/characters/\(charID)/orders/", token: token)
            async let fetchLP: [ESILoyaltyPoints] = ESIClient.shared.fetch(
                "/characters/\(charID)/loyalty/points/", token: token)
            async let fetchClones: ESIClonesResponse = ESIClient.shared.fetch(
                "/characters/\(charID)/clones/", token: token)
            async let fetchPublicInfo: ESICharacterPublic = ESIClient.shared.fetch(
                "/characters/\(charID)/", bypassCache: true)

            // Use individual try? for non-critical endpoints so failures don't block
            let wallet = try await fetchWallet
            let skills = try await fetchSkills
            let queue = try await fetchQueue
            let location = try await fetchLocation
            let ship = try await fetchShip
            let online = try await fetchOnline
            let contracts = (try? await fetchContracts) ?? []
            let industry = (try? await fetchIndustry) ?? []
            let colonies = (try? await fetchColonies) ?? []
            let journal = (try? await fetchJournal) ?? []
            let transactions = (try? await fetchTransactions) ?? []
            let orders = (try? await fetchOrders) ?? []
            let lp = (try? await fetchLP) ?? []
            let clonesData = try? await fetchClones
            let publicInfo = try? await fetchPublicInfo

            // Resolve corp and alliance names from the fresh public info
            var corporationName = ""
            var allianceName: String? = nil
            if let info = publicInfo {
                if let corp: ESICorporationPublic = try? await ESIClient.shared.fetch("/corporations/\(info.corporationId)/", bypassCache: true) {
                    corporationName = corp.name
                }
                if let allianceId = info.allianceId,
                   let alliance: ESIAlliancePublic = try? await ESIClient.shared.fetch("/alliances/\(allianceId)/", bypassCache: true) {
                    allianceName = alliance.name
                }
            }

            return PrefetchedCharacterData(
                wallet: wallet,
                skills: skills,
                skillQueue: queue,
                location: location,
                ship: ship,
                online: online,
                contracts: contracts,
                industryJobs: industry,
                colonies: colonies,
                journal: journal,
                transactions: transactions,
                marketOrders: orders,
                loyaltyPoints: lp,
                clones: clonesData,
                corporationName: corporationName,
                allianceName: allianceName,
                fetchedAt: Date()
            )
        } catch {
            return nil
        }
    }

    /// Pre-resolve all names and universe data so views can access them synchronously
    private func resolveAllCachedData(accountManager: AccountManager) async {
        var allTypeIDs: Set<Int> = []
        var allSystemIDs: Set<Int> = []
        var allNameIDs: Set<Int> = []

        for (_, data) in characterData {
            // Ship types
            allTypeIDs.insert(data.ship.shipTypeId)

            // Skill IDs (for name resolution)
            for entry in data.skillQueue {
                allNameIDs.insert(entry.skillId)
            }
            for skill in data.skills.skills {
                allTypeIDs.insert(skill.skillId)
                allNameIDs.insert(skill.skillId)
            }

            // Blueprint types from industry
            for job in data.industryJobs {
                allTypeIDs.insert(job.blueprintTypeId)
                allNameIDs.insert(job.blueprintTypeId)
            }

            // Solar systems
            allSystemIDs.insert(data.location.solarSystemId)
            for colony in data.colonies {
                allSystemIDs.insert(colony.solarSystemId)
                allNameIDs.insert(colony.solarSystemId)
            }

            // LP corporation IDs
            for lp in data.loyaltyPoints {
                allNameIDs.insert(lp.corporationId)
            }
        }

        // Batch resolve names via NameResolver (disk-cached)
        let names = await NameResolver.shared.resolve(ids: Array(allNameIDs))
        resolvedNames = names

        // Batch resolve types via UniverseCache (disk-cached)
        let types = await UniverseCache.shared.types(ids: Array(allTypeIDs))
        resolvedTypes = types

        // Collect group IDs from types
        var allGroupIDs: Set<Int> = []
        for (_, typeInfo) in types {
            allGroupIDs.insert(typeInfo.groupId)
        }

        // Batch resolve groups
        let groups = await UniverseCache.shared.groups(ids: allGroupIDs)
        resolvedGroups = groups

        // Resolve solar systems
        for sysID in allSystemIDs {
            if let sys = await UniverseCache.shared.solarSystem(id: sysID) {
                resolvedSystems[sysID] = sys
            }
        }

        // Resolve constellations and regions from systems
        var constellationIDs: Set<Int> = []
        for (_, sys) in resolvedSystems {
            constellationIDs.insert(sys.constellationId)
        }
        for cID in constellationIDs {
            if let c = await UniverseCache.shared.constellation(id: cID) {
                resolvedConstellations[cID] = c
                let rID = c.regionId
                if resolvedRegions[rID] == nil {
                    if let r = await UniverseCache.shared.region(id: rID) {
                        resolvedRegions[rID] = r
                    }
                }
            }
        }

        // Build menu bar summaries now that all data is resolved
        await buildMenuBarSummaries(accountManager: accountManager)
    }

    /// Builds CharacterSummary objects from prefetched data so MenuBarView is pre-populated on first open.
    func buildMenuBarSummaries(accountManager: AccountManager) async {
        for account in accountManager.accounts {
            guard let prefetched = characterData[account.characterID] else { continue }
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

            // PI extractor checks — use validToken so the token is refreshed if needed
            if !prefetched.colonies.isEmpty, !account.needsReauth,
               let token = try? await accountManager.validToken(for: account) {
                for colony in prefetched.colonies {
                    if let layout: ESIColonyLayout = try? await ESIClient.shared.fetch(
                        "/characters/\(account.characterID)/planets/\(colony.planetId)/", token: token
                    ) {
                        s.expiredExtractorCount += layout.pins.filter { $0.extractorDetails != nil && ($0.expiryTime ?? .distantPast) < Date() }.count
                    }
                }
            }

            // Use pre-resolved universe data
            if let sysInfo = resolvedSystems[prefetched.location.solarSystemId] {
                s.systemName = sysInfo.name
                s.securityStatus = sysInfo.securityStatus
            }
            if let typeInfo = resolvedTypes[prefetched.ship.shipTypeId] {
                s.shipTypeName = typeInfo.name
            }
            if let skillID = s.trainingSkillID {
                s.trainingSkillName = resolvedNames[skillID]
            }

            s.corporationName = prefetched.corporationName
            s.allianceName = prefetched.allianceName

            menuBarSummaries[account.characterID] = s
        }
    }
}
