//
//  DogmaLoadoutTests.swift
//  EVEOpsTests
//
//  Covers the loadout inferred for the dogma engine: which cargo charge a weapon takes
//  (charge group and size), drones launched within bandwidth and the active limit, and
//  splitting a fitted ship's slot assets into module and loaded charge. Pure inputs only.
//

import Foundation
import Testing
@testable import EVEOps

private let projectileAmmoGroup = 83
private let hybridAmmoGroup = 85
private let missileGroup = 385

private let autocannon = 2_873
private let launcher = 2_410
private let emsSmall = 178        // projectile, size 1
private let emsMedium = 179       // projectile, size 2
private let antimatter = 222      // hybrid, size 1
private let missile = 209
private let hobgoblin = 2_454     // 5 Mbit
private let hammerhead = 2_185    // 10 Mbit
private let rifter = 587
private let vexor = 626

private func type(_ id: Int, group: Int = 0, _ attributes: [Int: Double] = [:]) -> ESIType {
    ESIType(capacity: nil, description: nil,
            dogmaAttributes: attributes.map { ESIDogmaAttribute(attributeId: $0.key, value: $0.value) },
            dogmaEffects: nil, groupId: group, iconId: nil, marketGroupId: nil, mass: nil, name: "Type \(id)",
            packagedVolume: nil, portionSize: nil, published: true, radius: nil, typeId: id, volume: nil)
}

private let types: [Int: ESIType] = [
    autocannon: type(autocannon, [604: Double(projectileAmmoGroup), 128: 1]),
    launcher: type(launcher, [604: Double(missileGroup)]),
    emsSmall: type(emsSmall, group: projectileAmmoGroup, [128: 1]),
    emsMedium: type(emsMedium, group: projectileAmmoGroup, [128: 2]),
    antimatter: type(antimatter, group: hybridAmmoGroup, [128: 1]),
    missile: type(missile, group: missileGroup),
    hobgoblin: type(hobgoblin, [1272: 5]),
    hammerhead: type(hammerhead, [1272: 10]),
    rifter: type(rifter),
    vexor: type(vexor, [1271: 75]),
]

private func asset(_ id: Int, _ typeId: Int, flag: String, quantity: Int = 1, singleton: Bool = true) -> ESIAsset {
    ESIAsset(isBlueprintCopy: nil, isSingleton: singleton, itemId: id, locationFlag: flag, locationId: 1,
             locationType: "item", quantity: quantity, typeId: typeId)
}

struct DogmaLoadoutTests {
    @Test func picksFirstCargoChargeOfMatchingGroupAndSize() {
        let charge = DogmaLoadout.charge(for: types[autocannon]!, cargo: [antimatter, emsMedium, emsSmall], types: types)
        #expect(charge == emsSmall)
    }

    @Test func launcherWithoutChargeSizeTakesAnyChargeOfItsGroup() {
        #expect(DogmaLoadout.charge(for: types[launcher]!, cargo: [emsSmall, missile], types: types) == missile)
    }

    @Test func noChargeWhenNothingInCargoFits() {
        #expect(DogmaLoadout.charge(for: types[autocannon]!, cargo: [antimatter, emsMedium], types: types) == nil)
        #expect(DogmaLoadout.charge(for: types[hobgoblin]!, cargo: [emsSmall], types: types) == nil)
    }

    @Test func dronesFillBandwidthUpToTheActiveLimit() {
        // 75 Mbit: five Hammerheads would be 50, but the bay order puts 3 Hammerheads first.
        let drones = DogmaLoadout.activeDrones(bay: [(hammerhead, 3), (hobgoblin, 10)], ship: types[vexor], types: types)
        #expect(drones == [hammerhead, hammerhead, hammerhead, hobgoblin, hobgoblin])
    }

    @Test func dronesStopAtBandwidth() {
        let drones = DogmaLoadout.activeDrones(bay: [(hammerhead, 10)], ship: type(vexor, [1271: 25]), types: types)
        #expect(drones == [hammerhead, hammerhead])
    }

    @Test func noDronesWithoutBandwidthOrKnownDrones() {
        #expect(DogmaLoadout.activeDrones(bay: [(hobgoblin, 5)], ship: types[rifter], types: types).isEmpty)
        #expect(DogmaLoadout.activeDrones(bay: [(9_999, 5)], ship: types[vexor], types: types).isEmpty)
    }

