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

// Mark:  Metric Tile Grid

struct SummaryGridView: View {
    let summaries: [CharacterSummary]

    private var totalWealth: Double    { summaries.reduce(0) { $0 + $1.wallet } }
    private var dailyMade: Double      { summaries.reduce(0) { $0 + $1.dailyISKMade } }
    private var dailySpent: Double     { summaries.reduce(0) { $0 + $1.dailyISKSpent } }
    private var dailyNet: Double       { dailyMade - dailySpent }
    private var totalSP: Int           { summaries.reduce(0) { $0 + $1.totalSP } }
    private var emptyQueues: Int       { summaries.filter(\.isQueueEmpty).count }
    private var activeJobs: Int        { summaries.reduce(0) { $0 + $1.activeIndustryJobCount } }
    private var activeContracts: Int   { summaries.reduce(0) { $0 + $1.activeContractCount } }
    private var expiredExtractors: Int { summaries.reduce(0) { $0 + $1.expiredExtractorCount } }
    private var onlineCount: Int       { summaries.filter(\.online).count }
    private var nextSkillFinish: Date? { summaries.compactMap(\.currentSkillFinish).min() }
    private var nextJobFinish: Date?   { summaries.compactMap(\.nextJobFinish).min() }

    var body: some View {
        HStack(spacing: 8) {
            MetricTileView(
                icon: "creditcard.fill", color: .green,
                value: EVEFormatters.formatISKShort(totalWealth),
                label: String(localized: "Total Wealth")
            )
            MetricTileView(
                icon: "arrow.left.arrow.right.circle.fill", color: dailyNet >= 0 ? .green : .red,
                value: (dailyNet >= 0 ? "+" : "") + EVEFormatters.formatISKShort(dailyNet),
                label: String(localized: "Today's ISK"),
                subLabel: "+\(EVEFormatters.formatISKShort(dailyMade)) / -\(EVEFormatters.formatISKShort(dailySpent))"
            )
            MetricTileView(
                icon: "brain.head.profile.fill", color: .cyan,
                value: formatSP(totalSP),
                label: String(localized: "Skill Points")
            )
            MetricTileView(
                icon: "person.fill.checkmark", color: .blue,
                value: "\(onlineCount) / \(summaries.count)",
                label: onlineCount == summaries.count ? String(localized: "All Online") : String(localized: "Online")
            )
            if emptyQueues > 0 {
                MetricTileView(
                    icon: "exclamationmark.triangle.fill", color: .orange,
                    value: "\(emptyQueues) empty",
                    label: String(localized: "Queue Alert"),
                    isAlert: true
                )
            } else if let finish = nextSkillFinish {
                MetricTileView(
                    icon: "graduationcap.fill", color: .green,
                    value: EVEFormatters.timeUntil(finish),
                    label: String(localized: "Next Skill"),
                    subLabel: "\(summaries.count == 1 ? "" : "\(summaries.count) queues · ")\(String(localized: "All training"))"
                )
            } else {
                MetricTileView(
                    icon: "graduationcap.fill", color: .green,
                    value: String(localized: "All active"),
                    label: String(localized: "Training")
                )
            }
            if activeJobs == 0 {
                MetricTileView(
                    icon: "hammer.fill", color: .secondary,
                    value: String(localized: "None active"),
                    label: String(localized: "Industry")
                )
            } else if let next = nextJobFinish {
                MetricTileView(
                    icon: "hammer.fill", color: .purple,
                    value: EVEFormatters.timeUntil(next),
                    label: String(localized: "Next Job"),
                    subLabel: "\(activeJobs) job\(activeJobs == 1 ? "" : "s") active"
                )
            } else {
                MetricTileView(
                    icon: "hammer.fill", color: .purple,
                    value: "\(activeJobs) active",
                    label: String(localized: "Industry")
                )
            }
            MetricTileView(
                icon: "doc.text.fill", color: .teal,
                value: activeContracts == 0 ? String(localized: "None active") : "\(activeContracts) active",
                label: String(localized: "Contracts")
            )
            if expiredExtractors > 0 {
                MetricTileView(
                    icon: "exclamationmark.triangle.fill", color: .red,
                    value: "\(expiredExtractors) offline",
                    label: String(localized: "PI Extractors"),
                    isAlert: true
                )
            }
        }
    }

    private func formatSP(_ sp: Int) -> String {
        if sp >= 1_000_000 { return String(format: "%.1fM", Double(sp) / 1_000_000) }
        if sp >= 1_000 { return String(format: "%.0fK", Double(sp) / 1_000) }
        return "\(sp)"
    }
}

struct MetricTileView: View {
    let icon: String
    let color: Color
    let value: String
    let label: String
    var subLabel: String? = nil
    var isAlert: Bool = false

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(color.opacity(0.18))
                    .frame(width: 36, height: 36)
                Image(systemName: icon)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(color)
            }
            .padding(.top, 12)

            Spacer(minLength: 6)

            Text(value)
                .font(.system(size: 13, weight: .bold).monospacedDigit())
                .foregroundStyle(isAlert ? color : .primary)
                .lineLimit(1)
                .minimumScaleFactor(0.65)
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 6)

            Spacer(minLength: 2)

            Text(label)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 4)

            if let sub = subLabel {
                Text(sub)
                    .font(.system(size: 9))
                    .foregroundStyle(.secondary.opacity(0.65))
                    .lineLimit(1)
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, 4)
                    .padding(.bottom, 2)
            }

            Spacer(minLength: 8)
        }
        .frame(maxWidth: .infinity, minHeight: 82)
        .background(
            RoundedRectangle(cornerRadius: 11)
                .fill(color.opacity(0.06))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 11)
                .strokeBorder(color.opacity(isAlert ? 0.50 : 0.18), lineWidth: 1)
        )
    }
}
