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
import os

// MARK:  Models

/// One level of one skill.
nonisolated struct SkillLevelKey: Sendable, Hashable {
    let skillID: Int
    let level: Int
}

/// The stats Skill ROI compares a fit on, before and after a skill level.
nonisolated struct FitPerformance: Sendable, Hashable {
    var dps: Double
    /// Average EHP over the four damage types.
    var ehp: Double
    /// Shield, armor and hull repair plus passive shield regen, HP/s.
    var tank: Double
    var speed: Double
    var alignTime: Double
    var lockRange: Double
    var capStable: Bool

    init(_ stats: SimStats) {
        dps = stats.dps
        ehp = (stats.ehp.em + stats.ehp.explosive + stats.ehp.kinetic + stats.ehp.thermal) / 4
        tank = stats.shieldBoostRate + stats.armorRepairRate + stats.hullRepairRate + stats.passiveShieldRate
        speed = stats.maxVelocity
        alignTime = stats.alignTime
        lockRange = stats.maxTargetRange
        capStable = stats.isCapStable
    }
}

/// How a skill level changes one fit. Each is a fractional gain (0.032 = 3.2% better), 0
/// when unchanged; align time counts as a gain when it gets shorter.
nonisolated struct FitStatDelta: Sendable, Hashable {
    let fittingID: Int
    var dps = 0.0
    var ehp = 0.0
    var tank = 0.0
    var speed = 0.0
    var align = 0.0
    var lockRange = 0.0
    var becomesCapStable = false

    enum Stat: CaseIterable, Sendable {
        case dps, ehp, tank, speed, align, lockRange
    }

    func gain(_ stat: Stat) -> Double {
        switch stat {
        case .dps:       dps
        case .ehp:       ehp
        case .tank:      tank
        case .speed:     speed
        case .align:     align
        case .lockRange: lockRange
        }
    }

    var isEmpty: Bool { !becomesCapStable && Stat.allCases.allSatisfy { gain($0) == 0 } }

    /// The stat that improves most, for a one-line summary.
    var headline: (stat: Stat, gain: Double)? {
        Stat.allCases.map { ($0, gain($0)) }.max { $0.1 < $1.1 }.flatMap { $0.1 > 0 ? $0 : nil }
    }
}

// MARK:  Engine

/// Measures what the next level of each skill does for the fits a pilot can already fly —
/// DPS, tank, speed, lock range, capacitor — by running each fit through the dogma engine
/// before and after. Skills that change nothing on any fit are left out.
nonisolated enum SkillPerformanceEngine {
    /// Changes smaller than this are rounding, not a reason to train.
    static let threshold = 0.001

    /// - Parameters:
    ///   - fits: fitting ID → the fit as the engine sees it, for combat.
    ///   - skills: the pilot's levels with everything queued counted as trained.
    ///   - candidates: skills whose next level to measure; ones already at V are skipped.
    ///   - stats: the dogma engine, or a stand-in in tests. Called from several threads.
    static func deltas(fits: [Int: DogmaFit], skills: [Int: Int], candidates: Set<Int>,
                       stats: @Sendable (DogmaFit, [Int: Int]) -> SimStats) -> [SkillLevelKey: [FitStatDelta]] {
        let levels = candidates.compactMap { skill -> SkillLevelKey? in
            let next = (skills[skill] ?? 0) + 1
            return next <= 5 ? SkillLevelKey(skillID: skill, level: next) : nil
        }
        guard !levels.isEmpty, !fits.isEmpty else { return [:] }

        let fitList = fits.sorted { $0.key < $1.key }
        let results = OSAllocatedUnfairLock(initialState: [SkillLevelKey: [FitStatDelta]]())
        // One fit per worker: its baseline, then every candidate level against it.
        DispatchQueue.concurrentPerform(iterations: fitList.count) { index in
            let (fittingID, fit) = fitList[index]
            let base = FitPerformance(stats(fit, skills))
            var found: [(SkillLevelKey, FitStatDelta)] = []
            for key in levels {
                var trained = skills
                trained[key.skillID] = key.level
                let delta = delta(fittingID: fittingID, from: base, to: FitPerformance(stats(fit, trained)))
                if !delta.isEmpty { found.append((key, delta)) }
            }
            results.withLock { all in
                for (key, delta) in found { all[key, default: []].append(delta) }
            }
        }
        return results.withLock { $0 }.mapValues { $0.sorted { $0.fittingID < $1.fittingID } }
    }

    static func delta(fittingID: Int, from before: FitPerformance, to after: FitPerformance) -> FitStatDelta {
        func gain(_ old: Double, _ new: Double) -> Double {
            guard old > 0 else { return 0 }
            let change = (new - old) / old
            return change >= threshold ? change : 0
        }
        var delta = FitStatDelta(fittingID: fittingID)
        delta.dps = gain(before.dps, after.dps)
        delta.ehp = gain(before.ehp, after.ehp)
        delta.tank = gain(before.tank, after.tank)
        delta.speed = gain(before.speed, after.speed)
        // Shorter is better: the share of align time saved.
        if before.alignTime > 0, after.alignTime > 0 {
            let saved = (before.alignTime - after.alignTime) / before.alignTime
            delta.align = saved >= threshold ? saved : 0
        }
        delta.lockRange = gain(before.lockRange, after.lockRange)
        delta.becomesCapStable = !before.capStable && after.capStable
        return delta
    }

    /// The pilot's levels with every queued level counted as trained.
    static func levelsAfterQueue(_ skills: [Int: ReadyRoomSkillLevel], queue: [ESISkillQueue]) -> [Int: Int] {
        var out = skills.mapValues(\.active)
        for entry in queue { out[entry.skillId] = max(out[entry.skillId] ?? 0, entry.finishedLevel) }
        return out
    }

    /// Skills worth measuring: ones the pilot has, short of V, not capped by an Alpha clone.
    static func candidates(_ skills: [Int: ReadyRoomSkillLevel], afterQueue: [Int: Int]) -> Set<Int> {
        Set(skills.compactMap { id, level in
            level.active >= level.trained && (afterQueue[id] ?? level.active) < 5 ? id : nil
        })
    }
}
