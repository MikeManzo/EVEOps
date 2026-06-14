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

struct TrainingOverviewView: View {
    @Environment(AccountManager.self) private var accountManager
    @Environment(DashboardPrefetcher.self) private var prefetcher
    @AppStorage("backgroundPollInterval") private var pollInterval: Double = 300
    @State private var trainingData: [CharacterTrainingInfo] = []
    @State private var isLoading = false
    @State private var error: String?
    @State private var now = Date()
    @AppStorage("collapsedSkillCharacters") private var collapsedSkillCharactersRaw: String = ""
    @State private var selectedSkill: SkillSelection?
    @State private var skillSearchText: String = ""

    private struct SkillSelection: Equatable {
        let skillId: Int
        let skillName: String
        let groupName: String
        let knownSkill: KnownSkill?
        let queueEntry: TrainingQueueEntry?

        static func == (lhs: SkillSelection, rhs: SkillSelection) -> Bool {
            lhs.skillId == rhs.skillId && lhs.queueEntry?.position == rhs.queueEntry?.position
        }
    }

    var body: some View {
        LoadingStateView(isLoading: isLoading, error: error, isEmpty: trainingData.isEmpty, emptyMessage: "No training data") {
            HStack(spacing: 0) {
                ScrollView {
                    VStack(spacing: 20) {
                        aggregateSummary

                        ForEach(trainingData, id: \.characterID) { info in
                            characterTrainingCard(info)
                        }
                    }
                    .padding()
                }

                if let skill = selectedSkill {
                    Divider()
                    SkillDetailView(
                        skillId: skill.skillId,
                        skillName: skill.skillName,
                        groupName: skill.groupName,
                        knownSkill: skill.knownSkill,
                        queueEntry: skill.queueEntry
                    )
                    .frame(width: 320)
                }
            }
        }
        .safeAreaInset(edge: .top, spacing: 0) {
            VStack(spacing: 0) {
                HStack {
                    Text("Training Overview")
                        .font(.largeTitle.bold())
                    Spacer()
                }
                .padding(.horizontal, 16)
                .padding(.top, 12)
                .padding(.bottom, 8)

                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.secondary)
                    TextField("Search known skills...", text: $skillSearchText)
                        .textFieldStyle(.plain)
                    if !skillSearchText.isEmpty {
                        Button {
                            skillSearchText = ""
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                    if !trainingData.isEmpty {
                        Divider()
                            .frame(height: 16)
                        Button(action: exportSkillsToCSV) {
                            Label("Export CSV", systemImage: "square.and.arrow.up")
                                .font(.caption)
                        }
                        .buttonStyle(.borderless)
                    }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
                .padding(.horizontal, 16)
                .padding(.bottom, 8)

                Divider()
            }
            .background(.background)
        }
        .navigationTitle("")
        .task(id: accountManager.selectedCharacterID) {
            trainingData = []
            selectedSkill = nil
            if buildFromPrefetcher() { return }
            isLoading = true
            await loadTraining()
        }
        .task(id: "timer") {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                now = Date()
            }
        }
        .task(id: pollInterval) {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(pollInterval))
                await loadTraining()
            }
        }
    }

    // MARK:  Aggregate Summary

    private var aggregateSummary: some View {
        let totalSP = trainingData.reduce(0) { $0 + $1.totalSP }
        let totalUnallocated = trainingData.reduce(0) { $0 + $1.unallocatedSP }
        let totalSkills = trainingData.reduce(0) { $0 + $1.knownSkillCount }
        let emptyQueues = trainingData.filter(\.queueEmpty).count
        let activeQueues = trainingData.count - emptyQueues
        let totalQueuedSkills = trainingData.reduce(0) { $0 + $1.queue.count }

        return HStack(spacing: 0) {
            summaryTile(icon: "brain.head.profile.fill", color: .cyan,
                        label: "Total SP", value: formatSP(totalSP))
            Divider().frame(height: 36)
            summaryTile(icon: "tray.full.fill", color: .purple,
                        label: "Unallocated", value: formatSP(totalUnallocated))
            Divider().frame(height: 36)
            summaryTile(icon: "book.closed.fill", color: .blue,
                        label: "Known Skills", value: "\(totalSkills)")
            Divider().frame(height: 36)
            summaryTile(icon: "play.circle.fill", color: .green,
                        label: "Active Queues", value: "\(activeQueues) / \(trainingData.count)")
            Divider().frame(height: 36)
            summaryTile(icon: "list.number", color: .teal,
                        label: "Queued Skills", value: "\(totalQueuedSkills)")
            if emptyQueues > 0 {
                Divider().frame(height: 36)
                summaryTile(icon: "exclamationmark.triangle.fill", color: .orange,
                            label: "Empty Queues", value: "\(emptyQueues)")
            }
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 12)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
    }

    private func summaryTile(icon: String, color: Color, label: String, value: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .foregroundStyle(color)
                .font(.callout)
            VStack(alignment: .leading, spacing: 1) {
                Text(label)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Text(value)
                    .font(.caption.bold())
            }
        }
        .frame(maxWidth: .infinity)
    }

    // MARK:  Character Training Card

    private func characterTrainingCard(_ info: CharacterTrainingInfo) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            // Character header
            characterHeader(info)
                .padding(12)

            if !info.queue.isEmpty {
                Divider().padding(.horizontal, 12)

                if let current = info.queue.first(where: \.isCurrentlyTraining) {
                    currentlyTrainingSection(current, info: info)
                        .padding(12)
                    Divider().padding(.horizontal, 12)
                }

                let queuedOnly = info.queue.filter { !$0.isCurrentlyTraining }
                if !queuedOnly.isEmpty {
                    queueList(queuedOnly, info: info)
                        .padding(12)
                }
            }

            // Known Skills section
            Divider().padding(.horizontal, 12)
            knownSkillsSection(info)
        }
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
    }

    private func characterHeader(_ info: CharacterTrainingInfo) -> some View {
        HStack(spacing: 12) {
            AsyncImage(url: EVEImageURL.characterPortrait(info.characterID, size: 256)) { image in
                image.resizable()
            } placeholder: {
                RoundedRectangle(cornerRadius: 8).fill(.quaternary)
            }
            .frame(width: 48, height: 48)
            .clipShape(RoundedRectangle(cornerRadius: 8))

            VStack(alignment: .leading, spacing: 3) {
                Text(info.characterName)
                    .font(.headline)
                HStack(spacing: 16) {
                    Label("\(info.totalSP.formatted()) SP", systemImage: "brain.head.profile.fill")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                    if info.unallocatedSP > 0 {
                        Label("\(info.unallocatedSP.formatted()) unallocated", systemImage: "tray.full.fill")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.purple)
                    }
                    Label("\(info.knownSkillCount) skills", systemImage: "book.closed.fill")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                HStack(spacing: 8) {
                    ForEach(1...5, id: \.self) { level in
                        let count = info.skillsByLevel[level] ?? 0
                        HStack(spacing: 2) {
                            Text("L\(level)")
                                .font(.caption2.bold())
                                .foregroundStyle(levelColor(level))
                            Text("\(count)")
                                .font(.caption2.monospacedDigit())
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                if let jumpDate = info.lastCloneJumpDate,
                   Date().timeIntervalSince(jumpDate) < 86400 {
                    Label("Clone jump \(timeUntil(jumpDate)) ago — times refreshed", systemImage: "person.2.badge.gearshape.fill")
                        .font(.caption2)
                        .foregroundStyle(.yellow)
                }
            }

            Spacer()

            if info.queueEmpty {
                Label("Training Queue Empty!", systemImage: "exclamationmark.triangle.fill")
                    .font(.caption.bold())
                    .foregroundStyle(.orange)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(.orange.opacity(0.15), in: Capsule())
            } else {
                VStack(alignment: .trailing, spacing: 2) {
                    Text("\(info.queue.count) in queue")
                        .font(.caption.bold())
                        .foregroundStyle(.green)
                    if let end = info.queueEndDate {
                        Text("Ends: \(timeUntil(end))")
                            .font(.caption2.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    // MARK:  Currently Training

    private func currentlyTrainingSection(_ entry: TrainingQueueEntry, info: CharacterTrainingInfo) -> some View {
        Button {
            selectedSkill = skillSelection(for: entry, in: info)
        } label: {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "play.circle.fill")
                    .foregroundStyle(.green)
                Text("Currently Training")
                    .font(.subheadline.bold())
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }

            HStack(spacing: 12) {
                AsyncImage(url: EVEImageURL.typeIcon(entry.skillId, size: 256)) { phase in
                    if let image = phase.image {
                        image.resizable()
                            .frame(width: 40, height: 40)
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                    } else {
                        RoundedRectangle(cornerRadius: 6)
                            .fill(.quaternary)
                            .frame(width: 40, height: 40)
                    }
                }

                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(entry.skillName)
                            .font(.body.bold())
                        levelBadge(entry.level)
                        Spacer()
                        if let finish = entry.finishDate {
                            Text(timeUntil(finish))
                                .font(.subheadline.bold().monospacedDigit())
                                .foregroundStyle(.green)
                        }
                    }

                    if let startSP = entry.levelStartSP, let endSP = entry.levelEndSP {
                        let currentSP = estimateCurrentSP(entry)
                        let progress = endSP > startSP ? Double(currentSP - startSP) / Double(endSP - startSP) : 0

                        VStack(alignment: .leading, spacing: 2) {
                            ProgressView(value: min(max(progress, 0), 1))
                                .tint(.green)
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
                    }

                    HStack(spacing: 16) {
                        if let start = entry.startDate {
                            VStack(alignment: .leading, spacing: 1) {
                                Text("Started")
                                    .font(.caption2)
                                    .foregroundStyle(.tertiary)
                                Text(EVEFormatters.dateFormatter.string(from: start))
                                    .font(.caption2.monospacedDigit())
                                    .foregroundStyle(.secondary)
                            }
                        }
                        if let finish = entry.finishDate {
                            VStack(alignment: .leading, spacing: 1) {
                                Text("Finishes")
                                    .font(.caption2)
                                    .foregroundStyle(.tertiary)
                                Text(EVEFormatters.dateFormatter.string(from: finish))
                                    .font(.caption2.monospacedDigit())
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
        }
        }
        .buttonStyle(.plain)
    }

    // MARK:  Queue List

    private func queueList(_ queue: [TrainingQueueEntry], info: CharacterTrainingInfo) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Skill Queue (\(queue.count))")
                .font(.subheadline.bold())
                .foregroundStyle(.secondary)

            ForEach(queue, id: \.position) { entry in
                Button {
                    selectedSkill = skillSelection(for: entry, in: info)
                } label: {
                HStack(spacing: 8) {
                    Text("\(entry.position + 1)")
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.tertiary)
                        .frame(width: 20, alignment: .trailing)

                    if entry.isCurrentlyTraining {
                        Image(systemName: "play.circle.fill")
                            .foregroundStyle(.green)
                            .font(.caption)
                    } else if entry.finishDate != nil {
                        Image(systemName: "clock.fill")
                            .foregroundStyle(.blue)
                            .font(.caption)
                    } else {
                        Image(systemName: "pause.circle")
                            .foregroundStyle(.secondary)
                            .font(.caption)
                    }

                    AsyncImage(url: EVEImageURL.typeIcon(entry.skillId, size: 256)) { phase in
                        if let image = phase.image {
                            image.resizable()
                                .frame(width: 20, height: 20)
                                .clipShape(RoundedRectangle(cornerRadius: 3))
                        } else {
                            RoundedRectangle(cornerRadius: 3)
                                .fill(.quaternary)
                                .frame(width: 20, height: 20)
                        }
                    }

                    Text(entry.skillName)
                        .font(.caption)
                        .lineLimit(1)

                    levelBadge(entry.level)

                    Spacer()

                    if let startSP = entry.levelStartSP, let endSP = entry.levelEndSP {
                        Text("\((endSP - startSP).formatted()) SP")
                            .font(.caption2.monospacedDigit())
                            .foregroundStyle(.tertiary)
                    }

                    if let finish = entry.finishDate {
                        // Show discrete training duration (finish - start), not cumulative time from now
                        let display: String = {
                            if entry.isCurrentlyTraining { return timeUntil(finish) }
                            if let start = entry.startDate { return formatDuration(finish.timeIntervalSince(start)) }
                            return timeUntil(finish)
                        }()
                        Text(display)
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(entry.isCurrentlyTraining ? .green : .secondary)
                    }
                }
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK:  Known Skills Section

    private var collapsedSkillCharacters: Set<Int> {
        Set(collapsedSkillCharactersRaw.split(separator: ",").compactMap { Int($0) })
    }

    private func toggleSkillExpansion(for characterID: Int) {
        var set = collapsedSkillCharacters
        if set.contains(characterID) {
            set.remove(characterID)
        } else {
            set.insert(characterID)
        }
        collapsedSkillCharactersRaw = set.map(String.init).joined(separator: ",")
    }

    private func knownSkillsSection(_ info: CharacterTrainingInfo) -> some View {
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
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(displayGroups.sorted(by: { $0.groupName < $1.groupName }), id: \.groupName) { group in
                            skillGroupSection(group)
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.bottom, 12)
                }
            }
        }
    }

    private func skillGroupSection(_ group: KnownSkillGroup) -> some View {
        let groupSP = group.skills.reduce(0) { $0 + $1.skillpoints }
        let maxedCount = group.skills.filter { $0.trainedLevel == 5 }.count

        return VStack(alignment: .leading, spacing: 0) {
            // Group header
            HStack(spacing: 8) {
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

            // Skills in group
            ForEach(group.skills.sorted(by: { $0.name < $1.name }), id: \.skillId) { skill in
                skillRow(skill, groupName: group.groupName)
            }
        }
    }

    private func skillRow(_ skill: KnownSkill, groupName: String) -> some View {
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
            AsyncImage(url: EVEImageURL.typeIcon(skill.skillId, size: 256)) { phase in
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

    private func skillSelection(for entry: TrainingQueueEntry, in info: CharacterTrainingInfo) -> SkillSelection {
        let known = info.skillGroups.flatMap(\.skills).first { $0.skillId == entry.skillId }
        let group = info.skillGroups.first(where: { $0.skills.contains(where: { $0.skillId == entry.skillId }) })?.groupName ?? ""
        return SkillSelection(skillId: entry.skillId, skillName: entry.skillName, groupName: group, knownSkill: known, queueEntry: entry)
    }

    private func pipColor(trained: Int, active: Int, pip: Int) -> Color {
        if pip <= active {
            return levelColor(trained)
        } else if pip <= trained {
            return levelColor(trained).opacity(0.35)
        }
        return Color.white.opacity(0.05)
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

    private func formatDuration(_ interval: TimeInterval) -> String {
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

    private func timeUntil(_ date: Date) -> String {
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

    private func formatSP(_ sp: Int) -> String {
        if sp >= 1_000_000 {
            return String(format: "%.1fM", Double(sp) / 1_000_000)
        } else if sp >= 1_000 {
            return String(format: "%.0fK", Double(sp) / 1_000)
        }
        return "\(sp)"
    }

    private func filteredSkillGroups(_ groups: [KnownSkillGroup]) -> [KnownSkillGroup] {
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

    private func exportSkillsToCSV() {
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

    // MARK:  Prefetcher Fast Path

    private func buildFromPrefetcher() -> Bool {
        var data: [CharacterTrainingInfo] = []
        for account in [accountManager.selectedAccount].compactMap({ $0 }) {
            guard let prefetched = prefetcher.data(for: account.characterID) else { return false }
            let skills = prefetched.skills
            let queue = prefetched.skillQueue.sorted { $0.queuePosition < $1.queuePosition }

            // Build queue entries using pre-resolved names
            var resolvedQueue: [TrainingQueueEntry] = []
            for entry in queue {
                let name = prefetcher.resolvedNames[entry.skillId] ?? "Skill #\(entry.skillId)"
                let isTraining = entry.startDate != nil && entry.finishDate != nil &&
                    (entry.startDate! <= Date()) && (entry.finishDate! > Date())
                resolvedQueue.append(TrainingQueueEntry(
                    position: entry.queuePosition,
                    skillId: entry.skillId,
                    skillName: name,
                    level: entry.finishedLevel,
                    startDate: entry.startDate,
                    finishDate: entry.finishDate,
                    levelStartSP: entry.levelStartSp,
                    levelEndSP: entry.levelEndSp,
                    trainingStartSP: entry.trainingStartSp,
                    isCurrentlyTraining: isTraining
                ))
            }
            let activeQueue = resolvedQueue.filter { ($0.finishDate ?? .distantPast) > Date() }

            // Skill level breakdown
            var byLevel: [Int: Int] = [:]
            for skill in skills.skills {
                byLevel[skill.trainedSkillLevel, default: 0] += 1
            }

            // Build known skill groups using pre-resolved types and groups
            var groupedSkills: [Int: [KnownSkill]] = [:]
            for skill in skills.skills {
                let name = prefetcher.resolvedNames[skill.skillId] ?? "Skill #\(skill.skillId)"
                let knownSkill = KnownSkill(
                    skillId: skill.skillId,
                    name: name,
                    trainedLevel: skill.trainedSkillLevel,
                    activeLevel: skill.activeSkillLevel,
                    skillpoints: skill.skillpointsInSkill
                )
                let gid = prefetcher.resolvedTypes[skill.skillId]?.groupId ?? 0
                groupedSkills[gid, default: []].append(knownSkill)
            }

            let skillGroups = groupedSkills.map { gid, skills in
                KnownSkillGroup(
                    groupId: gid,
                    groupName: prefetcher.resolvedGroups[gid]?.name ?? "Unknown Group",
                    skills: skills
                )
            }

            data.append(CharacterTrainingInfo(
                characterID: account.characterID,
                characterName: account.characterName,
                totalSP: skills.totalSp,
                unallocatedSP: skills.unallocatedSp ?? 0,
                knownSkillCount: skills.skills.count,
                skillsByLevel: byLevel,
                queue: activeQueue,
                queueEmpty: activeQueue.isEmpty,
                queueEndDate: activeQueue.last?.finishDate,
                skillGroups: skillGroups,
                lastCloneJumpDate: prefetched.clones?.lastCloneJumpDate
            ))
        }
        trainingData = data
        if selectedSkill == nil, let firstInfo = data.first, let firstEntry = firstInfo.queue.first {
            selectedSkill = skillSelection(for: firstEntry, in: firstInfo)
        }
        return !data.isEmpty
    }

    // MARK:  Data Loading

    private func loadTraining() async {
        isLoading = true
        error = nil
        var data: [CharacterTrainingInfo] = []
        var lastError: Error?
        for account in [accountManager.selectedAccount].compactMap({ $0 }) {
            do {
                let token = try await accountManager.validToken(for: account)

                // Fetch clone status first to detect recent clone jumps.
                // A jump changes training speed, so stale cached queue times can appear 2x off.
                let clones: ESIClonesResponse? = try? await ESIClient.shared.fetch(
                    "/characters/\(account.characterID)/clones/", token: token
                )
                let lastCloneJump = clones?.lastCloneJumpDate
                // If the character jumped clones within the last 24 hours, bypass the queue cache
                // so we get the updated finish dates reflecting the new clone's training speed.
                let bypassQueueCache = lastCloneJump.map { Date().timeIntervalSince($0) < 86400 } ?? false

                async let fetchSkills: ESISkillsResponse = ESIClient.shared.fetch(
                    "/characters/\(account.characterID)/skills/", token: token
                )
                async let fetchQueue: [ESISkillQueue] = ESIClient.shared.fetch(
                    "/characters/\(account.characterID)/skillqueue/", token: token,
                    bypassCache: bypassQueueCache
                )

                let (skills, queue) = try await (fetchSkills, fetchQueue)
                let sortedQueue = queue.sorted { $0.queuePosition < $1.queuePosition }

                // Batch resolve ALL skill names (queue + known)
                let allSkillIDs = Array(Set(
                    sortedQueue.map(\.skillId) + skills.skills.map(\.skillId)
                ))
                let resolvedNames = await NameResolver.shared.resolve(ids: allSkillIDs)

                // Build queue entries
                var resolvedQueue: [TrainingQueueEntry] = []
                for entry in sortedQueue {
                    let name = resolvedNames[entry.skillId] ?? "Skill #\(entry.skillId)"
                    let isTraining = entry.startDate != nil && entry.finishDate != nil &&
                        (entry.startDate! <= Date()) && (entry.finishDate! > Date())
                    resolvedQueue.append(TrainingQueueEntry(
                        position: entry.queuePosition,
                        skillId: entry.skillId,
                        skillName: name,
                        level: entry.finishedLevel,
                        startDate: entry.startDate,
                        finishDate: entry.finishDate,
                        levelStartSP: entry.levelStartSp,
                        levelEndSP: entry.levelEndSp,
                        trainingStartSP: entry.trainingStartSp,
                        isCurrentlyTraining: isTraining
                    ))
                }

                let activeQueue = resolvedQueue.filter { ($0.finishDate ?? .distantPast) > Date() }

                // Build skill level breakdown
                var byLevel: [Int: Int] = [:]
                for skill in skills.skills {
                    byLevel[skill.trainedSkillLevel, default: 0] += 1
                }

                // Batch-fetch type info via UniverseCache (persistent disk cache)
                let typeIDs = Array(Set(skills.skills.map(\.skillId)))
                let fetchedTypes = await UniverseCache.shared.types(ids: typeIDs)

                var groupIdForSkill: [Int: Int] = [:]
                var uniqueGroupIDs: Set<Int> = []
                for (typeID, typeInfo) in fetchedTypes {
                    groupIdForSkill[typeID] = typeInfo.groupId
                    uniqueGroupIDs.insert(typeInfo.groupId)
                }

                // Batch-fetch group names via UniverseCache
                let fetchedGroups = await UniverseCache.shared.groups(ids: uniqueGroupIDs)

                var groupNames: [Int: String] = [:]
                for (gid, groupInfo) in fetchedGroups {
                    groupNames[gid] = groupInfo.name
                }

                // Build known skill groups
                var groupedSkills: [Int: [KnownSkill]] = [:]
                for skill in skills.skills {
                    let name = resolvedNames[skill.skillId] ?? "Skill #\(skill.skillId)"
                    let knownSkill = KnownSkill(
                        skillId: skill.skillId,
                        name: name,
                        trainedLevel: skill.trainedSkillLevel,
                        activeLevel: skill.activeSkillLevel,
                        skillpoints: skill.skillpointsInSkill
                    )
                    let gid = groupIdForSkill[skill.skillId] ?? 0
                    groupedSkills[gid, default: []].append(knownSkill)
                }

                let skillGroups = groupedSkills.map { gid, skills in
                    KnownSkillGroup(
                        groupId: gid,
                        groupName: groupNames[gid] ?? "Unknown Group",
                        skills: skills
                    )
                }

                data.append(CharacterTrainingInfo(
                    characterID: account.characterID,
                    characterName: account.characterName,
                    totalSP: skills.totalSp,
                    unallocatedSP: skills.unallocatedSp ?? 0,
                    knownSkillCount: skills.skills.count,
                    skillsByLevel: byLevel,
                    queue: activeQueue,
                    queueEmpty: activeQueue.isEmpty,
                    queueEndDate: activeQueue.last?.finishDate,
                    skillGroups: skillGroups,
                    lastCloneJumpDate: lastCloneJump
                ))
            } catch {
                lastError = error
            }
        }
        trainingData = data
        if selectedSkill == nil, let firstInfo = data.first, let firstEntry = firstInfo.queue.first {
            selectedSkill = skillSelection(for: firstEntry, in: firstInfo)
        }
        if data.isEmpty, let lastError {
            self.error = lastError.localizedDescription
        }
        isLoading = false
    }
}

// MARK:  Data Models

struct CharacterTrainingInfo {
    let characterID: Int
    let characterName: String
    let totalSP: Int
    let unallocatedSP: Int
    let knownSkillCount: Int
    let skillsByLevel: [Int: Int]
    let queue: [TrainingQueueEntry]
    let queueEmpty: Bool
    let queueEndDate: Date?
    var skillGroups: [KnownSkillGroup] = []
    let lastCloneJumpDate: Date?
}

struct TrainingQueueEntry {
    let position: Int
    let skillId: Int
    let skillName: String
    let level: Int
    let startDate: Date?
    let finishDate: Date?
    let levelStartSP: Int?
    let levelEndSP: Int?
    let trainingStartSP: Int?
    let isCurrentlyTraining: Bool
}

struct KnownSkillGroup {
    let groupId: Int
    let groupName: String
    let skills: [KnownSkill]
}

struct KnownSkill {
    let skillId: Int
    let name: String
    let trainedLevel: Int
    let activeLevel: Int
    let skillpoints: Int
}
