//
//  HangarForgeEngineTests.swift
//  EVEOpsTests
//
//  Covers Hangar Forge's search: which hulls and stock it considers, the goal scores,
//  hardpoints, ammo, skills, owned quantities and group limits, CPU upgrades, keeping
//  shield and armor apart, capacitor stability and drones. Dogma is a small fake model —
//  each fake attribute adds straight to one stat — so the tests check the search, not
//  the real engine.
//

import Foundation
import Testing
@testable import EVEOps

// MARK: - Fake Dogma

private enum Fake {
    static let shieldHP = 90_001
    static let armorHP = 90_002
    /// Weapon DPS, counted only when the weapon has a charge loaded.
    static let weaponDPS = 90_003
    /// Percent added to weapon DPS.
    static let damageBonus = 90_004
    /// GJ/s drawn while active.
    static let capDrain = 90_005
    static let cpuAdded = 90_007
    static let velocity = 90_008
    static let droneDPS = 90_009
    static let armorRepair = 90_010
}

private let cpuOutput = 48, powerOutput = 11, cpuUse = 50, powerUse = 30

/// Peak cap recharge on every fake hull: 2.5 × 1000 / 250 = 10 GJ/s.
private func fakeDogma(_ types: [Int: ESIType]) -> HangarForgeEngine.Evaluator {
    { fit in
        guard let hull = types[fit.shipTypeID] else { return SimStats() }
        func value(_ type: ESIType, _ id: Int) -> Double { type.attribute(id) ?? 0 }
        var stats = SimStats()
        stats.cpuTotal = value(hull, cpuOutput)
        stats.powerTotal = value(hull, powerOutput)
        stats.calibrationTotal = 400
        stats.shieldHP = value(hull, Fake.shieldHP)
        stats.armorHP = value(hull, Fake.armorHP)
        stats.hullHP = 500
        stats.maxVelocity = 200
        stats.capacitorCapacity = 1_000
        stats.rechargeRateSec = 250
        var weapons = 0.0, bonus = 1.0
        for slot in fit.slots {
            guard let id = slot.moduleTypeId, let module = types[id] else { continue }
            stats.cpuUsed += value(module, cpuUse)
            stats.powerUsed += value(module, powerUse)
            stats.cpuTotal += value(module, Fake.cpuAdded)
            stats.shieldHP += value(module, Fake.shieldHP)
            stats.armorHP += value(module, Fake.armorHP)
            stats.maxVelocity += value(module, Fake.velocity)
            stats.armorRepairRate += value(module, Fake.armorRepair)
            if slot.chargeTypeId != nil { weapons += value(module, Fake.weaponDPS) }
            bonus *= 1 + value(module, Fake.damageBonus) / 100
            if !fit.passiveModuleTypeIDs.contains(id) { stats.capDrainPerSec += value(module, Fake.capDrain) }
        }
        stats.droneDPS = fit.droneTypeIDs.compactMap { types[$0] }.reduce(0) { $0 + value($1, Fake.droneDPS) }
        stats.dps = weapons * bonus + stats.droneDPS
        stats.computeEHP()
        return stats
    }
}

// MARK: - Fixtures

private let jita = 60_003_760
private let amarr = 60_008_494
private let hullItem = 1_000

private let cruiserGroup = 26
private let strategicGroup = 963

private let thorax = 627
private let tengu = 29_984
private let gun = 3_082
private let ammo = 222
private let ammoGroup = 85
private let gyro = 519
private let plate = 11_303
private let extender = 3_841
private let damageControl = 2_046
private let coprocessor = 1_317
private let heavyGun = 3_090
private let repairer = 3_530
private let lightDrone = 2_486
private let mediumDrone = 2_185

private let high = 12, medium = 13, low = 11

private func type(_ id: Int, group: Int = 0, effects: [Int] = [], _ attributes: [Int: Double] = [:],
                  volume: Double? = nil) -> ESIType {
    ESIType(capacity: nil, description: nil,
            dogmaAttributes: attributes.map { ESIDogmaAttribute(attributeId: $0.key, value: $0.value) },
            dogmaEffects: effects.map { ESIDogmaEffect(effectId: $0, isDefault: false) },
            groupId: group, iconId: nil, marketGroupId: nil, mass: nil, name: "Type \(id)",
            packagedVolume: nil, portionSize: nil, published: true, radius: nil, typeId: id, volume: volume)
}

