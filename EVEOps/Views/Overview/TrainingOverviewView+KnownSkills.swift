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

/// One known skill as a row of the Skills table.
struct KnownSkillRow: Identifiable {
    let skill: KnownSkill
    let groupId: Int
    let group: String

    var id: Int { skill.skillId }
    var name: String { skill.name }
    var level: Int { skill.trainedLevel }
    var skillpoints: Int { skill.skillpoints }
}

extension TrainingOverviewView {
    // MARK:  Skills tab

    /// Every known skill, filtered by the group menu and the search field (which matches
    /// skill or group names).
    func knownSkillRows(_ info: CharacterTrainingInfo) -> [KnownSkillRow] {
        let query = skillSearchText.trimmingCharacters(in: .whitespaces).lowercased()
        return info.skillGroups.flatMap { group -> [KnownSkillRow] in
            if let skillGroupFilter, group.groupId != skillGroupFilter { return [] }
            let groupMatches = query.isEmpty || group.groupName.lowercased().contains(query)
            return group.skills
                .filter { groupMatches || $0.name.lowercased().contains(query) }
                .map { KnownSkillRow(skill: $0, groupId: group.groupId, group: group.groupName) }
        }
    }

    func skillGroupMenu(_ info: CharacterTrainingInfo) -> some View {
        let groups = info.skillGroups.sorted { $0.groupName < $1.groupName }
        return Picker("Group", selection: $skillGroupFilter) {
            Text("All Groups").tag(Int?.none)
            Divider()
            ForEach(groups, id: \.groupId) { group in
                Text("\(group.groupName) (\(group.skills.count))").tag(Int?.some(group.groupId))
            }
        }
        .labelsHidden()
        .fixedSize()
        .help("Show one skill group")
    }

    @ViewBuilder
    func skillsTab(_ info: CharacterTrainingInfo) -> some View {
        let rows = knownSkillRows(info).sorted(using: skillSortOrder)
        if rows.isEmpty {
            if skillSearchText.isEmpty {
                EVEEmptyState("No Skills", systemImage: "book.closed")
            } else {
                ContentUnavailableView.search(text: skillSearchText)
            }
        } else {
            Table(rows, selection: $selectedSkillRowID, sortOrder: $skillSortOrder) {
                TableColumn("Skill", value: \.name) { row in
                    HStack(spacing: EVESpacing.md) {
                        CachedAsyncImage(url: EVEImageURL.typeIcon(row.id, size: 64)) { image in
                            image.resizable()
                        } placeholder: {
                            RoundedRectangle(cornerRadius: EVERadius.xs).fill(.quaternary)
                        }
                        .frame(width: 20, height: 20)
                        .clipShape(RoundedRectangle(cornerRadius: EVERadius.xs))
                        Text(row.name)
                            .lineLimit(1)
                            .eveTruncationHelp(row.name)
                    }
                }
                .width(min: 180, ideal: 260)

                TableColumn("Group", value: \.group) { row in
                    Text(row.group)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                .width(min: 100, ideal: 150)

                TableColumn("Level", value: \.level) { row in
                    levelCell(row.skill)
                }
                .width(min: 120, ideal: 130)

                TableColumn("Skill Points", value: \.skillpoints) { row in
                    Text(row.skillpoints.formatted())
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                }
                .width(min: 80, ideal: 100)
            }
            .tableStyle(.inset(alternatesRowBackgrounds: true))
            .contextMenu(forSelectionType: KnownSkillRow.ID.self) { ids in
                if let id = ids.first, let row = rows.first(where: { $0.id == id }) {
                    EVEEntityMenuItems(entity: .item(typeID: row.id, name: row.name))
                }
            }
            .onChange(of: selectedSkillRowID) { _, id in
                guard let id, let row = rows.first(where: { $0.id == id }) else { return }
                selectedSkill = SkillSelection(
                    skillId: row.id,
                    skillName: row.name,
                    groupName: row.group,
                    knownSkill: row.skill,
                    queueEntry: info.queue.first { $0.skillId == row.id }
                )
            }
            .copyable(rows.filter { $0.id == selectedSkillRowID }.map {
                "\($0.name)\t\($0.group)\t\($0.level)\t\($0.skillpoints)"
            })
        }
    }

    /// Five level pips plus the level numeral — or "active/trained" in yellow when an
    /// Alpha clone caps the skill below what's been trained.
    private func levelCell(_ skill: KnownSkill) -> some View {
        HStack(spacing: EVESpacing.sm) {
            HStack(spacing: EVESpacing.xxs) {
                ForEach(1...5, id: \.self) { level in
                    RoundedRectangle(cornerRadius: EVERadius.hairline)
                        .fill(pipColor(trained: skill.trainedLevel, active: skill.activeLevel, pip: level))
                        .frame(width: 12, height: 10)
                        .overlay(
                            RoundedRectangle(cornerRadius: EVERadius.hairline)
                                .strokeBorder(level <= skill.trainedLevel ? .clear : EVEFill.trackBorder, lineWidth: 1)
                        )
                }
            }
            if skill.activeLevel < skill.trainedLevel {
                Text("\(skill.activeLevel)/\(skill.trainedLevel)")
                    .font(.caption.bold().monospacedDigit())
                    .foregroundStyle(.yellow)
                    .help("Alpha clone: level \(skill.activeLevel) active of \(skill.trainedLevel) trained")
            } else {
                Text(Self.roman(skill.trainedLevel))
                    .font(.caption.bold())
                    .foregroundStyle(levelColor(skill.trainedLevel))
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Level \(skill.trainedLevel)"))
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
        return EVEFill.track
    }
}
