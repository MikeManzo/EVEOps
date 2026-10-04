//
//  SkillROIEngineTests.swift
//  EVEOpsTests
//
//  Covers Skill ROI: which skill levels are candidates, fits a level makes flyable versus
//  brings closer, queued and Omega-locked skills, prerequisites in the plan, slot skills
//  weighted by how busy the slots are, ranking per day of training, and the EVE skill
//  plan export. Pure inputs only — no network, no ESI.
//

import Foundation
import Testing
@testable import EVEOps

private typealias Skill = IdleCapacityEngine.Skill

private let now = Date(timeIntervalSince1970: 1_800_000_000)

private let rifter = 587
private let thrasher = 16_242
private let autocannon = 2_873

private let frigateSkill = 3_330
private let destroyerSkill = 33_092
private let gunnerySkill = 3_300

private let attributes = ESICharacterAttributes(charisma: 20, intelligence: 20, memory: 20, perception: 20,
                                                willpower: 20, bonusRemaps: nil, accruedRemapCooldownDate: nil,
                                                lastRemapDate: nil)

private func info(_ id: Int, _ name: String, rank: Int = 1, depth: Int = 0) -> SkillTrainingInfo {
    SkillTrainingInfo(skillID: id, name: name, rank: rank, primaryAttribute: 167, secondaryAttribute: 168, depth: depth)
}

private let skillInfo: [Int: SkillTrainingInfo] = [
    frigateSkill: info(frigateSkill, "Minmatar Frigate", rank: 2, depth: 0),
    destroyerSkill: info(destroyerSkill, "Minmatar Destroyer", rank: 2, depth: 1),
    gunnerySkill: info(gunnerySkill, "Gunnery"),
    Skill.massProduction: info(Skill.massProduction, "Mass Production", rank: 2),
    Skill.industry: info(Skill.industry, "Industry"),
]

private func fit(_ id: Int, _ name: String, ship: Int) -> ESIFitting {
    ESIFitting(description: "", fittingId: id,
               items: [ESIFittingItem(flag: "HiSlot0", quantity: 1, typeId: autocannon)], name: name, shipTypeId: ship)
}

private func level(_ n: Int, trained: Int? = nil) -> ReadyRoomSkillLevel {
    ReadyRoomSkillLevel(active: n, trained: trained ?? n, sp: n == 0 ? 0 : SkillTraining.sp(forLevel: n, rank: 2))
}

/// Ready Room reports for a Rifter fit (needs Frigate III + Gunnery II) and a Thrasher fit
/// (needs Destroyer I, which needs Frigate III).
private func reports(skills: [Int: ReadyRoomSkillLevel], queue: [ESISkillQueue] = []) -> [ReadyRoomReport] {
    ReadyRoomEngine.reports(ReadyRoomInput(
        fittings: [fit(1, "Brawler", ship: rifter), fit(2, "Thrash", ship: thrasher)],
        typeNames: [rifter: "Rifter", thrasher: "Thrasher", autocannon: "200mm AutoCannon II"],
        shipClassNames: [rifter: "Frigate", thrasher: "Destroyer"],
        requirements: [rifter: [frigateSkill: 3], thrasher: [destroyerSkill: 1, frigateSkill: 3],
                       autocannon: [gunnerySkill: 2]],
        skillInfo: skillInfo,
        skills: skills,
        skillQueue: queue,
        attributes: attributes,
        holdings: [],
        places: [:],
        currentPlaceID: nil,
        jumps: [:],
        prices: [:],
        now: now
    ))
}

private func roiInput(skills: [Int: ReadyRoomSkillLevel], queue: [ESISkillQueue] = [],
                      capacity: IdleCapacityReport? = nil, pinned: Set<Int> = []) -> SkillROIInput {
    SkillROIInput(reports: reports(skills: skills, queue: queue), pinnedFittingIDs: pinned, skills: skills,
                  skillQueue: queue, attributes: attributes, skillInfo: skillInfo,
                  prerequisites: [destroyerSkill: [frigateSkill: 3]], capacity: capacity, now: now)
}

@Suite struct SkillROIEngineTests {
    // MARK: - Fits

