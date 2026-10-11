//
//  BriefCalibrationEngineTests.swift
//  EVEOpsTests
//
//  Covers entry brief accuracy tracking: which verdicts get logged (repeats within the
//  window collapse), when a verdict can be checked, what counts as a kill following it
//  (player kills only, inside the window, camps confirmed on the same gate), log bounds,
//  and the report's per-status and per-signal rates. Pure inputs only.
//

import Foundation
import Testing
@testable import EVEOps

private let now = Date(timeIntervalSince1970: 1_800_000_000)
private let minute: TimeInterval = 60

private let tama = 30002813, rancer = 30002560
private let gate = 50_001_234, otherGate = 50_001_235

private func threat(_ system: Int, _ status: EntryStatus, _ signals: [ThreatSignal] = []) -> SystemThreat {
    SystemThreat(systemID: system, status: status, score: 0,
                 signals: signals.isEmpty && status == .clear ? [.quiet(windowHours: 3)] : signals,
                 playerKills: 0, lastKillAt: nil)
}

private func camp(at gateID: Int = gate) -> ThreatSignal {
    .gateCamp(stargateID: gateID, kills: 2, pilots: 3, shipTypeIDs: [], lastKill: now)
}

private func kill(_ system: Int, at time: Date, location: Int? = nil, npc: Bool = false,
                  attackers: Set<Int> = [1]) -> ThreatKill {
    ThreatKill(id: UUID().hashValue, systemID: system, time: time, locationID: location,
               attackerIDs: attackers, attackerShipTypeIDs: [], isNPC: npc)
}

private func verdict(_ threat: SystemThreat, at time: Date = now, kills: Int?, campKills: Int = 0) -> BriefVerdict {
    var v = BriefVerdict(threat: threat, issuedAt: time)
    if let kills { v.outcome = .init(checkedAt: time, playerKills: kills, campGateKills: campKills) }
    return v
}

@Suite struct BriefCalibrationEngineTests {
    // MARK: - Recording

    @Test func verdictKeepsSignalKindsAndCampGates() {
        let v = BriefVerdict(threat: threat(tama, .danger, [camp(), camp(at: otherGate), .recentKills(count: 1, lastKill: now)]),
                             issuedAt: now)
        #expect(v.kinds == [.gateCamp, .recentKills])
        #expect(v.campGateIDs == [gate, otherGate])
        #expect(v.outcome == nil)
    }

    @Test func repeatedVerdictWithinWindowIsLoggedOnce() {
        var log = BriefCalibrationEngine.record([threat(tama, .clear)], into: [], now: now)
        log = BriefCalibrationEngine.record([threat(tama, .clear)], into: log, now: now + 10 * minute)
        #expect(log.count == 1)
    }

    @Test func changedStatusIsLoggedAgain() {
        var log = BriefCalibrationEngine.record([threat(tama, .clear)], into: [], now: now)
        log = BriefCalibrationEngine.record([threat(tama, .danger, [camp()])], into: log, now: now + 5 * minute)
        #expect(log.map(\.status) == [.clear, .danger])
    }

    @Test func sameVerdictAfterWindowIsLoggedAgain() {
        var log = BriefCalibrationEngine.record([threat(tama, .clear)], into: [], now: now)
        log = BriefCalibrationEngine.record([threat(tama, .clear)], into: log, now: now + 31 * minute)
        #expect(log.count == 2)
    }

    @Test func otherSystemsAreIndependent() {
        var log = BriefCalibrationEngine.record([threat(tama, .clear)], into: [], now: now)
        log = BriefCalibrationEngine.record([threat(tama, .clear), threat(rancer, .clear)], into: log, now: now + minute)
        #expect(log.map(\.systemID) == [tama, rancer])
    }

    // MARK: - Bounds

    @Test func pruneDropsOldAndStaleUncheckedVerdicts() {
        let old = verdict(threat(tama, .clear), at: now - 31 * 86_400, kills: 0)
        let staleUnchecked = verdict(threat(tama, .clear), at: now - 7 * 86_400, kills: nil)
        let checkedWeekOld = verdict(threat(tama, .clear), at: now - 7 * 86_400, kills: 0)
        let fresh = verdict(threat(tama, .clear), at: now - minute, kills: nil)
        let kept = BriefCalibrationEngine.prune([old, staleUnchecked, checkedWeekOld, fresh], now: now)
        #expect(kept.map(\.id) == [checkedWeekOld.id, fresh.id])
    }

