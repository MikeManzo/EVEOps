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

nonisolated extension EntryStatus: Codable {}

/// One Route Entry Brief verdict, kept so it can be checked against what happened next.
nonisolated struct BriefVerdict: Codable, Sendable, Equatable, Identifiable {
    /// The kinds of signal a brief can raise, without their details.
    enum Kind: String, Codable, Sendable, CaseIterable {
        case gateCamp, roamingGang, soloHunter, recentKills, unreportedKills, quiet

        init(_ signal: ThreatSignal) {
            switch signal {
            case .gateCamp:        self = .gateCamp
            case .roamingGang:     self = .roamingGang
            case .soloHunter:      self = .soloHunter
            case .recentKills:     self = .recentKills
            case .unreportedKills: self = .unreportedKills
            case .quiet:           self = .quiet
            }
        }

        var label: String {
            switch self {
            case .gateCamp:        return "Gate camp"
            case .roamingGang:     return "Roaming gang"
            case .soloHunter:      return "Cloaky hunter"
            case .recentKills:     return "Recent kills"
            case .unreportedKills: return "Unreported kills"
            case .quiet:           return "Quiet"
            }
        }
    }

    /// What zKillboard showed in the system during the `outcomeWindow` after the verdict.
    struct Outcome: Codable, Sendable, Equatable {
        let checkedAt: Date
        let playerKills: Int
        /// Player kills on a gate the verdict named as camped.
        let campGateKills: Int
    }

    let id: UUID
    let systemID: Int
    let issuedAt: Date
    let status: EntryStatus
    let score: Double
    let kinds: [Kind]
    let campGateIDs: [Int]
    var outcome: Outcome?

    init(threat: SystemThreat, issuedAt: Date, id: UUID = UUID()) {
        self.id = id
        systemID = threat.systemID
        self.issuedAt = issuedAt
        status = threat.status
        score = threat.score
        var kinds: [Kind] = []
        for kind in threat.signals.map(Kind.init) where !kinds.contains(kind) { kinds.append(kind) }
        self.kinds = kinds
        campGateIDs = threat.signals.compactMap {
            if case let .gateCamp(gate, _, _, _, _) = $0 { return gate }
            return nil
        }
    }
}

/// How often each kind of verdict was followed by a player kill.
nonisolated struct BriefCalibrationReport: Sendable, Equatable {
    struct Row: Sendable, Equatable {
        let verdicts: Int
        let followedByKill: Int
        var rate: Double? { verdicts > 0 ? Double(followedByKill) / Double(verdicts) : nil }
        /// Below this many checked verdicts a rate says more about luck than the thresholds.
        var isMeaningful: Bool { verdicts >= BriefCalibrationEngine.minSample }
    }

    let byStatus: [EntryStatus: Row]
    let byKind: [BriefVerdict.Kind: Row]
    /// Camp verdicts, and how many saw another kill on the same gate.
    let camps: Row
    let resolved: Int
    let pending: Int
    let oldest: Date?
}

// MARK:  Engine

