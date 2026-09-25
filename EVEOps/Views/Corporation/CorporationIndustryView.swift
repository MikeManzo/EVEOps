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
                .background(EVESurface.bar)

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

    private var rows: [IndustryJobRecord] {
        filteredJobs
            .map { IndustryJobRecord(job: $0, blueprintName: blueprintNames[$0.blueprintTypeId] ?? "Blueprint #\($0.blueprintTypeId)") }
    }

    // MARK: Table

    private var jobsTable: some View {
        IndustryJobsTable(records: rows)
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
