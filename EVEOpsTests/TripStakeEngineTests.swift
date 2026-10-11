//
//  TripStakeEngineTests.swift
//  EVEOpsTests
//
//  Covers the "what's at stake" estimate: sorting what's aboard into fit and cargo
//  (including container contents), pricing with unpriced items and blueprint copies,
//  the in-space case where ESI hides the ship's contents, insurance netting, and when to
//  suggest an implant-free jump clone.
//

import Foundation
import Testing
@testable import EVEOps

private let shipItem = 1_000
private let hullType = 587          // Rifter
private let moduleType = 10, chargeType = 11, droneType = 12, oreType = 13, containerType = 14, bpcType = 15
private let implantA = 20, implantB = 21
private let hangar = 60_003_760

private func asset(_ id: Int, type: Int, in location: Int, flag: String, qty: Int = 1, bpc: Bool? = nil) -> ESIAsset {
    ESIAsset(isBlueprintCopy: bpc, isSingleton: qty == 1, itemId: id, locationFlag: flag,
             locationId: location, locationType: "item", quantity: qty, typeId: type)
}

private let ship = asset(shipItem, type: hullType, in: hangar, flag: "Hangar")
private let fitted = [
    asset(2, type: moduleType, in: shipItem, flag: "HiSlot0"),
    asset(3, type: moduleType, in: shipItem, flag: "MedSlot1"),
    asset(4, type: chargeType, in: shipItem, flag: "HiSlot0", qty: 100),
    asset(5, type: droneType, in: shipItem, flag: "DroneBay", qty: 2),
]
private let carried = [
    asset(6, type: oreType, in: shipItem, flag: "Cargo", qty: 1_000),
    asset(7, type: containerType, in: shipItem, flag: "Cargo"),
    asset(8, type: oreType, in: 7, flag: "Unlocked", qty: 500),       // inside the container
    asset(9, type: bpcType, in: shipItem, flag: "Cargo", bpc: true),
]
private let elsewhere = asset(50, type: moduleType, in: hangar, flag: "Hangar")

private let prices: [Int: Double] = [
    hullType: 500_000, moduleType: 100_000, chargeType: 10, droneType: 50_000,
    oreType: 20, containerType: 30_000, bpcType: 9_000_000,
    implantA: 15_000_000, implantB: 10_000_000,
]

private func clones(_ jumpClones: [[Int]]) -> ESIClonesResponse {
    ESIClonesResponse(
        homeLocation: nil,
        jumpClones: jumpClones.enumerated().map { i, implants in
            ESIJumpClone(implants: implants, jumpCloneId: i, locationId: hangar + i, locationType: "station", name: nil)
        },
        lastCloneJumpDate: nil, lastStationChangeDate: nil
    )
}

private func stake(assets: [ESIAsset]? = [ship, elsewhere] + fitted + carried,
                   implants: [Int]? = [implantA, implantB],
                   clones: ESIClonesResponse? = nil,
                   insurance: [String: Double] = ["Basic": 86_000, "Platinum": 173_000],
                   risky: Bool = true, readyAt: Date? = nil) -> TripStake {
    TripStakeEngine.stake(shipTypeID: hullType, shipItemID: shipItem, shipName: "Lucky",
                          assets: assets, implants: implants, clones: clones,
                          prices: prices, insurance: insurance,
                          routeIsRisky: risky, cloneJumpReadyAt: readyAt)
}

@Suite struct TripStakeEngineTests {
    // MARK: - Contents

    @Test func sortsFitFromCargoIncludingContainerContents() {
        let (fit, cargo) = TripStakeEngine.contents(of: shipItem, in: [ship, elsewhere] + fitted + carried)
        #expect(Set(fit.map(\.itemId)) == [2, 3, 4, 5])
        #expect(Set(cargo.map(\.itemId)) == [6, 7, 8, 9])
    }

    @Test func fittedFlags() {
        for flag in ["HiSlot7", "LoSlot0", "RigSlot2", "SubSystemSlot1", "DroneBay", "FighterTube3"] {
            #expect(TripStakeEngine.isFitted(flag: flag), "\(flag)")
        }
        for flag in ["Cargo", "SpecializedOreHold", "FleetHangar", "ShipHangar"] {
            #expect(!TripStakeEngine.isFitted(flag: flag), "\(flag)")
        }
    }

    // MARK: - Valuation

    @Test func valuesHullFitCargoAndImplants() {
        let s = stake()
        #expect(s.hull == 500_000)
        // 2 modules + 100 charges + 2 drones
        #expect(s.fit == 200_000 + 1_000 + 100_000)
        // 1 500 ore + container; the blueprint copy isn't valued
        #expect(s.cargo == 30_000 + 30_000)
        #expect(s.implants == 25_000_000)
        #expect(s.implantCount == 2)
        #expect(s.shipLoss == 500_000 + 301_000 + 60_000)
        #expect(s.totalLoss == s.shipLoss + 25_000_000)
        #expect(s.unpricedCount == 1)
        #expect(s.contentsKnown)
    }

    @Test func unpricedItemsAreCountedNotValued() {
        let unknown = asset(30, type: 999, in: shipItem, flag: "Cargo", qty: 5)
        let s = stake(assets: [ship, unknown], implants: [999])
        #expect(s.cargo == 0)
        #expect(s.implants == 0)
        #expect(s.unpricedCount == 2)
    }

    @Test func shipInSpaceLeavesContentsUnknown() {
        // ESI drops the piloted ship and everything in it while undocked.
        let s = stake(assets: [elsewhere])
        #expect(!s.contentsKnown)
        #expect(s.fit == 0 && s.cargo == 0)
        #expect(s.hull == 500_000)
    }

    @Test func unreadableImplants() {
        let s = stake(implants: nil)
        #expect(!s.implantsKnown)
        #expect(s.implants == 0)
    }

    // MARK: - Insurance

    @Test func platinumPayoutOnlyOffsetsTheShip() {
        let s = stake()
        #expect(s.platinumPayout == 173_000)
        #expect(s.shipLossIfInsured == s.shipLoss - 173_000)
    }

    @Test func insuredLossNeverGoesNegative() {
        let s = stake(assets: [ship], insurance: ["Platinum": 2_000_000])
        #expect(s.shipLossIfInsured == 0)
    }

    @Test func noInsurancePrices() {
        let s = stake(insurance: [:])
        #expect(s.platinumPayout == nil)
        #expect(s.shipLossIfInsured == nil)
    }

    // MARK: - Clone advice

    @Test func suggestsEmptyCloneOnRiskyRoute() {
        let ready = Date(timeIntervalSince1970: 1_800_000_000)
        let s = stake(clones: clones([[implantA], []]), readyAt: ready)
        #expect(s.cloneAdvice == .jumpToEmptyClone(locationID: hangar + 1, readyAt: ready))
    }

    @Test func warnsWhenNoEmptyClone() {
        #expect(stake(clones: clones([[implantA]])).cloneAdvice == .noEmptyClone)
        #expect(stake(clones: clones([])).cloneAdvice == .noEmptyClone)
    }

    @Test func noAdviceWhenSafeCheapOrUnknown() {
        #expect(stake(clones: clones([[]]), risky: false).cloneAdvice == nil)
        #expect(stake(implants: [implantB], clones: clones([[]])).cloneAdvice == nil)   // 10M < threshold
        #expect(stake(clones: nil).cloneAdvice == nil)
    }
}
