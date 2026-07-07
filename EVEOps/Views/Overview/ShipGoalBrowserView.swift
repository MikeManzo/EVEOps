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

// MARK:  Constants

private let prereqAttrPairs: [(skillAttr: Int, levelAttr: Int)] = [
    (182, 277), (183, 278), (184, 279),
    (1285, 1289), (1286, 1290), (1287, 1291)
]

private let spThresholds: [Int: Int] = [
    0: 0, 1: 250, 2: 1_414, 3: 8_000, 4: 45_255, 5: 256_000
]

// MARK:  Accumulator

private final class PrereqAccumulator {
    var maxRequired: [Int: Int] = [:]
    var names: [Int: String] = [:]
    var visited: Set<Int> = []
}

// MARK:  Entry Model

private struct PrereqEntry: Identifiable {
    let skillId: Int
    let name: String
    let required: Int
    let trained: Int
    var id: Int { skillId }
    var isMet: Bool { trained >= required }
}

// MARK:  AI Goal Card

private struct ResolvedAISkill: Identifiable {
    let id: Int
    let name: String
    let targetLevel: Int
    let currentLevel: Int
    let rationale: String
    var needsTraining: Bool { currentLevel < targetLevel }
}

@available(macOS 26.0, *)
private struct ShipGoalAICard: View {
    let characterSkills: [Int: Int]?
    var onAddToPlan: ((SkillPlanItem) -> Void)?
    let onSearch: (String) -> Void

    @State private var goalText = ""
    @State private var isLoading = false
    @State private var recommendation: ShipGoalRecommendation?
    @State private var resolvedSkills: [ResolvedAISkill] = []
    @State private var errorMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("AI Training Advisor", systemImage: "sparkles")
                .font(.caption.bold())
                .foregroundStyle(.secondary)
                .symbolEffect(.variableColor.iterative.dimInactiveLayers, isActive: isLoading)

