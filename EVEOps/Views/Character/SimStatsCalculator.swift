//
// SimStatsCalculator.swift
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

import Foundation

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
    // Capacitor drain (active modules)
    static let capacitorNeed    = 6    // activation energy cost per cycle (GJ)
    static let activationTime   = 73   // cycle duration (ms)
    // Drones
    static let droneBandwidth   = 1271 // ship drone bandwidth (Mbit/s)
    static let droneBayCapacity = 283  // ship drone bay (m³)

    static let allResistances: Set<Int> = [267, 268, 269, 270, 271, 272, 273, 274, 109, 110, 111, 113]
}

// MARK:  Stats Calculator

struct SimStatsCalculator {

    // EVE ESI dogma modifier operator IDs — verified empirically from live ESI response data.
    // op=0 (preAssign):  Damage Control resistance floors — take min for resists.
    // op=2 (modAdd):     flat addition, never stacking-penalised.
    // op=4 (postMul):    multiply by factor, stacking-penalised.
    // op=6 (postPercent): multiply by (1+val/100), stacking-penalised.
    private enum Op {
        static let preAssign   = 0   // assign value before other ops (Damage Control, etc.)
        static let preMul      = 1   // multiply before flat adds (stacking penalised)
        static let modAdd      = 2   // flat addition — Shield Extenders, armor plates, etc.
        static let modSub      = 3   // flat subtraction
        static let postMul     = 4   // multiply by factor (stacking penalised) — PDS, etc.
        static let postPercent = 6   // ×(1 + val/100) (stacking penalised) — hardeners, skills
        static let postDiv     = 7   // divide by factor (stacking penalised)
        static let postAssign  = 11  // assign value after other ops
        // Apply: assigns → pre-multiply → flat add/sub → post-multiply/percent/div → post-assign.
        static let applyOrder  = [0, 1, 2, 3, 4, 7, 6, 11]
        // Stacking penalty applies to all multiplicative/divisive/percentage operators.
        static let stackPenalised: Set<Int> = [1, 4, 6, 7]
    }

    // e^-(rank/2.67)² — EVE's official stacking-penalty formula.
    private static func penalty(_ rank: Int) -> Double { exp(-pow(Double(rank) / 2.67, 2)) }

