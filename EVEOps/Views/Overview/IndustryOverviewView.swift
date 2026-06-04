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
import FoundationModels

struct IndustryOverviewView: View {
    @Environment(AccountManager.self) private var accountManager
    @Environment(DashboardPrefetcher.self) private var prefetcher
    @State private var jobs: [CharacterIndustryGroup] = []
    @State private var isLoading = false
    @State private var error: String?
    @State private var showActiveOnly = true

    var body: some View {
        LoadingStateView(isLoading: isLoading, error: error, isEmpty: jobs.isEmpty, emptyMessage: "No industry jobs found") {
            VStack(spacing: 0) {
                HStack {
                    Toggle("Active jobs only", isOn: $showActiveOnly)
                    Spacer()
                    Text("\(totalJobCount) jobs")
                        .foregroundStyle(.secondary)
                }
                .padding(10)
                .background(.bar)

                if #available(macOS 26.0, *) {
                    IndustryAIInsightCard(jobs: jobs)
                        .padding(10)
                }

                List {
                    ForEach(filteredJobs, id: \.characterName) { group in
                        Section(group.characterName) {
                            ForEach(group.jobs) { job in
                                IndustryJobRow(job: job)
                            }
                        }
                    }
                }
            }
        }
        .safeAreaInset(edge: .top, spacing: 0) {
            HStack {
                Text("Industry Overview")
                    .font(.largeTitle.bold())
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(.background)
        }
        .navigationTitle("Industry Overview")
        .task {
            if buildFromPrefetcher() { return }
            isLoading = true
            await loadJobs()
        }
    }

    private var totalJobCount: Int {
        filteredJobs.reduce(0) { $0 + $1.jobs.count }
    }

    private var filteredJobs: [CharacterIndustryGroup] {
        if !showActiveOnly { return jobs }
        return jobs.compactMap { group in
            let active = group.jobs.filter { $0.status == "active" }
            if active.isEmpty { return nil }
            return CharacterIndustryGroup(characterName: group.characterName, jobs: active)
        }
    }

    private func buildFromPrefetcher() -> Bool {
        var groups: [CharacterIndustryGroup] = []
        for account in accountManager.accounts {
            guard let prefetched = prefetcher.data(for: account.characterID) else { return false }
            if !prefetched.industryJobs.isEmpty {
                groups.append(CharacterIndustryGroup(
                    characterName: account.characterName,
                    jobs: prefetched.industryJobs.sorted { $0.endDate > $1.endDate }
                ))
            }
        }
        jobs = groups
        // Kick off background refresh for complete data (include_completed)
        Task { await loadJobs() }
        return true
    }

    private func loadJobs() async {
        if jobs.isEmpty { isLoading = true }
        error = nil
        var groups: [CharacterIndustryGroup] = []
        var lastError: Error?
        for account in accountManager.accounts {
            do {
                let token = try await accountManager.validToken(for: account)
                let rawJobs: [ESIIndustryJob] = try await ESIClient.shared.fetch(
                    "/characters/\(account.characterID)/industry/jobs/",
                    token: token,
                    queryItems: [URLQueryItem(name: "include_completed", value: "true")]
                )
                if !rawJobs.isEmpty {
                    groups.append(CharacterIndustryGroup(
                        characterName: account.characterName,
                        jobs: rawJobs.sorted { $0.endDate > $1.endDate }
                    ))
                }
            } catch {
                lastError = error
            }
        }
        jobs = groups
        if groups.isEmpty, let lastError {
            self.error = lastError.localizedDescription
        }
        isLoading = false
    }
}

struct CharacterIndustryGroup {
    let characterName: String
    let jobs: [ESIIndustryJob]
}

struct IndustryJobRow: View {
    let job: ESIIndustryJob
    @State private var blueprintName: String = ""
    @State private var estimatedValue: Double? = nil

