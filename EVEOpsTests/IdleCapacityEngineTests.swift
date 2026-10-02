//
//  IdleCapacityEngineTests.swift
//  EVEOpsTests
//
//  Covers the Idle Capacity engine: slot limits from skills, which jobs occupy a slot,
//  finished-but-undelivered jobs, skill queue states, extractors, which lines a pilot
//  gets, and the clone jump timer. Pure inputs only — no network, no ESI.
//

import Foundation
import Testing
@testable import EVEOps

private typealias Skill = IdleCapacityEngine.Skill

private let now = Date(timeIntervalSince1970: 1_800_000_000)
private let hour: TimeInterval = 3600

private func job(_ activity: Int, _ status: String = "active", endsIn: TimeInterval = 48 * hour) -> IdleCapacityJob {
    IdleCapacityJob(activityID: activity, status: status, endDate: now.addingTimeInterval(endsIn))
}

private func report(_ input: IdleCapacityInput) -> IdleCapacityReport {
    IdleCapacityEngine.report(input, now: now)
}

@Suite struct IdleCapacityEngineTests {
    // MARK: - Limits

    @Test func slotLimitsFollowSkills() {
        let skills = [
            Skill.massProduction: 5, Skill.advancedMassProduction: 4,
            Skill.laboratoryOperation: 5, Skill.advancedLaboratoryOperation: 3,
            Skill.trade: 5, Skill.retail: 5, Skill.wholesale: 5, Skill.tycoon: 5,
            Skill.interplanetaryConsolidation: 4,
        ]
        #expect(IdleCapacityEngine.manufacturingSlots(skills) == 10)
        #expect(IdleCapacityEngine.scienceSlots(skills) == 9)
        #expect(IdleCapacityEngine.orderSlots(skills) == 305)
        #expect(IdleCapacityEngine.orderSlots([:]) == 5)
        #expect(IdleCapacityEngine.planetLimit(skills) == 5)
    }

    @Test func noReactionSlotsWithoutReactions() {
        #expect(IdleCapacityEngine.reactionSlots([Skill.massReactions: 5]) == 0)
        #expect(IdleCapacityEngine.reactionSlots([Skill.reactions: 1, Skill.massReactions: 2]) == 3)
    }

    // MARK: - Industry

    @Test func freeManufacturingSlotIsIdle() {
        let line = report(IdleCapacityInput(skills: [Skill.industry: 5, Skill.massProduction: 2], jobs: [job(1), job(1)]))
            .line(.manufacturing)
        #expect(line?.status == .idle)
        #expect(line?.used == 2)
        #expect(line?.limit == 3)
        #expect(line?.free == 1)
    }

    @Test func fullSlotsFreeingWithinADayAreSoon() {
        let jobs = [job(1, endsIn: 2 * hour), job(1)]
        let line = report(IdleCapacityInput(skills: [Skill.industry: 1, Skill.massProduction: 1], jobs: jobs))
            .line(.manufacturing)
        #expect(line?.status == .soon)
        #expect(line?.date == now.addingTimeInterval(2 * hour))
    }

    @Test func fullSlotsAreBusy() {
        let line = report(IdleCapacityInput(skills: [Skill.industry: 1], jobs: [job(1)])).line(.manufacturing)
        #expect(line?.status == .busy)
        #expect(line?.free == 0)
    }

    @Test func finishedJobsStillOccupyButMakeTheLineIdle() {
        // A "ready" job and an active one past its end date both wait for delivery.
        let jobs = [job(1, "ready", endsIn: -hour), job(1, endsIn: -hour)]
        let line = report(IdleCapacityInput(skills: [Skill.industry: 1, Skill.massProduction: 1], jobs: jobs))
            .line(.manufacturing)
        #expect(line?.status == .idle)
        #expect(line?.used == 2)
        #expect(line?.count == 2)
        #expect(line?.free == 2)
    }

    @Test func deliveredAndCancelledJobsDontOccupy() {
        let jobs = [job(1, "delivered"), job(1, "cancelled"), job(1, "paused")]
        let line = report(IdleCapacityInput(skills: [Skill.industry: 1, Skill.massProduction: 1], jobs: jobs))
            .line(.manufacturing)
        #expect(line?.used == 1)
    }

    @Test func scienceCountsEveryResearchActivity() {
        let jobs = [3, 4, 5, 7, 8].map { job($0) } + [job(1)]
        let line = report(IdleCapacityInput(skills: [Skill.laboratoryOperation: 4], jobs: jobs)).line(.science)
        #expect(line?.used == 5)
        #expect(line?.status == .busy)
    }

    // MARK: - Which lines appear