private func hull(highs: Double = 3, mediums: Double = 2, lows: Double = 2, turrets: Double = 2,
                  cpu: Double = 300, bandwidth: Double = 0) -> ESIType {
    type(thorax, group: cruiserGroup, [
        HangarForgeEngine.hiSlotsAttribute: highs, HangarForgeEngine.medSlotsAttribute: mediums,
        HangarForgeEngine.lowSlotsAttribute: lows, HangarForgeEngine.turretSlotsAttribute: turrets,
        cpuOutput: cpu, powerOutput: 1_000, Fake.shieldHP: 500, Fake.armorHP: 500,
        DogmaLoadout.droneBandwidthAttribute: bandwidth, HangarForgeEngine.droneCapacityAttribute: 500,
    ])
}

private let catalog: [Int: ESIType] = [
    gun: type(gun, effects: [high, HangarForgeEngine.turretFittedEffect],
              [Fake.weaponDPS: 50, cpuUse: 20, DogmaLoadout.chargeGroupAttributes[0]: Double(ammoGroup)]),
    heavyGun: type(heavyGun, effects: [high, HangarForgeEngine.turretFittedEffect],
                   [Fake.weaponDPS: 200, cpuUse: 150, DogmaLoadout.chargeGroupAttributes[0]: Double(ammoGroup)]),
    ammo: type(ammo, group: ammoGroup),
    gyro: type(gyro, group: 59, effects: [low], [Fake.damageBonus: 20, cpuUse: 1]),
    plate: type(plate, group: 329, effects: [low], [Fake.armorHP: 1_000, cpuUse: 1]),
    extender: type(extender, group: 38, effects: [medium], [Fake.shieldHP: 1_000, cpuUse: 1]),
    damageControl: type(damageControl, group: 60, effects: [low],
                        [Fake.shieldHP: 100, Fake.armorHP: 100, cpuUse: 1, HangarForgeEngine.maxGroupFittedAttribute: 1]),
    coprocessor: type(coprocessor, group: 285, effects: [low], [Fake.cpuAdded: 100]),
    repairer: type(repairer, group: 62, effects: [low],
                   [Fake.armorRepair: 50, Fake.capDrain: 15, HangarForgeEngine.capacitorNeedAttribute: 100]),
    lightDrone: type(lightDrone, [DogmaLoadout.droneBandwidthUsedAttribute: 5, Fake.droneDPS: 10], volume: 5),
    mediumDrone: type(mediumDrone, [DogmaLoadout.droneBandwidthUsedAttribute: 10, Fake.droneDPS: 30], volume: 10),
]

private func holding(_ itemID: Int, type: Int, quantity: Int = 1, at place: Int = jita,
                     fittedTo: Int? = nil, assembled: Bool = false, corporation: Bool = false) -> ReadyRoomHolding {
    ReadyRoomHolding(itemID: itemID, typeID: type, quantity: quantity, placeID: place,
                     fittedToItemID: fittedTo, isAssembled: assembled, isCorporation: corporation)
}

private let forgeHull = HangarForgeHull(itemID: hullItem, typeID: thorax, placeID: jita, isAssembled: true,
                                        isCorporation: false, missingSkills: [:], isSupported: true)

/// Stock in the hull's station: type → quantity.
private func forge(_ stock: [Int: Int], hull hullType: ESIType = hull(), options: HangarForgeOptions = .init(),
                   requirements: [Int: [Int: Int]] = [:], skills: [Int: Int] = [:]) async throws -> HangarForgeResult {
    var types = catalog
    types[thorax] = hullType
    var holdings = [holding(hullItem, type: thorax, assembled: true)]
    for (index, (typeID, quantity)) in stock.sorted(by: { $0.key < $1.key }).enumerated() {
        holdings.append(holding(2_000 + index, type: typeID, quantity: quantity))
    }
    let input = HangarForgeInput(
        hull: forgeHull, holdings: holdings, types: types,
        requirements: types.mapValues { _ in [:] }.merging(requirements) { _, new in new },
        skills: skills, implants: []
    )
    return try await HangarForgeEngine.build(input, options: options, evaluate: fakeDogma(types))
}

private func modules(_ result: HangarForgeResult, _ category: SimSlotCategory) -> [Int] {
    result.picks.filter { $0.category == category }.map(\.typeID).sorted()
}

