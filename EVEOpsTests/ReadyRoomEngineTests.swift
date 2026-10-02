//
//  ReadyRoomEngineTests.swift
//  EVEOpsTests
//
//  Covers the Ready Room's readiness engine: tiering, where parts are counted (hangars,
//  containers, fitted hulls), choosing the staging station, skills already in the queue,
//  cargo never blocking readiness, the undocked piloted ship, and jump distances.
//  Pure inputs only — no network, no ESI.
//

import Foundation
import Testing
@testable import EVEOps

// MARK: - Fixtures

private let jita = 60_003_760
private let amarr = 60_008_494
private let jitaSystem = 30_000_142
private let amarrSystem = 30_002_187

private let rifter = 587
private let autocannon = 2_873
private let damageControl = 2_046
private let ammo = 12_625

private let frigateSkill = 3_330
private let gunnerySkill = 3_300

private func asset(_ itemID: Int, type: Int, at location: Int, flag: String = "Hangar",
                   quantity: Int = 1, assembled: Bool = false) -> ESIAsset {
    ESIAsset(isBlueprintCopy: nil, isSingleton: assembled, itemId: itemID, locationFlag: flag,
             locationId: location, locationType: "station", quantity: quantity, typeId: type)
}

private let rifterFit = ESIFitting(
    description: "", fittingId: 1,
    items: [
        ESIFittingItem(flag: "HiSlot0", quantity: 1, typeId: autocannon),
        ESIFittingItem(flag: "HiSlot1", quantity: 1, typeId: autocannon),
        ESIFittingItem(flag: "LoSlot0", quantity: 1, typeId: damageControl),
        ESIFittingItem(flag: "Cargo", quantity: 500, typeId: ammo),
    ],
    name: "Brawler", shipTypeId: rifter
)

private func level(_ active: Int, sp: Int, trained: Int? = nil) -> ReadyRoomSkillLevel {
    ReadyRoomSkillLevel(active: active, trained: trained ?? active, sp: sp)
}

private func input(
    assets: [ESIAsset],
    skills: [Int: ReadyRoomSkillLevel] = [frigateSkill: level(3, sp: 8_000), gunnerySkill: level(2, sp: 1_414)],
    queue: [ESISkillQueue] = [],
    currentPlace: Int = jita,
    piloted: ESICharacterShip? = nil,
    prices: [Int: Double] = [:]
) -> ReadyRoomInput {
    ReadyRoomInput(
        fittings: [rifterFit],
        typeNames: [rifter: "Rifter", autocannon: "200mm AutoCannon II", damageControl: "Damage Control II", ammo: "EMP S"],
        shipClassNames: [rifter: "Frigate"],
        requirements: [rifter: [frigateSkill: 1], autocannon: [gunnerySkill: 2], damageControl: [:]],
        skillInfo: [
            frigateSkill: SkillTrainingInfo(skillID: frigateSkill, name: "Minmatar Frigate", rank: 2,
                                            primaryAttribute: 167, secondaryAttribute: 168, depth: 1),
            gunnerySkill: SkillTrainingInfo(skillID: gunnerySkill, name: "Gunnery", rank: 1,
                                            primaryAttribute: 167, secondaryAttribute: 168, depth: 0),
        ],
        skills: skills,
        skillQueue: queue,
        attributes: ESICharacterAttributes(charisma: 20, intelligence: 20, memory: 20, perception: 20,
                                           willpower: 20, bonusRemaps: nil, accruedRemapCooldownDate: nil,
                                           lastRemapDate: nil),
        holdings: ReadyRoomEngine.holdings(from: assets, pilotedShip: piloted, pilotPlaceID: currentPlace),
        places: [
            jita: ReadyRoomPlace(id: jita, name: "Jita IV - Moon 4", systemID: jitaSystem, systemName: "Jita", security: 0.9),
            amarr: ReadyRoomPlace(id: amarr, name: "Amarr VIII", systemID: amarrSystem, systemName: "Amarr", security: 1.0),
        ],
        currentPlaceID: currentPlace,
        jumps: [jitaSystem: 0, amarrSystem: 45],
        prices: prices
    )
}

private func report(_ input: ReadyRoomInput) throws -> ReadyRoomReport {
    try #require(ReadyRoomEngine.reports(input).first)
}

// MARK: - Tiers

