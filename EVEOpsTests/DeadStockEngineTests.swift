//
//  DeadStockEngineTests.swift
//  EVEOpsTests
//
//  Covers Dead Stock: what counts as in use (assembled ships and everything in them, the
//  ship being flown, containers, blueprints, industry materials), parts kept back for
//  saved fittings across pilots, which stacks are left once those are kept, first-seen
//  history, liquidity, and the clipboard export. Pure inputs only — no network, no ESI.
//

import Foundation
import Testing
@testable import EVEOps

private let jita = 60_003_760
private let amarr = 60_008_494
private let alice = 90_000_001
private let bob = 90_000_002

private let rifter = 587
private let autocannon = 2_873
private let damageControl = 2_046
private let tritanium = 34
private let rifterBlueprint = 691
private let container = 3_465

private let categories: [Int: Int] = [
    rifter: DeadStockEngine.Category.ship, autocannon: 7, damageControl: 7,
    tritanium: 4, rifterBlueprint: DeadStockEngine.Category.blueprint, container: 2,
]

private func asset(_ itemID: Int, type: Int, at location: Int, flag: String = "Hangar",
                   quantity: Int = 1, assembled: Bool = false) -> ESIAsset {
    ESIAsset(isBlueprintCopy: nil, isSingleton: assembled, itemId: itemID, locationFlag: flag,
             locationId: location, locationType: "station", quantity: quantity, typeId: type)
}

private func fit(_ id: Int, name: String = "Brawler", guns: Int = 2) -> ESIFitting {
    ESIFitting(description: "", fittingId: id,
               items: [ESIFittingItem(flag: "HiSlot0", quantity: guns, typeId: autocannon)],
               name: name, shipTypeId: rifter)
}

private func report(_ assets: [Int: [ESIAsset]], fittings: [ESIFitting] = [], industrialists: Set<Int> = [],
                    firstSeen: [Int: Date] = [:], piloted: [Int: ESICharacterShip] = [:]) -> DeadStockReport {
    DeadStockEngine.report(DeadStockInput(
        assets: assets, pilotedShips: piloted, fittings: fittings, categories: categories,
        typeNames: [rifter: "Rifter", autocannon: "200mm AutoCannon II", damageControl: "Damage Control II",
                    tritanium: "Tritanium"],
        prices: [autocannon: DeadStockPrice(buy: 1_000_000, sell: 1_200_000),
                 damageControl: DeadStockPrice(buy: 500_000, sell: 600_000)],
        firstSeen: firstSeen, industrialists: industrialists
    ))
}

@Suite struct DeadStockEngineTests {
    // MARK: - In use

    @Test func looseModulesWithNoFitAreDead() throws {
        let r = report([alice: [asset(1, type: damageControl, at: jita, quantity: 3)]])
        let line = try #require(r.lines.first)
        #expect(line.typeID == damageControl)
        #expect(line.quantity == 3)
        #expect(line.value == 1_500_000)
        #expect(line.listValue == 1_800_000)
    }

    @Test func assembledShipsAndEverythingInThemAreInUse() {
        let r = report([alice: [
            asset(1, type: rifter, at: jita, assembled: true),
            asset(2, type: autocannon, at: 1, flag: "HiSlot0"),
            asset(3, type: damageControl, at: 1, flag: "Cargo", quantity: 4),
        ]])
        #expect(r.lines.isEmpty)
        #expect(r.excluded[.inUse] == 3)
    }

    @Test func packagedShipsWithoutAFitAreDead() {
        let r = report([alice: [asset(1, type: rifter, at: jita)]])
        #expect(r.lines.map(\.typeID) == [rifter])
    }

    @Test func contentsOfTheShipBeingFlownAreInUseEvenWhenESILeavesItOut() {
        let ship = ESICharacterShip(shipItemId: 99, shipName: "Mine", shipTypeId: rifter)
        let r = report([alice: [asset(2, type: damageControl, at: 99, flag: "LoSlot0")]], piloted: [alice: ship])
        #expect(r.lines.isEmpty)
    }

    @Test func containersAreSkippedButTheirContentsCount() {
        let r = report([alice: [
            asset(10, type: container, at: jita, assembled: true),
            asset(11, type: damageControl, at: 10, flag: "Unlocked", quantity: 2),
        ]])
        #expect(r.lines.map(\.typeID) == [damageControl])
        #expect(r.lines.first?.stacks.first?.placeID == jita)
        #expect(r.excluded[.container] == 1)
    }

    @Test func blueprintsAreNeverDeadStock() {
        let r = report([alice: [asset(1, type: rifterBlueprint, at: jita)]])
        #expect(r.lines.isEmpty)
        #expect(r.excluded[.blueprint] == 1)
    }

    @Test func materialsAreKeptOnlyForPilotsWhoDoIndustry() {
        let assets = [asset(1, type: tritanium, at: jita, quantity: 10_000)]
        #expect(report([alice: assets], industrialists: [alice]).lines.isEmpty)
        #expect(report([alice: assets]).lines.map(\.typeID) == [tritanium])
    }

