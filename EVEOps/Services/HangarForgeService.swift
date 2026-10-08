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

/// A hull in the forge's picker.
struct HangarForgeHullOption: Identifiable, Hashable {
    let hull: HangarForgeHull
    let typeName: String
    /// The name the pilot gave the ship in game, when it has one.
    let customName: String?
    let className: String
    let placeName: String

    var id: Int { hull.itemID }
    /// "Ratting Ishtar (Ishtar)", or just "Ishtar".
    var displayName: String { customName.map { "\($0) (\(typeName))" } ?? typeName }
}

/// The pilot's hulls, and every type and place the forge needs to name, built from a
/// Ready Room snapshot.
struct HangarForgeCatalog {
    /// The snapshot holdings this was built from, so a refresh that changes nothing
    /// doesn't rebuild it.
    let holdingsHash: Int
    let hulls: [HangarForgeHullOption]
    /// Hull types only — part types arrive with each run.
    let types: [Int: ESIType]
    let places: [Int: ReadyRoomPlace]
    let skillNames: [Int: String]

    /// Ship classes the pilot owns a hull in, by name, with how many hulls each.
    var classes: [(name: String, count: Int)] {
        Dictionary(grouping: hulls, by: \.className)
            .map { (name: $0.key, count: $0.value.count) }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }
}

/// A saved fitting for the same hull, run with the pilot's skills, to set beside a forged fit.
struct HangarForgeComparison: Identifiable {
    let fittingID: Int
    let name: String
    /// Its Ready Room tier, when the board has it.
    let tier: ReadyRoomTier?
    let performance: FitPerformance
    /// Within CPU, powergrid and calibration with today's skills.
    let fitsNow: Bool

    var id: Int { fittingID }
}

/// One forge build for a pilot: in progress, finished, or failed.
struct HangarForgeRun {
    let hullItemID: Int
    let options: HangarForgeOptions
    var done = 0
    var budget = 1
    var result: HangarForgeResult?
    var error: String?
    /// Names for the places the result takes parts from.
    var places: [Int: ReadyRoomPlace] = [:]
    /// Every type the run looked at, for names.
    var types: [Int: ESIType] = [:]
    /// Restored from an earlier launch rather than forged just now.
    var isRestored = false
    /// What the run is doing before the search starts ("Pricing market modules…").
    var phase: String?
    var comparisons: [HangarForgeComparison] = []

    var isRunning: Bool { result == nil && error == nil }
    var fraction: Double { min(Double(done) / Double(max(budget, 1)), 1) }
}

/// The last fit forged for a pilot, kept between launches.
private struct HangarForgeStoredRun: Codable {
    let hullItemID: Int
    let options: HangarForgeOptions
    let fit: HangarForgeSavedFit
}

// MARK:  Service

/// Builds the strongest fit for a hull the pilot owns from the parts they own — the Ready
/// Room's Hangar Forge tab. Reads the Ready Room's snapshot rather than loading assets again.
@MainActor
@Observable
final class HangarForgeService {
    static let shared = HangarForgeService()

    private(set) var catalogs: [Int: HangarForgeCatalog] = [:]
    private(set) var catalogErrors: [Int: String] = [:]
    private(set) var runs: [Int: HangarForgeRun] = [:]
    private var catalogLoading: Set<Int> = []
    private var tasks: [Int: Task<Void, Never>] = [:]

    /// Capsules have no slots to fill.
    private static let capsuleGroup = 29
    private static let shipCategory = 6

    /// Item groups the forge may buy from: modules that change damage, tank, speed or
    /// fitting room, and rigs (verified against the SDE). Weapons aren't bought.
    private static let marketGroups: Set<Int> = [
        59, 205, 302, 367, 645, 1988, 4067,          // damage modules
        211, 213, 1395, 1396, 644, 646,              // tracking, guidance, drone control
        38, 77, 295, 40, 1156, 57,                   // shield
        329, 326, 98, 62, 1199, 1150, 60,            // armor, damage control
        766, 769, 285, 43,                           // powergrid, CPU, capacitor
        764, 763, 762, 46,                           // speed and agility
        773, 774, 775, 776, 777, 778, 779, 781, 782, // rigs
    ]

    private init() {}

    func isLoadingCatalog(_ characterID: Int) -> Bool { catalogLoading.contains(characterID) }

    // MARK:  Catalog

