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
    var moduleTypes: [Int: ESIType] = [:]   // used by UI for names/icons only
    var stats: SimStats = SimStats()
    var activeSlotId: UUID?
    var isLoadingShip = false
    var shipName: String = ""
    var shipClassName: String = ""

    var draggingCategory: SimSlotCategory? = nil
    var pendingDropPayload: SimModuleDrag? = nil
    var implantTypeIds: [Int] = []
    var includeImplants: Bool = true
    var characterSkills: [Int: Int] = [:]   // skillTypeId → trainedSkillLevel

    /// True while SDE protobuf data is downloading on first launch.
    var isLoadingSDE = false

    var activeSlot: SimSlot? {
        guard let id = activeSlotId else { return nil }
        return slots.first { $0.id == id }
    }

    // MARK: Ship Selection

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

    // MARK: Slot Management

    @discardableResult
    func fillNextAvailableSlot(category: SimSlotCategory, typeId: Int) async -> Bool {
        guard let slot = slots.first(where: { $0.category == category && $0.isEmpty }) else { return false }
        await fillSlot(id: slot.id, with: typeId)
        return true
    }

    func fillSlot(id: UUID, with typeId: Int) async {
        guard let idx = slots.firstIndex(where: { $0.id == id }) else { return }
        slots[idx].moduleTypeId = typeId
        slots[idx].isOnline = true
        if moduleTypes[typeId] == nil {
            let types = await UniverseCache.shared.types(ids: [typeId])
            if let t = types[typeId] { moduleTypes[typeId] = t }
        }
        recomputeStats()
        activeSlotId = nil
    }

    /// Synchronous slot placement for drag-and-drop — mutates state immediately on the
    /// calling thread (must be main), then fetches the module ESIType in the background
    /// for display purposes only (names, icons).
    @MainActor
    func placeModule(slotId: UUID, typeId: Int) {
        guard let idx = slots.firstIndex(where: { $0.id == slotId }) else { return }
        slots[idx].moduleTypeId = typeId
        slots[idx].isOnline = true
        activeSlotId = nil
        draggingCategory = nil
        recomputeStats()
        if moduleTypes[typeId] == nil {
            Task {
                let types = await UniverseCache.shared.types(ids: [typeId])
                if let t = types[typeId] { moduleTypes[typeId] = t }
            }
        }
    }

    func clearSlot(id: UUID) {
        guard let idx = slots.firstIndex(where: { $0.id == id }) else { return }
        let old = slots[idx].moduleTypeId
        slots[idx].moduleTypeId = nil
        slots[idx].isOnline = true
        if let tid = old, !slots.contains(where: { $0.moduleTypeId == tid }) {
            moduleTypes.removeValue(forKey: tid)
        }
        recomputeStats()
    }

    func clearAll() {
        for i in slots.indices { slots[i].moduleTypeId = nil; slots[i].isOnline = true }
        moduleTypes = [:]
        recomputeStats()
    }

    // MARK: Load from Saved Fitting / Assets

    func loadFromSavedFitting(_ fitting: SavedFittingEntry) async {
        await selectShip(typeId: fitting.shipTypeId)
        isLoadingShip = true
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
        isLoadingShip = false
    }

    func loadFromShipModules(_ ship: ShipEntry, modules: [ESIAsset]) async {
        await selectShip(typeId: ship.typeId)
        isLoadingShip = true
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
        isLoadingShip = false
    }

    // MARK: Slot Building

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

    // MARK: Stats Calculation

    func recomputeStats() {
        guard !isLoadingSDE else { return }
        guard let shipType else { stats = SimStats(); return }
        stats = DogmaEngine.shared.calculate(
            shipTypeId: shipType.typeId,
            slots: slots,
            skills: characterSkills,
            implantTypeIds: includeImplants ? implantTypeIds : []
        )
    }

    // MARK: Character Data Loading

    /// Fetches the character's active implants and recomputes.
    func loadImplants(accountManager: AccountManager) async {
        guard let account = accountManager.selectedAccount,
              let token = try? await accountManager.validToken(for: account),
              let ids: [Int] = try? await ESIClient.shared.fetch(
                  "/characters/\(account.characterID)/implants/", token: token
              ) else {
            implantTypeIds = []
            recomputeStats()
            return
        }
        implantTypeIds = ids
        recomputeStats()
    }

    /// Fetches the character's trained skill levels and recomputes.
    func loadSkills(accountManager: AccountManager) async {
        guard let account = accountManager.selectedAccount,
              let token = try? await accountManager.validToken(for: account),
              let response: ESISkillsResponse = try? await ESIClient.shared.fetch(
                  "/characters/\(account.characterID)/skills/", token: token
              ) else {
            characterSkills = [:]
            recomputeStats()
            return
        }
        characterSkills = Dictionary(
            uniqueKeysWithValues: response.skills.map { ($0.skillId, $0.activeSkillLevel) }
        )
        recomputeStats()
    }
}
