//
// This file is part of EVEOps.
//
// EVEOps is free software: you can redistribute it and/or modify
// it under the terms of the GNU General Public License as published by
// the Free Software Foundation, version 3 or later.
//
// Copyright (c) 2026 CitizenCoder
//

import SwiftUI

// MARK:  Entry Brief Accuracy

/// How the Route Planner's entry briefs have held up: for each verdict, how often a
/// player kill followed in the system within half an hour. Shown in Settings ▸ Advanced
/// for tuning the brief's thresholds.
struct BriefAccuracySection: View {
    @State private var report: BriefCalibrationReport?
    @State private var isChecking = false
    @State private var confirmReset = false

    private var windowMinutes: Int { Int(BriefCalibrationEngine.outcomeWindow / 60) }

    var body: some View {
        Section {
            Text("Each lowsec entry brief is saved on this Mac, then checked against zKillboard for player kills in that system in the \(windowMinutes) minutes that followed. Clear verdicts should rarely be followed by a kill, and Danger verdicts often.")
                .font(.caption)
                .foregroundStyle(.secondary)

            if let report {
                if report.resolved == 0 {
                    Text(report.pending == 0
                         ? "No briefs yet. Plan a route through lowsec to start collecting."
                         : "\(report.pending) briefs waiting to be checked. Each can be checked about \(Int((BriefCalibrationEngine.outcomeWindow + BriefCalibrationEngine.reportingLag) / 60)) minutes after it was made.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(EntryStatus.allCases, id: \.self) { status in
                        rateRow(status.label, report.byStatus[status], noun: "a kill followed")
                    }
                    rateRow("Gate camp confirmed", report.camps, noun: "another kill on that gate")
                    ForEach([BriefVerdict.Kind.roamingGang, .soloHunter, .quiet], id: \.self) { kind in
                        rateRow(kind.label, report.byKind[kind], noun: "a kill followed")
                    }
                    if let hint = hint(report) {
                        Text(hint).font(.caption).foregroundStyle(.secondary)
                    }
                }
                footer(report)
            } else {
                ProgressView().controlSize(.small)
            }
        } header: {
            Text("Entry Brief Accuracy")
        }
        .task {
            // Show what's saved straight away; checking can take a while.
            await load(check: false)
            await load(check: true)
        }
        .confirmationDialog("Reset entry brief accuracy?", isPresented: $confirmReset) {
            Button("Reset", role: .destructive) {
                Task {
                    await BriefCalibrationLog.shared.clear()
                    await load(check: false)
                }
            }
        } message: {
            Text("All saved verdicts and results on this Mac are deleted.")
        }
    }

    @ViewBuilder
    private func rateRow(_ title: String, _ row: BriefCalibrationReport.Row?, noun: String) -> some View {
        if let row, row.verdicts > 0, let rate = row.rate {
            LabeledContent(title) {
                VStack(alignment: .trailing, spacing: 2) {
                    Text("\(rate.formatted(.percent.precision(.fractionLength(0)))) \(noun)")
                        .monospacedDigit()
                    Text(row.isMeaningful
                         ? "\(row.followedByKill) of \(row.verdicts) briefs"
                         : "\(row.followedByKill) of \(row.verdicts) briefs · too few to judge")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    @ViewBuilder
    private func footer(_ report: BriefCalibrationReport) -> some View {
        HStack {
            Button(isChecking ? "Checking…" : "Check Now") {
                Task { await load(check: true) }
            }
            .disabled(isChecking)
            Button("Reset…") { confirmReset = true }
                .foregroundStyle(.red)
                .disabled(report.resolved + report.pending == 0)
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                if report.pending > 0 {
                    Text("\(report.pending) waiting to be checked")
                }
                if let oldest = report.oldest {
                    Text("Since \(oldest.formatted(date: .abbreviated, time: .omitted))")
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
    }

    /// One line on what the numbers suggest, once there's enough to go on.
    private func hint(_ report: BriefCalibrationReport) -> String? {
        let clear = report.byStatus[.clear], danger = report.byStatus[.danger]
        if let clear, clear.isMeaningful, let rate = clear.rate, rate >= 0.15 {
            return "Clear briefs are followed by kills fairly often. The brief may be reassuring pilots too easily."
        }
        if let danger, danger.isMeaningful, let rate = danger.rate, rate < 0.2 {
            return "Danger briefs are rarely followed by kills. The brief may be raising the alarm too readily."
        }
        return nil
    }

    private func load(check: Bool) async {
        if check {
            isChecking = true
            report = await BriefCalibrationLog.shared.refreshedReport()
            isChecking = false
        } else {
            report = await BriefCalibrationLog.shared.report()
        }
    }
}
