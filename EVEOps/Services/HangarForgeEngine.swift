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

/// What "most powerful" means for a Hangar Forge build. Every goal scores a fit as a
/// weighted sum of log-scaled damage, defense and speed: logs make each one a ratio, so
/// doubling DPS is worth the same on a frigate as on a battleship, and no stat gets traded
/// all the way down to zero for a little more of another.
nonisolated enum HangarForgeGoal: String, CaseIterable, Sendable, Identifiable {
    case balanced, damage, tank, kite

    var id: String { rawValue }

    var title: String {
        switch self {
        case .balanced: String(localized: "Balanced")
        case .damage:   String(localized: "Damage")
        case .tank:     String(localized: "Tank")
        case .kite:     String(localized: "Kite")
        }
    }

    var weights: (damage: Double, defense: Double, speed: Double) {
        switch self {
        case .balanced: (1, 1, 0)
        case .damage:   (1, 0.25, 0)
        case .tank:     (0.25, 1, 0)
        case .kite:     (0.5, 0.25, 1)
        }
    }

    /// A kiting fit that runs its capacitor dry stops kiting, so it's never optional there.
    var requiresCapStable: Bool { self == .kite }
}

nonisolated struct HangarForgeOptions: Sendable, Hashable {
    var goal: HangarForgeGoal = .balanced
    var requireCapStable = false
    /// Use parts from every station, not just the one the hull is in.
    var anywhere = false
    /// Strip modules fitted to the pilot's other ships.
    var includeFittedElsewhere = false
    var includeCorporation = false
    /// Dogma calculations to spend on the search, all seeds together.
    var evaluationBudget = 20_000

    var capStableRequired: Bool { requireCapStable || goal.requiresCapStable }
}

/// A ship the pilot owns, as a starting point for a build.
nonisolated struct HangarForgeHull: Sendable, Hashable, Identifiable {
    let itemID: Int
    let typeID: Int
    let placeID: Int
    let isAssembled: Bool
    let isCorporation: Bool
    /// Skill → level still to train before the pilot can fly it; empty when flyable.
    let missingSkills: [Int: Int]
    /// False for Strategic Cruisers: their slots come from subsystems, which the forge
    /// doesn't choose.
    let isSupported: Bool

    var id: Int { itemID }
    var isFlyable: Bool { missingSkills.isEmpty }
}

/// One stack the forge may take a part from.
nonisolated struct HangarForgeSource: Sendable, Hashable {
    let placeID: Int
    let quantity: Int
    /// Set when the part is fitted to a ship — the hull being built, or another one.
    let fittedToItemID: Int?
    let isCorporation: Bool
}

nonisolated struct HangarForgeInput: Sendable {
    var hull: HangarForgeHull
    var holdings: [ReadyRoomHolding]
    /// The hull and every type in the holdings that could go on it.
    var types: [Int: ESIType]
    /// Type → skill → level, for the hull and every module, charge and drone. A type
    /// missing here is treated as unusable.
    var requirements: [Int: [Int: Int]]
    /// Active skill levels (what an Alpha clone can actually use).
    var skills: [Int: Int]
    var implants: [Int]
}

/// One filled slot in a forged fit.
nonisolated struct HangarForgePick: Sendable, Hashable, Identifiable {
    let flag: String
    let category: SimSlotCategory
    let typeID: Int
    let chargeTypeID: Int?
    /// The fit with one of this module taken out — what it's worth.
    let without: FitPerformance?

    var id: String { flag }
}

nonisolated struct HangarForgeResult: Sendable {
    let hull: HangarForgeHull
    let options: HangarForgeOptions
    let fit: DogmaFit
    let stats: SimStats
    let performance: FitPerformance
    let picks: [HangarForgePick]
    let drones: [Int]
    /// The fit with no drones launched, when it launches some.
    let withoutDrones: FitPerformance?
    /// Slots left empty because nothing owned improves the fit there.
    let openSlots: [SimSlotCategory: Int]
    /// Type → units the fit uses: one per module and drone, and every in-scope unit of a
    /// charge it loads (ammo is brought by the stack).
    let needs: [Int: Int]
    /// Where each needed type can be taken from.
    let sources: [Int: [HangarForgeSource]]
    let evaluations: Int
    /// True when the search stopped on its budget rather than running out of improvements.
    let hitBudget: Bool
}

