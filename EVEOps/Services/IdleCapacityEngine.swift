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

// MARK:  Models

/// One kind of capacity a pilot can leave unused.
nonisolated enum IdleCapacityKind: String, CaseIterable, Sendable, Hashable {
    case training, skillPoints, remap, manufacturing, science, reactions, market, contracts, planets, extractors, cloneJump, research
}

/// How a capacity line stands right now.
nonisolated enum IdleCapacityStatus: Int, Comparable, Sendable {
    /// Capacity is sitting unused (or work is finished and waiting to be collected).
    case idle
    /// Fully used, but it frees up within `IdleCapacityEngine.soonWindow`.
    case soon
    /// Fully used for a while yet.
    case busy
    /// Informational — nothing to act on (clone jump timers, remaps, research points).
    case info

    static func < (a: Self, b: Self) -> Bool { a.rawValue < b.rawValue }
}

/// An industry job, reduced to what slot usage needs.
nonisolated struct IdleCapacityJob: Sendable {
    let activityID: Int
    /// ESI status: active, paused, ready (finished, not delivered), …
    let status: String
    let endDate: Date
    /// Only needed for idle time; nil from callers that just count slots.
    var startDate: Date? = nil
    /// When a delivered or cancelled job left its slot.
    var completedDate: Date? = nil
}

/// A research agent, reduced to its points.
nonisolated struct IdleCapacityAgent: Sendable {
    let pointsPerDay: Double
    let remainderPoints: Double
    let startedAt: Date
}

/// Everything the engine reads for one pilot. Plain values so it runs off the main actor
/// and in tests.
nonisolated struct IdleCapacityInput: Sendable {
    /// Skill ID → active level (capped on an Alpha clone).
    var skills: [Int: Int] = [:]
    var unallocatedSP = 0
    var bonusRemaps = 0
    /// When the yearly remap is (or was) next available; nil when attributes weren't read.
    var nextRemap: Date?
    /// Finish date of each skill queue entry; nil for a paused queue.
    var queueFinishDates: [Date?] = []
    var jobs: [IdleCapacityJob] = []
    /// True when `jobs` also holds the last 90 days of delivered and cancelled jobs, so
    /// how long slots have sat idle is known.
    var jobHistoryLoaded = false
    var orderCount = 0
    /// When each open market order expires.
    var orderExpiries: [Date] = []
    /// Outstanding contracts the pilot issued (not on behalf of the corporation).
    var contractCount = 0
    var contractExpiries: [Date] = []
    var colonyCount = 0
    /// Earliest extractor expiry per colony; nil while the colony layouts aren't loaded.
    var extractorExpiries: [Date]?
    var lastCloneJump: Date?
    var jumpCloneCount = 0
    /// Nil when research agents couldn't be read (scope missing, not loaded yet).
    var researchAgents: [IdleCapacityAgent]?
}

/// One line on a pilot's card.
nonisolated struct IdleCapacityLine: Identifiable, Sendable {
    let kind: IdleCapacityKind
    let status: IdleCapacityStatus
    /// Slots (or planets, orders) in use and the pilot's limit, for slot-style lines.
    var used: Int?
    var limit: Int?
    /// Finished jobs waiting to be delivered, expired extractors, research agents.
    var count = 0
    /// When something changes: the queue ends, a slot frees, an extractor stops, the
    /// clone jump is ready.
    var date: Date?
    /// Research points accrued across agents.
    var points: Double?
    /// Market orders or contracts expiring within a day.
    var expiring = 0
    /// Since when the capacity has sat unused; `.distantPast` when that's longer than the
    /// job history reaches (90 days).
    var idleSince: Date?
    /// Slot time left unused over the last `IdleCapacityEngine.idleWindow` (industry lines,
    /// with job history loaded).
    var idleSlotTime: TimeInterval?

    var id: IdleCapacityKind { kind }

    /// Slots free right now, counting finished-but-undelivered jobs as free.
    var free: Int {
        guard let used, let limit else { return 0 }
        return max(limit - used, 0) + count
    }
}

