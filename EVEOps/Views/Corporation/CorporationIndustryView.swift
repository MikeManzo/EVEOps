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

struct CorporationIndustryView: View {
    @Environment(AccountManager.self) private var accountManager
    @Environment(ThemeManager.self) private var themeManager
    @State private var jobs: [ESIIndustryJob] = []
    @State private var blueprintNames: [Int: String] = [:]
    @State private var isLoading = true
    @State private var error: String?
    @State private var showActiveOnly = true
    @State private var selection = Set<CorpJobRow.ID>()
    @State private var sortOrder: [KeyPathComparator<CorpJobRow>] = [
        KeyPathComparator(\.endDate, order: .reverse)
    ]

    var body: some View {
        LoadingStateView(isLoading: isLoading, error: error, isEmpty: jobs.isEmpty, emptyMessage: "No Corporation Industry Jobs", emptySystemImage: "hammer") {
            VStack(spacing: 0) {
                HStack {
                    Toggle("Active jobs only", isOn: $showActiveOnly)
                    Spacer()
                    Text("\(filteredJobs.count) jobs")
                        .foregroundStyle(.secondary)
                }
                .padding(10)
                .background(.bar)

                jobsTable
            }
        }
        .eveScreenHeader("Corp Industry", section: .corpIndustry) {
            FreshnessIndicator(isLoading: isLoading) { await loadJobs() }
        }
        .task(id: accountManager.selectedCharacterID) {
            jobs = []
            isLoading = true
            await loadJobs()
        }
    }

    private var filteredJobs: [ESIIndustryJob] {
        if showActiveOnly {
            return jobs.filter { $0.status == "active" }
        }
        return jobs
    }

    private var rows: [CorpJobRow] {
        filteredJobs
            .map { CorpJobRow(job: $0, blueprintName: blueprintNames[$0.blueprintTypeId] ?? "Blueprint #\($0.blueprintTypeId)") }
            .sorted(using: sortOrder)
    }

    // MARK: Table

    private var jobsTable: some View {
        TimelineView(.periodic(from: .now, by: 30)) { context in
            Table(rows, selection: $selection, sortOrder: $sortOrder) {
                TableColumn("Blueprint", value: \.blueprintName) { row in
                    HStack(spacing: EVESpacing.md) {
                        CachedAsyncImage(url: EVEImageURL.typeIcon(row.job.blueprintTypeId, size: 64)) { image in
                            image.resizable()
                        } placeholder: {
                            RoundedRectangle(cornerRadius: EVERadius.xs).fill(.quaternary)
                        }
                        .frame(width: 20, height: 20)
                        .clipShape(RoundedRectangle(cornerRadius: EVERadius.xs))
                        Text(row.blueprintName).lineLimit(1)
                    }
                    .eveContextMenu(.item(typeID: row.job.blueprintTypeId, name: row.blueprintName))
                }
                .width(min: 180, ideal: 260)

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
                    Text(row.endDate, format: .dateTime.month(.abbreviated).day().hour().minute())
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
                .width(min: 100, ideal: 120)

                TableColumn("Cost", value: \.cost) { row in
                    Text(row.cost > 0 ? EVEFormatters.formatISKShort(row.cost) : "—")
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                }
                .width(min: 70, ideal: 90)
            }
            .tableStyle(.inset(alternatesRowBackgrounds: true))
            .copyable(rows.filter { selection.contains($0.id) }.map(\.copyText))
        }
    }

    @ViewBuilder
    private func progressCell(_ row: CorpJobRow, now: Date) -> some View {
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

    private func loadJobs() async {
        guard let account = accountManager.selectedAccount else { return }
        isLoading = true
        do {
            let token = try await accountManager.validToken(for: account)
            jobs = try await ESIClient.shared.fetch(
                "/corporations/\(account.corporationID)/industry/jobs/",
                token: token,
                queryItems: [URLQueryItem(name: "include_completed", value: "true")]
            )
            let types = await UniverseCache.shared.types(ids: Array(Set(jobs.map(\.blueprintTypeId))))
            blueprintNames = types.compactMapValues(\.name)
        } catch {
            self.error = error.localizedDescription
        }
        isLoading = false
    }
}

/// Flattened, sortable view of a corporation industry job for the jobs table.
struct CorpJobRow: Identifiable {
    let job: ESIIndustryJob
    let blueprintName: String

    var id: Int { job.jobId }
    var endDate: Date { job.endDate }
    var cost: Double { job.cost ?? 0 }

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
