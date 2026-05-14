//
// SimulateFittingView.swift
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
import UniformTypeIdentifiers

// MARK:  Module Drag Payload

// JSON-encoded payload carried over UTType.json — no Info.plist registration needed.
struct SimModuleDrag: Codable, Sendable {
    let typeId: Int
    let category: SimSlotCategory

    func makeItemProvider() -> NSItemProvider {
        let provider = NSItemProvider()
        if let data = try? JSONEncoder().encode(self) {
            provider.registerDataRepresentation(
                forTypeIdentifier: UTType.json.identifier,
                visibility: .all
            ) { completion in completion(data, nil); return nil }
        }
        return provider
    }

}

// MARK:  Slot Category

enum SimSlotCategory: String, CaseIterable, Equatable, Codable {
    case high, medium, low, rig, subsystem

    var displayName: String {
        switch self {
        case .high:      "High Slots"
        case .medium:    "Med Slots"
        case .low:       "Low Slots"
        case .rig:       "Rig Slots"
        case .subsystem: "Subsystems"
        }
    }

    var color: Color {
        switch self {
        case .high:      .orange
        case .medium:    .cyan
        case .low:       .yellow
        case .rig:       .green
        case .subsystem: .purple
        }
    }

    var icon: String {
        switch self {
        case .high:      "bolt.fill"
        case .medium:    "antenna.radiowaves.left.and.right"
        case .low:       "shield.lefthalf.filled"
        case .rig:       "gearshape.2.fill"
        case .subsystem: "cpu.fill"
        }
    }

    var flagPrefix: String {
        switch self {
        case .high:      "HiSlot"
        case .medium:    "MedSlot"
        case .low:       "LoSlot"
        case .rig:       "RigSlot"
        case .subsystem: "SubSystem"
        }
    }

}

// MARK:  Sim Slot

struct SimSlot: Identifiable, Equatable {
    let id: UUID
    let category: SimSlotCategory
    let index: Int
    var moduleTypeId: Int?

    init(category: SimSlotCategory, index: Int, moduleTypeId: Int? = nil) {
        self.id = UUID()
        self.category = category
        self.index = index
        self.moduleTypeId = moduleTypeId
    }

    var flag: String { "\(category.flagPrefix)\(index)" }
    var isEmpty: Bool { moduleTypeId == nil }

    static func == (lhs: SimSlot, rhs: SimSlot) -> Bool { lhs.id == rhs.id }
}

// MARK:  Sim Resists

struct SimResists {
    var em: Double = 0
    var explosive: Double = 0
    var kinetic: Double = 0
    var thermal: Double = 0
    var average: Double { (em + explosive + kinetic + thermal) / 4 }
}

// MARK:  Implant Contribution

struct ImplantContribution: Identifiable {
    let typeId: Int
    let name: String
    let bonuses: [String]
    var id: Int { typeId }
}

// MARK:  Sim Stats

struct SimStats {
    var shieldHP: Double = 0
    var armorHP: Double = 0
    var hullHP: Double = 0
    var shieldResists = SimResists()
    var armorResists = SimResists()
    var hullResists = SimResists()
    var ehp: Double = 0
    var maxVelocity: Double = 0
    var alignTime: Double = 0
    var signatureRadius: Double = 0
    var capacitorCapacity: Double = 0
    var rechargeRateSec: Double = 0
    var shieldRechargeTimeSec: Double = 0
    var maxTargetRange: Double = 0
    var scanResolution: Double = 0
    var mass: Double = 0
    var inertiaMod: Double = 0
    var warpSpeed: Double = 0
    var maxLockedTargets: Double = 0
    var sensorStrength: Double = 0
    // Fitting resources
    var cpuUsed: Double = 0
    var cpuTotal: Double = 0
    var powerUsed: Double = 0
    var powerTotal: Double = 0
    var calibrationUsed: Double = 0
    var calibrationTotal: Double = 0
    var hasData: Bool { shieldHP > 0 || armorHP > 0 || hullHP > 0 }
    var implantContributions: [ImplantContribution] = []
}

// MARK:  Dogma Attribute IDs
// Values sourced from EVE SDE. Stats show base ship values without module bonuses.

private enum DogmaAttr {
    static let hiSlots           = 14   // attr 14 = High Slots
    static let medSlots          = 13   // attr 13 = Medium Slots
    static let loSlots           = 12   // attr 12 = Low Slots
    static let rigSlots          = 1137
    static let subsystemSlots    = 1367
    static let mass              = 4
    static let shieldCapacity    = 263  // Shield HP
    static let armorHP           = 265  // Armor HP
    static let hullHP            = 9    // Hull/Structure HP
    static let agility           = 70   // attr 70 = Inertia Modifier
    static let maxVelocity       = 37   // attr 37 = Maximum Velocity
    static let capacitorCapacity    = 482   // Capacitor Capacity (GJ)
    static let capacitorRechargeTime = 55   // Capacitor Recharge Time (ms)
    static let shieldRechargeRate   = 479   // Shield Recharge Time (ms)
    static let maxTargetRange    = 76
    static let signatureRadius   = 552  // attr 552 = Signature Radius (m)
    static let scanResolution    = 564  // Scan Resolution (mm)
    static let shieldEmRes       = 271  // Shield EM damage resonance
    static let shieldExpRes      = 272  // Shield Explosive damage resonance
    static let shieldKinRes      = 273  // Shield Kinetic damage resonance
    static let shieldThermRes    = 274  // Shield Thermal damage resonance
    static let armorEmRes        = 267  // Armor EM damage resonance
    static let armorExpRes       = 268  // Armor Explosive damage resonance
    static let armorKinRes       = 269  // Armor Kinetic damage resonance
    static let armorThermRes     = 270  // Armor Thermal damage resonance
    static let hullEmRes         = 113  // attr 113 = Hull EM damage resonance
    static let hullExpRes        = 109  // attr 109 = Hull Explosive damage resonance
    static let hullKinRes        = 110  // attr 110 = Hull Kinetic damage resonance
    static let hullThermRes      = 111  // attr 111 = Hull Thermal damage resonance
    // Fitting resources
    static let powerOutput       = 11   // ship power grid total (MW)
    static let power             = 30   // module power grid cost (MW)
    static let cpuOutput         = 48   // attr 48 = CPU Output (tf)
    static let cpu               = 50   // module CPU cost (tf)
    static let upgradeCapacity       = 1130 // ship calibration total
    static let upgradeCost           = 1132 // rig calibration cost
    static let warpSpeed             = 192  // Warp Speed (AU/s)
    static let maxLockedTargets      = 600  // attr 600 = Max Locked Targets
    static let radarStrength         = 208
    static let ladarStrength         = 209
    static let magnetometricStrength = 210
    static let gravimetricStrength   = 211

    static let allResistances: Set<Int> = [267, 268, 269, 270, 271, 272, 273, 274, 109, 110, 111, 113]
}

// MARK:  Stats Calculator

struct SimStatsCalculator {

    // Dogma operator IDs from EVE SDE.
    // Stacking penalties apply to preMul(1), preDiv(2), postPercent(8), postMul(9), postDiv(10).
    // modAdd(6) and modSub(7) are never stacking-penalised.
    private enum Op {
        static let preAssign   = 5
        static let modAdd      = 6
        static let modSub      = 7
        static let addRate     = 3
        static let subRate     = 4
        static let preMul      = 1
        static let preDiv      = 2
        static let postPercent = 8
        static let postMul     = 9
        static let postDiv     = 10
        static let postAssign  = 11
        static let applyOrder  = [5, 6, 7, 3, 4, 1, 2, 8, 9, 10, 11]
        static let stackPenalised: Set<Int> = [1, 2, 8, 9, 10]
    }

    // e^-(rank/2.67)² — EVE's official stacking-penalty formula.
    private static func penalty(_ rank: Int) -> Double { exp(-pow(Double(rank) / 2.67, 2)) }

