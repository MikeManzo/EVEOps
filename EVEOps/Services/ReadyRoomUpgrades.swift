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

/// What buying one part does for a fit, against what the staged hull has in those slots
/// today: the fit as saved, and the fit with that part's missing units put back to the
/// modules (or empty slots) fitted now.
nonisolated struct ReadyRoomUpgrade: Sendable, Hashable {
    let today: FitPerformance
    let withPurchase: FitPerformance
    let delta: FitStatDelta
}

nonisolated enum ReadyRoomUpgrades {
    /// The fit with `line`'s missing units swapped for `line.displaced`. A displaced module
    /// goes in the slot it already sits in when the fit puts this part there, otherwise in
    /// the next of the fit's slots for this part.
    static func todayFitting(_ fitting: ESIFitting, line: ReadyRoomPartLine) -> ESIFitting {
        var targets = fitting.items
            .filter { $0.typeId == line.typeID && ReadyRoomEngine.slotCategory($0.flag) == line.category }
            .map(\.flag)
            .sorted { $0.localizedStandardCompare($1) == .orderedAscending }
        var swaps: [String: Int?] = [:]
        var rest: [ReadyRoomPartLine.Displaced] = []
        for entry in line.displaced {
            if let index = targets.firstIndex(of: entry.flag) {
                swaps[targets.remove(at: index)] = entry.typeID
            } else {
                rest.append(entry)
            }
        }
        for entry in rest where !targets.isEmpty {
            swaps[targets.removeFirst()] = entry.typeID
        }

        var items = fitting.items.filter { swaps[$0.flag] == nil || $0.typeId != line.typeID }
        for (flag, typeID) in swaps {
            if let typeID { items.append(ESIFittingItem(flag: flag, quantity: 1, typeId: typeID)) }
        }
        return ESIFitting(description: fitting.description, fittingId: fitting.fittingId, items: items,
                          name: fitting.name, shipTypeId: fitting.shipTypeId)
    }

    /// Part line ID → upgrade, for every missing part that displaces something on the
    /// staged hull. Empty when the dogma engine can't be loaded.
    @MainActor
    static func measure(report: ReadyRoomReport, snapshot: ReadyRoomSnapshot) async -> [String: ReadyRoomUpgrade] {
        let lines = report.requiredParts.filter { !$0.displaced.isEmpty }
        guard !lines.isEmpty,
              let fitting = snapshot.input.fittings.first(where: { $0.fittingId == report.fittingID }),
              await ReadyRoomFittingChecker.prepareEngine(allowLoad: true) else { return [:] }

        let typeIDs = Set([fitting.shipTypeId] + fitting.items.map(\.typeId)
                          + lines.flatMap { $0.displaced.compactMap(\.typeID) })
        let types = await UniverseCache.shared.types(ids: Array(typeIDs))
        let skills = snapshot.input.skills.mapValues(\.active)
        let implants = snapshot.pilot.implantIDs

        return await Task.detached(priority: .userInitiated) {
            func performance(_ fitting: ESIFitting) -> FitPerformance {
                let fit = DogmaFit(fitting: fitting, types: types, implants: implants, onlineOnly: false)
                return FitPerformance(DogmaEngine.shared.calculate(fit, skills: skills))
            }
            let saved = performance(fitting)
            var out: [String: ReadyRoomUpgrade] = [:]
            for line in lines {
                let today = performance(todayFitting(fitting, line: line))
                out[line.id] = ReadyRoomUpgrade(
                    today: today, withPurchase: saved,
                    delta: SkillPerformanceEngine.delta(fittingID: fitting.fittingId, from: today, to: saved)
                )
            }
            return out
        }.value
    }
}
