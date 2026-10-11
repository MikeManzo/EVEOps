//
//  EscapeCheckEngineTests.swift
//  EVEOpsTests
//
//  Covers the gate camp escape check: rounding align time up to server ticks, the
//  verdict thresholds, telling covert ops cloaks, microwarpdrives and agility gear apart
//  from look-alikes, which suggestions each fit gets, and reading fitted slots from assets.
//

import Foundation
import Testing
@testable import EVEOps

private let covertCloak = 11_578, prototypeCloak = 11_370
private let mwd = 440, afterburner = 438
private let inertiaStab = 1_405, nanofiber = 2_605
private let nozzleJoints = 26_058, hyperspatialRig = 26_060
private let badger = 648, rifter = 587

private func type(_ id: Int, group: Int, _ attributes: [Int: Double] = [:]) -> ESIType {
    ESIType(capacity: nil, description: nil,
            dogmaAttributes: attributes.map { ESIDogmaAttribute(attributeId: $0.key, value: $0.value) },
            dogmaEffects: nil, groupId: group, iconId: nil, marketGroupId: nil, mass: nil, name: "Type \(id)",
            packagedVolume: nil, portionSize: nil, published: true, radius: nil, typeId: id, volume: nil)
}

private let types: [Int: ESIType] = [
    covertCloak: type(covertCloak, group: 330, [1298: 963]),
    prototypeCloak: type(prototypeCloak, group: 330, [565: 0.5]),
    mwd: type(mwd, group: 46, [554: 500]),
    afterburner: type(afterburner, group: 46),
    inertiaStab: type(inertiaStab, group: 762),
    nanofiber: type(nanofiber, group: 763),
    nozzleJoints: type(nozzleJoints, group: 782, [151: -11.7]),
    hyperspatialRig: type(hyperspatialRig, group: 782, [1281: 20]),
]

private func check(align: Double, modules: [Int] = [], group: Int? = 25) -> EscapeCheck {
    EscapeCheckEngine.check(shipTypeID: rifter, shipName: nil, alignTime: align, warpSpeed: 5,
                            fitKnown: true, shipGroupID: group, modules: modules, types: types)
}

@Suite("Escape check")
struct EscapeCheckEngineTests {
    @Test("Align time rounds up to whole server ticks")
    func ticks() {
        #expect(EscapeCheckEngine.ticks(1.4) == 2)
        #expect(EscapeCheckEngine.ticks(2.0) == 2)
        #expect(EscapeCheckEngine.ticks(2.0000001) == 2)
        #expect(EscapeCheckEngine.ticks(2.01) == 3)
        #expect(EscapeCheckEngine.ticks(0.9) == 1)
    }

    @Test("Verdict thresholds: two ticks or fewer, up to four, five or more")
    func thresholds() {
        #expect(check(align: 1.9).verdict == .hardToCatch)
        #expect(check(align: 2.0).verdict == .hardToCatch)
        #expect(check(align: 2.1).verdict == .catchableByFastLockers)
        #expect(check(align: 4.0).verdict == .catchableByFastLockers)
        #expect(check(align: 4.2).verdict == .catchable)
        #expect(check(align: 12).verdict == .catchable)
    }

    @Test("A covert ops cloak beats any align time")
    func covertCloakWins() {
        let result = check(align: 9, modules: [covertCloak])
        #expect(result.verdict == .warpsCloaked)
        #expect(result.suggestions == [.warpCloaked])
    }

    @Test("Gear: covert vs prototype cloak, MWD vs afterburner, agility modules and rigs")
    func gear() {
        let all = EscapeCheckEngine.gear(
            modules: [prototypeCloak, afterburner, inertiaStab, nanofiber, nozzleJoints, hyperspatialRig],
            types: types)
        #expect(all == EscapeGear(covertCloak: false, cloak: true, microwarpdrive: false, agilityModules: 3))

        let covert = EscapeCheckEngine.gear(modules: [covertCloak, mwd], types: types)
        #expect(covert == EscapeGear(covertCloak: true, cloak: false, microwarpdrive: true, agilityModules: 0))
    }

    @Test("Hard-to-catch ships get no suggestions")
    func noSuggestionsWhenFast() {
        #expect(check(align: 1.8, modules: [mwd]).suggestions.isEmpty)
    }

    @Test("Cloak and MWD fitted: use the trick, then agility")
    func cloakTrick() {
        let result = check(align: 5, modules: [prototypeCloak, mwd])
        #expect(result.suggestions.first == .useCloakTrick)
        #expect(result.suggestions.contains(.addAgility(cutNeeded: 0.6)))
    }

    @Test("Half the trick fitted: suggest the missing piece")
    func missingPiece() {
        #expect(check(align: 5, modules: [prototypeCloak]).suggestions.first == .addMicrowarpdrive)
        #expect(check(align: 5, modules: [mwd]).suggestions.first == .addCloak)
        #expect(check(align: 5, modules: [afterburner]).suggestions.first == .addAgility(cutNeeded: 0.6))
    }

    @Test("Uncloaked haulers are told to scout; cloaked ones aren't")
    func haulers() {
        let hauler = check(align: 11, modules: [], group: 28)
        #expect(hauler.isHauler)
        #expect(hauler.suggestions.last == .scoutAhead)
        #expect(!check(align: 11, modules: [prototypeCloak, mwd], group: 28).suggestions.contains(.scoutAhead))
        #expect(!check(align: 11, group: 25).suggestions.contains(.scoutAhead))
    }

    @Test("Slots come from the ship's singleton slot assets; charges and cargo are left out")
    func slotsFromAssets() {
        func asset(_ id: Int, type: Int, in location: Int, flag: String, singleton: Bool = true) -> ESIAsset {
            ESIAsset(isBlueprintCopy: nil, isSingleton: singleton, itemId: id, locationFlag: flag,
                     locationId: location, locationType: "item", quantity: singleton ? 1 : 100, typeId: type)
        }
        let ship = 1_000
        let slots = EscapeCheckEngine.slots(shipItemID: ship, assets: [
            asset(1, type: mwd, in: ship, flag: "MedSlot0"),
            asset(2, type: inertiaStab, in: ship, flag: "LoSlot2"),
            asset(3, type: nozzleJoints, in: ship, flag: "RigSlot1"),
            asset(4, type: 31_000, in: ship, flag: "SubSystemSlot3"),
            asset(5, type: 200, in: ship, flag: "HiSlot0", singleton: false),   // loaded charge
            asset(6, type: 34, in: ship, flag: "Cargo", singleton: false),
            asset(7, type: inertiaStab, in: 2_000, flag: "LoSlot0"),          // another ship
        ])
        let found = Set(slots.map { "\($0.flag)=\($0.moduleTypeId ?? 0)" })
        #expect(found == ["MedSlot0=\(mwd)", "LoSlot2=\(inertiaStab)", "RigSlot1=\(nozzleJoints)", "SubSystem3=31000"])
    }

    @Test("Wording: headline, tick count, in-space caveat, percentage")
    @MainActor func wording() {
        var result = check(align: 6, modules: [], group: 28)
        #expect(EscapeCheckText.headline(result) == "A gate camp will probably catch you")
        #expect(EscapeCheckText.stats(result).contains("6 server ticks"))
        #expect(EscapeCheckText.footnote(result) == nil)
        result.fitKnown = false
        #expect(EscapeCheckText.footnote(result)?.contains("bare hull") == true)
        #expect(EscapeCheckText.suggestion(.addAgility(cutNeeded: 0.6)).contains("60%"))
    }
}
