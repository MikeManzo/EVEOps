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

// MARK:  Context models

/// How a system's kills usually run at this hour, from zKillboard's weekday × hour heatmap.
nonisolated struct SystemBaseline: Sendable, Equatable {
    enum HourActivity: Sendable, Equatable {
        /// Too few kills on record to have a pattern.
        case rarelyKills
        case quieter, typical, busier
    }
    let hour: HourActivity
    /// Kills in the past week, when zKillboard reported it.
    let weekKills: Int?
}

/// Faction Warfare state of a system, from ESI `/fw/systems/`.
nonisolated struct FactionWarfareState: Sendable, Equatable {
    /// ESI's `contested` value: captured, contested, uncontested or vulnerable.
    let contested: String
    /// Victory points as a percentage of the threshold.
    let percent: Int

    /// Contested and vulnerable systems are where FW pilots are actively fighting.
    var isFrontline: Bool { contested == "contested" || contested == "vulnerable" }
}

/// Slow-changing facts about a system that set expectations without being danger signals.
nonisolated struct SystemContext: Sendable, Equatable {
    var baseline: SystemBaseline?
    var factionWarfare: FactionWarfareState?
    /// Wormhole hubs (Thera, Turnur) with a live connection into this system, per EVE-Scout.
    var wormholeHubs: [String] = []

    var isEmpty: Bool { baseline == nil && factionWarfare == nil && wormholeHubs.isEmpty }
}

// MARK:  Alerts

/// Something worth interrupting the pilot for while they watch a route.
nonisolated struct RouteAlert: Sendable, Equatable {
    enum Kind: Sendable, Equatable {
        /// A fresh camp on one of the system's gates.
        case gateCamp(stargateID: Int)
        /// A fresh gang killing in or next to the system.
        case roamingGang(lastSeenSystemID: Int)
        /// The system went to Danger for another reason (a burst of kills).
        case escalated
        /// The pilot is one jump from a Danger system on their route.
        case nextJumpDanger(fromSystemID: Int)
    }
    let systemID: Int
    let kind: Kind
    /// Identifies the alert so the same camp or gang isn't announced twice.
    let key: String
}

// MARK:  Engine

/// Decides which changes on a watched route deserve a notification, and reads the
/// zKillboard heatmap. Pure inputs only.
nonisolated enum RouteWatchEngine {
    /// New alerts between two classifications of the same route.
    /// - Parameters:
    ///   - route: every system on the route, in order.
    ///   - pilotSystemID: where the pilot is, if known. When they're on the route, only
    ///     systems ahead of them are announced.
    ///   - alreadySent: keys of alerts sent earlier; those aren't repeated.
    static func alerts(
        previous: [Int: SystemThreat],
        current: [Int: SystemThreat],
        route: [Int],
        pilotSystemID: Int?,
        alreadySent: Set<String>,
        now: Date
    ) -> [RouteAlert] {
        var ahead = route
        var nextSystemID: Int?
        if let pilotSystemID, let index = route.firstIndex(of: pilotSystemID) {
            ahead = Array(route[(index + 1)...])
            nextSystemID = ahead.first
        }

        var out: [RouteAlert] = []
        var sent = alreadySent
        func add(_ alert: RouteAlert) {
            guard !sent.contains(alert.key) else { return }
            sent.insert(alert.key)
            out.append(alert)
        }

        for id in ahead {
            guard let threat = current[id] else { continue }
            var announced = false
            for signal in threat.signals {
                switch signal {
                case let .gateCamp(gate, _, _, _, lastKill)
                    where now.timeIntervalSince(lastKill) <= SystemThreatEngine.freshWindow:
                    // Keyed by camp start would re-announce a long camp; by gate + hour is
                    // once per camp in practice, and again if it comes back later.
                    add(RouteAlert(systemID: id, kind: .gateCamp(stargateID: gate),
                                   key: "camp-\(gate)-\(hourBucket(lastKill))"))
                    announced = true
                case let .roamingGang(_, lastSeen, _, _, lastKill)
                    where now.timeIntervalSince(lastKill) <= SystemThreatEngine.freshWindow:
                    // Once per system the gang reaches, however many route systems that
                    // touches, and not again for every kill it makes there.
                    add(RouteAlert(systemID: id, kind: .roamingGang(lastSeenSystemID: lastSeen),
                                   key: "gang-\(lastSeen)-\(hourBucket(lastKill))"))
                    announced = true
                default:
                    break
                }
            }
            let was = previous[id]?.status ?? .clear
            if !announced, threat.status == .danger, was < .danger {
                add(RouteAlert(systemID: id, kind: .escalated,
                               key: "danger-\(id)-\(Int(now.timeIntervalSince1970))"))
            }
        }

        if let pilotSystemID, let next = nextSystemID, current[next]?.status == .danger {
            add(RouteAlert(systemID: next, kind: .nextJumpDanger(fromSystemID: pilotSystemID),
                           key: "next-\(pilotSystemID)-\(next)"))
        }
        return out
    }

    private static func hourBucket(_ date: Date) -> Int { Int(date.timeIntervalSince1970 / 3600) }

    // MARK: Baseline

    /// Below this many kills on the whole heatmap there's no pattern to speak of.
    static let minHeatmapKills = 50

    /// Reads zKillboard's `activity` heatmap for the current UTC weekday and hour.
    /// - Parameter activity: seven rows (Sunday first) of 24 hourly kill counts, UTC.
    static func baseline(activity: [[Int]], weekKills: Int?, now: Date) -> SystemBaseline? {
        guard activity.count == 7, activity.allSatisfy({ $0.count == 24 }) else { return nil }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let day = calendar.component(.weekday, from: now) - 1   // 1 = Sunday
        let hour = calendar.component(.hour, from: now)

        let total = activity.joined().reduce(0, +)
        guard total >= minHeatmapKills else {
            return SystemBaseline(hour: .rarelyKills, weekKills: weekKills)
        }
        let mean = Double(total) / Double(7 * 24)
        let ratio = Double(activity[day][hour]) / mean
        let level: SystemBaseline.HourActivity = ratio < 0.6 ? .quieter : ratio > 1.4 ? .busier : .typical
        return SystemBaseline(hour: level, weekKills: weekKills)
    }
}
