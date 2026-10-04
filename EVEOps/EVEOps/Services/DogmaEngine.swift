//
// DogmaEngine.swift
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
import OSLog

// MARK:  Input models (must match Rust EsfFit serde layout exactly)

nonisolated private struct EsfFit: Encodable {
    let ship_type_id: Int
    let modules: [EsfModule]
    let drones: [EsfDrone]
    let implants: [Int]
}

nonisolated private struct EsfModule: Encodable {
    let type_id: Int
    let slot: EsfSlot
    let state: String       // "Passive" | "Online" | "Active" | "Overload"
    let charge: EsfCharge?
}

nonisolated private struct EsfSlot: Encodable {
    let index: Int
    // "type" is a reserved keyword — CodingKeys maps slotType → "type"
    let slotType: String
    enum CodingKeys: String, CodingKey {
        case slotType = "type"
        case index
    }
}

nonisolated private struct EsfCharge: Encodable {
    let type_id: Int
}

nonisolated private struct EsfDrone: Encodable {
    let type_id: Int
    let state: String
}

// MARK:  Output model (must match Rust FfiSimStats serde layout exactly)

nonisolated private struct FfiSimStats: Decodable {
    let shield_hp: Double
    let armor_hp: Double
    let hull_hp: Double
    let shield_em_res: Double
    let shield_exp_res: Double
    let shield_kin_res: Double
    let shield_therm_res: Double
    let armor_em_res: Double
    let armor_exp_res: Double
    let armor_kin_res: Double
    let armor_therm_res: Double
    let hull_em_res: Double
    let hull_exp_res: Double
    let hull_kin_res: Double
    let hull_therm_res: Double
    let max_velocity: Double
    let align_time_sec: Double
    let mass: Double
    let inertia_mod: Double
    let warp_speed: Double
    let signature_radius: Double
    let capacitor_capacity: Double
    let capacitor_recharge_sec: Double
    let shield_recharge_sec: Double
    let max_target_range: Double
    let scan_resolution: Double
    let max_locked_targets: Double
    let sensor_strength: Double
    let cpu_total: Double
    let cpu_used: Double
    let power_total: Double
    let power_used: Double
    let calibration_total: Double
    let calibration_used: Double
    let drone_bandwidth: Double
    let drone_bay_capacity: Double
    let cap_drain_per_sec: Double
    // Derived attributes — optional so an engine built before they were exposed still decodes.
    let dps: Double?
    let dps_with_reload: Double?
    let alpha: Double?
    let drone_dps: Double?
    let ehp: Double?
    let passive_shield_rate: Double?
    let shield_boost_rate: Double?
    let armor_repair_rate: Double?
    let hull_repair_rate: Double?
    let cap_depletes_in: Double?
}

// MARK:  Fit

/// Everything the engine needs to calculate one fit.
nonisolated struct DogmaFit: Sendable {
    let shipTypeID: Int
    var slots: [SimSlot]
    var droneTypeIDs: [Int] = []
    var implantTypeIDs: [Int] = []
    /// Modules sent as "Online" rather than "Active": passive modules (no capacitor need),
    /// or every module for an online-only calculation such as a fitting check.
    var passiveModuleTypeIDs: Set<Int> = []
}

// MARK:  Engine

