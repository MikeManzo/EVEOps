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

/// What the Idle Capacity screen and its background alerts need beyond the prefetched
/// snapshot: extractor expiries, research agents and industry job history. Builds each
/// pilot's engine input from the two.
@MainActor
@Observable
final class IdleCapacityService {
    static let shared = IdleCapacityService()

    /// Character → planet → when that colony's extractors stop.
    private(set) var extractorExpiries: [Int: [Int: Date]] = [:]
    /// Character → research agents; absent when the scope is missing or the read failed.
    private(set) var researchAgents: [Int: [IdleCapacityAgent]] = [:]
    /// Character → the last 90 days of industry jobs, delivered and cancelled included.
    private(set) var jobHistory: [Int: [ESIIndustryJob]] = [:]

    // MARK: Input

    func input(characterID: Int, data: DashboardPrefetcher.PrefetchedCharacterData) -> IdleCapacityInput {
        let history = jobHistory[characterID]
        var jobs = data.industryJobs
        if let history {
            let current = Set(jobs.map(\.jobId))
            jobs += history.filter { !current.contains($0.jobId) }
        }
        let contracts = Self.openContracts(data.contracts, issuer: characterID)
        return IdleCapacityInput(
            skills: Dictionary(data.skills.skills.map { ($0.skillId, $0.activeSkillLevel) }, uniquingKeysWith: max),
            unallocatedSP: data.skills.unallocatedSp ?? 0,
            bonusRemaps: data.attributes?.bonusRemaps ?? 0,
            nextRemap: data.attributes.map {
                IdleCapacityEngine.nextRemap(accruedCooldown: $0.accruedRemapCooldownDate, lastRemap: $0.lastRemapDate)
            },
            queueFinishDates: data.skillQueue.map(\.finishDate),
            jobs: jobs.map {
                IdleCapacityJob(activityID: $0.activityId, status: $0.status, endDate: $0.endDate,
                                startDate: $0.startDate, completedDate: $0.completedDate)
            },
            jobHistoryLoaded: history != nil,
            orderCount: data.marketOrders.count,
            orderExpiries: data.marketOrders.compactMap(Self.expiry),
            contractCount: contracts.count,
            contractExpiries: contracts.map(\.dateExpired),
            colonyCount: data.colonies.count,
            extractorExpiries: extractorExpiries[characterID].map { Array($0.values) },
            lastCloneJump: data.clones?.lastCloneJumpDate,
            jumpCloneCount: data.clones?.jumpClones.count ?? 0,
            researchAgents: researchAgents[characterID]
        )
    }

    /// Outstanding contracts the pilot issued themselves — the ones that use a contract slot.
    private static func openContracts(_ contracts: [ESIContract], issuer: Int) -> [ESIContract] {
        contracts.filter { $0.issuerId == issuer && !$0.forCorporation && $0.status == "outstanding" }
    }

    /// Immediate orders (duration 0) never sit on the market.
    private static func expiry(_ order: ESIMarketOrder) -> Date? {
        order.duration > 0 ? order.issued.addingTimeInterval(Double(order.duration) * 86400) : nil
    }

    // MARK: Loading

    /// Extractor expiries (from each colony's layout) and research agents; with
    /// `includeHistory`, the 90-day industry job history too.
    func loadExtras(accountManager: AccountManager, prefetcher: DashboardPrefetcher, includeHistory: Bool) async {
        let accounts = accountManager.accounts.filter { !$0.needsReauth }
        var collected: [Int: String] = [:]
        for account in accounts {
            collected[account.characterID] = try? await accountManager.validToken(for: account)
        }
        let tokens = collected
        let colonies: [(characterID: Int, planetID: Int)] = accounts.flatMap { account in
            (prefetcher.characterData[account.characterID]?.colonies ?? []).map { (account.characterID, $0.planetId) }
        }
        let researchers = accounts.filter { $0.scopes.contains("esi-characters.read_agents_research.v1") }.map(\.characterID)

        async let expiries = withTaskGroup(of: (Int, Int, Date?).self) { group in
            for (characterID, planetID) in colonies {
                guard let token = tokens[characterID] else { continue }
                group.addTask {
                    let layout: ESIColonyLayout? = try? await ESIClient.shared.fetch(
                        "/characters/\(characterID)/planets/\(planetID)/", token: token
                    )
                    return (characterID, planetID, layout.flatMap(ExtractorStatus.init(layout:))?.expiry)
                }
            }
            var out: [Int: [Int: Date]] = [:]
            for await (characterID, planetID, expiry) in group {
                if let expiry { out[characterID, default: [:]][planetID] = expiry }
            }
            return out
        }

        async let agents = withTaskGroup(of: (Int, [IdleCapacityAgent]?).self) { group in
            for characterID in researchers {
                guard let token = tokens[characterID] else { continue }
                group.addTask {
                    let raw: [ESIResearchAgent]? = try? await ESIClient.shared.fetch(
                        "/characters/\(characterID)/agents_research/", token: token
                    )
                    return (characterID, raw?.map {
                        IdleCapacityAgent(pointsPerDay: $0.pointsPerDay, remainderPoints: $0.remainderPoints, startedAt: $0.startedAt)
                    })
                }
            }
            var out: [Int: [IdleCapacityAgent]] = [:]
            for await (characterID, list) in group {
                if let list { out[characterID] = list }
            }
            return out
        }

        async let history = withTaskGroup(of: (Int, [ESIIndustryJob]?).self) { group in
            guard includeHistory else { return [Int: [ESIIndustryJob]]() }
            for (characterID, token) in tokens {
                group.addTask {
                    let jobs: [ESIIndustryJob]? = try? await ESIClient.shared.fetch(
                        "/characters/\(characterID)/industry/jobs/", token: token,
                        queryItems: [URLQueryItem(name: "include_completed", value: "true")]
                    )
                    return (characterID, jobs)
                }
            }
            var out: [Int: [ESIIndustryJob]] = [:]
            for await (characterID, jobs) in group {
                if let jobs { out[characterID] = jobs }
            }
            return out
        }

        extractorExpiries = await expiries
        researchAgents = await agents
        let loadedHistory = await history
        if includeHistory { jobHistory = loadedHistory }
    }