    // Apply ship→module LocationModifier overrides to a single module attribute value.
    // Used in step 2 so ship role bonuses (e.g. doubled shield extender HP) are reflected
    // before the module's effect pushes its value onto the ship's pending map.
    private static func applyShipToModAttr(_ base: Double, attrId: Int, shipMods: [Int: [Int: [Double]]]) -> Double {
        guard let opGroups = shipMods[attrId] else { return base }
        var val = base
        for op in Op.applyOrder {
            guard var vals = opGroups[op] else { continue }
            switch op {
            case Op.preAssign:
                val = vals.min() ?? val
            case Op.modAdd:
                val += vals.reduce(0, +)
            case Op.modSub:
                val -= vals.reduce(0, +)
            case Op.preMul, Op.postMul:
                vals.sort { abs($0 - 1.0) > abs($1 - 1.0) }
                for (i, v) in vals.enumerated() { val *= 1.0 + (v - 1.0) * penalty(i) }
            case Op.postDiv:
                vals.sort { abs($0 - 1.0) > abs($1 - 1.0) }
                for (i, v) in vals.enumerated() where v != 0 { val /= 1.0 + (v - 1.0) * penalty(i) }
            case Op.postPercent:
                vals.sort { abs($0) > abs($1) }
                for (i, v) in vals.enumerated() { val *= 1.0 + v * penalty(i) / 100.0 }
            case Op.postAssign:
                val = vals.first ?? val
            default: break
            }
        }
        return val
    }

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
        characterSkills: [Int: Int] = [:],
        skillTypes: [Int: ESIType] = [:],
        effectCache: [Int: ESIDogmaEffectDetail] = [:]
    ) -> SimStats {
        // 1 ── Build mutable attribute map from ship base values.
        //      Resistance attributes default to 1.0 (0 % resist) if absent.
        var attrs: [Int: Double] = [:]
        for a in shipType.dogmaAttributes ?? [] { attrs[a.attributeId] = a.value }

#if DEBUG
        let debugKeyAttrs: Set<Int> = [9, 37, 70, 192, 263, 265, 267, 268, 269, 270, 271, 272, 273, 274, 109, 110, 111, 113]
        print("[Sim] Ship '\(shipType.name)' base attrs: " +
              debugKeyAttrs.sorted().map { "\($0)=\(attrs[$0].map { String(format: "%.4f", $0) } ?? "MISSING")" }.joined(separator: " "))
#endif

        // 1b ── Two-pass dogma prep: build the ship's own attribute map and collect
        //       any LocationModifier effects the ship has that boost MODULE attributes.
        //       (e.g. a role bonus like "100% bonus to shield extender HP" lives here.)
        //       These are applied to each module's source-attribute value in step 2,
        //       before the module pushes its effect onto the ship's pending map.
        let shipSelfAttrMap = Dictionary(
            uniqueKeysWithValues: (shipType.dogmaAttributes ?? []).map { ($0.attributeId, $0.value) }
        )
        // [moduleAttrId: [op: [values]]] — ship→module overrides built from LocationModifier effects
        var shipToModuleAttrs: [Int: [Int: [Double]]] = [:]
        for effect in shipType.dogmaEffects ?? [] {
            guard let detail = effectCache[effect.effectId] else { continue }
            if let cat = detail.effectCategory, cat == 1 || cat == 2 || cat == 3 || cat == 5 { continue }
            for m in detail.modifiers {
                guard m.function == "LocationModifier",
                      let tgt = m.modifiedAttributeId,
                      let src = m.modifyingAttributeId,
                      let op  = m.operatorId,
                      let val = shipSelfAttrMap[src] else { continue }
#if DEBUG
                print("[Sim] SHIP→MOD eff=\(effect.effectId) modAttr=\(tgt) shipAttr=\(src) op=\(op) val=\(val)")
#endif
                shipToModuleAttrs[tgt, default: [:]][op, default: []].append(val)
            }
        }

        // 2 ── Collect modifier records from every fitted module.
        //      pending[targetAttrId][op] = [sourceValues…]
        //      Before pushing a module source-attribute value, apply any ship→module
        //      LocationModifier overrides so role bonuses (e.g. doubled extender HP)
        //      are reflected correctly.
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
                // Active effects (effectCategory 1): apply only those targeting resistance
                // resonance attributes. This mirrors EVE's fitting panel which shows resists
                // with hardeners running, but ignores active penalties on non-resist stats
                // (e.g. the Prototype Cloaking Device's -90 % velocity hit).
                // Passive (0) and online (4) effects always apply.
                if let cat = detail.effectCategory, cat == 1 {
                    let hasResistTarget = detail.modifiers.contains {
                        guard let tgt = $0.modifiedAttributeId else { return false }
                        return DogmaAttr.allResistances.contains(tgt)
                    }
                    if !hasResistTarget { continue }
                }
                for m in detail.modifiers {
                    // LocationRequiredSkillModifier from modules targets sub-items (missiles/launchers),
                    // not the ship itself — exclude it from ship-level attribute computation.
                    let knownFunc = m.function == "LocationModifier"
                                 || m.function == "ItemModifier"
                    guard knownFunc,
                          m.domain == "shipID",
                          let tgt  = m.modifiedAttributeId,
                          let src  = m.modifyingAttributeId,
                          let op   = m.operatorId else { continue }
                    // Source value must come from the module's own attributes.
                    // Falling back to the ship's attribute for the same ID caused wrong values
                    // (e.g. ship power-grid output) to be fed into resist/HP multiplier slots.
                    guard let rawVal = modAttrMap[src] else {
#if DEBUG
                        let hpResistAttrs: Set<Int> = [9, 263, 265, 267, 268, 269, 270, 271, 272, 273, 274, 109, 110, 111, 113]
                        if hpResistAttrs.contains(tgt) {
                            let modKeys = (mod.dogmaAttributes ?? []).map(\.attributeId).sorted()
                            print("[Sim] SKIP '\(mod.name)' eff=\(effect.effectId) tgt=\(tgt) src=\(src) op=\(op) — srcNotInMap; moduleAttrs=\(modKeys)")
                        }
#endif
                        continue
                    }
                    // Apply ship→module modifiers (e.g. role bonus to shield extender HP).
                    let val = Self.applyShipToModAttr(rawVal, attrId: src, shipMods: shipToModuleAttrs)
#if DEBUG
                    let hpResistAttrs: Set<Int> = [9, 37, 70, 192, 263, 265, 267, 268, 269, 270, 271, 272, 273, 274, 109, 110, 111, 113, 479, 480, 481, 482]
                    if hpResistAttrs.contains(tgt) {
                        let adjusted = val != rawVal ? " (adjusted from \(rawVal))" : ""
                        print("[Sim] MOD '\(mod.name)' eff=\(effect.effectId) func=\(m.function ?? "?") tgt=\(tgt) src=\(src) op=\(op) val=\(val)\(adjusted)")
                    }
#endif
                    pending[tgt, default: [:]][op, default: []].append(val)
                }
            }
            if !resolvedAny { fallbackModules.append(mod) }
        }

        // 2a ── Process the ship type's own ItemModifier effects (passive/online only).
        //       These modify the ship's own attributes directly (e.g. built-in HP multiplier).
        //       LocationModifier effects were already handled in step 1b above.
        for effect in shipType.dogmaEffects ?? [] {
            guard let detail = effectCache[effect.effectId] else { continue }
            if let cat = detail.effectCategory, cat == 1 || cat == 2 || cat == 3 || cat == 5 { continue }
            for m in detail.modifiers {
                guard m.function == "ItemModifier",
                      let tgt = m.modifiedAttributeId,
                      let src = m.modifyingAttributeId,
                      let op  = m.operatorId,
                      let val = shipSelfAttrMap[src] else { continue }
#if DEBUG
                let hpResistAttrs: Set<Int> = [9, 37, 70, 192, 263, 265, 267, 268, 269, 270, 271, 272, 273, 274, 109, 110, 111, 113]
                if hpResistAttrs.contains(tgt) {
                    print("[Sim] SHIP SELF eff=\(effect.effectId) func=\(m.function ?? "?") tgt=\(tgt) src=\(src) op=\(op) val=\(val)")
                }
#endif
                pending[tgt, default: [:]][op, default: []].append(val)
            }
        }

        // 2b ── Collect modifier records from character skills.
        //       Scaling rules per operator:
        //         postPercent/modAdd/addRate/subRate: value is per-level amount → multiply by level
        //         preMul/postMul/preDiv/postDiv: value is a compounding per-level multiplier → raise to power of level
        //         preAssign/postAssign: use as-is (level scaling not meaningful for assignment)
        for (skillTypeId, skillLevel) in characterSkills where skillLevel > 0 {
            guard let skillType = skillTypes[skillTypeId] else { continue }
            let skillAttrMap = Dictionary(
                uniqueKeysWithValues: (skillType.dogmaAttributes ?? []).map { ($0.attributeId, $0.value) }
            )
            for effect in skillType.dogmaEffects ?? [] {
                guard let detail = effectCache[effect.effectId] else { continue }
                for m in detail.modifiers {
                    let knownFunc = m.function == "LocationModifier"
                                 || m.function == "LocationRequiredSkillModifier"
                                 || m.function == "ItemModifier"
                    guard knownFunc,
                          m.domain == "shipID",
                          let tgt = m.modifiedAttributeId,
                          let src = m.modifyingAttributeId,
                          let op  = m.operatorId,
                          let baseVal = skillAttrMap[src] else { continue }

                    // Scale the per-level attribute value according to the operator's semantics.
                    let scaledVal: Double
                    switch op {
                    case Op.preMul, Op.postMul, Op.postDiv:
                        // Multipliers compound per level: 0.95^5, not 0.95×5.
                        scaledVal = pow(baseVal, Double(skillLevel))
                    default:
                        // Additive/percentage bonuses accumulate linearly.
                        scaledVal = baseVal * Double(skillLevel)
                    }

#if DEBUG
                    let simDebugHP: Set<Int> = [9, 37, 70, 192, 263, 265, 267, 268, 269, 270, 271, 272, 273, 274, 109, 110, 111, 113]
                    if simDebugHP.contains(tgt) {
                        print("[Sim] SKILL '\(skillType.name)' lv=\(skillLevel) eff=\(effect.effectId) func=\(m.function ?? "?") tgt=\(tgt) src=\(src) op=\(op) baseVal=\(baseVal) scaledVal=\(scaledVal)")
                    }
#endif
                    pending[tgt, default: [:]][op, default: []].append(scaledVal)
                }
            }
        }

        // 3 ── Apply dogma modifiers in the standard evaluation order.