nonisolated enum HangarForgeFailure: Error, Equatable, LocalizedError {
    case unknownHull
    case notFlyable
    case subsystemsUnsupported
    case engineUnavailable

    var errorDescription: String? {
        switch self {
        case .unknownHull:           String(localized: "This hull's details couldn't be loaded.")
        case .notFlyable:            String(localized: "You can't fly this hull yet.")
        case .subsystemsUnsupported: String(localized: "Strategic Cruisers aren't supported yet.")
        case .engineUnavailable:     String(localized: "The fitting engine isn't loaded.")
        }
    }
}

// MARK:  Engine

nonisolated enum HangarForgeEngine {
    typealias Evaluator = @Sendable (DogmaFit) -> SimStats
    typealias Progress = @Sendable (_ done: Int, _ budget: Int) -> Void

    // Dogma attributes and effects (verified against the SDE).
    static let hiSlotsAttribute = 14
    static let medSlotsAttribute = 13
    static let lowSlotsAttribute = 12
    static let rigSlotsAttribute = 1137
    static let turretSlotsAttribute = 102
    static let launcherSlotsAttribute = 101
    static let rigSizeAttribute = 1547
    static let maxSubSystemsAttribute = 1367
    static let droneCapacityAttribute = 283
    static let maxGroupFittedAttribute = 1544
    static let maxTypeFittedAttribute = 2431
    static let capacitorNeedAttribute = 6
    static let turretFittedEffect = 42
    static let launcherFittedEffect = 40
    static let canFitShipGroupAttributes = [1298, 1299, 1300, 1301, 1872, 1879, 1880, 1881, 2065, 2396,
                                            2476, 2477, 2478, 2479, 2480, 2481, 2482, 2483, 2484, 2485]
    static let canFitShipTypeAttributes = [1302, 1303, 1304, 1305, 1944, 2103, 2463, 2486, 2487, 2488, 2758, 5948]

    /// Seconds of fighting that repairs count for in a fit's defense.
    static let repairWindow: Double = 60
    /// Best weapon racks carried into the full search.
    static let weaponSeeds = 2

    // MARK: Hulls

    /// Every ship the pilot owns as a build candidate, packaged or assembled. The service
    /// loads requirements for every hull, so an unknown one counts as flyable.
    static func hulls(holdings: [ReadyRoomHolding], types: [Int: ESIType], shipGroupIDs: Set<Int>,
                      requirements: [Int: [Int: Int]], skills: [Int: Int]) -> [HangarForgeHull] {
        holdings.compactMap { holding in
            guard holding.fittedToItemID == nil, let type = types[holding.typeID],
                  shipGroupIDs.contains(type.groupId) else { return nil }
            let missing = (requirements[holding.typeID] ?? [:]).filter { skills[$0.key, default: 0] < $0.value }
            return HangarForgeHull(
                itemID: holding.itemID, typeID: holding.typeID, placeID: holding.placeID,
                isAssembled: holding.isAssembled, isCorporation: holding.isCorporation,
                missingSkills: missing,
                isSupported: (type.attribute(maxSubSystemsAttribute) ?? 0) == 0
            )
        }
    }

    // MARK: Stock

    /// Type → stacks the forge may use for `hull`. Whatever is fitted to the hull itself is
    /// always in; other stock depends on the options.
    static func stock(for hull: HangarForgeHull, holdings: [ReadyRoomHolding],
                      options: HangarForgeOptions) -> [Int: [HangarForgeSource]] {
        var out: [Int: [HangarForgeSource]] = [:]
        for holding in holdings where holding.itemID != hull.itemID {
            if holding.fittedToItemID != hull.itemID {
                if holding.fittedToItemID != nil && !options.includeFittedElsewhere { continue }
                if holding.isCorporation && !options.includeCorporation { continue }
                if !options.anywhere && holding.placeID != hull.placeID { continue }
            }
            out[holding.typeID, default: []].append(HangarForgeSource(
                placeID: holding.placeID, quantity: holding.quantity,
                fittedToItemID: holding.fittedToItemID, isCorporation: holding.isCorporation
            ))
        }
        return out
    }

    // MARK: Score

    /// How good a fit is for `goal`; nil when it can't be flown as calculated — over CPU,
    /// powergrid or calibration, or not cap stable when that's required.
    static func score(_ stats: SimStats, options: HangarForgeOptions) -> Double? {
        guard stats.hasData,
              stats.cpuUsed <= stats.cpuTotal + 0.05,
              stats.powerUsed <= stats.powerTotal + 0.05,
              stats.calibrationUsed <= stats.calibrationTotal + 0.05 else { return nil }
        if options.capStableRequired && !stats.isCapStable { return nil }
        let weights = options.goal.weights
        return weights.damage * log1p(max(stats.dps, 0))
            + weights.defense * log1p(defense(stats))
            + weights.speed * log1p(max(stats.maxVelocity, 0))
    }

    /// Average EHP, plus what repairs put back over `repairWindow` — active repairs only
    /// until the capacitor runs out, if that's sooner.
    static func defense(_ stats: SimStats) -> Double {
        let ehp = FitPerformance(stats).ehp
        let active = stats.shieldBoostRate + stats.armorRepairRate + stats.hullRepairRate
        let activeSeconds = min(repairWindow, stats.capDepletesIn ?? repairWindow)
        return ehp + stats.passiveShieldRate * repairWindow + active * activeSeconds
    }

    /// The stat to label a module or drone with: the one whose loss costs the goal's score
    /// most when it's taken out, not just the biggest percentage (a small passive regen
    /// can triple while EHP is what the module is for). Defense is shown as EHP or repair,
    /// whichever added more hit points over `repairWindow`. Nil when the goal doesn't
    /// value anything it adds.
    static func headline(without: FitPerformance, with: FitPerformance, goal: HangarForgeGoal) -> FitStatDelta.Stat? {
        let weights = goal.weights
        func defense(_ p: FitPerformance) -> Double { p.ehp + p.tank * repairWindow }
        func change(_ before: Double, _ after: Double) -> Double { log1p(max(after, 0)) - log1p(max(before, 0)) }
        let contributions: [(stat: FitStatDelta.Stat, value: Double)] = [
            (.dps, weights.damage * change(without.dps, with.dps)),
            (.ehp, weights.defense * change(defense(without), defense(with))),
            (.speed, weights.speed * change(without.speed, with.speed)),
        ]
        guard let top = contributions.max(by: { $0.value < $1.value }), top.value > 1e-9 else { return nil }
        guard top.stat == .ehp else { return top.stat }
        return (with.tank - without.tank) * repairWindow > with.ehp - without.ehp ? .tank : .ehp
    }

    // MARK: Build

    /// The best fit for the hull from owned parts. Call off the main actor: it runs
    /// thousands of dogma calculations (in parallel, through `evaluate`).
    static func build(_ input: HangarForgeInput, options: HangarForgeOptions,
                      evaluate: @escaping Evaluator, progress: Progress? = nil) async throws -> HangarForgeResult {
        guard let hullType = input.types[input.hull.typeID] else { throw HangarForgeFailure.unknownHull }
        guard input.hull.isSupported else { throw HangarForgeFailure.subsystemsUnsupported }
        guard input.hull.isFlyable else { throw HangarForgeFailure.notFlyable }

        let stock = stock(for: input.hull, holdings: input.holdings, options: options)
        let shop = Workshop(input: input, hullType: hullType, stock: stock, options: options,
                            evaluate: evaluate, progress: progress)
        try await shop.probe()

        let seeds = try await shop.weaponSeeds()
        let bans = shop.layerBans()
        let runs = seeds.flatMap { seed in bans.map { (seed, $0) } }

        var best: (loadout: ForgeLoadout, score: Double)?
        for (index, (seed, banned)) in runs.enumerated() {
            shop.limit = shop.evaluations + (options.evaluationBudget - shop.evaluations) / (runs.count - index)
            let loadout = try await shop.forge(from: seed, banned: banned)
            let score = try await shop.score(loadout)
            if let score, score > best?.score ?? -.infinity { best = (loadout, score) }
        }
        return try await shop.result(for: best?.loadout ?? ForgeLoadout(), stock: stock)
    }
}

