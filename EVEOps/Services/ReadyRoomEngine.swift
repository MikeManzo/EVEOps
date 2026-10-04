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

/// How close a saved fitting is to undocking. Ordered from "go now" to "can't": a fit
/// that needs training is further away than one that only needs parts bought.
nonisolated enum ReadyRoomTier: Int, CaseIterable, Comparable, Sendable {
    /// Flyable, fits, and every part is in the pilot's current station.
    case ready
    /// Flyable and fully owned, but the parts are somewhere else (or spread out).
    case travel
    /// Flyable; the parts not owned yet are already on their way (buy orders, industry
    /// jobs, courier contracts).
    case waiting
    /// Flyable, but some parts aren't owned or incoming anywhere.
    case buy
    /// A required or fitting skill isn't trained yet (queued counts as not yet).
    case train
    /// Over CPU, powergrid or calibration even with every fitting skill at V.
    case blocked

    static func < (lhs: Self, rhs: Self) -> Bool { lhs.rawValue < rhs.rawValue }
}

/// A station, structure, or (for ships in space) solar system holding assets.
nonisolated struct ReadyRoomPlace: Sendable, Hashable, Identifiable {
    let id: Int
    let name: String
    let systemID: Int?
    let systemName: String?
    let security: Double?

    var isInSpace: Bool { (30_000_000..<33_000_000).contains(id) }
}

/// One asset stack, reduced to what readiness needs.
nonisolated struct ReadyRoomHolding: Sendable, Hashable {
    let itemID: Int
    let typeID: Int
    let quantity: Int
    /// The station, structure or solar system the stack ultimately sits in — the end of
    /// its container chain (hangar → ship → can → …).
    let placeID: Int
    /// The ship this module is fitted to (a high/mid/low/rig/subsystem slot). Fitted
    /// modules only count toward a fit that uses that very hull.
    let fittedToItemID: Int?
    let isAssembled: Bool
    /// Held in a corporation hangar rather than the pilot's own.
    var isCorporation = false
    /// The slot it's fitted in ("LoSlot0"), when `fittedToItemID` is set.
    var slotFlag: String? = nil
}

/// A part already on its way to the pilot.
nonisolated struct ReadyRoomIncoming: Sendable, Hashable {
    enum Kind: Int, Sendable, Hashable {
        case industry, courier, buyOrder
    }

    let kind: Kind
    let typeID: Int
    let quantity: Int
    /// Where it will land, when known.
    let placeID: Int?
    /// When it lands, when known (industry end date). Buy orders have none.
    let eta: Date?
}

/// A pilot's level in one skill.
nonisolated struct ReadyRoomSkillLevel: Sendable, Hashable {
    /// The level the pilot can use now (capped on an Alpha clone).
    let active: Int
    /// The level trained, Omega or not.
    let trained: Int
    let sp: Int
}

/// Result of running a fit through the dogma engine with the pilot's skills and implants.
nonisolated struct ReadyRoomFittingCheck: Sendable, Hashable {
    let cpuUsed: Double
    let cpuTotal: Double
    let powerUsed: Double
    let powerTotal: Double
    let calibrationUsed: Double
    let calibrationTotal: Double
    /// Fitting skills (skill → level) the pilot would need to train for the fit to fit.
    /// Empty when it already fits, or when even all-V won't do it.
    let skillsToFit: [Int: Int]
    /// False when the fit is over budget even with every fitting skill at V.
    let fitsWithTraining: Bool

    var fitsNow: Bool {
        cpuUsed <= cpuTotal + 0.05 && powerUsed <= powerTotal + 0.05 && calibrationUsed <= calibrationTotal + 0.05
    }
}

nonisolated struct ReadyRoomSkillGap: Sendable, Hashable, Identifiable {
    let skillID: Int
    let name: String
    let trainedLevel: Int
    let requiredLevel: Int
    /// SP still to train; 0 for an Omega-locked skill (already trained).
    let sp: Int
    /// Training time from now at the pilot's current attributes; nil when unknown or Omega-locked.
    let seconds: Double?
    /// Set when the skill queue already reaches `requiredLevel` — when that level lands.
    let queuedFinish: Date?
    let depth: Int
    /// Trained high enough, but capped by an Alpha clone — only Omega unlocks it.
    let isOmegaLocked: Bool
    /// Needed only so the fit stays within CPU/powergrid, not to use the hull or modules.
    let isForFitting: Bool

    var id: Int { skillID }
    var isQueued: Bool { queuedFinish != nil }
}

