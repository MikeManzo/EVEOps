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
import OSLog

extension TrainingOverviewView {
    // MARK:  Helpers

    func levelBadge(_ level: Int) -> some View {
        Text("L\(level)")
            .font(.caption2.bold())
            .foregroundStyle(levelColor(level))
            .padding(.horizontal, 5)
            .padding(.vertical, 1)
            .background(levelColor(level).opacity(0.15), in: Capsule())
    }

    func levelColor(_ level: Int) -> Color {
        switch level {
        case 1: return .gray
        case 2: return .blue
        case 3: return .green
        case 4: return .purple
        case 5: return .orange
        default: return .secondary
        }
    }

    func formatDuration(_ interval: TimeInterval) -> String {
        let total = Int(max(interval, 0))
        let days = total / 86400
        let hours = (total % 86400) / 3600
        let minutes = (total % 3600) / 60
        let seconds = total % 60
        if days > 0 { return "\(days)d \(hours)h \(minutes)m" }
        if hours > 0 { return "\(hours)h \(minutes)m \(seconds)s" }
        if minutes > 0 { return "\(minutes)m \(seconds)s" }
        return "\(seconds)s"
    }

    func timeUntil(_ date: Date) -> String {
        let interval = date.timeIntervalSince(now)
        if interval <= 0 { return "Done" }
        let total = Int(interval)
        let days = total / 86400
        let hours = (total % 86400) / 3600
        let minutes = (total % 3600) / 60
        let seconds = total % 60
        if days > 0 {
            return "\(days)d \(hours)h \(minutes)m \(seconds)s"
        } else if hours > 0 {
            return "\(hours)h \(minutes)m \(seconds)s"
        } else if minutes > 0 {
            return "\(minutes)m \(seconds)s"
        }
        return "\(seconds)s"
    }

    func estimateCurrentSP(_ entry: TrainingQueueEntry) -> Int {
        guard let start = entry.startDate, let finish = entry.finishDate,
              let startSP = entry.trainingStartSP, let endSP = entry.levelEndSP else {
            return entry.levelStartSP ?? 0
        }
        let totalDuration = finish.timeIntervalSince(start)
        guard totalDuration > 0 else { return startSP }
        let elapsed = now.timeIntervalSince(start)
        let fraction = min(max(elapsed / totalDuration, 0), 1)
        return startSP + Int(Double(endSP - startSP) * fraction)
    }

    func formatSP(_ sp: Int) -> String {
        if sp >= 1_000_000 {
            return String(format: "%.1fM", Double(sp) / 1_000_000)
        } else if sp >= 1_000 {
            return String(format: "%.0fK", Double(sp) / 1_000)
        }
        return "\(sp)"
    }

