//
//  SkillPerformanceEngineTests.swift
//  EVEOpsTests
//
//  Covers measuring skill levels against flyable fits: which next levels change a fit and
//  by how much, align time counting when it shortens, rounding-sized changes ignored,
//  queued levels as the baseline, Alpha-capped and maxed skills skipped — and how Skill
//  ROI scores the result. A stand-in stats function replaces the dogma engine.
//

import Foundation
import Testing
@testable import EVEOps

private let gunnery = 3_300
private let navigation = 3_449
private let evasive = 3_453
private let trade = 3_443
private let industry = 3_380

private func fit(_ ship: Int) -> DogmaFit { DogmaFit(shipTypeID: ship, slots: []) }

/// DPS from Gunnery (fit 1 only — fit 2 has no guns), speed from Navigation, align from
/// Evasive Maneuvering, and a 0.01% speed nudge from Trade that should read as noise.
@Sendable private func fakeStats(_ fit: DogmaFit, _ skills: [Int: Int]) -> SimStats {
    var s = SimStats()
    s.dps = fit.shipTypeID == 1 ? 100 * (1 + 0.02 * Double(skills[gunnery] ?? 0)) : 0
    s.maxVelocity = 300 * (1 + 0.05 * Double(skills[navigation] ?? 0)) * (1 + 0.0001 * Double(skills[trade] ?? 0))
    s.mass = 1_000_000
    s.inertiaMod = 1 - 0.05 * Double(skills[evasive] ?? 0)
    s.alignTime = log(4) * s.mass * s.inertiaMod / 1_000_000
    return s
}

private func level(_ n: Int, trained: Int? = nil) -> ReadyRoomSkillLevel {
    ReadyRoomSkillLevel(active: n, trained: trained ?? n, sp: 0)
}

@Suite struct SkillPerformanceEngineTests {
    private let fits = [10: fit(1), 20: fit(2)]

    @Test func measuresTheNextLevelOnEveryFitItChanges() throws {
        let deltas = SkillPerformanceEngine.deltas(fits: fits, skills: [gunnery: 3, navigation: 4],
                                                   candidates: [gunnery, navigation], stats: fakeStats)
        let gun = try #require(deltas[SkillLevelKey(skillID: gunnery, level: 4)])
        #expect(gun.map(\.fittingID) == [10])                       // fit 2 has no guns
        #expect(abs(gun[0].dps - 0.02 / 1.06) < 1e-9)               // 106 → 108 DPS
        let nav = try #require(deltas[SkillLevelKey(skillID: navigation, level: 5)])
        #expect(nav.map(\.fittingID) == [10, 20])
        #expect(nav.allSatisfy { $0.speed > 0 && $0.dps == 0 })
    }

    @Test func shorterAlignCountsAsAGain() throws {
        let deltas = SkillPerformanceEngine.deltas(fits: [10: fit(1)], skills: [evasive: 2],
                                                   candidates: [evasive], stats: fakeStats)
        let align = try #require(deltas[SkillLevelKey(skillID: evasive, level: 3)]?.first)
        #expect(abs(align.align - 0.05 / 0.9) < 1e-9)
        #expect(align.headline?.stat == .align)
    }

    @Test func skillsThatChangeNothingOrOnlyRoundingAreLeftOut() {
        let deltas = SkillPerformanceEngine.deltas(fits: fits, skills: [trade: 1, industry: 1],
                                                   candidates: [trade, industry], stats: fakeStats)
        #expect(deltas.isEmpty)
    }

    @Test func skillsAtFiveHaveNoNextLevel() {
        let deltas = SkillPerformanceEngine.deltas(fits: fits, skills: [gunnery: 5], candidates: [gunnery],
                                                   stats: fakeStats)
        #expect(deltas.isEmpty)
    }

    @Test func queuedLevelsAreTheBaseline() {
        let queue = [ESISkillQueue(finishDate: nil, finishedLevel: 4, levelEndSp: nil, levelStartSp: nil,
                                   queuePosition: 0, skillId: gunnery, startDate: nil, trainingStartSp: nil)]
        let after = SkillPerformanceEngine.levelsAfterQueue([gunnery: level(3), navigation: level(2)], queue: queue)
        #expect(after == [gunnery: 4, navigation: 2])
    }

    @Test func candidatesSkipAlphaCappedAndMaxedSkills() {
        let skills = [gunnery: level(3), navigation: level(2, trained: 4), evasive: level(4)]
        let candidates = SkillPerformanceEngine.candidates(skills, afterQueue: [gunnery: 3, navigation: 2, evasive: 5])
        #expect(candidates == [gunnery])
    }

    @Test func becomingCapStableIsReported() {
        var before = FitPerformance(SimStats()); before.capStable = false
        var after = before; after.capStable = true
        let delta = SkillPerformanceEngine.delta(fittingID: 1, from: before, to: after)
        #expect(delta.becomesCapStable && !delta.isEmpty)
    }

    // MARK: - Skill ROI scoring

    private func roi(_ performance: [SkillLevelKey: [FitStatDelta]], pinned: Set<Int> = []) -> SkillROIInput {
        SkillROIInput(reports: [], pinnedFittingIDs: pinned, skills: [gunnery: level(3)],
                      skillInfo: [gunnery: SkillTrainingInfo(skillID: gunnery, name: "Gunnery", rank: 1,
                                                             primaryAttribute: 167, secondaryAttribute: 168, depth: 0)],
                      performance: performance)
    }

    @Test func aLevelThatOnlyImprovesFitsIsStillAGoal() throws {
        var delta = FitStatDelta(fittingID: 10); delta.dps = 0.03
        let goals = SkillROIEngine.goals(roi([SkillLevelKey(skillID: gunnery, level: 4): [delta]]))
        let goal = try #require(goals.first)
        #expect(goal.level == 4)
        #expect(goal.improves.map(\.fittingID) == [10])
        #expect(abs(goal.breakdown.performance - 3 * SkillROIEngine.Weight.dps) < 1e-9)
        #expect(goal.breakdown.completes == 0 && goal.breakdown.capacity == 0)
    }

    @Test func pinnedFitsDoubleTheirImprovementAndSortFirst() throws {
        var small = FitStatDelta(fittingID: 10); small.dps = 0.02
        var large = FitStatDelta(fittingID: 20); large.dps = 0.03
        let key = SkillLevelKey(skillID: gunnery, level: 4)
        let plain = try #require(SkillROIEngine.goals(roi([key: [small, large]])).first)
        let pinned = try #require(SkillROIEngine.goals(roi([key: [small, large]], pinned: [10])).first)
        #expect(plain.improves.map(\.fittingID) == [20, 10])
        #expect(pinned.improves.map(\.fittingID) == [10, 20])        // 2% × 2 beats 3%
        #expect(pinned.breakdown.performance > plain.breakdown.performance)
    }
}