/// Wraps the DogmaEngine C FFI (DogmaEngine.xcframework).
/// Call `prepare(pbDirPath:)` once after SDE data is downloaded, then `calculate(...)` from
/// any thread: the engine's loaded data is read-only, and each calculation builds its own
/// working state, so concurrent calls are safe.
nonisolated final class DogmaEngine: @unchecked Sendable {
    static let shared = DogmaEngine()

    /// Owns the native handle; destroyed when the last calculation using it lets go, so
    /// `prepare` can swap data without pulling it out from under one in flight.
    private final class Handle: @unchecked Sendable {
        let pointer: OpaquePointer
        init(_ pointer: OpaquePointer) { self.pointer = pointer }
        deinit { dogma_engine_destroy(pointer) }
    }

    private let handle = OSAllocatedUnfairLock<Handle?>(initialState: nil)

    private init() {}

    var isReady: Bool { handle.withLock { $0 != nil } }

    // MARK: Lifecycle

    func prepare(pbDirPath: String) {
        let loaded = dogma_engine_create(pbDirPath).map(Handle.init)
        handle.withLock { $0 = loaded }
        if loaded != nil {
            Self.log { $0.info("[DogmaEngine] Loaded SDE data from \(pbDirPath)") }
        } else {
            Self.log { $0.info("[DogmaEngine] Failed to load SDE data — check .pb2 files at \(pbDirPath)") }
        }
    }

    // MARK: Calculate

    func calculate(
        shipTypeId: Int,
        slots: [SimSlot],
        skills: [Int: Int],
        implantTypeIds: [Int] = [],
        passiveModuleTypeIds: Set<Int> = [],
        droneTypeIds: [Int] = []
    ) -> SimStats {
        calculate(DogmaFit(shipTypeID: shipTypeId, slots: slots, droneTypeIDs: droneTypeIds,
                           implantTypeIDs: implantTypeIds, passiveModuleTypeIDs: passiveModuleTypeIds),
                  skills: skills)
    }

    func calculate(_ fit: DogmaFit, skills: [Int: Int]) -> SimStats {
        guard let handle = handle.withLock({ $0 }) else {
            Self.log { $0.warning("[DogmaEngine] calculate() called before engine is ready (shipTypeId=\(fit.shipTypeID))") }
            return SimStats()
        }

        // Build module list from filled slots.
        // Rigs and subsystems are passive-only — the engine rejects "Active" for those
        // slot types and ignores the module entirely, so they must be sent as "Online".
        // Passive modules in activatable slot types (e.g. Shield Resistance Amplifiers in
        // medium slots, Energized Platings in low slots) have no activation cycle; sending
        // them as "Active" causes the engine to double-apply their bonus. The caller
        // identifies these via attr 6 (capacitorNeed) == 0 and passes them in passiveModuleTypeIDs.
        let modules: [EsfModule] = fit.slots.compactMap { slot in
            guard let typeId = slot.moduleTypeId else { return nil }
            let isPassive = slot.category.isPassiveOnly || fit.passiveModuleTypeIDs.contains(typeId)
            let onlineState = isPassive ? "Online" : "Active"
            return EsfModule(
                type_id: typeId,
                slot: EsfSlot(index: slot.index, slotType: slot.category.esfSlotType),
                state: slot.isOnline ? onlineState : "Passive",
                charge: slot.chargeTypeId.map { EsfCharge(type_id: $0) }
            )
        }
        // Drones in space, attacking — what drone DPS is measured against.
        let drones = fit.droneTypeIDs.map { EsfDrone(type_id: $0, state: "Active") }

        // Skills: BTreeMap<i32,i32> serialises to {"typeId": level} with string keys
        let skillsStringKeyed = Dictionary(uniqueKeysWithValues: skills.map { (String($0.key), $0.value) })

        let esfFit = EsfFit(ship_type_id: fit.shipTypeID, modules: modules, drones: drones, implants: fit.implantTypeIDs)

        guard let fitData    = try? JSONEncoder().encode(esfFit),
              let skillsData = try? JSONEncoder().encode(skillsStringKeyed),
              let fitStr     = String(data: fitData,    encoding: .utf8),
              let skillStr   = String(data: skillsData, encoding: .utf8)
        else {
            Self.log { $0.error("[DogmaEngine] JSON encoding failed — shipTypeId=\(fit.shipTypeID)") }
            return SimStats()
        }

        let resultPtr = withExtendedLifetime(handle) { dogma_engine_calculate(handle.pointer, fitStr, skillStr) }
        guard let resultPtr else {
            Self.log { $0.error("[DogmaEngine] calculate() returned null — shipTypeId=\(fit.shipTypeID) modules=\(modules.count) drones=\(drones.count) skills=\(skills.count) implants=\(fit.implantTypeIDs.count)") }
            return SimStats()
        }
        defer { dogma_engine_free_string(resultPtr) }

        let resultStr = String(cString: resultPtr)

        guard let resultData = resultStr.data(using: .utf8),
              let raw = try? JSONDecoder().decode(FfiSimStats.self, from: resultData)
        else {
            Self.log { $0.error("[DogmaEngine] Decode failed — shipTypeId=\(fit.shipTypeID) raw=\(resultStr)") }
            return SimStats()
        }

        return raw.toSimStats()
    }

    /// The app logger lives on the main actor; calculations may not.
    private static func log(_ write: @escaping @MainActor @Sendable (EVELogger) -> Void) {
        Task { @MainActor in write(Logger.dogmaEngine) }
    }
}

