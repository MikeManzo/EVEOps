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
import OSLog

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

    /// How long prefetched data is considered fresh. Tracks `BackgroundMonitor`'s
    /// own poll interval (default 300s, user-adjustable down to 60s) plus a grace
    /// window — pinning this to a fixed value shorter than the poll interval meant
    /// `data(for:)` went nil for the last minute-plus of every cycle, which is why
    /// things like the sidebar's online/offline dot kept blinking out and coming
    /// back on its own.
    private var freshness: TimeInterval {
        let stored = UserDefaults.standard.double(forKey: "backgroundPollInterval")
        let pollInterval = stored >= 60 ? stored : 300
        return pollInterval + 60
    }

    /// Characters whose one-time (assets/killmails/implants) AI insight prefetch
    /// has already run this session — see `prefetchAIInsights`.
    private var expensiveInsightsDone: Set<Int> = []

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
        Logger.prefetch.info("Prefetcher: Starting prefetch for \(accountManager.accounts.count) account(s)")
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
        Logger.prefetch.info("Prefetcher: Complete — \(characterData.count) character(s) loaded")
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
        } catch ESIError.unauthorized {
            await accountManager.handleUnauthorized(for: account)
            await Logger.prefetch.error("Prefetcher: ESI 401 for \(account.characterName) — reauth required")
            return nil
        } catch {
            await Logger.prefetch.error("Prefetcher: Failed to prefetch \(account.characterName) — \(error.localizedDescription)")
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

        // Resolve solar systems concurrently
        resolvedSystems = await withTaskGroup(of: (Int, ESISolarSystem?).self) { group in
            for sysID in allSystemIDs {
                group.addTask { (sysID, await UniverseCache.shared.solarSystem(id: sysID)) }
            }
            var out: [Int: ESISolarSystem] = [:]
            for await (id, sys) in group {
                if let sys { out[id] = sys }
            }
            return out
        }

        // Resolve constellations concurrently, then their regions
        var constellationIDs: Set<Int> = []
        for (_, sys) in resolvedSystems {
            constellationIDs.insert(sys.constellationId)
        }
        resolvedConstellations = await withTaskGroup(of: (Int, ESIConstellation?).self) { group in
            for cID in constellationIDs {
                group.addTask { (cID, await UniverseCache.shared.constellation(id: cID)) }
            }
            var out: [Int: ESIConstellation] = [:]
            for await (id, c) in group {
                if let c { out[id] = c }
            }
            return out
        }
        let regionIDs = Set(resolvedConstellations.values.map(\.regionId))
        resolvedRegions = await withTaskGroup(of: (Int, ESIRegion?).self) { group in
            for rID in regionIDs {
                group.addTask { (rID, await UniverseCache.shared.region(id: rID)) }
            }
            var out: [Int: ESIRegion] = [:]
            for await (id, r) in group {
                if let r { out[id] = r }
            }
            return out
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
            if let current = currentlyTraining { s.trainingSkillID = current.skillId }
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
        DockTileController.update(
            summaries: Array(menuBarSummaries.values),
            selectedCharacterID: accountManager.selectedCharacterID
        )
    }

    // MARK:  AI Insight Prefetch

    /// Proactively runs the on-device AI analyses that feed the Dashboard's Daily
    /// Briefing widget, so they're already cached by the time the user opens it.
    /// Respects the same AI Insights toggles as the manual per-tab views.
    ///
    /// Industry and Skills need nothing beyond what's already sitting in
    /// `characterData`/`resolvedTypes`/`resolvedGroups`, so they re-run every poll
    /// cycle — `IntelligenceService`'s own per-prompt cache makes that a no-op
    /// unless the underlying jobs/skills actually changed. Finances, Combat, and
    /// Implants each need an extra fetch (assets + market prices, killmail
    /// history, active implants) that doesn't change minute to minute, so those
    /// run once per character per session via `expensiveInsightsDone`.
    func prefetchAIInsights(accountManager: AccountManager) async {
        guard UserDefaults.standard.bool(forKey: "aiInsightsEnabled") else { return }
        guard (UserDefaults.standard.object(forKey: "aiInsightBriefing") as? Bool) ?? true else { return }
        guard #available(macOS 26.0, *), IntelligenceService.isSupported else { return }

        let industryEnabled = (UserDefaults.standard.object(forKey: "aiInsightIndustry") as? Bool) ?? true
        let skillsEnabled = (UserDefaults.standard.object(forKey: "aiInsightSkills") as? Bool) ?? true
        let financeEnabled = (UserDefaults.standard.object(forKey: "aiInsightFinances") as? Bool) ?? true
        let combatEnabled = (UserDefaults.standard.object(forKey: "aiInsightKillmails") as? Bool) ?? true
        let implantsEnabled = (UserDefaults.standard.object(forKey: "aiInsightClones") as? Bool) ?? true

        for account in accountManager.accounts {
            guard let data = characterData[account.characterID] else { continue }

            if industryEnabled, !data.industryJobs.isEmpty {
                await prefetchIndustryInsight(characterName: account.characterName, data: data)
            }
            if skillsEnabled, !data.skills.skills.isEmpty {
                await prefetchSkillInsight(characterName: account.characterName, data: data)
            }

            guard !expensiveInsightsDone.contains(account.characterID) else { continue }
            guard financeEnabled || combatEnabled || implantsEnabled else { continue }
            expensiveInsightsDone.insert(account.characterID)

            guard !account.needsReauth, let token = try? await accountManager.validToken(for: account) else { continue }

            if financeEnabled {
                await prefetchFinanceInsight(characterName: account.characterName, characterID: account.characterID, data: data, token: token)
            }
            if combatEnabled {
                await prefetchCombatInsight(characterName: account.characterName, characterID: account.characterID, token: token)
            }
            if implantsEnabled {
                await prefetchImplantsInsight(characterName: account.characterName, characterID: account.characterID, data: data, token: token)
            }
        }
    }

    /// One-time asset valuation + finance insight. Mirrors FinancesView's
    /// `loadAssetValues()` + `FinanceAIInsightCard.generate()`.
    @available(macOS 26.0, *)
    private func prefetchFinanceInsight(characterName: String, characterID: Int, data: PrefetchedCharacterData, token: String) async {
        let marketPrices: [ESIMarketPrice] = (try? await ESIClient.shared.fetch("/markets/prices/")) ?? []
        let priceMap = Dictionary(
            marketPrices.map { ($0.typeId, $0.averagePrice ?? $0.adjustedPrice ?? 0.0) },
            uniquingKeysWith: { first, _ in first }
        )

        let assets: [ESIAsset] = (try? await ESIClient.shared.fetchPages("/characters/\(characterID)/assets/", token: token)) ?? []
        let assetValue = assets
            .filter { !($0.isBlueprintCopy ?? false) }
            .reduce(0.0) { $0 + (priceMap[$1.typeId] ?? 0) * Double($1.quantity) }

        let totalEscrow = data.marketOrders.filter { $0.isBuyOrder ?? false }.compactMap(\.escrow).reduce(0, +)
        let totalSellOrderValue = data.marketOrders
            .filter { !($0.isBuyOrder ?? false) }
            .reduce(0.0) { $0 + $1.price * Double($1.volumeRemain) }
        let netWorth = data.wallet + totalEscrow + totalSellOrderValue + assetValue

        let topRefs = Dictionary(grouping: data.journal, by: { $0.refType })
            .map { refType, entries in
                (name: refType.replacingOccurrences(of: "_", with: " ").capitalized,
                 total: entries.compactMap(\.amount).reduce(0, +))
            }
            .sorted { abs($0.total) > abs($1.total) }
            .prefix(5)
            .map { (name: $0.name, totalFormatted: EVEFormatters.formatISKShort($0.total)) }

        _ = try? await IntelligenceService.shared.analyzeFinances(
            characterName: characterName,
            balanceFormatted: EVEFormatters.formatISKShort(data.wallet),
            netWorthFormatted: EVEFormatters.formatISKShort(netWorth),
            sellOrderCount: data.marketOrders.filter { !($0.isBuyOrder ?? false) }.count,
            buyOrderCount: data.marketOrders.filter { $0.isBuyOrder ?? false }.count,
            topRefTypes: Array(topRefs)
        )
    }

    /// One-time combat insight. Mirrors `CombatAIInsightCard.generate()`, but
    /// bounded to the 50 most recent killmails — the interactive Killmails tab
    /// still pulls full lifetime history; a briefing summary doesn't need it.
    @available(macOS 26.0, *)
    private func prefetchCombatInsight(characterName: String, characterID: Int, token: String) async {
        var killRefs: [(killmailId: Int, hash: String)] = []
        if let zkbRefs = try? await ZKillboardClient.shared.fetchKillRefs(characterID: characterID), !zkbRefs.isEmpty {
            killRefs = zkbRefs.map { ($0.killmailId, $0.zkb.hash) }
        } else if let esiRefs: [ESIKillmailRef] = try? await ESIClient.shared.fetchPages(
            "/characters/\(characterID)/killmails/recent/", token: token
        ) {
            killRefs = esiRefs.map { ($0.killmailId, $0.killmailHash) }
        }
        guard !killRefs.isEmpty else { return }
        let bounded = Array(killRefs.prefix(50))

        var killmails: [(killmail: ESIKillmail, isKill: Bool)] = []
        await withTaskGroup(of: (killmail: ESIKillmail, isKill: Bool)?.self) { group in
            for ref in bounded {
                group.addTask {
                    guard let km: ESIKillmail = try? await ESIClient.shared.fetch(
                        "/killmails/\(ref.killmailId)/\(ref.hash)/"
                    ) else { return nil }
                    return (killmail: km, isKill: km.victim.characterId != characterID)
                }
            }
            for await entry in group { if let e = entry { killmails.append(e) } }
        }
        guard !killmails.isEmpty else { return }

        let kills = killmails.filter(\.isKill)
        let losses = killmails.filter { !$0.isKill }

        let lostShipCounts = Dictionary(grouping: losses, by: { $0.killmail.victim.shipTypeId })
            .map { typeId, entries in (typeId: typeId, count: entries.count) }
            .sorted { $0.count > $1.count }
            .prefix(4)
        let lostShipTypes = await UniverseCache.shared.types(ids: lostShipCounts.map(\.typeId))
        let topLostShips = lostShipCounts.map { item in
            (name: lostShipTypes[item.typeId]?.name ?? "Ship #\(item.typeId)", count: item.count)
        }

        let avgAttackers = losses.isEmpty ? 0.0
            : Double(losses.reduce(0) { $0 + $1.killmail.attackers.count }) / Double(losses.count)

        let systemCounts = Dictionary(grouping: killmails, by: { $0.killmail.solarSystemId })
            .map { systemId, entries in (systemId: systemId, count: entries.count) }
            .sorted { $0.count > $1.count }
            .prefix(4)
        let systemNames = await NameResolver.shared.resolve(ids: systemCounts.map(\.systemId))
        let activeSystemNames = systemCounts.map { systemNames[$0.systemId] ?? "System #\($0.systemId)" }

        let threatShipIds = losses.flatMap { $0.killmail.attackers.compactMap(\.shipTypeId) }
        let threatCounts = Dictionary(grouping: threatShipIds, by: { $0 })
            .map { typeId, arr in (typeId: typeId, count: arr.count) }
            .sorted { $0.count > $1.count }
            .prefix(4)
        let threatShipTypes = await UniverseCache.shared.types(ids: threatCounts.map(\.typeId))
        let commonThreatShips = threatCounts.map { threatShipTypes[$0.typeId]?.name ?? "Ship #\($0.typeId)" }

        _ = try? await IntelligenceService.shared.analyzeCombat(
            characterName: characterName,
            killCount: kills.count,
            lossCount: losses.count,
            topLostShips: Array(topLostShips),
            activeSystemNames: Array(activeSystemNames),
            avgAttackersOnLoss: avgAttackers,
            commonThreatShips: Array(commonThreatShips)
        )
    }

    /// One-time implants insight. Jump clone implants come free from the already-
    /// prefetched `clones` response; only the active-implant list is an extra call.
    @available(macOS 26.0, *)
    private func prefetchImplantsInsight(characterName: String, characterID: Int, data: PrefetchedCharacterData, token: String) async {
        let implantIDs: [Int] = (try? await ESIClient.shared.fetch("/characters/\(characterID)/implants/", token: token)) ?? []
        let jumpClones = data.clones?.jumpClones ?? []
        guard !implantIDs.isEmpty || !jumpClones.isEmpty else { return }

        let allImplantIDs = Array(Set(implantIDs + jumpClones.flatMap(\.implants)))
        let types = await UniverseCache.shared.types(ids: allImplantIDs)

        let activeImplantNames = implantIDs.map { types[$0]?.name ?? "Implant #\($0)" }
        let jumpCloneImplantNames = jumpClones.map { jc in jc.implants.map { types[$0]?.name ?? "Implant #\($0)" } }

        let topSkillAreas = Dictionary(grouping: data.skills.skills) { resolvedTypes[$0.skillId]?.groupId }
            .compactMap { groupId, skills -> (name: String, sp: Int)? in
                guard let groupId, let groupName = resolvedGroups[groupId]?.name else { return nil }
                return (name: groupName, sp: skills.reduce(0) { $0 + $1.skillpointsInSkill })
            }
            .sorted { $0.sp > $1.sp }
            .prefix(5)
            .map { (name: $0.name, spFormatted: Self.formatSP($0.sp)) }

        _ = try? await IntelligenceService.shared.analyzeImplants(
            characterName: characterName,
            activeImplantNames: activeImplantNames,
            jumpCloneImplantNames: jumpCloneImplantNames,
            totalSP: data.skills.totalSp,
            topSkillAreas: Array(topSkillAreas)
        )
    }

    @available(macOS 26.0, *)
    private func prefetchIndustryInsight(characterName: String, data: PrefetchedCharacterData) async {
        func activityLabel(_ id: Int) -> String {
            switch id {
            case 1: return "Manufacturing"
            case 3: return "TE Research"
            case 4: return "ME Research"
            case 5: return "Copying"
            case 8: return "Invention"
            case 9: return "Reactions"
            default: return "Activity \(id)"
            }
        }

        let activityBreakdown = Dictionary(grouping: data.industryJobs, by: { activityLabel($0.activityId) })
            .map { activity, jobList in (activity: activity, count: jobList.count) }
            .sorted { $0.count > $1.count }

        let topBlueprints = Dictionary(grouping: data.industryJobs, by: { $0.blueprintTypeId })
            .map { typeId, jobList in (typeId: typeId, count: jobList.count) }
            .sorted { $0.count > $1.count }
            .prefix(8)
            .map { resolvedTypes[$0.typeId]?.name ?? "Blueprint #\($0.typeId)" }

        _ = try? await IntelligenceService.shared.analyzeIndustry(
            characterName: characterName,
            totalJobs: data.industryJobs.count,
            activeJobs: data.industryJobs.filter { $0.status == "active" }.count,
            activityBreakdown: activityBreakdown,
            topBlueprints: topBlueprints
        )
    }

    @available(macOS 26.0, *)
    private func prefetchSkillInsight(characterName: String, data: PrefetchedCharacterData) async {
        let allSkills = data.skills.skills

        let topGroups = Dictionary(grouping: allSkills) { resolvedTypes[$0.skillId]?.groupId }
            .compactMap { groupId, skills -> (name: String, sp: Int, skillCount: Int, maxedCount: Int)? in
                guard let groupId, let groupName = resolvedGroups[groupId]?.name else { return nil }
                let sp = skills.reduce(0) { $0 + $1.skillpointsInSkill }
                let maxed = skills.filter { $0.trainedSkillLevel == 5 }.count
                return (name: groupName, sp: sp, skillCount: skills.count, maxedCount: maxed)
            }
            .sorted { $0.sp > $1.sp }
            .prefix(6)
            .map { (name: $0.name, spFormatted: Self.formatSP($0.sp), skillCount: $0.skillCount, maxedCount: $0.maxedCount) }

        let partialSkills = allSkills
            .filter { (1...4).contains($0.trainedSkillLevel) }
            .sorted { $0.skillpointsInSkill > $1.skillpointsInSkill }
            .prefix(60)
            .compactMap { skill -> (name: String, level: Int)? in
                guard let name = resolvedTypes[skill.skillId]?.name else { return nil }
                return (name: name, level: skill.trainedSkillLevel)
            }

        let maxedSkills = allSkills
            .filter { $0.trainedSkillLevel == 5 }
            .sorted { $0.skillpointsInSkill > $1.skillpointsInSkill }
            .prefix(40)
            .compactMap { resolvedTypes[$0.skillId]?.name }

        _ = try? await IntelligenceService.shared.analyzeTrainedSkills(
            characterName: characterName,
            totalSP: data.skills.totalSp,
            topGroups: Array(topGroups),
            partialSkills: Array(partialSkills),
            maxedSkills: Array(maxedSkills)
        )
    }

    private static func formatSP(_ sp: Int) -> String {
        if sp >= 1_000_000 { return String(format: "%.1fM SP", Double(sp) / 1_000_000) }
        if sp >= 1_000 { return String(format: "%.0fK SP", Double(sp) / 1_000) }
        return "\(sp) SP"
    }
}