    /// Compute ship stats using the full EVE dogma modifier system.
    ///
    /// `effectCache` maps effect IDs → their ESI modifier records.
    /// For any module whose effects are not yet cached the calculator falls back
    /// to a simple heuristic so the panel always shows something useful while
    /// effect details load in the background.
    static func compute(
        shipType: ESIType,
        fittedModules: [ESIType] = [],
        implants: [ESIType] = [],
        effectCache: [Int: ESIDogmaEffectDetail] = [:]
    ) -> SimStats {
        // 1 ── Build mutable attribute map from ship base values.
        //      Resistance attributes default to 1.0 (0 % resist) if absent.
        var attrs: [Int: Double] = [:]
        for a in shipType.dogmaAttributes ?? [] { attrs[a.attributeId] = a.value }

#if DEBUG
        print("[Sim] Ship '\(shipType.name)' ALL attrs (\(attrs.count)): \(attrs.sorted { $0.key < $1.key })")
#endif

        // 2 ── Collect modifier records from every fitted module.
        //      pending[targetAttrId][op] = [sourceValues…]
        var pending: [Int: [Int: [Double]]] = [:]
        var fallbackModules: [ESIType] = []

        for mod in fittedModules + implants {
            let modAttrMap = Dictionary(
                uniqueKeysWithValues: (mod.dogmaAttributes ?? []).map { ($0.attributeId, $0.value) }
            )
            var resolvedAny = false

            for effect in mod.dogmaEffects ?? [] {
                guard let detail = effectCache[effect.effectId] else { continue }
                resolvedAny = true
                for m in detail.modifiers {
                    let knownFunc = m.function == "LocationModifier"
                                 || m.function == "LocationRequiredSkillModifier"
                                 || m.function == "ItemModifier"
                    guard knownFunc,
                          m.domain == "shipID",
                          let tgt  = m.modifiedAttributeId,
                          let src  = m.modifyingAttributeId,
                          let op   = m.operatorId else { continue }
                    // Source value: prefer module's own attribute, fall back to ship's current
                    // attribute (needed for some Abyssal/mutated module effect chains).
                    guard let val = modAttrMap[src] ?? attrs[src] else {
#if DEBUG
                        let hpResistAttrs: Set<Int> = [9, 263, 265, 267, 268, 269, 270, 271, 272, 273, 274, 109, 110, 111, 113]
                        if hpResistAttrs.contains(tgt) {
                            let modKeys = (mod.dogmaAttributes ?? []).map(\.attributeId).sorted()
                            print("[Sim] SKIP '\(mod.name)' eff=\(effect.effectId) tgt=\(tgt) src=\(src) op=\(op) — srcNotInMap; moduleAttrs=\(modKeys)")
                        }
#endif
                        continue
                    }
#if DEBUG
                    let hpResistAttrs: Set<Int> = [9, 70, 265, 267, 268, 269, 270, 271, 272, 273, 274, 479, 480, 481, 482]
                    if hpResistAttrs.contains(tgt) {
                        let fromModule = modAttrMap[src] != nil
                        print("[Sim] APPLY '\(mod.name)' eff=\(effect.effectId) tgt=\(tgt) src=\(src) op=\(op) val=\(val) from:\(fromModule ? "module" : "ship")")
                    }
#endif
                    pending[tgt, default: [:]][op, default: []].append(val)
                }
            }
            if !resolvedAny { fallbackModules.append(mod) }
        }

        // 3 ── Apply dogma modifiers in the standard evaluation order.
        for (attrId, opGroups) in pending {
            let isResist = DogmaAttr.allResistances.contains(attrId)
            var base = attrs[attrId] ?? (isResist ? 1.0 : 0.0)

            for op in Op.applyOrder {
                guard var vals = opGroups[op] else { continue }

                if Op.stackPenalised.contains(op) {
                    // Sort largest absolute effect first so the best bonus takes rank 0.
                    vals.sort { abs($0 - 1.0) > abs($1 - 1.0) }
                }

                switch op {
                case Op.preAssign, Op.postAssign:
                    base = vals.first ?? base

                case Op.modAdd:
                    base += vals.reduce(0, +)

                case Op.modSub:
                    base -= vals.reduce(0, +)

                case Op.addRate:
                    base *= 1.0 + vals.reduce(0, +) / 100.0

                case Op.subRate:
                    base *= 1.0 - vals.reduce(0, +) / 100.0

                case Op.preMul, Op.postMul:
                    for (i, v) in vals.enumerated() {
                        base *= 1.0 + (v - 1.0) * penalty(i)
                    }

                case Op.preDiv, Op.postDiv:
                    for (i, v) in vals.enumerated() where v != 0 {
                        base /= 1.0 + (v - 1.0) * penalty(i)
                    }

                case Op.postPercent:
                    vals.sort { abs($0) > abs($1) }
                    for (i, v) in vals.enumerated() {
                        base *= 1.0 + v * penalty(i) / 100.0
                    }

                default: break
                }
            }
            attrs[attrId] = base
        }

        // 4 ── Fitting resource usage — read directly from each module's own attributes.
        //      These don't go through dogma modifier chains (skills are ignored in the sim),
        //      so they are available immediately even before effect details are cached.
        var cpuUsed = 0.0
        var powerUsed = 0.0
        var calibrationUsed = 0.0
        for mod in fittedModules {
            let mAttrs = mod.dogmaAttributes ?? []
            func mv(_ id: Int) -> Double { mAttrs.first { $0.attributeId == id }?.value ?? 0 }
            cpuUsed         += mv(DogmaAttr.cpu)
            powerUsed       += mv(DogmaAttr.power)
            calibrationUsed += mv(DogmaAttr.upgradeCost)
        }

        // 5 ── Extract SimStats from the computed attribute map.
        func a(_ id: Int) -> Double { attrs[id] ?? 0 }
        func r(_ id: Int) -> Double { attrs[id] ?? 1.0 }

        var s = SimStats()
        s.shieldHP          = a(DogmaAttr.shieldCapacity)
        s.armorHP           = a(DogmaAttr.armorHP)
        s.hullHP            = a(DogmaAttr.hullHP)
        s.mass              = a(DogmaAttr.mass)
        s.maxVelocity       = a(DogmaAttr.maxVelocity)
        s.signatureRadius   = a(DogmaAttr.signatureRadius)
        s.capacitorCapacity = a(DogmaAttr.capacitorCapacity)
        s.rechargeRateSec        = a(DogmaAttr.capacitorRechargeTime) / 1000  // ESI returns ms, convert to s
        s.shieldRechargeTimeSec  = a(DogmaAttr.shieldRechargeRate) / 1000
        s.maxTargetRange    = a(DogmaAttr.maxTargetRange)
        s.scanResolution    = a(DogmaAttr.scanResolution)
        s.inertiaMod        = a(DogmaAttr.agility)
        s.warpSpeed         = a(DogmaAttr.warpSpeed)
        s.maxLockedTargets  = a(DogmaAttr.maxLockedTargets)
        s.sensorStrength    = [DogmaAttr.radarStrength, DogmaAttr.ladarStrength,
                               DogmaAttr.magnetometricStrength, DogmaAttr.gravimetricStrength]
                               .map { a($0) }.max() ?? 0
        s.cpuUsed           = cpuUsed
        s.cpuTotal          = a(DogmaAttr.cpuOutput)
        s.powerUsed         = powerUsed
        s.powerTotal        = a(DogmaAttr.powerOutput)
        s.calibrationUsed   = calibrationUsed
        s.calibrationTotal  = a(DogmaAttr.upgradeCapacity)

        let agility = a(DogmaAttr.agility)
        if s.mass > 0 && agility > 0 {
            s.alignTime = -log(0.25) * s.mass * agility / 1_000_000
        }

        s.shieldResists = SimResists(
            em:        (1 - r(DogmaAttr.shieldEmRes))    * 100,
            explosive: (1 - r(DogmaAttr.shieldExpRes))   * 100,
            kinetic:   (1 - r(DogmaAttr.shieldKinRes))   * 100,
            thermal:   (1 - r(DogmaAttr.shieldThermRes)) * 100
        )
        s.armorResists = SimResists(
            em:        (1 - r(DogmaAttr.armorEmRes))  * 100,
            explosive: (1 - r(DogmaAttr.armorExpRes)) * 100,
            kinetic:   (1 - r(DogmaAttr.armorKinRes)) * 100,
            thermal:   (1 - r(DogmaAttr.armorThermRes)) * 100
        )
        s.hullResists = SimResists(
            em:        (1 - r(DogmaAttr.hullEmRes))  * 100,
            explosive: (1 - r(DogmaAttr.hullExpRes)) * 100,
            kinetic:   (1 - r(DogmaAttr.hullKinRes)) * 100,
            thermal:   (1 - r(DogmaAttr.hullThermRes)) * 100
        )

        s.ehp = ehpFor(hp: s.shieldHP, resists: s.shieldResists)
              + ehpFor(hp: s.armorHP,  resists: s.armorResists)
              + ehpFor(hp: s.hullHP,   resists: s.hullResists)

#if DEBUG
        if !fittedModules.isEmpty {
            print("[Sim] Computed HP — ship=\(shipType.name)[\(shipType.typeId)] shield=\(s.shieldHP) armor=\(s.armorHP) hull=\(s.hullHP) mass=\(attrs[4] ?? -1) agility=\(attrs[70] ?? -1) modules=[\(fittedModules.map(\.name).joined(separator: ", "))]")
        }
#endif

        s.implantContributions = implants.compactMap { implant in
            let bonuses = describeImplantBonuses(implant: implant, effectCache: effectCache)
            return bonuses.isEmpty ? nil : ImplantContribution(typeId: implant.typeId, name: implant.name, bonuses: bonuses)
        }

        return s
    }

    private static func ehpFor(hp: Double, resists: SimResists) -> Double {
        let avg = resists.average / 100
        guard avg < 1 else { return hp }
        return hp / (1 - avg)
    }

    // Human-readable names for ship attributes we surface in the implant list.
    private static let trackedAttrDisplay: [Int: String] = [
        11:  "Power Grid",
        48:  "CPU Output",
        263: "Shield HP",
        265: "Armor HP",
        9:   "Hull HP",
        37:  "Max Velocity",
        70:  "Agility",
        192: "Warp Speed",
        482: "Capacitor",
        55:  "Cap Recharge",
        76:  "Target Range",
        564: "Scan Resolution",
        552: "Signature Radius",
        271: "Shield EM Resist",
        272: "Shield Explosive Resist",
        273: "Shield Kinetic Resist",
        274: "Shield Thermal Resist",
        267: "Armor EM Resist",
        268: "Armor Explosive Resist",
        269: "Armor Kinetic Resist",
        270: "Armor Thermal Resist",
        113: "Hull EM Resist",
        109: "Hull Explosive Resist",
        110: "Hull Kinetic Resist",
        111: "Hull Thermal Resist",
    ]

