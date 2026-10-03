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

// MARK:  Models

/// One distinct fitting across every pilot. Pilots often save the same fit; they collapse
/// into one row, whoever saved it.
nonisolated struct HangarMatrixFit: Sendable, Identifiable, Hashable {
    let signature: String
    /// The first saved copy — its ID keys the Ready Room report and fit check.
    let fitting: ESIFitting
    /// Pilot → their saved copy's fitting ID.
    let owners: [Int: Int]

    var id: String { signature }
}

/// How one fit stands across every pilot.
nonisolated struct HangarMatrixRow: Sendable, Identifiable {
    let fit: HangarMatrixFit
    let shipTypeName: String
    let shipClassName: String
    /// Pilot → Ready Room report for this fit.
    let cells: [Int: ReadyRoomReport]

    var id: String { fit.id }
    var name: String { fit.fitting.name }

    /// Pilots who can fly it now (skills and fitting), whatever the parts situation.
    var flyableCount: Int { cells.values.filter { $0.tier < .train }.count }
    var readyCount: Int { cells.values.filter { $0.tier == .ready }.count }

    /// The pilot closest to undocking in it: best tier, then fewest jumps, then least to buy.
    var bestPilot: Int? {
        cells.min { a, b in HangarMatrixEngine.closer(a.value, b.value, idA: a.key, idB: b.key) }?.key
    }

    /// Jita value of the whole fit — hull, modules, drones and cargo; nil while any part is
    /// unpriced.
    var fitValue: Double? { cells.values.first.flatMap(HangarMatrixEngine.fitValue) }
    /// Modules fitted to slots (cargo, drones and fighters left out).
    var moduleCount: Int { fit.fitting.items.filter { ReadyRoomEngine.isFittedFlag($0.flag) }.reduce(0) { $0 + $1.quantity } }
    /// Skills (prerequisites included) needed to fly the hull and use its modules.
    var requiredSkillCount: Int { cells.values.first?.requiredSkills.count ?? 0 }
    /// Pilots who've saved this fit themselves.
    var ownerIDs: [Int] { fit.owners.keys.sorted() }
    /// Pilots still training for it, and the shortest training among them.
    var shortestTraining: (characterID: Int, seconds: Double)? {
        cells.compactMap { id, report in
            report.tier == .train ? report.trainingSeconds.map { (id, $0) } : nil
        }
        .min { $0.1 != $1.1 ? $0.1 < $1.1 : $0.0 < $1.0 }
    }
}

/// What the matrix shows about each pilot in its column header and pilot strip.
nonisolated struct HangarMatrixPilot: Sendable, Identifiable {
    let characterID: Int
    let name: String
    /// Where they are: station or structure, or "In space · system".
    let location: ReadyRoomPlace?
    let shipTypeID: Int?
    let shipTypeName: String?
    let totalSP: Int?
    let jumpCloneCount: Int
    /// When the next clone jump is allowed; nil when it is now.
    let cloneJumpReadyAt: Date?
    let implantCount: Int
    let isRemapAvailable: Bool
    /// Fits by tier for this pilot across the whole matrix.
    let tierCounts: [ReadyRoomTier: Int]

    var id: Int { characterID }
    var readyCount: Int { tierCounts[.ready] ?? 0 }
    var flyableCount: Int { tierCounts.filter { $0.key < .train }.values.reduce(0, +) }
}

// MARK:  Engine