@Suite struct ReadyRoomEngineTests {
    @Test func everythingHereAndTrainedIsReady() throws {
        let r = try report(input(assets: [
            asset(1, type: rifter, at: jita, assembled: true),
            asset(2, type: autocannon, at: jita, quantity: 2),
            asset(3, type: damageControl, at: jita),
        ]))
        #expect(r.tier == .ready)
        #expect(r.isStagingCurrentLocation)
        #expect(r.missingCount == 0)
    }

    @Test func cargoNeverBlocksReadiness() throws {
        let r = try report(input(assets: [
            asset(1, type: rifter, at: jita, assembled: true),
            asset(2, type: autocannon, at: jita, quantity: 2),
            asset(3, type: damageControl, at: jita),
        ]))
        let cargo = try #require(r.optionalParts.first)
        #expect(cargo.missing == 500)
        #expect(r.tier == .ready)
    }

    @Test func partsInAnotherStationRequireTravel() throws {
        let r = try report(input(assets: [
            asset(1, type: rifter, at: amarr, assembled: true),
            asset(2, type: autocannon, at: amarr, quantity: 2),
            asset(3, type: damageControl, at: amarr),
        ]))
        #expect(r.tier == .travel)
        #expect(r.staging?.id == amarr)
        #expect(r.stagingJumps == 45)
    }

    @Test func splitPartsRequireTravelAndListTheOtherStation() throws {
        let r = try report(input(assets: [
            asset(1, type: rifter, at: jita, assembled: true),
            asset(2, type: autocannon, at: jita, quantity: 2),
            asset(3, type: damageControl, at: amarr),
        ]))
        #expect(r.tier == .travel)
        #expect(r.staging?.id == jita)
        let dc = try #require(r.parts.first { $0.typeID == damageControl })
        #expect(dc.elsewhere == [.init(placeID: amarr, quantity: 1)])
    }

    @Test func missingPartsNeedBuyingAndArePriced() throws {
        let r = try report(input(
            assets: [asset(1, type: rifter, at: jita, assembled: true)],
            prices: [autocannon: 1_000_000, damageControl: 500_000]
        ))
        #expect(r.tier == .buy)
        #expect(r.missingCount == 3)
        #expect(r.missingISK == 2_500_000)
    }

    @Test func missingISKIsUnknownUntilEverythingIsPriced() throws {
        let r = try report(input(assets: [], prices: [autocannon: 1_000_000]))
        #expect(r.missingISK == nil)
        #expect(r.staging == nil)
    }

    // MARK: - Skills

    @Test func untrainedSkillPutsFitInTrainFirstWithPrerequisitesFirst() throws {
        let r = try report(input(
            assets: [asset(1, type: rifter, at: jita, assembled: true)],
            skills: [:]
        ))
        #expect(r.tier == .train)
        #expect(r.skillGaps.map(\.skillID) == [gunnerySkill, frigateSkill])   // depth 0 before depth 1
        let seconds = try #require(r.trainingSeconds)
        // Gunnery 0→2 at rank 1 (1,414 SP) + Frigate 0→1 at rank 2 (500 SP), at 30 SP/min.
        #expect(abs(seconds - Double(1_414 + 500) / 30 * 60) < 0.001)
    }

    @Test func skillsAlreadyQueuedCountAsQueuedNotUnplanned() throws {
        let finish = Date(timeIntervalSinceReferenceDate: 900_000_000)
        let queue = [ESISkillQueue(finishDate: finish, finishedLevel: 2, levelEndSp: nil, levelStartSp: nil,
                                   queuePosition: 0, skillId: gunnerySkill, startDate: nil, trainingStartSp: nil)]
        let r = try report(input(
            assets: [],
            skills: [frigateSkill: level(3, sp: 8_000), gunnerySkill: level(1, sp: 250)],
            queue: queue
        ))
        #expect(r.tier == .train)
        #expect(r.unqueuedGaps.isEmpty)
        #expect(r.queuedUntil == finish)
        #expect(r.trainingSeconds == 0)
    }

    @Test func cargoSkillsDoNotGateFlying() throws {
        var i = input(assets: [
            asset(1, type: rifter, at: jita, assembled: true),
            asset(2, type: autocannon, at: jita, quantity: 2),
            asset(3, type: damageControl, at: jita),
        ])
        i.requirements[ammo] = [99_999: 5]
        #expect(try report(i).tier == .ready)
    }

    // MARK: - Assets

    @Test func partsInsideContainersCountAtTheirStation() throws {
        let r = try report(input(assets: [
            asset(1, type: rifter, at: jita, assembled: true),
            asset(10, type: 17_366, at: jita, assembled: true),                 // a station container
            asset(2, type: autocannon, at: 10, flag: "Unlocked", quantity: 2),
            asset(3, type: damageControl, at: 10, flag: "Unlocked"),
        ]))
        #expect(r.tier == .ready)
    }

