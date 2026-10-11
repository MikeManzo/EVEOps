//
//  RouteWatchEngineTests.swift
//  EVEOpsTests
//
//  Covers the live route watch: which changes become notifications (fresh camps and gangs
//  once each, escalation to Danger, Danger one jump ahead, nothing behind the pilot), the
//  zKillboard hour-of-day baseline and its parser, and gangs caught next to the route.
//

import Foundation
import Testing
@testable import EVEOps

private let now = Date(timeIntervalSince1970: 1_800_000_000)   // Fri 2027-01-15 08:00 UTC
private let minute: TimeInterval = 60

private let a = 1, b = 2, c = 3, d = 4
private let route = [a, b, c, d]
private let gate = 50_000_001

private func threat(_ id: Int, _ status: EntryStatus, _ signals: [ThreatSignal] = []) -> SystemThreat {
    SystemThreat(systemID: id, status: status, score: 0, signals: signals, playerKills: signals.count, lastKillAt: nil)
}

private func camp(minutesAgo: Double) -> ThreatSignal {
    .gateCamp(stargateID: gate, kills: 2, pilots: 3, shipTypeIDs: [], lastKill: now.addingTimeInterval(-minutesAgo * minute))
}

private func alerts(previous: [Int: SystemThreat], current: [Int: SystemThreat],
                    pilot: Int? = nil, sent: Set<String> = []) -> [RouteAlert] {
    RouteWatchEngine.alerts(previous: previous, current: current, route: route,
                            pilotSystemID: pilot, alreadySent: sent, now: now)
}

@Suite struct RouteWatchEngineTests {
    // MARK: - Alerts

    @Test func freshCampIsAnnouncedOnce() {
        let current = [c: threat(c, .danger, [camp(minutesAgo: 3)])]
        let first = alerts(previous: [c: threat(c, .clear)], current: current)
        #expect(first.count == 1)
        #expect(first.first?.kind == .gateCamp(stargateID: gate))

        let again = alerts(previous: current, current: current, sent: Set(first.map(\.key)))
        #expect(again.isEmpty)
    }

    @Test func staleCampIsNotAnnounced() {
        let current = [c: threat(c, .caution, [camp(minutesAgo: 90)])]
        #expect(alerts(previous: [:], current: current).isEmpty)
    }

    @Test func gangIsAnnouncedOncePerSighting() {
        let gang = ThreatSignal.roamingGang(pilots: 4, lastSeenSystemID: c, previousSystemID: d,
                                            shipTypeIDs: [], lastKill: now.addingTimeInterval(-2 * minute))
        // The same sighting shows up on two route systems: one alert.
        let current = [b: threat(b, .caution, [gang]), c: threat(c, .danger, [gang])]
        let out = alerts(previous: [:], current: current)
        #expect(out.count == 1)
        #expect(out.first?.kind == .roamingGang(lastSeenSystemID: c))
    }

    @Test func goingToDangerWithoutAPatternIsAnnounced() {
        let out = alerts(previous: [b: threat(b, .caution)], current: [b: threat(b, .danger)])
        #expect(out.map(\.kind) == [.escalated])
    }

    @Test func stayingInDangerIsNotReannounced() {
        #expect(alerts(previous: [b: threat(b, .danger)], current: [b: threat(b, .danger)]).isEmpty)
    }

    @Test func systemsBehindThePilotAreIgnored() {
        let current = [a: threat(a, .danger, [camp(minutesAgo: 1)]), b: threat(b, .clear)]
        #expect(alerts(previous: [a: threat(a, .clear)], current: current, pilot: b).isEmpty)
    }

    @Test func dangerOneJumpAheadIsAnnounced() {
        let current = [c: threat(c, .danger)]
        let out = alerts(previous: current, current: current, pilot: b)
        #expect(out.map(\.kind) == [.nextJumpDanger(fromSystemID: b)])
        #expect(out.first?.systemID == c)

        // Not again while the pilot sits in the same system.
        #expect(alerts(previous: current, current: current, pilot: b, sent: Set(out.map(\.key))).isEmpty)
    }

