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

/// Keeps a plotted route's entry briefs current from zKillboard's live feed, and notifies
/// the pilot when something new turns up ahead of them: a gate camp, a gang, a system
/// going to Danger, or Danger one jump away. Runs until stopped, a new route is watched,
/// or `maxDuration` passes, whether or not the Route Planner is on screen.
@MainActor
@Observable
final class RouteWatchService {
    static let shared = RouteWatchService()
    private init() {}

    /// A watch ends on its own after this long, so a forgotten one doesn't run all week.
    static let maxDuration: TimeInterval = 3 * 3600
    /// How often briefs are rebuilt without new kills, so old kills age out.
    private static let refreshInterval: TimeInterval = 60
    private static let locationInterval: TimeInterval = 30
    /// Kills arriving close together are classified once.
    private static let debounce: TimeInterval = 2

    // MARK: Observable state

    /// Every system on the watched route, in order; empty when not watching.
    private(set) var routeIDs: [Int] = []
    /// Live briefs for the watched lowsec systems.
    private(set) var intel: [Int: SystemIntel] = [:]
    private(set) var startedAt: Date?
    /// Last time the live feed answered, kill or not, so the UI can show it's alive.
    private(set) var lastFeedContact: Date?
    /// Live kills seen on or next to the route since the watch started.
    private(set) var liveKillsSeen = 0
    /// Where the watching pilot is, when their location can be read.
    private(set) var pilotSystemID: Int?
    private(set) var pilotName: String?

    var isWatching: Bool { !routeIDs.isEmpty }

    func isWatching(route: [Int]) -> Bool { isWatching && routeIDs == route }

    // MARK: Private state

    private var lowsecIDs: [Int] = []
    /// Lowsec route systems plus their stargate neighbours; live kills elsewhere are ignored.
    private var watchSet: Set<Int> = []
    private var kills: [Int: ThreatKill] = [:]
    private var fetchedAt: [Int: Date] = [:]
    private var esi: SystemDangerService.Snapshot?
    private var context: [Int: SystemContext] = [:]
    private var lastThreats: [Int: SystemThreat] = [:]
    private var sentKeys: Set<String> = []
    private var tasks: [Task<Void, Never>] = []
    private var rebuildTask: Task<Void, Never>?

    // MARK: Lifecycle

    /// Starts watching `route`, replacing any earlier watch.
    /// - Parameters:
    ///   - lowsecIDs: the route's lowsec systems, the ones that get briefs.
    ///   - accountManager: when the selected pilot has the location scope, their position
    ///     is followed so only systems ahead of them are announced.
    func start(route: [Int], lowsecIDs: [Int], esi: SystemDangerService.Snapshot?,
               accountManager: AccountManager?) async {
        stop()
        let lowsec = Array(lowsecIDs.prefix(SystemDangerService.briefMaxSystems))
        guard !lowsec.isEmpty else { return }

        routeIDs = route
        self.lowsecIDs = lowsec
        self.esi = esi
        startedAt = Date()

        var set = Set(lowsec)
        if let topology = await UniverseTopology.shared.loadedTopology() {
            let wanted = Set(lowsec)
            for (a, b) in topology.jumps {
                if wanted.contains(a) { set.insert(b) }
                if wanted.contains(b) { set.insert(a) }
            }
        }
        watchSet = set

        // Seed from the same zKillboard backfill the brief used (cached, so no new requests).
        let fill = await SystemDangerService.shared.backfill(lowsec)
        guard routeIDs == route else { return }
        for kill in fill.kills { kills[kill.id] = kill }
        fetchedAt = fill.fetchedAt
        context = await SystemDangerService.shared.context(for: lowsec)
        await rebuild(announce: false)

        tasks.append(Task { [weak self] in await self?.consumeFeed() })
        tasks.append(Task { [weak self] in await self?.tick() })
        if let accountManager, let account = accountManager.selectedAccount,
           account.scopes.contains("esi-location.read_location.v1") {
            pilotName = account.characterName
            let characterID = account.characterID
            tasks.append(Task { [weak self] in
                await self?.followPilot(characterID: characterID, accountManager: accountManager)
            })
        }
    }

    func stop() {
        tasks.forEach { $0.cancel() }
        tasks = []
        rebuildTask?.cancel()
        rebuildTask = nil
        routeIDs = []
        lowsecIDs = []
        watchSet = []
        intel = [:]
        kills = [:]
        fetchedAt = [:]
        context = [:]
        lastThreats = [:]
        sentKeys = []
        startedAt = nil
        lastFeedContact = nil
        liveKillsSeen = 0
        pilotSystemID = nil
        pilotName = nil
    }

    // MARK: Loops

    private func consumeFeed() async {
        for await live in await ZKillLiveFeed.shared.kills() {
            guard !Task.isCancelled else { return }
            lastFeedContact = Date()
            guard watchSet.contains(live.esi.solarSystemId), kills[live.killmailId] == nil else { continue }
            kills[live.killmailId] = ThreatKill(live: live)
            liveKillsSeen += 1
            scheduleRebuild()
        }
    }

