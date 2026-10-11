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

// MARK: Model

/// Recent activity for a single solar system, from ESI's hourly `system_kills` /
/// `system_jumps` aggregates. All counts cover roughly the last hour.
struct SystemDanger: Sendable, Equatable {
    var shipKills: Int = 0
    var podKills: Int = 0
    var npcKills: Int = 0
    var shipJumps: Int = 0
    /// The Route Entry Brief, when one was built for this system (lowsec on a plotted route).
    var intel: SystemIntel?

    /// Player-vs-player activity — the figure that actually matters for route safety.
    var combatKills: Int { shipKills + podKills }
    var isHostile: Bool { combatKills > 0 }

    nonisolated static let none = SystemDanger()
}

/// Coarse severity bucket for `SystemDanger.combatKills`, used to drive colour/labels.
enum DangerLevel: Int, Comparable, CaseIterable, Sendable {
    case quiet, elevated, high, extreme

    init(combatKills: Int) {
        switch combatKills {
        case ..<1:    self = .quiet
        case 1..<5:   self = .elevated
        case 5..<20:  self = .high
        default:      self = .extreme
        }
    }

    static func < (lhs: DangerLevel, rhs: DangerLevel) -> Bool { lhs.rawValue < rhs.rawValue }

    var label: String {
        switch self {
        case .quiet:    return "Quiet"
        case .elevated: return "Elevated"
        case .high:     return "High"
        case .extreme:  return "Extreme"
        }
    }
}

/// A Route Entry Brief for one system: the classified recent killmails plus the names
/// and data ages the brief needs to read in plain language.
struct SystemIntel: Sendable, Equatable {
    let threat: SystemThreat
    /// Names for every system and ship type the signals mention.
    let names: [Int: String]
    /// Stargate → the system it leads to, for "camp on the Amamake gate".
    let gateDestinations: [Int: Int]
    /// When zKillboard was asked; nil when that request failed and only ESI is shown.
    let zkillFetchedAt: Date?
    /// When ESI's hourly map was fetched.
    let esiFetchedAt: Date?

    var zkillFailed: Bool { zkillFetchedAt == nil }

    func name(_ id: Int) -> String { names[id] ?? "#\(id)" }
}

// MARK: Service