// MARK:  FfiSimStats → SimStats mapping

nonisolated private extension FfiSimStats {
    func toSimStats() -> SimStats {
        var stats = SimStats()

        stats.shieldHP = shield_hp
        stats.armorHP  = armor_hp
        stats.hullHP   = hull_hp

        // Engine returns resonances (1.0 = no resist, 0.0 = immune).
        // SimResists stores resistance percentages (0 = no resist, 100 = immune)
        // to match what SimResistBadge and computeEHP() expect.
        func res(_ r: Double) -> Double { (1.0 - r) * 100.0 }
        stats.shieldResists = SimResists(em: res(shield_em_res),  explosive: res(shield_exp_res),
                                     kinetic: res(shield_kin_res), thermal: res(shield_therm_res))
        stats.armorResists  = SimResists(em: res(armor_em_res),   explosive: res(armor_exp_res),
                                     kinetic: res(armor_kin_res),  thermal: res(armor_therm_res))
        stats.hullResists   = SimResists(em: res(hull_em_res),    explosive: res(hull_exp_res),
                                     kinetic: res(hull_kin_res),   thermal: res(hull_therm_res))

        stats.maxVelocity          = max_velocity
        stats.mass                 = mass
        stats.inertiaMod           = inertia_mod
        // EVE align time: T = −ln(0.25) × mass × inertiaMod / 1,000,000 = ln(4) × mass × inertiaMod / 1e6.
        // Compute from the engine's inertia_mod (which includes rig/module effects) rather than
        // align_time_sec, which the engine does not update when rigs modify inertia.
        let mI = mass * inertia_mod
        stats.alignTime = mI > 0 ? Foundation.log(4.0) * mI / 1_000_000.0 : align_time_sec
        // The engine JSON has warp_speed and max_locked_targets swapped relative to their
        // semantic meaning: the field named "max_locked_targets" carries the warp speed AU/s,
        // and the field named "warp_speed" carries the max locked targets count.
        stats.warpSpeed            = max_locked_targets
        stats.maxLockedTargets     = warp_speed
        stats.signatureRadius      = signature_radius
        stats.capacitorCapacity    = capacitor_capacity
        stats.rechargeRateSec      = capacitor_recharge_sec
        stats.shieldRechargeTimeSec = shield_recharge_sec
        stats.maxTargetRange       = max_target_range
        stats.scanResolution       = scan_resolution
        stats.sensorStrength       = sensor_strength
        stats.cpuTotal             = cpu_total
        stats.cpuUsed              = cpu_used
        stats.powerTotal           = power_total
        stats.powerUsed            = power_used
        stats.calibrationTotal     = calibration_total
        stats.calibrationUsed      = calibration_used
        stats.droneBandwidth       = drone_bandwidth
        stats.droneBayCapacity     = drone_bay_capacity
        stats.capDrainPerSec       = cap_drain_per_sec

        stats.dps                  = dps ?? 0
        stats.dpsWithReload        = dps_with_reload ?? 0
        stats.alpha                = alpha ?? 0
        stats.droneDPS             = drone_dps ?? 0
        stats.passiveShieldRate    = passive_shield_rate ?? 0
        stats.shieldBoostRate      = shield_boost_rate ?? 0
        stats.armorRepairRate      = armor_repair_rate ?? 0
        stats.hullRepairRate       = hull_repair_rate ?? 0
        // The engine reports a negative time when the capacitor is stable.
        stats.capDepletesIn        = cap_depletes_in.flatMap { $0 > 0 ? $0 : nil }

        // EHP stays Swift-side (per damage type, from resonances) — the engine's `ehp`
        // uses its own uniform damage profile, so it isn't mapped.
        stats.computeEHP()
        return stats
    }
}

// MARK:  SimSlotCategory → ESF slot type string

nonisolated private extension SimSlotCategory {
    // Must match EsfSlotType enum variant names in the Rust crate exactly.
    var esfSlotType: String {
        switch self {
        case .high:      "High"
        case .medium:    "Medium"
        case .low:       "Low"
        case .rig:       "Rig"
        case .subsystem: "SubSystem"
        }
    }
}