// MARK: - Hulls and Stock

@Test func hullsListOwnedShipsWithFlyabilityAndSupport() {
    let types = [thorax: hull(), tengu: type(tengu, group: strategicGroup, [HangarForgeEngine.maxSubSystemsAttribute: 5]),
                 gyro: catalog[gyro]!]
    let holdings = [
        holding(1, type: thorax, assembled: true),
        holding(2, type: tengu, at: amarr),
        holding(3, type: gyro, fittedTo: 1),
    ]
    let hulls = HangarForgeEngine.hulls(holdings: holdings, types: types, shipGroupIDs: [cruiserGroup, strategicGroup],
                                        requirements: [thorax: [3_332: 3], tengu: [:]], skills: [3_332: 2])
    #expect(hulls.map(\.typeID) == [thorax, tengu])
    #expect(hulls[0].missingSkills == [3_332: 3])
    #expect(!hulls[0].isFlyable)
    #expect(hulls[0].isSupported)
    #expect(hulls[1].isFlyable)
    #expect(!hulls[1].isSupported)
}

@Test func stockFollowsTheChosenScope() {
    let holdings = [
        holding(hullItem, type: thorax, assembled: true),
        holding(10, type: gyro, fittedTo: hullItem),          // on this hull: always in
        holding(11, type: plate),                             // loose, same station
        holding(12, type: extender, at: amarr),               // another station
        holding(13, type: damageControl, fittedTo: 99),       // on another ship
        holding(14, type: coprocessor, corporation: true),    // corporation hangar
    ]
    let narrow = HangarForgeEngine.stock(for: forgeHull, holdings: holdings, options: .init())
    #expect(Set(narrow.keys) == [gyro, plate])

    var wide = HangarForgeOptions()
    wide.anywhere = true
    wide.includeFittedElsewhere = true
    wide.includeCorporation = true
    let everything = HangarForgeEngine.stock(for: forgeHull, holdings: holdings, options: wide)
    #expect(Set(everything.keys) == [gyro, plate, extender, damageControl, coprocessor])
}

// MARK: - Score

@Test func scoreRejectsOverloadedAndCapUnstableFits() {
    var stats = SimStats()
    stats.shieldHP = 1_000
    stats.cpuTotal = 100
    stats.cpuUsed = 120
    stats.capacitorCapacity = 1_000
    stats.rechargeRateSec = 250
    #expect(HangarForgeEngine.score(stats, options: .init()) == nil)

    stats.cpuUsed = 80
    stats.capDrainPerSec = 20
    #expect(HangarForgeEngine.score(stats, options: .init()) != nil)
    var stable = HangarForgeOptions()
    stable.requireCapStable = true
    #expect(HangarForgeEngine.score(stats, options: stable) == nil)
    #expect(HangarForgeEngine.score(stats, options: HangarForgeOptions(goal: .kite)) == nil)
}

// MARK: - Build

@Test func fillsHardpointsWithLoadedWeapons() async throws {
    let result = try await forge([gun: 4, ammo: 1_000], options: .init(goal: .damage))
    #expect(modules(result, .high) == [gun, gun])
    #expect(result.picks.filter { $0.typeID == gun }.allSatisfy { $0.chargeTypeID == ammo })
    #expect(result.openSlots[.high] == 1)
    #expect(result.performance.dps == 100)
    #expect(result.needs[ammo] == 1_000)
}

@Test func goalsTradeDamageForTank() async throws {
    let stock = [gun: 2, ammo: 1_000, gyro: 2, plate: 2]
    let damage = try await forge(stock, options: .init(goal: .damage))
    #expect(modules(damage, .low) == [gyro, gyro])
    let tank = try await forge(stock, options: .init(goal: .tank))
    #expect(modules(tank, .low) == [plate, plate].sorted())
}

@Test func keepsShieldAndArmorApart() async throws {
    let result = try await forge([gun: 2, ammo: 1_000, extender: 2, plate: 2, gyro: 2])
    let fitted = Set(result.picks.map(\.typeID))
    #expect(!(fitted.contains(extender) && fitted.contains(plate)))
}

@Test func addsAFittingUpgradeWhenItUnlocksAModule() async throws {
    let tight = hull(cpu: 100)
    let withUpgrade = try await forge([heavyGun: 1, ammo: 100, coprocessor: 1], hull: tight)
    #expect(modules(withUpgrade, .high) == [heavyGun])
    #expect(modules(withUpgrade, .low) == [coprocessor])

    let without = try await forge([heavyGun: 1, ammo: 100], hull: tight)
    #expect(without.picks.isEmpty)
}