// MARK:  Search State

/// A fit as the search sees it: module types per slot category (sorted, so equal fits are
/// equal values), the charge each module type loads, and the drones in space.
private nonisolated struct ForgeLoadout: Hashable, Sendable {
    var modules: [SimSlotCategory: [Int]] = [:]
    var charges: [Int: Int] = [:]
    var drones: [Int] = []

    func filled(_ category: SimSlotCategory) -> Int { modules[category]?.count ?? 0 }
    func count(of typeID: Int) -> Int { allModules.filter { $0 == typeID }.count }
    var allModules: [Int] { SimSlotCategory.allCases.flatMap { modules[$0] ?? [] } }

    func adding(_ typeID: Int, to category: SimSlotCategory) -> ForgeLoadout {
        var copy = self
        copy.modules[category, default: []].append(typeID)
        copy.modules[category]?.sort()
        return copy
    }

    func removing(_ typeID: Int, from category: SimSlotCategory) -> ForgeLoadout {
        var copy = self
        guard let index = copy.modules[category]?.firstIndex(of: typeID) else { return self }
        copy.modules[category]?.remove(at: index)
        if copy.modules[category]?.isEmpty == true { copy.modules[category] = nil }
        if copy.count(of: typeID) == 0 { copy.charges[typeID] = nil }
        return copy
    }
}

