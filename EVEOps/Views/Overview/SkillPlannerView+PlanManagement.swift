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
    // MARK:  Plan Management

    func addToPlan(skill: KnownSkill, targetLevel: Int) {
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

    func addPlanItem(_ item: SkillPlanItem) {
        planItems.removeAll { $0.skillId == item.skillId }
        planItems.append(item)
        savePlan()
        Task {
            let types = await UniverseCache.shared.types(ids: [item.skillId])
            skillTypes.merge(types) { _, new in new }
        }
    }

    func updateItem(_ item: SkillPlanItem, targetLevel: Int) {
        guard let idx = planItems.firstIndex(where: { $0.skillId == item.skillId }) else { return }
        planItems[idx] = SkillPlanItem(
            skillId: item.skillId,
            skillName: item.skillName,
            fromLevel: item.fromLevel,
            targetLevel: targetLevel
        )
        savePlan()
    }

    var clipboardHelpPopover: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Clipboard Import / Export")
                .font(.headline)

            VStack(alignment: .leading, spacing: 6) {
                Label("Export", systemImage: "square.and.arrow.up")
                    .font(.subheadline.bold())
                Text("Copies your plan as plain text — one skill per line:")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("Navigation 5\nSpaceship Command 4\nDrones 3")
                    .font(.caption.monospaced())
                    .padding(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(.quaternary, in: RoundedRectangle(cornerRadius: 6))
            }

            VStack(alignment: .leading, spacing: 6) {
                Label("Import", systemImage: "square.and.arrow.down")
                    .font(.subheadline.bold())
                Text("Reads the same format from your clipboard and adds skills to this plan.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Divider()

            VStack(alignment: .leading, spacing: 4) {
                Label("Add to EVE Queue", systemImage: "gamecontroller")
                    .font(.subheadline.bold())
                Text("Export your plan, switch to EVE, then open the skill queue and choose:")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("☰  →  Add skills listed in clipboard to end of queue")
                    .font(.caption.bold())
                    .padding(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(.quaternary, in: RoundedRectangle(cornerRadius: 6))
            }
        }
        .padding(16)
        .frame(width: 300)
    }

    func exportPlan() {
        let text = planItems.map { "\($0.skillName) \($0.targetLevel)" }.joined(separator: "\n")
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    func importFromClipboard() async {
        guard let text = NSPasteboard.general.string(forType: .string) else { return }

        var parsed: [(name: String, level: Int)] = []
        for line in text.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty else { continue }
            let parts = trimmed.components(separatedBy: " ")
            guard parts.count >= 2, let level = Int(parts.last!), (1...5).contains(level) else { continue }
            let name = parts.dropLast().joined(separator: " ").trimmingCharacters(in: .whitespaces)
            guard !name.isEmpty else { continue }
            parsed.append((name: name, level: level))
        }
        guard !parsed.isEmpty else { return }

        isImporting = true

        let allSkills = selectedCharInfo?.skillGroups.flatMap(\.skills) ?? []
        var newItems: [SkillPlanItem] = []
        var unknownEntries: [(name: String, level: Int)] = []

        for entry in parsed {
            if let match = allSkills.first(where: { $0.name.lowercased() == entry.name.lowercased() }) {
                guard entry.level > match.trainedLevel else { continue }
                newItems.append(SkillPlanItem(
                    skillId: match.skillId, skillName: match.name,
                    fromLevel: match.trainedLevel, targetLevel: entry.level
                ))
            } else {
                unknownEntries.append(entry)
            }
        }

        if !unknownEntries.isEmpty {
            let names = unknownEntries.map { $0.name }
            if let result: ESIIDsResponse = try? await ESIClient.shared.post("/universe/ids/", body: names),
               let types = result.inventoryTypes {
                let typeMap = Dictionary(types.map { ($0.name.lowercased(), $0) }, uniquingKeysWith: { a, _ in a })
                for entry in unknownEntries {
                    if let type = typeMap[entry.name.lowercased()] {
                        newItems.append(SkillPlanItem(
                            skillId: type.id, skillName: type.name,
                            fromLevel: 0, targetLevel: entry.level
                        ))
                    }
                }
            }
        }

        isImporting = false

        guard !newItems.isEmpty else {
            importMessage = "No matching skills found"
            try? await Task.sleep(for: .seconds(2))
            importMessage = nil
            return
        }

        for item in newItems {
            planItems.removeAll { $0.skillId == item.skillId }
            planItems.append(item)
        }
        savePlan()

        let resolvedTypes = await UniverseCache.shared.types(ids: newItems.map(\.skillId))
        skillTypes.merge(resolvedTypes) { _, new in new }

        let count = newItems.count
        importMessage = "\(count) skill\(count == 1 ? "" : "s") imported"
        try? await Task.sleep(for: .seconds(2))
        importMessage = nil
    }

}