    static func describeImplantBonuses(
        implant: ESIType,
        effectCache: [Int: ESIDogmaEffectDetail]
    ) -> [String] {
        let modAttrMap = Dictionary(
            uniqueKeysWithValues: (implant.dogmaAttributes ?? []).map { ($0.attributeId, $0.value) }
        )
        var seen = Set<String>()
        var result: [String] = []
        for effect in implant.dogmaEffects ?? [] {
            guard let detail = effectCache[effect.effectId] else { continue }
            for m in detail.modifiers {
                let knownFunc = m.function == "LocationModifier"
                             || m.function == "LocationRequiredSkillModifier"
                             || m.function == "ItemModifier"
                guard knownFunc,
                      m.domain == "shipID",
                      let tgt   = m.modifiedAttributeId,
                      let src   = m.modifyingAttributeId,
                      let op    = m.operatorId,
                      let label = trackedAttrDisplay[tgt],
                      let val   = modAttrMap[src] else { continue }
                if let desc = formatImplantBonus(label: label, attrId: tgt, op: op, value: val),
                   seen.insert(desc).inserted {
                    result.append(desc)
                }
            }
        }
        return result
    }

    private static func formatImplantBonus(label: String, attrId: Int, op: Int, value: Double) -> String? {
        let isResist = DogmaAttr.allResistances.contains(attrId)
        switch op {
        case Op.postPercent:
            // Resist attrs store a negative percentage (reduce resonance = improve resist).
            let pct = isResist ? -value : value
            guard abs(pct) >= 0.01 else { return nil }
            return String(format: "%+.1f%% \(label)", pct)
        case Op.preMul, Op.postMul:
            let pct = isResist ? (1.0 - value) * 100 : (value - 1.0) * 100
            guard abs(pct) >= 0.01 else { return nil }
            return String(format: "%+.1f%% \(label)", pct)
        case Op.preDiv, Op.postDiv:
            guard value != 0 else { return nil }
            let pct = isResist ? (1.0 - 1.0 / value) * 100 : (1.0 / value - 1.0) * 100
            guard abs(pct) >= 0.01 else { return nil }
            return String(format: "%+.1f%% \(label)", pct)
        case Op.modAdd:
            guard abs(value) >= 0.001 else { return nil }
            return String(format: "%+.1f \(label)", value)
        case Op.modSub:
            guard abs(value) >= 0.001 else { return nil }
            return String(format: "%.1f \(label)", -value)
        default:
            return nil
        }
    }
}

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
        shipClassName = CharacterFittingsView.eveShipGroups[t.groupId] ?? ""
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
        for i in 0..<count(DogmaAttr.hiSlots)       { result.append(SimSlot(category: .high,      index: i)) }
        for i in 0..<count(DogmaAttr.medSlots)      { result.append(SimSlot(category: .medium,    index: i)) }
        for i in 0..<count(DogmaAttr.loSlots)       { result.append(SimSlot(category: .low,       index: i)) }
        for i in 0..<count(DogmaAttr.rigSlots)      { result.append(SimSlot(category: .rig,       index: i)) }
        for i in 0..<count(DogmaAttr.subsystemSlots) { result.append(SimSlot(category: .subsystem, index: i)) }
        return result
    }

    func recomputeStats() {
        guard let shipType else { stats = SimStats(); return }
        let fitted = slots.compactMap { $0.moduleTypeId }.compactMap { moduleTypes[$0] }
        let activeImplants = includeImplants ? implantTypes : []
        stats = SimStatsCalculator.compute(shipType: shipType, fittedModules: fitted, implants: activeImplants, effectCache: effectDetailsCache)
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

    /// Pre-fetch dogma effect details for all currently fitted modules, then recompute.
    /// Called after placing modules so full dogma replaces the base-only stats.
    func prefetchFittedEffects() {
        let fittedTypes = slots.compactMap { $0.moduleTypeId }.compactMap { moduleTypes[$0] }
        let effectIds = Set((fittedTypes + implantTypes).flatMap { $0.dogmaEffects?.map(\.effectId) ?? [] })
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

// MARK:  Main View

// Walks the AppKit view hierarchy to set autosaveName on the backing NSSplitView,
// which makes macOS persist and restore each divider position automatically.
private struct SplitViewAutosave: NSViewRepresentable {
    let name: String
    func makeNSView(context: Context) -> NSView {
        let v = NSView()
        DispatchQueue.main.async { Self.apply(to: v, name: name) }
        return v
    }
    func updateNSView(_ nsView: NSView, context: Context) {}
    private static func apply(to view: NSView, name: String) {
        var candidate: NSView? = view.superview
        while let v = candidate {
            if let split = v as? NSSplitView {
                split.autosaveName = NSSplitView.AutosaveName(name)
                return
            }
            candidate = v.superview
        }
    }
}

struct SimulateFittingView: View {
    @State private var simState = SimulatorState()
    @Environment(AccountManager.self) private var accountManager

    var body: some View {
        HSplitView {
            SimLeftPanel()
                .frame(minWidth: 220, idealWidth: 260, maxWidth: 320)
                .environment(simState)

            SimFittingDiagram()
                .frame(minWidth: 380)
                .environment(simState)

            SimStatsPanel()
                .frame(minWidth: 280, idealWidth: 300, maxWidth: 360)
                .environment(simState)
        }
        .background(SplitViewAutosave(name: "SimulateFittingView.split"))
        .task { await simState.loadImplants(accountManager: accountManager) }
        .onChange(of: accountManager.selectedAccount?.characterID) { _, _ in
            Task { await simState.loadImplants(accountManager: accountManager) }
        }
    }
}

// MARK:  Left Panel

private enum LeftPanelMode { case ships, modules }

// Dogma effect IDs that identify which slot a module occupies
private enum SlotEffect {
    static let high: Int       = 11
    static let low: Int        = 12
    static let medium: Int     = 13
    static let rig: Int        = 2663
    static let subsystem: Int  = 3772

    static func category(from effects: [ESIDogmaEffect]) -> SimSlotCategory? {
        let ids = Set(effects.map(\.effectId))
        if ids.contains(high)      { return .high }
        if ids.contains(medium)    { return .medium }
        if ids.contains(low)       { return .low }
        if ids.contains(rig)       { return .rig }
        if ids.contains(subsystem) { return .subsystem }
        return nil
    }
}

struct SimLeftPanel: View {
    @Environment(SimulatorState.self) private var simState
    @Environment(AccountManager.self) private var accountManager

    // Ship browser
    @State private var allShipSections: [(className: String, ships: [ESIType])] = []
    @State private var isLoadingShips = false
    @State private var shipSearchText = ""
    @AppStorage("simulateCollapsedShipSections") private var collapsedSectionsRaw: String = ""

    // Module browser
    @State private var allModuleSections: [(category: SimSlotCategory, modules: [ESIType])] = []
    @State private var isLoadingModules = false
    @State private var moduleFilterText = ""
    @AppStorage("simulateCollapsedModuleSections") private var collapsedModuleSectionsRaw: String = ""
    @State private var noSlotMessage: String?

    @State private var leftMode: LeftPanelMode = .ships
    @State private var showLoadSheet = false

    private var filteredShipSections: [(className: String, ships: [ESIType])] {
        let q = shipSearchText.lowercased().trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return allShipSections }
        return allShipSections.compactMap { section in
            let filtered = section.ships.filter { $0.name.lowercased().contains(q) }
            return filtered.isEmpty ? nil : (className: section.className, ships: filtered)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            if leftMode == .modules {
                allModulesBrowser
            } else {
                shipBrowser
            }
        }
        .sheet(isPresented: $showLoadSheet) {
            SimLoadFittingSheet()
                .environment(simState)
                .environment(accountManager)
        }
        .task {
            await loadAllShips()
            if simState.shipTypeId != nil {
                leftMode = .modules
                await loadAllModules()
            }
        }
        .onChange(of: simState.shipTypeId) { _, newId in
            withAnimation(.easeInOut(duration: 0.15)) {
                leftMode = newId != nil ? .modules : .ships
            }
            if newId != nil { Task { await loadAllModules() } }
        }
        .onChange(of: simState.activeSlotId) { _, newId in
            if newId != nil && simState.shipTypeId != nil {
                withAnimation(.easeInOut(duration: 0.15)) { leftMode = .modules }
            }
        }
    }

    // MARK: Ship Browser

    private var shipBrowser: some View {
        VStack(spacing: 0) {
            searchBar(text: $shipSearchText, placeholder: "Filter ships…") { _ in }

            Button { showLoadSheet = true } label: {
                Label("Load from Saved Fitting or Ship…", systemImage: "square.and.arrow.down")
                    .font(.caption).frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderless)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 10)
            .padding(.bottom, 8)

            Divider()

            if isLoadingShips {
                VStack(spacing: 8) {
                    ProgressView()
                    Text("Loading ship database…").font(.caption).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if filteredShipSections.isEmpty {
                emptyState(shipSearchText.isEmpty ? "No ships" : "No ships match \"\(shipSearchText)\"")
            } else {
                List {
                    ForEach(filteredShipSections, id: \.className) { section in
                        Section(isExpanded: Binding(
                            get: { !collapsedSectionsRaw.components(separatedBy: "\n").contains(section.className) },
                            set: { expanded in
                                var set = Set(collapsedSectionsRaw.components(separatedBy: "\n").filter { !$0.isEmpty })
                                if expanded { set.remove(section.className) } else { set.insert(section.className) }
                                collapsedSectionsRaw = set.joined(separator: "\n")
                            }
                        )) {
                            ForEach(section.ships, id: \.typeId) { type in
                                SimShipRow(type: type)
                                    .contentShape(Rectangle())
                                    .onTapGesture {
                                        Task { await simState.selectShip(typeId: type.typeId) }
                                    }
                            }
                        } header: {
                            HStack(spacing: 6) {
                                Image(systemName: CharacterFittingsView.shipClassIcon(section.className))
                                    .font(.caption2).foregroundStyle(.secondary)
                                Text(section.className).font(.subheadline.bold())
                                Spacer()
                                Text("\(section.ships.count)")
                                    .font(.caption.monospacedDigit()).foregroundStyle(.tertiary)
                            }
                        }
                    }
                }
                .listStyle(.sidebar)
            }
        }
    }

    // MARK: All-Modules Browser

    private var allModulesBrowser: some View {
        VStack(spacing: 0) {
            // Header
            HStack(spacing: 8) {
                Button {
                    simState.activeSlotId = nil
                    withAnimation(.easeInOut(duration: 0.15)) { leftMode = .ships }
                } label: {
                    Label("Ships", systemImage: "chevron.left").font(.caption.bold())
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)

                Spacer()

                if !simState.shipName.isEmpty {
                    VStack(alignment: .trailing, spacing: 1) {
                        Text(simState.shipName).font(.caption.bold()).lineLimit(1)
                        if !simState.shipClassName.isEmpty {
                            Text(simState.shipClassName).font(.caption2).foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .padding(.horizontal, 10).padding(.vertical, 8)

            // Slot targeting indicator
            if let active = simState.activeSlot {
                HStack(spacing: 6) {
                    Image(systemName: active.category.icon)
                        .font(.caption2).foregroundStyle(active.category.color)
                    Text("Targeting \(active.category.displayName) · slot \(active.index + 1)")
                        .font(.caption2).foregroundStyle(active.category.color)
                    Spacer()
                    Button {
                        simState.activeSlotId = nil
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.caption2).foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 10).padding(.vertical, 5)
                .background(active.category.color.opacity(0.08))
            }

            Divider()
            searchBar(text: $moduleFilterText, placeholder: "Filter modules…") { _ in }
            Divider()

            if isLoadingModules {
                VStack(spacing: 8) {
                    ProgressView()
                    Text("Loading module database…").font(.caption).foregroundStyle(.secondary)
                    Text("First launch only — cached for 7 days")
                        .font(.caption2).foregroundStyle(.tertiary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if allModuleSections.isEmpty {
                emptyState("No modules available")
            } else {
                ZStack(alignment: .bottom) {
                    List {
                        ForEach(allModuleSections, id: \.category) { section in
                            let filtered = filterModules(section.modules)
                            let totalSlots = simState.slots.filter { $0.category == section.category }.count
                            let usedSlots  = simState.slots.filter { $0.category == section.category && !$0.isEmpty }.count
                            if !filtered.isEmpty || moduleFilterText.isEmpty {
                                Section(isExpanded: Binding(
                                    get: { !collapsedModuleSectionsRaw.components(separatedBy: "\n").contains(section.category.displayName) },
                                    set: { expanded in
                                        var set = Set(collapsedModuleSectionsRaw.components(separatedBy: "\n").filter { !$0.isEmpty })
                                        if expanded { set.remove(section.category.displayName) } else { set.insert(section.category.displayName) }
                                        collapsedModuleSectionsRaw = set.joined(separator: "\n")
                                    }
                                )) {
                                    ForEach(filtered, id: \.typeId) { type in
                                        let drag = SimModuleDrag(typeId: type.typeId, category: section.category)
                                        SimModuleRow(type: type)
                                            .contentShape(Rectangle())
                                            .opacity(totalSlots == 0 || usedSlots >= totalSlots ? 0.4 : 1.0)
                                            .onDrag({
                                                simState.draggingCategory = drag.category
                                                simState.pendingDropPayload = drag
                                                return drag.makeItemProvider()
                                            }, preview: {
                                                SimModuleDragPreview(type: type, category: section.category)
                                            })
                                            .onTapGesture {
                                                Task { await selectModule(type: type, category: section.category) }
                                            }
                                    }
                                } header: {
                                    HStack(spacing: 6) {
                                        Image(systemName: section.category.icon)
                                            .font(.caption2).foregroundStyle(section.category.color)
                                        Text(section.category.displayName).font(.subheadline.bold())
                                        Spacer()
                                        if totalSlots > 0 {
                                            Text("\(usedSlots)/\(totalSlots)")
                                                .font(.caption.monospacedDigit())
                                                .foregroundStyle(usedSlots >= totalSlots
                                                    ? Color.secondary
                                                    : section.category.color.opacity(0.85))
                                        }
                                    }
                                }
                            }
                        }
                    }
                    .listStyle(.sidebar)

                    if let msg = noSlotMessage {
                        Text(msg)
                            .font(.caption.bold())
                            .padding(.horizontal, 12).padding(.vertical, 7)
                            .background(.ultraThinMaterial, in: Capsule())
                            .padding(.bottom, 10)
                            .transition(.move(edge: .bottom).combined(with: .opacity))
                    }
                }
                .animation(.easeInOut(duration: 0.2), value: noSlotMessage != nil)
            }
        }
        .task { await loadAllModules() }
    }

    // MARK: Module Selection

    private func selectModule(type: ESIType, category: SimSlotCategory) async {
        // If user tapped a specific slot of the right category, fill it directly
        if let active = simState.activeSlot, active.category == category {
            await simState.fillSlot(id: active.id, with: type.typeId)
            simState.activeSlotId = nil
            return
        }
        // Otherwise fill next available slot of this category
        let filled = await simState.fillNextAvailableSlot(category: category, typeId: type.typeId)
        if !filled {
            withAnimation { noSlotMessage = "No open \(category.displayName) on this ship" }
            Task {
                try? await Task.sleep(for: .seconds(2))
                withAnimation { noSlotMessage = nil }
            }
        }
    }

    // MARK: Data Loading

    private func loadAllShips() async {
        guard allShipSections.isEmpty else { return }
        isLoadingShips = true
        let groupIds = Set(CharacterFittingsView.eveShipGroups.keys)
        let groups = await UniverseCache.shared.groups(ids: groupIds)
        let allTypeIds = Array(Set(groups.values.flatMap(\.types)))
        let types = await UniverseCache.shared.types(ids: allTypeIds)
        let shipTypes = types.values.filter {
            CharacterFittingsView.eveShipGroupIds.contains($0.groupId) && $0.published
        }
        let byClass = Dictionary(grouping: Array(shipTypes)) {
            CharacterFittingsView.eveShipGroups[$0.groupId] ?? "Unknown"
        }
        allShipSections = byClass.keys.sorted().map { cls in
            (className: cls, ships: byClass[cls]!.sorted { $0.name < $1.name })
        }
        isLoadingShips = false
    }

    private func loadAllModules() async {
        guard allModuleSections.isEmpty else { return }
        isLoadingModules = true
        defer { isLoadingModules = false }

        guard let modCategory = await UniverseCache.shared.category(id: 7) else { return }
        let groups = await UniverseCache.shared.groups(ids: Set(modCategory.groups))
        let publishedTypeIds = Array(Set(
            groups.values.filter(\.published).flatMap(\.types)
        ))
        guard !publishedTypeIds.isEmpty else { return }
        let types = await UniverseCache.shared.types(ids: publishedTypeIds)

        var bySlot: [SimSlotCategory: [ESIType]] = [:]
        for t in types.values where t.published {
            guard let effects = t.dogmaEffects,
                  let cat = SlotEffect.category(from: effects) else { continue }
            bySlot[cat, default: []].append(t)
        }

        allModuleSections = SimSlotCategory.allCases.compactMap { cat in
            guard let mods = bySlot[cat], !mods.isEmpty else { return nil }
            return (category: cat, modules: mods.sorted { $0.name < $1.name })
        }
    }

    // MARK: Helpers

    private func filterModules(_ modules: [ESIType]) -> [ESIType] {
        let q = moduleFilterText.lowercased().trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return modules }
        return modules.filter { $0.name.lowercased().contains(q) }
    }

    @ViewBuilder
    private func searchBar(
        text: Binding<String>,
        placeholder: String,
        onChange: @escaping (String) -> Void
    ) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass").foregroundStyle(.secondary).font(.subheadline)
            TextField(placeholder, text: text)
                .textFieldStyle(.plain)
                .onChange(of: text.wrappedValue) { _, q in onChange(q) }
            if !text.wrappedValue.isEmpty {
                Button { text.wrappedValue = "" } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 10).padding(.vertical, 7)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 8))
        .padding(10)
    }

    private func emptyState(_ msg: String) -> some View {
        VStack(spacing: 8) {
            Image(systemName: "questionmark.circle").font(.largeTitle).foregroundStyle(.tertiary)
            Text(msg).font(.subheadline).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK:  Fitting Diagram

struct SimFittingDiagram: View {
    @Environment(SimulatorState.self) private var simState

    private var highSlots: [SimSlot] { simState.slots.filter { $0.category == .high } }
    private var medSlots:  [SimSlot] { simState.slots.filter { $0.category == .medium } }
    private var lowSlots:  [SimSlot] { simState.slots.filter { $0.category == .low } }
    private var rigSlots:  [SimSlot] { simState.slots.filter { $0.category == .rig } }
    private var subSlots:  [SimSlot] { simState.slots.filter { $0.category == .subsystem } }

    var body: some View {
        if simState.shipTypeId == nil {
            emptyState
        } else {
            ScrollView {
                VStack(spacing: 0) {
                    shipHero
                    Divider()
                    slotGrid
                        .padding(16)
                }
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "helm")
                .font(.system(size: 64))
                .foregroundStyle(.tertiary)
            Text("No Ship Selected")
                .font(.title2.bold())
                .foregroundStyle(.secondary)
            Text("Search for a ship in the left panel to begin")
                .font(.subheadline)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var shipHero: some View {
        ZStack(alignment: .bottomLeading) {
            AsyncImage(url: EVEImageURL.typeRender(simState.shipTypeId ?? 0, size: 512)) { img in
                img.resizable().aspectRatio(contentMode: .fill)
            } placeholder: {
                Rectangle().fill(
                    LinearGradient(
                        colors: [Color(.darkGray).opacity(0.3), .black.opacity(0.5)],
                        startPoint: .topLeading, endPoint: .bottomTrailing
                    )
                )
            }
            .frame(height: 200).clipped()

            LinearGradient(
                stops: [.init(color: .clear, location: 0), .init(color: .black.opacity(0.85), location: 1)],
                startPoint: .top, endPoint: .bottom
            )

            HStack(alignment: .bottom) {
                VStack(alignment: .leading, spacing: 4) {
                    if simState.isLoadingShip {
                        ProgressView().tint(.white)
                    } else {
                        Text(simState.shipName)
                            .font(.title2.bold()).foregroundStyle(.white)
                        if !simState.shipClassName.isEmpty {
                            Text(simState.shipClassName)
                                .font(.subheadline).foregroundStyle(.white.opacity(0.6))
                        }
                    }
                }
                Spacer()
                if simState.slots.contains(where: { !$0.isEmpty }) {
                    Button { simState.clearAll() } label: {
                        Label("Clear Fit", systemImage: "trash")
                            .font(.caption.bold())
                            .padding(.horizontal, 10).padding(.vertical, 6)
                            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 8))
                            .foregroundStyle(.white)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(14)
        }
        .frame(height: 200)
    }

    private var slotGrid: some View {
        VStack(alignment: .leading, spacing: 10) {
            if !highSlots.isEmpty { SimSlotRowView(slots: highSlots, category: .high) }
            if !medSlots.isEmpty  { SimSlotRowView(slots: medSlots,  category: .medium) }
            if !lowSlots.isEmpty  { SimSlotRowView(slots: lowSlots,  category: .low) }
            if !rigSlots.isEmpty  { SimSlotRowView(slots: rigSlots,  category: .rig) }
            if !subSlots.isEmpty  { SimSlotRowView(slots: subSlots,  category: .subsystem) }

            if simState.slots.isEmpty && !simState.isLoadingShip {
                HStack {
                    Spacer()
                    Label("No fitting slots detected for this ship type",
                          systemImage: "exclamationmark.triangle")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                }
                .padding(.top, 20)
            }
        }
    }
}

// MARK:  Slot Row

struct SimSlotRowView: View {
    let slots: [SimSlot]
    let category: SimSlotCategory
    @Environment(SimulatorState.self) private var simState

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(category.displayName, systemImage: category.icon)
                .font(.caption.bold())
                .foregroundStyle(category.color)

            LazyVGrid(
                columns: Array(repeating: GridItem(.fixed(52), spacing: 6), count: 8),
                alignment: .leading,
                spacing: 6
            ) {
                ForEach(slots) { slot in
                    SimSlotSocketView(slot: slot)
                        .environment(simState)
                }
            }
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(category.color.opacity(0.05))
                .overlay(RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(category.color.opacity(0.18), lineWidth: 1))
        )
    }
}

// MARK:  Slot Drop Target (AppKit)
// NSViewRepresentable so we can return NSDragOperation.none for incompatible slots,
// which makes the system cursor badge switch from "+" to "not-allowed" (⊘).

private final class _SimDropNSView: NSView {
    var slotCategory: SimSlotCategory = .high
    var simState: SimulatorState?
    var onTargeted: ((Bool) -> Void)?
    var onDrop: ((Int) -> Void)?

    private func dragOperation() -> NSDragOperation {
        guard let cat = simState?.draggingCategory else { return .copy }
        return cat == slotCategory ? .copy : []
    }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        onTargeted?(true)
        return dragOperation()
    }

    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        dragOperation()
    }

    override func draggingExited(_ sender: NSDraggingInfo?) {
        onTargeted?(false)
    }

    override func prepareForDragOperation(_ sender: NSDraggingInfo) -> Bool { true }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        onTargeted?(false)
        guard let state = simState,
              let payload = state.pendingDropPayload,
              payload.category == slotCategory else {
            simState?.pendingDropPayload = nil
            return false
        }
        state.pendingDropPayload = nil
        onDrop?(payload.typeId)
        return true
    }

    // Pass mouse clicks through to the SwiftUI Button sitting on top.
    // Drag events are dispatched via NSDraggingDestination registration, not hitTest.
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}

private struct SimDropTarget: NSViewRepresentable {
    let slotCategory: SimSlotCategory
    let simState: SimulatorState
    @Binding var isTargeted: Bool
    let onDrop: (Int) -> Void

    func makeNSView(context: Context) -> _SimDropNSView {
        let v = _SimDropNSView()
        v.registerForDraggedTypes([.init("public.json")])
        return v
    }

    func updateNSView(_ v: _SimDropNSView, context: Context) {
        v.slotCategory = slotCategory
        v.simState = simState
        v.onTargeted = { isTargeted = $0 }
        v.onDrop = onDrop
    }
}

// MARK:  Slot Socket

struct SimSlotSocketView: View {
    let slot: SimSlot
    @Environment(SimulatorState.self) private var simState
    @State private var showPopover = false
    @State private var isDropTargeted = false
    @State private var isHovered = false

    // Read live from simState so this view observes mutations — the `slot` let is a frozen copy.
    private var currentModuleTypeId: Int? {
        simState.slots.first { $0.id == slot.id }?.moduleTypeId
    }

    private var isActive: Bool { simState.activeSlotId == slot.id }
    private var isValidDropTarget: Bool {
        isDropTargeted && (simState.draggingCategory == nil || simState.draggingCategory == slot.category)
    }
    private var isInvalidDropTarget: Bool {
        isDropTargeted && simState.draggingCategory != nil && simState.draggingCategory != slot.category
    }
    private var isHighlighted: Bool { isActive || isValidDropTarget }

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Button {
                if currentModuleTypeId == nil {
                    simState.activeSlotId = slot.id
                } else {
                    showPopover = true
                }
            } label: {
                ZStack {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(isInvalidDropTarget
                              ? Color.red.opacity(0.20)
                              : isHighlighted
                                ? slot.category.color.opacity(isDropTargeted ? 0.35 : 0.25)
                                : Color(.windowBackgroundColor).opacity(0.6))
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .strokeBorder(
                                    isInvalidDropTarget
                                        ? Color.red.opacity(0.8)
                                        : isHighlighted ? slot.category.color : slot.category.color.opacity(0.25),
                                    lineWidth: isInvalidDropTarget || isHighlighted ? 2 : 1
                                )
                        )

                    if let typeId = currentModuleTypeId {
                        AsyncImage(url: EVEImageURL.typeIcon(typeId, size: 64)) { img in
                            img.resizable().aspectRatio(contentMode: .fit)
                        } placeholder: {
                            RoundedRectangle(cornerRadius: 6).fill(.quaternary)
                        }
                        .padding(5)
                    } else if isInvalidDropTarget {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 18))
                            .foregroundStyle(Color.red.opacity(0.85))
                    } else {
                        Image(systemName: isDropTargeted ? "plus.circle.fill" : "plus")
                            .font(.system(size: isDropTargeted ? 18 : 13,
                                          weight: isDropTargeted ? .regular : .ultraLight))
                            .foregroundStyle(slot.category.color.opacity(isDropTargeted ? 0.9 : 0.35))
                    }
                }
            }
            .buttonStyle(.plain)
            .frame(width: 52, height: 52)
            .scaleEffect(isValidDropTarget ? 1.08 : isInvalidDropTarget ? 0.94 : 1.0)
            .animation(.spring(response: 0.2, dampingFraction: 0.6), value: isValidDropTarget)
            .animation(.spring(response: 0.2, dampingFraction: 0.6), value: isInvalidDropTarget)
            .background(
                SimDropTarget(
                    slotCategory: slot.category,
                    simState: simState,
                    isTargeted: $isDropTargeted
                ) { typeId in
                    guard let idx = simState.slots.firstIndex(where: { $0.id == slot.id }) else { return }
                    simState.slots[idx].moduleTypeId = typeId
                    simState.activeSlotId = nil
                    simState.draggingCategory = nil
                    simState.recomputeStats()  // immediate pass (may use fallback for new module)
                    Task {
                        // Ensure the module type is in the cache, then fetch its effect details.
                        if simState.moduleTypes[typeId] == nil {
                            let fetched = await UniverseCache.shared.types(ids: [typeId])
                            await MainActor.run {
                                if let t = fetched[typeId] {
                                    simState.moduleTypes[typeId] = t
                                    simState.recomputeStats()
                                }
                            }
                        }
                        // Now pre-fetch effect details so full dogma replaces the heuristic.
                        await MainActor.run { simState.prefetchFittedEffects() }
                    }
                }
            )
            .popover(isPresented: $showPopover, arrowEdge: .bottom) {
                SimModulePopover(slot: slot)
                    .environment(simState)
            }

            // Hover × badge — shown only when a module is fitted and the slot is hovered.
            if isHovered && currentModuleTypeId != nil {
                Button {
                    simState.clearSlot(id: slot.id)
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.red)
                        .shadow(color: .black.opacity(0.5), radius: 2, x: 0, y: 1)
                }
                .buttonStyle(.plain)
                .offset(x: 4, y: -4)
                .transition(.scale(scale: 0.5).combined(with: .opacity))
            }
        }
        .onHover { isHovered = $0 }
        .animation(.easeInOut(duration: 0.12), value: isHovered)
    }
}