    @Test func aLevelThatClosesEveryGapMakesTheFitFlyable() throws {
        // Has Gunnery II; only Frigate III stands between the pilot and the Rifter.
        let goals = SkillROIEngine.goals(roiInput(skills: [frigateSkill: level(2), gunnerySkill: level(2)]))
        let frigate = try #require(goals.first { $0.skillID == frigateSkill })
        #expect(frigate.level == 3)
        #expect(frigate.completes.map(\.name) == ["Brawler"])
        // The Thrasher still needs Destroyer I.
        #expect(frigate.advances.map(\.name) == ["Thrash"])
    }

    @Test func prerequisitesComeAlongInThePlan() throws {
        let goals = SkillROIEngine.goals(roiInput(skills: [frigateSkill: level(2), gunnerySkill: level(2)]))
        let destroyer = try #require(goals.first { $0.skillID == destroyerSkill })
        #expect(destroyer.plan.map(\.skillID) == [frigateSkill, destroyerSkill])
        // Destroyer I (with Frigate III) makes both fits flyable.
        #expect(Set(destroyer.completes.map(\.name)) == ["Brawler", "Thrash"])
        #expect((destroyer.seconds ?? 0) > (goals.first { $0.skillID == frigateSkill }?.seconds ?? .infinity))
    }

    @Test func queuedLevelsAreNotCandidatesAndCountAsDone() {
        let queue = [ESISkillQueue(finishDate: now.addingTimeInterval(3600), finishedLevel: 3, levelEndSp: nil,
                                   levelStartSp: nil, queuePosition: 0, skillId: frigateSkill, startDate: nil,
                                   trainingStartSp: nil)]
        let goals = SkillROIEngine.goals(roiInput(skills: [frigateSkill: level(2), gunnerySkill: level(1)], queue: queue))
        #expect(!goals.contains { $0.skillID == frigateSkill })
        // With Frigate III queued, Gunnery II alone finishes the Rifter.
        #expect(goals.first { $0.skillID == gunnerySkill }?.completes.map(\.name) == ["Brawler"])
    }

    @Test func omegaLockedFitsAreSkipped() {
        // Trained Frigate III but capped at II on Alpha — training can't fix it.
        let goals = SkillROIEngine.goals(roiInput(skills: [frigateSkill: level(2, trained: 3), gunnerySkill: level(1)]))
        #expect(goals.allSatisfy { $0.completes.isEmpty && $0.advances.isEmpty })
    }

    @Test func pinnedFitsWeighDouble() throws {
        let skills = [frigateSkill: level(2), gunnerySkill: level(2)]
        let plain = try #require(SkillROIEngine.goals(roiInput(skills: skills)).first { $0.skillID == frigateSkill })
        let pinned = try #require(SkillROIEngine.goals(roiInput(skills: skills, pinned: [1])).first { $0.skillID == frigateSkill })
        #expect(pinned.score > plain.score)
    }

    // MARK: - Slots

    private func industryReport(used: Int, limit: Int, idle: TimeInterval?) -> IdleCapacityReport {
        var line = IdleCapacityLine(kind: .manufacturing, status: .busy, used: used, limit: limit)
        line.idleSlotTime = idle
        return IdleCapacityReport(lines: [line])
    }

    @Test func slotSkillsAddCapacityForLinesThePilotHas() throws {
        let skills = [frigateSkill: level(3), gunnerySkill: level(2), Skill.massProduction: level(2)]
        let goals = SkillROIEngine.goals(roiInput(skills: skills, capacity: industryReport(used: 3, limit: 3, idle: 0)))
        let goal = try #require(goals.first { $0.skillID == Skill.massProduction })
        #expect(goal.level == 3)
        #expect(goal.capacity?.added == 1)
        #expect(goal.capacity?.busyShare == 1)
    }