nonisolated struct ReadyRoomPartLine: Sendable, Hashable, Identifiable {
    struct Elsewhere: Sendable, Hashable {
        let placeID: Int
        let quantity: Int
        var isCorporation = false
    }

    struct Incoming: Sendable, Hashable {
        let kind: ReadyRoomIncoming.Kind
        let quantity: Int
        let placeID: Int?
        let eta: Date?
    }

    /// An owned better version of the part (Tech II for Tech I) standing in for it.
    struct Substitute: Sendable, Hashable {
        let typeID: Int
        let name: String
        let quantity: Int
    }

    /// What the staged hull has today in a slot a missing unit would take.
    struct Displaced: Sendable, Hashable {
        let flag: String
        /// The module fitted there now; nil when the slot is empty.
        let typeID: Int?
        let name: String?
    }

    let typeID: Int
    let name: String
    /// Slot group label ("High Slots", "Drone Bay", "Hull", …).
    let category: String
    let required: Int
    let atStaging: Int
    let elsewhere: [Elsewhere]
    let incoming: [Incoming]
    let missing: Int
    let unitPrice: Double?
    /// How many of the owned units (staged or elsewhere) come from corporation hangars.
    let fromCorporation: Int
    /// Cargo items (ammo, scripts, paste) — listed, but never block readiness.
    let isOptional: Bool
    /// Owned stand-ins counted toward `atStaging` and `elsewhere`.
    var substitutes: [Substitute] = []
    /// One entry per missing unit, when the fit has an assembled hull at staging: the
    /// module (or empty slot) the purchase replaces.
    var displaced: [Displaced] = []

    var id: String { "\(category)-\(typeID)" }
    var elsewhereQuantity: Int { elsewhere.reduce(0) { $0 + $1.quantity } }
    var incomingQuantity: Int { incoming.reduce(0) { $0 + $1.quantity } }
    var missingCost: Double? { missing == 0 ? 0 : unitPrice.map { $0 * Double(missing) } }
}

nonisolated struct ReadyRoomReport: Sendable, Hashable, Identifiable {
    let fittingID: Int
    let name: String
    let fittingDescription: String
    let shipTypeID: Int
    let shipTypeName: String
    let shipClassName: String
    let tier: ReadyRoomTier

    let skillGaps: [ReadyRoomSkillGap]
    /// Training still to queue (excludes queued and Omega-locked skills); nil when the
    /// pilot's attributes aren't known.
    let trainingSeconds: Double?
    /// When the last queued requirement finishes, if the queue covers any.
    let queuedUntil: Date?
    /// Skills (ID → level) to use the hull and its modules — no fitting skills. What other
    /// pilots are measured against.
    let requiredSkills: [Int: Int]
    /// CPU / powergrid / calibration result; nil until the dogma engine has run.
    let fitting: ReadyRoomFittingCheck?

    let parts: [ReadyRoomPartLine]
    let staging: ReadyRoomPlace?
    let stagingJumps: Int?
    let isStagingCurrentLocation: Bool
    /// The assembled hull picked at the staging location, if any.
    let stagedHullItemID: Int?
    /// One of the pilot's jump clones sits in the staging station.
    let hasJumpCloneAtStaging: Bool

    var id: Int { fittingID }
    var requiredParts: [ReadyRoomPartLine] { parts.filter { !$0.isOptional } }
    var optionalParts: [ReadyRoomPartLine] { parts.filter(\.isOptional) }
    var requiredCount: Int { requiredParts.reduce(0) { $0 + $1.required } }
    var atStagingCount: Int { requiredParts.reduce(0) { $0 + $1.atStaging } }
    var ownedCount: Int { requiredParts.reduce(0) { $0 + $1.atStaging + $1.elsewhereQuantity } }
    var incomingCount: Int { requiredParts.reduce(0) { $0 + $1.incomingQuantity } }
    var missingCount: Int { requiredParts.reduce(0) { $0 + $1.missing } }
    var corporationCount: Int { requiredParts.reduce(0) { $0 + $1.fromCorporation } }
    /// Gaps that still need queueing — neither queued nor Omega-locked.
    var unqueuedGaps: [ReadyRoomSkillGap] { skillGaps.filter { !$0.isQueued && !$0.isOmegaLocked } }
    var needsOmega: Bool { skillGaps.contains(where: \.isOmegaLocked) }
    var isFlyable: Bool { skillGaps.isEmpty }
    var hasHullAtStaging: Bool { parts.first { $0.category == ReadyRoomEngine.hullCategory }?.atStaging == 1 }
    /// Stations (other than staging) that hold parts to collect.
    var collectionPlaceIDs: [Int] {
        var seen = Set<Int>()
        return requiredParts.flatMap(\.elsewhere).map(\.placeID).filter { seen.insert($0).inserted }
    }

    /// ISK to buy every missing required part; nil while any of them is unpriced.
    var missingISK: Double? {
        var total = 0.0
        for line in requiredParts where line.missing > 0 {
            guard let cost = line.missingCost else { return nil }
            total += cost
        }
        return total
    }
}

