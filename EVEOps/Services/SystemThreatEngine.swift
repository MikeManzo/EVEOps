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

// MARK:  Models

/// One killmail reduced to what threat classification needs.
nonisolated struct ThreatKill: Sendable, Equatable {
    let id: Int
    let systemID: Int
    let time: Date
    /// zKillboard's nearest celestial. A stargate when it falls in `SystemThreatEngine.stargateIDs`.
    let locationID: Int?
    /// Player attackers' character IDs. NPCs and structures are left out.
    let attackerIDs: Set<Int>
    /// Every attacker's ship type, one entry per attacker that has one.
    let attackerShipTypeIDs: [Int]
    /// zKillboard's `npc` flag: the victim died to NPCs only.
    let isNPC: Bool

    var isPlayerKill: Bool { !isNPC && !attackerIDs.isEmpty }
    var stargateID: Int? {
        guard let locationID, SystemThreatEngine.stargateIDs.contains(locationID) else { return nil }
        return locationID
    }
}

/// How a pilot should feel about jumping in, from least to most worrying.
nonisolated enum EntryStatus: Int, Comparable, Sendable, CaseIterable {
    case clear, caution, danger

    static func < (a: Self, b: Self) -> Bool { a.rawValue < b.rawValue }

    var label: String {
        switch self {
        case .clear:   return "Clear"
        case .caution: return "Caution"
        case .danger:  return "Danger"
        }
    }
}

/// One finding about a system, in the order the brief should show them.
nonisolated enum ThreatSignal: Sendable, Equatable {
    /// At least two kills on the same stargate within `campWindow`, sharing attackers.
    case gateCamp(stargateID: Int, kills: Int, pilots: Int, shipTypeIDs: [Int], lastKill: Date)
    /// The same pilots killed in this system and an adjacent one. `lastSeenSystemID` is
    /// where they were most recently; `previousSystemID` where they were before that.
    case roamingGang(pilots: Int, lastSeenSystemID: Int, previousSystemID: Int, shipTypeIDs: [Int], lastKill: Date)
    /// Small-gang kills by cloaky hunting hulls (covert ops, bombers, recons, T3 cruisers).
    case soloHunter(kills: Int, shipTypeID: Int?, lastKill: Date)
    /// Player kills that fit none of the patterns above.
    case recentKills(count: Int, lastKill: Date)
    /// ESI's hourly map counts kills that zKillboard doesn't have yet.
    case unreportedKills(count: Int)
    /// No player kills in the whole window.
    case quiet(windowHours: Int)
}

/// The classified picture for one system.
nonisolated struct SystemThreat: Sendable, Equatable {
    let systemID: Int
    let status: EntryStatus
    /// Recency-weighted player kills: each kill counts 1 when fresh, halving every `halfLife`.
    let score: Double
    let signals: [ThreatSignal]
    let playerKills: Int
    let lastKillAt: Date?
}

// MARK:  Engine

