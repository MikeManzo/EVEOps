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
    case training, manufacturing, science, reactions, market, planets, extractors, cloneJump, research
}

/// How a capacity line stands right now.
nonisolated enum IdleCapacityStatus: Int, Comparable, Sendable {
    /// Capacity is sitting unused (or work is finished and waiting to be collected).
    case idle
    /// Fully used, but it frees up within `IdleCapacityEngine.soonWindow`.
    case soon
    /// Fully used for a while yet.
    case busy
    /// Informational — nothing to act on (clone jump timers, research points).
    case info

    static func < (a: Self, b: Self) -> Bool { a.rawValue < b.rawValue }
}

/// An industry job, reduced to what slot usage needs.
nonisolated struct IdleCapacityJob: Sendable {
    let activityID: Int
    /// ESI status: active, paused, ready (finished, not delivered), …
    let status: String
    let endDate: Date
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
    /// Finish date of each skill queue entry; nil for a paused queue.
    var queueFinishDates: [Date?] = []
    var jobs: [IdleCapacityJob] = []
    var orderCount = 0
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
}

// MARK:  Engine

nonisolated enum IdleCapacityEngine {
    /// "Soon" means within a day — the same window the Colonies screen uses.
    static let soonWindow: TimeInterval = 24 * 3600

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
    }

    enum Activity {
        static let manufacturing: Set<Int> = [1]
        /// TE and ME research, copying, reverse engineering, invention.
        static let science: Set<Int> = [3, 4, 5, 7, 8]
        static let reactions: Set<Int> = [9, 11]
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

    /// 24 hours between clone jumps, an hour less per level of Infomorph Synchronizing.
    /// Nil when a jump is allowed now.
    static func cloneJumpReadyAt(lastJump: Date?, infomorphSynchronizing: Int, now: Date = .now) -> Date? {
        guard let lastJump else { return nil }
        let ready = lastJump.addingTimeInterval(Double(24 - infomorphSynchronizing) * 3600)
        return ready > now ? ready : nil
    }

    // MARK: Report

    /// A pilot's capacity. Slot lines only appear for activities the pilot has invested
    /// in (trained the slot skill or is using it), so a pure combat pilot isn't told
    /// their one factory slot is idle.
    static func report(_ input: IdleCapacityInput, now: Date = .now) -> IdleCapacityReport {
        let skills = input.skills
        var lines: [IdleCapacityLine] = [training(input.queueFinishDates, now: now)]

        let manufacturing = input.jobs.filter { Activity.manufacturing.contains($0.activityID) }
        if skills[Skill.industry, default: 0] > 0 || skills[Skill.massProduction, default: 0] > 0 || !manufacturing.isEmpty {
            lines.append(slots(.manufacturing, jobs: manufacturing, limit: manufacturingSlots(skills), now: now))
        }
        let science = input.jobs.filter { Activity.science.contains($0.activityID) }
        if skills[Skill.laboratoryOperation, default: 0] > 0 || !science.isEmpty {
            lines.append(slots(.science, jobs: science, limit: scienceSlots(skills), now: now))
        }
        let reactions = input.jobs.filter { Activity.reactions.contains($0.activityID) }
        if reactionSlots(skills) > 0 || !reactions.isEmpty {
            lines.append(slots(.reactions, jobs: reactions, limit: reactionSlots(skills), now: now))
        }

        if skills[Skill.trade, default: 0] > 0 || input.orderCount > 0 {
            let limit = orderSlots(skills)
            lines.append(IdleCapacityLine(kind: .market, status: input.orderCount < limit ? .idle : .busy,
                                          used: input.orderCount, limit: limit))
        }

        if skills[Skill.interplanetaryConsolidation, default: 0] > 0 || input.colonyCount > 0 {
            let limit = planetLimit(skills)
            lines.append(IdleCapacityLine(kind: .planets, status: input.colonyCount < limit ? .idle : .busy,
                                          used: input.colonyCount, limit: limit))
        }
        if input.colonyCount > 0, let expiries = input.extractorExpiries, !expiries.isEmpty {
            lines.append(extractors(expiries, now: now))
        }

        if input.jumpCloneCount > 0 {
            let readyAt = cloneJumpReadyAt(lastJump: input.lastCloneJump,
                                           infomorphSynchronizing: skills[Skill.infomorphSynchronizing, default: 0],
                                           now: now)
            lines.append(IdleCapacityLine(kind: .cloneJump, status: .info, count: input.jumpCloneCount, date: readyAt))
        }

        if let agents = input.researchAgents, !agents.isEmpty {
            let points = agents.reduce(0) { sum, agent in
                sum + agent.remainderPoints + agent.pointsPerDay * now.timeIntervalSince(agent.startedAt) / 86400
            }
            lines.append(IdleCapacityLine(kind: .research, status: .info, count: agents.count, points: points))
        }

        return IdleCapacityReport(lines: lines)
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

    /// Jobs occupy a slot until delivered, so finished ones still count as used — but they
    /// are reported (`count`) and make the line idle, since the slot is doing nothing.
    private static func slots(_ kind: IdleCapacityKind, jobs: [IdleCapacityJob], limit: Int, now: Date) -> IdleCapacityLine {
        let occupying = jobs.filter { ["active", "paused", "ready"].contains($0.status) }
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
        return IdleCapacityLine(kind: kind, status: status, used: occupying.count, limit: limit,
                                count: finished.count, date: nextFree)
    }

    /// Idle when any extractor has stopped; soon when one stops within a day.
    private static func extractors(_ expiries: [Date], now: Date) -> IdleCapacityLine {
        let expired = expiries.filter { $0 <= now }.count
        let next = expiries.filter { $0 > now }.min()
        let status: IdleCapacityStatus
        if expired > 0 {
            status = .idle
        } else if let next, next.timeIntervalSince(now) < soonWindow {
            status = .soon
        } else {
            status = .busy
        }
        return IdleCapacityLine(kind: .extractors, status: status, count: expired, date: next)
    }
}
