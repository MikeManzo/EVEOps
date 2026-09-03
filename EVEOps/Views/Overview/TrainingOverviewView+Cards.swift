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
    // MARK:  Aggregate Summary

    var aggregateSummary: some View {
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

    func summaryTile(icon: String, color: Color, label: String, value: String) -> some View {
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

    func characterTrainingCard(_ info: CharacterTrainingInfo) -> some View {
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

    func characterHeader(_ info: CharacterTrainingInfo) -> some View {
        HStack(spacing: 12) {
            CachedAsyncImage(url: EVEImageURL.characterPortrait(info.characterID, size: 256)) { image in
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

    func currentlyTrainingSection(_ entry: TrainingQueueEntry, info: CharacterTrainingInfo) -> some View {
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
                CachedAsyncImage(url: EVEImageURL.typeIcon(entry.skillId, size: 256)) { phase in
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
                                Text(progress.formatted(.percent.precision(.fractionLength(0))))
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

    func queueList(_ queue: [TrainingQueueEntry], info: CharacterTrainingInfo) -> some View {
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

                    CachedAsyncImage(url: EVEImageURL.typeIcon(entry.skillId, size: 256)) { phase in
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

}
