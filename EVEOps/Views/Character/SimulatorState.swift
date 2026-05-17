//
// SimulatorState.swift
// EVEOps
//
// This file is part of EVEOps.
//
// EVEOps is free software: you can redistribute it and/or modify
// it under the terms of the GNU General Public License as published by
// the Free Software Foundation, version 3 or later.
//
// Copyright (c) 2026 CitizenCoder
//

import SwiftUI

// MARK:  Simulator State

@Observable @MainActor
final class SimulatorState {
    var shipTypeId: Int?
    var shipType: ESIType?
    var slots: [SimSlot] = []
    var moduleTypes: [Int: ESIType] = [:]
    var stats: SimStats = SimStats()
    var activeSlotId: UUID?
    var isLoadingShip = false
    var shipName: String = ""
    var shipClassName: String = ""

    var draggingCategory: SimSlotCategory? = nil
    var pendingDropPayload: SimModuleDrag? = nil
    var effectDetailsCache: [Int: ESIDogmaEffectDetail] = [:]
    var isComputingEffects = false
    var implantTypes: [ESIType] = []
    var includeImplants: Bool = true
    var characterSkills: [Int: Int] = [:]   // skillTypeId → activeSkillLevel
    var skillTypes: [Int: ESIType] = [:]    // skillTypeId → type data with dogma attrs/effects

    var activeSlot: SimSlot? {
        guard let id = activeSlotId else { return nil }
        return slots.first { $0.id == id }
    }

    func selectShip(typeId: Int) async {
        isLoadingShip = true
        shipTypeId = typeId
        slots = []
        moduleTypes = [:]
        stats = SimStats()
        activeSlotId = nil

        let types = await UniverseCache.shared.types(ids: [typeId])
        guard let t = types[typeId] else { isLoadingShip = false; return }
        shipType = t
        shipName = t.name
        shipClassName = await UniverseCache.shared.group(id: t.groupId)?.name ?? ""
        slots = buildSlots(from: t)
        recomputeStats()
        isLoadingShip = false
    }

    @discardableResult
    func fillNextAvailableSlot(category: SimSlotCategory, typeId: Int) async -> Bool {
        guard let slot = slots.first(where: { $0.category == category && $0.isEmpty }) else { return false }
        await fillSlot(id: slot.id, with: typeId)
        return true
    }

    func fillSlot(id: UUID, with typeId: Int) async {
        guard let idx = slots.firstIndex(where: { $0.id == id }) else { return }
        slots[idx].moduleTypeId = typeId
        if moduleTypes[typeId] == nil {
            let types = await UniverseCache.shared.types(ids: [typeId])
            if let t = types[typeId] { moduleTypes[typeId] = t }
        }
        recomputeStats()
        activeSlotId = nil
        prefetchFittedEffects()
    }

    /// Synchronous slot placement for drag-and-drop — mutates state immediately on the
    /// calling thread (must be main), then fetches the module type in the background.
    @MainActor
    func placeModule(slotId: UUID, typeId: Int) {
        guard let idx = slots.firstIndex(where: { $0.id == slotId }) else { return }
        slots[idx].moduleTypeId = typeId
        activeSlotId = nil
        recomputeStats()
        draggingCategory = nil
        if moduleTypes[typeId] == nil {
            Task {
                let types = await UniverseCache.shared.types(ids: [typeId])
                if let t = types[typeId] {
                    moduleTypes[typeId] = t
                    recomputeStats()
                }
                prefetchFittedEffects()
            }
        } else {
            prefetchFittedEffects()
        }
    }

    func clearSlot(id: UUID) {
        guard let idx = slots.firstIndex(where: { $0.id == id }) else { return }
        let old = slots[idx].moduleTypeId
        slots[idx].moduleTypeId = nil
        if let tid = old, !slots.contains(where: { $0.moduleTypeId == tid }) {
            moduleTypes.removeValue(forKey: tid)
        }
        recomputeStats()
    }

    func clearAll() {
        for i in slots.indices { slots[i].moduleTypeId = nil }
        moduleTypes = [:]
        recomputeStats()
    }

    func loadFromSavedFitting(_ fitting: SavedFittingEntry) async {
        await selectShip(typeId: fitting.shipTypeId)
        let typeIds = Array(Set(fitting.items.map(\.typeId)))
        let types = await UniverseCache.shared.types(ids: typeIds)
        moduleTypes.merge(types) { _, new in new }
        for item in fitting.items {
            for cat in SimSlotCategory.allCases where item.flag.hasPrefix(cat.flagPrefix) {
                let suffix = item.flag.dropFirst(cat.flagPrefix.count)
                if let idx = Int(suffix),
                   let si = slots.firstIndex(where: { $0.category == cat && $0.index == idx }) {
                    slots[si].moduleTypeId = item.typeId
                }
            }
        }
        recomputeStats()
        prefetchFittedEffects()
    }