    /// Finds the pilot's hulls in the snapshot's holdings and names them, then brings back
    /// the last fit forged for this pilot if it can still be built.
    func loadCatalog(_ snapshot: ReadyRoomSnapshot, token: String) async {
        let characterID = snapshot.characterID
        let holdings = snapshot.input.holdings
        let hash = holdings.hashValue
        guard catalogs[characterID]?.holdingsHash != hash,
              catalogLoading.insert(characterID).inserted else { return }
        defer { catalogLoading.remove(characterID) }

        // Ship groups list their types, so only the hulls themselves need fetching — not
        // every type in a large asset list.
        var shipGroupIDs = CharacterFittingsView.eveShipGroupIds
            .union(await UniverseCache.shared.category(id: Self.shipCategory)?.groups ?? [])
        shipGroupIDs.remove(Self.capsuleGroup)
        let groups = await UniverseCache.shared.groups(ids: shipGroupIDs)
        let shipTypeIDs = Set(groups.values.flatMap(\.types))
        let candidates = holdings.filter { $0.fittedToItemID == nil }
        let typeIDs = shipTypeIDs.isEmpty
            ? Set(candidates.map(\.typeID))                                 // groups unavailable: check everything
            : Set(candidates.map(\.typeID)).intersection(shipTypeIDs)
        let types = await UniverseCache.shared.types(ids: Array(typeIDs))

        let requirements = await SkillPrerequisites.shared.requirements(for: Array(typeIDs))
        let skills = snapshot.input.skills.mapValues(\.active)
        let hulls = HangarForgeEngine.hulls(holdings: holdings, types: types, shipGroupIDs: shipGroupIDs,
                                            requirements: requirements, skills: skills)
        let missingSkillIDs = Set(hulls.flatMap(\.missingSkills.keys))
        let skillNames = await SkillPrerequisites.shared.trainingInfo(for: Array(missingSkillIDs)).mapValues(\.name)
        let customNames = await Self.shipNames(hulls.filter { $0.isAssembled && !$0.isCorporation }.map(\.itemID),
                                               characterID: characterID, token: token)

        var places = snapshot.places
        let unnamed = Set(hulls.map(\.placeID)).subtracting(places.keys)
        if !unnamed.isEmpty {
            places.merge(await ReadyRoomPlaces.resolve(unnamed, token: token)) { old, _ in old }
        }

        var options: [HangarForgeHullOption] = []
        for hull in hulls {
            let groupID = types[hull.typeID]?.groupId ?? 0
            let className: String = groups[groupID]?.name ?? CharacterFittingsView.eveShipGroups[groupID]
                ?? String(localized: "Other")
            options.append(HangarForgeHullOption(
                hull: hull,
                typeName: types[hull.typeID]?.name ?? String(localized: "Unknown ship"),
                customName: customNames[hull.itemID],
                className: className,
                placeName: places[hull.placeID]?.name ?? String(localized: "Unknown location")
            ))
        }
        options.sort { a, b in
            let byType = a.typeName.localizedStandardCompare(b.typeName)
            if byType != .orderedSame { return byType == .orderedAscending }
            let byPlace = a.placeName.localizedStandardCompare(b.placeName)
            if byPlace != .orderedSame { return byPlace == .orderedAscending }
            return (a.customName ?? "").localizedStandardCompare(b.customName ?? "") == .orderedAscending
        }

        catalogs[characterID] = HangarForgeCatalog(holdingsHash: hash, hulls: options, types: types,
                                                   places: places, skillNames: skillNames)
        catalogErrors[characterID] = nil

        if runs[characterID] == nil { await restore(snapshot, token: token) }
    }

    /// Names the pilot gave their assembled ships; ships still called by their type are left out.
    private static func shipNames(_ itemIDs: [Int], characterID: Int, token: String) async -> [Int: String] {
        var out: [Int: String] = [:]
        for start in stride(from: 0, to: itemIDs.count, by: 1_000) {
            let chunk = Array(itemIDs[start..<min(start + 1_000, itemIDs.count)])
            guard let names: [ESIAssetName] = try? await ESIClient.shared.post(
                "/characters/\(characterID)/assets/names/", body: chunk, token: token
            ) else { continue }
            for entry in names where entry.name != "None" && !entry.name.isEmpty { out[entry.itemId] = entry.name }
        }
        return out
    }

    // MARK:  Forge

    /// Starts a build, replacing any running for the same pilot.
    func forge(_ hull: HangarForgeHull, options: HangarForgeOptions, snapshot: ReadyRoomSnapshot, token: String) {
        let characterID = snapshot.characterID
        tasks[characterID]?.cancel()
        runs[characterID] = HangarForgeRun(hullItemID: hull.itemID, options: options, budget: options.evaluationBudget)
        tasks[characterID] = Task { [weak self] in
            await self?.run(hull, options: options, snapshot: snapshot, token: token)
        }
    }

    func cancel(_ characterID: Int) {
        tasks[characterID]?.cancel()
        tasks[characterID] = nil
        runs[characterID] = nil
    }