/// Everything the engine reads. Built by `ReadyRoomService`; plain values so the engine
/// can run off the main actor and in tests.
nonisolated struct ReadyRoomInput: Sendable {
    var fittings: [ESIFitting]
    var typeNames: [Int: String]
    /// Ship type ID → class name ("Assault Frigate").
    var shipClassNames: [Int: String]
    /// Type ID → full skill requirements (prerequisites included). Also holds entries for
    /// fitting skills, so their own prerequisites come along when a fit needs them.
    var requirements: [Int: [Int: Int]]
    var skillInfo: [Int: SkillTrainingInfo]
    var skills: [Int: ReadyRoomSkillLevel]
    var skillQueue: [ESISkillQueue]
    var attributes: ESICharacterAttributes?
    var holdings: [ReadyRoomHolding]
    var places: [Int: ReadyRoomPlace]
    /// The pilot's station/structure, or their solar system when in space.
    var currentPlaceID: Int?
    /// System ID → jumps from the pilot's current system.
    var jumps: [Int: Int]
    var prices: [Int: Double]
    var incoming: [ReadyRoomIncoming] = []
    /// Fitting ID → dogma result.
    var fittingChecks: [Int: ReadyRoomFittingCheck] = [:]
    /// Stations and structures holding one of the pilot's jump clones.
    var jumpClonePlaceIDs: Set<Int> = []
    /// Fit type → better versions (Tech II for Tech I) the pilot owns and can use, best
    /// first. Owned ones stand in when the exact part is missing.
    var substitutes: [Int: [Int]] = [:]
    var now: Date = .now
}

// MARK:  Engine

