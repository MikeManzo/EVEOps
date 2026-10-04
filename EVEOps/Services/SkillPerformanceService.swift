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

/// Runs `SkillPerformanceEngine` for a pilot's Ready Room board and remembers the answer —
/// it only changes when a skill level lands or is queued, a fit changes, or implants swap.
@MainActor
final class SkillPerformanceService {
    static let shared = SkillPerformanceService()

    private struct Entry {
        let key: Int
        let fits: [Int: DogmaFit]
        let queue: [ESISkillQueue]
        let deltas: [SkillLevelKey: [FitStatDelta]]
    }

    private var cache: [Int: Entry] = [:]

    private init() {}

    /// What the next level of each skill does for the fits this pilot can fly (counting
    /// queued training as done). Empty when the dogma engine can't be loaded.
    func deltas(for snapshot: ReadyRoomSnapshot) async -> [SkillLevelKey: [FitStatDelta]] {
        let input = snapshot.input
        let skills = SkillPerformanceEngine.levelsAfterQueue(input.skills, queue: input.skillQueue)
        let flyable = Set(snapshot.reports
            .filter { $0.unqueuedGaps.isEmpty && !$0.needsOmega && $0.tier != .blocked }
            .map(\.fittingID))
        let fittings = input.fittings.filter { flyable.contains($0.fittingId) }
        guard !fittings.isEmpty else {
            cache[snapshot.characterID] = nil
            return [:]
        }

        let implants = snapshot.pilot.implantIDs
        var hasher = Hasher()
        hasher.combine(fittings.map(\.fittingId))
        hasher.combine(fittings.map(\.items))
        hasher.combine(skills)
        hasher.combine(implants)
        let key = hasher.finalize()
        if let cached = cache[snapshot.characterID], cached.key == key { return cached.deltas }
        cache[snapshot.characterID] = nil

        guard await ReadyRoomFittingChecker.prepareEngine(allowLoad: true) else { return [:] }
        let typeIDs = Set(fittings.flatMap { [$0.shipTypeId] + $0.items.map(\.typeId) })
        let types = await UniverseCache.shared.types(ids: Array(typeIDs))
        let fits = Dictionary(uniqueKeysWithValues: fittings.map {
            ($0.fittingId, DogmaFit(fitting: $0, types: types, implants: implants, onlineOnly: false))
        })
        let candidates = SkillPerformanceEngine.candidates(input.skills, afterQueue: skills)

        let deltas = await Task.detached(priority: .userInitiated) {
            SkillPerformanceEngine.deltas(fits: fits, skills: skills, candidates: candidates) {
                DogmaEngine.shared.calculate($0, skills: $1)
            }
        }.value
        cache[snapshot.characterID] = Entry(key: key, fits: fits, queue: input.skillQueue, deltas: deltas)
        return deltas
    }

    /// Measures from a plan's levels — the fits from the last `deltas(for:)` for this pilot,
    /// with queued training still counted as done. Nil until that has run. Safe to call off
    /// the main actor.
    func remeasure(for characterID: Int) -> (@Sendable ([Int: Int], Set<Int>) -> [SkillLevelKey: [FitStatDelta]])? {
        guard let entry = cache[characterID], !entry.fits.isEmpty else { return nil }
        let fits = entry.fits
        let queue = entry.queue
        return { levels, changed in
            var skills = levels
            for item in queue { skills[item.skillId] = max(skills[item.skillId] ?? 0, item.finishedLevel) }
            return SkillPerformanceEngine.deltas(fits: fits, skills: skills, candidates: changed) {
                DogmaEngine.shared.calculate($0, skills: $1)
            }
        }
    }
}