// MARK:  Module Drag Preview

struct SimModuleDragPreview: View {
    let type: ESIType
    let category: SimSlotCategory

    var body: some View {
        HStack(spacing: 10) {
            AsyncImage(url: EVEImageURL.typeIcon(type.typeId, size: 64)) { img in
                img.resizable().aspectRatio(contentMode: .fit)
            } placeholder: {
                RoundedRectangle(cornerRadius: 6).fill(.quaternary)
            }
            .frame(width: 36, height: 36)
            .clipShape(RoundedRectangle(cornerRadius: 6))

            VStack(alignment: .leading, spacing: 3) {
                Text(type.name).font(.caption.bold()).lineLimit(1)
                Label(category.displayName, systemImage: category.icon)
                    .font(.caption2).foregroundStyle(category.color)
            }
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 10))
    }
}

// MARK:  Module Popover

struct SimModulePopover: View {
    let slot: SimSlot
    @Environment(SimulatorState.self) private var simState
    @Environment(\.openWindow) private var openWindow

    private var moduleType: ESIType? {
        slot.moduleTypeId.flatMap { simState.moduleTypes[$0] }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let t = moduleType, let typeId = slot.moduleTypeId {
                HStack(spacing: 12) {
                    AsyncImage(url: EVEImageURL.typeIcon(typeId, size: 128)) { img in
                        img.resizable().aspectRatio(contentMode: .fit)
                    } placeholder: {
                        RoundedRectangle(cornerRadius: 8).fill(.quaternary)
                    }
                    .frame(width: 56, height: 56)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .overlay(RoundedRectangle(cornerRadius: 8)
                        .strokeBorder(.white.opacity(0.1), lineWidth: 0.5))

                    VStack(alignment: .leading, spacing: 4) {
                        Text(t.name).font(.headline).lineLimit(2)
                        Label(slot.category.displayName, systemImage: slot.category.icon)
                            .font(.caption).foregroundStyle(slot.category.color)
                    }
                    Spacer()
                }
                .padding(14)

                Divider()

                HStack(spacing: 0) {
                    Button {
                        openWindow(value: GalaxyMarketSearchInput(typeId: typeId, typeName: t.name))
                    } label: {
                        Label("Market", systemImage: "globe.europe.africa.fill")
                            .font(.caption).frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderless).foregroundStyle(.blue)

                    Divider().frame(height: 30)

                    Button(role: .destructive) {
                        simState.clearSlot(id: slot.id)
                    } label: {
                        Label("Remove", systemImage: "minus.circle")
                            .font(.caption).frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderless).foregroundStyle(.red)
                }
                .padding(.horizontal, 10).padding(.vertical, 8)
            }
        }
        .frame(width: 280)
    }
}

