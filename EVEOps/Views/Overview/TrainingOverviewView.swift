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
    @Environment(ThemeManager.self) var themeManager
    var palette: EVEPalette { themeManager.palette }
    @AppStorage("backgroundPollInterval") var pollInterval: Double = 300
    @State var trainingData: [CharacterTrainingInfo] = []
    @State var isLoading = false
    @State var isRefreshing = false
    @State var lastRefresh: Date?
    @State var error: String?
    /// Drives the coarse, minute-level text (queue end, durations). The seconds-level
    /// countdown and progress ring in the hero update themselves in their own
    /// `TimelineView`, so the whole screen no longer re-renders every second.
    @State var now = Date()
    @State var selectedSkill: SkillSelection?
    @State var skillSearchText: String = ""
    @State var isExportingSkills = false
    @State var isExportingAllSkills = false
    @AppStorage("training.tab") var tab: TrainingTab = .queue
    @State var skillGroupFilter: Int?
    @State var skillSortOrder: [KeyPathComparator<KnownSkillRow>] = [KeyPathComparator(\.name)]
    @State var selectedSkillRowID: KnownSkillRow.ID?
    /// Header extras fetched on demand: the pilot's attributes (for the attribute bars,
    /// remap info and clone-state check) and the current skill's primary/secondary
    /// attribute dogma IDs (164…168).
    @State var attributes: ESICharacterAttributes?
    @State var currentSkillAttributeIDs: [Int] = []
    /// Header insights: plugged-in implants, types for the queued skills (rank and
    /// attribute pair, for the remap payoff) and the character's saved Skill Planner plan.
    @State var implantTypes: [ESIType] = []
    @State var implantsLoaded = false
    @State var queueSkillTypes: [Int: ESIType] = [:]
    @State var savedPlan: [SkillPlanItem] = []
    @State var planSkillTypes: [Int: ESIType] = [:]

    enum TrainingTab: String, CaseIterable, Identifiable {
        case queue, skills
        var id: Self { self }
    }

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
            emptyMessage: "No Training Data",
            emptySystemImage: "brain.head.profile",
            onRetry: { Task { await refresh() } }
        ) {
            if let info = trainingData.first {
                VStack(spacing: 0) {
                    trainingHero(info)
                        .padding(.horizontal, EVESpacing.xl)
                        .padding(.top, EVESpacing.lg)
                        .padding(.bottom, EVESpacing.md)

                    tabBar(info)
                        .padding(.horizontal, EVESpacing.xl)
                        .padding(.bottom, EVESpacing.md)

                    Divider()

                    // Both tabs stay mounted and only the active one is shown. Inserting the
                    // Skills table into the already laid-out window sent the split view into
                    // endless Update Constraints passes (hang, then crash); built with the
                    // first layout, it's fine.
                    ZStack {
                        tabPane(.queue) { queueTab(info) }
                        tabPane(.skills) { skillsTab(info) }
                    }                }
            }
        }
        .eveInspector(item: $selectedSkill, width: 320) { skill in
            SkillDetailView(
                skillId: skill.skillId,
                skillName: skill.skillName,
                groupName: skill.groupName,
                knownSkill: skill.knownSkill,
                queueEntry: skill.queueEntry
            )
        }
        .onChange(of: selectedSkill) { _, newValue in
            // Closing the inspector deselects the table row that opened it.
            if newValue == nil { selectedSkillRowID = nil }
        }
        .eveScreenHeader("Training Overview", section: .training) {
            RelativeTimestamp(date: lastRefresh)
            exportMenu
            RefreshButton(isRefreshing: isRefreshing) {
                Task { await refresh() }
            }
        }
        .task(id: accountManager.selectedCharacterID) {
            trainingData = []
            selectedSkill = nil
            skillGroupFilter = nil
            attributes = nil
            currentSkillAttributeIDs = []
            implantTypes = []
            implantsLoaded = false
            queueSkillTypes = [:]
            savedPlan = []
            planSkillTypes = [:]
            if buildFromPrefetcher() { return }
            isLoading = true
            await loadTraining()
        }
        .task(id: heroDetailsKey) { await loadHeroDetails() }
        .task { await prefetcher.warmSkillGroupCatalog() }
        .task(id: insightsKey) { await loadInsights() }
        .periodicTick(every: 60) { now = Date() }
        .autoRefresh(every: pollInterval) { await refresh() }
        .onChange(of: AppRouter.shared.refreshTick) { _, _ in
            Task { await refresh() }
        }
    }

    // MARK: Tab bar

    private func tabBar(_ info: CharacterTrainingInfo) -> some View {
        HStack(spacing: EVESpacing.lg) {
            Picker("View", selection: $tab) {
                Text("Queue (\(info.queue.count))").tag(TrainingTab.queue)
                Text("Trained Skills (\(info.knownSkillCount))").tag(TrainingTab.skills)
            }
            .eveSegmentedPicker()
            .labelsHidden()
            .fixedSize()

            Spacer(minLength: EVESpacing.md)

            // Always laid out (hidden on Queue) so switching tabs doesn't resize the bar.
            Group {
                skillGroupMenu(info)
                EVESearchField("Search skills or groups", text: $skillSearchText)
                    .frame(maxWidth: 260)
            }
            .opacity(tab == .skills ? 1 : 0)
            .allowsHitTesting(tab == .skills)
            .accessibilityHidden(tab != .skills)
        }
    }

    private func tabPane(_ pane: TrainingTab, @ViewBuilder content: () -> some View) -> some View {
        content()
            .opacity(tab == pane ? 1 : 0)
            .allowsHitTesting(tab == pane)
            .accessibilityHidden(tab != pane)
    }

    private var exportMenu: some View {
        Menu {
            Button("Export Known Skills…", systemImage: "square.and.arrow.up") {
                Task { await exportSkillsToCSV() }
            }
            .disabled(trainingData.isEmpty || isExportingSkills)
            Button("Export All EVE Skills…", systemImage: "square.and.arrow.up.on.square") {
                Task { await exportAllSkillsToCSV() }
            }
            .disabled(isExportingAllSkills)
        } label: {
            if isExportingSkills || isExportingAllSkills {
                ProgressView().controlSize(.small)
            } else {
                Label("Export", systemImage: "square.and.arrow.up")
            }
        }
        .help("Export skills to CSV")
    }

    func refresh() async {
        isRefreshing = true
        defer { isRefreshing = false }
        await loadTraining()
    }

}
