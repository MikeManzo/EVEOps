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

/// Industry jobs as a native table — sortable, resizable columns, live progress, ⌘C —
/// shared by Industry Overview (all pilots) and Corp Industry. The Character and
/// Est. Value columns appear only when records carry that data.
struct IndustryJobsTable: View {
    let records: [IndustryJobRecord]

    @Environment(ThemeManager.self) private var themeManager
    @State private var selection = Set<IndustryJobRecord.ID>()
    @State private var sortOrder: [KeyPathComparator<IndustryJobRecord>] = [
        KeyPathComparator(\.endDate, order: .reverse)
    ]

    private var showsCharacter: Bool { records.contains { $0.characterName != nil } }
    private var showsValue: Bool { records.contains { $0.estimatedValue != nil } }
    private var sorted: [IndustryJobRecord] { records.sorted(using: sortOrder) }

    var body: some View {
        TimelineView(.periodic(from: .now, by: 30)) { context in
            Table(sorted, selection: $selection, sortOrder: $sortOrder) {
                TableColumn("Blueprint", value: \.blueprintName) { row in
                    HStack(spacing: EVESpacing.md) {
                        CachedAsyncImage(url: EVEImageURL.typeIcon(row.job.productTypeId ?? row.job.blueprintTypeId, size: 64)) { image in
                            image.resizable()
                        } placeholder: {
                            RoundedRectangle(cornerRadius: EVERadius.xs).fill(.quaternary)
                        }
                        .frame(width: 20, height: 20)
                        .clipShape(RoundedRectangle(cornerRadius: EVERadius.xs))
                        Text(row.blueprintName).lineLimit(1).eveTruncationHelp(row.blueprintName)
                    }
                    .eveContextMenu(.item(typeID: row.job.blueprintTypeId, name: row.blueprintName))
                }
                .width(min: 180, ideal: 250)

                if showsCharacter {
                    TableColumn("Character", value: \.characterSortKey) { row in
                        Text(row.characterName ?? "").lineLimit(1).foregroundStyle(.secondary)
                    }
                    .width(min: 90, ideal: 120)
                }

                TableColumn("Activity", value: \.activityName) { row in
                    Label(row.activityName, systemImage: row.activityIcon)
                        .foregroundStyle(row.activityColor(palette: themeManager.palette))
                }
                .width(min: 110, ideal: 130)

                TableColumn("Runs", value: \.job.runs) { row in
                    Text(row.job.runs.formatted())
                        .monospacedDigit()
                        .frame(maxWidth: .infinity, alignment: .trailing)
                }
                .width(50)

                TableColumn("Progress", value: \.endDate) { row in
                    progressCell(row, now: context.date)
                }
                .width(min: 150, ideal: 190)

                TableColumn("Ends", value: \.endDate) { row in
                    Text(EVEDates.short(row.endDate, now: context.date))
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                        .help(EVEDates.full(row.endDate))
                }
                .width(min: 90, ideal: 120)

                if showsValue {
                    TableColumn("Est. Value", value: \.valueSortKey) { row in
                        Text(row.estimatedValue.map { "≈ " + EVEFormatters.formatISKShort($0) } ?? "—")
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .trailing)
                            .help("Estimated Jita buy value of the output · via Fuzzwork")
                    }
                    .width(min: 80, ideal: 100)
                }

                TableColumn("Cost", value: \.cost) { row in
                    Text(row.cost > 0 ? EVEFormatters.formatISKShort(row.cost) : "—")
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                }
                .width(min: 70, ideal: 90)
            }
            .tableStyle(.inset(alternatesRowBackgrounds: true))
            .copyable(sorted.filter { selection.contains($0.id) }.map(\.copyText))
        }
    }

    @ViewBuilder
    private func progressCell(_ row: IndustryJobRecord, now: Date) -> some View {
        if row.job.status == "active" {
            if row.endDate > now {
                HStack(spacing: EVESpacing.sm) {
                    EVEProgressBar(value: row.progress(at: now), tint: themeManager.palette.industry, height: 4)
                        .frame(width: 60)
                    Text(EVEFormatters.timeUntil(row.endDate))
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
            } else {
                Label("Ready", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            }
        } else {
            Text(row.job.status.capitalized)
                .foregroundStyle(.secondary)
        }
    }
}

/// Flattened, sortable view of an industry job for `IndustryJobsTable`.
struct IndustryJobRecord: Identifiable {
    let job: ESIIndustryJob
    let blueprintName: String
    /// Set when the table lists jobs across several pilots.
    var characterName: String? = nil
    /// Estimated product value (manufacturing), when known.
    var estimatedValue: Double? = nil

    var id: Int { job.jobId }
    var endDate: Date { job.endDate }
    var cost: Double { job.cost ?? 0 }
    var characterSortKey: String { characterName ?? "" }
    var valueSortKey: Double { estimatedValue ?? 0 }

    func progress(at now: Date) -> Double {
        let total = job.endDate.timeIntervalSince(job.startDate)
        guard total > 0 else { return 1 }
        return min(max(now.timeIntervalSince(job.startDate) / total, 0), 1)
    }

    var activityName: String {
        switch job.activityId {
        case 1: return String(localized: "Manufacturing")
        case 3: return String(localized: "TE Research")
        case 4: return String(localized: "ME Research")
        case 5: return String(localized: "Copying")
        case 8: return String(localized: "Invention")
        case 9: return String(localized: "Reactions")
        default: return String(localized: "Activity \(job.activityId)")
        }
    }

    var activityIcon: String {
        switch job.activityId {
        case 1: return "hammer.fill"
        case 3, 4: return "flask.fill"
        case 5: return "doc.on.doc.fill"
        case 8: return "lightbulb.fill"
        case 9: return "atom"
        default: return "gearshape.fill"
        }
    }

    /// Manufacturing takes the theme's industry color; the other activities keep distinct
    /// hues so they stay tellable-apart in a mixed list.
    func activityColor(palette: EVEPalette) -> Color {
        switch job.activityId {
        case 1: return palette.industry
        case 3, 4: return .purple
        case 5: return .cyan
        case 8: return .orange
        case 9: return .green
        default: return .secondary
        }
    }

    /// Tab-separated line for ⌘C, so rows paste cleanly into a spreadsheet.
    var copyText: String {
        [blueprintName, activityName, String(job.runs), job.status,
         job.endDate.formatted(.iso8601)]
            .joined(separator: "\t")
    }
}