#if DEBUG
        do {
            let simKeyAttrs: [Int] = [9, 37, 70, 109, 110, 111, 113, 192, 263, 265, 267, 268, 269, 270, 271, 272, 273, 274]
            for attr in simKeyAttrs {
                if let opGroups = pending[attr] {
                    for (op, vals) in opGroups.sorted(by: { $0.key < $1.key }) {
                        print("[Sim] PENDING attr[\(attr)] op=\(op) vals=\(vals.map { String(format: "%.4f", $0) })")
                    }
                } else {
                    print("[Sim] PENDING attr[\(attr)] — no modifiers")
                }
            }
        }
#endif
        for (attrId, opGroups) in pending {
            let isResist = DogmaAttr.allResistances.contains(attrId)
            var base = attrs[attrId] ?? (isResist ? 1.0 : 0.0)

            for op in Op.applyOrder {
                guard var vals = opGroups[op] else { continue }

                switch op {
                case Op.preAssign:
                    // Resistance resonances: lower value = better resist. Take the minimum
                    // assigned value, but only adopt it if it actually improves on the current base.
                    // This matches EVE's DC behaviour: it raises a floor without worsening good resists.
                    let best = vals.min() ?? base
                    base = isResist ? min(base, best) : best

                case Op.postAssign:
                    base = vals.first ?? base

                case Op.modAdd:
                    // Flat addition — not stacking-penalised (Shield Extenders, armor plates, etc.)
                    base += vals.reduce(0, +)

                case Op.modSub:
                    base -= vals.reduce(0, +)

                case Op.preMul, Op.postMul:
                    // Multiply by factor; sort largest-effect first for stacking penalty ranking.
                    vals.sort { abs($0 - 1.0) > abs($1 - 1.0) }
                    for (i, v) in vals.enumerated() {
                        base *= 1.0 + (v - 1.0) * penalty(i)
                    }

                case Op.postDiv:
                    vals.sort { abs($0 - 1.0) > abs($1 - 1.0) }
                    for (i, v) in vals.enumerated() where v != 0 {
                        base /= 1.0 + (v - 1.0) * penalty(i)
                    }

                case Op.postPercent:
                    // Percentage multiply ×(1+val/100); sort largest absolute % first.
                    vals.sort { abs($0) > abs($1) }
                    for (i, v) in vals.enumerated() {
                        base *= 1.0 + v * penalty(i) / 100.0
                    }

                default: break
                }
            }
            attrs[attrId] = base
        }

        // Clamp all resistance resonance attributes to [0.0, 1.0] so that impossible
        // values from bad modifier data never reach the display layer.
        for attrId in DogmaAttr.allResistances {
            if let v = attrs[attrId] { attrs[attrId] = max(0.0, min(1.0, v)) }
        }