private nonisolated enum Hardpoint: Hashable { case turret, launcher }

/// Which defense layer a module builds up. Each search seed sticks to one, so fits don't
/// end up half shield, half armor.
private nonisolated enum Layer { case shield, armor, neutral }

/// An owned module that can go on the hull.
private nonisolated struct Part {
    let typeID: Int
    let category: SimSlotCategory
    let groupID: Int
    let hardpoint: Hardpoint?
    let available: Int
    let maxGroupFitted: Int?
    let maxTypeFitted: Int?
    /// Owned charges it accepts that the pilot can use, most plentiful first.
    let charges: [Int]
}

// MARK:  Workshop

/// One build's search: the hull's limits, the parts on hand, and a cache of every fit
/// calculated so far.
private nonisolated final class Workshop {
    let input: HangarForgeInput
    let hullType: ESIType
    let options: HangarForgeOptions
    let evaluate: HangarForgeEngine.Evaluator
    let progress: HangarForgeEngine.Progress?

    let slotCounts: [SimSlotCategory: Int]
    let hardpoints: [Hardpoint: Int]
    let parts: [Int: Part]
    let partsByCategory: [SimSlotCategory: [Part]]
    let groupLimits: [Int: Int]
    let chargeStock: [Int: Int]
    let droneStock: [Int: Int]
    let droneBandwidth: Double
    let droneBay: Double
    let passive: Set<Int>

    var limit: Int
    var evaluations = 0
    var hitBudget = false
    var cache: [ForgeLoadout: SimStats] = [:]
    var layers: [Int: Layer] = [:]
    var enablers: Set<Int> = []

    init(input: HangarForgeInput, hullType: ESIType, stock: [Int: [HangarForgeSource]],
         options: HangarForgeOptions, evaluate: @escaping HangarForgeEngine.Evaluator,
         progress: HangarForgeEngine.Progress?) {
        self.input = input
        self.hullType = hullType
        self.options = options
        self.evaluate = evaluate
        self.progress = progress
        limit = options.evaluationBudget

        func int(_ attribute: Int) -> Int { Int(hullType.attribute(attribute) ?? 0) }
        slotCounts = [
            .high: int(HangarForgeEngine.hiSlotsAttribute), .medium: int(HangarForgeEngine.medSlotsAttribute),
            .low: int(HangarForgeEngine.lowSlotsAttribute), .rig: int(HangarForgeEngine.rigSlotsAttribute),
        ]
        hardpoints = [.turret: int(HangarForgeEngine.turretSlotsAttribute),
                      .launcher: int(HangarForgeEngine.launcherSlotsAttribute)]

        let types = input.types
        func usable(_ typeID: Int) -> Bool {
            guard let needs = input.requirements[typeID] else { return false }
            return needs.allSatisfy { input.skills[$0.key, default: 0] >= $0.value }
        }
        let quantities = stock.mapValues { $0.reduce(0) { $0 + $1.quantity } }

        var parts: [Int: Part] = [:]
        var moduleChargeGroups: [Int: (groups: Set<Int>, size: Double?)] = [:]
        for (typeID, quantity) in quantities {
            guard let type = types[typeID], let effects = type.dogmaEffects,
                  let category = SimSlotEffect.category(from: effects), category != .subsystem,
                  (slotCounts[category] ?? 0) > 0, usable(typeID), Self.fits(type, on: hullType) else { continue }
            let effectIDs = Set(effects.map(\.effectId))
            let hardpoint: Hardpoint? = effectIDs.contains(HangarForgeEngine.turretFittedEffect) ? .turret
                : effectIDs.contains(HangarForgeEngine.launcherFittedEffect) ? .launcher : nil
            if let hardpoint, (hardpoints[hardpoint] ?? 0) == 0 { continue }
            if category == .rig,
               type.attribute(HangarForgeEngine.rigSizeAttribute) != hullType.attribute(HangarForgeEngine.rigSizeAttribute) { continue }
            moduleChargeGroups[typeID] = (
                Set(DogmaLoadout.chargeGroupAttributes.compactMap { type.attribute($0) }.map { Int($0) }.filter { $0 > 0 }),
                type.attribute(DogmaLoadout.chargeSizeAttribute)
            )
            parts[typeID] = Part(
                typeID: typeID, category: category, groupID: type.groupId, hardpoint: hardpoint, available: quantity,
                maxGroupFitted: type.attribute(HangarForgeEngine.maxGroupFittedAttribute).map { Int($0) },
                maxTypeFitted: type.attribute(HangarForgeEngine.maxTypeFittedAttribute).map { Int($0) },
                charges: []
            )
        }

        // Charges: owned, usable, and accepted by at least one part.
        var chargeStock: [Int: Int] = [:]
        for (typeID, part) in parts {
            guard let accepts = moduleChargeGroups[typeID], !accepts.groups.isEmpty else { continue }
            let charges = quantities.keys.filter { chargeID in
                guard parts[chargeID] == nil, let charge = types[chargeID], accepts.groups.contains(charge.groupId),
                      usable(chargeID) else { return false }
                guard let size = accepts.size else { return true }
                return charge.attribute(DogmaLoadout.chargeSizeAttribute) == size
            }.sorted { a, b in
                let (qa, qb) = (quantities[a] ?? 0, quantities[b] ?? 0)
                return qa != qb ? qa > qb : a < b
            }
            for charge in charges { chargeStock[charge] = quantities[charge] }
            parts[typeID] = Part(typeID: part.typeID, category: part.category, groupID: part.groupID,
                                 hardpoint: part.hardpoint, available: part.available,
                                 maxGroupFitted: part.maxGroupFitted, maxTypeFitted: part.maxTypeFitted,
                                 charges: charges)
        }
        self.parts = parts
        self.chargeStock = chargeStock
        partsByCategory = Dictionary(grouping: parts.values.sorted { $0.typeID < $1.typeID }, by: \.category)
        groupLimits = parts.values.reduce(into: [:]) { limits, part in
            guard let max = part.maxGroupFitted, max > 0 else { return }
            limits[part.groupID] = min(limits[part.groupID] ?? max, max)
        }
        passive = Set(parts.keys.filter { (types[$0]?.attribute(HangarForgeEngine.capacitorNeedAttribute) ?? 0) == 0 })

        droneBandwidth = hullType.attribute(DogmaLoadout.droneBandwidthAttribute) ?? 0
        droneBay = hullType.attribute(HangarForgeEngine.droneCapacityAttribute) ?? 0
        droneStock = quantities.filter { typeID, _ in
            parts[typeID] == nil && usable(typeID)
                && (types[typeID]?.attribute(DogmaLoadout.droneBandwidthUsedAttribute) ?? 0) > 0
        }
    }

    /// The module's own fitting restrictions allow this hull.
    static func fits(_ module: ESIType, on hull: ESIType) -> Bool {
        let groups = HangarForgeEngine.canFitShipGroupAttributes.compactMap { module.attribute($0) }.map { Int($0) }
        let ships = HangarForgeEngine.canFitShipTypeAttributes.compactMap { module.attribute($0) }.map { Int($0) }
        if groups.isEmpty && ships.isEmpty { return true }
        return groups.contains(hull.groupId) || ships.contains(hull.typeId)
    }

    // MARK: Rules

    /// Slots, hardpoints, owned quantities and group/type limits — everything dogma doesn't
    /// check. CPU, powergrid and calibration are left to the score.
    func allows(_ loadout: ForgeLoadout) -> Bool {
        var turrets = 0, launchers = 0
        var byType: [Int: Int] = [:]
        var byGroup: [Int: Int] = [:]
        for (category, modules) in loadout.modules {
            guard modules.count <= slotCounts[category] ?? 0 else { return false }
            for typeID in modules {
                guard let part = parts[typeID] else { return false }
                byType[typeID, default: 0] += 1
                byGroup[part.groupID, default: 0] += 1
                if part.hardpoint == .turret { turrets += 1 }
                if part.hardpoint == .launcher { launchers += 1 }
            }
        }
        guard turrets <= hardpoints[.turret] ?? 0, launchers <= hardpoints[.launcher] ?? 0 else { return false }
        for (typeID, count) in byType {
            guard let part = parts[typeID], count <= part.available else { return false }
            if let max = part.maxTypeFitted, max > 0, count > max { return false }
        }
        for (groupID, count) in byGroup {
            if let max = groupLimits[groupID], count > max { return false }
        }
        var chargeUse: [Int: Int] = [:]
        for (moduleID, chargeID) in loadout.charges { chargeUse[chargeID, default: 0] += byType[moduleID] ?? 0 }
        return chargeUse.allSatisfy { $0.value <= chargeStock[$0.key] ?? 0 }
    }

    /// `loadout` with one more `typeID`, loading a charge it has enough of; nil when the
    /// rules don't allow it.
    func add(_ typeID: Int, to loadout: ForgeLoadout) -> ForgeLoadout? {
        guard let part = parts[typeID], loadout.filled(part.category) < slotCounts[part.category] ?? 0 else { return nil }
        var next = loadout.adding(typeID, to: part.category)
        let count = next.count(of: typeID)
        if next.charges[typeID].map({ chargeStock[$0] ?? 0 < count }) ?? true {
            next.charges[typeID] = part.charges.first { chargeStock[$0] ?? 0 >= count }
        }
        return allows(next) ? next : nil
    }

    func dogmaFit(_ loadout: ForgeLoadout) -> DogmaFit {
        var slots: [SimSlot] = []
        for category in SimSlotCategory.allCases {
            for (index, typeID) in (loadout.modules[category] ?? []).enumerated() {
                slots.append(SimSlot(category: category, index: index, moduleTypeId: typeID,
                                     chargeTypeId: loadout.charges[typeID]))
            }
        }
        return DogmaFit(shipTypeID: input.hull.typeID, slots: slots, droneTypeIDs: loadout.drones,
                        implantTypeIDs: input.implants, passiveModuleTypeIDs: passive)
    }

    // MARK: Evaluation

    /// Calculates every fit not already cached, in parallel. Past the budget, only `force`d
    /// fits are calculated; the rest score nil.
    @discardableResult
    func scores(_ loadouts: [ForgeLoadout], force: Bool = false) async throws -> [Double?] {
        try Task.checkCancellation()
        var fresh: [ForgeLoadout] = []
        var seen = Set<ForgeLoadout>()
        for loadout in loadouts where cache[loadout] == nil && seen.insert(loadout).inserted { fresh.append(loadout) }
        if !force && fresh.count > limit - evaluations {
            hitBudget = true
            fresh = Array(fresh.prefix(max(limit - evaluations, 0)))
        }
        if !fresh.isEmpty {
            let fits = fresh.map(dogmaFit)
            let evaluate = evaluate
            let results = await withTaskGroup(of: (Int, SimStats).self, returning: [(Int, SimStats)].self) { group in
                for (index, fit) in fits.enumerated() { group.addTask { (index, evaluate(fit)) } }
                return await group.reduce(into: []) { $0.append($1) }
            }
            for (index, stats) in results { cache[fresh[index]] = stats }
            evaluations += fresh.count
            progress?(evaluations, options.evaluationBudget)
        }
        return loadouts.map { cache[$0].flatMap { HangarForgeEngine.score($0, options: options) } }
    }

    func score(_ loadout: ForgeLoadout) async throws -> Double? {
        try await scores([loadout], force: true)[0]
    }

    private func best(of loadouts: [ForgeLoadout]) async throws -> (loadout: ForgeLoadout, score: Double)? {
        let scored = try await scores(loadouts)
        return zip(loadouts, scored).compactMap { loadout, score in score.map { (loadout, $0) } }
            .max { $0.1 < $1.1 }
    }

    // MARK: Probe

    /// Calculates each part alone on the empty hull, to learn which layer it tanks and
    /// whether it adds CPU or powergrid.
    func probe() async throws {
        let empty = ForgeLoadout()
        let singles = parts.keys.sorted().compactMap { typeID in add(typeID, to: empty).map { (typeID, $0) } }
        try await scores([empty] + singles.map(\.1), force: true)
        guard let base = cache[empty], base.hasData else { throw HangarForgeFailure.engineUnavailable }
        for (typeID, loadout) in singles {
            guard let stats = cache[loadout] else { continue }
            layers[typeID] = Self.layer(from: base, to: stats)
            if stats.cpuTotal > base.cpuTotal + 0.5 || stats.powerTotal > base.powerTotal + 0.5 {
                enablers.insert(typeID)
            }
        }
    }

    static func layer(from base: SimStats, to stats: SimStats) -> Layer {
        func ehp(_ hp: Double, _ r: SimResists) -> Double {
            hp / max(1 - (r.em + r.explosive + r.kinetic + r.thermal) / 400, 1e-6)
        }
        func gain(_ before: Double, _ after: Double) -> Double {
            before > 0 ? (after - before) / before : (after > 0 ? 1 : 0)
        }
        let shield = max(gain(ehp(base.shieldHP, base.shieldResists), ehp(stats.shieldHP, stats.shieldResists)),
                         gain(base.shieldBoostRate + base.passiveShieldRate, stats.shieldBoostRate + stats.passiveShieldRate))
        let armor = max(gain(ehp(base.armorHP, base.armorResists), ehp(stats.armorHP, stats.armorResists)),
                        gain(base.armorRepairRate, stats.armorRepairRate))
        let top = max(shield, armor)
        // Damage controls and the like help both layers alike — fine on either seed.
        guard top > 0.005, min(shield, armor) < top * 0.3 else { return .neutral }
        return shield > armor ? .shield : .armor
    }

    /// Parts each seed leaves out: a shield seed drops armor parts and vice versa. One
    /// empty ban when the parts on hand don't split.
    func layerBans() -> [Set<Int>] {
        let shield = Set(layers.filter { $0.value == .shield }.keys)
        let armor = Set(layers.filter { $0.value == .armor }.keys)
        guard !shield.isEmpty, !armor.isEmpty else { return [[]] }
        return [armor, shield]
    }

    // MARK: Seeds

    /// The best racks of each owned weapon, loaded with their best ammo, top few kept.
    /// Hull bonuses usually settle the weapon choice here, before anything else is fitted.
    func weaponSeeds() async throws -> [ForgeLoadout] {
        let weapons = parts.values.filter { $0.hardpoint != nil }.map(\.typeID).sorted()
        var racks: [[ForgeLoadout]] = []
        for weapon in weapons {
            var rack: [ForgeLoadout] = []
            var loadout = ForgeLoadout()
            while let next = add(weapon, to: loadout) { rack.append(next); loadout = next }
            racks.append(rack)
        }
        try await scores(racks.flatMap(\.self), force: true)

        var seeds: [(ForgeLoadout, Double)] = []
        for rack in racks {
            let scored = try await scores(rack, force: true)
            guard let pick = zip(rack, scored).compactMap({ l, s in s.map { (l, $0) } }).max(by: { $0.1 < $1.1 }) else { continue }
            let tuned = try await tuneCharges(pick.0)
            if let score = try await score(tuned) { seeds.append((tuned, score)) }
        }
        let kept = seeds.sorted { $0.1 > $1.1 }.prefix(HangarForgeEngine.weaponSeeds).map(\.0)
        return kept.isEmpty ? [ForgeLoadout()] : Array(kept)
    }

    // MARK: Search

    /// Seed → drones → greedy fill → ammo → swaps → drones and ammo again.
    func forge(from seed: ForgeLoadout, banned: Set<Int>) async throws -> ForgeLoadout {
        var loadout = try await chooseDrones(seed)
        loadout = try await climb(loadout, banned: banned, swaps: false)
        loadout = try await tuneCharges(loadout)
        loadout = try await climb(loadout, banned: banned, swaps: true)
        loadout = try await chooseDrones(loadout)
        return try await tuneCharges(loadout)
    }

    /// Hill-climbs from `start`, taking the single best move each round: adding a module,
    /// and with `swaps`, also removing or replacing one. Adds that only fit alongside a
    /// CPU/powergrid upgrade are tried as pairs once single moves run out.
    func climb(_ start: ForgeLoadout, banned: Set<Int>, swaps: Bool) async throws -> ForgeLoadout {
        var current = start
        var currentScore = try await score(current) ?? -.infinity
        while evaluations < limit {
            var moves = additions(to: current, banned: banned)
            if swaps { moves += replacements(in: current, banned: banned) }
            if let best = try await best(of: moves), best.score > currentScore + 1e-9 {
                (current, currentScore) = best
                continue
            }
            let pairs = enablers.subtracting(banned).sorted().compactMap { add($0, to: current) }
                .flatMap { additions(to: $0, banned: banned) }
            if let best = try await best(of: pairs), best.score > currentScore + 1e-9 {
                (current, currentScore) = best
                continue
            }
            break
        }
        return current
    }

    func additions(to loadout: ForgeLoadout, banned: Set<Int>) -> [ForgeLoadout] {
        partsByCategory.values.joined().filter { !banned.contains($0.typeID) }.compactMap { add($0.typeID, to: loadout) }
    }

    /// Every way to take one module out, or swap it for another of its slot type.
    func replacements(in loadout: ForgeLoadout, banned: Set<Int>) -> [ForgeLoadout] {
        var out: [ForgeLoadout] = []
        for (category, modules) in loadout.modules {
            for typeID in Set(modules).sorted() {
                let removed = loadout.removing(typeID, from: category)
                out.append(removed)
                for part in partsByCategory[category] ?? [] where part.typeID != typeID && !banned.contains(part.typeID) {
                    if let swapped = add(part.typeID, to: removed) { out.append(swapped) }
                }
            }
        }
        return out
    }

    /// For each module type that takes charges, the owned charge (or none) that scores best.
    func tuneCharges(_ start: ForgeLoadout) async throws -> ForgeLoadout {
        var current = start
        for typeID in Set(current.allModules).sorted() {
            guard let part = parts[typeID], !part.charges.isEmpty else { continue }
            let choices: [Int?] = [nil] + part.charges
            let variants = choices.map { charge -> ForgeLoadout in
                var variant = current
                variant.charges[typeID] = charge
                return variant
            }.filter(allows)
            if let best = try await best(of: variants + [current]) { current = best.loadout }
        }
        return current
    }

    /// The drones to launch: the best single type filling the bandwidth, or a mix in that
    /// ranking's order, whichever scores higher.
    func chooseDrones(_ start: ForgeLoadout) async throws -> ForgeLoadout {
        guard droneBandwidth > 0, !droneStock.isEmpty else { return start }
        let types = input.types
        func bandwidth(_ id: Int) -> Double { types[id]?.attribute(DogmaLoadout.droneBandwidthUsedAttribute) ?? .infinity }
        func volume(_ id: Int) -> Double { types[id]?.volume ?? .infinity }

        func launch(_ ranking: [Int]) -> [Int] {
            var left = (bandwidth: droneBandwidth, bay: droneBay)
            var out: [Int] = []
            for id in ranking {
                for _ in 0..<(droneStock[id] ?? 0) {
                    guard out.count < DogmaLoadout.maxActiveDrones,
                          bandwidth(id) <= left.bandwidth, volume(id) <= left.bay else { break }
                    out.append(id)
                    left.bandwidth -= bandwidth(id)
                    left.bay -= volume(id)
                }
            }
            return out.sorted()
        }

        var none = start
        none.drones = []
        let singles = droneStock.keys.sorted().compactMap { id -> (Int, ForgeLoadout)? in
            var loadout = start
            loadout.drones = launch([id])
            return loadout.drones.isEmpty ? nil : (id, loadout)
        }
        let scored = try await scores(singles.map(\.1))
        let ranking = zip(singles, scored).compactMap { pair, score in score.map { (pair.0, $0) } }
            .sorted { $0.1 > $1.1 }.map(\.0)
        var mixed = start
        mixed.drones = launch(ranking)
        return try await best(of: [none, start, mixed] + singles.map(\.1))?.loadout ?? start
    }

    // MARK: Result

    func result(for loadout: ForgeLoadout, stock: [Int: [HangarForgeSource]]) async throws -> HangarForgeResult {
        // What each module is worth: the fit with one taken out.
        var without: [Int: ForgeLoadout] = [:]
        for (category, modules) in loadout.modules {
            for typeID in Set(modules) { without[typeID] = loadout.removing(typeID, from: category) }
        }
        var noDrones = loadout
        noDrones.drones = []
        try await scores([loadout, noDrones] + Array(without.values), force: true)

        let stats = cache[loadout] ?? SimStats()
        let fit = dogmaFit(loadout)
        let picks = fit.slots.compactMap { slot -> HangarForgePick? in
            guard let typeID = slot.moduleTypeId else { return nil }
            return HangarForgePick(flag: slot.flag, category: slot.category, typeID: typeID,
                                   chargeTypeID: slot.chargeTypeId,
                                   without: without[typeID].flatMap { cache[$0] }.map(FitPerformance.init))
        }

        var needs: [Int: Int] = [:]
        for typeID in loadout.allModules + loadout.drones { needs[typeID, default: 0] += 1 }
        for charge in Set(loadout.charges.values) { needs[charge] = chargeStock[charge] }

        var open: [SimSlotCategory: Int] = [:]
        for (category, count) in slotCounts where count > loadout.filled(category) {
            open[category] = count - loadout.filled(category)
        }

        return HangarForgeResult(
            hull: input.hull, options: options, fit: fit, stats: stats, performance: FitPerformance(stats),
            picks: picks, drones: loadout.drones,
            withoutDrones: loadout.drones.isEmpty ? nil : cache[noDrones].map(FitPerformance.init),
            openSlots: open, needs: needs, sources: stock.filter { needs[$0.key] != nil },
            evaluations: evaluations, hitBudget: hitBudget
        )
    }
}