@Test func skipsModulesThePilotCantUse() async throws {
    let result = try await forge([gun: 2, ammo: 100, gyro: 2], options: .init(goal: .damage),
                                 requirements: [gyro: [3_300: 5]], skills: [3_300: 4])
    #expect(!result.picks.contains { $0.typeID == gyro })
}

@Test func ownedQuantitiesAndGroupLimitsCapWhatsFitted() async throws {
    let result = try await forge([damageControl: 3, gyro: 1, gun: 1, ammo: 100], hull: hull(lows: 4),
                                 options: .init(goal: .tank))
    let lows = modules(result, .low)
    #expect(lows.filter { $0 == damageControl }.count == 1)
    #expect(lows.filter { $0 == gyro }.count <= 1)
}

@Test func capStableRuleDropsCapHungryModules() async throws {
    let loose = try await forge([repairer: 1], options: .init(goal: .tank))
    #expect(modules(loose, .low) == [repairer])

    var stable = HangarForgeOptions(goal: .tank)
    stable.requireCapStable = true
    let strict = try await forge([repairer: 1], options: stable)
    #expect(strict.picks.isEmpty)
}

@Test func dronesMixTypesToFillBandwidth() async throws {
    let result = try await forge([lightDrone: 10, mediumDrone: 2], hull: hull(bandwidth: 25),
                                 options: .init(goal: .damage))
    #expect(result.drones == [lightDrone, mediumDrone, mediumDrone].sorted())
    #expect(result.performance.dps == 70)
    #expect(result.withoutDrones?.dps == 0)
}

@Test func refusesHullsItCantBuild() async throws {
    let types = [thorax: hull()]
    func input(_ hull: HangarForgeHull) -> HangarForgeInput {
        HangarForgeInput(hull: hull, holdings: [], types: types, requirements: [:], skills: [:], implants: [])
    }
    let unflyable = HangarForgeHull(itemID: 1, typeID: thorax, placeID: jita, isAssembled: true, isCorporation: false,
                                    missingSkills: [3_332: 1], isSupported: true)
    await #expect(throws: HangarForgeFailure.notFlyable) {
        try await HangarForgeEngine.build(input(unflyable), options: .init(), evaluate: fakeDogma(types))
    }
    await #expect(throws: HangarForgeFailure.engineUnavailable) {
        try await HangarForgeEngine.build(input(forgeHull), options: .init(), evaluate: { _ in SimStats() })
    }
}

// MARK: - Headline

private func performance(dps: Double = 0, ehp: Double = 10_000, tank: Double = 0, speed: Double = 300) -> FitPerformance {
    var stats = SimStats()
    stats.dps = dps
    stats.ehp = SimEHPProfile(em: ehp, explosive: ehp, kinetic: ehp, thermal: ehp)
    stats.armorRepairRate = tank
    stats.maxVelocity = speed
    return FitPerformance(stats)
}

@Test func headlinePrefersWhatTheGoalValuesOverTheBiggestPercentage() {
    // A shield extender: regen 1 → 3.2 HP/s (+220%) but EHP 8,000 → 11,000 is the point.
    let extender = HangarForgeEngine.headline(without: performance(ehp: 8_000, tank: 1),
                                              with: performance(ehp: 11_000, tank: 3.2), goal: .balanced)
    #expect(extender == .ehp)

    // A repairer adds no EHP, only repair.
    let repairer = HangarForgeEngine.headline(without: performance(), with: performance(tank: 50), goal: .balanced)
    #expect(repairer == .tank)

    // Weapons still read as DPS on a tank build.
    let weapon = HangarForgeEngine.headline(without: performance(dps: 100), with: performance(dps: 150), goal: .tank)
    #expect(weapon == .dps)

    // Speed only counts toward Kite; elsewhere there's no goal headline.
    let propulsion = (without: performance(speed: 300), with: performance(speed: 1_500))
    #expect(HangarForgeEngine.headline(without: propulsion.without, with: propulsion.with, goal: .balanced) == nil)
    #expect(HangarForgeEngine.headline(without: propulsion.without, with: propulsion.with, goal: .kite) == .speed)
}