nonisolated enum ReadyRoomEngine {
    static let hullCategory = "Hull"

    // MARK:  Reports

    static func reports(_ input: ReadyRoomInput) -> [ReadyRoomReport] {
        let pools = Pools(holdings: input.holdings)
        let incoming = Dictionary(grouping: input.incoming, by: \.typeID)
            .mapValues { $0.sorted { ($0.eta ?? .distantFuture) < ($1.eta ?? .distantFuture) } }
        return input.fittings.map { report(for: $0, input: input, pools: pools, incoming: incoming) }
    }

    private static func report(for fitting: ESIFitting, input: ReadyRoomInput, pools: Pools,
                               incoming: [Int: [ReadyRoomIncoming]]) -> ReadyRoomReport {
        // Demand: hull first, then each type by slot group, quantities summed.
        var demand: [(typeID: Int, category: String, quantity: Int, optional: Bool)] = [
            (fitting.shipTypeId, hullCategory, 1, false)
        ]
        var seen: [String: Int] = [:]
        for item in fitting.items {
            let category = slotCategory(item.flag)
            let key = "\(category)-\(item.typeId)"
            if let index = seen[key] {
                demand[index].quantity += item.quantity
            } else {
                seen[key] = demand.count
                demand.append((item.typeId, category, item.quantity, category == "Cargo"))
            }
        }
        let required = demand.filter { !$0.optional }
        var needByType: [Int: Int] = [:]
        for line in required where line.category != hullCategory { needByType[line.typeID, default: 0] += line.quantity }

        // Staging: the place where the most of the fit (by value) already sits.
        let staging = chooseStaging(fitting: fitting, needByType: needByType, input: input, pools: pools)
        var claimedFitted: [Int: Int] = [:]                 // type → qty used from the staged hull's slots
        var claimedPersonal: [Int: [Int: Int]] = [:]        // place → type → qty already claimed by this fit
        var claimedCorporation: [Int: [Int: Int]] = [:]
        var claimedIncoming: [Int: Int] = [:]               // type → qty of incoming already claimed

        /// The pilot's own stock first, then corporation stock, net of what this fit
        /// already claimed (a type can appear in more than one slot group).
        func take(_ typeID: Int, at placeID: Int, upTo want: Int) -> (personal: Int, corporation: Int) {
            let personalLeft = pools.quantity(of: typeID, at: placeID, corporation: false)
                - (claimedPersonal[placeID]?[typeID] ?? 0)
            let corpLeft = pools.quantity(of: typeID, at: placeID, corporation: true)
                - (claimedCorporation[placeID]?[typeID] ?? 0)
            let personal = max(min(personalLeft, want), 0)
            let corporation = max(min(corpLeft, want - personal), 0)
            claimedPersonal[placeID, default: [:]][typeID, default: 0] += personal
            claimedCorporation[placeID, default: [:]][typeID, default: 0] += corporation
            return (personal, corporation)
        }

        struct Match {
            var remaining: Int
            var atStaging = 0
            var fromCorporation = 0
            var elsewhere: [ReadyRoomPartLine.Elsewhere] = []
            var substitutes: [Int: Int] = [:]               // substitute type → qty used
            var arriving: [ReadyRoomPartLine.Incoming] = []
        }

        /// Takes `typeID` for a line: off the staged hull's slots, the staging hangar, then
        /// the nearest other places.
        func claim(_ typeID: Int, category: String, into match: inout Match) -> Int {
            let before = match.remaining
            if let staging, category != hullCategory {
                let fitted = max((staging.fittedCounts[typeID] ?? 0) - claimedFitted[typeID, default: 0], 0)
                let fromFitted = min(fitted, match.remaining)
                claimedFitted[typeID, default: 0] += fromFitted
                let got = take(typeID, at: staging.placeID, upTo: match.remaining - fromFitted)
                let here = fromFitted + got.personal + got.corporation
                match.atStaging += here
                match.fromCorporation += got.corporation
                match.remaining -= here
            }
            if match.remaining > 0 {
                let others = pools.places(holding: typeID)
                    .filter { $0 != staging?.placeID }
                    .sorted { jumpsTo($0, input: input) < jumpsTo($1, input: input) }
                for placeID in others where match.remaining > 0 {
                    let got = take(typeID, at: placeID, upTo: match.remaining)
                    if got.personal > 0 { match.elsewhere.append(.init(placeID: placeID, quantity: got.personal)) }
                    if got.corporation > 0 {
                        match.elsewhere.append(.init(placeID: placeID, quantity: got.corporation, isCorporation: true))
                    }
                    match.remaining -= got.personal + got.corporation
                    match.fromCorporation += got.corporation
                }
            }
            return before - match.remaining
        }

        // The exact parts for every line first, so a stand-in never takes stock another
        // line names; then owned stand-ins (Tech II for Tech I); then what's on its way.
        var matches: [Match] = []
        for line in demand {
            var match = Match(remaining: line.quantity)
            if line.category == hullCategory, staging?.hullItemID != nil {
                match.atStaging = 1
                match.remaining = 0
            } else {
                _ = claim(line.typeID, category: line.category, into: &match)
            }
            matches.append(match)
        }
        for (index, line) in demand.enumerated() where matches[index].remaining > 0 && !line.optional {
            for substitute in input.substitutes[line.typeID] ?? [] where matches[index].remaining > 0 {
                let used = claim(substitute, category: line.category, into: &matches[index])
                if used > 0 { matches[index].substitutes[substitute, default: 0] += used }
            }
        }
        for (index, line) in demand.enumerated() where matches[index].remaining > 0 && !line.optional {
            var skip = claimedIncoming[line.typeID, default: 0]
            for entry in incoming[line.typeID] ?? [] where matches[index].remaining > 0 {
                let available = max(entry.quantity - skip, 0)
                skip = max(skip - entry.quantity, 0)
                let use = min(available, matches[index].remaining)
                guard use > 0 else { continue }
                matches[index].arriving.append(.init(kind: entry.kind, quantity: use, placeID: entry.placeID, eta: entry.eta))
                claimedIncoming[line.typeID, default: 0] += use
                matches[index].remaining -= use
            }
        }

        var parts = zip(demand, matches).map { line, match in
            ReadyRoomPartLine(
                typeID: line.typeID,
                name: input.typeNames[line.typeID] ?? "Type #\(line.typeID)",
                category: line.category,
                required: line.quantity,
                atStaging: match.atStaging,
                elsewhere: match.elsewhere,
                incoming: match.arriving,
                missing: match.remaining,
                unitPrice: input.prices[line.typeID],
                fromCorporation: match.fromCorporation,
                isOptional: line.optional,
                substitutes: match.substitutes.sorted { $0.key < $1.key }.map {
                    .init(typeID: $0.key, name: input.typeNames[$0.key] ?? "Type #\($0.key)", quantity: $0.value)
                }
            )
        }
        if let hull = staging?.hullItemID {
            assignDisplaced(to: &parts, fitting: fitting, hullSlots: pools.fittedSlots(on: hull), typeNames: input.typeNames)
        }

        // Skills for the hull and every required module (cargo doesn't gate flying), then
        // whatever fitting skills the dogma check says the fit needs.
        var requiredSkills: [Int: Int] = [:]
        for typeID in Set(required.map(\.typeID)) {
            for (skill, level) in input.requirements[typeID] ?? [:] {
                requiredSkills[skill] = max(requiredSkills[skill] ?? 0, level)
            }
        }
        let check = input.fittingChecks[fitting.fittingId]
        var neededSkills = requiredSkills
        for (skill, level) in check?.skillsToFit ?? [:] {
            neededSkills[skill] = max(neededSkills[skill] ?? 0, level)
            for (prerequisite, prerequisiteLevel) in input.requirements[skill] ?? [:] {
                neededSkills[prerequisite] = max(neededSkills[prerequisite] ?? 0, prerequisiteLevel)
            }
        }
        let gaps = skillGaps(neededSkills, baseRequired: requiredSkills, skills: input.skills,
                             skillInfo: input.skillInfo, attributes: input.attributes,
                             queue: input.skillQueue, now: input.now)

        let stagingPlace = staging.flatMap { input.places[$0.placeID] }
        let isHere = staging != nil && staging?.placeID == input.currentPlaceID
        let requiredLines = parts.filter { !$0.isOptional }
        let tier: ReadyRoomTier
        if let check, !check.fitsWithTraining {
            tier = .blocked
        } else if !gaps.isEmpty {
            tier = .train
        } else if requiredLines.contains(where: { $0.missing > 0 }) {
            tier = .buy
        } else if requiredLines.contains(where: { !$0.incoming.isEmpty }) {
            tier = .waiting
        } else if !isHere || requiredLines.contains(where: { !$0.elsewhere.isEmpty }) {
            tier = .travel
        } else {
            tier = .ready
        }

        let unqueued = gaps.filter { !$0.isQueued && !$0.isOmegaLocked }
        let seconds: Double? = unqueued.contains { $0.seconds == nil } ? nil : unqueued.reduce(0) { $0 + ($1.seconds ?? 0) }

        return ReadyRoomReport(
            fittingID: fitting.fittingId,
            name: fitting.name,
            fittingDescription: fitting.description,
            shipTypeID: fitting.shipTypeId,
            shipTypeName: input.typeNames[fitting.shipTypeId] ?? "Ship #\(fitting.shipTypeId)",
            shipClassName: input.shipClassNames[fitting.shipTypeId] ?? "Unknown",
            tier: tier,
            skillGaps: gaps,
            trainingSeconds: seconds,
            queuedUntil: gaps.compactMap(\.queuedFinish).max(),
            requiredSkills: requiredSkills,
            fitting: check,
            parts: parts,
            staging: stagingPlace,
            stagingJumps: stagingPlace?.systemID.flatMap { input.jumps[$0] },
            isStagingCurrentLocation: isHere,
            stagedHullItemID: staging?.hullItemID,
            hasJumpCloneAtStaging: staging.map { input.jumpClonePlaceIDs.contains($0.placeID) } ?? false
        )
    }

    // MARK:  Displaced modules

    /// For each missing unit of a slot module, what the staged hull holds today in the slot
    /// it would take. Per slot group, the hull's modules the fit doesn't use are surplus; a
    /// missing unit replaces surplus in the slot the fit names, else other surplus in the
    /// group, else fills an empty slot.
    static func assignDisplaced(to parts: inout [ReadyRoomPartLine], fitting: ESIFitting,
                                hullSlots: [String: Int], typeNames: [Int: String]) {
        let fitByCategory = Dictionary(grouping: fitting.items.filter { isFittedFlag($0.flag) }) { slotCategory($0.flag) }
        for (category, fitItems) in fitByCategory {
            let missingLines = parts.indices.filter { parts[$0].category == category && parts[$0].missing > 0 }
            guard !missingLines.isEmpty else { continue }

            let fitSlots = Dictionary(fitItems.map { ($0.flag, $0.typeId) }, uniquingKeysWith: { first, _ in first })
            let hullFlags = hullSlots.keys.filter { slotCategory($0) == category }.sorted(by: flagOrder)
            // Keep the hull's modules the fit uses: same slot first, then anywhere in the group.
            var need: [Int: Int] = [:]
            for item in fitItems { need[item.typeId, default: 0] += item.quantity }
            for line in parts where line.category == category {
                for substitute in line.substitutes { need[substitute.typeID, default: 0] += substitute.quantity }
            }
            var kept = Set<String>()
            for flag in hullFlags where fitSlots[flag] == hullSlots[flag] {
                let type = hullSlots[flag]!
                if need[type, default: 0] > 0 { need[type]! -= 1; kept.insert(flag) }
            }
            for flag in hullFlags where !kept.contains(flag) {
                let type = hullSlots[flag]!
                if need[type, default: 0] > 0 { need[type]! -= 1; kept.insert(flag) }
            }
            var surplus = hullFlags.filter { !kept.contains($0) }
            var taken = Set<String>()

            func displaced(_ flag: String) -> ReadyRoomPartLine.Displaced {
                let type = hullSlots[flag]
                return .init(flag: flag, typeID: type, name: type.map { typeNames[$0] ?? "Type #\($0)" })
            }

            // The fit's own slots for each line's type that the hull doesn't fill with it.
            var ownFlags: [Int: [String]] = [:]
            var out: [Int: [ReadyRoomPartLine.Displaced]] = [:]
            for index in missingLines {
                ownFlags[index] = fitSlots.filter { $0.value == parts[index].typeID && hullSlots[$0.key] != parts[index].typeID }
                    .map(\.key).sorted(by: flagOrder)
            }
            func wants(_ index: Int) -> Bool { out[index, default: []].count < parts[index].missing }
            func take(_ flag: String, for index: Int) {
                surplus.removeAll { $0 == flag }
                taken.insert(flag)
                out[index, default: []].append(displaced(flag))
            }
            // Every line's surplus in its own slots first, then surplus anywhere in the
            // group (a stand-in), then its slots left empty.
            for index in missingLines {
                for flag in ownFlags[index]! where wants(index) && surplus.contains(flag) { take(flag, for: index) }
            }
            for index in missingLines {
                while wants(index), let flag = surplus.first { take(flag, for: index) }
            }
            for index in missingLines {
                for flag in ownFlags[index]! where wants(index) && hullSlots[flag] == nil && !taken.contains(flag) {
                    take(flag, for: index)
                }
                while wants(index) {
                    out[index, default: []].append(.init(flag: ownFlags[index]!.first ?? category, typeID: nil, name: nil))
                }
                parts[index].displaced = out[index] ?? []
            }
        }
    }

    /// "HiSlot2" before "HiSlot10".
    private static func flagOrder(_ a: String, _ b: String) -> Bool {
        a.localizedStandardCompare(b) == .orderedAscending
    }

    // MARK:  Staging

    private struct Staging {
        let placeID: Int
        let hullItemID: Int?
        /// Modules fitted to `hullItemID`, by type.
        let fittedCounts: [Int: Int]
    }

    private static func chooseStaging(fitting: ESIFitting, needByType: [Int: Int], input: ReadyRoomInput, pools: Pools) -> Staging? {
        var candidates = Set(pools.places(holding: fitting.shipTypeId))
        for typeID in needByType.keys { candidates.formUnion(pools.places(holding: typeID)) }
        guard !candidates.isEmpty else { return nil }

        // Value weights: market price where known, so a 200M hull outweighs a 1M module.
        // A flat weight otherwise keeps the comparison meaningful before prices arrive.
        func weight(_ typeID: Int) -> Double { max(input.prices[typeID] ?? 1, 1) }
        let hullWeight = max(input.prices[fitting.shipTypeId] ?? 10, 10)

        var best: (staging: Staging, score: Double)?
        for placeID in candidates {
            // The best assembled hull here is the one whose fitted modules overlap the fit most.
            var hullID: Int?
            var fitted: [Int: Int] = [:]
            var bestOverlap = -1.0
            for hull in pools.hulls(of: fitting.shipTypeId, at: placeID) {
                let counts = pools.fittedCounts(on: hull)
                let overlap = needByType.reduce(0.0) { $0 + Double(min($1.value, counts[$1.key] ?? 0)) * weight($1.key) }
                if overlap > bestOverlap {
                    bestOverlap = overlap
                    hullID = hull
                    fitted = counts
                }
            }
            let hasHull = hullID != nil || pools.quantity(of: fitting.shipTypeId, at: placeID) > 0

            var score = hasHull ? hullWeight : 0
            for (typeID, need) in needByType {
                let available = (fitted[typeID] ?? 0) + pools.quantity(of: typeID, at: placeID)
                score += Double(min(need, available)) * weight(typeID)
            }

            let staging = Staging(placeID: placeID, hullItemID: hullID, fittedCounts: fitted)
            if let current = best {
                if score > current.score || (score == current.score && prefers(placeID, over: current.staging.placeID, input: input)) {
                    best = (staging, score)
                }
            } else {
                best = (staging, score)
            }
        }
        return best?.staging
    }

    /// Tie-break: the pilot's own location, then the nearer place, then a stable order.
    private static func prefers(_ a: Int, over b: Int, input: ReadyRoomInput) -> Bool {
        if a == input.currentPlaceID { return true }
        if b == input.currentPlaceID { return false }
        let ja = jumpsTo(a, input: input), jb = jumpsTo(b, input: input)
        return ja != jb ? ja < jb : a < b
    }

    private static func jumpsTo(_ placeID: Int, input: ReadyRoomInput) -> Int {
        input.places[placeID]?.systemID.flatMap { input.jumps[$0] } ?? .max
    }

    // MARK:  Skills

    /// The skills (of `needed`) a pilot is short of, in training order — prerequisites
    /// first. Public so other pilots can be measured against a fit's requirements.
    static func skillGaps(
        _ needed: [Int: Int],
        baseRequired: [Int: Int]? = nil,
        skills: [Int: ReadyRoomSkillLevel],
        skillInfo: [Int: SkillTrainingInfo],
        attributes: ESICharacterAttributes?,
        queue: [ESISkillQueue],
        now: Date = .now
    ) -> [ReadyRoomSkillGap] {
        let queued = QueueIndex(queue)
        var gaps: [ReadyRoomSkillGap] = []
        for (skillID, level) in needed {
            let have = skills[skillID] ?? ReadyRoomSkillLevel(active: 0, trained: 0, sp: 0)
            guard have.active < level else { continue }
            let info = skillInfo[skillID]
            let omegaLocked = have.trained >= level

            var sp = 0
            var seconds: Double?
            if !omegaLocked, let info {
                sp = SkillTraining.spNeeded(toLevel: level, trainedLevel: have.trained, spInSkill: have.sp, rank: info.rank)
                if let attributes {
                    let rate = SkillTraining.spPerMinute(primary: info.primaryAttribute, secondary: info.secondaryAttribute, attributes: attributes)
                    if rate > 0 { seconds = Double(sp) / rate * 60 }
                }
            }

            gaps.append(ReadyRoomSkillGap(
                skillID: skillID,
                name: info?.name ?? "Skill #\(skillID)",
                trainedLevel: have.active,
                requiredLevel: level,
                sp: sp,
                seconds: seconds,
                queuedFinish: omegaLocked ? nil : queued.finish(skillID: skillID, level: level),
                depth: info?.depth ?? 0,
                isOmegaLocked: omegaLocked,
                isForFitting: baseRequired.map { ($0[skillID] ?? 0) < level } ?? false
            ))
        }
        return gaps.sorted {
            $0.depth != $1.depth ? $0.depth < $1.depth
                : $0.name.localizedStandardCompare($1.name) == .orderedAscending
        }
    }

    private struct QueueIndex {
        /// Skill → entries (level, finish), as queued.
        let entries: [Int: [(level: Int, finish: Date?)]]

        init(_ queue: [ESISkillQueue]) {
            entries = Dictionary(grouping: queue, by: \.skillId)
                .mapValues { $0.map { (level: $0.finishedLevel, finish: $0.finishDate) } }
        }

        /// When the queue brings `skillID` to `level`. A paused queue has no finish dates;
        /// that still counts as queued, landing at an unknown time (`.distantFuture`).
        func finish(skillID: Int, level: Int) -> Date? {
            guard let reaching = entries[skillID]?.filter({ $0.level >= level }).min(by: { $0.level < $1.level }) else {
                return nil
            }
            return reaching.finish ?? .distantFuture
        }
    }

    // MARK:  Holdings

    /// Reduces the raw asset list to holdings with resolved places. The piloted ship is
    /// added when ESI omits it (it does while the pilot is in space), so its fitted
    /// modules — which ESI still lists inside it — resolve to the pilot's location.
    static func holdings(from assets: [ESIAsset], pilotedShip: ESICharacterShip?, pilotPlaceID: Int?,
                         isCorporation: Bool = false) -> [ReadyRoomHolding] {
        var assets = assets
        if let ship = pilotedShip, let pilotPlaceID, !assets.contains(where: { $0.itemId == ship.shipItemId }) {
            assets.append(ESIAsset(
                isBlueprintCopy: nil, isSingleton: true, itemId: ship.shipItemId, locationFlag: "Hangar",
                locationId: pilotPlaceID, locationType: "other", quantity: 1, typeId: ship.shipTypeId
            ))
        }
        let byID = Dictionary(assets.map { ($0.itemId, $0) }, uniquingKeysWith: { first, _ in first })
        let roots = RootResolver(byID: byID)

        return assets.map { asset in
            let parentIsItem = byID[asset.locationId] != nil
            return ReadyRoomHolding(
                itemID: asset.itemId,
                typeID: asset.typeId,
                quantity: asset.quantity,
                placeID: roots.root(of: asset.locationId),
                fittedToItemID: parentIsItem && isFittedFlag(asset.locationFlag) ? asset.locationId : nil,
                isAssembled: asset.isSingleton,
                isCorporation: isCorporation,
                slotFlag: parentIsItem && isFittedFlag(asset.locationFlag) ? asset.locationFlag : nil
            )
        }
    }

    /// Follows a location ID up through the item tree (hangar → ship → container) to the
    /// station, structure or system at its top.
    struct RootResolver {
        let byID: [Int: ESIAsset]

        func root(of locationID: Int) -> Int {
            var location = locationID
            var hops = 0
            while let parent = byID[location], hops < 16 {
                location = parent.locationId
                hops += 1
            }
            return location
        }
    }

    private struct Pools {
        /// place → type → loose quantity (not fitted to any ship), personal and corporation.
        let personal: [Int: [Int: Int]]
        let corporation: [Int: [Int: Int]]
        /// type → places with loose stock of it.
        let placesByType: [Int: Set<Int>]
        /// place → type → assembled hulls (the pilot's own).
        let hullsByPlace: [Int: [Int: [Int]]]
        /// hull item → fitted module counts by type.
        let fittedByHull: [Int: [Int: Int]]
        /// hull item → slot flag → module type. A loaded charge shares its module's flag;
        /// the module is the assembled one.
        let slotsByHull: [Int: [String: Int]]

        init(holdings: [ReadyRoomHolding]) {
            var personal: [Int: [Int: Int]] = [:]
            var corporation: [Int: [Int: Int]] = [:]
            var places: [Int: Set<Int>] = [:]
            var hulls: [Int: [Int: [Int]]] = [:]
            var fitted: [Int: [Int: Int]] = [:]
            var slots: [Int: [String: Int]] = [:]
            for holding in holdings {
                if let hull = holding.fittedToItemID {
                    fitted[hull, default: [:]][holding.typeID, default: 0] += holding.quantity
                    if let flag = holding.slotFlag, holding.isAssembled || slots[hull]?[flag] == nil {
                        slots[hull, default: [:]][flag] = holding.typeID
                    }
                    continue
                }
                if holding.isCorporation {
                    corporation[holding.placeID, default: [:]][holding.typeID, default: 0] += holding.quantity
                } else {
                    personal[holding.placeID, default: [:]][holding.typeID, default: 0] += holding.quantity
                    if holding.isAssembled, holding.quantity == 1 {
                        hulls[holding.placeID, default: [:]][holding.typeID, default: []].append(holding.itemID)
                    }
                }
                places[holding.typeID, default: []].insert(holding.placeID)
            }
            self.personal = personal
            self.corporation = corporation
            self.placesByType = places
            self.hullsByPlace = hulls
            self.fittedByHull = fitted
            self.slotsByHull = slots
        }

        func places(holding typeID: Int) -> [Int] { Array(placesByType[typeID] ?? []) }

        func hulls(of typeID: Int, at placeID: Int) -> [Int] { hullsByPlace[placeID]?[typeID] ?? [] }

        func fittedCounts(on hullID: Int) -> [Int: Int] { fittedByHull[hullID] ?? [:] }

        func fittedSlots(on hullID: Int) -> [String: Int] { slotsByHull[hullID] ?? [:] }

        /// Stock of `typeID` at a place that isn't fitted to a ship (hangars, containers,
        /// cargo holds and drone bays all count). `corporation` nil = both.
        func quantity(of typeID: Int, at placeID: Int, corporation corp: Bool? = nil) -> Int {
            let own = personal[placeID]?[typeID] ?? 0
            let shared = corporation[placeID]?[typeID] ?? 0
            switch corp {
            case .none:        return own + shared
            case .some(false): return own
            case .some(true):  return shared
            }
        }
    }

    // MARK:  Jumps

    /// Stargate jumps from `origin` to every reachable system (breadth-first search over
    /// the whole graph — one pass answers every destination).
    static func jumpDistances(from origin: Int, links: [(Int, Int)]) -> [Int: Int] {
        jumpDistances(from: origin, adjacency: adjacency(links))
    }

    static func adjacency(_ links: [(Int, Int)]) -> [Int: [Int]] {
        var adjacency: [Int: [Int]] = [:]
        for (a, b) in links {
            adjacency[a, default: []].append(b)
            adjacency[b, default: []].append(a)
        }
        return adjacency
    }

    static func jumpDistances(from origin: Int, adjacency: [Int: [Int]]) -> [Int: Int] {
        var distance: [Int: Int] = [origin: 0]
        var frontier = [origin]
        while !frontier.isEmpty {
            var next: [Int] = []
            for system in frontier {
                let d = distance[system]! + 1
                for neighbor in adjacency[system] ?? [] where distance[neighbor] == nil {
                    distance[neighbor] = d
                    next.append(neighbor)
                }
            }
            frontier = next
        }
        return distance
    }

    /// A short pickup tour: from `origin`, always the nearest unvisited stop next, ending
    /// at `destination` (the staging system). Returns the stops in order with the jumps
    /// for each leg; nil legs are unreachable by gate.
    static func collectionRoute(origin: Int, stops: [Int], destination: Int?,
                                adjacency: [Int: [Int]]) -> [(systemID: Int, jumps: Int?)] {
        var remaining = Array(Set(stops).subtracting([destination].compactMap { $0 }))
        var route: [(Int, Int?)] = []
        var position = origin
        while !remaining.isEmpty {
            let distances = jumpDistances(from: position, adjacency: adjacency)
            remaining.sort { (distances[$0] ?? .max, $0) < (distances[$1] ?? .max, $1) }
            let next = remaining.removeFirst()
            route.append((next, distances[next]))
            position = next
        }
        if let destination {
            route.append((destination, jumpDistances(from: position, adjacency: adjacency)[destination]))
        }
        return route
    }

    // MARK:  Flags

    static func isFittedFlag(_ flag: String) -> Bool {
        flag.hasPrefix("HiSlot") || flag.hasPrefix("MedSlot") || flag.hasPrefix("LoSlot")
            || flag.hasPrefix("RigSlot") || flag.hasPrefix("SubSystem") || flag.hasPrefix("ServiceSlot")
    }

    /// The same slot groups (and labels) as the Fittings screen.
    static func slotCategory(_ flag: String) -> String {
        if flag.hasPrefix("HiSlot") { return "High Slots" }
        if flag.hasPrefix("MedSlot") { return "Med Slots" }
        if flag.hasPrefix("LoSlot") { return "Low Slots" }
        if flag.hasPrefix("RigSlot") { return "Rig Slots" }
        if flag.hasPrefix("SubSystem") { return "Subsystems" }
        if flag.hasPrefix("ServiceSlot") { return "Service Slots" }
        if flag == "DroneBay" { return "Drone Bay" }
        if flag == "FighterBay" { return "Fighter Bay" }
        return "Cargo"
    }
}