    func loadFromShipModules(_ ship: ShipEntry, modules: [ESIAsset]) async {
        await selectShip(typeId: ship.typeId)
        let typeIds = Array(Set(modules.map(\.typeId)))
        let types = await UniverseCache.shared.types(ids: typeIds)
        moduleTypes.merge(types) { _, new in new }
        for asset in modules {
            for cat in SimSlotCategory.allCases where asset.locationFlag.hasPrefix(cat.flagPrefix) {
                let suffix = asset.locationFlag.dropFirst(cat.flagPrefix.count)
                if let idx = Int(suffix),
                   let si = slots.firstIndex(where: { $0.category == cat && $0.index == idx }) {
                    slots[si].moduleTypeId = asset.typeId
                }
            }
        }
        recomputeStats()
        prefetchFittedEffects()
    }

    private func buildSlots(from type: ESIType) -> [SimSlot] {
        let attrs = type.dogmaAttributes ?? []
        func count(_ id: Int) -> Int { Int(attrs.first { $0.attributeId == id }?.value ?? 0) }
        var result: [SimSlot] = []
        for i in 0..<count(14)   { result.append(SimSlot(category: .high,      index: i)) }
        for i in 0..<count(13)   { result.append(SimSlot(category: .medium,    index: i)) }
        for i in 0..<count(12)   { result.append(SimSlot(category: .low,       index: i)) }
        for i in 0..<count(1137) { result.append(SimSlot(category: .rig,       index: i)) }
        for i in 0..<count(1367) { result.append(SimSlot(category: .subsystem, index: i)) }
        return result
    }

    func recomputeStats() {
        guard let shipType else { stats = SimStats(); return }
        let fitted = slots.compactMap { $0.moduleTypeId }.compactMap { moduleTypes[$0] }
        let activeImplants = includeImplants ? implantTypes : []
        stats = SimStatsCalculator.compute(
            shipType: shipType,
            fittedModules: fitted,
            implants: activeImplants,
            characterSkills: characterSkills,
            skillTypes: skillTypes,
            effectCache: effectDetailsCache
        )
    }


    /// Fetch the character's active implants, resolve their ESI types, and recompute.
    func loadImplants(accountManager: AccountManager) async {
        guard let account = accountManager.selectedAccount,
              let token = try? await accountManager.validToken(for: account),
              let ids: [Int] = try? await ESIClient.shared.fetch(
                  "/characters/\(account.characterID)/implants/", token: token
              ) else {
            implantTypes = []
            recomputeStats()
            return
        }
        let types = await UniverseCache.shared.types(ids: ids)
        implantTypes = ids.compactMap { types[$0] }
        recomputeStats()
        prefetchFittedEffects()
    }

    /// Fetch the character's active skills, resolve their ESI types, and recompute.
    func loadSkills(accountManager: AccountManager) async {
        guard let account = accountManager.selectedAccount,
              let token = try? await accountManager.validToken(for: account),
              let response: ESISkillsResponse = try? await ESIClient.shared.fetch(
                  "/characters/\(account.characterID)/skills/", token: token
              ) else {
            characterSkills = [:]
            skillTypes = [:]
            recomputeStats()
            return
        }
        characterSkills = Dictionary(
            uniqueKeysWithValues: response.skills.map { ($0.skillId, $0.activeSkillLevel) }
        )
        let types = await UniverseCache.shared.types(ids: Array(characterSkills.keys))
        skillTypes = types
        recomputeStats()
        prefetchFittedEffects()
    }

    /// Pre-fetch dogma effect details for all currently fitted modules, implants,
    /// and character skills, then recompute.
    func prefetchFittedEffects() {
        let fittedTypes = slots.compactMap { $0.moduleTypeId }.compactMap { moduleTypes[$0] }
        let shipTypes = shipType.map { [$0] } ?? []
        let allTypes = fittedTypes + implantTypes + Array(skillTypes.values) + shipTypes
        let effectIds = Set(allTypes.flatMap { $0.dogmaEffects?.map(\.effectId) ?? [] })
        guard !effectIds.isEmpty else { return }

        isComputingEffects = true
        Task {
            let details = await UniverseCache.shared.effectDetails(ids: effectIds)
            await MainActor.run {
                var changed = false
                for (id, d) in details where self.effectDetailsCache[id] == nil {
                    self.effectDetailsCache[id] = d
                    changed = true
                }
                if changed { self.recomputeStats() }
                self.isComputingEffects = false
            }
        }
    }
}
