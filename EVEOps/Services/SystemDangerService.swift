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

    /// Player-vs-player activity — the figure that actually matters for route safety.
    var combatKills: Int { shipKills + podKills }
    var isHostile: Bool { combatKills > 0 }

    static let none = SystemDanger()
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
}