    @Test func pilotOffRouteSeesEverySystem() {
        let current = [a: threat(a, .danger)]
        #expect(alerts(previous: [a: threat(a, .clear)], current: current, pilot: 999).count == 1)
    }

    // MARK: - Baseline

    /// A flat heatmap of `value` with one cell changed.
    private func heatmap(_ value: Int, set day: Int, _ hour: Int, to cell: Int) -> [[Int]] {
        var grid = Array(repeating: Array(repeating: value, count: 24), count: 7)
        grid[day][hour] = cell
        return grid
    }

    @Test func baselineReadsTheCurrentUTCHour() {
        // `now` is a Friday (index 5), 08:00 UTC.
        let busy = RouteWatchEngine.baseline(activity: heatmap(10, set: 5, 8, to: 40), weekKills: 120, now: now)
        #expect(busy == SystemBaseline(hour: .busier, weekKills: 120))
        let quiet = RouteWatchEngine.baseline(activity: heatmap(10, set: 5, 8, to: 1), weekKills: nil, now: now)
        #expect(quiet?.hour == .quieter)
        let usual = RouteWatchEngine.baseline(activity: heatmap(10, set: 5, 8, to: 10), weekKills: nil, now: now)
        #expect(usual?.hour == .typical)
    }

    @Test func sparseHeatmapMeansRarelyKills() {
        let sparse = RouteWatchEngine.baseline(activity: heatmap(0, set: 2, 3, to: 5), weekKills: 0, now: now)
        #expect(sparse?.hour == .rarelyKills)
    }

    @Test func malformedHeatmapIsIgnored() {
        #expect(RouteWatchEngine.baseline(activity: [[1, 2, 3]], weekKills: nil, now: now) == nil)
    }

    @Test func parsesZKillboardActivity() throws {
        var activity: [String: Any] = ["max": 9, "days": ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]]
        for day in 0..<7 { activity[String(day)] = Array(repeating: day, count: 24) }
        let json: [String: Any] = ["activity": activity, "activepvp": ["kills": ["type": "Total Kills", "count": 1323]]]
        let data = try JSONSerialization.data(withJSONObject: json)

        let parsed = try #require(ZKillboardClient.parseActivity(data))
        #expect(parsed.heatmap.count == 7)
        #expect(parsed.heatmap[3] == Array(repeating: 3, count: 24))
        #expect(parsed.weekKills == 1323)
        #expect(ZKillboardClient.parseActivity(Data("{}".utf8)) == nil)
    }

    // MARK: - Gangs next to the route

    @Test func gangOffRouteNextToTheRouteIsCaught() throws {
        // Route system 10 neighbours 20; 20 neighbours 30. Neither 20 nor 30 is on the route.
        let adjacency: [Int: Set<Int>] = [10: [20], 20: [10, 30], 30: [20]]
        func kill(_ system: Int, _ minutesAgo: Double) -> ThreatKill {
            ThreatKill(id: system * 100 + Int(minutesAgo), systemID: system, time: now.addingTimeInterval(-minutesAgo * minute),
                       locationID: nil, attackerIDs: [7, 8, 9], attackerShipTypeIDs: [], isNPC: false)
        }
        let threats = SystemThreatEngine.classify(
            systemIDs: [10], kills: [kill(30, 25), kill(20, 5)], adjacency: adjacency, now: now
        )
        let here = try #require(threats[10])
        #expect(here.status == .caution)
        #expect(here.playerKills == 0)
        guard case let .roamingGang(pilots, lastSeen, previous, _, _)? = here.signals.first else {
            Issue.record("expected a gang, got \(here.signals)"); return
        }
        #expect(pilots == 3)
        #expect(lastSeen == 20)
        #expect(previous == 30)
    }
}