    @Test func splitsSlotAssetsIntoModuleAndLoadedCharge() {
        let assets = [
            asset(1, emsSmall, flag: "HiSlot0", quantity: 120, singleton: false),
            asset(2, autocannon, flag: "HiSlot0"),
            asset(3, autocannon, flag: "HiSlot1"),
        ]
        let split = DogmaLoadout.splitSlotAssets(assets, types: types)
        #expect(split["HiSlot0"]?.module == autocannon)
        #expect(split["HiSlot0"]?.charge == emsSmall)
        #expect(split["HiSlot1"]?.module == autocannon)
        #expect(split["HiSlot1"]?.charge == nil)
    }

    @Test func splitFallsBackToSingletonWhenTypesAreUnknown() {
        let assets = [asset(1, 70_001, flag: "MedSlot0", quantity: 1, singleton: false),
                      asset(2, 70_000, flag: "MedSlot0")]
        let split = DogmaLoadout.splitSlotAssets(assets, types: [:])
        #expect(split["MedSlot0"]?.module == 70_000)
        #expect(split["MedSlot0"]?.charge == 70_001)
    }

    @MainActor
    @Test func applyLoadsChargesFromCargoAndPicksDrones() {
        var slots = [SimSlot(category: .high, index: 0, moduleTypeId: autocannon),
                     SimSlot(category: .high, index: 1, moduleTypeId: launcher),
                     SimSlot(category: .high, index: 2)]
        let items = [ESIFittingItem(flag: "Cargo", quantity: 1000, typeId: emsSmall),
                     ESIFittingItem(flag: "DroneBay", quantity: 5, typeId: hobgoblin)]
        let drones = DogmaLoadout.apply(items: items, to: &slots, ship: types[vexor], types: types)
        #expect(slots.map(\.chargeTypeId) == [emsSmall, nil, nil])
        #expect(drones == Array(repeating: hobgoblin, count: 5))
    }

    @MainActor
    @Test func swappingTheModuleUnloadsItsCharge() {
        var slot = SimSlot(category: .high, index: 0, moduleTypeId: autocannon, chargeTypeId: emsSmall)
        slot.moduleTypeId = autocannon
        #expect(slot.chargeTypeId == emsSmall)
        slot.moduleTypeId = launcher
        #expect(slot.chargeTypeId == nil)
    }
}

// MARK: - Engine (needs the cached SDE)

private let sdeDir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
    .appendingPathComponent("EVEOps/sde2").path
private let hasSDE = FileManager.default.fileExists(atPath: sdeDir + "/dogmaAttributes.pb2")

/// Runs a real fit through the dogma engine end to end — only where the app has already
/// downloaded its SDE data, since the engine can't run without it.
@MainActor
@Suite(.enabled(if: hasSDE, "SDE not cached — launch the app once to download it"))
struct DogmaEngineOffenseTests {
    private let blaster = 3_146, voidM = 12_789, droneAmp = 4_405
    private let skills = [3_300: 5, 3_315: 5, 3_304: 5, 3_436: 5, 3_442: 5, 3_332: 5]

    private func stats(skills: [Int: Int], ammo: Bool = true, drones: Bool = true) -> SimStats {
        DogmaEngine.shared.prepare(pbDirPath: sdeDir)
        let slots = (0..<4).map { SimSlot(category: .high, index: $0, moduleTypeId: blaster, chargeTypeId: ammo ? voidM : nil) }
            + (0..<2).map { SimSlot(category: .low, index: $0, moduleTypeId: droneAmp) }
        return DogmaEngine.shared.calculate(shipTypeId: vexor, slots: slots, skills: skills,
                                            passiveModuleTypeIds: [droneAmp],
                                            droneTypeIds: drones ? Array(repeating: hammerhead, count: 5) : [])
    }

    @Test func reportsWeaponAndDroneDPS() {
        let s = stats(skills: skills)
        #expect(s.weaponDPS > 100)
        #expect(s.droneDPS > 100)
        #expect(s.alpha > 0)
        #expect(s.dpsWithReload > 0 && s.dpsWithReload <= s.dps)
    }

    @Test func noAmmoAndNoDronesMeansNoDPS() {
        #expect(stats(skills: skills, ammo: false, drones: false).dps == 0)
    }

    @Test func supportSkillsMoveTheirOwnDamage() {
        let all = stats(skills: skills)
        var surgical = skills; surgical[3_315] = 4
        var interfacing = skills; interfacing[3_442] = 4
        let lessGun = stats(skills: surgical), lessDrone = stats(skills: interfacing)
        #expect(lessGun.weaponDPS < all.weaponDPS)
        #expect(lessGun.droneDPS == all.droneDPS)
        #expect(lessDrone.droneDPS < all.droneDPS)
    }
}
