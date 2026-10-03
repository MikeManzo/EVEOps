//
//  HangarMatrixEngineTests.swift
//  EVEOpsTests
//
//  Covers the Hangar Matrix: when two saved fittings are the same fit, collapsing them
//  across pilots, measuring every pilot against every fit, sharing what one pilot's board
//  learned with the others, and picking the pilot closest to undocking. Pure inputs only —
//  no network, no ESI.
//

import Foundation
import Testing
@testable import EVEOps

private let jita = 60_003_760
private let jitaSystem = 30_000_142
private let alice = 90_000_001
private let bob = 90_000_002

private let rifter = 587
private let autocannon = 2_873
private let frigateSkill = 3_330

private func fit(_ id: Int, name: String = "Brawler", items: [ESIFittingItem]? = nil) -> ESIFitting {
    ESIFitting(description: "", fittingId: id,
               items: items ?? [ESIFittingItem(flag: "HiSlot0", quantity: 1, typeId: autocannon),
                                ESIFittingItem(flag: "HiSlot1", quantity: 1, typeId: autocannon)],
               name: name, shipTypeId: rifter)
}

private func input(fittings: [ESIFitting], frigate: Int, assets: [ESIAsset] = [],
                   knowsRifter: Bool = true) -> ReadyRoomInput {
    ReadyRoomInput(
        fittings: fittings,
        typeNames: knowsRifter ? [rifter: "Rifter", autocannon: "200mm AutoCannon II"] : [:],
        shipClassNames: knowsRifter ? [rifter: "Frigate"] : [:],
        requirements: knowsRifter ? [rifter: [frigateSkill: 1], autocannon: [:]] : [:],
        skillInfo: [frigateSkill: SkillTrainingInfo(skillID: frigateSkill, name: "Minmatar Frigate", rank: 2,
                                                    primaryAttribute: 167, secondaryAttribute: 168, depth: 0)],
        skills: frigate > 0 ? [frigateSkill: ReadyRoomSkillLevel(active: frigate, trained: frigate, sp: 8_000)] : [:],
        skillQueue: [],
        attributes: nil,
        holdings: ReadyRoomEngine.holdings(from: assets, pilotedShip: nil, pilotPlaceID: jita),
        places: [jita: ReadyRoomPlace(id: jita, name: "Jita IV - Moon 4", systemID: jitaSystem, systemName: "Jita", security: 0.9)],
        currentPlaceID: jita,
        jumps: [jitaSystem: 0],
        prices: [:]
    )
}

private func asset(_ itemID: Int, type: Int, quantity: Int = 1, assembled: Bool = false) -> ESIAsset {
    ESIAsset(isBlueprintCopy: nil, isSingleton: assembled, itemId: itemID, locationFlag: "Hangar",
             locationId: jita, locationType: "station", quantity: quantity, typeId: type)
}

@Suite struct HangarMatrixEngineTests {
    // MARK: - Signatures

    @Test func signatureIgnoresNameAndSlotNumbers() {
        let a = fit(1, name: "Mine")
        let b = fit(2, name: "Yours", items: [ESIFittingItem(flag: "HiSlot2", quantity: 2, typeId: autocannon)])
        #expect(HangarMatrixEngine.signature(a) == HangarMatrixEngine.signature(b))
    }

    @Test func signatureTellsSlotGroupsApart() {
        let cargo = fit(2, items: [ESIFittingItem(flag: "Cargo", quantity: 2, typeId: autocannon)])
        #expect(HangarMatrixEngine.signature(fit(1)) != HangarMatrixEngine.signature(cargo))
    }

    @Test func distinctFitsMergeOwnersAcrossPilots() throws {
        let fits = HangarMatrixEngine.distinctFits([alice: [fit(1)], bob: [fit(7, name: "Copy"), fit(8, name: "Other", items: [])]])
        #expect(fits.count == 2)
        let shared = try #require(fits.first { $0.owners.count == 2 })
        #expect(shared.owners == [alice: 1, bob: 7])
        #expect(shared.fitting.fittingId == 1)
    }

    // MARK: - Rows