#if DEBUG
        do {
            let simKeyAttrs: [Int] = [9, 37, 70, 109, 110, 111, 113, 192, 263, 265, 267, 268, 269, 270, 271, 272, 273, 274]
            for attr in simKeyAttrs {
                print("[Sim] FINAL attr[\(attr)] = \(attrs[attr].map { String(format: "%.6f", $0) } ?? "MISSING")")
            }
        }
#endif

        // 4 ── Fitting resource usage — read directly from each module's own attributes.
        //      Individual module CPU/power costs are not yet reduced by skills (e.g. Advanced
        //      Weapon Upgrades), so these values are the raw base costs from the module type.
        //      Ship-level totals (cpuTotal, powerTotal) are already skill-adjusted via step 2b.
        var cpuUsed = 0.0
        var powerUsed = 0.0
        var calibrationUsed = 0.0
        var capDrainPerSec = 0.0
        for mod in fittedModules {
            let mAttrs = mod.dogmaAttributes ?? []
            func mv(_ id: Int) -> Double { mAttrs.first { $0.attributeId == id }?.value ?? 0 }
            cpuUsed         += mv(DogmaAttr.cpu)
            powerUsed       += mv(DogmaAttr.power)
            calibrationUsed += mv(DogmaAttr.upgradeCost)
            let capNeed = mv(DogmaAttr.capacitorNeed)
            let actTime = mv(DogmaAttr.activationTime)
            if capNeed > 0, actTime > 0 {
                capDrainPerSec += capNeed / (actTime / 1000.0)
            }
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
        s.capDrainPerSec    = capDrainPerSec
        s.droneBandwidth    = a(DogmaAttr.droneBandwidth)
        s.droneBayCapacity  = a(DogmaAttr.droneBayCapacity)

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

        s.trainingContributions = characterSkills.compactMap { (skillTypeId, skillLevel) -> TrainingContribution? in
            guard skillLevel > 0, let skillType = skillTypes[skillTypeId] else { return nil }
            let bonuses = describeSkillBonuses(skill: skillType, level: skillLevel, effectCache: effectCache)
            return bonuses.isEmpty ? nil : TrainingContribution(typeId: skillTypeId, name: skillType.name, level: skillLevel, bonuses: bonuses)
        }.sorted { $0.name < $1.name }

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
        case Op.postDiv:
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

    static func describeSkillBonuses(
        skill: ESIType,
        level: Int,
        effectCache: [Int: ESIDogmaEffectDetail]
    ) -> [String] {
        let skillAttrMap = Dictionary(
            uniqueKeysWithValues: (skill.dogmaAttributes ?? []).map { ($0.attributeId, $0.value) }
        )
        var seen = Set<String>()
        var result: [String] = []
        for effect in skill.dogmaEffects ?? [] {
            guard let detail = effectCache[effect.effectId] else { continue }
            for m in detail.modifiers {
                let knownFunc = m.function == "LocationModifier"
                             || m.function == "LocationRequiredSkillModifier"
                             || m.function == "ItemModifier"
                guard knownFunc,
                      m.domain == "shipID",
                      let tgt      = m.modifiedAttributeId,
                      let src      = m.modifyingAttributeId,
                      let op       = m.operatorId,
                      let label    = trackedAttrDisplay[tgt],
                      let baseVal  = skillAttrMap[src] else { continue }
                if let desc = formatSkillBonus(label: label, attrId: tgt, op: op, baseVal: baseVal, level: level),
                   seen.insert(desc).inserted {
                    result.append(desc)
                }
            }
        }
        return result
    }

    private static func formatSkillBonus(label: String, attrId: Int, op: Int, baseVal: Double, level: Int) -> String? {
        let scaledVal = baseVal * Double(level)
        let isResist = DogmaAttr.allResistances.contains(attrId)
        switch op {
        case Op.postPercent:
            let pctTotal    = isResist ? -scaledVal : scaledVal
            let pctPerLevel = isResist ? -baseVal   : baseVal
            guard abs(pctTotal) >= 0.01 else { return nil }
            return String(format: "%+.1f%% \(label) (%+.1f%%/lvl)", pctTotal, pctPerLevel)
        case Op.modAdd:
            guard abs(scaledVal) >= 0.001 else { return nil }
            return String(format: "%+.1f \(label) (%+.1f/lvl)", scaledVal, baseVal)
        case Op.modSub:
            guard abs(scaledVal) >= 0.001 else { return nil }
            return String(format: "%.1f \(label) (%.1f/lvl)", -scaledVal, -baseVal)
        default:
            return nil
        }
    }
}