/// Decides which brief verdicts to keep, when each can be checked, what happened after
/// it, and how the thresholds have done overall. Pure inputs only, so it is fully
/// unit-testable; `BriefCalibrationLog` does the storage and fetching.
nonisolated enum BriefCalibrationEngine {
    /// A verdict is right or wrong by what happens in this long after it.
    static let outcomeWindow: TimeInterval = 30 * 60
    /// zKillboard gets killmails minutes to tens of minutes late, so wait this much past
    /// the window before checking it.
    static let reportingLag: TimeInterval = 15 * 60
    /// The same verdict for the same system within this long is one verdict, not many:
    /// the live watch rebuilds briefs every few minutes and would otherwise swamp the log.
    static let repeatWindow: TimeInterval = 30 * 60
    /// zKillboard looks back at most a week; verdicts not checked by then never will be.
    static let checkDeadline: TimeInterval = 6 * 86_400
    static let maxVerdicts = 2_000
    static let maxAge: TimeInterval = 30 * 86_400
    static let minSample = 10

    /// Adds verdicts for `threats` to `log`, skipping any that repeat the latest verdict
    /// for the same system within `repeatWindow`, then trims the log to its bounds.
    static func record(_ threats: [SystemThreat], into log: [BriefVerdict], now: Date) -> [BriefVerdict] {
        var latest: [Int: BriefVerdict] = [:]
        for v in log where latest[v.systemID].map({ v.issuedAt > $0.issuedAt }) ?? true { latest[v.systemID] = v }

        var out = log
        for threat in threats.sorted(by: { $0.systemID < $1.systemID }) {
            if let last = latest[threat.systemID],
               last.status == threat.status,
               now.timeIntervalSince(last.issuedAt) < repeatWindow { continue }
            let verdict = BriefVerdict(threat: threat, issuedAt: now)
            out.append(verdict)
            latest[threat.systemID] = verdict
        }
        return prune(out, now: now)
    }

    /// Drops verdicts older than `maxAge`, unchecked ones past `checkDeadline`, and the
    /// oldest beyond `maxVerdicts`.
    static func prune(_ log: [BriefVerdict], now: Date) -> [BriefVerdict] {
        let kept = log.filter { v in
            let age = now.timeIntervalSince(v.issuedAt)
            return age <= maxAge && (v.outcome != nil || age <= checkDeadline)
        }
        .sorted { $0.issuedAt < $1.issuedAt }
        return Array(kept.suffix(maxVerdicts))
    }

    /// Unchecked verdicts whose window has closed and had time to reach zKillboard.
    static func due(_ log: [BriefVerdict], now: Date) -> [BriefVerdict] {
        log.filter { $0.outcome == nil && isDue($0, now: now) }
    }

    static func isDue(_ verdict: BriefVerdict, now: Date) -> Bool {
        now.timeIntervalSince(verdict.issuedAt) >= outcomeWindow + reportingLag
    }

    /// What happened in the verdict's system during the `outcomeWindow` after it.
    /// - Parameter kills: kills zKillboard has for the system, covering that window.
    static func outcome(for verdict: BriefVerdict, kills: [ThreatKill], now: Date) -> BriefVerdict.Outcome {
        let end = verdict.issuedAt.addingTimeInterval(outcomeWindow)
        let after = kills.filter {
            $0.isPlayerKill && $0.systemID == verdict.systemID && $0.time > verdict.issuedAt && $0.time <= end
        }
        let gates = Set(verdict.campGateIDs)
        return BriefVerdict.Outcome(
            checkedAt: now,
            playerKills: after.count,
            campGateKills: after.filter { $0.stargateID.map(gates.contains) ?? false }.count
        )
    }

    /// Seconds zKillboard needs to look back from `now` to cover every verdict's window.
    static func lookback(for verdicts: [BriefVerdict], now: Date) -> Int {
        guard let oldest = verdicts.map(\.issuedAt).min() else { return 3600 }
        let hours = Int((now.timeIntervalSince(oldest) / 3600).rounded(.up))
        return min(168, max(1, hours)) * 3600
    }

    static func report(_ log: [BriefVerdict]) -> BriefCalibrationReport {
        let checked = log.filter { $0.outcome != nil }
        func row(_ verdicts: [BriefVerdict], hit: (BriefVerdict.Outcome) -> Bool = { $0.playerKills > 0 }) -> BriefCalibrationReport.Row {
            .init(verdicts: verdicts.count, followedByKill: verdicts.filter { hit($0.outcome!) }.count)
        }

        var byStatus: [EntryStatus: BriefCalibrationReport.Row] = [:]
        for status in EntryStatus.allCases { byStatus[status] = row(checked.filter { $0.status == status }) }
        var byKind: [BriefVerdict.Kind: BriefCalibrationReport.Row] = [:]
        for kind in BriefVerdict.Kind.allCases { byKind[kind] = row(checked.filter { $0.kinds.contains(kind) }) }

        return BriefCalibrationReport(
            byStatus: byStatus,
            byKind: byKind,
            camps: row(checked.filter { !$0.campGateIDs.isEmpty }, hit: { $0.campGateKills > 0 }),
            resolved: checked.count,
            pending: log.count - checked.count,
            oldest: log.map(\.issuedAt).min()
        )
    }
}
