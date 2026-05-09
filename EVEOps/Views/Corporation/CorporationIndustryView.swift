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
    @State private var jobs: [ESIIndustryJob] = []
    @State private var isLoading = true
    @State private var error: String?
    @State private var showActiveOnly = true

    var body: some View {
        LoadingStateView(isLoading: isLoading, error: error, isEmpty: jobs.isEmpty, emptyMessage: "No corporation industry jobs found") {
            VStack(spacing: 0) {
                HStack {
                    Toggle("Active jobs only", isOn: $showActiveOnly)
                    Spacer()
                    Text("\(filteredJobs.count) jobs")
                        .foregroundStyle(.secondary)
                }
                .padding(10)
                .background(.bar)

                List(filteredJobs) { job in
                    IndustryJobRow(job: job)
                }
            }
        }
        .navigationTitle("Corp Industry")
        .task { await loadJobs() }
    }

    private var filteredJobs: [ESIIndustryJob] {
        if showActiveOnly {
            return jobs.filter { $0.status == "active" }
        }
        return jobs
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
            jobs.sort { $0.endDate > $1.endDate }
        } catch {
            self.error = error.localizedDescription
        }
        isLoading = false
    }
}
