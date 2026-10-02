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

/// Runs saved fits through the same dogma engine as the Simulator to answer "does this
/// actually fit?" — CPU, powergrid and calibration with the pilot's skills and implants —
/// and, when it doesn't, which fitting skills would make it fit.
@MainActor
enum ReadyRoomFittingChecker {
    /// Skills that raise CPU/powergrid output or lower module fitting costs.
    static let cpuSkills = [3426, 3318, 3432, 3424]          // CPU Management, Weapon / Electronics / Energy Grid Upgrades
    static let powerSkills = [3413, 11207, 3425]             // Power Grid Management, Advanced Weapon / Shield Upgrades
    static var fittingSkills: [Int] { cpuSkills + powerSkills }

    /// Most engine calls spent searching one fit's training path — a fit that needs
    /// more than this many levels is reported as fitting at all-V, without the path.
    private static let searchBudget = 60

    private static var lastFailedPrepare: Date?

    /// Loads the engine's static data. Background checks (`allowLoad` false) only use an
    /// engine that's already loaded — loading checks GitHub for a new data release, which
    /// shouldn't happen every poll — and a failed load isn't retried for ten minutes.
    static func prepareEngine(allowLoad: Bool) async -> Bool {
        if DogmaEngine.shared.isReady { return true }
        guard allowLoad else { return false }
        if let lastFailedPrepare, Date.now.timeIntervalSince(lastFailedPrepare) < 600 { return false }
        defer { if !DogmaEngine.shared.isReady { lastFailedPrepare = .now } }
        await SDEDataManager.shared.ensureLoaded()
        guard let path = await SDEDataManager.shared.pbDirPath else { return false }
        if !DogmaEngine.shared.isReady { DogmaEngine.shared.prepare(pbDirPath: path) }
        return DogmaEngine.shared.isReady
    }

    /// `skills` are active levels; `shipType` and `moduleTypes` carry the dogma attributes
    /// used for calibration (the engine doesn't report it).
    static func check(
        fitting: ESIFitting,
        skills: [Int: Int],
        implants: [Int],
        shipType: ESIType?,
        moduleTypes: [Int: ESIType]
    ) -> ReadyRoomFittingCheck? {
        guard DogmaEngine.shared.isReady else { return nil }
        let slots = Self.slots(for: fitting)
        guard !slots.isEmpty else { return nil }

        func stats(_ skills: [Int: Int]) -> SimStats {
            // Online-only (passive) is enough: activation doesn't change fitting cost.
            DogmaEngine.shared.calculate(shipTypeId: fitting.shipTypeId, slots: slots, skills: skills,
                                         implantTypeIds: implants,
                                         passiveModuleTypeIds: Set(slots.compactMap(\.moduleTypeId)))
        }
        let calibration = Self.calibration(slots: slots, shipType: shipType, moduleTypes: moduleTypes)
        let now = stats(skills)
        guard now.cpuTotal > 0 || now.powerTotal > 0 else { return nil }   // engine didn't know the hull

        func result(_ s: SimStats, toFit: [Int: Int], fits: Bool) -> ReadyRoomFittingCheck {
            ReadyRoomFittingCheck(cpuUsed: s.cpuUsed, cpuTotal: s.cpuTotal, powerUsed: s.powerUsed,
                                  powerTotal: s.powerTotal, calibrationUsed: calibration.used,
                                  calibrationTotal: calibration.total, skillsToFit: toFit, fitsWithTraining: fits)
        }
        let calibrationOK = calibration.used <= calibration.total + 0.05
        if overage(now) == 0 { return result(now, toFit: [:], fits: calibrationOK) }

        // Would it fit with every fitting skill at V? If not, no training fixes it.
        var maxed = skills
        for skill in fittingSkills { maxed[skill] = 5 }
        guard calibrationOK, overage(stats(maxed)) == 0 else { return result(now, toFit: [:], fits: false) }

        // Greedy path: raise one level at a time, always the one that closes the most of
        // the gap, until it fits. Not guaranteed minimal, but short and explainable.
        var current = skills
        var budget = searchBudget
        var currentStats = now
        while overage(currentStats) > 0, budget > 0 {
            let candidates = relevantSkills(for: currentStats).filter { (current[$0] ?? 0) < 5 }
            var best: (skill: Int, stats: SimStats, overage: Double)?
            for skill in candidates where budget > 0 {
                var trial = current
                trial[skill] = (trial[skill] ?? 0) + 1
                let s = stats(trial)
                budget -= 1
                let o = overage(s)
                if best == nil || o < best!.overage { best = (skill, s, o) }
            }
            guard let best else { break }
            current[best.skill] = (current[best.skill] ?? 0) + 1
            currentStats = best.stats
        }
        var toFit: [Int: Int] = [:]
        if overage(currentStats) == 0 {
            for skill in fittingSkills where (current[skill] ?? 0) > (skills[skill] ?? 0) { toFit[skill] = current[skill] }
        } else {
            // Budget ran out: fall back to "all fitting skills to V" for the ones short of it.
            for skill in fittingSkills where (skills[skill] ?? 0) < 5 { toFit[skill] = 5 }
        }
        return result(now, toFit: toFit, fits: true)
    }

    /// Fractional overrun of CPU plus powergrid; 0 when both fit.
    private static func overage(_ s: SimStats) -> Double {
        let cpu = s.cpuTotal > 0 ? max(s.cpuUsed - s.cpuTotal, 0) / s.cpuTotal : 0
        let power = s.powerTotal > 0 ? max(s.powerUsed - s.powerTotal, 0) / s.powerTotal : 0
        return cpu + power
    }

    private static func relevantSkills(for s: SimStats) -> [Int] {
        (s.cpuUsed > s.cpuTotal ? cpuSkills : []) + (s.powerUsed > s.powerTotal ? powerSkills : [])
    }

    /// The fit's modules as simulator slots. Flags are "HiSlot0", "SubSystemSlot0", …; a flag
    /// without a parsable index gets the next free one in its group.
    private static func slots(for fitting: ESIFitting) -> [SimSlot] {
        var next: [SimSlotCategory: Int] = [:]
        var result: [SimSlot] = []
        for item in fitting.items {
            guard let category = SimSlotCategory.allCases.first(where: { item.flag.hasPrefix($0.flagPrefix) }) else { continue }
            let suffix = item.flag.dropFirst(category.flagPrefix.count).replacingOccurrences(of: "Slot", with: "")
            let index = Int(suffix) ?? next[category, default: 0]
            next[category] = max(next[category, default: 0], index + 1)
            result.append(SimSlot(category: category, index: index, moduleTypeId: item.typeId))
        }
        return result
    }

    /// Calibration from dogma attributes, as the Simulator does: 1132 on the hull, 1153 per rig.
    private static func calibration(slots: [SimSlot], shipType: ESIType?, moduleTypes: [Int: ESIType]) -> (used: Double, total: Double) {
        let total = shipType?.dogmaAttributes?.first { $0.attributeId == 1132 }?.value ?? 0
        let used = slots.filter { $0.category == .rig }.compactMap { slot in
            slot.moduleTypeId.flatMap { moduleTypes[$0]?.dogmaAttributes?.first { $0.attributeId == 1153 }?.value }
        }.reduce(0, +)
        return (used, total)
    }
}