/// A pilot's capacity, line by line.
nonisolated struct IdleCapacityReport: Sendable {
    let lines: [IdleCapacityLine]

    func line(_ kind: IdleCapacityKind) -> IdleCapacityLine? { lines.first { $0.kind == kind } }

    /// Lines with capacity unused right now.
    var idleCount: Int { lines.filter { $0.status == .idle }.count }
    /// Lines that run out within the next day.
    var soonCount: Int { lines.filter { $0.status == .soon }.count }
    /// Industry slot time left unused over the last week; nil without job history.
    var idleSlotTime: TimeInterval? {
        let times = lines.compactMap(\.idleSlotTime)
        return times.isEmpty ? nil : times.reduce(0, +)
    }
}

/// Something that frees up, runs out or comes ready — a mark on the timeline.
nonisolated struct IdleCapacityEvent: Sendable {
    let kind: IdleCapacityKind
    let date: Date
}

// MARK:  Engine

nonisolated enum IdleCapacityEngine {
    /// "Soon" means within a day — the same window the Colonies screen uses.
    static let soonWindow: TimeInterval = 24 * 3600
    /// How far back idle slot time is totted up.
    static let idleWindow: TimeInterval = 7 * 24 * 3600

    enum Skill {
        static let industry = 3380
        static let massProduction = 3387
        static let advancedMassProduction = 24625
        static let laboratoryOperation = 3406
        static let advancedLaboratoryOperation = 24624
        static let reactions = 45746
        static let massReactions = 45748
        static let advancedMassReactions = 45749
        static let trade = 3443
        static let retail = 3444
        static let wholesale = 16596
        static let tycoon = 18580
        static let interplanetaryConsolidation = 2495
        static let infomorphSynchronizing = 33399
        static let infomorphPsychology = 24242
        static let advancedInfomorphPsychology = 33407
        static let contracting = 25235
    }

    enum Activity {
        static let manufacturing: Set<Int> = [1]
        /// TE and ME research, copying, reverse engineering, invention.
        static let science: Set<Int> = [3, 4, 5, 7, 8]
        static let reactions: Set<Int> = [9, 11]

        static func kind(_ activityID: Int) -> IdleCapacityKind? {
            if manufacturing.contains(activityID) { return .manufacturing }
            if science.contains(activityID) { return .science }
            if reactions.contains(activityID) { return .reactions }
            return nil
        }
    }

    // MARK: Limits

    static func manufacturingSlots(_ skills: [Int: Int]) -> Int {
        1 + skills[Skill.massProduction, default: 0] + skills[Skill.advancedMassProduction, default: 0]
    }

    static func scienceSlots(_ skills: [Int: Int]) -> Int {
        1 + skills[Skill.laboratoryOperation, default: 0] + skills[Skill.advancedLaboratoryOperation, default: 0]
    }

    /// No reaction slots at all until Reactions is trained.
    static func reactionSlots(_ skills: [Int: Int]) -> Int {
        guard skills[Skill.reactions, default: 0] > 0 else { return 0 }
        return 1 + skills[Skill.massReactions, default: 0] + skills[Skill.advancedMassReactions, default: 0]
    }

    static func orderSlots(_ skills: [Int: Int]) -> Int {
        5 + 4 * skills[Skill.trade, default: 0] + 8 * skills[Skill.retail, default: 0]
            + 16 * skills[Skill.wholesale, default: 0] + 32 * skills[Skill.tycoon, default: 0]
    }

    static func planetLimit(_ skills: [Int: Int]) -> Int {
        1 + skills[Skill.interplanetaryConsolidation, default: 0]
    }

    static func contractSlots(_ skills: [Int: Int]) -> Int {
        1 + 4 * skills[Skill.contracting, default: 0]
    }

    static func jumpCloneLimit(_ skills: [Int: Int]) -> Int {
        skills[Skill.infomorphPsychology, default: 0] + skills[Skill.advancedInfomorphPsychology, default: 0]
    }

    /// When the yearly remap is next available: ESI's accrued cooldown when it gives one,
    /// otherwise a year after the last remap; `.distantPast` for a pilot who never remapped.
    static func nextRemap(accruedCooldown: Date?, lastRemap: Date?) -> Date {
        if let accruedCooldown { return accruedCooldown }
        guard let lastRemap else { return .distantPast }
        return Calendar.current.date(byAdding: .year, value: 1, to: lastRemap) ?? .distantFuture
    }

    static func isRemapAvailable(bonusRemaps: Int, nextRemap: Date, now: Date = .now) -> Bool {
        bonusRemaps > 0 || nextRemap <= now
    }

    /// 24 hours between clone jumps, an hour less per level of Infomorph Synchronizing.
    /// Nil when a jump is allowed now.
    static func cloneJumpReadyAt(lastJump: Date?, infomorphSynchronizing: Int, now: Date = .now) -> Date? {
        guard let lastJump else { return nil }
        let ready = lastJump.addingTimeInterval(Double(24 - infomorphSynchronizing) * 3600)
        return ready > now ? ready : nil
    }

    /// The pilot's active Infomorph Synchronizing level, 0 when untrained or unknown.
    static func infomorphSynchronizing(in skills: ESISkillsResponse?) -> Int {
        skills?.skills.first { $0.skillId == Skill.infomorphSynchronizing }?.activeSkillLevel ?? 0
    }

    // MARK: Report

    /// A pilot's capacity. Slot lines only appear for activities the pilot has invested
    /// in (trained the slot skill or is using it), so a pure combat pilot isn't told
    /// their one factory slot is idle.
    static func report(_ input: IdleCapacityInput, now: Date = .now) -> IdleCapacityReport {
        let skills = input.skills
        var lines: [IdleCapacityLine] = [training(input.queueFinishDates, now: now)]

        if input.unallocatedSP > 0 {
            lines.append(IdleCapacityLine(kind: .skillPoints, status: .idle, count: input.unallocatedSP))
        }
        if let nextRemap = input.nextRemap, isRemapAvailable(bonusRemaps: input.bonusRemaps, nextRemap: nextRemap, now: now) {
            lines.append(IdleCapacityLine(kind: .remap, status: .info, count: input.bonusRemaps))
        }

        // Delivered and cancelled jobs only matter for idle time, so they don't make a
        // line appear on their own.
        let history = input.jobHistoryLoaded
        let manufacturing = input.jobs.filter { Activity.manufacturing.contains($0.activityID) }
        if skills[Skill.industry, default: 0] > 0 || skills[Skill.massProduction, default: 0] > 0 || manufacturing.contains(where: occupiesSlot) {
            lines.append(slots(.manufacturing, jobs: manufacturing, limit: manufacturingSlots(skills), history: history, now: now))
        }
        let science = input.jobs.filter { Activity.science.contains($0.activityID) }
        if skills[Skill.laboratoryOperation, default: 0] > 0 || science.contains(where: occupiesSlot) {
            lines.append(slots(.science, jobs: science, limit: scienceSlots(skills), history: history, now: now))
        }
        let reactions = input.jobs.filter { Activity.reactions.contains($0.activityID) }
        if reactionSlots(skills) > 0 || reactions.contains(where: occupiesSlot) {
            lines.append(slots(.reactions, jobs: reactions, limit: reactionSlots(skills), history: history, now: now))
        }

        if skills[Skill.trade, default: 0] > 0 || input.orderCount > 0 {
            lines.append(listings(.market, used: input.orderCount, limit: orderSlots(skills),
                                  expiries: input.orderExpiries, now: now))
        }
        if skills[Skill.contracting, default: 0] > 0 || input.contractCount > 0 {
            lines.append(listings(.contracts, used: input.contractCount, limit: contractSlots(skills),
                                  expiries: input.contractExpiries, now: now))
        }

        if skills[Skill.interplanetaryConsolidation, default: 0] > 0 || input.colonyCount > 0 {
            let limit = planetLimit(skills)
            lines.append(IdleCapacityLine(kind: .planets, status: input.colonyCount < limit ? .idle : .busy,
                                          used: input.colonyCount, limit: limit))
        }
        if input.colonyCount > 0, let expiries = input.extractorExpiries, !expiries.isEmpty {
            lines.append(extractors(expiries, now: now))
        }

        // Free jump clone slots are idle; otherwise the line just carries the jump timer.
        let cloneLimit = jumpCloneLimit(skills)
        if input.jumpCloneCount > 0 || cloneLimit > 0 {
            let readyAt = cloneJumpReadyAt(lastJump: input.lastCloneJump,
                                           infomorphSynchronizing: skills[Skill.infomorphSynchronizing, default: 0],
                                           now: now)
            lines.append(IdleCapacityLine(kind: .cloneJump, status: input.jumpCloneCount < cloneLimit ? .idle : .info,
                                          used: input.jumpCloneCount, limit: cloneLimit, date: readyAt))
        }

        if let agents = input.researchAgents, !agents.isEmpty {
            let points = agents.reduce(0) { sum, agent in
                sum + agent.remainderPoints + agent.pointsPerDay * now.timeIntervalSince(agent.startedAt) / 86400
            }
            lines.append(IdleCapacityLine(kind: .research, status: .info, count: agents.count, points: points))
        }

        return IdleCapacityReport(lines: lines)
    }

    // MARK: Timeline

    /// Everything that frees up, runs out or comes ready within `window`, soonest first.
    static func events(_ input: IdleCapacityInput, now: Date = .now, window: TimeInterval = soonWindow) -> [IdleCapacityEvent] {
        let end = now.addingTimeInterval(window)
        var out: [IdleCapacityEvent] = []
        func add(_ kind: IdleCapacityKind?, _ date: Date?) {
            guard let kind, let date, date > now, date <= end else { return }
            out.append(IdleCapacityEvent(kind: kind, date: date))
        }
        add(.training, input.queueFinishDates.compactMap { $0 }.max())
        for job in input.jobs where job.status == "active" {
            add(Activity.kind(job.activityID), job.endDate)
        }
        for expiry in input.extractorExpiries ?? [] { add(.extractors, expiry) }
        if input.jumpCloneCount > 0 {
            add(.cloneJump, cloneJumpReadyAt(lastJump: input.lastCloneJump,
                                             infomorphSynchronizing: input.skills[Skill.infomorphSynchronizing, default: 0],
                                             now: now))
        }
        for expiry in input.orderExpiries { add(.market, expiry) }
        for expiry in input.contractExpiries { add(.contracts, expiry) }
        return out.sorted { $0.date < $1.date }
    }

    // MARK: Idle time

    /// Slot time unused between `from` and `to`: the limit minus the jobs running at each
    /// moment. Assumes today's limit applied throughout. A job runs from its start to its
    /// end date — or to when it was cancelled.
    static func idleSlotTime(_ jobs: [IdleCapacityJob], limit: Int, from: Date, to: Date) -> TimeInterval {
        var changes: [(date: Date, delta: Int)] = []
        for job in jobs {
            guard let start = job.startDate else { continue }
            let end = job.status == "cancelled" ? (job.completedDate ?? job.endDate) : job.endDate
            let clippedStart = max(start, from)
            let clippedEnd = min(end, to)
            guard clippedStart < clippedEnd else { continue }
            changes.append((clippedStart, 1))
            changes.append((clippedEnd, -1))
        }
        changes.sort { $0.date < $1.date }
        var idle: TimeInterval = 0
        var running = 0
        var cursor = from
        for change in changes {
            idle += Double(max(limit - running, 0)) * change.date.timeIntervalSince(cursor)
            running += change.delta
            cursor = change.date
        }
        return idle + Double(max(limit - running, 0)) * to.timeIntervalSince(cursor)
    }

    /// The last time a slot was taken or given back: a job started, or one was delivered
    /// or cancelled. Slot usage hasn't changed since, so any free slot has been free at
    /// least this long. Nil when nothing happened within the job history.
    static func lastSlotChange(_ jobs: [IdleCapacityJob], now: Date) -> Date? {
        let starts = jobs.compactMap(\.startDate)
        let releases = jobs.filter { ["delivered", "cancelled", "reverted"].contains($0.status) }
            .map { $0.completedDate ?? $0.endDate }
        return (starts + releases).filter { $0 <= now }.max()
    }

    // MARK: Lines

    /// Idle when nothing is queued (or the queue is paused); soon when it ends within a day.
    private static func training(_ finishDates: [Date?], now: Date) -> IdleCapacityLine {
        let upcoming = finishDates.compactMap { $0 }.filter { $0 > now }
        guard let end = upcoming.max() else {
            // Entries with no finish date mean a paused queue — still not training.
            let paused = finishDates.contains { $0 == nil }
            return IdleCapacityLine(kind: .training, status: .idle, count: paused ? finishDates.count : 0)
        }
        let status: IdleCapacityStatus = end.timeIntervalSince(now) < soonWindow ? .soon : .busy
        return IdleCapacityLine(kind: .training, status: status, count: upcoming.count, date: end)
    }

    private static func occupiesSlot(_ job: IdleCapacityJob) -> Bool {
        ["active", "paused", "ready"].contains(job.status)
    }

    /// Jobs occupy a slot until delivered, so finished ones still count as used — but they
    /// are reported (`count`) and make the line idle, since the slot is doing nothing.
    /// With job history, the line also says how long it's been idle and how much slot
    /// time went unused this past week.
    private static func slots(_ kind: IdleCapacityKind, jobs: [IdleCapacityJob], limit: Int,
                              history: Bool, now: Date) -> IdleCapacityLine {
        let occupying = jobs.filter(occupiesSlot)
        let finished = occupying.filter { $0.status == "ready" || ($0.status == "active" && $0.endDate <= now) }
        let running = occupying.filter { $0.status == "active" && $0.endDate > now }
        let nextFree = running.map(\.endDate).min()
        let status: IdleCapacityStatus
        if occupying.count < limit || !finished.isEmpty {
            status = .idle
        } else if let nextFree, nextFree.timeIntervalSince(now) < soonWindow {
            status = .soon
        } else {
            status = .busy
        }
        var line = IdleCapacityLine(kind: kind, status: status, used: occupying.count, limit: limit,
                                    count: finished.count, date: nextFree)
        if status == .idle {
            // A finished job has idled since it ended; a free slot since usage last changed.
            var since = finished.map(\.endDate)
            if history, occupying.count < limit { since.append(lastSlotChange(jobs, now: now) ?? .distantPast) }
            line.idleSince = since.min()
        }
        if history {
            line.idleSlotTime = idleSlotTime(jobs, limit: limit, from: now.addingTimeInterval(-idleWindow), to: now)
        }
        return line
    }

    /// Market orders and contracts: idle with slots free; when full, soon if one expires
    /// within a day.
    private static func listings(_ kind: IdleCapacityKind, used: Int, limit: Int, expiries: [Date], now: Date) -> IdleCapacityLine {
        let upcoming = expiries.filter { $0 > now }
        let expiring = upcoming.filter { $0.timeIntervalSince(now) < soonWindow }.count
        let status: IdleCapacityStatus = used < limit ? .idle : expiring > 0 ? .soon : .busy
        return IdleCapacityLine(kind: kind, status: status, used: used, limit: limit,
                                date: upcoming.min(), expiring: expiring)
    }

    /// Idle when any extractor has stopped; soon when one stops within a day.
    private static func extractors(_ expiries: [Date], now: Date) -> IdleCapacityLine {
        let stopped = expiries.filter { $0 <= now }
        let expired = stopped.count
        let next = expiries.filter { $0 > now }.min()
        let status: IdleCapacityStatus
        if expired > 0 {
            status = .idle
        } else if let next, next.timeIntervalSince(now) < soonWindow {
            status = .soon
        } else {
            status = .busy
        }
        var line = IdleCapacityLine(kind: .extractors, status: status, count: expired, date: next)
        line.idleSince = stopped.min()
        return line
    }
}