/// Fetches and indexes the galaxy-wide `system_kills` / `system_jumps` aggregates so
/// callers can look up per-system activity by ID without re-parsing the full
/// (~5 000-entry) arrays on every use. `ESIClient` already honours the endpoints'
/// hourly `Expires` header; the short local interval here only suppresses repeated
/// re-indexing within a single burst of work (e.g. plotting a route).
actor SystemDangerService {
    static let shared = SystemDangerService()

    struct Snapshot: Sendable {
        let kills: [Int: ESISystemKills]
        let jumps: [Int: Int]
        let fetchedAt: Date

        func danger(for systemId: Int) -> SystemDanger {
            let k = kills[systemId]
            return SystemDanger(
                shipKills: k?.shipKills ?? 0,
                podKills:  k?.podKills ?? 0,
                npcKills:  k?.npcKills ?? 0,
                shipJumps: jumps[systemId] ?? 0
            )
        }

        /// System IDs whose ship + pod kills in the last hour exceed `threshold`.
        func hostileSystems(threshold: Int) -> Set<Int> {
            var out = Set<Int>()
            for (id, k) in kills where k.shipKills + k.podKills > threshold {
                out.insert(id)
            }
            return out
        }
    }

    private var cached: Snapshot?
    private var inFlight: Task<Snapshot, Error>?
    private let minRefreshInterval: TimeInterval = 120

    /// Most recent snapshot without triggering a fetch.
    func cachedSnapshot() -> Snapshot? { cached }

    func snapshot(forceRefresh: Bool = false) async throws -> Snapshot {
        if !forceRefresh, let cached, Date().timeIntervalSince(cached.fetchedAt) < minRefreshInterval {
            return cached
        }
        if let inFlight { return try await inFlight.value }

        let task = Task { () throws -> Snapshot in
            async let killsRaw: [ESISystemKills] = ESIClient.shared.fetch("/universe/system_kills/", bypassCache: forceRefresh)
            async let jumpsRaw: [ESISystemJumps] = ESIClient.shared.fetch("/universe/system_jumps/", bypassCache: forceRefresh)
            let (kills, jumps) = try await (killsRaw, jumpsRaw)

            var killMap = [Int: ESISystemKills](minimumCapacity: kills.count)
            for k in kills { killMap[k.systemId] = k }
            var jumpMap = [Int: Int](minimumCapacity: jumps.count)
            for j in jumps { jumpMap[j.systemId] = j.shipJumps }

            return Snapshot(kills: killMap, jumps: jumpMap, fetchedAt: Date())
        }
        inFlight = task
        defer { inFlight = nil }

        do {
            let snap = try await task.value
            cached = snap
            return snap
        } catch {
            if let cached { return cached }   // serve stale data rather than nothing
            throw error
        }
    }

    // MARK: Route Entry Brief

    /// How far back the brief looks on zKillboard.
    static let briefWindowHours = 3
    /// Upper bound on zKillboard lookups per route, to stay polite on long lowsec routes.
    static let briefMaxSystems = 30

    /// Builds a Route Entry Brief for each of `systemIDs` (in route order, so consecutive
    /// systems count as neighbours even before the galaxy topology has loaded). Pulls each
    /// system's last few hours from zKillboard, fills in attackers from ESI for any kill
    /// zKillboard returned without them, and classifies the lot. A system whose zKillboard
    /// request fails still gets a brief, from ESI's hourly counts only.
    func entryIntel(for systemIDs: [Int], esi: Snapshot?) async -> [Int: SystemIntel] {
        let ids = Array(systemIDs.prefix(Self.briefMaxSystems))
        guard !ids.isEmpty else { return [:] }

        // zKillboard asks for requests spaced out, so ask one system at a time.
        var refs: [Int: [ZKBSystemKill]] = [:]
        var fetchedAt: [Int: Date] = [:]
        for id in ids {
            guard let result = try? await ZKillboardClient.shared.fetchSystemKills(
                systemID: id, pastSeconds: Self.briefWindowHours * 3600
            ) else { continue }
            refs[id] = result.kills
            fetchedAt[id] = result.fetchedAt
        }

        let kills = await threatKills(refs)
        let adjacency = await adjacency(for: ids)
        let shipTypeIDs = Set(kills.flatMap(\.attackerShipTypeIDs))
        let types = await UniverseCache.shared.types(ids: Array(shipTypeIDs))
        let shipGroups = types.mapValues(\.groupId)

        var esiKills: [Int: Int] = [:]
        if let esi { for id in ids { esiKills[id] = esi.danger(for: id).combatKills } }

        let threats = SystemThreatEngine.classify(
            systemIDs: ids, kills: kills, adjacency: adjacency, shipGroups: shipGroups,
            esiCombatKills: esiKills, windowHours: Self.briefWindowHours, now: Date()
        )

        // Resolve every ID the signals mention.
        var gateIDs = Set<Int>(), systemNameIDs = Set(ids), shipIDs = Set<Int>()
        for threat in threats.values {
            for signal in threat.signals {
                switch signal {
                case let .gateCamp(gate, _, _, ships, _):
                    gateIDs.insert(gate); shipIDs.formUnion(ships)
                case let .roamingGang(_, last, previous, ships, _):
                    systemNameIDs.formUnion([last, previous]); shipIDs.formUnion(ships)
                case let .soloHunter(_, ship, _):
                    if let ship { shipIDs.insert(ship) }
                default: break
                }
            }
        }
        var gateDestinations: [Int: Int] = [:]
        for gate in gateIDs {
            if let sg = await UniverseCache.shared.stargate(id: gate) {
                gateDestinations[gate] = sg.destination.systemId
                systemNameIDs.insert(sg.destination.systemId)
            }
        }
        var names: [Int: String] = [:]
        for id in systemNameIDs {
            if let sys = await UniverseCache.shared.solarSystem(id: id) { names[id] = sys.name }
        }
        for (id, type) in await UniverseCache.shared.types(ids: Array(shipIDs)) { names[id] = type.name }

        var out: [Int: SystemIntel] = [:]
        for (id, threat) in threats {
            out[id] = SystemIntel(
                threat: threat, names: names, gateDestinations: gateDestinations,
                zkillFetchedAt: fetchedAt[id], esiFetchedAt: esi?.fetchedAt
            )
        }
        return out
    }

    /// Converts zKillboard entries to `ThreatKill`s, fetching the ESI killmail for any
    /// entry that came back without attackers.
    private func threatKills(_ refs: [Int: [ZKBSystemKill]]) async -> [ThreatKill] {
        await withTaskGroup(of: ThreatKill?.self) { group in
            for (systemID, entries) in refs {
                for entry in entries {
                    group.addTask {
                        if let attackers = entry.attackers, let time = entry.killmailTime {
                            return Self.threatKill(entry, systemID: systemID, time: time, attackers: attackers)
                        }
                        guard let mail: ESIKillmail = try? await ESIClient.shared.fetch(
                            "/killmails/\(entry.killmailId)/\(entry.zkb.hash)/"
                        ) else { return nil }
                        return Self.threatKill(entry, systemID: systemID, time: mail.killmailTime, attackers: mail.attackers)
                    }
                }
            }
            var out: [ThreatKill] = []
            for await kill in group { if let kill { out.append(kill) } }
            return out
        }
    }

    private nonisolated static func threatKill(
        _ entry: ZKBSystemKill, systemID: Int, time: Date, attackers: [ESIKillmailAttacker]
    ) -> ThreatKill {
        ThreatKill(
            id: entry.killmailId,
            systemID: entry.solarSystemId ?? systemID,
            time: time,
            locationID: entry.zkb.locationID,
            attackerIDs: Set(attackers.compactMap(\.characterId)),
            attackerShipTypeIDs: attackers.compactMap(\.shipTypeId),
            isNPC: entry.zkb.isNPC
        )
    }

    /// Stargate links touching `ids`: consecutive route systems, plus the galaxy topology
    /// when it is already loaded (it is never downloaded just for a brief).
    private func adjacency(for ids: [Int]) async -> [Int: Set<Int>] {
        var adj: [Int: Set<Int>] = [:]
        for (a, b) in zip(ids, ids.dropFirst()) {
            adj[a, default: []].insert(b)
            adj[b, default: []].insert(a)
        }
        if let topology = await UniverseTopology.shared.loadedTopology() {
            let wanted = Set(ids)
            for (a, b) in topology.jumps where wanted.contains(a) || wanted.contains(b) {
                adj[a, default: []].insert(b)
                adj[b, default: []].insert(a)
            }
        }
        return adj
    }
}