    func filteredSkillGroups(_ groups: [KnownSkillGroup]) -> [KnownSkillGroup] {
        let query = skillSearchText.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return groups }
        let lower = query.lowercased()
        return groups.compactMap { group in
            if group.groupName.lowercased().contains(lower) {
                return group
            }
            let matched = group.skills.filter { $0.name.lowercased().contains(lower) }
            guard !matched.isEmpty else { return nil }
            return KnownSkillGroup(groupId: group.groupId, groupName: group.groupName, skills: matched)
        }
    }

    func exportSkillsToCSV() async {
        guard !isExportingSkills else { return }
        isExportingSkills = true
        defer { isExportingSkills = false }

        // Resolve every known skill's type so we can list its training attributes.
        // These are already warm in the universe cache from the view's own load.
        let allSkillIds = trainingData.flatMap { info in
            info.skillGroups.flatMap { $0.skills.map(\.skillId) }
        }
        let types = await UniverseCache.shared.types(ids: allSkillIds)

        let panel = NSSavePanel()
        panel.title = "Export Known Skills"
        let baseName = trainingData.count == 1
            ? trainingData[0].characterName.replacingOccurrences(of: " ", with: "_")
            : "eve_skills"
        panel.nameFieldStringValue = "\(baseName)_skills.csv"
        panel.allowedContentTypes = [UTType.commaSeparatedText]
        guard panel.runModal() == .OK, let url = panel.url else { return }

        var lines = ["Character,Group,Skill Name,Trained Level,Active Level,Skillpoints,Primary Attribute,Secondary Attribute"]
        for info in trainingData {
            for group in info.skillGroups.sorted(by: { $0.groupName < $1.groupName }) {
                for skill in group.skills.sorted(by: { $0.name < $1.name }) {
                    let char = info.characterName.replacingOccurrences(of: "\"", with: "\"\"")
                    let grp = group.groupName.replacingOccurrences(of: "\"", with: "\"\"")
                    let sName = skill.name.replacingOccurrences(of: "\"", with: "\"\"")
                    let dogma = types[skill.skillId]?.dogmaAttributes ?? []
                    let primary = dogma.first { $0.attributeId == 180 }.map { Int($0.value) }.map(trainingAttrName) ?? ""
                    let secondary = dogma.first { $0.attributeId == 181 }.map { Int($0.value) }.map(trainingAttrName) ?? ""
                    lines.append("\"\(char)\",\"\(grp)\",\"\(sName)\",\(skill.trainedLevel),\(skill.activeLevel),\(skill.skillpoints),\(primary),\(secondary)")
                }
            }
        }
        try? lines.joined(separator: "\n").write(to: url, atomically: true, encoding: .utf8)
    }

    // MARK:  Export the full EVE skill catalog

    /// Human-readable name for a skill's training dogma attribute (dogma IDs 164–168).
    private func trainingAttrName(_ id: Int) -> String {
        switch id {
        case 164: return "Charisma"
        case 165: return "Intelligence"
        case 166: return "Memory"
        case 167: return "Perception"
        case 168: return "Willpower"
        default:  return ""
        }
    }

    /// Exports every published skill in EVE — not just the selected character's known
    /// skills — resolved from the Skills category (16) via the universe cache.
    func exportAllSkillsToCSV() async {
        guard !isExportingAllSkills else { return }
        isExportingAllSkills = true
        defer { isExportingAllSkills = false }

        // 1. Skills category → skill group IDs.
        guard let skillCategory = await UniverseCache.shared.category(id: 16) else {
            Logger.universe.error("[AllSkillsExport] could not load category 16")
            return
        }
        let groups = await UniverseCache.shared.groups(ids: Set(skillCategory.groups))

        // 2. Every type ID across the published skill groups.
        let publishedGroups = groups.values.filter { $0.published }
        let allTypeIds = publishedGroups.flatMap(\.types)
        let types = await UniverseCache.shared.types(ids: allTypeIds)

        // 3. Build one row per published skill, sorted by group then skill name.
        struct Row { let group: String; let name: String; let typeId: Int; let rank: Int; let primary: String; let secondary: String; let spToV: Int }
        var rows: [Row] = []
        for group in publishedGroups.sorted(by: { $0.name < $1.name }) {
            let skills = group.types
                .compactMap { types[$0] }
                .filter { $0.published }
                .sorted { $0.name < $1.name }
            for skill in skills {
                let dogma = skill.dogmaAttributes ?? []
                let rank = dogma.first { $0.attributeId == 275 }.map { Int($0.value) } ?? 1
                let primaryId = dogma.first { $0.attributeId == 180 }.map { Int($0.value) }
                let secondaryId = dogma.first { $0.attributeId == 181 }.map { Int($0.value) }
                rows.append(Row(
                    group: group.name,
                    name: skill.name,
                    typeId: skill.typeId,
                    rank: rank,
                    primary: primaryId.map(trainingAttrName) ?? "",
                    secondary: secondaryId.map(trainingAttrName) ?? "",
                    spToV: rank * 256_000
                ))
            }
        }

        guard !rows.isEmpty else {
            Logger.universe.error("[AllSkillsExport] resolved 0 skills")
            return
        }

        // 4. Save panel + write.
        let panel = NSSavePanel()
        panel.title = "Export All Skills"
        panel.nameFieldStringValue = "eve_all_skills.csv"
        panel.allowedContentTypes = [UTType.commaSeparatedText]
        guard panel.runModal() == .OK, let url = panel.url else { return }

        func esc(_ s: String) -> String { "\"\(s.replacingOccurrences(of: "\"", with: "\"\""))\"" }
        var lines = ["Group,Skill Name,Type ID,Rank,Primary Attribute,Secondary Attribute,SP to Level 5"]
        for r in rows {
            lines.append("\(esc(r.group)),\(esc(r.name)),\(r.typeId),\(r.rank),\(r.primary),\(r.secondary),\(r.spToV)")
        }
        try? lines.joined(separator: "\n").write(to: url, atomically: true, encoding: .utf8)
        Logger.universe.info("[AllSkillsExport] wrote \(rows.count) skills to \(url.lastPathComponent)")
    }

}
