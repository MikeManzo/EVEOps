//
//  IdleCapacityEngineTests.swift
//  EVEOpsTests
//
//  Covers the Idle Capacity engine: slot limits from skills, which jobs occupy a slot,
//  finished-but-undelivered jobs, skill queue states, extractors, which lines a pilot
//  gets, the clone jump timer and slots, SP and remaps, expiring listings, idle time
//  from job history, and timeline events. Pure inputs only — no network, no ESI.
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

/// A job with a start date, for idle-time tests: ran from `startedAgo` to `endsIn`.
private func timedJob(_ status: String, startedAgo: TimeInterval, endsIn: TimeInterval,
                      completedAgo: TimeInterval? = nil) -> IdleCapacityJob {
    IdleCapacityJob(activityID: 1, status: status, endDate: now.addingTimeInterval(endsIn),
                    startDate: now.addingTimeInterval(-startedAgo),
                    completedDate: completedAgo.map { now.addingTimeInterval(-$0) })
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

    @Test func freeJumpCloneSlotsAreIdle() {
        let skills = [Skill.infomorphPsychology: 5, Skill.advancedInfomorphPsychology: 2]
        #expect(IdleCapacityEngine.jumpCloneLimit(skills) == 7)
        let line = report(IdleCapacityInput(skills: skills, jumpCloneCount: 4)).line(.cloneJump)
        #expect(line?.status == .idle)
        #expect(line?.free == 3)
        let full = report(IdleCapacityInput(skills: [Skill.infomorphPsychology: 2], jumpCloneCount: 2)).line(.cloneJump)
        #expect(full?.status == .info)
    }

    // MARK: - Skill points & remaps

    @Test func unallocatedSkillPointsAreIdle() {
        #expect(report(IdleCapacityInput()).line(.skillPoints) == nil)
        let line = report(IdleCapacityInput(unallocatedSP: 250_000)).line(.skillPoints)
        #expect(line?.status == .idle)
        #expect(line?.count == 250_000)
    }

    @Test func remapLineFollowsCooldownAndBonusRemaps() {
        #expect(report(IdleCapacityInput()).line(.remap) == nil) // attributes not read
        #expect(report(IdleCapacityInput(nextRemap: now.addingTimeInterval(48 * hour))).line(.remap) == nil)
        #expect(report(IdleCapacityInput(nextRemap: now.addingTimeInterval(-hour))).line(.remap)?.status == .info)
        #expect(report(IdleCapacityInput(bonusRemaps: 2, nextRemap: now.addingTimeInterval(48 * hour))).line(.remap)?.count == 2)
    }

    @Test func nextRemapIsAYearAfterTheLastUnlessESISaysOtherwise() {
        let last = now.addingTimeInterval(-30 * 24 * hour)
        let cooldown = now.addingTimeInterval(5 * hour)
        #expect(IdleCapacityEngine.nextRemap(accruedCooldown: cooldown, lastRemap: last) == cooldown)
        #expect(IdleCapacityEngine.nextRemap(accruedCooldown: nil, lastRemap: last)
                == Calendar.current.date(byAdding: .year, value: 1, to: last))
        #expect(IdleCapacityEngine.nextRemap(accruedCooldown: nil, lastRemap: nil) == .distantPast)
    }

    // MARK: - Listings

    @Test func fullMarketWithAnOrderExpiringIsSoon() {
        let expiries = [now.addingTimeInterval(3 * hour), now.addingTimeInterval(72 * hour)]
        let line = report(IdleCapacityInput(orderCount: 5, orderExpiries: expiries)).line(.market)
        #expect(line?.status == .soon)
        #expect(line?.expiring == 1)
        #expect(line?.date == now.addingTimeInterval(3 * hour))
    }

    @Test func contractSlotsFollowContracting() {
        #expect(IdleCapacityEngine.contractSlots([Skill.contracting: 4]) == 17)
        let line = report(IdleCapacityInput(skills: [Skill.contracting: 1], contractCount: 2,
                                            contractExpiries: [now.addingTimeInterval(hour)])).line(.contracts)
        #expect(line?.status == .idle)
        #expect(line?.free == 3)
        #expect(line?.expiring == 1)
        #expect(report(IdleCapacityInput()).line(.contracts) == nil)
    }

    // MARK: - Idle time

    @Test func freeSlotIdlesSinceTheLastDelivery() {
        // Two slots: one job still running, one delivered five hours ago.
        let jobs = [
            timedJob("active", startedAgo: 10 * hour, endsIn: 20 * hour),
            timedJob("delivered", startedAgo: 30 * hour, endsIn: -8 * hour, completedAgo: 5 * hour),
        ]
        let line = report(IdleCapacityInput(skills: [Skill.industry: 1, Skill.massProduction: 1],
                                            jobs: jobs, jobHistoryLoaded: true)).line(.manufacturing)
        #expect(line?.status == .idle)
        #expect(line?.idleSince == now.addingTimeInterval(-5 * hour))
    }

    @Test func idleSinceNeedsHistoryForFreeSlots() {
        let line = report(IdleCapacityInput(skills: [Skill.industry: 1], jobs: [])).line(.manufacturing)
        #expect(line?.idleSince == nil)
        let unused = report(IdleCapacityInput(skills: [Skill.industry: 1], jobs: [], jobHistoryLoaded: true)).line(.manufacturing)
        #expect(unused?.idleSince == .distantPast)
    }

    @Test func finishedJobIdlesSinceItEnded() {
        let line = report(IdleCapacityInput(skills: [Skill.industry: 1], jobs: [job(1, "ready", endsIn: -3 * hour)]))
            .line(.manufacturing)
        #expect(line?.idleSince == now.addingTimeInterval(-3 * hour))
    }

    @Test func idleSlotTimeIntegratesUnusedSlots() {
        let from = now.addingTimeInterval(-10 * hour)
        // One slot, a job running the last 4 hours: 6 hours idle.
        let one = [timedJob("active", startedAgo: 4 * hour, endsIn: 10 * hour)]
        #expect(IdleCapacityEngine.idleSlotTime(one, limit: 1, from: from, to: now) == 6 * hour)
        // Two slots: one busy throughout, the other used 2 of 10 hours before a cancel — 8 idle.
        let two = [
            timedJob("active", startedAgo: 20 * hour, endsIn: 10 * hour),
            timedJob("cancelled", startedAgo: 10 * hour, endsIn: 10 * hour, completedAgo: 8 * hour),
        ]
        #expect(IdleCapacityEngine.idleSlotTime(two, limit: 2, from: from, to: now) == 8 * hour)
        #expect(IdleCapacityEngine.idleSlotTime([], limit: 3, from: from, to: now) == 30 * hour)
    }

    @Test func historyOnlyJobsDontAddLines() {
        let old = timedJob("delivered", startedAgo: 50 * hour, endsIn: -40 * hour, completedAgo: 40 * hour)
        #expect(report(IdleCapacityInput(jobs: [old], jobHistoryLoaded: true)).line(.manufacturing) == nil)
    }

    // MARK: - Timeline

    @Test func eventsCoverTheNextDayInOrder() {
        let input = IdleCapacityInput(
            queueFinishDates: [now.addingTimeInterval(5 * hour)],
            jobs: [job(1, endsIn: 2 * hour), job(5, endsIn: 30 * hour), job(9, "ready", endsIn: -hour)],
            orderExpiries: [now.addingTimeInterval(12 * hour)],
            colonyCount: 1,
            extractorExpiries: [now.addingTimeInterval(-hour), now.addingTimeInterval(8 * hour)],
            lastCloneJump: now.addingTimeInterval(-20 * hour),
            jumpCloneCount: 1
        )
        let events = IdleCapacityEngine.events(input, now: now)
        #expect(events.map(\.kind) == [.manufacturing, .cloneJump, .training, .extractors, .market])
        #expect(events.first?.date == now.addingTimeInterval(2 * hour))
    }
}
