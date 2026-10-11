//
//  SystemThreatEngineTests.swift
//  EVEOpsTests
//
//  Covers the Route Entry Brief classifier: gate camps (same gate, close in time, shared
//  pilots), roaming gangs across adjacent systems, cloaky hunters, recency weighting,
//  ESI's hourly count running ahead of zKillboard, and quiet systems. Pure inputs only.
//

import Foundation
import Testing
@testable import EVEOps

private let now = Date(timeIntervalSince1970: 1_800_000_000)
private let minute: TimeInterval = 60

private let tama = 30002813, nourvukaiken = 30002812, kedama = 30002814, far = 30000142
private let gateToNourvukaiken = 50_001_234, otherGate = 50_001_235
private let planet = 40_178_431

private let sabre = 22456, loki = 29990, buzzard = 11192
private let groups = [sabre: 541, loki: 963, buzzard: 830]

/// Tama — Nourvukaiken and Tama — Kedama are linked; `far` touches nothing.
private let adjacency: [Int: Set<Int>] = [
    tama: [nourvukaiken, kedama], nourvukaiken: [tama], kedama: [tama],
]

private func kill(_ system: Int, minutesAgo: Double, at location: Int? = nil,
                  by attackers: Set<Int>, ships: [Int] = [sabre], npc: Bool = false) -> ThreatKill {
    ThreatKill(id: UUID().hashValue, systemID: system, time: now.addingTimeInterval(-minutesAgo * minute),
                      locationID: location, attackerIDs: attackers, attackerShipTypeIDs: ships, isNPC: npc)
}

private func classify(_ kills: [ThreatKill], systems: [Int] = [tama, nourvukaiken, kedama, far],
                      esi: [Int: Int] = [:]) -> [Int: SystemThreat] {
    SystemThreatEngine.classify(systemIDs: systems, kills: kills, adjacency: adjacency,
                                shipGroups: groups, esiCombatKills: esi, now: now)
}

@Suite struct SystemThreatEngineTests {
    // MARK: - Quiet

    @Test func noKillsIsQuietAndClear() {
        let t = classify([])[far]!
        #expect(t.status == .clear)
        #expect(t.signals == [.quiet(windowHours: 3)])
        #expect(t.lastKillAt == nil)
    }

    @Test func npcKillsDoNotCount() {
        let t = classify([kill(far, minutesAgo: 2, by: [], npc: true)])[far]!
        #expect(t.status == .clear)
        #expect(t.playerKills == 0)
    }

    // MARK: - Gate camps

    @Test func twoKillsOnOneGateBySamePilotsIsACamp() {
        let kills = [
            kill(tama, minutesAgo: 14, at: gateToNourvukaiken, by: [1, 2, 3]),
            kill(tama, minutesAgo: 6, at: gateToNourvukaiken, by: [2, 3, 4], ships: [sabre, loki]),
        ]
        let t = classify(kills)[tama]!
        #expect(t.status == .danger)
        guard case let .gateCamp(gate, count, pilots, ships, last)? = t.signals.first else {
            Issue.record("expected a gate camp, got \(t.signals)"); return
        }
        #expect(gate == gateToNourvukaiken)
        #expect(count == 2)
        #expect(pilots == 4)
        #expect(ships.first == sabre)
        #expect(last == now.addingTimeInterval(-6 * minute))
    }

    @Test func killsTooFarApartAreNotACamp() {
        let kills = [
            kill(tama, minutesAgo: 90, at: gateToNourvukaiken, by: [1]),
            kill(tama, minutesAgo: 30, at: gateToNourvukaiken, by: [1]),
        ]
        #expect(SystemThreatEngine.gateCamps(kills).isEmpty)
    }

    @Test func differentPilotsOnOneGateAreNotACamp() {
        let kills = [
            kill(tama, minutesAgo: 10, at: gateToNourvukaiken, by: [1]),
            kill(tama, minutesAgo: 5, at: gateToNourvukaiken, by: [2]),
        ]
        #expect(SystemThreatEngine.gateCamps(kills).isEmpty)
    }

    @Test func killsOnDifferentGatesOrOffGateAreNotACamp() {
        let kills = [
            kill(tama, minutesAgo: 10, at: gateToNourvukaiken, by: [1]),
            kill(tama, minutesAgo: 8, at: otherGate, by: [1]),
            kill(tama, minutesAgo: 6, at: planet, by: [1]),
        ]
        #expect(SystemThreatEngine.gateCamps(kills).isEmpty)
    }

    @Test func oldCampIsOnlyCaution() {
        let kills = [
            kill(tama, minutesAgo: 150, at: gateToNourvukaiken, by: [1, 2]),
            kill(tama, minutesAgo: 140, at: gateToNourvukaiken, by: [1, 2]),
        ]
        let t = classify(kills)[tama]!
        #expect(t.status == .caution)
        #expect(t.signals.contains { if case .gateCamp = $0 { true } else { false } })
    }

