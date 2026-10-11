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
import OSLog

/// Keeps every Route Entry Brief verdict on disk and, once each one's window has passed,
/// asks zKillboard what actually happened in that system, so the brief's thresholds can
/// be judged against real outcomes. Everything stays on this Mac, bounded by
/// `BriefCalibrationEngine.maxVerdicts` and `maxAge`.
actor BriefCalibrationLog {
    static let shared = BriefCalibrationLog()

    static let storageURL: URL = {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return base.appendingPathComponent("EVEOps/brief-calibration.json")
    }()

    /// Background checks run at most this often; opening the report checks right away.
    private static let checkInterval: TimeInterval = 15 * 60
    /// Systems checked per background pass, to stay polite to zKillboard.
    private static let maxSystemsPerCheck = 10

    private static let log = Logger(subsystem: "CitizenCoder.EVEOps", category: "briefCalibration")

    private var verdicts: [BriefVerdict]?
    private var lastCheck: Date?
    private var checking: Task<Void, Never>?

    func record(_ threats: [SystemThreat], now: Date = Date()) {
        guard !threats.isEmpty else { return }
        let before = loaded()
        let after = BriefCalibrationEngine.record(threats, into: before, now: now)
        if after != before { save(after) }

        if lastCheck.map({ now.timeIntervalSince($0) >= Self.checkInterval }) ?? true {
            lastCheck = now
            checking = checking ?? Task { await self.checkDue(limit: Self.maxSystemsPerCheck) }
        }
    }

    /// Checks every verdict that's due, then returns the report.
    func refreshedReport() async -> BriefCalibrationReport {
        if let checking { await checking.value }
        lastCheck = Date()
        await checkDue(limit: .max)
        return report()
    }

    func report() -> BriefCalibrationReport {
        BriefCalibrationEngine.report(loaded())
    }

    func clear() {
        save([])
    }

    // MARK: Checking

    /// Looks up outcomes for due verdicts, one zKillboard request per system covering all
    /// of that system's due verdicts. Systems that can't be fetched wait for the next pass.
    private func checkDue(limit: Int) async {
        defer { checking = nil }
        let due = BriefCalibrationEngine.due(loaded(), now: Date())
        guard !due.isEmpty else { return }

        let bySystem = Dictionary(grouping: due, by: \.systemID)
        // Oldest first, so nothing slips past zKillboard's week of history.
        let systems = bySystem.keys.sorted {
            bySystem[$0]!.map(\.issuedAt).min()! < bySystem[$1]!.map(\.issuedAt).min()!
        }

        var outcomes: [UUID: BriefVerdict.Outcome] = [:]
        for systemID in systems.prefix(limit) {
            let pending = bySystem[systemID]!
            let now = Date()
            // The brief's own window when it's enough, so recent checks reuse its cached fetch.
            let seconds = max(SystemDangerService.briefWindowHours * 3600,
                              BriefCalibrationEngine.lookback(for: pending, now: now))
            guard let kills = await SystemDangerService.shared.kills(systemID: systemID, pastSeconds: seconds) else {
                continue
            }
            for verdict in pending {
                outcomes[verdict.id] = BriefCalibrationEngine.outcome(for: verdict, kills: kills, now: now)
            }
        }
        guard !outcomes.isEmpty else { return }

        // Apply to the current log, which may have grown while we were fetching.
        var current = loaded()
        for i in current.indices { if let o = outcomes[current[i].id] { current[i].outcome = o } }
        save(BriefCalibrationEngine.prune(current, now: Date()))
        Self.log.info("Checked \(outcomes.count) entry brief verdicts")
    }

    // MARK: Storage

    private func loaded() -> [BriefVerdict] {
        if let verdicts { return verdicts }
        var decoded: [BriefVerdict] = []
        if let data = try? Data(contentsOf: Self.storageURL) {
            do {
                decoded = try JSONDecoder().decode([BriefVerdict].self, from: data)
            } catch {
                Self.log.error("Couldn't read brief calibration log: \(error.localizedDescription)")
            }
        }
        verdicts = decoded
        return decoded
    }

    private func save(_ log: [BriefVerdict]) {
        verdicts = log
        do {
            try FileManager.default.createDirectory(
                at: Self.storageURL.deletingLastPathComponent(), withIntermediateDirectories: true
            )
            try JSONEncoder().encode(log).write(to: Self.storageURL, options: .atomic)
        } catch {
            Self.log.error("Couldn't save brief calibration log: \(error.localizedDescription)")
        }
    }
}