    @Test func modulesFittedToAnotherShipDoNotCount() throws {
        let r = try report(input(assets: [
            asset(1, type: rifter, at: jita, assembled: true),
            asset(20, type: 999, at: jita, assembled: true),                    // some other hull
            asset(2, type: autocannon, at: 20, flag: "HiSlot0"),
            asset(4, type: autocannon, at: 20, flag: "HiSlot1"),
            asset(3, type: damageControl, at: jita),
        ]))
        #expect(r.tier == .buy)
        #expect(r.parts.first { $0.typeID == autocannon }?.missing == 2)
    }

    @Test func modulesFittedToTheFitsOwnHullCount() throws {
        let r = try report(input(assets: [
            asset(1, type: rifter, at: amarr, assembled: true),
            asset(2, type: autocannon, at: 1, flag: "HiSlot0"),
            asset(4, type: autocannon, at: 1, flag: "HiSlot1"),
            asset(3, type: damageControl, at: 1, flag: "LoSlot0"),
        ]))
        #expect(r.tier == .travel)
        #expect(r.stagedHullItemID == 1)
        #expect(r.atStagingCount == r.requiredCount)
    }

    @Test func stagingPrefersTheBetterFittedHull() throws {
        let r = try report(input(assets: [
            asset(1, type: rifter, at: jita, assembled: true),                 // bare hull here
            asset(5, type: rifter, at: amarr, assembled: true),                // fitted hull there
            asset(2, type: autocannon, at: 5, flag: "HiSlot0"),
            asset(4, type: autocannon, at: 5, flag: "HiSlot1"),
            asset(3, type: damageControl, at: 5, flag: "LoSlot0"),
        ]))
        #expect(r.staging?.id == amarr)
        #expect(r.stagedHullItemID == 5)
    }

    @Test func undockedPilotedShipResolvesToThePilotsSystem() throws {
        let ship = ESICharacterShip(shipItemId: 1, shipName: "Brawler", shipTypeId: rifter)
        var i = input(
            assets: [
                asset(2, type: autocannon, at: 1, flag: "HiSlot0"),
                asset(4, type: autocannon, at: 1, flag: "HiSlot1"),
                asset(3, type: damageControl, at: 1, flag: "LoSlot0"),
            ],
            currentPlace: jitaSystem,
            piloted: ship
        )
        i.places[jitaSystem] = ReadyRoomPlace(id: jitaSystem, name: "In space · Jita", systemID: jitaSystem,
                                             systemName: "Jita", security: 0.9)
        let r = try report(i)
        #expect(r.tier == .ready)
        #expect(r.staging?.isInSpace == true)
    }

    // MARK: - Incoming, corporation, clones

    @Test func partsOnTheWayMakeTheFitWaitingNotBuy() throws {
        var i = input(assets: [
            asset(1, type: rifter, at: jita, assembled: true),
            asset(3, type: damageControl, at: jita),
        ])
        let eta = Date(timeIntervalSinceReferenceDate: 900_000_000)
        i.incoming = [ReadyRoomIncoming(kind: .industry, typeID: autocannon, quantity: 5, placeID: jita, eta: eta)]
        let r = try report(i)
        #expect(r.tier == .waiting)
        #expect(r.missingCount == 0)
        #expect(r.incomingCount == 2)
    }

    @Test func incomingThatFallsShortStillNeedsBuying() throws {
        var i = input(assets: [asset(1, type: rifter, at: jita, assembled: true), asset(3, type: damageControl, at: jita)])
        i.incoming = [ReadyRoomIncoming(kind: .buyOrder, typeID: autocannon, quantity: 1, placeID: jita, eta: nil)]
        let r = try report(i)
        #expect(r.tier == .buy)
        #expect(r.missingCount == 1)
    }

    @Test func corporationStockCountsAfterPersonalStock() throws {
        var i = input(assets: [
            asset(1, type: rifter, at: jita, assembled: true),
            asset(2, type: autocannon, at: jita),
            asset(3, type: damageControl, at: jita),
        ])
        i.holdings += ReadyRoomEngine.holdings(from: [asset(50, type: autocannon, at: jita, quantity: 4)],
                                               pilotedShip: nil, pilotPlaceID: nil, isCorporation: true)
        let r = try report(i)
        #expect(r.tier == .ready)
        #expect(r.parts.first { $0.typeID == autocannon }?.fromCorporation == 1)
    }

