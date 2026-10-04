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

/// Capacity a skill adds: more slots for something the pilot already does, and how busy
/// those slots are now.
nonisolated struct SkillROICapacity: Sendable, Hashable {
    let kind: IdleCapacityKind
    let added: Int
    let limit: Int
    /// Share of the current limit in use, 0…1 — slot time over the last week for industry
    /// (when job history is loaded), slots filled right now otherwise.
    let busyShare: Double
}

/// Where a goal's value comes from, before dividing by training days.
nonisolated struct SkillROIScore: Sendable, Hashable {
    var completes = 0.0
    var advances = 0.0
    var performance = 0.0
    var capacity = 0.0
    /// Training days the value is spread over (with the minimum applied).
    var days = 1.0

    var value: Double { completes + advances + performance + capacity }
    var total: Double { value / days }
}

/// One skill level worth training, and what it pays for.
nonisolated struct SkillROIGoal: Sendable, Identifiable {
    let skillID: Int
    let level: Int
    let name: String
    /// What to train, prerequisites first — only levels not already trained or queued.
    let plan: [ReadyRoomSkillGap]
    /// Training time for `plan`; nil when attributes or skill data are missing.
    let seconds: Double?
    /// Fits this makes flyable (with anything else they need already queued).
    let completes: [ReadyRoomReport]
    /// Fits this gets closer without finishing.
    let advances: [ReadyRoomReport]
    /// Fits the pilot can already fly that this makes better, best first.
    let improves: [FitStatDelta]
    let capacity: SkillROICapacity?
    let breakdown: SkillROIScore

    var score: Double { breakdown.total }

    var id: String { "\(skillID)-\(level)" }
    var isQuickWin: Bool { (seconds ?? .infinity) < 86400 && (!completes.isEmpty || !improves.isEmpty || capacity != nil) }
}

/// The best set of goals that fits in a training budget, in the order to train them.
nonisolated struct SkillROIPlan: Sendable {
    var picks: [SkillROIGoal] = []
    /// Training time for every pick, back to back.
    var seconds = 0.0

    /// Fits the plan makes flyable / makes better, each counted once.
    var fitsCompleted: Set<Int> { Set(picks.flatMap { $0.completes.map(\.fittingID) }) }
    var fitsImproved: Set<Int> { Set(picks.flatMap { $0.improves.map(\.fittingID) }) }
}

nonisolated struct SkillROIInput: Sendable {
    var reports: [ReadyRoomReport]
    var pinnedFittingIDs: Set<Int> = []
    var skills: [Int: ReadyRoomSkillLevel]
    var skillQueue: [ESISkillQueue] = []
    var attributes: ESICharacterAttributes?
    var skillInfo: [Int: SkillTrainingInfo]
    /// Skill → its own prerequisites (closure).
    var prerequisites: [Int: [Int: Int]] = [:]
    var capacity: IdleCapacityReport?
    /// What the next level of each skill does for flyable fits (see `SkillPerformanceEngine`).
    var performance: [SkillLevelKey: [FitStatDelta]] = [:]
    var now: Date = .now
}

// MARK:  Engine