// MARK:  Stats Panel

struct SimStatsPanel: View {
    @Environment(SimulatorState.self) private var simState

    var body: some View {
        if simState.shipTypeId == nil {
            VStack(spacing: 14) {
                Image(systemName: "chart.bar.doc.horizontal")
                    .font(.system(size: 40)).foregroundStyle(.tertiary)
                Text("Ship stats will appear here\nonce a ship is selected")
                    .font(.subheadline).foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    if simState.isLoadingShip {
                        HStack { Spacer(); ProgressView(); Spacer() }.padding()
                    } else if simState.stats.hasData {
                        SimFittingSection(stats: simState.stats)
                        SimCapBlock(stats: simState.stats)
                        SimOffenseBlock(stats: simState.stats)
                        SimDefenseBlock(stats: simState.stats)
                        SimTargetingBlock(stats: simState.stats)
                        SimNavBlock(stats: simState.stats)
                        SimDronesBlock(stats: simState.stats)
                        SimImplantsBlock()

                        if simState.isComputingEffects {
                            HStack(spacing: 6) {
                                ProgressView().scaleEffect(0.65)
                                Text("Computing module bonuses…")
                                    .font(.caption2).foregroundStyle(.secondary)
                            }
                            .padding(.horizontal, 10)
                            .padding(.top, 8)
                        }
                    } else {
                        VStack(spacing: 8) {
                            Image(systemName: "exclamationmark.triangle").foregroundStyle(.orange)
                            Text("No stat data available for this ship type.")
                                .font(.caption).foregroundStyle(.secondary)
                                .multilineTextAlignment(.center)
                        }
                        .frame(maxWidth: .infinity).padding()
                    }
                }
                .padding(.bottom, 14)
            }
        }
    }
}

