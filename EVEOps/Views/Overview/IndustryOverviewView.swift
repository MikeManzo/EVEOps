import SwiftUI

struct IndustryOverviewView: View {
    @Environment(AccountManager.self) private var accountManager
    @State private var jobs: [CharacterIndustryGroup] = []
    @State private var isLoading = true
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
        .navigationTitle("Industry Overview")
        .task { await loadJobs() }
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

    private func loadJobs() async {
        isLoading = true
        var groups: [CharacterIndustryGroup] = []
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
                // Skip
            }
        }
        jobs = groups
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
            }
        }
        .task {
            if let typeInfo: ESIType = try? await ESIClient.shared.fetch("/universe/types/\(job.blueprintTypeId)/") {
                blueprintName = typeInfo.name
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