    @Test func jumpCloneAtStagingIsFlagged() throws {
        var i = input(assets: [asset(1, type: rifter, at: amarr, assembled: true)])
        i.jumpClonePlaceIDs = [amarr]
        #expect(try report(i).hasJumpCloneAtStaging)
    }

    // MARK: - Omega & fitting

    @Test func alphaCappedSkillIsOmegaLockedWithNoTrainingTime() throws {
        let r = try report(input(
            assets: [],
            skills: [frigateSkill: level(3, sp: 8_000), gunnerySkill: level(1, sp: 1_414, trained: 2)]
        ))
        let gap = try #require(r.skillGaps.first)
        #expect(gap.isOmegaLocked)
        #expect(r.needsOmega)
        #expect(r.unqueuedGaps.isEmpty)
        #expect(r.tier == .train)
    }

    @Test func fittingSkillsAndTheirPrerequisitesJoinTheGaps() throws {
        let cpu = 3_426
        let weaponUpgrades = 3_318
        var i = input(assets: [
            asset(1, type: rifter, at: jita, assembled: true),
            asset(2, type: autocannon, at: jita, quantity: 2),
            asset(3, type: damageControl, at: jita),
        ])
        i.requirements[weaponUpgrades] = [cpu: 2]
        i.skillInfo[weaponUpgrades] = SkillTrainingInfo(skillID: weaponUpgrades, name: "Weapon Upgrades", rank: 2,
                                                        primaryAttribute: 165, secondaryAttribute: 166, depth: 1)
        i.skillInfo[cpu] = SkillTrainingInfo(skillID: cpu, name: "CPU Management", rank: 1,
                                             primaryAttribute: 165, secondaryAttribute: 166, depth: 0)
        i.fittingChecks[rifterFit.fittingId] = ReadyRoomFittingCheck(
            cpuUsed: 130, cpuTotal: 125, powerUsed: 40, powerTotal: 50, calibrationUsed: 0, calibrationTotal: 400,
            skillsToFit: [weaponUpgrades: 3], fitsWithTraining: true
        )
        let r = try report(i)
        #expect(r.tier == .train)
        #expect(Set(r.skillGaps.map(\.skillID)) == [cpu, weaponUpgrades])
        #expect(r.skillGaps.allSatisfy { $0.isForFitting })
        #expect(r.requiredSkills[weaponUpgrades] == nil)
    }

    @Test func fitOverBudgetAtAllVIsBlocked() throws {
        var i = input(assets: [asset(1, type: rifter, at: jita, assembled: true)])
        i.fittingChecks[rifterFit.fittingId] = ReadyRoomFittingCheck(
            cpuUsed: 300, cpuTotal: 125, powerUsed: 40, powerTotal: 50, calibrationUsed: 0, calibrationTotal: 400,
            skillsToFit: [:], fitsWithTraining: false
        )
        #expect(try report(i).tier == .blocked)
    }

    // MARK: - Routes

    @Test func collectionRouteVisitsNearestFirstAndEndsAtStaging() {
        // 1 - 2 - 3 - 4, with 5 hanging off 1.
        let adjacency = ReadyRoomEngine.adjacency([(1, 2), (2, 3), (3, 4), (1, 5)])
        let route = ReadyRoomEngine.collectionRoute(origin: 1, stops: [3, 5], destination: 4, adjacency: adjacency)
        #expect(route.map(\.systemID) == [5, 3, 4])
        #expect(route.map(\.jumps) == [1, 3, 1])
    }

    // MARK: - Jumps & SP

    @Test func jumpDistancesAreBreadthFirst() {
        let d = ReadyRoomEngine.jumpDistances(from: 1, links: [(1, 2), (2, 3), (1, 4), (4, 3), (5, 6)])
        #expect(d[1] == 0)
        #expect(d[2] == 1)
        #expect(d[3] == 2)
        #expect(d[5] == nil)
    }

    @Test func spNeededCreditsPartialTraining() {
        #expect(SkillTraining.spNeeded(toLevel: 3, trainedLevel: 2, spInSkill: 5_000, rank: 1) == 3_000)
        #expect(SkillTraining.spNeeded(toLevel: 1, trainedLevel: 0, spInSkill: 0, rank: 3) == 750)
        #expect(SkillTraining.spNeeded(toLevel: 2, trainedLevel: 4, spInSkill: 45_255, rank: 1) == 0)
    }
}