    @Test func everyPilotIsMeasuredAgainstEveryFit() throws {
        let fits = HangarMatrixEngine.distinctFits([alice: [fit(1)]])
        let inputs = HangarMatrixEngine.mergedInputs([
            alice: input(fittings: [fit(1)], frigate: 1,
                         assets: [asset(1, type: rifter, assembled: true), asset(2, type: autocannon, quantity: 2)]),
            bob: input(fittings: [], frigate: 0, knowsRifter: false),
        ], fits: fits)
        let row = try #require(HangarMatrixEngine.rows(fits: fits, inputs: inputs).first)
        #expect(row.cells[alice]?.tier == .ready)
        // Bob never saved it and his own board knew nothing about Rifters — merged in from Alice.
        #expect(row.cells[bob]?.tier == .train)
        #expect(row.shipTypeName == "Rifter")
        #expect(row.flyableCount == 1)
        #expect(row.readyCount == 1)
        #expect(row.bestPilot == alice)
    }

    @Test func ownersFitCheckCarriesOverToTheRowsFit() throws {
        let fits = HangarMatrixEngine.distinctFits([alice: [fit(1)], bob: [fit(7)]])
        var bobInput = input(fittings: [fit(7)], frigate: 1)
        bobInput.fittingChecks = [7: ReadyRoomFittingCheck(cpuUsed: 200, cpuTotal: 100, powerUsed: 1, powerTotal: 10,
                                                           calibrationUsed: 0, calibrationTotal: 400,
                                                           skillsToFit: [:], fitsWithTraining: false)]
        let inputs = HangarMatrixEngine.mergedInputs([alice: input(fittings: [fit(1)], frigate: 1), bob: bobInput], fits: fits)
        #expect(inputs[bob]?.fittingChecks[1]?.fitsWithTraining == false)
        let row = try #require(HangarMatrixEngine.rows(fits: fits, inputs: inputs).first)
        #expect(row.cells[bob]?.tier == .blocked)
    }

    @Test func closestPilotPrefersTierThenDistance() {
        let fits = HangarMatrixEngine.distinctFits([alice: [fit(1)]])
        let base = HangarMatrixEngine.mergedInputs([
            alice: input(fittings: [fit(1)], frigate: 1),
            bob: input(fittings: [], frigate: 1, assets: [asset(1, type: rifter, assembled: true),
                                                          asset(2, type: autocannon, quantity: 2)]),
        ], fits: fits)
        let row = HangarMatrixEngine.rows(fits: fits, inputs: base).first
        // Alice owns nothing (buy); Bob has everything here (ready).
        #expect(row?.cells[alice]?.tier == .buy)
        #expect(row?.bestPilot == bob)
    }

    // MARK: - Metadata

    @Test func rowMetadataCountsValueModulesSkillsAndOwners() throws {
        let fits = HangarMatrixEngine.distinctFits([alice: [fit(1)], bob: [fit(7)]])
        var aliceInput = input(fittings: [fit(1)], frigate: 1)
        aliceInput.prices = [rifter: 500_000, autocannon: 100_000]
        let inputs = HangarMatrixEngine.mergedInputs([alice: aliceInput, bob: input(fittings: [fit(7)], frigate: 0)], fits: fits)
        let row = try #require(HangarMatrixEngine.rows(fits: fits, inputs: inputs).first)
        #expect(row.fitValue == 700_000)
        #expect(row.moduleCount == 2)
        #expect(row.requiredSkillCount == 1)
        #expect(row.ownerIDs == [alice, bob])
    }

    @Test func fitValueIsUnknownWhileAnyPartIsUnpriced() throws {
        let fits = HangarMatrixEngine.distinctFits([alice: [fit(1)]])
        var aliceInput = input(fittings: [fit(1)], frigate: 1)
        aliceInput.prices = [rifter: 500_000]
        let row = try #require(HangarMatrixEngine.rows(fits: fits, inputs: [alice: aliceInput]).first)
        #expect(row.fitValue == nil)
    }

    @Test func tierCountsAndShortestTrainingPerPilot() throws {
        var trainee = input(fittings: [], frigate: 0)
        trainee.attributes = ESICharacterAttributes(charisma: 20, intelligence: 20, memory: 20, perception: 20,
                                                    willpower: 20, bonusRemaps: nil, accruedRemapCooldownDate: nil,
                                                    lastRemapDate: nil)
        let fits = HangarMatrixEngine.distinctFits([alice: [fit(1)]])
        let inputs = HangarMatrixEngine.mergedInputs([alice: input(fittings: [fit(1)], frigate: 1), bob: trainee], fits: fits)
        let rows = HangarMatrixEngine.rows(fits: fits, inputs: inputs)
        #expect(HangarMatrixEngine.tierCounts(rows, pilot: alice) == [.buy: 1])
        #expect(HangarMatrixEngine.tierCounts(rows, pilot: bob) == [.train: 1])
        let training = try #require(rows.first?.shortestTraining)
        #expect(training.characterID == bob)
        #expect(training.seconds > 0)
    }
}