    // MARK: - Fittings

    @Test func savedFitsKeepTheirPartsBack() throws {
        let r = report([alice: [asset(1, type: autocannon, at: jita, quantity: 5)]], fittings: [fit(1)])
        let line = try #require(r.lines.first)
        #expect(line.owned == 5)
        #expect(line.reserved == 2)
        #expect(line.quantity == 3)
        #expect(r.reservedTypes == 1)
    }

    @Test func theSameFitSavedByTwoPilotsReservesOnce() throws {
        let r = report([alice: [asset(1, type: autocannon, at: jita, quantity: 5)]],
                       fittings: [fit(1, name: "Alice's"), fit(2, name: "Bob's")])
        #expect(try #require(r.lines.first).quantity == 3)
        #expect(r.fitCount == 1)
    }

    @Test func differentFitsEachReserveTheirOwnParts() {
        let r = report([alice: [asset(1, type: autocannon, at: jita, quantity: 5)]],
                       fittings: [fit(1), fit(2, guns: 3)])
        #expect(r.lines.isEmpty)
    }

    @Test func partsAreReservedAcrossPilots() throws {
        let r = report([alice: [asset(1, type: autocannon, at: jita, quantity: 1)],
                        bob: [asset(2, type: autocannon, at: amarr, quantity: 3)]],
                       fittings: [fit(1)])
        let line = try #require(r.lines.first)
        #expect(line.quantity == 2)
    }

    @Test func newestStacksAreReservedSoTheOldestShowAsDead() throws {
        let old = Date(timeIntervalSince1970: 1_700_000_000)
        let new = Date(timeIntervalSince1970: 1_800_000_000)
        let r = report([alice: [asset(1, type: autocannon, at: jita, quantity: 2),
                                asset(2, type: autocannon, at: amarr, quantity: 2)]],
                       fittings: [fit(1)], firstSeen: [1: old, 2: new])
        let line = try #require(r.lines.first)
        #expect(line.stacks.map(\.placeID) == [jita])
        #expect(line.untouchedSince == old)
    }

    // MARK: - History

    @Test func untouchedSinceNeedsHistoryForEveryStack() {
        let stack = { (id: Int, seen: Date?) in
            DeadStockStack(characterID: alice, itemID: id, placeID: jita, quantity: 1, firstSeen: seen)
        }
        let seen = Date(timeIntervalSince1970: 1_750_000_000)
        func line(_ stacks: [DeadStockStack]) -> DeadStockLine {
            DeadStockLine(typeID: 1, name: "", categoryID: nil, quantity: stacks.count, owned: stacks.count,
                          reserved: 0, stacks: stacks, price: nil, unitVolume: nil)
        }
        #expect(line([stack(1, seen), stack(2, nil)]).untouchedSince == nil)
        #expect(line([stack(1, seen), stack(2, .distantPast)]).untouchedSince == seen)
        #expect(line([stack(1, .distantPast)]).untouchedSince == .distantPast)
    }

    @Test func historyMarksFirstRecordAsPreTrackingAndLaterArrivalsAsNew() {
        var history = DeadStockHistory()
        let first = Date(timeIntervalSince1970: 1_800_000_000)
        let later = first.addingTimeInterval(86400)
        history.record(characterID: alice, itemIDs: [1, 2], now: first)
        history.record(characterID: alice, itemIDs: [2, 3], now: later)
        #expect(history.items[alice]?[1] == nil)
        #expect(history.items[alice]?[2] == .distantPast)
        #expect(history.items[alice]?[3] == later)
        #expect(history.trackingSince[alice] == first)
    }

    // MARK: - Totals and export

    @Test func valueByPlaceSumsDeadStacks() {
        let r = report([alice: [asset(1, type: autocannon, at: jita, quantity: 2),
                                asset(2, type: damageControl, at: amarr, quantity: 1)]])
        #expect(r.valueByPlace.first?.placeID == jita)
        #expect(r.totalValue == 2_500_000)
    }

    @Test func liquidityComparesQuantityToDailyVolume() {
        #expect(DeadStockEngine.liquidity(quantity: 5, averageDailyVolume: 100) == .high)
        #expect(DeadStockEngine.liquidity(quantity: 50, averageDailyVolume: 100) == .medium)
        #expect(DeadStockEngine.liquidity(quantity: 500, averageDailyVolume: 100) == .low)
        #expect(DeadStockEngine.liquidity(quantity: 5, averageDailyVolume: 0) == DeadStockEngine.Liquidity.none)
        #expect(DeadStockEngine.liquidity(quantity: 5, averageDailyVolume: nil) == nil)
    }

    @Test func clipboardUsesNameTabQuantityLines() {
        let r = report([alice: [asset(1, type: autocannon, at: jita, quantity: 2)]])
        #expect(DeadStockEngine.clipboardText(r.lines) == "200mm AutoCannon II\t2")
    }
}
