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

/// Builds the Hangar Matrix: loads each pilot's Ready Room board, then measures every
/// pilot against every distinct fit any of them has saved.
@MainActor
@Observable
final class HangarMatrixService {
    static let shared = HangarMatrixService()

    private(set) var rows: [HangarMatrixRow] = []
    /// Pilots in the matrix, in column order.
    private(set) var pilotIDs: [Int] = []
    /// Location, ship, clone and fit counts per pilot.
    private(set) var pilots: [Int: HangarMatrixPilot] = [:]
    private(set) var isLoading = false
    private(set) var progress: String?
    /// Pilots whose board couldn't load, by name.
    private(set) var failedPilots: [String] = []
    /// False until every pilot has been run through the dogma engine for every fit.
    private(set) var fitChecksDone = false

    private init() {}

    func refresh(accountManager: AccountManager, prefetcher: DashboardPrefetcher, force: Bool = false) async {
        guard !isLoading else { return }
        isLoading = true
        defer {
            isLoading = false
            progress = nil
        }
        let readyRoom = ReadyRoomService.shared
        let accounts = accountManager.accounts.filter { !$0.needsReauth }

        // Each pilot's board — the Ready Room caches these, so only missing or forced ones load.
        for (index, account) in accounts.enumerated() where force || readyRoom.snapshots[account.characterID] == nil {
            progress = String(localized: "Loading \(account.characterName) · \(index + 1) of \(accounts.count)")
            await readyRoom.refresh(account, accountManager: accountManager, prefetcher: prefetcher, force: force)
        }
        let snapshots = accounts.compactMap { readyRoom.snapshots[$0.characterID] }
        failedPilots = accounts.filter { readyRoom.snapshots[$0.characterID] == nil }.map(\.characterName)
        pilotIDs = snapshots.map(\.characterID)

        let fits = HangarMatrixEngine.distinctFits(
            Dictionary(snapshots.map { ($0.characterID, $0.input.fittings) }, uniquingKeysWith: { a, _ in a })
        )
        let baseInputs = Dictionary(snapshots.map { ($0.characterID, $0.input) }, uniquingKeysWith: { a, _ in a })

        // Places other pilots' fits point at that a pilot's own board never resolved.
        progress = String(localized: "Finding stations…")
        let fitTypes = Set(fits.flatMap { [$0.fitting.shipTypeId] + $0.fitting.items.map(\.typeId) })
        var extraPlaces: [Int: ReadyRoomPlace] = [:]
        let known = Set(baseInputs.values.flatMap(\.places.keys))
        let missing = Set(baseInputs.values.flatMap { input in
            input.holdings.filter { fitTypes.contains($0.typeID) }.map(\.placeID)
        }).subtracting(known)
        if !missing.isEmpty, let account = accounts.first, let token = try? await accountManager.validToken(for: account) {
            extraPlaces = await ReadyRoomPlaces.resolve(missing, token: token)
        }

        var inputs = HangarMatrixEngine.mergedInputs(baseInputs, fits: fits, extraPlaces: extraPlaces)
        await publish(fits: fits, inputs: inputs)
        updatePilots(snapshots, accounts: accounts, prefetcher: prefetcher)

        // Fit checks for the pilot × fit pairs no board ran.
        guard await ReadyRoomFittingChecker.prepareEngine(allowLoad: true) else {
            fitChecksDone = false
            return
        }
        progress = String(localized: "Checking CPU and powergrid…")
        let types = await UniverseCache.shared.types(ids: Array(fitTypes))
        var fittingSkills = Set<Int>()
        for snapshot in snapshots {
            guard var input = inputs[snapshot.characterID] else { continue }
            let skills = input.skills.mapValues(\.active)
            for fit in fits where input.fittingChecks[fit.fitting.fittingId] == nil {
                if let check = readyRoom.fittingCheck(fit.fitting, skills: skills, implants: snapshot.pilot.implantIDs,
                                                      types: types) {
                    input.fittingChecks[fit.fitting.fittingId] = check
                    fittingSkills.formUnion(check.skillsToFit.keys)
                }
                await Task.yield()   // the dogma engine runs on the main actor
            }
            inputs[snapshot.characterID] = input
        }
        // Fitting skills' own prerequisites and training info, so their gaps can be costed.
        let knownSkills = Set(inputs.values.flatMap(\.requirements.keys))
        let newSkills = fittingSkills.subtracting(knownSkills)
        if !newSkills.isEmpty {
            let requirements = await SkillPrerequisites.shared.requirements(for: Array(newSkills))
            let info = await SkillPrerequisites.shared.trainingInfo(
                for: Array(newSkills.union(requirements.values.flatMap(\.keys)))
            )
            for id in inputs.keys {
                inputs[id]?.requirements.merge(requirements) { a, _ in a }
                inputs[id]?.skillInfo.merge(info) { a, _ in a }
            }
        }
        fitChecksDone = true
        await publish(fits: fits, inputs: inputs)
        updatePilots(snapshots, accounts: accounts, prefetcher: prefetcher)
    }

    private func updatePilots(_ snapshots: [ReadyRoomSnapshot], accounts: [StoredAccount],
                              prefetcher: DashboardPrefetcher) {
        var out: [Int: HangarMatrixPilot] = [:]
        for snapshot in snapshots {
            let id = snapshot.characterID
            let data = prefetcher.characterData[id]
            out[id] = HangarMatrixPilot(
                characterID: id,
                name: accounts.first { $0.characterID == id }?.characterName ?? "#\(id)",
                location: snapshot.input.currentPlaceID.flatMap { snapshot.input.places[$0] },
                shipTypeID: snapshot.pilot.shipTypeID,
                shipTypeName: snapshot.pilot.shipTypeName,
                totalSP: data?.skills.totalSp,
                jumpCloneCount: data?.clones?.jumpClones.count ?? snapshot.input.jumpClonePlaceIDs.count,
                cloneJumpReadyAt: snapshot.pilot.cloneJumpReadyAt,
                implantCount: snapshot.pilot.implantIDs.count,
                isRemapAvailable: snapshot.pilot.isRemapAvailable,
                tierCounts: HangarMatrixEngine.tierCounts(rows, pilot: id)
            )
        }
        pilots = out
    }

    private func publish(fits: [HangarMatrixFit], inputs: [Int: ReadyRoomInput]) async {
        rows = await Task.detached(priority: .userInitiated) {
            HangarMatrixEngine.rows(fits: fits, inputs: inputs)
        }.value
    }
}
