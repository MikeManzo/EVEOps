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
}
