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

extension TrainingOverviewView {
    // MARK:  Known Skills Section

    var collapsedSkillCharacters: Set<Int> {
        Set(collapsedSkillCharactersRaw.split(separator: ",").compactMap { Int($0) })
    }

    func toggleSkillExpansion(for characterID: Int) {
        var set = collapsedSkillCharacters
        if set.contains(characterID) {
            set.remove(characterID)
        } else {
            set.insert(characterID)
        }
        collapsedSkillCharactersRaw = set.map(String.init).joined(separator: ",")
    }

    var collapsedSkillGroups: Set<String> {
        Set(collapsedSkillGroupsRaw.split(separator: ",").map(String.init))
    }

    func toggleSkillGroupExpansion(_ key: String) {
        var set = collapsedSkillGroups
        if set.contains(key) {
            set.remove(key)
        } else {
            set.insert(key)
        }
        collapsedSkillGroupsRaw = set.sorted().joined(separator: ",")
    }

    func setAllSkillGroups(_ info: CharacterTrainingInfo, collapsed: Bool) {
        var set = collapsedSkillGroups
        for group in info.skillGroups {
            let key = "\(info.characterID)-\(group.groupId)"
            if collapsed {
                set.insert(key)
            } else {
                set.remove(key)
            }
        }
        collapsedSkillGroupsRaw = set.sorted().joined(separator: ",")
    }

    func knownSkillsSection(_ info: CharacterTrainingInfo) -> some View {
        let isSearching = !skillSearchText.trimmingCharacters(in: .whitespaces).isEmpty
        let isExpanded = isSearching || !collapsedSkillCharacters.contains(info.characterID)
        let displayGroups = filteredSkillGroups(info.skillGroups)
        let matchedCount = displayGroups.reduce(0) { $0 + $1.skills.count }

        return VStack(alignment: .leading, spacing: 0) {
            Button {
                if !isSearching {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        toggleSkillExpansion(for: info.characterID)
                    }
                }
            } label: {
                HStack {
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(width: 16)
                    Image(systemName: "book.closed.fill")
                        .foregroundStyle(.blue)
                    if isSearching {
                        Text("Known Skills (\(matchedCount) of \(info.knownSkillCount))")
                            .font(.subheadline.bold())
                    } else {
                        Text("Known Skills (\(info.knownSkillCount))")
                            .font(.subheadline.bold())
                    }
                    Spacer()
                    Text("\(info.totalSP.formatted()) SP")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                .padding(12)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if isExpanded {
                Divider().padding(.horizontal, 12)

                if displayGroups.isEmpty {
                    Text("No skills match \"\(skillSearchText)\"")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(12)
                } else {
                    if !isSearching && displayGroups.count > 1 {
                        HStack(spacing: 12) {
                            Spacer()
                            Button("Expand All") {
                                withAnimation(.easeInOut(duration: 0.2)) {
                                    setAllSkillGroups(info, collapsed: false)
                                }
                            }
                            Button("Collapse All") {
                                withAnimation(.easeInOut(duration: 0.2)) {
                                    setAllSkillGroups(info, collapsed: true)
                                }
                            }
                        }
                        .font(.caption)
                        .buttonStyle(.plain)
                        .foregroundStyle(.blue)
                        .padding(.horizontal, 12)
                        .padding(.top, 8)
                    }

                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(displayGroups.sorted(by: { $0.groupName < $1.groupName }), id: \.groupName) { group in
                            skillGroupSection(group, characterID: info.characterID)
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.bottom, 12)
                }
            }
        }
    }

    func skillGroupSection(_ group: KnownSkillGroup, characterID: Int) -> some View {
        let groupSP = group.skills.reduce(0) { $0 + $1.skillpoints }
        let maxedCount = group.skills.filter { $0.trainedLevel == 5 }.count
        let isSearching = !skillSearchText.trimmingCharacters(in: .whitespaces).isEmpty
        let key = "\(characterID)-\(group.groupId)"
        let isExpanded = isSearching || !collapsedSkillGroups.contains(key)

        return VStack(alignment: .leading, spacing: 0) {
            // Group header
            Button {
                if !isSearching {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        toggleSkillGroupExpansion(key)
                    }
                }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .frame(width: 12)
                    Text(group.groupName)
                        .font(.caption.bold())
                        .foregroundStyle(.primary)
                    Text("\(group.skills.count) skills")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                    if maxedCount > 0 {
                        Text("\(maxedCount) maxed")
                            .font(.caption2)
                            .foregroundStyle(.orange)
                    }
                    Spacer()
                    Text("\(groupSP.formatted()) SP")
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 6)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            // Skills in group
            if isExpanded {
                ForEach(group.skills.sorted(by: { $0.name < $1.name }), id: \.skillId) { skill in
                    skillRow(skill, groupName: group.groupName)
                }
            }
        }
    }

    func skillRow(_ skill: KnownSkill, groupName: String) -> some View {
        Button {
            selectedSkill = SkillSelection(
                skillId: skill.skillId,
                skillName: skill.name,
                groupName: groupName,
                knownSkill: skill,
                queueEntry: nil
            )
        } label: {
        HStack(spacing: 8) {
            CachedAsyncImage(url: EVEImageURL.typeIcon(skill.skillId, size: 256)) { phase in
                if let image = phase.image {
                    image.resizable()
                        .frame(width: 24, height: 24)
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                } else {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(.quaternary)
                        .frame(width: 24, height: 24)
                }
            }

            Text(skill.name)
                .font(.caption)
                .lineLimit(1)

            Spacer()

            // Level pips
            HStack(spacing: 2) {
                ForEach(1...5, id: \.self) { level in
                    RoundedRectangle(cornerRadius: 2)
                        .fill(pipColor(trained: skill.trainedLevel, active: skill.activeLevel, pip: level))
                        .frame(width: 14, height: 12)
                        .overlay(
                            RoundedRectangle(cornerRadius: 2)
                                .strokeBorder(
                                    level <= skill.trainedLevel ? .clear : .white.opacity(0.1),
                                    lineWidth: 1
                                )
                        )
                }
            }

            // Active vs trained indicator
            if skill.activeLevel < skill.trainedLevel {
                Text("\(skill.activeLevel)/\(skill.trainedLevel)")
                    .font(.caption2.bold().monospacedDigit())
                    .foregroundStyle(.yellow)
                    .frame(width: 28)
            } else {
                Text("L\(skill.trainedLevel)")
                    .font(.caption2.bold().monospacedDigit())
                    .foregroundStyle(levelColor(skill.trainedLevel))
                    .frame(width: 28)
            }

            Text("\(skill.skillpoints.formatted()) SP")
                .font(.caption2.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: 80, alignment: .trailing)
        }
        .padding(.vertical, 2)
        }
        .buttonStyle(.plain)
    }

    // MARK:  Selection Helpers

    func skillSelection(for entry: TrainingQueueEntry, in info: CharacterTrainingInfo) -> SkillSelection {
        let known = info.skillGroups.flatMap(\.skills).first { $0.skillId == entry.skillId }
        let group = info.skillGroups.first(where: { $0.skills.contains(where: { $0.skillId == entry.skillId }) })?.groupName ?? ""
        return SkillSelection(skillId: entry.skillId, skillName: entry.skillName, groupName: group, knownSkill: known, queueEntry: entry)
    }

    func pipColor(trained: Int, active: Int, pip: Int) -> Color {
        if pip <= active {
            return levelColor(trained)
        } else if pip <= trained {
            return levelColor(trained).opacity(0.35)
        }
        return Color.white.opacity(0.05)
    }

}