    // MARK: Alerts

    /// Each poll cycle: alert on extractors that stopped, clone jumps that came ready, and
    /// orders or contracts that now expire within a day. The first check for a pilot only
    /// records a baseline.
    func backgroundCheck(accountManager: AccountManager, prefetcher: DashboardPrefetcher) async {
        let defaults = UserDefaults.standard
        func enabled(_ key: String) -> Bool { defaults.object(forKey: key) as? Bool ?? true }
        guard enabled("notificationsEnabled") else { return }
        let extractorsOn = enabled("notifyExtractorsExpired")
        let cloneJumpOn = enabled("notifyCloneJumpReady")
        let expiringOn = enabled("notifyListingsExpiring")
        guard extractorsOn || cloneJumpOn || expiringOn else { return }

        if extractorsOn {
            await loadExtras(accountManager: accountManager, prefetcher: prefetcher, includeHistory: false)
        }

        let now = Date()
        let soon = now.addingTimeInterval(IdleCapacityEngine.soonWindow)
        for account in accountManager.accounts {
            let characterID = account.characterID
            guard let data = prefetcher.characterData[characterID] else { continue }
            let key = "idleCapacityAlerts.\(characterID)"
            let stored = defaults.dictionary(forKey: key) as? [String: [Int]]

            // A colony whose layout didn't load this time keeps what was stored for it.
            let layouts = extractorExpiries[characterID] ?? [:]
            let colonyIDs = Set(data.colonies.map(\.planetId))
            let carried = (stored?["stopped"] ?? []).filter { colonyIDs.contains($0) && layouts[$0] == nil }
            let stopped = layouts.filter { $0.value <= now }.map(\.key) + carried

            let expiringOrders = data.marketOrders
                .filter { Self.expiry($0).map { $0 > now && $0 <= soon } ?? false }
                .map(\.orderId)
            let expiringContracts = Self.openContracts(data.contracts, issuer: characterID)
                .filter { $0.dateExpired > now && $0.dateExpired <= soon }
                .map(\.contractId)

            let hasJumpClones = !(data.clones?.jumpClones.isEmpty ?? true)
            let jumpPending = hasJumpClones && IdleCapacityEngine.cloneJumpReadyAt(
                lastJump: data.clones?.lastCloneJumpDate,
                infomorphSynchronizing: IdleCapacityEngine.infomorphSynchronizing(in: data.skills),
                now: now
            ) != nil

            defaults.set([
                "stopped": stopped,
                "orders": expiringOrders,
                "contracts": expiringContracts,
                "jumpPending": jumpPending ? [1] : [],
            ], forKey: key)
            guard let stored else { continue }

            var lines: [String] = []
            let newlyStopped = Set(stopped).subtracting(stored["stopped"] ?? []).count
            if extractorsOn, newlyStopped > 0 {
                lines.append(String(localized: "\(newlyStopped) PI extractors stopped"))
            }
            if cloneJumpOn, hasJumpClones, !jumpPending, stored["jumpPending"]?.isEmpty == false {
                lines.append(String(localized: "Clone jump available"))
            }
            let newOrders = Set(expiringOrders).subtracting(stored["orders"] ?? []).count
            if expiringOn, newOrders > 0 {
                lines.append(String(localized: "\(newOrders) market orders expire within a day"))
            }
            let newContracts = Set(expiringContracts).subtracting(stored["contracts"] ?? []).count
            if expiringOn, newContracts > 0 {
                lines.append(String(localized: "\(newContracts) contracts expire within a day"))
            }
            guard !lines.isEmpty else { continue }
            await NotificationService.shared.notifyIdleCapacity(
                characterID: characterID, characterName: account.characterName, lines: lines
            )
        }
    }
}
