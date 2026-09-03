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
import UniformTypeIdentifiers

struct TrainingOverviewView: View {
    @Environment(AccountManager.self) var accountManager
    @Environment(DashboardPrefetcher.self) var prefetcher
    @AppStorage("backgroundPollInterval") var pollInterval: Double = 300
    @State var trainingData: [CharacterTrainingInfo] = []
    @State var isLoading = false
    @State var isRefreshing = false
    @State var lastRefresh: Date?
    @State var error: String?
    @State var now = Date()
    @AppStorage("collapsedSkillCharacters") var collapsedSkillCharactersRaw: String = ""
    @AppStorage("collapsedSkillGroups") var collapsedSkillGroupsRaw: String = ""
    @State var selectedSkill: SkillSelection?
    @State var skillSearchText: String = ""

    struct SkillSelection: Equatable {
        let skillId: Int
        let skillName: String
        let groupName: String
        let knownSkill: KnownSkill?
        let queueEntry: TrainingQueueEntry?

        static func == (lhs: SkillSelection, rhs: SkillSelection) -> Bool {
            lhs.skillId == rhs.skillId && lhs.queueEntry?.position == rhs.queueEntry?.position
        }
    }

    var body: some View {
        LoadingStateView(
            isLoading: isLoading,
            error: error,
            isEmpty: trainingData.isEmpty,
            hasContent: !trainingData.isEmpty,
            emptyMessage: "No training data",
            onRetry: { Task { await refresh() } }
        ) {
            HStack(spacing: 0) {
                ScrollView {
                    VStack(spacing: 20) {
                        aggregateSummary

                        ForEach(trainingData, id: \.characterID) { info in
                            characterTrainingCard(info)
                        }
                    }
                    .padding()
                }

                if let skill = selectedSkill {
                    Divider()
                    SkillDetailView(
                        skillId: skill.skillId,
                        skillName: skill.skillName,
                        groupName: skill.groupName,
                        knownSkill: skill.knownSkill,
                        queueEntry: skill.queueEntry
                    )
                    .frame(width: 320)
                }
            }
        }
        .safeAreaInset(edge: .top, spacing: 0) {
            VStack(spacing: 0) {
                HStack(spacing: 12) {
                    Text("Training Overview")
                        .font(.largeTitle.bold())
                    Spacer()
                    RelativeTimestamp(date: lastRefresh)
                    RefreshButton(isRefreshing: isRefreshing) {
                        Task { await refresh() }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 12)
                .padding(.bottom, 8)

                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.secondary)
                    TextField("Search known skills...", text: $skillSearchText)
                        .textFieldStyle(.plain)
                    if !skillSearchText.isEmpty {
                        Button {
                            skillSearchText = ""
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                    if !trainingData.isEmpty {
                        Divider()
                            .frame(height: 16)
                        Button(action: exportSkillsToCSV) {
                            Label("Export CSV", systemImage: "square.and.arrow.up")
                                .font(.caption)
                        }
                        .buttonStyle(.borderless)
                    }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
                .padding(.horizontal, 16)
                .padding(.bottom, 8)

                Divider()
            }
            .background(.background)
        }
        .navigationTitle("")
        .task(id: accountManager.selectedCharacterID) {
            trainingData = []
            selectedSkill = nil
            if buildFromPrefetcher() { return }
            isLoading = true
            await loadTraining()
        }
        .periodicTick(every: 1) { now = Date() }
        .autoRefresh(every: pollInterval) { await refresh() }
        .onChange(of: AppRouter.shared.refreshTick) { _, _ in
            Task { await refresh() }
        }
    }

    func refresh() async {
        isRefreshing = true
        defer { isRefreshing = false }
        await loadTraining()
    }

}
