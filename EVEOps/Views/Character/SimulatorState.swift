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

import OSLog
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
    private(set) var implantTypes: [Int: ESIType] = [:]
    var includeImplants: Bool = true
    var characterSkills: [Int: Int] = [:]   // skillTypeId → trainedSkillLevel
    var activeModulesEnabled: Bool = true   // false = passive-only view (hardeners idle)

    // Per-ship calibration factors, measured once from a bare engine call (no modules,
    // no skills, no implants) and compared to the ESI-sourced dogma attribute values.
    // Dividing results by these factors anchors each stat to the correct live SDE base,
    // correcting for any divergence between the engine's protobuf SDE and EVE's current data.
    //   warpInflationFactor  = bare.warpSpeed  / attr600  (warp speed)
    //   inertiaAlignFactor   = attr70          / bare.inertiaMod (inertia modifier)
    private var cachedCalibrationShipId: Int? = nil
    private var warpInflationFactor: Double = 1.0
    private var inertiaAlignFactor: Double = 1.0

    // Implant multipliers for ship attributes the engine does not apply natively.
    // Keyed by EVE dogma attribute ID; computed once per implant load and applied in recomputeStats().
    private var implantAttrMultipliers: [Int: Double] = [:]

    // Attributes whose implant effects the engine does not apply to ships.
    // Add attr IDs here as new discrepancies are confirmed.
    //   70  = inertiaMod         (agility implants — EM series)
    //   600 = warpSpeedMultiplier (warp speed implants — WS series)
    private static let engineSkippedImplantAttrs: Set<Int> = [70, 600]

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
                if let t = types[typeId] {
                    moduleTypes[typeId] = t
                    // Re-run with the now-loaded dogma attrs so calibration and other
                    // attribute-derived values (e.g. rig costs) are correct immediately.
                    recomputeStats()
                }
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
        shipName = fitting.name
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
        shipName = ship.displayName
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
        refreshWarpCalibration(for: shipType)
        // Offline modules are excluded from the engine call: the engine applies passive rig
        // effects regardless of module state ("Passive" is not honoured for rigs), so the
        // only reliable way to honour the online/offline toggle is to not pass offline slots.
        let onlineSlots = slots.filter { $0.isOnline }
        let activeImplants = includeImplants ? implantTypeIds : []
        let fittedModuleIds = onlineSlots.compactMap(\.moduleTypeId)

        // Build the set of module typeIds that should be sent as "Online" (not "Active").
        // When active modules are disabled (passive-only view), every module is treated as
        // online-but-idle — matching the in-game station view where hardeners are fitted but
        // not activated. When active modules are enabled, only truly passive modules (attr 6
        // capacitorNeed == 0) are sent as Online; active modules like hardeners are "Active".
        let passiveModuleTypeIds: Set<Int>
        if activeModulesEnabled {
            passiveModuleTypeIds = Set(fittedModuleIds.filter { typeId in
                let capNeed = moduleTypes[typeId]?.dogmaAttributes?.first(where: { $0.attributeId == 6 })?.value ?? 0
                return capNeed == 0
            })
        } else {
            passiveModuleTypeIds = Set(fittedModuleIds)
        }

        Logger.dogmaEngine.info("[Sim] recompute ship=\(shipType.typeId, privacy: .public) modules=\(fittedModuleIds, privacy: .public) passive=\(Array(passiveModuleTypeIds), privacy: .public) skills=\(self.characterSkills.count, privacy: .public) implants=\(activeImplants, privacy: .public)")
        stats = DogmaEngine.shared.calculate(
            shipTypeId: shipType.typeId,
            slots: onlineSlots,
            skills: characterSkills,
            implantTypeIds: activeImplants,
            passiveModuleTypeIds: passiveModuleTypeIds
        )

        Logger.dogmaEngine.info("[Sim] raw resists shEM=\(self.stats.shieldResists.em, privacy: .public) shThm=\(self.stats.shieldResists.thermal, privacy: .public) shKin=\(self.stats.shieldResists.kinetic, privacy: .public) shExp=\(self.stats.shieldResists.explosive, privacy: .public)")

        // Re-run without implants to establish a no-implant baseline used by both the warp
        // speed and inertia corrections below. For each stat we prefer the engine's own
        // implant ratio when it applied them (future-proof); otherwise we fall back to the
        // effect-chain-derived multiplier from implantAttrMultipliers.
        if warpInflationFactor > 0 {
            let noImplant = DogmaEngine.shared.calculate(
                shipTypeId: shipType.typeId,
                slots: onlineSlots,
                skills: characterSkills,
                implantTypeIds: [],
                passiveModuleTypeIds: passiveModuleTypeIds
            )

            // Warp speed (attr 600) ─────────────────────────────────────────────────────
            let base = noImplant.warpSpeed / warpInflationFactor
            let warpEngineRatio = (includeImplants && noImplant.warpSpeed > 0)
                ? stats.warpSpeed / noImplant.warpSpeed : 1.0
            let warpFactor = warpEngineRatio > 1.001
                ? warpEngineRatio
                : (includeImplants ? implantAttrMultipliers[600] ?? 1.0 : 1.0)
            stats.warpSpeed = base * warpFactor

            // Inertia modifier (attr 70) ────────────────────────────────────────────────
            // Mirror the warp speed pattern: build from corrected baseline rather than
            // patching stats.inertiaMod in-place. inertiaAlignFactor corrects the engine's
            // stale SDE base; inertiaFactor carries any implant effect.
            let inertiaEngineRatio = (includeImplants && noImplant.inertiaMod > 0)
                ? stats.inertiaMod / noImplant.inertiaMod : 1.0
            let inertiaFactor = abs(inertiaEngineRatio - 1.0) > 0.001
                ? inertiaEngineRatio
                : (includeImplants ? implantAttrMultipliers[70] ?? 1.0 : 1.0)
            stats.inertiaMod = noImplant.inertiaMod * inertiaAlignFactor * inertiaFactor
            let mI = stats.mass * stats.inertiaMod
            if mI > 0 { stats.alignTime = Foundation.log(4.0) * mI / 1_000_000.0 }

        }

        // Engine always returns calibration_total=0 and calibration_used=0 (known limitation).
        // Override from dogma attributes: attr 1132 = upgradeCapacity (ship calibration total),
        // attr 1153 = upgradeCost (rig calibration cost per module).
        if stats.calibrationTotal == 0 {
            let total = shipType.dogmaAttributes?.first(where: { $0.attributeId == 1132 })?.value ?? 0
            if total > 0 {
                let used = slots
                    .filter { $0.category == .rig && $0.isOnline }
                    .compactMap { slot -> Double? in
                        guard let tid = slot.moduleTypeId,
                              let t = moduleTypes[tid] else { return nil }
                        return t.dogmaAttributes?.first(where: { $0.attributeId == 1153 })?.value
                    }
                    .reduce(0, +)
                stats.calibrationTotal = total
                stats.calibrationUsed = used
            }
        }

        // Guard against genuine engine wrong-sign anomalies where an active module's effect
        // inverts scan resolution catastrophically. Shield extenders legitimately reduce scan
        // resolution by ~10% each (stacked), so up to ~25% below base is normal. Only
        // override when the value collapses below 50% of base — a real anomaly threshold.
        let baseScanRes = shipType.dogmaAttributes?.first(where: { $0.attributeId == 564 })?.value ?? 0
        if baseScanRes > 0 && stats.scanResolution < baseScanRes * 0.50 {
            let clean = DogmaEngine.shared.calculate(
                shipTypeId: shipType.typeId, slots: [], skills: characterSkills,
                implantTypeIds: includeImplants ? implantTypeIds : []
            )
            Logger.dogmaEngine.warning("[Sim] Scan resolution anomaly: engine=\(self.stats.scanResolution, privacy: .public) base=\(baseScanRes, privacy: .public) — overriding with no-module value=\(clean.scanResolution, privacy: .public)")
            stats.scanResolution = clean.scanResolution
        }
    }

    // Runs a bare-ship engine call once per ship type to measure calibration factors for
    // stats where the engine's SDE may diverge from EVE's live data.
    //   warpInflationFactor = bare.warpSpeed / attr600  (corrects engine warp inflation)
    //   inertiaAlignFactor  = attr70 / bare.inertiaMod  (corrects stale SDE base inertia)
    private func refreshWarpCalibration(for shipType: ESIType) {
        guard DogmaEngine.shared.isReady,
              cachedCalibrationShipId != shipType.typeId,
              let attr600 = shipType.dogmaAttributes?.first(where: { $0.attributeId == 600 })?.value,
              attr600 > 0
        else { return }

        let bare = DogmaEngine.shared.calculate(
            shipTypeId: shipType.typeId, slots: [], skills: [:], implantTypeIds: []
        )
        guard bare.warpSpeed > 0 else {
            Logger.dogmaEngine.error("[Sim] Bare warp=0 for typeId=\(shipType.typeId, privacy: .public) — calibration skipped")
            return
        }

        let factor = bare.warpSpeed / attr600
        guard (0.01...1000.0).contains(factor) else {
            Logger.dogmaEngine.error("[Sim] Inflation factor \(factor, privacy: .public) out of range for typeId=\(shipType.typeId, privacy: .public) (bare=\(bare.warpSpeed, privacy: .public) attr600=\(attr600, privacy: .public))")
            return
        }
        warpInflationFactor = factor
        Logger.dogmaEngine.info("[Sim] Warp calibration typeId=\(shipType.typeId, privacy: .public): attr600=\(attr600, privacy: .public) bare=\(bare.warpSpeed, privacy: .public) factor=\(factor, privacy: .public)")

        // Inertia (attr 70): ESI base / bare engine result corrects stale SDE values.
        if let attr70 = shipType.dogmaAttributes?.first(where: { $0.attributeId == 70 })?.value,
           attr70 > 0, bare.inertiaMod > 0 {
            inertiaAlignFactor = attr70 / bare.inertiaMod
            Logger.dogmaEngine.info("[Sim] Inertia calibration typeId=\(shipType.typeId, privacy: .public): attr70=\(attr70, privacy: .public) bare=\(bare.inertiaMod, privacy: .public) factor=\(self.inertiaAlignFactor, privacy: .public)")
        } else {
            inertiaAlignFactor = 1.0
        }

        cachedCalibrationShipId = shipType.typeId
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
            implantTypes = [:]
            implantAttrMultipliers = [:]
            recomputeStats()
            return
        }
        implantTypeIds = ids
        implantTypes = await UniverseCache.shared.types(ids: ids)
        implantAttrMultipliers = await computeImplantAttrMultipliers()
        recomputeStats()
    }

    // Traces each implant's dogma effect chain and collects multipliers for every ship
    // attribute in engineSkippedImplantAttrs (attrs the engine does not apply from implants).
    //
    // ESIDogmaModifier.function (JSON "func") holds the modifier scope type — NOT the math
    // operation. Math is in operatorId (JSON "operator"):
    //   0=PreAssign, 1=PreMul, 2=PreDiv, 3=ModAdd, 4=ModSub,
    //   5=PostMul, 6=PostPercent, 7=PostDiv, 8=RevPostPercent
    private func computeImplantAttrMultipliers() async -> [Int: Double] {
        guard !implantTypeIds.isEmpty else { return [:] }
        let allEffectIds = Set(implantTypeIds.flatMap { id in
            (implantTypes[id]?.dogmaEffects ?? []).map(\.effectId)
        })
        guard !allEffectIds.isEmpty else { return [:] }
        let effectMap = await UniverseCache.shared.effectDetails(ids: allEffectIds)
        Logger.dogmaEngine.info("[Sim] Implant chain: implants=\(self.implantTypeIds.count, privacy: .public) effectIds=\(allEffectIds.count, privacy: .public) fetched=\(effectMap.count, privacy: .public)")
        var multipliers: [Int: Double] = [:]
        for id in implantTypeIds {
            guard let t = implantTypes[id] else { continue }
            for eff in (t.dogmaEffects ?? []) {
                guard let detail = effectMap[eff.effectId] else { continue }
                for mod in detail.modifiers {
                    guard let attrId = mod.modifiedAttributeId,
                          Self.engineSkippedImplantAttrs.contains(attrId),
                          let srcId = mod.modifyingAttributeId,
                          let srcVal = t.dogmaAttributes?.first(where: { $0.attributeId == srcId })?.value,
                          srcVal != 0 else { continue }
                    var factor = multipliers[attrId] ?? 1.0
                    switch mod.operatorId ?? -1 {
                    case 6: factor *= (1.0 + srcVal / 100.0)   // PostPercent
                    case 8: factor *= (1.0 - srcVal / 100.0)   // RevPostPercent
                    case 5, 1: factor *= srcVal                 // PostMul / PreMul
                    case 7, 2: factor /= srcVal                 // PostDiv / PreDiv
                    default: break
                    }
                    multipliers[attrId] = factor
                }
            }
        }
        if !multipliers.isEmpty {
            Logger.dogmaEngine.info("[Sim] Implant attr multipliers: \(multipliers, privacy: .public)")
        }
        return multipliers
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
