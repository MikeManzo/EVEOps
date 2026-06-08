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

struct SkillDetailView: View {
    let skillId: Int
    let skillName: String
    let groupName: String
    let knownSkill: KnownSkill?
    let queueEntry: TrainingQueueEntry?

    @State private var typeInfo: ESIType?
    @State private var now = Date()

    private var trainedLevel: Int { knownSkill?.trainedLevel ?? 0 }
    private var activeLevel: Int { knownSkill?.activeLevel ?? 0 }
    private var skillpoints: Int { knownSkill?.skillpoints ?? 0 }

    // Skill rank from dogma attribute 275 (skillTimeConstant)
    private var skillRank: Int? {
        typeInfo?.dogmaAttributes?.first(where: { $0.attributeId == 275 }).map { Int($0.value) }
    }

    // Cumulative SP required to reach each level (multiplied by rank)
    private let spBase = [250, 1414, 8000, 45255, 256000]

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                headerSection

                VStack(alignment: .leading, spacing: 16) {
                    if let entry = queueEntry {
                        trainingStatusSection(entry)
                        Divider()
                    }

                    levelsSection
                    Divider()
                    skillInfoSection
                }
                .padding()
            }
        }
        .frame(minWidth: 280, idealWidth: 320)
        .task(id: skillId) { await loadTypeInfo() }
        .task(id: "timer") {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                now = Date()
            }
        }
    }

    // MARK:  Header

    private var headerSection: some View {
        ZStack(alignment: .bottom) {
            Rectangle()
                .fill(Color(white: 0.08))
                .frame(height: 180)
                .overlay {
                    AsyncImage(url: EVEImageURL.typeIcon(skillId, size: 256)) { phase in
                        if let image = phase.image {
                            image.resizable()
                                .interpolation(.high)
                                .frame(width: 120, height: 120)
                        } else {
                            Image(systemName: "book.closed.fill")
                                .font(.system(size: 48))
                                .foregroundStyle(.quaternary)
                        }
                    }
                }

            VStack(alignment: .leading, spacing: 2) {
                Text(skillName)
                    .font(.headline)
                    .foregroundStyle(.white)
                Text(groupName)
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.7))
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .background(.ultraThinMaterial.opacity(0.9))
        }
    }

    // MARK:  Training Status

    private func trainingStatusSection(_ entry: TrainingQueueEntry) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: entry.isCurrentlyTraining ? "play.circle.fill" : "clock.fill")
                    .foregroundStyle(entry.isCurrentlyTraining ? .green : .blue)
                Text(entry.isCurrentlyTraining ? "Currently Training" : "In Queue (#\(entry.position + 1))")
                    .font(.subheadline.bold())
                Spacer()
                levelBadge(entry.level)
            }

            if let startSP = entry.levelStartSP, let endSP = entry.levelEndSP {
                let currentSP = estimateCurrentSP(entry)
                let progress = endSP > startSP ? Double(currentSP - startSP) / Double(endSP - startSP) : 0

                ProgressView(value: min(max(progress, 0), 1))
                    .tint(entry.isCurrentlyTraining ? .green : .blue)

                HStack {
                    Text("\(currentSP.formatted()) / \(endSP.formatted()) SP")
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text("\(Int(progress * 100))%")
                        .font(.caption2.bold().monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }

            HStack(spacing: 16) {
                if let start = entry.startDate {
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Started")
                            .font(.caption2).foregroundStyle(.tertiary)
                        Text(EVEFormatters.dateFormatter.string(from: start))
                            .font(.caption2.monospacedDigit()).foregroundStyle(.secondary)
                    }
                }
                if let finish = entry.finishDate {
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Finishes")
                            .font(.caption2).foregroundStyle(.tertiary)
                        Text(EVEFormatters.dateFormatter.string(from: finish))
                            .font(.caption2.monospacedDigit()).foregroundStyle(.secondary)
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 1) {
                        Text("Remaining")
                            .font(.caption2).foregroundStyle(.tertiary)
                        Text(timeUntil(finish))
                            .font(.caption2.bold().monospacedDigit())
                            .foregroundStyle(entry.isCurrentlyTraining ? .green : .blue)
                    }
                }
            }
        }
    }

    // MARK:  Levels

    private var levelsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Skill Levels")
                    .font(.subheadline.bold())
                    .foregroundStyle(.secondary)
                Spacer()
                if skillpoints > 0 {
                    Text("\(skillpoints.formatted()) SP trained")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }

            ForEach(1...5, id: \.self) { level in
                levelRow(level)
            }
        }
    }

    private func levelRow(_ level: Int) -> some View {
        let isTrained = level <= trainedLevel
        let isActive = level <= activeLevel
        let isTargetLevel = queueEntry?.level == level
        let spRequired = skillRank.map { spBase[level - 1] * $0 }

        return HStack(spacing: 8) {
            levelBadge(level)
                .opacity(isTrained || isTargetLevel ? 1.0 : 0.35)

            // 5 mini pips representing levels up to this level
            HStack(spacing: 2) {
                ForEach(1...5, id: \.self) { pip in
                    RoundedRectangle(cornerRadius: 1.5)
                        .fill(pipFill(pip: pip, forLevel: level, trained: trainedLevel,
                                     active: activeLevel, targetLevel: queueEntry?.level))
                        .frame(width: 10, height: 8)
                }
            }

            if let sp = spRequired {
                Text(formatSP(sp))
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.tertiary)
            }

            Spacer()

            if isTrained && !isActive {
                Text("Inactive")
                    .font(.caption2.bold())
                    .foregroundStyle(.yellow)
            } else if isTrained {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                    .font(.caption)
            } else if isTargetLevel, let finish = queueEntry?.finishDate {
                Label(timeUntil(finish), systemImage: queueEntry?.isCurrentlyTraining == true ? "play.circle.fill" : "clock")
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(queueEntry?.isCurrentlyTraining == true ? .green : .blue)
                    .lineLimit(1)
            }
        }
        .padding(.vertical, 2)
    }

    private func pipFill(pip: Int, forLevel level: Int, trained: Int, active: Int, targetLevel: Int?) -> Color {
        guard pip == level else {
            // Only fill the pip matching this level row's level
            return Color.white.opacity(0.05)
        }
        if level <= active {
            return levelColor(level)
        } else if level <= trained {
            return levelColor(level).opacity(0.4) // trained but inactive
        } else if level == targetLevel {
            return (queueEntry?.isCurrentlyTraining == true ? Color.green : Color.blue).opacity(0.5)
        }
        return Color.white.opacity(0.05)
    }

    // MARK:  Skill Info

    private var skillInfoSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Skill Information")
                .font(.subheadline.bold())
                .foregroundStyle(.secondary)

            infoRow(label: "Group", value: groupName)
            infoRow(label: "Type ID", value: "\(skillId)")

            if let rank = skillRank {
                infoRow(label: "Rank", value: "\(rank)×")
            }

            if let attrs = typeInfo?.dogmaAttributes {
                if let primaryVal = attrs.first(where: { $0.attributeId == 180 }).map({ Int($0.value) }),
                   let name = attributeName(primaryVal) {
                    infoRow(label: "Primary Attr", value: name)
                }
                if let secondaryVal = attrs.first(where: { $0.attributeId == 181 }).map({ Int($0.value) }),
                   let name = attributeName(secondaryVal) {
                    infoRow(label: "Secondary Attr", value: name)
                }
            }

            if let desc = typeInfo?.description, !desc.isEmpty {
                Divider()
                Text("Description")
                    .font(.subheadline.bold())
                    .foregroundStyle(.secondary)
                Text(desc.strippingEVEMarkup)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    // MARK:  Helpers

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

    private func infoRow(label: String, value: String) -> some View {
        HStack(alignment: .top) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 110, alignment: .trailing)
            Text(value)
                .font(.caption)
                .textSelection(.enabled)
            Spacer()
        }
    }

    private func attributeName(_ id: Int) -> String? {
        switch id {
        case 164: return "Intelligence"
        case 165: return "Charisma"
        case 166: return "Memory"
        case 167: return "Perception"
        case 168: return "Willpower"
        default: return nil
        }
    }

    private func formatSP(_ sp: Int) -> String {
        if sp >= 1_000_000 {
            return String(format: "%.1fM SP", Double(sp) / 1_000_000)
        } else if sp >= 1_000 {
            return String(format: "%.0fK SP", Double(sp) / 1_000)
        }
        return "\(sp) SP"
    }

    private func timeUntil(_ date: Date) -> String {
        let interval = date.timeIntervalSince(now)
        if interval <= 0 { return "Done" }
        let total = Int(interval)
        let days = total / 86400
        let hours = (total % 86400) / 3600
        let minutes = (total % 3600) / 60
        let seconds = total % 60
        if days > 0 { return "\(days)d \(hours)h \(minutes)m" }
        if hours > 0 { return "\(hours)h \(minutes)m \(seconds)s" }
        if minutes > 0 { return "\(minutes)m \(seconds)s" }
        return "\(seconds)s"
    }

    private func estimateCurrentSP(_ entry: TrainingQueueEntry) -> Int {
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

    // MARK:  Data Loading

    private func loadTypeInfo() async {
        typeInfo = try? await ESIClient.shared.fetch("/universe/types/\(skillId)/")
    }
}