/// Ranks skill levels by what they unlock for this pilot — saved fits that become flyable,
/// fits that get closer, flyable fits that get better, industry/market/PI/clone slots for
/// things already in use — per day of training. Not the meta: their hangar, their slots.
nonisolated enum SkillROIEngine {
    private typealias Skill = IdleCapacityEngine.Skill

    enum Weight {
        static let completesFit = 10.0
        static let advancesFit = 2.0
        static let pinned = 2.0
        static let capacity = 12.0
        /// Points per 1% gain on one fit, by stat — a 5% DPS gain on a pinned fit is worth
        /// about as much as making a fit flyable.
        static let dps = 1.0
        static let ehp = 0.8
        static let tank = 0.8
        static let speed = 0.4
        static let align = 0.4
        static let lockRange = 0.2
        /// A fit that runs out of capacitor and stops doing so.
        static let capStable = 4.0
        /// Training shorter than this counts as this long, so a 5-minute skill doesn't
        /// swamp everything else.
        static let minimumDays = 0.25
        /// What an unknown training time counts as.
        static let unknownDays = 7.0
    }

    static func goals(_ input: SkillROIInput) -> [SkillROIGoal] {
        let candidates = candidateLevels(input)
        let skillLevels = input.skills.mapValues(\.active)
        var out: [SkillROIGoal] = []
        for (skillID, level) in candidates {
            guard (input.skills[skillID]?.active ?? 0) < level else { continue }
            var needed = [skillID: level]
            for (prerequisite, prerequisiteLevel) in input.prerequisites[skillID] ?? [:] {
                needed[prerequisite] = max(needed[prerequisite] ?? 0, prerequisiteLevel)
            }
            let gaps = ReadyRoomEngine.skillGaps(needed, skills: input.skills, skillInfo: input.skillInfo,
                                                 attributes: input.attributes, queue: input.skillQueue, now: input.now)
            // An Omega-locked goal can't be trained; one fully queued is already handled.
            guard !gaps.contains(where: { $0.skillID == skillID && $0.isOmegaLocked }) else { continue }
            let plan = gaps.filter { !$0.isQueued && !$0.isOmegaLocked }
            guard plan.contains(where: { $0.skillID == skillID }) else { continue }
            let seconds: Double? = plan.contains { $0.seconds == nil } ? nil : plan.reduce(0) { $0 + ($1.seconds ?? 0) }

            // Levels after training the plan.
            var after = skillLevels
            for gap in plan { after[gap.skillID] = max(after[gap.skillID] ?? 0, gap.requiredLevel) }

            var completes: [ReadyRoomReport] = []
            var advances: [ReadyRoomReport] = []
            for report in input.reports where report.tier == .train && !report.needsOmega {
                // Gaps an earlier pick in a plan already closed don't count again.
                let remaining = report.unqueuedGaps.filter { (skillLevels[$0.skillID] ?? 0) < $0.requiredLevel }
                guard !remaining.isEmpty else { continue }
                let covered = remaining.filter { (after[$0.skillID] ?? 0) >= $0.requiredLevel }
                if covered.count == remaining.count {
                    completes.append(report)
                } else if !covered.isEmpty {
                    advances.append(report)
                }
            }

            let capacity = capacityGain(skillID: skillID, before: skillLevels, after: after, report: input.capacity)
            func pinned(_ fittingID: Int) -> Double { input.pinnedFittingIDs.contains(fittingID) ? Weight.pinned : 1 }
            let improves = (input.performance[SkillLevelKey(skillID: skillID, level: level)] ?? [])
                .map { (delta: $0, points: performancePoints($0) * pinned($0.fittingID)) }
                .sorted { $0.points > $1.points }
            guard !completes.isEmpty || !advances.isEmpty || !improves.isEmpty || capacity != nil else { continue }

            var breakdown = SkillROIScore()
            breakdown.completes = completes.reduce(0) { $0 + Weight.completesFit * pinned($1.fittingID) }
            breakdown.advances = advances.reduce(0) { $0 + Weight.advancesFit * pinned($1.fittingID) }
            breakdown.performance = improves.reduce(0) { $0 + $1.points }
            if let capacity {
                let share = min(Double(capacity.added) / Double(max(capacity.limit, 1)), 1)
                breakdown.capacity = Weight.capacity * capacity.busyShare * capacity.busyShare * share
            }
            breakdown.days = seconds.map { max($0 / 86400, Weight.minimumDays) } ?? Weight.unknownDays

            out.append(SkillROIGoal(
                skillID: skillID,
                level: level,
                name: input.skillInfo[skillID]?.name ?? plan.first { $0.skillID == skillID }?.name ?? "Skill #\(skillID)",
                plan: plan,
                seconds: seconds,
                completes: completes.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending },
                advances: advances.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending },
                improves: improves.map(\.delta),
                capacity: capacity,
                breakdown: breakdown
            ))
        }
        return out.sorted { a, b in
            if a.score != b.score { return a.score > b.score }
            return (a.seconds ?? .infinity) < (b.seconds ?? .infinity)
        }
    }

    // MARK: Plan

    /// Greedy plan: take the best goal that still fits the budget, count it as trained,
    /// rank again, repeat. Re-ranking keeps shared prerequisites from being paid for twice
    /// and stops crediting a fit to later picks once an earlier one made it flyable.
    /// - Parameters:
    ///   - include: which goals may be picked (the screen's filter). A pick still scores for
    ///     everything it does, not just the kind of value that let it in.
    ///   - remeasure: given levels after the picks so far and the skills a pick just
    ///     changed, what the next level of each of those does for flyable fits.
    static func plan(_ input: SkillROIInput, budget: TimeInterval, maxPicks: Int = 40,
                     include: (SkillROIGoal) -> Bool = { _ in true },
                     remeasure: ([Int: Int], Set<Int>) -> [SkillLevelKey: [FitStatDelta]] = { _, _ in [:] }) -> SkillROIPlan {
        var state = input
        var plan = SkillROIPlan()
        while plan.picks.count < maxPicks {
            let next = goals(state).first { goal in
                guard include(goal), let seconds = goal.seconds else { return false }
                return plan.seconds + seconds <= budget
            }
            guard let pick = next, let seconds = pick.seconds else { break }
            plan.picks.append(pick)
            plan.seconds += seconds

            var changed = Set<Int>()
            for gap in pick.plan {
                let had = state.skills[gap.skillID]
                let rank = state.skillInfo[gap.skillID]?.rank ?? 1
                state.skills[gap.skillID] = ReadyRoomSkillLevel(
                    active: gap.requiredLevel,
                    trained: max(had?.trained ?? 0, gap.requiredLevel),
                    sp: max(had?.sp ?? 0, SkillTraining.sp(forLevel: gap.requiredLevel, rank: rank))
                )
                changed.insert(gap.skillID)
            }
            // Measurements for levels just trained are spent; the next level of each changed
            // skill is measured from the new baseline.
            state.performance = state.performance.filter { !changed.contains($0.key.skillID) }
            state.performance.merge(remeasure(state.skills.mapValues(\.active), changed)) { _, new in new }
        }
        return plan
    }

    // MARK: Candidates

    /// Skill levels worth pricing: every gap standing between the pilot and a saved fit,
    /// plus the next level of each slot skill for activities the pilot already does.
    static func candidateLevels(_ input: SkillROIInput) -> [(skillID: Int, level: Int)] {
        var seen = Set<String>()
        var out: [(Int, Int)] = []
        func add(_ skillID: Int, _ level: Int) {
            guard level <= 5, seen.insert("\(skillID)-\(level)").inserted else { return }
            out.append((skillID, level))
        }
        for report in input.reports where report.tier == .train && !report.needsOmega {
            for gap in report.unqueuedGaps { add(gap.skillID, gap.requiredLevel) }
        }
        for skillID in slotSkills(input.capacity, skills: input.skills.mapValues(\.active)) {
            add(skillID, (input.skills[skillID]?.active ?? 0) + 1)
        }
        for key in input.performance.keys.sorted(by: { ($0.skillID, $0.level) < ($1.skillID, $1.level) }) {
            add(key.skillID, key.level)
        }
        return out
    }

    // MARK: Performance

    /// Points for one fit's gains, before the pinned multiplier.
    static func performancePoints(_ delta: FitStatDelta) -> Double {
        let weights: [FitStatDelta.Stat: Double] = [
            .dps: Weight.dps, .ehp: Weight.ehp, .tank: Weight.tank,
            .speed: Weight.speed, .align: Weight.align, .lockRange: Weight.lockRange,
        ]
        let percent = FitStatDelta.Stat.allCases.reduce(0) { $0 + (weights[$1] ?? 0) * delta.gain($1) * 100 }
        return percent + (delta.becomesCapStable ? Weight.capStable : 0)
    }

    /// For each capacity line the pilot has, the slot skill to raise next.
    static func slotSkills(_ report: IdleCapacityReport?, skills: [Int: Int]) -> [Int] {
        guard let report else { return [] }
        func next(_ chain: [Int]) -> Int? { chain.first { (skills[$0] ?? 0) < 5 } }
        var out: [Int] = []
        for line in report.lines {
            let skill: Int?
            switch line.kind {
            case .manufacturing: skill = next([Skill.massProduction, Skill.advancedMassProduction])
            case .science:       skill = next([Skill.laboratoryOperation, Skill.advancedLaboratoryOperation])
            case .reactions:     skill = next([Skill.massReactions, Skill.advancedMassReactions])
            case .market:        skill = next([Skill.trade, Skill.retail, Skill.wholesale, Skill.tycoon])
            case .contracts:     skill = next([Skill.contracting])
            case .planets:       skill = next([Skill.interplanetaryConsolidation])
            case .cloneJump:     skill = next([Skill.infomorphPsychology, Skill.advancedInfomorphPsychology])
            default:             skill = nil
            }
            if let skill { out.append(skill) }
        }
        return out
    }

    // MARK: Capacity

    /// Slots a goal adds to a line the pilot has, with how busy that line is.
    static func capacityGain(skillID: Int, before: [Int: Int], after: [Int: Int],
                             report: IdleCapacityReport?) -> SkillROICapacity? {
        guard let report else { return nil }
        let kinds: [(IdleCapacityKind, ([Int: Int]) -> Int, Set<Int>)] = [
            (.manufacturing, IdleCapacityEngine.manufacturingSlots, [Skill.massProduction, Skill.advancedMassProduction]),
            (.science, IdleCapacityEngine.scienceSlots, [Skill.laboratoryOperation, Skill.advancedLaboratoryOperation]),
            (.reactions, IdleCapacityEngine.reactionSlots, [Skill.reactions, Skill.massReactions, Skill.advancedMassReactions]),
            (.market, IdleCapacityEngine.orderSlots, [Skill.trade, Skill.retail, Skill.wholesale, Skill.tycoon]),
            (.contracts, IdleCapacityEngine.contractSlots, [Skill.contracting]),
            (.planets, IdleCapacityEngine.planetLimit, [Skill.interplanetaryConsolidation]),
            (.cloneJump, IdleCapacityEngine.jumpCloneLimit, [Skill.infomorphPsychology, Skill.advancedInfomorphPsychology]),
        ]
        for (kind, limit, skills) in kinds where skills.contains(skillID) {
            guard let line = report.line(kind) else { return nil }
            let added = limit(after) - limit(before)
            guard added > 0 else { return nil }
            let current = line.limit ?? limit(before)
            return SkillROICapacity(kind: kind, added: added, limit: current,
                                    busyShare: busyShare(line, limit: current))
        }
        return nil
    }

    /// How much of a line's capacity is in use: industry slot time over the idle window
    /// when known, otherwise slots filled now.
    static func busyShare(_ line: IdleCapacityLine, limit: Int) -> Double {
        guard limit > 0 else { return 0 }
        if let idle = line.idleSlotTime {
            return min(max(1 - idle / (Double(limit) * IdleCapacityEngine.idleWindow), 0), 1)
        }
        let used = max((line.used ?? 0) - line.count, 0)
        return min(Double(used) / Double(limit), 1)
    }

    // MARK: Export

    /// EVE's skill plan text: one "Skill Name Level" line per level, prerequisites first —
    /// pastes straight into the in-game skill queue.
    static func eveSkillPlan(_ goals: [SkillROIGoal], skills: [Int: ReadyRoomSkillLevel]) -> String {
        var reached = skills.mapValues(\.active)
        var lines: [String] = []
        for gap in goals.flatMap(\.plan) {
            let from = reached[gap.skillID] ?? 0
            guard gap.requiredLevel > from else { continue }
            for level in (from + 1)...gap.requiredLevel {
                lines.append("\(gap.name) \(roman(level))")
            }
            reached[gap.skillID] = gap.requiredLevel
        }
        return lines.joined(separator: "\n")
    }

    private static func roman(_ level: Int) -> String {
        ["0", "I", "II", "III", "IV", "V"][min(max(level, 0), 5)]
    }
}