/// Sorts recent killmails into the patterns a pilot can act on: a camp on a specific
/// gate, a gang moving between neighbouring systems, a lone cloaky hunter, or just
/// activity. Pure inputs only, so it is fully unit-testable.
nonisolated enum SystemThreatEngine {
    /// Stargate item IDs live in this range; other celestials (planets, moons, belts,
    /// stations) don't.
    static let stargateIDs = 50_000_000..<60_000_000

    /// Kills on the same gate this close together, sharing a pilot, are one camp.
    static let campWindow: TimeInterval = 20 * 60
    /// Sightings of the same pilots this close together, in adjacent systems, are one gang.
    static let gangWindow: TimeInterval = 60 * 60
    /// A gang needs at least this many shared pilots. One pilot is a hunter, not a gang.
    static let gangMinPilots = 2
    /// Kills older than this no longer count toward "fresh" danger.
    static let freshWindow: TimeInterval = 30 * 60
    static let halfLife: TimeInterval = 20 * 60
    /// Score at or above which a system is `danger` even without a named pattern.
    static let dangerScore: Double = 3
    /// Kills with at most this many player attackers can be a hunter's.
    static let hunterMaxAttackers = 3

    /// Covert Ops, Force Recon, Stealth Bomber, Black Ops, Strategic Cruiser: the hulls
    /// that hunt cloaked and leave no trace until they kill.
    static let hunterGroupIDs: Set<Int> = [830, 833, 834, 898, 963]

    /// Weight of a kill `age` seconds old. 1 when fresh, halving every `halfLife`.
    static func weight(age: TimeInterval) -> Double {
        pow(0.5, max(0, age) / halfLife)
    }

    /// Classifies every system in `systemIDs`.
    /// - Parameters:
    ///   - kills: player and NPC kills across all of `systemIDs` (others are ignored).
    ///   - adjacency: stargate neighbours; only links between `systemIDs` matter.
    ///   - shipGroups: ship type → group ID, for spotting hunter hulls. Missing types are
    ///     treated as non-hunters.
    ///   - esiCombatKills: ESI's last-hour ship + pod kills per system, used only to flag
    ///     kills zKillboard hasn't received yet.
    ///   - windowHours: how far back `kills` reach, for the "quiet" wording.
    static func classify(
        systemIDs: [Int],
        kills: [ThreatKill],
        adjacency: [Int: Set<Int>],
        shipGroups: [Int: Int] = [:],
        esiCombatKills: [Int: Int] = [:],
        windowHours: Int = 3,
        now: Date
    ) -> [Int: SystemThreat] {
        let wanted = Set(systemIDs)
        let playerKills = kills.filter { $0.isPlayerKill && wanted.contains($0.systemID) && $0.time <= now }
        let bySystem = Dictionary(grouping: playerKills, by: \.systemID)
        let gangs = roamingGangs(playerKills, adjacency: adjacency)

        var out: [Int: SystemThreat] = [:]
        for id in systemIDs {
            let local = (bySystem[id] ?? []).sorted { $0.time < $1.time }
            out[id] = threat(
                systemID: id, kills: local,
                gangs: gangs.filter { gang in
                    // Gangs that killed here, or were last seen one jump away.
                    gang.systems.contains(id) || adjacency[id]?.contains(gang.lastSeen.systemID) == true
                },
                shipGroups: shipGroups,
                esiCombatKills: esiCombatKills[id] ?? 0,
                windowHours: windowHours, now: now
            )
        }
        return out
    }

    // MARK: Per system

    private static func threat(
        systemID: Int, kills: [ThreatKill], gangs: [Gang],
        shipGroups: [Int: Int], esiCombatKills: Int, windowHours: Int, now: Date
    ) -> SystemThreat {
        var signals: [ThreatSignal] = []
        var explained = Set<Int>()   // kill IDs already covered by a signal
        var status = EntryStatus.clear

        let camps = gateCamps(kills)
        for camp in camps {
            signals.append(.gateCamp(
                stargateID: camp.stargateID, kills: camp.kills.count, pilots: camp.pilots.count,
                shipTypeIDs: topShips(camp.kills), lastKill: camp.lastKill
            ))
            explained.formUnion(camp.kills.map(\.id))
            status = max(status, now.timeIntervalSince(camp.lastKill) <= freshWindow ? .danger : .caution)
        }

        for gang in gangs {
            let last = gang.lastSeen
            // A gang that never came here only matters while it could still arrive.
            if !gang.systems.contains(systemID), now.timeIntervalSince(last.time) > gangWindow { continue }
            let previous = gang.sightings.filter { $0.systemID != last.systemID }.max { $0.time < $1.time }!
            signals.append(.roamingGang(
                pilots: gang.pilots.count, lastSeenSystemID: last.systemID,
                previousSystemID: previous.systemID, shipTypeIDs: topShips(gang.sightings),
                lastKill: last.time
            ))
            explained.formUnion(gang.sightings.filter { $0.systemID == systemID }.map(\.id))
            let fresh = now.timeIntervalSince(last.time) <= freshWindow
            status = max(status, fresh && last.systemID == systemID ? .danger : .caution)
        }

        let rest = kills.filter { !explained.contains($0.id) }
        let hunterKills = rest.filter { isHunterKill($0, shipGroups: shipGroups) }
        if let last = hunterKills.last {
            let hull = last.attackerShipTypeIDs.first { shipGroups[$0].map(hunterGroupIDs.contains) ?? false }
            signals.append(.soloHunter(kills: hunterKills.count, shipTypeID: hull, lastKill: last.time))
            explained.formUnion(hunterKills.map(\.id))
            status = max(status, .caution)
        }

        let other = rest.filter { !explained.contains($0.id) }
        if let last = other.last {
            signals.append(.recentKills(count: other.count, lastKill: last.time))
            status = max(status, .caution)
        }

        let score = kills.reduce(0) { $0 + weight(age: now.timeIntervalSince($1.time)) }
        if score >= dangerScore { status = .danger }

        // ESI's hourly count can be ahead of zKillboard. Only worth saying when zKill shows
        // fewer kills in the last hour than ESI does.
        let zkillLastHour = kills.filter { now.timeIntervalSince($0.time) <= 3600 }.count
        if esiCombatKills > zkillLastHour {
            signals.append(.unreportedKills(count: esiCombatKills - zkillLastHour))
            status = max(status, .caution)
        }

        if kills.isEmpty && signals.isEmpty {
            signals.append(.quiet(windowHours: windowHours))
        }

        return SystemThreat(
            systemID: systemID, status: status, score: score, signals: signals,
            playerKills: kills.count, lastKillAt: kills.last?.time
        )
    }

    // MARK: Gate camps

    struct Camp: Equatable {
        let stargateID: Int
        var kills: [ThreatKill]
        var pilots: Set<Int>
        var lastKill: Date { kills.last!.time }
    }

    /// Chains kills on the same stargate that are within `campWindow` of the previous one
    /// and share at least one pilot with the chain so far. Chains of 2+ kills are camps,
    /// newest first.
    static func gateCamps(_ kills: [ThreatKill]) -> [Camp] {
        let atGates = Dictionary(grouping: kills.filter { $0.stargateID != nil }, by: { $0.stargateID! })
        var camps: [Camp] = []
        for (gate, gateKills) in atGates {
            var chain: Camp?
            for kill in gateKills.sorted(by: { $0.time < $1.time }) {
                if var current = chain,
                   kill.time.timeIntervalSince(current.lastKill) <= campWindow,
                   !current.pilots.isDisjoint(with: kill.attackerIDs) {
                    current.kills.append(kill)
                    current.pilots.formUnion(kill.attackerIDs)
                    chain = current
                } else {
                    if let done = chain, done.kills.count >= 2 { camps.append(done) }
                    chain = Camp(stargateID: gate, kills: [kill], pilots: kill.attackerIDs)
                }
            }
            if let done = chain, done.kills.count >= 2 { camps.append(done) }
        }
        return camps.sorted { $0.lastKill > $1.lastKill }
    }

    // MARK: Roaming gangs

    struct Gang: Equatable {
        var pilots: Set<Int>
        var sightings: [ThreatKill]
        var systems: Set<Int> { Set(sightings.map(\.systemID)) }
        var lastSeen: ThreatKill { sightings.max { $0.time < $1.time }! }
    }

    /// Finds pilots who killed in two adjacent systems within `gangWindow` of each other,
    /// at least `gangMinPilots` of them together. Overlapping pairs merge into one gang so
    /// a gang crossing three systems is reported once per system, not twice.
    static func roamingGangs(_ kills: [ThreatKill], adjacency: [Int: Set<Int>]) -> [Gang] {
        let sorted = kills.sorted { $0.time < $1.time }
        var gangs: [Gang] = []
        for (i, a) in sorted.enumerated() {
            for b in sorted[(i + 1)...] {
                guard b.time.timeIntervalSince(a.time) <= gangWindow else { break }
                guard a.systemID != b.systemID,
                      adjacency[a.systemID]?.contains(b.systemID) == true
                        || adjacency[b.systemID]?.contains(a.systemID) == true else { continue }
                let shared = a.attackerIDs.intersection(b.attackerIDs)
                guard shared.count >= gangMinPilots else { continue }

                if let idx = gangs.firstIndex(where: { !$0.pilots.isDisjoint(with: shared) }) {
                    gangs[idx].pilots.formUnion(shared)
                    for k in [a, b] where !gangs[idx].sightings.contains(where: { $0.id == k.id }) {
                        gangs[idx].sightings.append(k)
                    }
                } else {
                    gangs.append(Gang(pilots: shared, sightings: [a, b]))
                }
            }
        }
        return gangs
    }

    // MARK: Helpers

    static func isHunterKill(_ kill: ThreatKill, shipGroups: [Int: Int]) -> Bool {
        guard kill.attackerIDs.count <= hunterMaxAttackers else { return false }
        return kill.attackerShipTypeIDs.contains { shipGroups[$0].map(hunterGroupIDs.contains) ?? false }
    }

    /// The two most-flown attacker hulls across `kills`, most common first.
    static func topShips(_ kills: [ThreatKill]) -> [Int] {
        var counts: [Int: Int] = [:]
        for kill in kills { for ship in kill.attackerShipTypeIDs { counts[ship, default: 0] += 1 } }
        return counts.sorted { $0.value != $1.value ? $0.value > $1.value : $0.key < $1.key }
            .prefix(2).map(\.key)
    }
}
