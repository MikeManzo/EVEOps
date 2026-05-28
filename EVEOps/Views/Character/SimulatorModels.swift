//
// SimulatorModels.swift
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

    // Rigs and subsystems can't be activated — send "Online" not "Active" to the engine,
    // otherwise it ignores the module entirely and applies none of its passive effects.
    var isPassiveOnly: Bool { self == .rig || self == .subsystem }

}

// MARK:  Sim Slot

struct SimSlot: Identifiable, Equatable {
    let id: UUID
    let category: SimSlotCategory
    let index: Int
    var moduleTypeId: Int?
    var isOnline: Bool = true

    init(category: SimSlotCategory, index: Int, moduleTypeId: Int? = nil, isOnline: Bool = true) {
        self.id = UUID()
        self.category = category
        self.index = index
        self.moduleTypeId = moduleTypeId
        self.isOnline = isOnline
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
}

// MARK:  Sim EHP Profile

/// Per-damage-type effective HP summed across all three defence layers.
/// Each value is computed from the layer's actual resonance, not an average.
struct SimEHPProfile {
    var em: Double = 0
    var explosive: Double = 0
    var kinetic: Double = 0
    var thermal: Double = 0

    /// Worst-case EHP — the damage type this ship is most vulnerable to.
    var minimum: Double { min(em, min(explosive, min(kinetic, thermal))) }
    var hasData: Bool { em > 0 }
}

// MARK:  Implant Contribution

struct ImplantContribution: Identifiable {
    let typeId: Int
    let name: String
    let bonuses: [String]
    var id: Int { typeId }
}

// MARK:  Training Contribution

struct TrainingContribution: Identifiable {
    let typeId: Int
    let name: String
    let level: Int
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
    var ehp = SimEHPProfile()
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
    // Capacitor drain from active modules (GJ/s, assuming all active simultaneously)
    var capDrainPerSec: Double = 0
    // Drones
    var droneBandwidth: Double = 0
    var droneBayCapacity: Double = 0

    var passiveCapRechargePerSec: Double {
        // EVE cap regen: rate(C) = 10·C_max/τ·(√(C/C_max) − C/C_max)
        // Peak occurs at C = 0.25·C_max → peakRate = 2.5·C_max/τ
        guard rechargeRateSec > 0 else { return 0 }
        return 2.5 * capacitorCapacity / rechargeRateSec
    }
    var netCapGJps: Double { passiveCapRechargePerSec - capDrainPerSec }
    var isCapStable: Bool { netCapGJps >= 0 }

    var hasData: Bool { shieldHP > 0 || armorHP > 0 || hullHP > 0 }
    var implantContributions: [ImplantContribution] = []
    var trainingContributions: [TrainingContribution] = []

    /// Populates `ehp` from the current HP and resistance values.
    /// Resistance values are percentages (0 = no resist, 100 = immune).
    mutating func computeEHP() {
        func layerEHP(_ hp: Double, _ pct: Double) -> Double {
            let resonance = 1.0 - pct / 100.0
            guard resonance > 1e-6 else { return hp > 0 ? 1e12 : 0 }
            return hp / resonance
        }
        ehp.em        = layerEHP(shieldHP, shieldResists.em)        + layerEHP(armorHP, armorResists.em)        + layerEHP(hullHP, hullResists.em)
        ehp.explosive = layerEHP(shieldHP, shieldResists.explosive)  + layerEHP(armorHP, armorResists.explosive)  + layerEHP(hullHP, hullResists.explosive)
        ehp.kinetic   = layerEHP(shieldHP, shieldResists.kinetic)    + layerEHP(armorHP, armorResists.kinetic)    + layerEHP(hullHP, hullResists.kinetic)
        ehp.thermal   = layerEHP(shieldHP, shieldResists.thermal)    + layerEHP(armorHP, armorResists.thermal)    + layerEHP(hullHP, hullResists.thermal)
    }
}