    /// Periodic refresh: ages kills out, notices the feed going quiet, ends the watch.
    private func tick() async {
        while !Task.isCancelled {
            try? await Task.sleep(nanoseconds: UInt64(Self.refreshInterval * 1_000_000_000))
            guard !Task.isCancelled else { return }
            if let startedAt, Date().timeIntervalSince(startedAt) > Self.maxDuration {
                stop(); return
            }
            // The feed only answers with kills; a quiet stretch still means it's current.
            await rebuild(announce: true)
        }
    }

    private func followPilot(characterID: Int, accountManager: AccountManager) async {
        while !Task.isCancelled {
            if let account = accountManager.accounts.first(where: { $0.characterID == characterID }),
               let token = try? await accountManager.validToken(for: account),
               let location: ESICharacterLocation = try? await ESIClient.shared.fetch(
                   "/characters/\(characterID)/location/", token: token, bypassCache: true) {
                if location.solarSystemId != pilotSystemID {
                    pilotSystemID = location.solarSystemId
                    scheduleRebuild()
                }
            }
            try? await Task.sleep(nanoseconds: UInt64(Self.locationInterval * 1_000_000_000))
        }
    }

    private func scheduleRebuild() {
        rebuildTask?.cancel()
        rebuildTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(Self.debounce * 1_000_000_000))
            guard !Task.isCancelled else { return }
            await self?.rebuild(announce: true)
        }
    }

    // MARK: Rebuild

    private func rebuild(announce: Bool) async {
        let route = routeIDs
        guard !route.isEmpty else { return }
        let now = Date()

        // Drop kills that have left the brief's window.
        let window = TimeInterval(SystemDangerService.briefWindowHours * 3600)
        kills = kills.filter { now.timeIntervalSince($0.value.time) <= window }

        // The live feed keeps every watched system current while it's answering.
        var ages = fetchedAt
        if let contact = lastFeedContact { for id in lowsecIDs { ages[id] = contact } }

        var built = await SystemDangerService.shared.buildIntel(
            systemIDs: lowsecIDs, contextIDs: Array(watchSet), kills: Array(kills.values),
            fetchedAt: ages, esi: esi, now: now
        )
        guard routeIDs == route else { return }
        for id in built.keys {
            built[id]?.context = context[id]
            built[id]?.isLive = true
        }

        let threats = built.mapValues(\.threat)
        let alerts = RouteWatchEngine.alerts(
            previous: lastThreats.isEmpty ? threats : lastThreats, current: threats,
            route: route, pilotSystemID: pilotSystemID, alreadySent: sentKeys, now: now
        )
        sentKeys.formUnion(alerts.map(\.key))
        lastThreats = threats
        intel = built

        guard announce else { return }
        for alert in alerts {
            guard let brief = built[alert.systemID] else { continue }
            let (title, body) = text(for: alert, brief: brief, route: route)
            await NotificationService.shared.notifyRouteWatch(title: title, body: body, key: alert.key)
        }
    }

    private func text(for alert: RouteAlert, brief: SystemIntel, route: [Int]) -> (String, String) {
        let name = brief.name(alert.systemID)
        let index = route.firstIndex(of: alert.systemID)
        let previous = index.flatMap { $0 > 0 ? route[$0 - 1] : nil }
        let next = index.flatMap { $0 < route.count - 1 ? route[$0 + 1] : nil }
        let reasons = RouteEntryBriefText.reasons(brief, previousSystemID: previous, nextSystemID: next)
        let local = String(localized: "Paste Local before you jump in.")

        switch alert.kind {
        case .gateCamp:
            let line = reasons.first { $0.hasPrefix("Likely gate camp") } ?? reasons.first ?? ""
            return (String(localized: "Gate camp on your route: \(name)"), line + " " + local)
        case .roamingGang:
            let line = reasons.first { $0.contains("-pilot gang") } ?? reasons.first ?? ""
            return (String(localized: "Gang near your route: \(name)"), line)
        case .escalated:
            return (String(localized: "\(name) is now Danger"), (reasons.first ?? "") + " " + local)
        case .nextJumpDanger:
            return (String(localized: "Next jump is dangerous: \(name)"), (reasons.first ?? "") + " " + local)
        }
    }
}

extension ThreatKill {
    nonisolated init(live: ZKBLiveKill) {
        self.init(
            id: live.killmailId,
            systemID: live.esi.solarSystemId,
            time: live.esi.killmailTime,
            locationID: live.zkb.locationID,
            attackerIDs: Set(live.esi.attackers.compactMap(\.characterId)),
            attackerShipTypeIDs: live.esi.attackers.compactMap(\.shipTypeId),
            isNPC: live.zkb.isNPC
        )
    }
}