            HStack(spacing: 8) {
                TextField("Describe your goal… e.g. \"market trader\", \"PvP pilot\", \"miner\"", text: $goalText)
                    .textFieldStyle(.plain)
                    .onSubmit { Task { await fetch() } }
                    .disabled(isLoading)

                if isLoading {
                    ProgressView().controlSize(.mini)
                } else {
                    Button { Task { await fetch() } } label: {
                        Image(systemName: "arrow.up.circle.fill")
                            .font(.title3)
                            .foregroundStyle(goalText.count >= 5 ? Color.accentColor : Color.secondary.opacity(0.3))
                    }
                    .buttonStyle(.plain)
                    .disabled(goalText.count < 5)
                }
            }
            .padding(8)
            .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))

            if isLoading {
                HStack(spacing: 6) {
                    ProgressView().controlSize(.small)
                    Text(resolvedSkills.isEmpty && recommendation != nil
                         ? "Building training plan…"
                         : "Analyzing with Apple Intelligence…")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 2)
            }

            if let err = errorMessage {
                Text(err).font(.caption).foregroundStyle(.red).lineLimit(2)
            } else if let rec = recommendation {
                Text(rec.playstyleSummary)
                    .font(.caption).foregroundStyle(.secondary).lineLimit(3)

                if !resolvedSkills.isEmpty {
                    Divider()
                    HStack {
                        Text("Recommended Training")
                            .font(.caption.bold()).foregroundStyle(.secondary)
                        Spacer()
                        if let add = onAddToPlan {
                            let pending = resolvedSkills.filter(\.needsTraining)
                            if !pending.isEmpty {
                                Button {
                                    for s in pending {
                                        add(SkillPlanItem(skillId: s.id, skillName: s.name,
                                                          fromLevel: s.currentLevel, targetLevel: s.targetLevel))
                                    }
                                } label: {
                                    Label("Add All", systemImage: "plus.circle.fill").font(.caption.bold())
                                }
                                .buttonStyle(.borderedProminent)
                                .controlSize(.mini)
                            }
                        }
                    }

                    ScrollView {
                        VStack(spacing: 0) {
                            ForEach(resolvedSkills) { skill in
                                skillRow(skill)
                                Divider().padding(.leading, 8)
                            }
                        }
                    }
                    .frame(maxHeight: 240)
                } else if isLoading {
                    // resolving names — spinner already visible
                } else if !rec.skillFocus.isEmpty {
                    Text("Focus: " + rec.skillFocus.joined(separator: " · "))
                        .font(.caption2).foregroundStyle(.tertiary).lineLimit(2)
                }

                if !rec.suggestedSearch.isEmpty {
                    Button { onSearch(rec.suggestedSearch) } label: {
                        Label("Search for \(rec.shipClass.isEmpty ? rec.suggestedSearch : rec.shipClass)",
                              systemImage: "magnifyingglass")
                            .font(.caption.bold())
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                }
            }
        }
        .padding(10)
    }

    private func skillRow(_ skill: ResolvedAISkill) -> some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text(skill.name).font(.caption.bold()).lineLimit(1)
                if !skill.rationale.isEmpty {
                    Text(skill.rationale).font(.caption2).foregroundStyle(.tertiary).lineLimit(1)
                }
            }
            Spacer()
            HStack(spacing: 4) {
                levelChip(skill.currentLevel, dimmed: true)
                Image(systemName: "arrow.right").font(.caption2).foregroundStyle(.secondary)
                levelChip(skill.targetLevel)
            }
            if skill.needsTraining {
                if let add = onAddToPlan {
                    Button {
                        add(SkillPlanItem(skillId: skill.id, skillName: skill.name,
                                         fromLevel: skill.currentLevel, targetLevel: skill.targetLevel))
                    } label: {
                        Image(systemName: "plus.circle").font(.title3).foregroundStyle(Color.accentColor)
                    }
                    .buttonStyle(.plain)
                }
            } else {
                Image(systemName: "checkmark.circle.fill").font(.subheadline).foregroundStyle(.green)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
    }

    private func levelChip(_ level: Int, dimmed: Bool = false) -> some View {
        let colors: [Color] = [.gray, .gray, .blue, .green, .purple, .orange]
        let color = colors[min(level, 5)]
        return Text("L\(level)")
            .font(.caption2.bold())
            .foregroundStyle(dimmed ? color.opacity(0.5) : color)
            .padding(.horizontal, 5).padding(.vertical, 1)
            .background(dimmed ? color.opacity(0.05) : color.opacity(0.15), in: Capsule())
    }

    private func fetch() async {
        guard goalText.count >= 5, !isLoading else { return }
        isLoading = true
        errorMessage = nil
        recommendation = nil
        resolvedSkills = []

        // First call: playstyle summary + ship info (simple JSON, reliable)
        do {
            let rec = try await IntelligenceService.shared.recommendShipsForGoal(
                goalDescription: goalText, characterSP: 0, trainedGroups: [])
            recommendation = rec
        } catch {
            isLoading = false
            errorMessage = "Apple Intelligence is unavailable. Please try again."
            return
        }

        // Second call: specific skill list with lenient GoalTrainingList format
        if let training = try? await IntelligenceService.shared.recommendSkillsForGoal(goalDescription: goalText),
           !training.skills.isEmpty {
            await resolveSkillNames(training.skills)
        }

        isLoading = false
    }

    private func resolveSkillNames(_ skills: [GoalTrainingSkill]) async {
        let names = skills.map(\.skillName)
        struct IDResp: Decodable { let inventoryTypes: [ESIIDName]? }
        let resp: IDResp? = try? await ESIClient.shared.post("/universe/ids/", body: names)
        let nameToId = Dictionary(
            uniqueKeysWithValues: (resp?.inventoryTypes ?? []).map { ($0.name, $0.id) }
        )
        resolvedSkills = skills.compactMap { skill in
            guard let id = nameToId[skill.skillName] else { return nil }
            return ResolvedAISkill(
                id: id,
                name: skill.skillName,
                targetLevel: min(max(skill.targetLevel, 1), 5),
                currentLevel: characterSkills?[id] ?? 0,
                rationale: skill.rationale
            )
        }
    }
}