    @Test func pruneKeepsNewestUpToTheCap() {
        let log = (0..<(BriefCalibrationEngine.maxVerdicts + 5)).map {
            verdict(threat(tama, .clear), at: now - Double($0) * minute, kills: 0)
        }
        let kept = BriefCalibrationEngine.prune(log, now: now)
        #expect(kept.count == BriefCalibrationEngine.maxVerdicts)
        #expect(kept.last?.issuedAt == now)
    }

    // MARK: - When to check

    @Test func verdictIsDueOnlyAfterWindowAndLag() {
        let v = verdict(threat(tama, .clear), kills: nil)
        #expect(!BriefCalibrationEngine.isDue(v, now: now + 30 * minute))
        #expect(!BriefCalibrationEngine.isDue(v, now: now + 44 * minute))
        #expect(BriefCalibrationEngine.isDue(v, now: now + 45 * minute))
        #expect(BriefCalibrationEngine.due([verdict(threat(tama, .clear), kills: 0)], now: now + 3600).isEmpty)
    }

    @Test func lookbackCoversOldestVerdictInWholeHours() {
        let vs = [verdict(threat(tama, .clear), at: now - 90 * minute, kills: nil),
                  verdict(threat(tama, .clear), at: now - 50 * minute, kills: nil)]
        #expect(BriefCalibrationEngine.lookback(for: vs, now: now) == 2 * 3600)
        let ancient = [verdict(threat(tama, .clear), at: now - 30 * 86_400, kills: nil)]
        #expect(BriefCalibrationEngine.lookback(for: ancient, now: now) == 168 * 3600)
    }

    // MARK: - Outcomes

    @Test func outcomeCountsPlayerKillsInsideTheWindowOnly() {
        let v = verdict(threat(tama, .clear), kills: nil)
        let kills = [
            kill(tama, at: now - minute),                          // before the verdict
            kill(tama, at: now + 5 * minute),                      // counts
            kill(tama, at: now + 30 * minute),                     // edge, counts
            kill(tama, at: now + 31 * minute),                     // after the window
            kill(tama, at: now + 10 * minute, npc: true),          // NPC kill
            kill(tama, at: now + 10 * minute, attackers: []),      // no player attackers
            kill(rancer, at: now + 10 * minute),                   // another system
        ]
        let o = BriefCalibrationEngine.outcome(for: v, kills: kills, now: now + 3600)
        #expect(o.playerKills == 2)
        #expect(o.campGateKills == 0)
    }

    @Test func campIsConfirmedOnlyByAKillOnTheSameGate() {
        let v = verdict(threat(tama, .danger, [camp()]), kills: nil)
        let elsewhere = BriefCalibrationEngine.outcome(
            for: v, kills: [kill(tama, at: now + 5 * minute, location: otherGate)], now: now + 3600)
        #expect(elsewhere.playerKills == 1)
        #expect(elsewhere.campGateKills == 0)

        let onGate = BriefCalibrationEngine.outcome(
            for: v, kills: [kill(tama, at: now + 5 * minute, location: gate)], now: now + 3600)
        #expect(onGate.campGateKills == 1)
    }

    // MARK: - Report

    @Test func reportRatesByStatusSignalAndCamp() {
        let log = [
            verdict(threat(tama, .clear), kills: 0),
            verdict(threat(tama, .clear), kills: 0),
            verdict(threat(tama, .clear), kills: 0),
            verdict(threat(tama, .clear), kills: 1),
            verdict(threat(tama, .danger, [camp()]), kills: 2, campKills: 1),
            verdict(threat(tama, .danger, [camp()]), kills: 1, campKills: 0),
            verdict(threat(rancer, .caution, [.recentKills(count: 1, lastKill: now)]), kills: nil),
        ]
        let r = BriefCalibrationEngine.report(log)
        #expect(r.resolved == 6)
        #expect(r.pending == 1)
        #expect(r.byStatus[.clear] == .init(verdicts: 4, followedByKill: 1))
        #expect(r.byStatus[.clear]?.rate == 0.25)
        #expect(r.byStatus[.danger] == .init(verdicts: 2, followedByKill: 2))
        #expect(r.byStatus[.caution] == .init(verdicts: 0, followedByKill: 0))
        #expect(r.byStatus[.caution]?.rate == nil)
        #expect(r.byKind[.quiet] == .init(verdicts: 4, followedByKill: 1))
        #expect(r.camps == .init(verdicts: 2, followedByKill: 1))
        #expect(r.oldest == now)
    }

    @Test func smallSamplesAreNotMeaningful() {
        #expect(!BriefCalibrationReport.Row(verdicts: BriefCalibrationEngine.minSample - 1, followedByKill: 0).isMeaningful)
        #expect(BriefCalibrationReport.Row(verdicts: BriefCalibrationEngine.minSample, followedByKill: 0).isMeaningful)
    }
}
