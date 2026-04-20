import SwiftUI

struct SkillPlannerView: View {
    @Environment(AccountManager.self) private var accountManager
    @Environment(DashboardPrefetcher.self) private var prefetcher

    @State private var trainingData: [CharacterTrainingInfo] = []
    @State private var selectedCharacterID: Int?
    @State private var attributes: ESICharacterAttributes?
    @State private var planItems: [SkillPlanItem] = []
    @State private var skillTypes: [Int: ESIType] = [:]
    @State private var searchText = ""
    @State private var selectedGroupId: Int?
    @State private var isLoading = false
    @State private var error: String?

    private var selectedCharInfo: CharacterTrainingInfo? {
        let id = selectedCharacterID ?? accountManager.selectedAccount?.characterID ?? 0
        return trainingData.first { $0.characterID == id }
    }

    var body: some View {
        LoadingStateView(isLoading: isLoading, error: error, isEmpty: trainingData.isEmpty, emptyMessage: "No character data") {
            HStack(spacing: 0) {
                planPanel
                    .frame(width: 320)
                    .background(.regularMaterial)
                Divider()
                skillBrowser
            }
        }
        .navigationTitle("Skill Planner")
        .task(id: accountManager.selectedCharacterID) {
            await loadData()
        }
    }

    // MARK: - Plan Panel