// MARK:  ShipGoalBrowserView

struct ShipGoalBrowserView: View {
    let characterSkills: [Int: Int]?
    let characterAttributes: ESICharacterAttributes?
    var onAddToPlan: ((SkillPlanItem) -> Void)?

    @Environment(AccountManager.self) private var accountManager

    @State private var searchText = ""
    @State private var searchResults: [(id: Int, name: String)] = []
    @State private var isSearching = false
    @State private var searchDebounce: Task<Void, Never>?

    @State private var selectedShipId: Int?
    @State private var selectedShipName = ""
    @State private var isResolving = false
    @State private var prereqMessage: String?

    @State private var prerequisites: [PrereqEntry] = []
    @State private var skillTypeMap: [Int: ESIType] = [:]
    @State private var showMetSkills = false

    private var missing: [PrereqEntry] {
        prerequisites.filter { !$0.isMet }.sorted { $0.name < $1.name }
    }
    private var met: [PrereqEntry] {
        prerequisites.filter { $0.isMet }.sorted { $0.name < $1.name }
    }

    var body: some View {
        VStack(spacing: 0) {
            shipSearchBar.padding(10)
            Divider()
            content
        }
    }

    // MARK: Search Bar

    private var shipSearchBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
            TextField("Search for a ship…", text: $searchText)
                .textFieldStyle(.plain)
                .onChange(of: searchText) { _, new in triggerSearch(new) }
                .onSubmit {
                    if let first = searchResults.first { selectShip(first.id, name: first.name) }
                }
            if isSearching {
                ProgressView().controlSize(.mini)
            } else if !searchText.isEmpty {
                Button { clearSelection() } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(8)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
    }

    // MARK: Content