    @Test func idleSlotsMakeMoreSlotsWorthLess() throws {
        let skills = [frigateSkill: level(3), gunnerySkill: level(2), Skill.massProduction: level(2)]
        let busy = try #require(SkillROIEngine.goals(roiInput(skills: skills, capacity: industryReport(used: 3, limit: 3, idle: 0)))
            .first { $0.skillID == Skill.massProduction })
        let idleWeek = 3 * IdleCapacityEngine.idleWindow * 0.8
        let idle = try #require(SkillROIEngine.goals(roiInput(skills: skills, capacity: industryReport(used: 1, limit: 3, idle: idleWeek)))
            .first { $0.skillID == Skill.massProduction })
        #expect(abs((idle.capacity?.busyShare ?? 0) - 0.2) < 0.001)
        #expect(idle.score < busy.score)
    }

    @Test func noLineMeansNoSlotCandidate() {
        let skills = [frigateSkill: level(3), gunnerySkill: level(2)]
        #expect(SkillROIEngine.slotSkills(IdleCapacityReport(lines: []), skills: skills.mapValues(\.active)).isEmpty)
    }

    @Test func slotSkillChainsMoveOnAtLevelFive() {
        let report = IdleCapacityReport(lines: [IdleCapacityLine(kind: .market, status: .idle, used: 1, limit: 10)])
        #expect(SkillROIEngine.slotSkills(report, skills: [Skill.trade: 5, Skill.retail: 2]) == [Skill.retail])
    }

    // MARK: - Ranking and export

    @Test func goalsRankByValuePerTrainingDay() {
        let goals = SkillROIEngine.goals(roiInput(skills: [frigateSkill: level(2), gunnerySkill: level(2)]))
        #expect(zip(goals, goals.dropFirst()).allSatisfy { $0.score >= $1.score })
    }

    @Test func eveSkillPlanListsEveryLevelPrerequisitesFirst() throws {
        let skills = [frigateSkill: level(1), gunnerySkill: level(2)]
        let goals = SkillROIEngine.goals(roiInput(skills: skills))
        let destroyer = try #require(goals.first { $0.skillID == destroyerSkill })
        #expect(SkillROIEngine.eveSkillPlan([destroyer], skills: skills)
                == "Minmatar Frigate II\nMinmatar Frigate III\nMinmatar Destroyer I")
    }

    // MARK: - Plan

    @Test func planCreditsEachFitOnceAndPaysForSharedPrerequisitesOnce() throws {
        let skills = [frigateSkill: level(2), gunnerySkill: level(1)]
        let plan = SkillROIEngine.plan(roiInput(skills: skills), budget: 365 * 86400)
        #expect(plan.fitsCompleted == [1, 2])
        // Every fit is made flyable by exactly one pick.
        let credited = plan.picks.flatMap { $0.completes.map(\.fittingID) }
        #expect(credited.count == Set(credited).count)
        // Frigate III is trained once across the plan, however many picks needed it.
        let frigateLevels = plan.picks.flatMap(\.plan).filter { $0.skillID == frigateSkill }.map(\.requiredLevel)
        #expect(frigateLevels == [3])
        #expect(abs(plan.seconds - plan.picks.compactMap(\.seconds).reduce(0, +)) < 0.001)
    }

    @Test func planStaysWithinTheBudget() throws {
        let input = roiInput(skills: [frigateSkill: level(2), gunnerySkill: level(1)])
        let all = SkillROIEngine.plan(input, budget: 365 * 86400)
        let cheapest = try #require(all.picks.compactMap(\.seconds).min())
        let tight = SkillROIEngine.plan(input, budget: cheapest)
        #expect(tight.seconds <= cheapest)
        #expect(!tight.picks.isEmpty)
        #expect(SkillROIEngine.plan(input, budget: cheapest / 2).picks.isEmpty)
    }

    @Test func planOnlyPicksGoalsTheFilterIncludes() throws {
        // The fits need Frigate III / Destroyer I; Mass Production III adds a busy slot.
        let skills = [frigateSkill: level(2), gunnerySkill: level(2), Skill.massProduction: level(2)]
        var line = IdleCapacityLine(kind: .manufacturing, status: .busy, used: 3, limit: 3)
        line.idleSlotTime = 0
        let input = roiInput(skills: skills, capacity: IdleCapacityReport(lines: [line]))
        let year = 365.0 * 86400

        // Everything: the slot skill, and the fits (Destroyer I, bringing Frigate III along).
        let everything = SkillROIEngine.plan(input, budget: year)
        #expect(everything.picks.contains { $0.skillID == Skill.massProduction })
        #expect(everything.fitsCompleted == [1, 2])

        let slots = SkillROIEngine.plan(input, budget: year, include: SkillROIFilter.slots.includes)
        #expect(!slots.picks.isEmpty)
        #expect(slots.picks.allSatisfy { $0.capacity != nil })

        let fits = SkillROIEngine.plan(input, budget: year, include: SkillROIFilter.fits.includes)
        #expect(fits.fitsCompleted == [1, 2])
        #expect(!fits.picks.contains { $0.skillID == Skill.massProduction })

        #expect(SkillROIEngine.plan(input, budget: year, include: SkillROIFilter.improves.includes).picks.isEmpty)
    }

    @Test func planNamesTheBestGoalThatRanPastTheBudget() throws {
        let input = roiInput(skills: [frigateSkill: level(2), gunnerySkill: level(1)])
        let all = SkillROIEngine.plan(input, budget: 365 * 86400)
        #expect(all.nextOverBudget == nil)

        let cheapest = try #require(all.picks.compactMap(\.seconds).min())
        let tight = SkillROIEngine.plan(input, budget: cheapest)
        let next = try #require(tight.nextOverBudget)
        #expect(tight.seconds + (next.seconds ?? 0) > cheapest)
        #expect(!tight.picks.contains { $0.id == next.id })
    }

    @Test func rationaleSplitsThePlansValueAndLinksSetUpPicks() throws {
        let plan = SkillROIEngine.plan(roiInput(skills: [frigateSkill: level(2), gunnerySkill: level(1)]),
                                       budget: 365 * 86400)
        let rationale = SkillROIRationale(plan)
        #expect(abs(rationale.shares.reduce(0) { $0 + $1.share } - 1) < 0.0001)
        #expect(rationale.shares.map(\.share) == rationale.shares.map(\.share).sorted(by: >))
        #expect(Set(rationale.flyable.map(\.fittingID)) == plan.fitsCompleted)
        #expect(rationale.closer.allSatisfy { !plan.fitsCompleted.contains($0.fittingID) })
        for (index, later) in rationale.setsUp {
            #expect(later > index)
            let advanced = Set(plan.picks[index].advances.map(\.fittingID))
            #expect(plan.picks[later].completes.contains { advanced.contains($0.fittingID) })
        }
        // Every pick that brings a fit closer which a later pick finishes is linked to it.
        for (index, pick) in plan.picks.enumerated() {
            let advanced = Set(pick.advances.map(\.fittingID))
            let finishedLater = plan.picks.dropFirst(index + 1).contains { $0.completes.contains { advanced.contains($0.fittingID) } }
            #expect((rationale.setsUp[index] != nil) == finishedLater)
        }
    }

    @Test func mainSourceIsTheLargestShareOfAPick() {
        var breakdown = SkillROIScore()
        breakdown.completes = 10
        breakdown.performance = 12
        let goal = SkillROIGoal(skillID: 1, level: 1, name: "Test", plan: [], seconds: 60, completes: [], advances: [],
                                improves: [], capacity: nil, breakdown: breakdown)
        #expect(SkillROIRationale.mainSource(goal) == .performance)
    }

    @Test func planRemeasuresAfterAPerformancePick() throws {
        // Both fits flyable; Gunnery III → IV improves fit 1, and once trained, IV → V too.
        var input = roiInput(skills: [frigateSkill: level(3), gunnerySkill: level(3), destroyerSkill: level(1)])
        var gain = FitStatDelta(fittingID: 1); gain.dps = 0.04
        input.performance = [SkillLevelKey(skillID: gunnerySkill, level: 4): [gain]]
        var asked: [(Int, Set<Int>)] = []
        let plan = SkillROIEngine.plan(input, budget: 365 * 86400) { levels, changed in
            asked.append((levels[gunnerySkill] ?? 0, changed))
            let next = (levels[gunnerySkill] ?? 0) + 1
            return next <= 5 ? [SkillLevelKey(skillID: gunnerySkill, level: next): [gain]] : [:]
        }
        #expect(plan.picks.map { "\($0.skillID)-\($0.level)" } == ["\(gunnerySkill)-4", "\(gunnerySkill)-5"])
        #expect(asked.map(\.0) == [4, 5])
        #expect(asked.allSatisfy { $0.1 == [gunnerySkill] })
    }
}