    var body: some View {
        HStack {
            Image(systemName: activityIcon)
                .foregroundStyle(activityColor)

            VStack(alignment: .leading, spacing: 2) {
                Text(blueprintName.isEmpty ? "Blueprint #\(job.blueprintTypeId)" : blueprintName)
                    .font(.body)
                Text("\(activityName) - \(job.runs) run\(job.runs > 1 ? "s" : "")")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 2) {
                if job.status == "active" {
                    if job.endDate > Date() {
                        Text(EVEFormatters.timeUntil(job.endDate))
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.blue)
                    } else {
                        Text("Ready")
                            .font(.caption)
                            .foregroundStyle(.green)
                    }
                } else {
                    Text(job.status.capitalized)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if let value = estimatedValue {
                    Text("≈ \(EVEFormatters.formatISKShort(value))")
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.mint)
                        .help("Estimated Jita buy-order value · \(job.runs) run\(job.runs == 1 ? "" : "s") · via Fuzzwork")
                }
            }
        }
        .task {
            if let typeInfo = await UniverseCache.shared.type(id: job.blueprintTypeId) {
                blueprintName = typeInfo.name
            }
        }
        .task {
            guard job.activityId == 1, let productTypeId = job.productTypeId else { return }
            if let prices = try? await FuzzworkClient.shared.prices(typeIds: [productTypeId]),
               let price = prices[productTypeId] {
                estimatedValue = price.buyPercentile * Double(job.runs)
            }
        }
    }

    private var activityName: String {
        switch job.activityId {
        case 1: return "Manufacturing"
        case 3: return "TE Research"
        case 4: return "ME Research"
        case 5: return "Copying"
        case 8: return "Invention"
        case 9: return "Reactions"
        default: return "Activity \(job.activityId)"
        }
    }

    private var activityIcon: String {
        switch job.activityId {
        case 1: return "hammer.fill"
        case 3, 4: return "flask.fill"
        case 5: return "doc.on.doc.fill"
        case 8: return "lightbulb.fill"
        case 9: return "atom"
        default: return "gearshape.fill"
        }
    }

    private var activityColor: Color {
        switch job.activityId {
        case 1: return .blue
        case 3, 4: return .purple
        case 5: return .cyan
        case 8: return .orange
        case 9: return .green
        default: return .secondary
        }
    }
}

// MARK: Industry AI Insight Card

@available(macOS 26.0, *)
struct IndustryAIInsightCard: View {
    let jobs: [CharacterIndustryGroup]

    @AppStorage("aiInsightsEnabled") private var aiInsightsEnabled = false
    @AppStorage("aiInsightIndustry") private var aiInsightIndustry = true
    @State private var insight: IndustryInsight?
    @State private var isGenerating = false
    @State private var generationError: String?
    @State private var hasAutoGenerated = false

    private var model: SystemLanguageModel { .default }

    var body: some View {
        if aiInsightsEnabled && aiInsightIndustry, case .available = model.availability {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Label("AI Insight", systemImage: "sparkles")
                        .font(.subheadline.bold())
                        .foregroundStyle(.purple)
                    Spacer()
                    if insight != nil, !isGenerating {
                        Button {
                            Task { await generate() }
                        } label: {
                            Image(systemName: "arrow.clockwise")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                        .help("Regenerate insight")
                    }
                }

                if isGenerating {
                    HStack(spacing: 8) {
                        ProgressView().controlSize(.small)
                        Text("Analyzing industry data\u{2026}")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                } else if let insight {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(insight.summary)
                            .font(.subheadline)
                            .fixedSize(horizontal: false, vertical: true)
                        HStack(alignment: .top, spacing: 6) {
                            Image(systemName: "lightbulb.fill")
                                .font(.caption).foregroundStyle(.yellow).padding(.top, 1)
                            Text(insight.suggestion)
                                .font(.caption).foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                } else if let error = generationError {
                    Text(error).font(.caption).foregroundStyle(.red.opacity(0.8))
                } else {
                    Button("Generate Insight") { Task { await generate() } }
                        .buttonStyle(.bordered).controlSize(.small)
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(.purple.opacity(0.2)))
            .task(id: jobs.first?.characterName ?? "") {
                guard !hasAutoGenerated else { return }
                hasAutoGenerated = true
                await generate()
            }
        }
    }

    private func generate() async {
        isGenerating = true
        generationError = nil

        let allJobs = jobs.flatMap(\.jobs)
        let activeJobs = allJobs.filter { $0.status == "active" }

        let activityCounts = Dictionary(grouping: allJobs, by: { activityLabel($0.activityId) })
            .map { activity, jobList in (activity: activity, count: jobList.count) }
            .sorted { $0.count > $1.count }

        let bpCounts = Dictionary(grouping: allJobs, by: { $0.blueprintTypeId })
            .map { typeId, jobList in (typeId: typeId, count: jobList.count) }
            .sorted { $0.count > $1.count }
            .prefix(8)
        var topBlueprints: [String] = []
        for item in bpCounts {
            let name = (await UniverseCache.shared.type(id: item.typeId))?.name ?? "Blueprint #\(item.typeId)"
            topBlueprints.append(name)
        }

        let characterName = jobs.count == 1
            ? jobs[0].characterName
            : jobs.map(\.characterName).joined(separator: ", ")

        do {
            insight = try await IntelligenceService.shared.analyzeIndustry(
                characterName: characterName,
                totalJobs: allJobs.count,
                activeJobs: activeJobs.count,
                activityBreakdown: activityCounts,
                topBlueprints: topBlueprints
            )
        } catch {
            generationError = "Unable to generate insight. Try again later."
        }
        isGenerating = false
    }

    private func activityLabel(_ id: Int) -> String {
        switch id {
        case 1: return "Manufacturing"
        case 3: return "TE Research"
        case 4: return "ME Research"
        case 5: return "Copying"
        case 8: return "Invention"
        case 9: return "Reactions"
        default: return "Activity \(id)"
        }
    }
}