// MARK:  Section header

private struct SimSectionHeader: View {
    let title: String
    var summary: String? = nil
    var summaryColor: Color = .primary

    var body: some View {
        HStack {
            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
            Spacer()
            if let s = summary {
                Text(s)
                    .font(.system(size: 11, weight: .semibold).monospacedDigit())
                    .foregroundStyle(summaryColor)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(Color.primary.opacity(0.06))
    }
}

// MARK:  Fitting Resources

struct SimFittingSection: View {
    let stats: SimStats

    var body: some View {
        VStack(spacing: 0) {
            SimSectionHeader(title: "Fitting")
            VStack(alignment: .leading, spacing: 5) {
                if stats.cpuTotal > 0 {
                    SimResourceBar(label: "CPU", used: stats.cpuUsed, total: stats.cpuTotal,
                                   unit: "tf", color: .teal)
                }
                if stats.powerTotal > 0 {
                    SimResourceBar(label: "PG", used: stats.powerUsed, total: stats.powerTotal,
                                   unit: "MW", color: .orange)
                }
                if stats.calibrationTotal > 0 {
                    SimResourceBar(label: "Cal", used: stats.calibrationUsed, total: stats.calibrationTotal,
                                   unit: "", color: .purple)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
        }
    }
}

private struct SimResourceBar: View {
    let label: String
    let used: Double
    let total: Double
    let unit: String
    let color: Color

    private var fraction: Double { total > 0 ? min(1.0, used / total) : 0 }
    private var isOver: Bool { used > total }
    private var barColor: Color { isOver ? .red : fraction > 0.85 ? .yellow : color }

    var body: some View {
        HStack(spacing: 6) {
            Text(label)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.secondary)
                .frame(width: 24, alignment: .leading)

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 2).fill(.quaternary)
                    RoundedRectangle(cornerRadius: 2)
                        .fill(barColor.opacity(0.85))
                        .frame(width: max(0, geo.size.width * CGFloat(fraction)))
                }
            }
            .frame(height: 5)

            Text(formatUsage())
                .font(.system(size: 10).monospacedDigit())
                .foregroundStyle(isOver ? .red : .primary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
    }

    private func formatUsage() -> String {
        "\(fmt(used)) / \(fmt(total))\(unit.isEmpty ? "" : " \(unit)")"
    }

    private func fmt(_ v: Double) -> String {
        v >= 100 ? String(format: "%.0f", v) : String(format: "%.1f", v)
    }
}

// MARK:  Capacitor

struct SimCapBlock: View {
    let stats: SimStats

    private var peakRecharge: Double {
        guard stats.rechargeRateSec > 0 else { return 0 }
        return 2.5 * stats.capacitorCapacity / stats.rechargeRateSec
    }

    var body: some View {
        VStack(spacing: 0) {
            SimSectionHeader(title: "Capacitor", summary: "Stable", summaryColor: .green)
            VStack(alignment: .leading, spacing: 3) {
                if stats.capacitorCapacity > 0 {
                    HStack(spacing: 6) {
                        Text(String(format: "%.1f GJ", stats.capacitorCapacity))
                            .font(.system(size: 11).monospacedDigit())
                        if stats.rechargeRateSec > 0 {
                            Text("/")
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                            Text(fmtTime(stats.rechargeRateSec))
                                .font(.system(size: 11).monospacedDigit())
                        }
                        Spacer()
                    }
                }
                if peakRecharge > 0 {
                    Text(String(format: "Δ %.1f GJ/s (100.0%%)", peakRecharge))
                        .font(.system(size: 11).monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
        }
    }

    private func fmtTime(_ s: Double) -> String {
        String(format: "%.2f s", s)
    }
}

// MARK:  Offense

struct SimOffenseBlock: View {
    let stats: SimStats

    var body: some View {
        VStack(spacing: 0) {
            SimSectionHeader(title: "Offense", summary: "0.0 dps")
            HStack(spacing: 16) {
                Label("0.0 dps (0.0 dps)", systemImage: "scope")
                    .font(.caption2).foregroundStyle(.secondary)
                Spacer()
                Label("0 HP", systemImage: "shield.fill")
                    .font(.caption2).foregroundStyle(.secondary)
            }
            .padding(.horizontal, 10).padding(.vertical, 6)
        }
    }
}

// MARK:  Defense

struct SimDefenseBlock: View {
    let stats: SimStats

    private var peakShieldRegen: Double {
        guard stats.shieldRechargeTimeSec > 0 else { return 0 }
        return 2.5 * stats.shieldHP / stats.shieldRechargeTimeSec
    }

    var body: some View {
        VStack(spacing: 0) {
            SimSectionHeader(title: "Defense", summary: fmtEHP(stats.ehp))
            VStack(spacing: 2) {
                if peakShieldRegen > 0 {
                    SimShieldRechargeRow(peakHPS: peakShieldRegen)
                }
                SimHPLayerRow(icon: "shield.lefthalf.filled",
                              hp: stats.shieldHP, color: .cyan,
                              resists: stats.shieldResists)
                SimHPLayerRow(icon: "shield.fill",
                              hp: stats.armorHP, color: .yellow,
                              resists: stats.armorResists)
                SimHPLayerRow(icon: "cube.fill",
                              hp: stats.hullHP,
                              color: Color(red: 0.85, green: 0.45, blue: 0.25),
                              resists: stats.hullResists)
            }
            .padding(.vertical, 4)
        }
    }

    private func fmtEHP(_ v: Double) -> String {
        v >= 1_000_000 ? String(format: "%.2fM ehp", v / 1_000_000) :
        v >= 1_000     ? String(format: "%.0f ehp", v) :
                         String(format: "%.0f ehp", v)
    }
}

private struct SimShieldRechargeRow: View {
    let peakHPS: Double

    private static let emColor        = Color(red: 0.45, green: 0.60, blue: 1.00)
    private static let thermalColor   = Color(red: 1.00, green: 0.40, blue: 0.10)
    private static let kineticColor   = Color(white: 0.65)
    private static let explosiveColor = Color(red: 1.00, green: 0.82, blue: 0.15)

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "arrow.clockwise")
                .font(.system(size: 10))
                .foregroundStyle(.cyan)
                .frame(width: 14)
            Text(String(format: "%.1f hp/s", peakHPS))
                .font(.system(size: 11).monospacedDigit())
                .frame(minWidth: 44, alignment: .leading)
            Spacer()
            HStack(spacing: 3) {
                damageIcon("bolt.fill",  Self.emColor)
                damageIcon("flame.fill", Self.thermalColor)
                damageIcon("scope",      Self.kineticColor)
                damageIcon("burst.fill", Self.explosiveColor)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 3)
    }

    private func damageIcon(_ name: String, _ color: Color) -> some View {
        Image(systemName: name)
            .font(.system(size: 9))
            .foregroundStyle(color)
            .frame(width: 36)
    }
}

private struct SimHPLayerRow: View {
    let icon: String
    let hp: Double
    let color: Color
    let resists: SimResists

    private static let emColor        = Color(red: 0.45, green: 0.60, blue: 1.00)
    private static let thermalColor   = Color(red: 1.00, green: 0.40, blue: 0.10)
    private static let kineticColor   = Color(white: 0.65)
    private static let explosiveColor = Color(red: 1.00, green: 0.82, blue: 0.15)

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 10))
                .foregroundStyle(color)
                .frame(width: 14)
            Text(fmtHP(hp))
                .font(.system(size: 11).monospacedDigit())
                .frame(minWidth: 44, alignment: .leading)
            Spacer()
            HStack(spacing: 3) {
                SimResistBadge(value: resists.em,        color: Self.emColor)
                SimResistBadge(value: resists.thermal,   color: Self.thermalColor)
                SimResistBadge(value: resists.kinetic,   color: Self.kineticColor)
                SimResistBadge(value: resists.explosive, color: Self.explosiveColor)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 3)
    }

