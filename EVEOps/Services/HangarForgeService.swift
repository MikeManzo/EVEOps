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
    let className: String
    let placeName: String

    var id: Int { hull.itemID }
}

/// The pilot's hulls, and every type and place the forge needs to name, built from a
/// Ready Room snapshot.
struct HangarForgeCatalog {
    /// The snapshot holdings this was built from, so a refresh that changes nothing
    /// doesn't rebuild it.
    let holdingsHash: Int
    let hulls: [HangarForgeHullOption]
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

    var isRunning: Bool { result == nil && error == nil }
    var fraction: Double { min(Double(done) / Double(max(budget, 1)), 1) }
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

    private init() {}

    func isLoadingCatalog(_ characterID: Int) -> Bool { catalogLoading.contains(characterID) }

    // MARK:  Catalog

    /// Finds the pilot's hulls in the snapshot's holdings and names them. Types come from
    /// the shared cache, which the Fittings screen has usually filled already.
    func loadCatalog(_ snapshot: ReadyRoomSnapshot, token: String) async {
        let characterID = snapshot.characterID
        let holdings = snapshot.input.holdings
        let hash = holdings.hashValue
        guard catalogs[characterID]?.holdingsHash != hash,
              catalogLoading.insert(characterID).inserted else { return }
        defer { catalogLoading.remove(characterID) }

        let types = await UniverseCache.shared.types(ids: Array(Set(holdings.map(\.typeID))))
        let groups = await UniverseCache.shared.groups(ids: Set(types.values.map(\.groupId)))
        var shipGroupIDs = CharacterFittingsView.eveShipGroupIds.union(groups.values.filter { $0.categoryId == 6 }.map(\.groupId))
        shipGroupIDs.remove(Self.capsuleGroup)

        let hullTypeIDs = Set(holdings.compactMap { holding in
            types[holding.typeID].flatMap { shipGroupIDs.contains($0.groupId) ? holding.typeID : nil }
        })
        let requirements = await SkillPrerequisites.shared.requirements(for: Array(hullTypeIDs))
        let skills = snapshot.input.skills.mapValues(\.active)
        let hulls = HangarForgeEngine.hulls(holdings: holdings, types: types, shipGroupIDs: shipGroupIDs,
                                            requirements: requirements, skills: skills)
        let missingSkillIDs = Set(hulls.flatMap(\.missingSkills.keys))
        let skillNames = await SkillPrerequisites.shared.trainingInfo(for: Array(missingSkillIDs)).mapValues(\.name)

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
                className: className,
                placeName: places[hull.placeID]?.name ?? String(localized: "Unknown location")
            ))
        }
        options.sort { a, b in
            let byType = a.typeName.localizedStandardCompare(b.typeName)
            return byType != .orderedSame ? byType == .orderedAscending
                : a.placeName.localizedStandardCompare(b.placeName) == .orderedAscending
        }

        catalogs[characterID] = HangarForgeCatalog(holdingsHash: hash, hulls: options, types: types,
                                                   places: places, skillNames: skillNames)
        catalogErrors[characterID] = nil
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

        let holdings = snapshot.input.holdings
        let stock = HangarForgeEngine.stock(for: hull, holdings: holdings, options: options)
        let catalogTypes = catalogs[characterID]?.types ?? [:]
        let wanted = Set(stock.keys).union([hull.typeID]).subtracting(catalogTypes.keys)
        let types = catalogTypes.merging(await UniverseCache.shared.types(ids: Array(wanted))) { old, _ in old }
        let relevant = Self.relevantTypes(Set(stock.keys), types: types).union([hull.typeID])
        let requirements = await SkillPrerequisites.shared.requirements(for: Array(relevant))

        let input = HangarForgeInput(
            hull: hull, holdings: holdings,
            types: types.filter { relevant.contains($0.key) },
            requirements: requirements,
            skills: snapshot.input.skills.mapValues(\.active),
            implants: snapshot.pilot.implantIDs
        )
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
            var places = catalogs[characterID]?.places ?? snapshot.places
            let unnamed = Set(result.sources.values.flatMap { $0.map(\.placeID) }).subtracting(places.keys)
            if !unnamed.isEmpty {
                places.merge(await ReadyRoomPlaces.resolve(unnamed, token: token)) { old, _ in old }
            }
            finish {
                $0.result = result
                $0.places = places
                $0.done = result.evaluations
            }
        } catch is CancellationError {
            return
        } catch {
            finish { $0.error = error.localizedDescription }
        }
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