    private func run(_ hull: HangarForgeHull, options: HangarForgeOptions, snapshot: ReadyRoomSnapshot, token: String) async {
        let characterID = snapshot.characterID
        func finish(_ update: (inout HangarForgeRun) -> Void) {
            guard !Task.isCancelled, var current = runs[characterID], current.hullItemID == hull.itemID else { return }
            update(&current)
            runs[characterID] = current
        }

        guard await ReadyRoomFittingChecker.prepareEngine(allowLoad: true) else {
            finish { $0.error = HangarForgeFailure.engineUnavailable.localizedDescription }
            return
        }
        if (options.buyBudget ?? 0) > 0 { finish { $0.phase = String(localized: "Pricing market modules…") } }
        let (input, types) = await prepare(hull, options: options, snapshot: snapshot)
        finish { $0.phase = nil }
        let skills = input.skills
        let progress: HangarForgeEngine.Progress = { done, budget in
            Task { @MainActor [weak self] in
                guard let self, var current = self.runs[characterID], current.hullItemID == hull.itemID,
                      current.isRunning else { return }
                current.done = max(current.done, done)
                current.budget = budget
                self.runs[characterID] = current
            }
        }

        let work = Task.detached(priority: .userInitiated) {
            try await HangarForgeEngine.build(input, options: options,
                                              evaluate: { DogmaEngine.shared.calculate($0, skills: skills) },
                                              progress: progress)
        }
        do {
            let result = try await withTaskCancellationHandler { try await work.value } onCancel: { work.cancel() }
            let places = await places(for: result, characterID: characterID, snapshot: snapshot, token: token)
            let comparisons = await comparisons(for: hull, snapshot: snapshot)
            finish {
                $0.result = result
                $0.places = places
                $0.types = types
                $0.comparisons = comparisons
                $0.done = result.evaluations
            }
            if !Task.isCancelled { store(result, characterID: characterID) }
        } catch is CancellationError {
            return
        } catch {
            finish { $0.error = error.localizedDescription }
        }
    }

    /// The engine's input for `hull`: the stock in scope, the types it involves, and the
    /// skill requirements of everything that could go on the ship.
    private func prepare(_ hull: HangarForgeHull, options: HangarForgeOptions,
                         snapshot: ReadyRoomSnapshot) async -> (HangarForgeInput, [Int: ESIType]) {
        let holdings = snapshot.input.holdings
        let stock = HangarForgeEngine.stock(for: hull, holdings: holdings, options: options)
        let prices = await marketPrices(options)
        let catalogTypes = catalogs[snapshot.characterID]?.types ?? [:]
        let wanted = Set(stock.keys).union(prices.keys).union([hull.typeID]).subtracting(catalogTypes.keys)
        let types = catalogTypes.merging(await UniverseCache.shared.types(ids: Array(wanted))) { old, _ in old }
        let buyable = Set(prices.keys.filter { id in
            types[id].map { $0.published && $0.dogmaEffects.flatMap(SimSlotEffect.category(from:)) != nil } ?? false
        })
        let relevant = Self.relevantTypes(Set(stock.keys), types: types).union(buyable).union([hull.typeID])
        let requirements = await SkillPrerequisites.shared.requirements(for: Array(relevant))
        var input = HangarForgeInput(
            hull: hull, holdings: holdings,
            types: types.filter { relevant.contains($0.key) },
            requirements: requirements,
            skills: snapshot.input.skills.mapValues(\.active),
            implants: snapshot.pilot.implantIDs
        )
        input.market = prices.filter { buyable.contains($0.key) }
        return (input, types)
    }

    /// Jita prices for every module the forge may buy that's on sale within the budget —
    /// so only those need their details loaded. Empty without a budget.
    private func marketPrices(_ options: HangarForgeOptions) async -> [Int: Double] {
        guard let budget = options.buyBudget, budget > 0 else { return [:] }
        let groupIDs = Self.marketGroups.union(options.utilities.flatMap(\.groupIDs))
        let groups = await UniverseCache.shared.groups(ids: groupIDs)
        let typeIDs = Array(Set(groups.values.flatMap(\.types))).sorted()
        var out: [Int: Double] = [:]
        for start in stride(from: 0, to: typeIDs.count, by: 250) {
            let chunk = Array(typeIDs[start..<min(start + 250, typeIDs.count)])
            guard let prices = try? await FuzzworkClient.shared.prices(typeIds: chunk) else { continue }
            for (typeID, price) in prices where price.sellMin > 0 && price.sellMin <= budget { out[typeID] = price.sellMin }
        }
        return out
    }