    private func fmtHP(_ v: Double) -> String {
        v >= 1_000_000 ? String(format: "%.1fM", v / 1_000_000) :
        v >= 1_000     ? String(format: "%.0fk", v / 1_000) :
                         String(format: "%.0f", v)
    }
}

private struct SimResistBadge: View {
    let value: Double
    let color: Color

    var body: some View {
        Text(String(format: "%.0f %%", value))
            .font(.system(size: 9, weight: .semibold).monospacedDigit())
            .foregroundStyle(.white)
            .frame(width: 36)
            .padding(.vertical, 2)
            .background(RoundedRectangle(cornerRadius: 3).fill(color.opacity(0.45)))
    }
}

// MARK:  Targeting

struct SimTargetingBlock: View {
    let stats: SimStats

    var body: some View {
        VStack(spacing: 0) {
            SimSectionHeader(title: "Targeting",
                             summary: stats.maxTargetRange > 0 ? fmtRange(stats.maxTargetRange) : "—")
            VStack(spacing: 3) {
                simTwoColRow(
                    left:  stats.sensorStrength > 0 ? String(format: "%.2f points", stats.sensorStrength) : "—",
                    right: stats.scanResolution > 0  ? String(format: "%.0f mm", stats.scanResolution)    : "—"
                )
                simTwoColRow(
                    left:  stats.signatureRadius > 0  ? String(format: "%.0f m", stats.signatureRadius)   : "—",
                    right: stats.maxLockedTargets > 0 ? String(format: "%.0fx", stats.maxLockedTargets)   : "—"
                )
            }
            .padding(.horizontal, 10).padding(.vertical, 6)
        }
    }

    private func fmtRange(_ m: Double) -> String {
        m >= 1_000_000 ? String(format: "%.0f Mm", m / 1_000_000) :
        m >= 1_000     ? String(format: "%.2f km", m / 1_000) :
                         String(format: "%.0f m", m)
    }
}

// MARK:  Navigation

struct SimNavBlock: View {
    let stats: SimStats

    var body: some View {
        VStack(spacing: 0) {
            SimSectionHeader(title: "Navigation",
                             summary: stats.maxVelocity > 0 ? String(format: "%.1f m/s", stats.maxVelocity) : "—")
            VStack(spacing: 3) {
                simTwoColRow(
                    left:  stats.mass > 0       ? String(format: "%.2f t", stats.mass / 1_000) : "—",
                    right: stats.inertiaMod > 0 ? String(format: "%.4fx", stats.inertiaMod)    : "—"
                )
                simTwoColRow(
                    left:  stats.warpSpeed > 0 ? String(format: "%.2f AU/s", stats.warpSpeed) : "—",
                    right: stats.alignTime > 0 ? String(format: "%.2f s", stats.alignTime)    : "—"
                )
            }
            .padding(.horizontal, 10).padding(.vertical, 6)
        }
    }
}

// MARK:  Drones

struct SimDronesBlock: View {
    let stats: SimStats

    var body: some View {
        VStack(spacing: 0) {
            SimSectionHeader(title: "Drones", summary: "0.0 dps")
            VStack(alignment: .leading, spacing: 3) {
                simTwoColRow(left: "0/0 Mbit/sec", right: "—")
                Text("0 Active")
                    .font(.system(size: 11).monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 10).padding(.vertical, 6)
        }
    }
}

// MARK:  Implants

private struct SimImplantsBlock: View {
    @Environment(SimulatorState.self) private var simState

    var body: some View {
        if !simState.implantTypes.isEmpty {
            VStack(spacing: 0) {
                implantHeader
                if simState.includeImplants {
                    implantContent
                } else {
                    Text("Excluded from simulation")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                }
            }
        }
    }

