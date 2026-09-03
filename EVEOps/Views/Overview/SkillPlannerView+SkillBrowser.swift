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
import OSLog

extension SkillPlannerView {
    // MARK: Skill Browser

    func browserTab(_ title: String, icon: String, mode: BrowserMode) -> some View {
        Button { browserMode = mode } label: {
            Label(title, systemImage: icon)
                .font(.caption.bold())
                .frame(maxWidth: .infinity)
                .padding(.vertical, 5)
                .contentShape(Rectangle())
                .background(
                    browserMode == mode ? Color.primary.opacity(0.12) : Color.clear,
                    in: RoundedRectangle(cornerRadius: 6)
                )
        }
        .buttonStyle(.plain)
        .foregroundStyle(browserMode == mode ? AnyShapeStyle(.primary) : AnyShapeStyle(.secondary))
        .animation(.easeInOut(duration: 0.15), value: browserMode)
    }

    var skillBrowser: some View {
        VStack(spacing: 0) {
            HStack(spacing: 2) {
                browserTab("Skills",       icon: "list.bullet", mode: .skills)
                browserTab("Item Tree",    icon: "network",     mode: .tree)
                browserTab("Intelligence", icon: "scope",       mode: .shipGoal)
            }
            .padding(3)
            .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
            .padding(.horizontal, 12)
            .padding(.top, 10)
            .padding(.bottom, 8)

            Divider()

            if browserMode == .tree {
                ItemSkillTreeView(
                    characterSkills: characterSkillMap.isEmpty ? nil : characterSkillMap,
                    onAddToPlan: addPlanItem
                )
            } else if browserMode == .shipGoal {
                ShipGoalBrowserView(
                    characterSkills: characterSkillMap.isEmpty ? nil : characterSkillMap,
                    characterAttributes: attributes,
                    onAddToPlan: addPlanItem
                )
            } else {
                skillBrowserContent
            }
        }
    }

    var skillBrowserContent: some View {
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

    func groupPill(id: Int?, name: String, count: Int) -> some View {
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

    func skillRow(_ skill: KnownSkill) -> some View {
        let planned = planItems.first { $0.skillId == skill.skillId }
        let isMaxed = skill.trainedLevel == 5

        return HStack(spacing: 10) {
            CachedAsyncImage(url: EVEImageURL.typeIcon(skill.skillId, size: 64)) { phase in
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
                        .foregroundStyle(Color.accentColor)
                    Button {
                        planItems.removeAll { $0.skillId == skill.skillId }
                        savePlan()
                    } label: {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(Color.accentColor)
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
                        .foregroundStyle(Color.accentColor)
                }
                .menuStyle(.button)
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    // MARK:  Filtering

    func filteredGroups(_ info: CharacterTrainingInfo) -> [KnownSkillGroup] {
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

}
