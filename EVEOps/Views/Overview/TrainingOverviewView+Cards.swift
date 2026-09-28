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
    // MARK:  Hero

    /// The screen's fixed header: who this is and how their SP is built (left), and what
    /// they're training and how fast (right). Everything answerable at a glance lives
    /// here; the tabs below are for digging in.
    func trainingHero(_ info: CharacterTrainingInfo) -> some View {
        HStack(alignment: .top, spacing: EVESpacing.xl) {
            VStack(alignment: .leading, spacing: EVESpacing.lg) {
                pilotIdentity(info)
                Divider()
                HStack(alignment: .top, spacing: EVESpacing.xl) {
                    VStack(alignment: .leading, spacing: EVESpacing.md) {
                        attributesBlock(info)
                        remapPayoff(info)
                    }
                    .frame(maxWidth: 280, alignment: .leading)
                    Divider()
                    implantsBlock()
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                Divider()
                HStack(alignment: .top, spacing: EVESpacing.xl) {
                    planBlock(info)
                        .frame(maxWidth: 280, alignment: .leading)
                    Divider()
                    milestonesBlock(info)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Divider()

            nowTrainingPanel(info)
                .frame(minWidth: 320, idealWidth: 380, maxWidth: 440, alignment: .leading)
        }
        .padding(EVESpacing.xl)
        .eveElevatedCard()
    }

    // MARK:  Pilot

    private func pilotIdentity(_ info: CharacterTrainingInfo) -> some View {
        let prefetched = prefetcher.characterData[info.characterID]
        let atV = info.skillsByLevel[5] ?? 0
        return HStack(alignment: .top, spacing: EVESpacing.lg) {
            CachedAsyncImage(url: EVEImageURL.characterPortrait(info.characterID, size: 256)) { image in
                image.resizable()
            } placeholder: {
                RoundedRectangle(cornerRadius: EVERadius.lg).fill(.quaternary)
            }
            .frame(width: 72, height: 72)
            .clipShape(RoundedRectangle(cornerRadius: EVERadius.lg))
            .evePortraitRing(cornerRadius: EVERadius.lg, accent: palette.knowledge)
            .eveContextMenu(.character(id: info.characterID, name: info.characterName))

            VStack(alignment: .leading, spacing: EVESpacing.sm) {
                VStack(alignment: .leading, spacing: EVESpacing.xxs) {
                    HStack(spacing: EVESpacing.sm) {
                        Text(info.characterName)
                            .font(.title3.bold())
                            .lineLimit(1)
                        cloneStateBadge(info)
                    }
                    if let prefetched {
                        Text([prefetched.corporationName, prefetched.allianceName].compactMap { $0 }.joined(separator: " · "))
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }

                HStack(alignment: .firstTextBaseline, spacing: EVESpacing.sm) {
                    Text(info.totalSP.formatted())
                        .font(.eveStat)
                        .eveNumeric(info.totalSP)
                    Text("SP")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    if info.unallocatedSP > 0 {
                        EVEChip(Text("+\(formatSP(info.unallocatedSP)) unallocated"), tint: .purple)
                            .help("\(info.unallocatedSP.formatted()) SP not yet applied to a skill")
                    }
                    if atV > 0 {
                        EVEChip(Text("\(atV) at V"), tint: levelColor(5))
                            .help("\(atV) of \(info.knownSkillCount) known skills trained to level V")
                    }
                }

                levelDistribution(info)

                if let jumpDate = info.lastCloneJumpDate,
                   now.timeIntervalSince(jumpDate) < 86400 {
                    Label("Clone jump \(timeUntil(jumpDate)) ago — training times refreshed",
                          systemImage: "person.2.badge.gearshape.fill")
                        .font(.caption)
                        .foregroundStyle(.yellow)
                }
            }
        }
    }

    enum CloneState { case alpha, omega }

    /// ESI doesn't report clone state, so it's inferred: any skill whose active level is
    /// capped below its trained level means Alpha; otherwise the live training rate is
    /// compared with the Omega rate the pilot's attributes predict (Alpha trains at half
    /// speed). Returns nil when neither signal is available.
    func cloneState(_ info: CharacterTrainingInfo) -> CloneState? {
        if info.skillGroups.contains(where: { $0.skills.contains { $0.activeLevel < $0.trainedLevel } }) {
            return .alpha
        }
        guard let actual = currentSPPerHour(info), let expected = expectedOmegaSPPerHour() else { return nil }
        // Alpha runs at half the Omega rate. The live rate is averaged since the entry
        // started, so an attribute change mid-skill (remap, implants) can land it in
        // between — call it only when it's clearly one or the other.
        switch actual / expected {
        case ..<0.6:   return .alpha
        case 0.85...:  return .omega
        default:       return nil
        }
    }

    @ViewBuilder
    private func cloneStateBadge(_ info: CharacterTrainingInfo) -> some View {
        switch cloneState(info) {
        case .alpha:
            EVEChip(Text("Alpha"), tint: .secondary)
                .help("Alpha clone — trains at half speed, some skills capped")
        case .omega:
            EVEChip(Text("Omega"), tint: .yellow)
                .help("Omega clone — full training speed")
        case nil:
            EmptyView()
        }
    }

    /// Known skills by trained level as one stacked bar, with the counts beneath.
    private func levelDistribution(_ info: CharacterTrainingInfo) -> some View {
        let counts = (1...5).map { info.skillsByLevel[$0] ?? 0 }
        let total = max(counts.reduce(0, +), 1)
        return VStack(alignment: .leading, spacing: EVESpacing.xs) {
            GeometryReader { geo in
                HStack(spacing: 1.5) {
                    ForEach(1...5, id: \.self) { level in
                        let count = counts[level - 1]
                        if count > 0 {
                            Rectangle()
                                .fill(levelColor(level).gradient)
                                .frame(width: max(geo.size.width * Double(count) / Double(total) - 1.5, 2))
                                .help("Level \(level): \(count) skills")
                        }
                    }
                }
            }
            .frame(height: 6)
            .clipShape(Capsule())
            .frame(maxWidth: 360)

            HStack(spacing: EVESpacing.md) {
                ForEach(1...5, id: \.self) { level in
                    HStack(spacing: 3) {
                        Circle().fill(levelColor(level)).frame(width: 6, height: 6)
                        Text("\(Self.roman(level)) \(counts[level - 1])")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .accessibilityElement(children: .combine)
        }
    }

    // MARK:  Attributes

    private static let attributeOrder: [(dogmaID: Int, label: LocalizedStringKey, name: String)] = [
        (165, "INT", "Intelligence"), (166, "MEM", "Memory"), (167, "PER", "Perception"),
        (168, "WIL", "Willpower"), (164, "CHA", "Charisma")
    ]

    private func attributeValue(_ attrs: ESICharacterAttributes, _ dogmaID: Int) -> Int {
        switch dogmaID {
        case 164: return attrs.charisma
        case 165: return attrs.intelligence
        case 166: return attrs.memory
        case 167: return attrs.perception
        default:  return attrs.willpower
        }
    }

    /// Five attribute bars, with the current skill's primary and secondary highlighted,
    /// and remap availability beneath.
    @ViewBuilder
    private func attributesBlock(_ info: CharacterTrainingInfo) -> some View {
        VStack(alignment: .leading, spacing: EVESpacing.sm) {
            blockTitle("Attributes")
            if let attrs = attributes {
                let values = Self.attributeOrder.map { attributeValue(attrs, $0.dogmaID) }
                let scale = Double(max(values.max() ?? 1, 32))
                VStack(alignment: .leading, spacing: EVESpacing.xs) {
                    ForEach(Array(Self.attributeOrder.enumerated()), id: \.offset) { index, attr in
                        let isPrimary = currentSkillAttributeIDs.first == attr.dogmaID
                        let isSecondary = currentSkillAttributeIDs.dropFirst().first == attr.dogmaID
                        let highlight = isPrimary || isSecondary
                        HStack(spacing: EVESpacing.sm) {
                            Text(attr.label)
                                .font(.caption.weight(highlight ? .bold : .regular))
                                .foregroundStyle(highlight ? .primary : .secondary)
                                .frame(width: 30, alignment: .leading)
                            Capsule()
                                .fill(EVEFill.track)
                                .frame(height: 5)
                                .overlay(alignment: .leading) {
                                    GeometryReader { geo in
                                        Capsule()
                                            .fill(highlight ? AnyShapeStyle(palette.knowledge.gradient) : AnyShapeStyle(Color.secondary.opacity(0.5)))
                                            .frame(width: geo.size.width * Double(values[index]) / scale)
                                    }
                                }
                            Text("\(values[index])")
                                .font(.caption.monospacedDigit().weight(highlight ? .bold : .regular))
                                .foregroundStyle(highlight ? .primary : .secondary)
                                .frame(width: 22, alignment: .trailing)
                        }
                        .help(isPrimary ? "\(attr.name) — primary for the skill in training"
                              : isSecondary ? "\(attr.name) — secondary for the skill in training"
                              : attr.name)
                    }
                }
                remapLine(attrs)
            } else {
                Text("Loading…")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
    }

    @ViewBuilder
    private func remapLine(_ attrs: ESICharacterAttributes) -> some View {
        let bonus = attrs.bonusRemaps ?? 0
        let next = attrs.accruedRemapCooldownDate
        let available = next.map { $0 <= now } ?? true
        HStack(spacing: EVESpacing.xs) {
            Image(systemName: "arrow.triangle.2.circlepath")
            if available {
                Text("Remap available")
                    .foregroundStyle(.green)
            } else if let next {
                Text("Next remap \(EVEDates.short(next, now: now))")
                    .help(EVEDates.full(next))
            }
            if bonus > 0 {
                Text("· \(bonus) bonus")
            }
        }
        .font(.caption)
        .foregroundStyle(.secondary)
    }

    // MARK:  Group progress

    private struct GroupProgress: Identifiable {
        let id: Int
        let name: String
        let trainedSP: Int
        let maxSP: Int
        let knownCount: Int
        let skillCount: Int
        var fraction: Double { maxSP > 0 ? min(Double(trainedSP) / Double(maxSP), 1) : 0 }
    }

    private func groupProgress(_ info: CharacterTrainingInfo) -> [GroupProgress] {
        let known = Dictionary(info.skillGroups.map { ($0.groupId, $0) }, uniquingKeysWith: { a, _ in a })
        return skillGroupCatalog.map { entry in
            let group = known[entry.id]
            return GroupProgress(
                id: entry.id,
                name: entry.name,
                trainedSP: group?.skills.reduce(0) { $0 + $1.skillpoints } ?? 0,
                maxSP: entry.maxSP,
                knownCount: group?.skills.count ?? 0,
                skillCount: entry.skillCount
            )
        }
        .sorted { $0.fraction == $1.fraction ? $0.name < $1.name : $0.fraction > $1.fraction }
    }

    /// Every skill group's progress toward "all skills at V", most complete first, in two
    /// columns with no scrolling. Clicking a group filters the Skills tab to it.
    @ViewBuilder
    private func groupProgressBlock(_ info: CharacterTrainingInfo) -> some View {
        VStack(alignment: .leading, spacing: EVESpacing.sm) {
            HStack {
                blockTitle("Skill Group Progress")
                Spacer()
                if !skillGroupCatalog.isEmpty {
                    Text("to all V")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            if skillGroupCatalog.isEmpty {
                Text("Loading…")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                // Two columns, every group shown — reads down the first column, then the second.
                let groups = groupProgress(info)
                let half = (groups.count + 1) / 2
                HStack(alignment: .top, spacing: EVESpacing.lg) {
                    VStack(alignment: .leading, spacing: EVESpacing.sm) {
                        ForEach(groups.prefix(half)) { groupProgressRow($0) }
                    }
                    VStack(alignment: .leading, spacing: EVESpacing.sm) {
                        ForEach(groups.dropFirst(half)) { groupProgressRow($0) }
                    }
                }
            }
        }
    }

    private func groupProgressRow(_ group: GroupProgress) -> some View {
        let isFiltered = tab == .skills && skillGroupFilter == group.id
        return Button {
            tab = .skills
            skillGroupFilter = group.id
        } label: {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: EVESpacing.xs) {
                    Text(group.name)
                        .font(.caption.weight(isFiltered ? .semibold : .regular))
                        .foregroundStyle(group.knownCount == 0 ? .secondary : .primary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                    Spacer(minLength: EVESpacing.xs)
                    Text(group.fraction.formatted(.percent.precision(.fractionLength(0))))
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                Capsule()
                    .fill(EVEFill.track)
                    .frame(height: 4)
                    .overlay(alignment: .leading) {
                        GeometryReader { geo in
                            Capsule()
                                .fill(group.fraction >= 1 ? AnyShapeStyle(levelColor(5).gradient) : AnyShapeStyle(palette.knowledge.gradient))
                                .frame(width: max(geo.size.width * group.fraction, group.trainedSP > 0 ? 3 : 0))
                        }
                    }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("\(group.name): \(group.knownCount) of \(group.skillCount) skills known · \(group.trainedSP.formatted()) of \(group.maxSP.formatted()) SP to all V")
    }

    /// Small uppercase caption heading each header block.
    func blockTitle(_ title: LocalizedStringKey) -> some View {
        Text(title)
            .font(.eveMicroBold)
            .textCase(.uppercase)
            .tracking(0.6)
            .foregroundStyle(.secondary)
    }

    // MARK:  Now training

    /// Live SP/hour for the skill in training, from its SP span over its time span.
    func currentSPPerHour(_ info: CharacterTrainingInfo) -> Double? {
        guard let entry = info.queue.first(where: \.isCurrentlyTraining),
              let start = entry.startDate, let finish = entry.finishDate,
              let startSP = entry.trainingStartSP ?? entry.levelStartSP, let endSP = entry.levelEndSP,
              finish > start, endSP > startSP else { return nil }
        return Double(endSP - startSP) / finish.timeIntervalSince(start) * 3600
    }

    /// Omega training rate the pilot's attributes predict for the current skill:
    /// (primary + secondary / 2) SP per minute.
    private func expectedOmegaSPPerHour() -> Double? {
        guard let attrs = attributes, currentSkillAttributeIDs.count == 2 else { return nil }
        let primary = Double(attributeValue(attrs, currentSkillAttributeIDs[0]))
        let secondary = Double(attributeValue(attrs, currentSkillAttributeIDs[1]))
        return (primary + secondary / 2) * 60
    }

    /// SP still to train across the whole queue, counting only the untrained part of
    /// the skill in progress.
    private func queuedSP(_ info: CharacterTrainingInfo) -> Int {
        info.queue.reduce(0) { sum, entry in
            guard let end = entry.levelEndSP else { return sum }
            let from = entry.isCurrentlyTraining
                ? Int(Double(entry.levelStartSP ?? 0) + levelProgress(entry, at: now) * Double(end - (entry.levelStartSP ?? 0)))
                : (entry.levelStartSP ?? end)
            return sum + max(end - from, 0)
        }
    }

    @ViewBuilder
    private func nowTrainingPanel(_ info: CharacterTrainingInfo) -> some View {
        if info.queueEmpty {
            VStack(alignment: .leading, spacing: EVESpacing.lg) {
                HStack(spacing: EVESpacing.lg) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.title)
                        .foregroundStyle(.orange)
                    VStack(alignment: .leading, spacing: EVESpacing.xxs) {
                        Text("Skill queue is empty")
                            .font(.headline)
                        Text("This character isn't training anything.")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                        Button("Open Skill Planner") { AppRouter.shared.pendingSection = .skillPlanner }
                            .buttonStyle(.link)
                            .padding(.top, EVESpacing.xxs)
                    }
                }
                groupProgressBlock(info)
            }
        } else {
            VStack(alignment: .leading, spacing: EVESpacing.lg) {
                if let current = info.queue.first(where: \.isCurrentlyTraining) {
                    Button {
                        selectedSkill = skillSelection(for: current, in: info)
                    } label: {
                        currentSkillView(current)
                    }
                    .buttonStyle(.plain)
                    .eveContextMenu(.item(typeID: current.skillId, name: current.skillName))
                } else {
                    HStack(spacing: EVESpacing.lg) {
                        Image(systemName: "pause.circle.fill")
                            .font(.title)
                            .foregroundStyle(.secondary)
                        VStack(alignment: .leading, spacing: EVESpacing.xxs) {
                            Text("Training paused")
                                .font(.headline)
                            Text("\(info.queue.count) skills queued — resume training in EVE.")
                                .font(.callout)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                trainingStats(info)
                nextUp(info)
                groupProgressBlock(info)
            }
        }
    }

    private func currentSkillView(_ entry: TrainingQueueEntry) -> some View {
        HStack(spacing: EVESpacing.lg) {
            // Only this ring and the countdown beside it tick every second.
            TimelineView(.periodic(from: .now, by: 1)) { context in
                ZStack {
                    Circle()
                        .stroke(EVEFill.track, lineWidth: 5)
                    Circle()
                        .trim(from: 0, to: levelProgress(entry, at: context.date))
                        .stroke(Color.green.gradient, style: StrokeStyle(lineWidth: 5, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                    CachedAsyncImage(url: EVEImageURL.typeIcon(entry.skillId, size: 64)) { image in
                        image.resizable()
                    } placeholder: {
                        Image(systemName: "brain.head.profile").foregroundStyle(.secondary)
                    }
                    .frame(width: 30, height: 30)
                }
            }
            .frame(width: 64, height: 64)
            .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: EVESpacing.xxs) {
                Text("NOW TRAINING")
                    .font(.eveMicroBold)
                    .tracking(0.6)
                    .foregroundStyle(.green)
                Text("\(entry.skillName) \(Self.roman(entry.level))")
                    .font(.headline)
                    .lineLimit(1)
                    .eveTruncationHelp("\(entry.skillName) \(Self.roman(entry.level))")
                if let finish = entry.finishDate {
                    Text(timerInterval: Date.now...max(finish, .now), countsDown: true)
                        .font(.eveStatCompact)
                        .foregroundStyle(.green)
                    Text("Done \(EVEDates.short(finish, now: now))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .help(EVEDates.full(finish))
                }
            }
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }

    /// SP/hour · SP left in queue · queue end, as three compact figures.
    private func trainingStats(_ info: CharacterTrainingInfo) -> some View {
        let endsSoon = info.queueEndDate.map { $0.timeIntervalSince(now) < 86400 } ?? false
        return HStack(spacing: 0) {
            heroStat("SP / Hour") {
                Text(currentSPPerHour(info).map { Int($0.rounded()).formatted() } ?? "—")
            }
            .help(expectedOmegaSPPerHour().map { "Omega rate for this skill: \(Int($0.rounded()).formatted()) SP/h" } ?? "")
            Divider().frame(height: 28)
            heroStat("Queued SP") {
                Text(formatSP(queuedSP(info)))
            }
            Divider().frame(height: 28)
            heroStat("Queue Ends") {
                Text(info.queueEndDate.map { EVEFormatters.timeUntil($0) } ?? "—")
                    .foregroundStyle(endsSoon ? AnyShapeStyle(.orange) : AnyShapeStyle(.primary))
            }
            .help(info.queueEndDate.map { "Queue ends \(EVEDates.full($0))" } ?? "")
        }
        .padding(.vertical, EVESpacing.sm)
        .background(EVEFill.subtle, in: RoundedRectangle(cornerRadius: EVERadius.md))
    }

    private func heroStat<Value: View>(_ label: LocalizedStringKey, @ViewBuilder value: () -> Value) -> some View {
        VStack(spacing: EVESpacing.xxs) {
            value()
                .font(.callout.monospacedDigit().weight(.semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    /// The next two skills after the one in training.
    @ViewBuilder
    private func nextUp(_ info: CharacterTrainingInfo) -> some View {
        let upcoming = info.queue.filter { !$0.isCurrentlyTraining }.prefix(2)
        if !upcoming.isEmpty {
            VStack(alignment: .leading, spacing: EVESpacing.sm) {
                blockTitle("Up Next")
                ForEach(Array(upcoming), id: \.position) { entry in
                    Button {
                        selectedSkill = skillSelection(for: entry, in: info)
                    } label: {
                        HStack(spacing: EVESpacing.sm) {
                            CachedAsyncImage(url: EVEImageURL.typeIcon(entry.skillId, size: 64)) { image in
                                image.resizable()
                            } placeholder: {
                                RoundedRectangle(cornerRadius: EVERadius.xs).fill(.quaternary)
                            }
                            .frame(width: 20, height: 20)
                            .clipShape(RoundedRectangle(cornerRadius: EVERadius.xs))
                            Text("\(entry.skillName) \(Self.roman(entry.level))")
                                .font(.callout)
                                .lineLimit(1)
                            Spacer(minLength: EVESpacing.sm)
                            if let start = entry.startDate, let finish = entry.finishDate {
                                Text(formatDuration(finish.timeIntervalSince(start)))
                                    .font(.caption.monospacedDigit())
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .eveContextMenu(.item(typeID: entry.skillId, name: entry.skillName))
                }
            }
        }
    }

    // MARK:  Loading

    /// Re-run the insight loading when the character or the queue's makeup changes.
    var insightsKey: String {
        let info = trainingData.first
        return "\(info?.characterID ?? 0)-\(info?.queue.map { "\($0.skillId).\($0.level)" }.joined(separator: ",") ?? "")"
    }

    /// Re-run header loading when the character or the skill in training changes.
    var heroDetailsKey: String {
        let info = trainingData.first
        return "\(info?.characterID ?? 0)-\(info?.queue.first(where: \.isCurrentlyTraining)?.skillId ?? 0)"
    }

    /// Published skill groups (category 16) with their skill counts and SP to all V.
    /// Types come from `UniverseCache`, so after the first load this is disk-backed.
    func loadSkillGroupCatalog() async {
        guard skillGroupCatalog.isEmpty,
              let category = await UniverseCache.shared.category(id: 16) else { return }
        let groups = await UniverseCache.shared.groups(ids: Set(category.groups)).values.filter(\.published)
        let types = await UniverseCache.shared.types(ids: groups.flatMap(\.types))
        skillGroupCatalog = groups.map { group in
            let skills = group.types.compactMap { types[$0] }.filter(\.published)
            let maxSP = skills.reduce(0) { sum, skill in
                let rank = skill.dogmaAttributes?.first { $0.attributeId == 275 }.map { Int($0.value) } ?? 1
                return sum + rank * 256_000
            }
            return SkillGroupCatalogEntry(id: group.groupId, name: group.name,
                                          skillCount: skills.count, maxSP: maxSP)
        }
        .filter { $0.skillCount > 0 }
    }

    func loadHeroDetails() async {
        guard let info = trainingData.first,
              let account = accountManager.accounts.first(where: { $0.characterID == info.characterID }) else { return }

        if attributes == nil,
           let token = try? await accountManager.validToken(for: account) {
            attributes = try? await ESIClient.shared.fetch("/characters/\(info.characterID)/attributes/", token: token)
        }

        if let current = info.queue.first(where: \.isCurrentlyTraining),
           let type = await UniverseCache.shared.type(id: current.skillId),
           let dogma = type.dogmaAttributes {
            let primary = dogma.first { $0.attributeId == 180 }.map { Int($0.value) }
            let secondary = dogma.first { $0.attributeId == 181 }.map { Int($0.value) }
            currentSkillAttributeIDs = [primary, secondary].compactMap { $0 }
        } else {
            currentSkillAttributeIDs = []
        }
    }

    // MARK:  Queue tab

    @ViewBuilder
    func queueTab(_ info: CharacterTrainingInfo) -> some View {
        if info.queue.isEmpty {
            EVEEmptyState(title: Text("Nothing Queued"), systemImage: "list.bullet.clipboard",
                          message: Text("Queue skills in EVE, or build a plan in the Skill Planner.")) {
                Button("Open Skill Planner") { AppRouter.shared.pendingSection = .skillPlanner }
            }
        } else {
            ScrollView {
                VStack(alignment: .leading, spacing: EVESpacing.lg) {
                    if info.queue.count > 1 {
                        SkillQueueTimeline(queue: info.queue, tint: palette.knowledge)
                            .padding(EVESpacing.lg)
                            .eveCard()
                    }
                    queueList(info)
                }
                .padding(EVESpacing.xl)
            }
        }
    }

    private func queueList(_ info: CharacterTrainingInfo) -> some View {
        let durations = info.queue.map { queueDuration($0) }
        let longest = max(durations.max() ?? 1, 1)
        return VStack(spacing: 0) {
            ForEach(Array(info.queue.enumerated()), id: \.element.position) { index, entry in
                if index > 0 { Divider().padding(.leading, 76) }
                Button {
                    selectedSkill = skillSelection(for: entry, in: info)
                } label: {
                    queueRow(entry, duration: durations[index], longest: longest)
                }
                .buttonStyle(.plain)
                .eveContextMenu(.item(typeID: entry.skillId, name: entry.skillName))
            }
        }
        .eveCard()
    }

    /// Time this entry takes on its own — the remaining time for the skill in training.
    private func queueDuration(_ entry: TrainingQueueEntry) -> TimeInterval {
        guard let finish = entry.finishDate else { return 0 }
        let start = entry.isCurrentlyTraining ? now : (entry.startDate ?? now)
        return max(finish.timeIntervalSince(start), 0)
    }

    private func queueRow(_ entry: TrainingQueueEntry, duration: TimeInterval, longest: TimeInterval) -> some View {
        let isSelected = selectedSkill?.skillId == entry.skillId && selectedSkill?.queueEntry?.position == entry.position
        return HStack(spacing: EVESpacing.md) {
            Text("\(entry.position + 1)")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.tertiary)
                .frame(width: 22, alignment: .trailing)

            CachedAsyncImage(url: EVEImageURL.typeIcon(entry.skillId, size: 64)) { image in
                image.resizable()
            } placeholder: {
                RoundedRectangle(cornerRadius: EVERadius.xs).fill(.quaternary)
            }
            .frame(width: 28, height: 28)
            .clipShape(RoundedRectangle(cornerRadius: EVERadius.xs))

            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: EVESpacing.sm) {
                    Text("\(entry.skillName) \(Self.roman(entry.level))")
                        .fontWeight(entry.isCurrentlyTraining ? .semibold : .regular)
                        .lineLimit(1)
                        .eveTruncationHelp(entry.skillName)
                    if entry.isCurrentlyTraining {
                        EVEChip(Text("Training"), tint: .green)
                    }
                }
                if let startSP = entry.levelStartSP, let endSP = entry.levelEndSP {
                    Text("+\((endSP - startSP).formatted()) SP")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.tertiary)
                }
            }

            Spacer(minLength: EVESpacing.md)

            // Relative length of this skill against the longest in the queue.
            Capsule()
                .fill(EVEFill.track)
                .frame(width: 96, height: 5)
                .overlay(alignment: .leading) {
                    Capsule()
                        .fill((entry.isCurrentlyTraining ? Color.green : palette.knowledge).gradient)
                        .frame(width: max(96 * duration / longest, 4), height: 5)
                }
                .accessibilityHidden(true)

            Text(formatDuration(duration))
                .font(.callout.monospacedDigit())
                .foregroundStyle(entry.isCurrentlyTraining ? .green : .primary)
                .frame(width: 96, alignment: .trailing)

            Group {
                if let finish = entry.finishDate {
                    Text(EVEDates.short(finish, now: now))
                        .help(EVEDates.full(finish))
                } else {
                    Text("Paused")
                }
            }
            .font(.caption.monospacedDigit())
            .foregroundStyle(.secondary)
            .frame(width: 110, alignment: .trailing)
        }
        .padding(.horizontal, EVESpacing.lg)
        .padding(.vertical, EVESpacing.md)
        .background(isSelected ? palette.accent.opacity(EVEOpacity.soft) : Color.clear)
        .contentShape(Rectangle())
    }
}