    @ViewBuilder
    private var content: some View {
        if isSearching {
            ProgressView("Searching…").frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if !searchResults.isEmpty && selectedShipId == nil {
            searchResultsList
        } else if isResolving {
            VStack(spacing: 10) {
                ProgressView()
                Text("Resolving skill requirements…")
                    .font(.caption).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let msg = prereqMessage {
            VStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle").font(.title2).foregroundStyle(.tertiary)
                Text(msg).font(.caption).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if !prerequisites.isEmpty {
            requirementsList
        } else {
            emptyState
        }
    }

    // MARK: Empty State

    private var emptyState: some View {
        VStack(spacing: 0) {
            if #available(macOS 26.0, *), IntelligenceService.isSupported {
                ShipGoalAICard(characterSkills: characterSkills, onAddToPlan: onAddToPlan) { name in
                    searchText = name
                    triggerSearch(name)
                }
                Divider()
            }
            VStack(spacing: 12) {
                Image(systemName: "scope")
                    .font(.system(size: 42)).foregroundStyle(.tertiary)
                Text("Search for a ship to see what skills you need")
                    .font(.subheadline).foregroundStyle(.secondary)
                Text("Missing skills and total training time shown at a glance")
                    .font(.caption).foregroundStyle(.tertiary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: Search Results

    private var searchResultsList: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(searchResults, id: \.id) { result in
                    Button { selectShip(result.id, name: result.name) } label: {
                        HStack(spacing: 12) {
                            AsyncImage(url: EVEImageURL.typeIcon(result.id, size: 64)) { phase in
                                if let img = phase.image {
                                    img.resizable()
                                        .frame(width: 48, height: 48)
                                        .clipShape(RoundedRectangle(cornerRadius: 8))
                                } else {
                                    RoundedRectangle(cornerRadius: 8).fill(.quaternary)
                                        .frame(width: 48, height: 48)
                                }
                            }
                            Text(result.name)
                                .font(.body)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            Image(systemName: "chevron.right").font(.subheadline).foregroundStyle(.tertiary)
                        }
                        .padding(.horizontal, 12).padding(.vertical, 10).contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    Divider().padding(.leading, 72)
                }
            }
        }
    }

    // MARK: Requirements List

    private var requirementsList: some View {
        let totalSP = missing.reduce(0) { $0 + spNeeded($1) }
        let totalSecs = missing.reduce(0.0) { sum, e in
            sum + (characterAttributes.map { trainingTime(e, attrs: $0) } ?? 0)
        }
        let completionDate = totalSecs > 0 ? Date().addingTimeInterval(totalSecs) : nil as Date?

        return ScrollView {
            VStack(spacing: 0) {
                shipHeader(totalSP: totalSP, totalSecs: totalSecs, completionDate: completionDate)
                Divider()

                if missing.isEmpty {
                    alreadyReadyView
                } else {
                    sectionHeader(icon: "exclamationmark.circle.fill", color: .orange,
                                  title: "Needs Training", count: missing.count)
                    ForEach(missing) { entry in
                        prereqRow(entry)
                        Divider().padding(.leading, 52)
                    }
                }

                if !met.isEmpty {
                    Divider()
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) { showMetSkills.toggle() }
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: showMetSkills ? "chevron.down" : "chevron.right")
                                .font(.caption).foregroundStyle(.secondary).frame(width: 14)
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(.green).font(.caption)
                            Text("Already Trained (\(met.count))")
                                .font(.subheadline.bold()).foregroundStyle(.secondary)
                            Spacer()
                        }
                        .padding(.horizontal, 12).padding(.vertical, 10).contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)

                    if showMetSkills {
                        ForEach(met) { entry in
                            metRow(entry)
                            Divider().padding(.leading, 52)
                        }
                    }
                }
            }
        }
    }

    // MARK: Ship Header

    private func shipHeader(totalSP: Int, totalSecs: Double, completionDate: Date?) -> some View {
        HStack(spacing: 14) {
            if let id = selectedShipId {
                AsyncImage(url: EVEImageURL.typeIcon(id, size: 128)) { phase in
                    if let img = phase.image {
                        img.resizable()
                            .frame(width: 56, height: 56)
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                    } else {
                        RoundedRectangle(cornerRadius: 10).fill(.quaternary).frame(width: 56, height: 56)
                    }
                }
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(selectedShipName).font(.headline).lineLimit(1)

                if missing.isEmpty {
                    Label("Ready to fly", systemImage: "checkmark.circle.fill")
                        .font(.caption.bold()).foregroundStyle(.green)
                } else {
                    HStack(spacing: 10) {
                        Label("\(missing.count) skill\(missing.count == 1 ? "" : "s") needed",
                              systemImage: "exclamationmark.circle")
                            .font(.caption).foregroundStyle(.orange)
                        if totalSP > 0 {
                            Label(formatSP(totalSP), systemImage: "brain.head.profile")
                                .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                        }
                        if totalSecs > 0 {
                            Label(formatDuration(totalSecs), systemImage: "clock")
                                .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                        }
                    }
                    if let date = completionDate {
                        Text("Finishes: \(date.formatted(date: .abbreviated, time: .shortened))")
                            .font(.caption2).foregroundStyle(.tertiary)
                    }
                }
            }

            Spacer()

            if !missing.isEmpty, let add = onAddToPlan {
                Button {
                    for entry in missing {
                        add(SkillPlanItem(skillId: entry.skillId, skillName: entry.name,
                                         fromLevel: entry.trained, targetLevel: entry.required))
                    }
                } label: {
                    Label("Add All to Plan", systemImage: "plus.circle.fill")
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            }
        }
        .padding(14)
    }

    private var alreadyReadyView: some View {
        VStack(spacing: 8) {
            Image(systemName: "checkmark.circle.fill").font(.title).foregroundStyle(.green)
            Text("You can already fly this ship!")
                .font(.headline).foregroundStyle(.green)
            Text("All \(prerequisites.count) skill requirements are met.")
                .font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(24)
    }

    private func sectionHeader(icon: String, color: Color, title: String, count: Int) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon).foregroundStyle(color).font(.caption)
            Text("\(title) (\(count))").font(.subheadline.bold()).foregroundStyle(.secondary)
            Spacer()
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
        .background(Color.secondary.opacity(0.05))
    }

    // MARK: Skill Rows

    private func prereqRow(_ entry: PrereqEntry) -> some View {
        let sp = spNeeded(entry)
        let secs = characterAttributes.map { trainingTime(entry, attrs: $0) } ?? 0.0

        return HStack(spacing: 10) {
            AsyncImage(url: EVEImageURL.typeIcon(entry.skillId, size: 64)) { phase in
                if let img = phase.image {
                    img.resizable().frame(width: 28, height: 28).clipShape(RoundedRectangle(cornerRadius: 4))
                } else {
                    RoundedRectangle(cornerRadius: 4).fill(.quaternary).frame(width: 28, height: 28)
                }
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(entry.name).font(.subheadline).lineLimit(1)
                HStack(spacing: 4) {
                    levelBadge(entry.trained, dimmed: true)
                    Image(systemName: "arrow.right").font(.caption2).foregroundStyle(.secondary)
                    levelBadge(entry.required)
                }
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 2) {
                if sp > 0 {
                    Text(formatSP(sp)).font(.caption2.monospacedDigit()).foregroundStyle(.secondary)
                }
                if secs > 0 {
                    Text(formatDuration(secs)).font(.caption2.monospacedDigit()).foregroundStyle(.green)
                }
            }

            if let add = onAddToPlan {
                Button {
                    add(SkillPlanItem(skillId: entry.skillId, skillName: entry.name,
                                     fromLevel: entry.trained, targetLevel: entry.required))
                } label: {
                    Image(systemName: "plus.circle").font(.title3).foregroundStyle(Color.accentColor)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
    }

    private func metRow(_ entry: PrereqEntry) -> some View {
        HStack(spacing: 10) {
            AsyncImage(url: EVEImageURL.typeIcon(entry.skillId, size: 64)) { phase in
                if let img = phase.image {
                    img.resizable().frame(width: 28, height: 28)
                        .clipShape(RoundedRectangle(cornerRadius: 4)).opacity(0.5)
                } else {
                    RoundedRectangle(cornerRadius: 4).fill(.quaternary).frame(width: 28, height: 28)
                }
            }
            Text(entry.name).font(.subheadline).foregroundStyle(.secondary).lineLimit(1)
            Spacer()
            HStack(spacing: 4) {
                levelBadge(entry.trained, dimmed: true)
                Text("/ L\(entry.required)").font(.caption2).foregroundStyle(.tertiary)
            }
            Image(systemName: "checkmark").font(.caption2).foregroundStyle(.green)
        }
        .padding(.horizontal, 12).padding(.vertical, 6)
    }

    // MARK: Search Logic

    private func triggerSearch(_ query: String) {
        searchDebounce?.cancel()
        if selectedShipId != nil && query == selectedShipName { return }
        guard query.count >= 2 else {
            if query.isEmpty { searchResults = [] }
            return
        }
        selectedShipId = nil
        prerequisites = []
        prereqMessage = nil
        searchDebounce = Task {
            try? await Task.sleep(nanoseconds: 280_000_000)
            guard !Task.isCancelled else { return }
            await runSearch(query)
        }
    }

    private func runSearch(_ query: String) async {
        isSearching = true
        defer { isSearching = false }

        var candidates: [(id: Int, name: String)] = []

        if let account = accountManager.selectedAccount,
           let token = try? await accountManager.validToken(for: account) {
            struct SearchResp: Decodable { let inventoryType: [Int]? }
            struct NameEntry: Decodable { let id: Int; let name: String }
            let resp: SearchResp? = try? await ESIClient.shared.fetch(
                "/characters/\(account.characterID)/search/", token: token,
                queryItems: [
                    URLQueryItem(name: "categories", value: "inventory_type"),
                    URLQueryItem(name: "search", value: query),
                    URLQueryItem(name: "strict", value: "false")
                ]
            )
            let ids = Array((resp?.inventoryType ?? []).prefix(200))
            guard !ids.isEmpty else { searchResults = []; return }
            let names: [NameEntry] = (try? await ESIClient.shared.post("/universe/names/", body: ids)) ?? []
            candidates = names.map { (id: $0.id, name: $0.name) }
        } else {
            struct IDResp: Decodable { let inventoryTypes: [ESIIDName]? }
            let resp: IDResp? = try? await ESIClient.shared.post("/universe/ids/", body: [query])
            candidates = (resp?.inventoryTypes ?? []).map { (id: $0.id, name: $0.name) }
        }

        guard !candidates.isEmpty else { searchResults = []; return }

        // Filter to ships (ESI category 6)
        let typeMap = await UniverseCache.shared.types(ids: candidates.map(\.id))
        let groupIds = Set(typeMap.values.map(\.groupId))
        let groupMap = await UniverseCache.shared.groups(ids: groupIds)

        let lower = query.lowercased()
        searchResults = candidates.filter { item in
            guard let t = typeMap[item.id], let g = groupMap[t.groupId] else { return false }
            return g.categoryId == 6
        }.sorted {
            let a = $0.name.lowercased(), b = $1.name.lowercased()
            if (a == lower) != (b == lower) { return a == lower }
            if a.hasPrefix(lower) != b.hasPrefix(lower) { return a.hasPrefix(lower) }
            return a < b
        }
    }

    private func selectShip(_ id: Int, name: String) {
        selectedShipId = id
        selectedShipName = name
        searchText = name
        searchResults = []
        prerequisites = []
        showMetSkills = false
        Task { await resolvePrerequisites(for: id) }
    }

    private func clearSelection() {
        searchText = ""; searchResults = []
        selectedShipId = nil; selectedShipName = ""
        prerequisites = []; prereqMessage = nil
        showMetSkills = false
    }

    // MARK: Prerequisite Resolution

    private func resolvePrerequisites(for typeId: Int) async {
        isResolving = true
        prereqMessage = nil
        defer { isResolving = false }

        guard let typeData = await UniverseCache.shared.type(id: typeId),
              let attrs = typeData.dogmaAttributes else {
            prereqMessage = "Could not load ship data."
            return
        }

        let acc = PrereqAccumulator()
        await walkPrereqs(attrs: attrs, acc: acc)

        guard !acc.maxRequired.isEmpty else {
            prereqMessage = "This ship has no skill requirements."
            return
        }

        // Batch-fetch type data for SP/time calculations
        let skillIds = Array(acc.maxRequired.keys)
        skillTypeMap = await UniverseCache.shared.types(ids: skillIds)

        // Fill in any names not captured during the walk
        let missingNames = skillIds.filter { acc.names[$0] == nil }
        if !missingNames.isEmpty {
            let resolved = await NameResolver.shared.resolve(ids: missingNames)
            for (id, name) in resolved { acc.names[id] = name }
        }

        prerequisites = acc.maxRequired.map { skillId, required in
            PrereqEntry(
                skillId: skillId,
                name: acc.names[skillId] ?? skillTypeMap[skillId]?.name ?? "Skill #\(skillId)",
                required: required,
                trained: characterSkills?[skillId] ?? 0
            )
        }.sorted { $0.name < $1.name }
    }

    private func walkPrereqs(attrs: [ESIDogmaAttribute], acc: PrereqAccumulator) async {
        for (skillAttr, levelAttr) in prereqAttrPairs {
            guard let skillVal = attrs.first(where: { $0.attributeId == skillAttr }),
                  skillVal.value > 0,
                  let levelVal = attrs.first(where: { $0.attributeId == levelAttr }),
                  levelVal.value > 0 else { continue }

            let skillId = Int(skillVal.value)
            let reqLevel = Int(levelVal.value)

            // Keep the highest required level if this skill appears on multiple paths
            acc.maxRequired[skillId] = max(acc.maxRequired[skillId] ?? 0, reqLevel)

            guard !acc.visited.contains(skillId) else { continue }
            acc.visited.insert(skillId)

            // Recurse into the skill's own prerequisites
            if let skillType = await UniverseCache.shared.type(id: skillId) {
                acc.names[skillId] = skillType.name
                if let subAttrs = skillType.dogmaAttributes {
                    await walkPrereqs(attrs: subAttrs, acc: acc)
                }
            }
        }
    }

    // MARK: SP & Time Calculations

    private func spNeeded(_ entry: PrereqEntry) -> Int {
        guard entry.trained < entry.required else { return 0 }
        let rank = skillRank(entry.skillId)
        return (spThresholds[entry.required] ?? 0) * rank
             - (spThresholds[entry.trained]   ?? 0) * rank
    }

    private func trainingTime(_ entry: PrereqEntry, attrs: ESICharacterAttributes) -> Double {
        let sp = Double(spNeeded(entry))
        guard sp > 0, let type = skillTypeMap[entry.skillId] else { return 0 }
        let dogma = type.dogmaAttributes ?? []
        let primaryId   = dogma.first(where: { $0.attributeId == 180 }).map { Int($0.value) } ?? 165
        let secondaryId = dogma.first(where: { $0.attributeId == 181 }).map { Int($0.value) } ?? 166
        let spPerMin = Double(charAttr(attrs, id: primaryId)) + Double(charAttr(attrs, id: secondaryId)) * 0.5
        guard spPerMin > 0 else { return 0 }
        return sp / spPerMin * 60.0
    }

    private func skillRank(_ typeId: Int) -> Int {
        guard let attr = skillTypeMap[typeId]?.dogmaAttributes?.first(where: { $0.attributeId == 275 }) else { return 1 }
        return max(1, Int(attr.value))
    }

    private func charAttr(_ attrs: ESICharacterAttributes, id: Int) -> Int {
        switch id {
        case 164: return attrs.charisma
        case 165: return attrs.intelligence
        case 166: return attrs.memory
        case 167: return attrs.perception
        case 168: return attrs.willpower
        default:  return attrs.intelligence
        }
    }

    // MARK: Visual Helpers

    private func levelBadge(_ level: Int, dimmed: Bool = false) -> some View {
        let color = levelColor(level)
        return Text("L\(level)")
            .font(.caption2.bold())
            .foregroundStyle(dimmed ? color.opacity(0.5) : color)
            .padding(.horizontal, 5).padding(.vertical, 1)
            .background((dimmed ? color.opacity(0.05) : color.opacity(0.15)), in: Capsule())
    }

    private func levelColor(_ level: Int) -> Color {
        switch level {
        case 1:  return .gray
        case 2:  return .blue
        case 3:  return .green
        case 4:  return .purple
        case 5:  return .orange
        default: return .secondary
        }
    }

    private func formatSP(_ sp: Int) -> String {
        if sp >= 1_000_000 { return String(format: "%.1fM SP", Double(sp) / 1_000_000) }
        if sp >= 1_000    { return String(format: "%.0fK SP", Double(sp) / 1_000) }
        return "\(sp) SP"
    }

    private func formatDuration(_ seconds: Double) -> String {
        let total = Int(max(seconds, 0))
        if total == 0 { return "<1m" }
        let days    = total / 86400
        let hours   = (total % 86400) / 3600
        let minutes = (total % 3600) / 60
        if days  > 0 { return "\(days)d \(hours)h \(minutes)m" }
        if hours > 0 { return "\(hours)h \(minutes)m" }
        return "\(minutes)m"
    }

}
