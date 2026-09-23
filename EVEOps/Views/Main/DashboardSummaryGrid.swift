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

    @Environment(ThemeManager.self) private var themeManager
    private var palette: EVEPalette { themeManager.palette }

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
                label: String(localized: "Total Wealth"),
                destination: .finances
            )
            MetricTileView(
                icon: "arrow.left.arrow.right.circle.fill", color: dailyNet >= 0 ? .green : .red,
                value: (dailyNet >= 0 ? "+" : "") + EVEFormatters.formatISKShort(dailyNet),
                label: String(localized: "Today's ISK"),
                subLabel: "+\(EVEFormatters.formatISKShort(dailyMade)) / -\(EVEFormatters.formatISKShort(dailySpent))",
                destination: .finances
            )
            MetricTileView(
                icon: "brain.head.profile.fill", color: palette.knowledge,
                value: formatSP(totalSP),
                label: String(localized: "Skill Points"),
                destination: .training
            )
            MetricTileView(
                icon: "person.fill.checkmark", color: palette.online,
                value: "\(onlineCount) / \(summaries.count)",
                label: onlineCount == summaries.count ? String(localized: "All Online") : String(localized: "Online")
            )
            if emptyQueues > 0 {
                MetricTileView(
                    icon: "exclamationmark.triangle.fill", color: .orange,
                    value: "\(emptyQueues) empty",
                    label: String(localized: "Queue Alert"),
                    isAlert: true,
                    destination: .training
                )
            } else if let finish = nextSkillFinish {
                MetricTileView(
                    icon: "graduationcap.fill", color: .green,
                    value: EVEFormatters.timeUntil(finish),
                    label: String(localized: "Next Skill"),
                    subLabel: "\(summaries.count == 1 ? "" : "\(summaries.count) queues · ")\(String(localized: "All training"))",
                    destination: .training
                )
            } else {
                MetricTileView(
                    icon: "graduationcap.fill", color: .green,
                    value: String(localized: "All active"),
                    label: String(localized: "Training"),
                    destination: .training
                )
            }
            if activeJobs == 0 {
                MetricTileView(
                    icon: "hammer.fill", color: .secondary,
                    value: String(localized: "None active"),
                    label: String(localized: "Industry"),
                    destination: .industry
                )
            } else if let next = nextJobFinish {
                MetricTileView(
                    icon: "hammer.fill", color: palette.industry,
                    value: EVEFormatters.timeUntil(next),
                    label: String(localized: "Next Job"),
                    subLabel: "\(activeJobs) job\(activeJobs == 1 ? "" : "s") active",
                    destination: .industry
                )
            } else {
                MetricTileView(
                    icon: "hammer.fill", color: palette.industry,
                    value: "\(activeJobs) active",
                    label: String(localized: "Industry"),
                    destination: .industry
                )
            }
            MetricTileView(
                icon: "doc.text.fill", color: palette.contracts,
                value: activeContracts == 0 ? String(localized: "None active") : "\(activeContracts) active",
                label: String(localized: "Contracts"),
                destination: .contracts
            )
            if expiredExtractors > 0 {
                MetricTileView(
                    icon: "exclamationmark.triangle.fill", color: .red,
                    value: "\(expiredExtractors) offline",
                    label: String(localized: "PI Extractors"),
                    isAlert: true,
                    destination: .colonies
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
    /// When set, the tile becomes a button that jumps to this sidebar section.
    var destination: NavigationSection? = nil

    @Environment(AccountManager.self) private var accountManager
    /// Set by a per-character card so clicking one of its tiles also switches to that pilot.
    @Environment(\.metricTileCharacterID) private var characterID

    var body: some View {
        if let destination {
            Button {
                if let characterID { accountManager.selectedCharacterID = characterID }
                AppRouter.shared.pendingSection = destination
            } label: {
                tile
            }
            .buttonStyle(.plain)
            .eveHoverable(cornerRadius: EVERadius.xl)
            .help(Text("Open \(Text(destination.title))"))
            .accessibilityHint(Text("Opens \(Text(destination.title))"))
        } else {
            tile
        }
    }

    private var tile: some View {
        VStack(spacing: 0) {
            ZStack {
                RoundedRectangle(cornerRadius: EVERadius.md)
                    .fill(color.opacity(0.18))
                    .frame(width: 36, height: 36)
                Image(systemName: icon)
                    .font(.eveSubsectionTitle)
                    .foregroundStyle(color)
            }
            .padding(.top, 12)

            Spacer(minLength: 6)

            Text(value)
                .font(.eveTileValue)
                .foregroundStyle(isAlert ? color : .primary)
                .lineLimit(1)
                .minimumScaleFactor(0.65)
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 6)
                .eveNumeric(value)

            Spacer(minLength: 2)

            Text(label)
                .font(.eveLabelMedium)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 4)

            if let sub = subLabel {
                Text(sub)
                    .font(.eveMicro)
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
            RoundedRectangle(cornerRadius: EVERadius.xl)
                .fill(color.opacity(0.06))
        )
        .overlay(
            RoundedRectangle(cornerRadius: EVERadius.xl)
                .strokeBorder(color.opacity(isAlert ? 0.50 : 0.18), lineWidth: 1)
        )
    }
}

extension EnvironmentValues {
    /// The character whose card a `MetricTileView` sits on, if any.
    @Entry var metricTileCharacterID: Int? = nil
}