    private var planPanel: some View {
        VStack(spacing: 0) {
            if accountManager.accounts.count > 1 {
                characterPicker
                    .padding(10)
                    .background(.bar)
                Divider()
            }

            if let attrs = attributes {
                attributesBar(attrs)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(.bar)
                Divider()
            }

            planSummaryBar
                .padding(10)
            Divider()

            if planItems.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "list.bullet.clipboard")
                        .font(.system(size: 36))
                        .foregroundStyle(.tertiary)
                    Text("No skills planned")
                        .font(.subheadline.bold())
                        .foregroundStyle(.secondary)
                    Text("Browse skills on the right and tap + to add them to your plan.")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 20)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 1) {
                        ForEach(planItems) { item in
                            planRow(item)
                            Divider().padding(.leading, 44)
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
        }
    }

    private var characterPicker: some View {
        Picker("Character", selection: Binding(
            get: { selectedCharacterID ?? accountManager.selectedAccount?.characterID },
            set: { newVal in
                selectedCharacterID = newVal
                planItems = []
                Task {
                    await loadAttributes()
                    loadPlan()
                }
            }
        )) {
            ForEach(accountManager.accounts, id: \.characterID) { account in
                Text(account.characterName).tag(Optional(account.characterID))
            }
        }
        .pickerStyle(.menu)
    }

    private func attributesBar(_ attrs: ESICharacterAttributes) -> some View {
        HStack(spacing: 0) {
            attrTile("INT", value: attrs.intelligence, color: .blue)
            attrTile("MEM", value: attrs.memory, color: .green)
            attrTile("PER", value: attrs.perception, color: .orange)
            attrTile("WIL", value: attrs.willpower, color: .purple)
            attrTile("CHA", value: attrs.charisma, color: .pink)
        }
    }

    private func attrTile(_ label: String, value: Int, color: Color) -> some View {
        VStack(spacing: 1) {
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text("\(value)")
                .font(.caption.bold().monospacedDigit())
                .foregroundStyle(color)
        }
        .frame(maxWidth: .infinity)
    }

    private var planSummaryBar: some View {
        let totalSP = planItems.reduce(0) { $0 + spNeeded(for: $1) }
        let totalSeconds = planItems.reduce(0.0) {
            $0 + (attributes.map { trainingTime(for: $1, attrs: $0) } ?? 0)
        }

        return HStack(spacing: 0) {
            VStack(spacing: 2) {
                Text("Skills")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Text("\(planItems.count)")
                    .font(.title3.bold())
            }
            .frame(maxWidth: .infinity)

            Divider().frame(height: 30)

            VStack(spacing: 2) {
                Text("Total SP")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Text(formatSP(totalSP))
                    .font(.title3.bold().monospacedDigit())
                    .foregroundStyle(.blue)
            }
            .frame(maxWidth: .infinity)

            Divider().frame(height: 30)

            VStack(spacing: 2) {
                Text("Time")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Text(attributes != nil ? formatDuration(totalSeconds) : "—")
                    .font(.title3.bold().monospacedDigit())
                    .foregroundStyle(.green)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
            }
            .frame(maxWidth: .infinity)

            Divider().frame(height: 30)

            Button(role: .destructive) {
                planItems.removeAll()
                savePlan()
            } label: {
                Image(systemName: "trash")
                    .foregroundStyle(planItems.isEmpty ? .tertiary : .red)
            }
            .buttonStyle(.plain)
            .disabled(planItems.isEmpty)
            .frame(width: 36)
        }
    }

    private func planRow(_ item: SkillPlanItem) -> some View {
        let sp = spNeeded(for: item)
        let seconds = attributes.map { trainingTime(for: item, attrs: $0) } ?? 0.0

        return HStack(spacing: 8) {
            AsyncImage(url: EVEImageURL.typeIcon(item.skillId, size: 64)) { phase in
                if let image = phase.image {
                    image.resizable().frame(width: 28, height: 28).clipShape(RoundedRectangle(cornerRadius: 4))
                } else {
                    RoundedRectangle(cornerRadius: 4).fill(.quaternary).frame(width: 28, height: 28)
                }
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(item.skillName)
                    .font(.caption.bold())
                    .lineLimit(1)
                HStack(spacing: 4) {
                    levelBadge(item.fromLevel)
                    Image(systemName: "arrow.right")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    levelBadge(item.targetLevel)
                }
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 2) {
                Text(formatSP(sp))
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)
                if attributes != nil {
                    Text(formatDuration(seconds))
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.green)
                }
            }

            if item.fromLevel < 4 {
                Menu {
                    ForEach((item.targetLevel == 5 ? [] : Array((item.targetLevel + 1)...5)), id: \.self) { level in
                        Button("Extend to L\(level)") { updateItem(item, targetLevel: level) }
                    }
                    Divider()
                    ForEach(Array(((item.fromLevel + 1)...(item.targetLevel - 1)).reversed()), id: \.self) { level in
                        Button("Reduce to L\(level)") { updateItem(item, targetLevel: level) }
                    }
                } label: {
                    Image(systemName: "slider.horizontal.3")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .menuStyle(.button)
                .buttonStyle(.plain)
            }

            Button(role: .destructive) {
                planItems.removeAll { $0.skillId == item.skillId }
                savePlan()
            } label: {
                Image(systemName: "minus.circle.fill")
                    .foregroundStyle(.red)
                    .font(.callout)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
    }

    // MARK: - Skill Browser

    private var skillBrowser: some View {
        VStack(spacing: 0) {
            // Search bar
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("Search skills...", text: $searchText)
                    .textFieldStyle(.plain)
                if !searchText.isEmpty {
                    Button { searchText = "" } label: {
                        Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(8)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
            .padding(10)

            if let info = selectedCharInfo {
                // Group filter pills
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        groupPill(id: nil, name: "All", count: info.skillGroups.reduce(0) { $0 + $1.skills.count })
                        ForEach(info.skillGroups.sorted(by: { $0.groupName < $1.groupName }), id: \.groupId) { group in
                            groupPill(id: group.groupId, name: group.groupName, count: group.skills.count)
                        }
                    }
                    .padding(.horizontal, 10)
                    .padding(.bottom, 8)
                }
                .background(.bar)

                Divider()

                let groups = filteredGroups(info)
                if groups.isEmpty {
                    Text(searchText.isEmpty ? "No skills" : "No results for \"\(searchText)\"")
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 0, pinnedViews: .sectionHeaders) {
                            ForEach(groups, id: \.groupId) { group in
                                Section {
                                    ForEach(group.skills.sorted(by: { $0.name < $1.name }), id: \.skillId) { skill in
                                        skillRow(skill)
                                        Divider().padding(.leading, 46)
                                    }
                                } header: {
                                    HStack {
                                        Text(group.groupName)
                                            .font(.caption.bold())
                                            .foregroundStyle(.secondary)
                                        Spacer()
                                        Text("\(group.skills.count) skills")
                                            .font(.caption2)
                                            .foregroundStyle(.tertiary)
                                    }
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 5)
                                    .frame(maxWidth: .infinity)
                                    .background(.bar)
                                }
                            }
                        }
                    }
                }
            } else {
                Text("No character data loaded")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    private func groupPill(id: Int?, name: String, count: Int) -> some View {
        let isSelected = selectedGroupId == id
        return Button {
            selectedGroupId = id
        } label: {
            HStack(spacing: 4) {
                Text(name)
                    .font(.caption)
                Text("\(count)")
                    .font(.caption2)
                    .opacity(0.7)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(isSelected ? Color.accentColor : Color.secondary.opacity(0.15), in: Capsule())
            .foregroundStyle(isSelected ? .white : .primary)
        }
        .buttonStyle(.plain)
    }

    private func skillRow(_ skill: KnownSkill) -> some View {
        let planned = planItems.first { $0.skillId == skill.skillId }
        let isMaxed = skill.trainedLevel == 5

        return HStack(spacing: 10) {
            AsyncImage(url: EVEImageURL.typeIcon(skill.skillId, size: 64)) { phase in
                if let image = phase.image {
                    image.resizable().frame(width: 32, height: 32).clipShape(RoundedRectangle(cornerRadius: 5))
                } else {
                    RoundedRectangle(cornerRadius: 5).fill(.quaternary).frame(width: 32, height: 32)
                }
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(skill.name)
                    .font(.subheadline)
                    .lineLimit(1)

                HStack(spacing: 2) {
                    ForEach(1...5, id: \.self) { level in
                        RoundedRectangle(cornerRadius: 2)
                            .fill(level <= skill.trainedLevel ? levelColor(skill.trainedLevel) : Color.white.opacity(0.08))
                            .frame(width: 16, height: 10)
                    }
                    Text("L\(skill.trainedLevel)")
                        .font(.caption2.bold())
                        .foregroundStyle(levelColor(skill.trainedLevel))
                        .padding(.leading, 4)
                    Text("• \(formatSP(skill.skillpoints))")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }

            Spacer()

            if let existing = planned {
                HStack(spacing: 6) {
                    Text("→ L\(existing.targetLevel)")
                        .font(.caption.bold())
                        .foregroundStyle(.accentColor)
                    Button {
                        planItems.removeAll { $0.skillId == skill.skillId }
                        savePlan()
                    } label: {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.accentColor)
                            .font(.title3)
                    }
                    .buttonStyle(.plain)
                }
            } else if isMaxed {
                Text("Maxed")
                    .font(.caption2.bold())
                    .foregroundStyle(.orange)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(.orange.opacity(0.12), in: Capsule())
            } else {
                let nextLevel = skill.trainedLevel + 1
                Menu {
                    ForEach(nextLevel...5, id: \.self) { level in
                        Button("Plan to L\(level)") {
                            addToPlan(skill: skill, targetLevel: level)
                        }
                    }
                } label: {
                    Image(systemName: "plus.circle")
                        .font(.title3)
                        .foregroundStyle(.accentColor)
                }
                .menuStyle(.button)
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    // MARK: - Filtering

    private func filteredGroups(_ info: CharacterTrainingInfo) -> [KnownSkillGroup] {
        var groups = info.skillGroups
        if let gid = selectedGroupId {
            groups = groups.filter { $0.groupId == gid }
        }
        if !searchText.isEmpty {
            groups = groups.compactMap { group in
                let matching = group.skills.filter { $0.name.localizedCaseInsensitiveContains(searchText) }
                return matching.isEmpty ? nil : KnownSkillGroup(groupId: group.groupId, groupName: group.groupName, skills: matching)
            }
        }
        return groups.sorted { $0.groupName < $1.groupName }
    }

    // MARK: - Plan Management

    private func addToPlan(skill: KnownSkill, targetLevel: Int) {
        planItems.removeAll { $0.skillId == skill.skillId }
        let item = SkillPlanItem(
            skillId: skill.skillId,
            skillName: skill.name,
            fromLevel: skill.trainedLevel,
            targetLevel: targetLevel
        )
        planItems.append(item)
        savePlan()
        Task {
            let types = await UniverseCache.shared.types(ids: [skill.skillId])
            skillTypes.merge(types) { _, new in new }
        }
    }

    private func updateItem(_ item: SkillPlanItem, targetLevel: Int) {
        guard let idx = planItems.firstIndex(where: { $0.skillId == item.skillId }) else { return }
        planItems[idx] = SkillPlanItem(
            skillId: item.skillId,
            skillName: item.skillName,
            fromLevel: item.fromLevel,
            targetLevel: targetLevel
        )
        savePlan()
    }

    // MARK: - SP & Time Calculations

    // Total SP at each level for rank-1 skills
    private static let spThresholds: [Int: Int] = [
        0: 0, 1: 250, 2: 1414, 3: 8000, 4: 45255, 5: 256000
    ]

    private func spForLevel(_ level: Int, rank: Int) -> Int {
        (Self.spThresholds[level] ?? 0) * rank
    }

    private func spNeeded(for item: SkillPlanItem) -> Int {
        guard item.fromLevel < item.targetLevel else { return 0 }
        let rank = skillRank(for: item.skillId)
        return spForLevel(item.targetLevel, rank: rank) - spForLevel(item.fromLevel, rank: rank)
    }

    private func trainingTime(for item: SkillPlanItem, attrs: ESICharacterAttributes) -> Double {
        let sp = Double(spNeeded(for: item))
        guard sp > 0 else { return 0 }
        let type = skillTypes[item.skillId]
        let (primaryId, secondaryId) = dogmaAttributes(for: type)
        let primary = Double(characterAttr(attrs, dogmaId: primaryId))
        let secondary = Double(characterAttr(attrs, dogmaId: secondaryId))
        let spPerHour = primary + secondary * 0.5
        guard spPerHour > 0 else { return 0 }
        return sp / spPerHour * 3600.0
    }

    private func skillRank(for typeId: Int) -> Int {
        guard let type = skillTypes[typeId],
              let attr = type.dogmaAttributes?.first(where: { $0.attributeId == 275 }) else { return 1 }
        return max(1, Int(attr.value))
    }

    /// Returns (primaryDogmaID, secondaryDogmaID) — values are 164…168
    private func dogmaAttributes(for type: ESIType?) -> (Int, Int) {
        guard let dogma = type?.dogmaAttributes else { return (165, 166) }
        let primary = dogma.first(where: { $0.attributeId == 180 }).map { Int($0.value) } ?? 165
        let secondary = dogma.first(where: { $0.attributeId == 181 }).map { Int($0.value) } ?? 166
        return (primary, secondary)
    }

    /// Maps dogma attribute ID (164-168) → actual character attribute value
    private func characterAttr(_ attrs: ESICharacterAttributes, dogmaId: Int) -> Int {
        switch dogmaId {
        case 164: return attrs.charisma
        case 165: return attrs.intelligence
        case 166: return attrs.memory
        case 167: return attrs.perception
        case 168: return attrs.willpower
        default:  return attrs.intelligence
        }
    }

    // MARK: - Persistence

    private var planKey: String {
        "skillPlan-\(selectedCharacterID ?? accountManager.selectedAccount?.characterID ?? 0)"
    }

    private func savePlan() {
        if let data = try? JSONEncoder().encode(planItems) {
            UserDefaults.standard.set(data, forKey: planKey)
        }
    }

    private func loadPlan() {
        guard let data = UserDefaults.standard.data(forKey: planKey),
              let items = try? JSONDecoder().decode([SkillPlanItem].self, from: data) else { return }
        planItems = items
        let ids = items.map { $0.skillId }
        Task {
            let types = await UniverseCache.shared.types(ids: ids)
            skillTypes.merge(types) { _, new in new }
        }
    }

    // MARK: - Data Loading

    private func loadData() async {
        isLoading = true
        error = nil

        // Try prefetcher first
        var data: [CharacterTrainingInfo] = []
        for account in accountManager.accounts {
            guard let prefetched = prefetcher.data(for: account.characterID) else { continue }
            data.append(buildInfo(from: prefetched, account: account))
        }

        if !data.isEmpty {
            trainingData = data
            if selectedCharacterID == nil {
                selectedCharacterID = accountManager.selectedAccount?.characterID
            }
            await loadAttributes()
            loadPlan()
            isLoading = false
            return
        }

        // Live fetch fallback
        guard let account = accountManager.selectedAccount else { isLoading = false; return }
        do {
            let token = try await accountManager.validToken(for: account)
            async let fetchSkills: ESISkillsResponse = ESIClient.shared.fetch("/characters/\(account.characterID)/skills/", token: token)
            async let fetchQueue: [ESISkillQueue] = ESIClient.shared.fetch("/characters/\(account.characterID)/skillqueue/", token: token)
            let (skills, _) = try await (fetchSkills, fetchQueue)

            let allIDs = Array(Set(skills.skills.map(\.skillId)))
            let resolvedNames = await NameResolver.shared.resolve(ids: allIDs)
            let types = await UniverseCache.shared.types(ids: allIDs)
            let groupIDs = Set(types.values.map(\.groupId))
            let groups = await UniverseCache.shared.groups(ids: groupIDs)

            var groupedSkills: [Int: [KnownSkill]] = [:]
            for skill in skills.skills {
                let name = resolvedNames[skill.skillId] ?? "Skill #\(skill.skillId)"
                let known = KnownSkill(skillId: skill.skillId, name: name, trainedLevel: skill.trainedSkillLevel, activeLevel: skill.activeSkillLevel, skillpoints: skill.skillpointsInSkill)
                let gid = types[skill.skillId]?.groupId ?? 0
                groupedSkills[gid, default: []].append(known)
            }
            let skillGroups = groupedSkills.map { gid, skills in
                KnownSkillGroup(groupId: gid, groupName: groups[gid]?.name ?? "Unknown", skills: skills)
            }
            let info = CharacterTrainingInfo(
                characterID: account.characterID, characterName: account.characterName,
                totalSP: skills.totalSp, unallocatedSP: skills.unallocatedSp ?? 0,
                knownSkillCount: skills.skills.count, skillsByLevel: [:],
                queue: [], queueEmpty: true, queueEndDate: nil,
                skillGroups: skillGroups, lastCloneJumpDate: nil
            )
            trainingData = [info]
            selectedCharacterID = account.characterID
            await loadAttributes()
            loadPlan()
        } catch {
            self.error = error.localizedDescription
        }
        isLoading = false
    }

    private func loadAttributes() async {
        let charID = selectedCharacterID ?? accountManager.selectedAccount?.characterID ?? 0
        guard let account = accountManager.accounts.first(where: { $0.characterID == charID }) else { return }
        do {
            let token = try await accountManager.validToken(for: account)
            let attrs: ESICharacterAttributes = try await ESIClient.shared.fetch(
                "/characters/\(charID)/attributes/", token: token
            )
            self.attributes = attrs
        } catch {
            // Non-critical — time estimates just won't show
        }
    }

    private func buildInfo(from prefetched: DashboardPrefetcher.PrefetchedCharacterData, account: StoredAccount) -> CharacterTrainingInfo {
        var groupedSkills: [Int: [KnownSkill]] = [:]
        for skill in prefetched.skills.skills {
            let name = prefetcher.resolvedNames[skill.skillId] ?? "Skill #\(skill.skillId)"
            let known = KnownSkill(skillId: skill.skillId, name: name, trainedLevel: skill.trainedSkillLevel, activeLevel: skill.activeSkillLevel, skillpoints: skill.skillpointsInSkill)
            let gid = prefetcher.resolvedTypes[skill.skillId]?.groupId ?? 0
            groupedSkills[gid, default: []].append(known)
        }
        let skillGroups = groupedSkills.map { gid, skills in
            KnownSkillGroup(groupId: gid, groupName: prefetcher.resolvedGroups[gid]?.name ?? "Unknown Group", skills: skills)
        }
        return CharacterTrainingInfo(
            characterID: account.characterID, characterName: account.characterName,
            totalSP: prefetched.skills.totalSp, unallocatedSP: prefetched.skills.unallocatedSp ?? 0,
            knownSkillCount: prefetched.skills.skills.count, skillsByLevel: [:],
            queue: [], queueEmpty: true, queueEndDate: nil,
            skillGroups: skillGroups, lastCloneJumpDate: prefetched.clones?.lastCloneJumpDate
        )
    }

    // MARK: - Visual Helpers

    private func levelBadge(_ level: Int) -> some View {
        Text("L\(level)")
            .font(.caption2.bold())
            .foregroundStyle(levelColor(level))
            .padding(.horizontal, 5)
            .padding(.vertical, 1)
            .background(levelColor(level).opacity(0.15), in: Capsule())
    }

    private func levelColor(_ level: Int) -> Color {
        switch level {
        case 1: return .gray
        case 2: return .blue
        case 3: return .green
        case 4: return .purple
        case 5: return .orange
        default: return .secondary
        }
    }

    private func formatSP(_ sp: Int) -> String {
        if sp >= 1_000_000 { return String(format: "%.1fM SP", Double(sp) / 1_000_000) }
        if sp >= 1_000 { return String(format: "%.0fK SP", Double(sp) / 1_000) }
        return "\(sp) SP"
    }

    private func formatDuration(_ seconds: Double) -> String {
        let total = Int(max(seconds, 0))
        if total == 0 { return "<1m" }
        let days = total / 86400
        let hours = (total % 86400) / 3600
        let minutes = (total % 3600) / 60
        if days > 0 { return "\(days)d \(hours)h \(minutes)m" }
        if hours > 0 { return "\(hours)h \(minutes)m" }
        return "\(minutes)m"
    }
}

// MARK: - Data Model

struct SkillPlanItem: Identifiable, Codable, Equatable {
    let skillId: Int
    let skillName: String
    let fromLevel: Int
    var targetLevel: Int

    var id: Int { skillId }
}