nonisolated enum HangarMatrixEngine {
    /// What makes two saved fittings the same: hull plus every item, by slot group and
    /// quantity. Names and descriptions don't count.
    static func signature(_ fitting: ESIFitting) -> String {
        var quantities: [String: Int] = [:]
        for item in fitting.items {
            quantities["\(ReadyRoomEngine.slotCategory(item.flag)):\(item.typeId)", default: 0] += item.quantity
        }
        let parts = quantities.sorted { $0.key < $1.key }.map { "\($0.key)x\($0.value)" }
        return "\(fitting.shipTypeId)|" + parts.joined(separator: ",")
    }

    /// Every pilot's fittings, collapsed to distinct fits in a stable order (by name, then
    /// signature).
    static func distinctFits(_ fittingsByPilot: [Int: [ESIFitting]]) -> [HangarMatrixFit] {
        var order: [String] = []
        var first: [String: ESIFitting] = [:]
        var owners: [String: [Int: Int]] = [:]
        for characterID in fittingsByPilot.keys.sorted() {
            for fitting in fittingsByPilot[characterID] ?? [] {
                let key = signature(fitting)
                if first[key] == nil {
                    first[key] = fitting
                    order.append(key)
                }
                if owners[key]?[characterID] == nil { owners[key, default: [:]][characterID] = fitting.fittingId }
            }
        }
        return order.compactMap { key in
            first[key].map { HangarMatrixFit(signature: key, fitting: $0, owners: owners[key] ?? [:]) }
        }
        .sorted { a, b in
            let order = a.fitting.name.localizedStandardCompare(b.fitting.name)
            return order != .orderedSame ? order == .orderedAscending : a.signature < b.signature
        }
    }

    /// Re-runs each pilot's Ready Room input against every distinct fit. Inputs must
    /// already hold names, requirements and places for all of them (`mergedInputs`).
    static func rows(fits: [HangarMatrixFit], inputs: [Int: ReadyRoomInput]) -> [HangarMatrixRow] {
        var cells: [String: [Int: ReadyRoomReport]] = [:]
        let byFittingID = Dictionary(fits.map { ($0.fitting.fittingId, $0.signature) }, uniquingKeysWith: { a, _ in a })
        for (characterID, base) in inputs {
            var input = base
            input.fittings = fits.map(\.fitting)
            for report in ReadyRoomEngine.reports(input) {
                guard let key = byFittingID[report.fittingID] else { continue }
                cells[key, default: [:]][characterID] = report
            }
        }
        return fits.map { fit in
            let pilotCells = cells[fit.signature] ?? [:]
            let sample = pilotCells.values.first
            return HangarMatrixRow(fit: fit,
                                   shipTypeName: sample?.shipTypeName ?? "Ship #\(fit.fitting.shipTypeId)",
                                   shipClassName: sample?.shipClassName ?? "Unknown",
                                   cells: pilotCells)
        }
    }

    /// Folds what every pilot's snapshot learned (type names, ship classes, skill
    /// requirements, training info, prices) into each pilot's input, so any pilot can be
    /// measured against any pilot's fit. Fit checks map from each owner's fitting ID to
    /// the row's canonical one.
    static func mergedInputs(_ inputs: [Int: ReadyRoomInput], fits: [HangarMatrixFit],
                             extraChecks: [Int: [Int: ReadyRoomFittingCheck]] = [:],
                             extraPlaces: [Int: ReadyRoomPlace] = [:]) -> [Int: ReadyRoomInput] {
        var names: [Int: String] = [:]
        var classes: [Int: String] = [:]
        var requirements: [Int: [Int: Int]] = [:]
        var skillInfo: [Int: SkillTrainingInfo] = [:]
        var prices: [Int: Double] = [:]
        for input in inputs.values {
            names.merge(input.typeNames) { a, _ in a }
            classes.merge(input.shipClassNames) { a, _ in a }
            requirements.merge(input.requirements) { a, _ in a }
            skillInfo.merge(input.skillInfo) { a, _ in a }
            prices.merge(input.prices) { a, _ in a }
        }
        var out: [Int: ReadyRoomInput] = [:]
        for (characterID, base) in inputs {
            var input = base
            input.typeNames.merge(names) { a, _ in a }
            input.shipClassNames.merge(classes) { a, _ in a }
            input.requirements.merge(requirements) { a, _ in a }
            input.skillInfo.merge(skillInfo) { a, _ in a }
            input.prices.merge(prices) { a, _ in a }
            input.places.merge(extraPlaces) { a, _ in a }
            var checks: [Int: ReadyRoomFittingCheck] = extraChecks[characterID] ?? [:]
            for fit in fits {
                if let own = fit.owners[characterID], let check = base.fittingChecks[own] {
                    checks[fit.fitting.fittingId] = check
                }
            }
            input.fittingChecks = checks
            out[characterID] = input
        }
        return out
    }

    /// Jita value of every part in a report (required and cargo); nil if any is unpriced.
    static func fitValue(_ report: ReadyRoomReport) -> Double? {
        var total = 0.0
        for part in report.parts {
            guard let price = part.unitPrice else { return nil }
            total += price * Double(part.required)
        }
        return total
    }

    /// Fits by tier for one pilot across all rows.
    static func tierCounts(_ rows: [HangarMatrixRow], pilot: Int) -> [ReadyRoomTier: Int] {
        var out: [ReadyRoomTier: Int] = [:]
        for row in rows { if let tier = row.cells[pilot]?.tier { out[tier, default: 0] += 1 } }
        return out
    }

    /// Ordering for "who's closest": tier, then jumps to staging, then ISK still to buy,
    /// then training left, then a stable ID order.
    static func closer(_ a: ReadyRoomReport, _ b: ReadyRoomReport, idA: Int, idB: Int) -> Bool {
        if a.tier != b.tier { return a.tier < b.tier }
        let ja = a.isStagingCurrentLocation ? -1 : (a.stagingJumps ?? .max)
        let jb = b.isStagingCurrentLocation ? -1 : (b.stagingJumps ?? .max)
        if ja != jb { return ja < jb }
        let ia = a.missingISK ?? .infinity, ib = b.missingISK ?? .infinity
        if ia != ib { return ia < ib }
        let ta = a.trainingSeconds ?? .infinity, tb = b.trainingSeconds ?? .infinity
        if ta != tb { return ta < tb }
        return idA < idB
    }
}
