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

    private var cache: [Int: (key: Int, deltas: [SkillLevelKey: [FitStatDelta]])] = [:]

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
        guard !fittings.isEmpty else { return [:] }

        let implants = snapshot.pilot.implantIDs
        var hasher = Hasher()
        hasher.combine(fittings.map(\.fittingId))
        hasher.combine(fittings.map(\.items))
        hasher.combine(skills)
        hasher.combine(implants)
        let key = hasher.finalize()
        if let cached = cache[snapshot.characterID], cached.key == key { return cached.deltas }

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
        cache[snapshot.characterID] = (key, deltas)
        return deltas
    }
}
