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
import OSLog

struct SkillPlannerView: View {
    @Environment(AccountManager.self) var accountManager
    @Environment(DashboardPrefetcher.self) var prefetcher

    @State var trainingData: [CharacterTrainingInfo] = []
    @State var attributes: ESICharacterAttributes?
    @State var planItems: [SkillPlanItem] = []
    @State var skillTypes: [Int: ESIType] = [:]
    @State var searchText = ""
    @State var selectedGroupId: Int?
    @State var isLoading = false
    @State var error: String?
    @State var browserMode: BrowserMode = .skills
    @State var isImporting = false
    @State var importMessage: String?
    @State var showingClipboardHelp = false

    var selectedCharInfo: CharacterTrainingInfo? {
        let id = accountManager.selectedAccount?.characterID ?? 0
        return trainingData.first { $0.characterID == id }
    }

    var characterSkillMap: [Int: Int] {
        selectedCharInfo?.skillGroups.flatMap(\.skills)
            .reduce(into: [:]) { $0[$1.skillId] = $1.trainedLevel } ?? [:]
    }

    var body: some View {
        LoadingStateView(isLoading: isLoading, error: error, isEmpty: trainingData.isEmpty, emptyMessage: "No character data") {
            HStack(spacing: 0) {
                Spacer(minLength: 15)    // MRM
                planPanel
                    .frame(width: 320)
                    .background(.regularMaterial)
                Divider()
                skillBrowser
            }
        }
        .safeAreaInset(edge: .top, spacing: 0) {
            HStack {
                Text("Skill Planner")
                    .font(.largeTitle.bold())
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(.background)
        }
        .navigationTitle("")
        .task(id: accountManager.selectedCharacterID) {
            await loadData()
        }
        .onChange(of: prefetcher.lastRefresh) { _, _ in
            // A background prefetch just landed — pick up any skills that finished
            // training since we last loaded, without dropping into the full loading
            // state (that would tear down the Item Tree's in-progress search/selection).
            Task { await refreshTrainingDataSilently() }
        }
    }

}
