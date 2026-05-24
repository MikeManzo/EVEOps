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

private struct EsfFit: Encodable {
    let ship_type_id: Int
    let modules: [EsfModule]
    let drones: [EsfDrone]
}

private struct EsfModule: Encodable {
    let type_id: Int
    let slot: EsfSlot
    let state: String       // "Passive" | "Online" | "Active" | "Overload"
    let charge: EsfCharge?
}

private struct EsfSlot: Encodable {
    let index: Int
    // "type" is a reserved keyword — CodingKeys maps slotType → "type"
    let slotType: String
    enum CodingKeys: String, CodingKey {
        case slotType = "type"
        case index
    }
}

private struct EsfCharge: Encodable {
    let type_id: Int
}

private struct EsfDrone: Encodable {
    let type_id: Int
    let state: String
}

// MARK:  Output model (must match Rust FfiSimStats serde layout exactly)

private struct FfiSimStats: Decodable {
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
}

// MARK:  Engine

/// Wraps the DogmaEngine C FFI (DogmaEngine.xcframework).
/// Call `prepare(pbDirPath:)` once after SDE data is downloaded,
/// then call `calculate(...)` from SimulatorState.recomputeStats().
@MainActor
final class DogmaEngine {
    static let shared = DogmaEngine()

    private var handle: OpaquePointer?
    private(set) var isReady = false

    private init() {}

    // MARK: Lifecycle

    func prepare(pbDirPath: String) {
        if let existing = handle {
            dogma_engine_destroy(existing)
            handle = nil
            isReady = false
        }
        handle = dogma_engine_create(pbDirPath)
        isReady = handle != nil
        if isReady {
            Logger.dogmaEngine.info("[DogmaEngine] Loaded SDE data from \(pbDirPath)")
        } else {
            Logger.dogmaEngine.info("[DogmaEngine] Failed to load SDE data — check .pb2 files at \(pbDirPath)")
        }
    }

    deinit {
        if let h = handle { dogma_engine_destroy(h) }
    }

    // MARK: Calculate

    func calculate(
        shipTypeId: Int,
        slots: [SimSlot],
        skills: [Int: Int],
        implantTypeIds: [Int] = []
    ) -> SimStats {
        guard let handle, isReady else { return SimStats() }

        // Build module list from filled slots
        let modules: [EsfModule] = slots.compactMap { slot in
            guard let typeId = slot.moduleTypeId else { return nil }
            return EsfModule(
                type_id: typeId,
                slot: EsfSlot(index: slot.index, slotType: slot.category.esfSlotType),
                state: "Active",   // active = hardeners/propulsion on; matches in-game fitting view
                charge: nil
            )
        }

        // Implants are passed as extra modules in the implicit "None" slot
        // The dogma engine treats them as items on the character, but since we
        // have no separate implant slot type, we add them with state Online.
        // Note: full implant support may require engine-side changes in a future pass.

        // Skills: BTreeMap<i32,i32> serialises to {"typeId": level} with string keys
        let skillsStringKeyed = Dictionary(uniqueKeysWithValues: skills.map { (String($0.key), $0.value) })

        let fit = EsfFit(ship_type_id: shipTypeId, modules: modules, drones: [])

        guard let fitData    = try? JSONEncoder().encode(fit),
              let skillsData = try? JSONEncoder().encode(skillsStringKeyed),
              let fitStr     = String(data: fitData,    encoding: .utf8),
              let skillStr   = String(data: skillsData, encoding: .utf8)
        else {
            Logger.dogmaEngine.info("[DogmaEngine] JSON encoding failed")
            return SimStats()
        }

        guard let resultPtr = dogma_engine_calculate(handle, fitStr, skillStr) else {
            Logger.dogmaEngine.info("[DogmaEngine] calculate() returned null — check fit/skills JSON and .pb2 data")
            return SimStats()
        }
        defer { dogma_engine_free_string(resultPtr) }

        let resultStr = String(cString: resultPtr)
        guard let resultData = resultStr.data(using: .utf8),
              let raw = try? JSONDecoder().decode(FfiSimStats.self, from: resultData)
        else {
            Logger.dogmaEngine.info("[DogmaEngine] Failed to decode result JSON: \(resultStr)")
            return SimStats()
        }

        return raw.toSimStats()
    }
}

// MARK:  FfiSimStats → SimStats mapping

private extension FfiSimStats {
    func toSimStats() -> SimStats {
        var s = SimStats()

        s.shieldHP = shield_hp
        s.armorHP  = armor_hp
        s.hullHP   = hull_hp

        // Engine returns resonances (1.0 = no resist, 0.0 = immune).
        // SimResists stores resistance percentages (0 = no resist, 100 = immune)
        // to match what SimResistBadge and computeEHP() expect.
        func res(_ r: Double) -> Double { (1.0 - r) * 100.0 }
        s.shieldResists = SimResists(em: res(shield_em_res),  explosive: res(shield_exp_res),
                                     kinetic: res(shield_kin_res), thermal: res(shield_therm_res))
        s.armorResists  = SimResists(em: res(armor_em_res),   explosive: res(armor_exp_res),
                                     kinetic: res(armor_kin_res),  thermal: res(armor_therm_res))
        s.hullResists   = SimResists(em: res(hull_em_res),    explosive: res(hull_exp_res),
                                     kinetic: res(hull_kin_res),   thermal: res(hull_therm_res))

        s.maxVelocity          = max_velocity
        s.alignTime            = align_time_sec
        s.mass                 = mass
        s.inertiaMod           = inertia_mod
        s.warpSpeed            = warp_speed
        s.signatureRadius      = signature_radius
        s.capacitorCapacity    = capacitor_capacity
        s.rechargeRateSec      = capacitor_recharge_sec
        s.shieldRechargeTimeSec = shield_recharge_sec
        s.maxTargetRange       = max_target_range
        s.scanResolution       = scan_resolution
        s.maxLockedTargets     = max_locked_targets
        s.sensorStrength       = sensor_strength
        s.cpuTotal             = cpu_total
        s.cpuUsed              = cpu_used
        s.powerTotal           = power_total
        s.powerUsed            = power_used
        s.calibrationTotal     = calibration_total
        s.calibrationUsed      = calibration_used
        s.droneBandwidth       = drone_bandwidth
        s.droneBayCapacity     = drone_bay_capacity
        s.capDrainPerSec       = cap_drain_per_sec

        s.computeEHP()
        return s
    }
}

// MARK:  SimSlotCategory → ESF slot type string

private extension SimSlotCategory {
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
