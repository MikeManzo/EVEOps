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

    func exportSkillsToCSV() {
        let panel = NSSavePanel()
        panel.title = "Export Known Skills"
        let baseName = trainingData.count == 1
            ? trainingData[0].characterName.replacingOccurrences(of: " ", with: "_")
            : "eve_skills"
        panel.nameFieldStringValue = "\(baseName)_skills.csv"
        panel.allowedContentTypes = [UTType.commaSeparatedText]
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            var lines = ["Character,Group,Skill Name,Trained Level,Active Level,Skillpoints"]
            for info in trainingData {
                for group in info.skillGroups.sorted(by: { $0.groupName < $1.groupName }) {
                    for skill in group.skills.sorted(by: { $0.name < $1.name }) {
                        let char = info.characterName.replacingOccurrences(of: "\"", with: "\"\"")
                        let grp = group.groupName.replacingOccurrences(of: "\"", with: "\"\"")
                        let sName = skill.name.replacingOccurrences(of: "\"", with: "\"\"")
                        lines.append("\"\(char)\",\"\(grp)\",\"\(sName)\",\(skill.trainedLevel),\(skill.activeLevel),\(skill.skillpoints)")
                    }
                }
            }
            try? lines.joined(separator: "\n").write(to: url, atomically: true, encoding: .utf8)
        }
    }

}