    /// The pilot's saved fittings for this hull type, calculated with today's skills.
    private func comparisons(for hull: HangarForgeHull, snapshot: ReadyRoomSnapshot) async -> [HangarForgeComparison] {
        let fittings = snapshot.input.fittings.filter { $0.shipTypeId == hull.typeID }
        guard !fittings.isEmpty else { return [] }
        let types = await UniverseCache.shared.types(ids: Array(Set(fittings.flatMap { [$0.shipTypeId] + $0.items.map(\.typeId) })))
        let skills = snapshot.input.skills.mapValues(\.active)
        let implants = snapshot.pilot.implantIDs
        let tiers = Dictionary(snapshot.reports.map { ($0.fittingID, $0.tier) }, uniquingKeysWith: { a, _ in a })
        let calculated = await Task.detached(priority: .userInitiated) {
            fittings.map { fitting -> (Int, String, FitPerformance, Bool) in
                let fit = DogmaFit(fitting: fitting, types: types, implants: implants, onlineOnly: false)
                let stats = DogmaEngine.shared.calculate(fit, skills: skills)
                let fits = stats.cpuUsed <= stats.cpuTotal + 0.05 && stats.powerUsed <= stats.powerTotal + 0.05
                    && stats.calibrationUsed <= stats.calibrationTotal + 0.05
                return (fitting.fittingId, fitting.name, FitPerformance(stats), fits)
            }
        }.value
        return calculated.map { id, name, performance, fits in
            HangarForgeComparison(fittingID: id, name: name, tier: tiers[id], performance: performance, fitsNow: fits)
        }.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    private func places(for result: HangarForgeResult, characterID: Int, snapshot: ReadyRoomSnapshot,
                        token: String) async -> [Int: ReadyRoomPlace] {
        var places = catalogs[characterID]?.places ?? snapshot.places
        let unnamed = Set(result.sources.values.flatMap { $0.map(\.placeID) }).subtracting(places.keys)
        if !unnamed.isEmpty {
            places.merge(await ReadyRoomPlaces.resolve(unnamed, token: token)) { old, _ in old }
        }
        return places
    }

    // MARK:  Last Fit

    private func storeKey(_ characterID: Int) -> String { "hangarForge.lastFit.\(characterID)" }

    private func store(_ result: HangarForgeResult, characterID: Int) {
        let stored = HangarForgeStoredRun(hullItemID: result.hull.itemID, options: result.options, fit: result.saved)
        if let data = try? JSONEncoder().encode(stored) {
            UserDefaults.standard.set(data, forKey: storeKey(characterID))
        }
    }

    /// Brings back the last fit forged for this pilot, recalculated against today's
    /// skills and assets. Dropped quietly when the hull is gone or a part is no longer
    /// owned, usable or in scope.
    private func restore(_ snapshot: ReadyRoomSnapshot, token: String) async {
        let characterID = snapshot.characterID
        guard let data = UserDefaults.standard.data(forKey: storeKey(characterID)),
              let stored = try? JSONDecoder().decode(HangarForgeStoredRun.self, from: data),
              let hull = catalogs[characterID]?.hulls.first(where: { $0.id == stored.hullItemID })?.hull,
              await ReadyRoomFittingChecker.prepareEngine(allowLoad: true) else { return }

        var options = stored.options
        options.includeCorporation = ReadyRoomService.shared.includeCorporation
        let (input, types) = await prepare(hull, options: options, snapshot: snapshot)
        let skills = input.skills
        let result = try? await Task.detached(priority: .userInitiated) {
            try await HangarForgeEngine.restore(stored.fit, input: input, options: options,
                                                evaluate: { DogmaEngine.shared.calculate($0, skills: skills) })
        }.value
        guard let result = result ?? nil, runs[characterID] == nil else { return }
        let places = await places(for: result, characterID: characterID, snapshot: snapshot, token: token)
        let comparisons = await comparisons(for: hull, snapshot: snapshot)
        guard runs[characterID] == nil else { return }
        runs[characterID] = HangarForgeRun(hullItemID: hull.itemID, options: options, done: result.evaluations,
                                           budget: result.evaluations, result: result, places: places,
                                           types: types, isRestored: true, comparisons: comparisons)
    }

    /// Owned types that could go on a ship: modules, drones, and charges some owned module
    /// takes. Keeps skill lookups to what matters when the stock spans a whole asset list.
    nonisolated static func relevantTypes(_ typeIDs: Set<Int>, types: [Int: ESIType]) -> Set<Int> {
        let modules = typeIDs.filter { types[$0]?.dogmaEffects.flatMap(SimSlotEffect.category(from:)) != nil }
        let chargeGroups = Set(modules.flatMap { id in
            DogmaLoadout.chargeGroupAttributes.compactMap { types[id]?.attribute($0) }.map { Int($0) }
        })
        return Set(typeIDs.filter { id in
            guard let type = types[id] else { return false }
            return modules.contains(id) || chargeGroups.contains(type.groupId)
                || (type.attribute(DogmaLoadout.droneBandwidthUsedAttribute) ?? 0) > 0
        })
    }
}