    private var implantHeader: some View {
        HStack {
            Text("Implants")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
            Spacer()
            Toggle(isOn: Binding(
                get: { simState.includeImplants },
                set: { v in simState.includeImplants = v; simState.recomputeStats() }
            )) { EmptyView() }
            .toggleStyle(.switch)
            .controlSize(.mini)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(Color.primary.opacity(0.06))
    }

    @ViewBuilder
    private var implantContent: some View {
        let contributions = simState.stats.implantContributions
        if contributions.isEmpty {
            Text("No active implants modify this ship's stats")
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
        } else {
            VStack(alignment: .leading, spacing: 6) {
                ForEach(contributions) { c in
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 6) {
                            AsyncImage(url: EVEImageURL.typeIcon(c.typeId, size: 64)) { img in
                                img.resizable().aspectRatio(contentMode: .fit)
                            } placeholder: {
                                RoundedRectangle(cornerRadius: 3).fill(.quaternary)
                            }
                            .frame(width: 20, height: 20)
                            .clipShape(RoundedRectangle(cornerRadius: 3))

                            Text(c.name)
                                .font(.system(size: 10, weight: .semibold))
                                .lineLimit(1)
                        }
                        ForEach(c.bonuses, id: \.self) { bonus in
                            HStack(spacing: 4) {
                                Circle()
                                    .fill(.purple.opacity(0.5))
                                    .frame(width: 4, height: 4)
                                Text(bonus)
                                    .font(.system(size: 10))
                                    .foregroundStyle(.secondary)
                            }
                            .padding(.leading, 26)
                        }
                    }
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
        }
    }
}

// MARK:  Stat row helpers

@ViewBuilder
private func simTwoColRow(left: String, right: String) -> some View {
    HStack(spacing: 0) {
        Text(left)
            .font(.system(size: 11).monospacedDigit())
            .frame(maxWidth: .infinity, alignment: .leading)
        Text(right)
            .font(.system(size: 11).monospacedDigit())
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

@ViewBuilder
private func simStatRow(_ label: String, _ value: String) -> some View {
    HStack {
        Text(label).font(.caption2).foregroundStyle(.secondary)
        Spacer()
        Text(value).font(.caption2.monospacedDigit())
    }
}

// MARK:  Load Fitting Sheet

struct SimLoadFittingSheet: View {
    @Environment(SimulatorState.self) private var simState
    @Environment(AccountManager.self) private var accountManager
    @Environment(\.dismiss) private var dismiss

    enum LoadMode { case saved, current }
    @State private var mode: LoadMode = .saved
    @State private var savedFittings: [SavedFittingEntry] = []
    @State private var ships: [ShipEntry] = []
    @State private var shipModules: [Int: [ESIAsset]] = [:]
    @State private var isLoading = false

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Load Fitting").font(.headline)
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
            }
            .padding()

            Picker("Mode", selection: $mode) {
                Text("Saved Fittings").tag(LoadMode.saved)
                Text("Current Ships").tag(LoadMode.current)
            }
            .pickerStyle(.segmented)
            .padding(.horizontal)
            .padding(.bottom, 8)

            Divider()

            if isLoading {
                VStack(spacing: 8) {
                    ProgressView()
                    Text("Loading…").font(.caption).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if mode == .saved {
                savedFittingsList
            } else {
                currentShipsList
            }
        }
        .frame(width: 380, height: 480)
        .task { await loadData() }
    }

    private var savedFittingsList: some View {
        Group {
            if savedFittings.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "bookmark.slash").font(.largeTitle).foregroundStyle(.tertiary)
                    Text("No saved fittings found").font(.subheadline).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(savedFittings) { fitting in
                    loadRow(
                        imageURL: EVEImageURL.typeRender(fitting.shipTypeId, size: 128),
                        title: fitting.name,
                        subtitle: fitting.shipTypeName,
                        detail: "\(fitting.items.count) modules"
                    ) {
                        Task { await simState.loadFromSavedFitting(fitting); dismiss() }
                    }
                }
                .listStyle(.inset)
            }
        }
    }

    private var currentShipsList: some View {
        Group {
            if ships.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "helm").font(.largeTitle).foregroundStyle(.tertiary)
                    Text("No assembled ships found").font(.subheadline).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(ships) { ship in
                    loadRow(
                        imageURL: EVEImageURL.typeRender(ship.typeId, size: 128),
                        title: ship.displayName,
                        subtitle: ship.typeName,
                        detail: ship.locationName
                    ) {
                        Task {
                            await simState.loadFromShipModules(ship, modules: shipModules[ship.itemId] ?? [])
                            dismiss()
                        }
                    }
                }
                .listStyle(.inset)
            }
        }
    }

    private func loadRow(
        imageURL: URL?,
        title: String,
        subtitle: String,
        detail: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                AsyncImage(url: imageURL) { img in
                    img.resizable().aspectRatio(contentMode: .fill)
                } placeholder: {
                    RoundedRectangle(cornerRadius: 6).fill(.quaternary)
                }
                .frame(width: 44, height: 44)
                .clipShape(RoundedRectangle(cornerRadius: 6))

                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.subheadline.bold())
                    Text(subtitle).font(.caption).foregroundStyle(.secondary)
                    Text(detail).font(.caption2).foregroundStyle(.tertiary)
                }
                Spacer()
                Image(systemName: "chevron.right").font(.caption2).foregroundStyle(.tertiary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func loadData() async {
        isLoading = true
        var fittings: [SavedFittingEntry] = []
        var loadedShips: [ShipEntry] = []
        var loadedModules: [Int: [ESIAsset]] = [:]

        for account in accountManager.accounts {
            guard let token = try? await accountManager.validToken(for: account) else { continue }

            if let raw: [ESIFitting] = try? await ESIClient.shared.fetch(
                "/characters/\(account.characterID)/fittings/", token: token
            ) {
                let tids = Array(Set(raw.map(\.shipTypeId)))
                let types = await UniverseCache.shared.types(ids: tids)
                for f in raw {
                    let gid = types[f.shipTypeId]?.groupId ?? 0
                    fittings.append(SavedFittingEntry(
                        characterID: account.characterID,
                        characterName: account.characterName,
                        fittingId: f.fittingId,
                        name: f.name,
                        fittingDescription: f.description,
                        shipTypeId: f.shipTypeId,
                        shipTypeName: types[f.shipTypeId]?.name ?? "Unknown",
                        shipClassName: CharacterFittingsView.eveShipGroups[gid] ?? "Unknown",
                        items: f.items
                    ))
                }
            }

            if let rawAssets: [ESIAsset] = try? await ESIClient.shared.fetchPages(
                "/characters/\(account.characterID)/assets/", token: token
            ) {
                var seen = Set<Int>()
                let assets = rawAssets.filter { seen.insert($0.itemId).inserted }
                let tids = Array(Set(assets.map(\.typeId)))
                let types = await UniverseCache.shared.types(ids: tids)
                let shipTids = Set(types.filter { CharacterFittingsView.eveShipGroupIds.contains($0.value.groupId) }.keys)
                let byLoc = Dictionary(grouping: assets, by: \.locationId)

                for a in assets where shipTids.contains(a.typeId) && a.isSingleton {
                    let gid = types[a.typeId]?.groupId ?? 0
                    loadedShips.append(ShipEntry(
                        characterID: account.characterID,
                        characterName: account.characterName,
                        itemId: a.itemId,
                        typeId: a.typeId,
                        typeName: types[a.typeId]?.name ?? "Unknown",
                        customName: nil,
                        locationName: "Unknown Location",
                        isSingleton: true,
                        shipClassName: CharacterFittingsView.eveShipGroups[gid] ?? "Unknown"
                    ))
                    let mods = (byLoc[a.itemId] ?? []).filter { f in
                        f.locationFlag.hasPrefix("HiSlot") || f.locationFlag.hasPrefix("MedSlot") ||
                        f.locationFlag.hasPrefix("LoSlot") || f.locationFlag.hasPrefix("RigSlot") ||
                        f.locationFlag.hasPrefix("SubSystem")
                    }
                    if !mods.isEmpty { loadedModules[a.itemId] = mods }
                }
            }
        }

        savedFittings = fittings.sorted { $0.name < $1.name }
        ships = loadedShips.sorted { $0.displayName < $1.displayName }
        shipModules = loadedModules
        isLoading = false
    }
}

// MARK:  Ship Search Row

struct SimShipRow: View {
    let type: ESIType

    var body: some View {
        HStack(spacing: 10) {
            AsyncImage(url: EVEImageURL.typeRender(type.typeId, size: 128)) { img in
                img.resizable().aspectRatio(contentMode: .fill)
            } placeholder: {
                RoundedRectangle(cornerRadius: 8).fill(.quaternary)
            }
            .frame(width: 48, height: 48)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(.white.opacity(0.08), lineWidth: 0.5))

            VStack(alignment: .leading, spacing: 2) {
                Text(type.name).font(.subheadline.bold())
                Text(CharacterFittingsView.eveShipGroups[type.groupId] ?? "Ship")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(.vertical, 4)
    }
}

// MARK:  Module Search Row

struct SimModuleRow: View {
    let type: ESIType

    var body: some View {
        HStack(spacing: 10) {
            AsyncImage(url: EVEImageURL.typeIcon(type.typeId, size: 64)) { img in
                img.resizable().aspectRatio(contentMode: .fit)
            } placeholder: {
                RoundedRectangle(cornerRadius: 6).fill(.quaternary)
            }
            .frame(width: 34, height: 34)
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(.white.opacity(0.08), lineWidth: 0.5))

            Text(type.name).font(.subheadline).lineLimit(2)
            Spacer()
        }
        .padding(.vertical, 2)
    }
}