    @Test func uninvestedActivitiesAreLeftOut() {
        let r = report(IdleCapacityInput())
        #expect(r.lines.map(\.kind) == [.training])
    }

    @Test func runningJobsShowTheLineEvenWithoutSkills() {
        let r = report(IdleCapacityInput(jobs: [job(5)]))
        #expect(r.line(.science)?.limit == 1)
    }

    // MARK: - Training

    @Test func emptyQueueIsIdle() {
        let line = report(IdleCapacityInput()).line(.training)
        #expect(line?.status == .idle)
        #expect(line?.count == 0)
    }

    @Test func pausedQueueIsIdle() {
        let line = report(IdleCapacityInput(queueFinishDates: [nil, nil])).line(.training)
        #expect(line?.status == .idle)
        #expect(line?.count == 2)
    }

    @Test func queueEndingWithinADayIsSoon() {
        let line = report(IdleCapacityInput(queueFinishDates: [now.addingTimeInterval(hour), now.addingTimeInterval(5 * hour)]))
            .line(.training)
        #expect(line?.status == .soon)
        #expect(line?.date == now.addingTimeInterval(5 * hour))
    }

    @Test func longQueueIsBusy() {
        let line = report(IdleCapacityInput(queueFinishDates: [now.addingTimeInterval(-hour), now.addingTimeInterval(72 * hour)]))
            .line(.training)
        #expect(line?.status == .busy)
        #expect(line?.count == 1)
    }

    // MARK: - Market & planets

    @Test func marketLineCountsOrdersAgainstLimit() {
        let line = report(IdleCapacityInput(skills: [Skill.trade: 2], orderCount: 13)).line(.market)
        #expect(line?.status == .busy)
        #expect(line?.limit == 13)
        let idle = report(IdleCapacityInput(skills: [Skill.trade: 2], orderCount: 3)).line(.market)
        #expect(idle?.free == 10)
    }

    @Test func unusedPlanetsAreIdle() {
        let line = report(IdleCapacityInput(skills: [Skill.interplanetaryConsolidation: 3], colonyCount: 2)).line(.planets)
        #expect(line?.status == .idle)
        #expect(line?.free == 2)
    }

    @Test func stoppedExtractorsAreIdle() {
        let expiries = [now.addingTimeInterval(-hour), now.addingTimeInterval(-2 * hour), now.addingTimeInterval(10 * hour)]
        let line = report(IdleCapacityInput(colonyCount: 3, extractorExpiries: expiries)).line(.extractors)
        #expect(line?.status == .idle)
        #expect(line?.count == 2)
        #expect(line?.date == now.addingTimeInterval(10 * hour))
    }

    @Test func extractorStoppingWithinADayIsSoon() {
        let line = report(IdleCapacityInput(colonyCount: 1, extractorExpiries: [now.addingTimeInterval(3 * hour)])).line(.extractors)
        #expect(line?.status == .soon)
    }

    @Test func noExtractorLineUntilLayoutsLoad() {
        #expect(report(IdleCapacityInput(colonyCount: 2)).line(.extractors) == nil)
        #expect(report(IdleCapacityInput(colonyCount: 2, extractorExpiries: [])).line(.extractors) == nil)
    }

    // MARK: - Clones & research

    @Test func cloneJumpTimerShortensWithInfomorphSynchronizing() {
        let jumped = now.addingTimeInterval(-10 * hour)
        #expect(IdleCapacityEngine.cloneJumpReadyAt(lastJump: jumped, infomorphSynchronizing: 0, now: now)
                == now.addingTimeInterval(14 * hour))
        #expect(IdleCapacityEngine.cloneJumpReadyAt(lastJump: jumped, infomorphSynchronizing: 5, now: now)
                == now.addingTimeInterval(9 * hour))
        #expect(IdleCapacityEngine.cloneJumpReadyAt(lastJump: now.addingTimeInterval(-30 * hour), infomorphSynchronizing: 0, now: now) == nil)
        #expect(IdleCapacityEngine.cloneJumpReadyAt(lastJump: nil, infomorphSynchronizing: 0, now: now) == nil)
    }

    @Test func cloneAndResearchLinesAreInformational() {
        let agents = [IdleCapacityAgent(pointsPerDay: 50, remainderPoints: 10, startedAt: now.addingTimeInterval(-48 * hour))]
        let r = report(IdleCapacityInput(jumpCloneCount: 2, researchAgents: agents))
        #expect(r.line(.cloneJump)?.status == .info)
        #expect(r.line(.research)?.points == 110)
        #expect(r.idleCount == 1) // only the empty skill queue
    }
}
