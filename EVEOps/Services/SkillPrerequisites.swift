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

// MARK:  Training math

/// Skill-point and training-time arithmetic shared by every screen that answers "how long
/// until I can use this?". Pure functions, so they run anywhere (including detached tasks)
/// and are unit-testable.
nonisolated enum SkillTraining {
    /// Cumulative SP for each level of a rank-1 skill; multiply by rank.
    static let spThresholds: [Int: Int] = [
        0: 0, 1: 250, 2: 1_414, 3: 8_000, 4: 45_255, 5: 256_000
    ]

    static func sp(forLevel level: Int, rank: Int) -> Int {
        (spThresholds[min(max(level, 0), 5)] ?? 0) * max(rank, 1)
    }

    /// SP still to train to reach `level`, crediting SP already in the skill (a partially
    /// trained level counts) as well as the trained level itself.
    static func spNeeded(toLevel level: Int, trainedLevel: Int, spInSkill: Int, rank: Int) -> Int {
        let have = max(spInSkill, sp(forLevel: trainedLevel, rank: rank))
        return max(sp(forLevel: level, rank: rank) - have, 0)
    }

    /// SP per minute from the character's attributes: primary + secondary / 2.
    static func spPerMinute(primary: Int, secondary: Int, attributes: ESICharacterAttributes) -> Double {
        Double(value(of: primary, in: attributes)) + Double(value(of: secondary, in: attributes)) * 0.5
    }

    /// Value of a dogma attribute ID (164–168) in the character's attributes.
    static func value(of attributeID: Int, in attributes: ESICharacterAttributes) -> Int {
        switch attributeID {
        case 164: return attributes.charisma
        case 165: return attributes.intelligence
        case 166: return attributes.memory
        case 167: return attributes.perception
        case 168: return attributes.willpower
        default:  return attributes.intelligence
        }
    }
}

// MARK:  Prerequisites

/// One skill as the training math needs it: rank and its two training attributes.
nonisolated struct SkillTrainingInfo: Sendable, Hashable {
    let skillID: Int
    let name: String
    let rank: Int
    let primaryAttribute: Int
    let secondaryAttribute: Int
    /// Longest chain of prerequisites beneath this skill (0 for a skill with none). Sorting
    /// by depth puts every prerequisite ahead of the skills that need it.
    let depth: Int
}

/// Resolves an item type's *full* skill requirements — its own required skills plus each
/// of their prerequisites, recursively — from dogma attributes, memoised per type.
///
/// Before this, the walk was copied privately into the Ship Goal Browser, Item Skill Tree
/// and Skill Requirements views; new screens should use this one.
actor SkillPrerequisites {
    static let shared = SkillPrerequisites()

    /// Dogma attribute pairs (required skill ID, required level). Skills 4–6 don't follow
    /// the simple "next ID" pattern skills 1–3 do — see `SkillRequirementsView`.
    nonisolated static let attributePairs: [(skill: Int, level: Int)] = [
        (182, 277), (183, 278), (184, 279),
        (1285, 1286), (1289, 1287), (1290, 1288)
    ]

    private var directCache: [Int: [Int: Int]] = [:]
    private var closureCache: [Int: [Int: Int]] = [:]
    private var infoCache: [Int: SkillTrainingInfo] = [:]
    private var inFlight: [Int: Task<SkillTrainingInfo?, Never>] = [:]

    /// Every skill (ID → highest required level) needed to use `typeID`, prerequisites
    /// included. Empty when the type has no requirements or its data can't be loaded.
    func requirements(for typeID: Int) async -> [Int: Int] {
        if let cached = closureCache[typeID] { return cached }
        var result: [Int: Int] = [:]
        var visited: Set<Int> = [typeID]
        await walk(typeID, into: &result, visited: &visited)
        closureCache[typeID] = result
        return result
    }

    /// Requirements for several types at once, keyed by type.
    func requirements(for typeIDs: [Int]) async -> [Int: [Int: Int]] {
        var out: [Int: [Int: Int]] = [:]
        for id in Set(typeIDs) { out[id] = await requirements(for: id) }
        return out
    }

    /// Rank, attributes and prerequisite depth for each skill.
    func trainingInfo(for skillIDs: [Int]) async -> [Int: SkillTrainingInfo] {
        var out: [Int: SkillTrainingInfo] = [:]
        for id in Set(skillIDs) {
            if let info = await info(for: id) { out[id] = info }
        }
        return out
    }

    // MARK:  Implementation

    private func walk(_ typeID: Int, into result: inout [Int: Int], visited: inout Set<Int>) async {
        for (skill, level) in await direct(for: typeID) {
            result[skill] = max(result[skill] ?? 0, level)
            guard visited.insert(skill).inserted else { continue }
            await walk(skill, into: &result, visited: &visited)
        }
    }

    private func direct(for typeID: Int) async -> [Int: Int] {
        if let cached = directCache[typeID] { return cached }
        guard let attributes = await dogma(for: typeID) else { return [:] }
        let map = Dictionary(attributes.map { ($0.attributeId, $0.value) }, uniquingKeysWith: { a, _ in a })
        var out: [Int: Int] = [:]
        for pair in Self.attributePairs {
            guard let skill = map[pair.skill].map(Int.init), skill > 0,
                  let level = map[pair.level].map(Int.init), level > 0 else { continue }
            out[skill] = max(out[skill] ?? 0, level)
        }
        directCache[typeID] = out
        return out
    }

    /// `path` is the chain of skills being resolved above this one; it stops a malformed
    /// (cyclic) prerequisite chain from recursing forever. Concurrent requests for the same
    /// skill share one in-flight lookup.
    private func info(for skillID: Int, path: Set<Int> = []) async -> SkillTrainingInfo? {
        if let cached = infoCache[skillID] { return cached }
        guard !path.contains(skillID) else { return nil }
        if let pending = inFlight[skillID] { return await pending.value }
        let task = Task { await self.resolveInfo(skillID, path: path.union([skillID])) }
        inFlight[skillID] = task
        let info = await task.value
        inFlight[skillID] = nil
        if let info { infoCache[skillID] = info }
        return info
    }

    private func resolveInfo(_ skillID: Int, path: Set<Int>) async -> SkillTrainingInfo? {
        guard let type = await UniverseCache.shared.type(id: skillID) else { return nil }
        let attributes = await dogma(for: skillID) ?? []
        func attr(_ id: Int) -> Int? { attributes.first { $0.attributeId == id }.map { Int($0.value) } }

        var depth = 0
        for prerequisite in await direct(for: skillID).keys {
            if let sub = await info(for: prerequisite, path: path) { depth = max(depth, sub.depth + 1) }
        }
        return SkillTrainingInfo(
            skillID: skillID,
            name: type.name,
            rank: max(attr(275) ?? 1, 1),
            primaryAttribute: attr(180) ?? 165,
            secondaryAttribute: attr(181) ?? 166,
            depth: depth
        )
    }

    /// Dogma attributes from the disk cache, falling back to a fresh fetch when the cached
    /// copy was saved without them.
    private func dogma(for typeID: Int) async -> [ESIDogmaAttribute]? {
        if let cached = await UniverseCache.shared.type(id: typeID)?.dogmaAttributes, !cached.isEmpty {
            return cached
        }
        let fetched: ESIType? = try? await ESIClient.shared.fetch("/universe/types/\(typeID)/", bypassCache: true)
        return fetched?.dogmaAttributes
    }
}