    // MARK: - Roaming gangs

    @Test func samePilotsInAdjacentSystemsAreAGang() {
        let kills = [
            kill(nourvukaiken, minutesAgo: 40, by: [1, 2, 3, 9]),
            kill(tama, minutesAgo: 10, by: [1, 2, 3], ships: [loki]),
        ]
        let threats = classify(kills)
        let here = threats[tama]!
        #expect(here.status == .danger)
        guard case let .roamingGang(pilots, lastSeen, previous, _, _)? = here.signals.first else {
            Issue.record("expected a gang, got \(here.signals)"); return
        }
        #expect(pilots == 3)
        #expect(lastSeen == tama)
        #expect(previous == nourvukaiken)

        // Where they came from is only caution: they've moved on.
        #expect(threats[nourvukaiken]!.status == .caution)
        // One jump from where they are now: warned, though nothing died there.
        let ahead = threats[kedama]!
        #expect(ahead.status == .caution)
        #expect(ahead.playerKills == 0)
        #expect(ahead.signals.contains { if case .roamingGang = $0 { true } else { false } })
        // Not adjacent to anything: untouched.
        #expect(threats[far]!.status == .clear)
    }

    @Test func onePilotAcrossSystemsIsNotAGang() {
        let kills = [
            kill(nourvukaiken, minutesAgo: 30, by: [1]),
            kill(tama, minutesAgo: 10, by: [1]),
        ]
        #expect(SystemThreatEngine.roamingGangs(kills, adjacency: adjacency).isEmpty)
    }

    @Test func gangInNonAdjacentSystemsIsNotLinked() {
        let kills = [
            kill(far, minutesAgo: 30, by: [1, 2]),
            kill(tama, minutesAgo: 10, by: [1, 2]),
        ]
        #expect(SystemThreatEngine.roamingGangs(kills, adjacency: adjacency).isEmpty)
    }

    @Test func staleGangNextDoorIsIgnored() {
        let kills = [
            kill(nourvukaiken, minutesAgo: 170, by: [1, 2]),
            kill(tama, minutesAgo: 150, by: [1, 2]),
        ]
        let ahead = classify(kills)[kedama]!
        #expect(ahead.status == .clear)
    }

    // MARK: - Hunters

    @Test func smallCloakyKillIsAHunter() {
        let t = classify([kill(far, minutesAgo: 25, at: planet, by: [7], ships: [buzzard])])[far]!
        #expect(t.status == .caution)
        #expect(t.signals == [.soloHunter(kills: 1, shipTypeID: buzzard, lastKill: now.addingTimeInterval(-25 * minute))])
    }

    @Test func bigGangInCloakyHullsIsNotAHunter() {
        let k = kill(far, minutesAgo: 25, by: [1, 2, 3, 4, 5], ships: [loki, loki])
        #expect(!SystemThreatEngine.isHunterKill(k, shipGroups: groups))
        #expect(classify([k])[far]!.signals.first == .recentKills(count: 1, lastKill: k.time))
    }

    // MARK: - Scoring

    @Test func weightHalvesEveryHalfLife() {
        #expect(SystemThreatEngine.weight(age: 0) == 1)
        #expect(abs(SystemThreatEngine.weight(age: 20 * minute) - 0.5) < 1e-9)
        #expect(abs(SystemThreatEngine.weight(age: 40 * minute) - 0.25) < 1e-9)
    }

    @Test func manyFreshUnrelatedKillsAreDanger() {
        let kills = (0..<4).map { kill(far, minutesAgo: Double($0), by: [100 + $0]) }
        let t = classify(kills)[far]!
        #expect(t.score >= SystemThreatEngine.dangerScore)
        #expect(t.status == .danger)
    }

    @Test func oldScatteredKillsAreOnlyCaution() {
        let kills = (0..<4).map { kill(far, minutesAgo: 120 + Double($0) * 10, by: [100 + $0]) }
        #expect(classify(kills)[far]!.status == .caution)
    }

    // MARK: - ESI cross-check

    @Test func esiAheadOfZKillIsFlagged() {
        let t = classify([], esi: [far: 2])[far]!
        #expect(t.status == .caution)
        #expect(t.signals == [.unreportedKills(count: 2)])
    }

    @Test func esiMatchingZKillIsNotFlagged() {
        let t = classify([kill(far, minutesAgo: 10, by: [1, 2, 3, 4])], esi: [far: 1])[far]!
        #expect(!t.signals.contains(.unreportedKills(count: 1)))
    }
}
