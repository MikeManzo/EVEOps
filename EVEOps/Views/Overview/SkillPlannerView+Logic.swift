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
    // MARK:  SP & Time Calculations

    // Total SP at each level for rank-1 skills
    static let spThresholds: [Int: Int] = [
        0: 0, 1: 250, 2: 1414, 3: 8000, 4: 45255, 5: 256000
    ]

    func spForLevel(_ level: Int, rank: Int) -> Int {
        (Self.spThresholds[level] ?? 0) * rank
    }

    func spNeeded(for item: SkillPlanItem) -> Int {
        guard item.fromLevel < item.targetLevel else { return 0 }
        let rank = skillRank(for: item.skillId)
        return spForLevel(item.targetLevel, rank: rank) - spForLevel(item.fromLevel, rank: rank)
    }

    func trainingTime(for item: SkillPlanItem, attrs: ESICharacterAttributes) -> Double {
        let sp = Double(spNeeded(for: item))
        guard sp > 0 else { return 0 }
        let type = skillTypes[item.skillId]
        let (primaryId, secondaryId) = dogmaAttributes(for: type)
        let primary = Double(characterAttr(attrs, dogmaId: primaryId))
        let secondary = Double(characterAttr(attrs, dogmaId: secondaryId))
        // EVE formula: SP per minute = primary + secondary × 0.5
        let spPerMinute = primary + secondary * 0.5
        guard spPerMinute > 0 else { return 0 }
        return sp / spPerMinute * 60.0
    }

    func skillRank(for typeId: Int) -> Int {
        guard let type = skillTypes[typeId],
              let attr = type.dogmaAttributes?.first(where: { $0.attributeId == 275 }) else { return 1 }
        return max(1, Int(attr.value))
    }

    /// Returns (primaryDogmaID, secondaryDogmaID) — values are 164…168
    func dogmaAttributes(for type: ESIType?) -> (Int, Int) {
        guard let dogma = type?.dogmaAttributes else { return (165, 166) }
        let primary = dogma.first(where: { $0.attributeId == 180 }).map { Int($0.value) } ?? 165
        let secondary = dogma.first(where: { $0.attributeId == 181 }).map { Int($0.value) } ?? 166
        return (primary, secondary)
    }

    /// Maps dogma attribute ID (164-168) → actual character attribute value
    func characterAttr(_ attrs: ESICharacterAttributes, dogmaId: Int) -> Int {
        switch dogmaId {
        case 164: return attrs.charisma
        case 165: return attrs.intelligence
        case 166: return attrs.memory
        case 167: return attrs.perception
        case 168: return attrs.willpower
        default:  return attrs.intelligence
        }
    }

    // MARK:  Persistence

    var planKey: String {
        "skillPlan-\(accountManager.selectedAccount?.characterID ?? 0)"
    }

    func savePlan() {
        if let data = try? JSONEncoder().encode(planItems) {
            UserDefaults.standard.set(data, forKey: planKey)
        }
    }

    func loadPlan() {
        guard let data = UserDefaults.standard.data(forKey: planKey),
              let items = try? JSONDecoder().decode([SkillPlanItem].self, from: data) else { return }
        planItems = items
        let ids = items.map { $0.skillId }
        Task {
            let types = await UniverseCache.shared.types(ids: ids)
            skillTypes.merge(types) { _, new in new }
        }
    }

    // MARK:  Data Loading

    /// Replaces `trainingData` entries with the latest prefetched snapshot in place, so the
    /// Item Tree's `characterSkillMap` reflects newly-completed training the next time an item
    /// is searched — without toggling `isLoading`, which would tear down the browser subtree.
    func refreshTrainingDataSilently() async {
        for account in accountManager.accounts {
            guard let prefetched = prefetcher.data(for: account.characterID) else { continue }
            let info = buildInfo(from: prefetched, account: account)
            if let idx = trainingData.firstIndex(where: { $0.characterID == account.characterID }) {
                trainingData[idx] = info
            } else {
                trainingData.append(info)
            }
        }
    }

    func loadData() async {
        isLoading = true
        error = nil

        // Try prefetcher first
        var data: [CharacterTrainingInfo] = []
        for account in accountManager.accounts {
            guard let prefetched = prefetcher.data(for: account.characterID) else { continue }
            data.append(buildInfo(from: prefetched, account: account))
        }

        if !data.isEmpty {
            trainingData = data
            await loadAttributes()
            loadPlan()
            isLoading = false
            return
        }

        // Live fetch fallback
        guard let account = accountManager.selectedAccount else { isLoading = false; return }
        do {
            let token = try await accountManager.validToken(for: account)
            async let fetchSkills: ESISkillsResponse = ESIClient.shared.fetch("/characters/\(account.characterID)/skills/", token: token)
            async let fetchQueue: [ESISkillQueue] = ESIClient.shared.fetch("/characters/\(account.characterID)/skillqueue/", token: token)
            let (skills, _) = try await (fetchSkills, fetchQueue)

            let allIDs = Array(Set(skills.skills.map(\.skillId)))
            let resolvedNames = await NameResolver.shared.resolve(ids: allIDs)
            let types = await UniverseCache.shared.types(ids: allIDs)
            let groupIDs = Set(types.values.map(\.groupId))
            let groups = await UniverseCache.shared.groups(ids: groupIDs)

            var groupedSkills: [Int: [KnownSkill]] = [:]
            for skill in skills.skills {
                let name = resolvedNames[skill.skillId] ?? "Skill #\(skill.skillId)"
                let known = KnownSkill(skillId: skill.skillId, name: name, trainedLevel: skill.trainedSkillLevel, activeLevel: skill.activeSkillLevel, skillpoints: skill.skillpointsInSkill)
                let gid = types[skill.skillId]?.groupId ?? 0
                groupedSkills[gid, default: []].append(known)
            }
            let skillGroups = groupedSkills.map { gid, skills in
                KnownSkillGroup(groupId: gid, groupName: groups[gid]?.name ?? "Unknown", skills: skills)
            }
            let info = CharacterTrainingInfo(
                characterID: account.characterID, characterName: account.characterName,
                totalSP: skills.totalSp, unallocatedSP: skills.unallocatedSp ?? 0,
                knownSkillCount: skills.skills.count, skillsByLevel: [:],
                queue: [], queueEmpty: true, queueEndDate: nil,
                skillGroups: skillGroups, lastCloneJumpDate: nil
            )
            trainingData = [info]
            await loadAttributes()
            loadPlan()
        } catch {
            self.error = error.localizedDescription
        }
        isLoading = false
    }

    func loadAttributes() async {
        let charID = accountManager.selectedAccount?.characterID ?? 0
        guard let account = accountManager.accounts.first(where: { $0.characterID == charID }) else { return }
        do {
            let token = try await accountManager.validToken(for: account)
            let attrs: ESICharacterAttributes = try await ESIClient.shared.fetch(
                "/characters/\(charID)/attributes/", token: token
            )
            self.attributes = attrs
        } catch {
            // Non-critical — time estimates just won't show
        }
    }

    func buildInfo(from prefetched: DashboardPrefetcher.PrefetchedCharacterData, account: StoredAccount) -> CharacterTrainingInfo {
        var groupedSkills: [Int: [KnownSkill]] = [:]
        for skill in prefetched.skills.skills {
            let name = prefetcher.resolvedNames[skill.skillId] ?? "Skill #\(skill.skillId)"
            let known = KnownSkill(skillId: skill.skillId, name: name, trainedLevel: skill.trainedSkillLevel, activeLevel: skill.activeSkillLevel, skillpoints: skill.skillpointsInSkill)
            let gid = prefetcher.resolvedTypes[skill.skillId]?.groupId ?? 0
            groupedSkills[gid, default: []].append(known)
        }
        let skillGroups = groupedSkills.map { gid, skills in
            KnownSkillGroup(groupId: gid, groupName: prefetcher.resolvedGroups[gid]?.name ?? "Unknown Group", skills: skills)
        }
        return CharacterTrainingInfo(
            characterID: account.characterID, characterName: account.characterName,
            totalSP: prefetched.skills.totalSp, unallocatedSP: prefetched.skills.unallocatedSp ?? 0,
            knownSkillCount: prefetched.skills.skills.count, skillsByLevel: [:],
            queue: [], queueEmpty: true, queueEndDate: nil,
            skillGroups: skillGroups, lastCloneJumpDate: prefetched.clones?.lastCloneJumpDate
        )
    }

    // MARK:  Visual Helpers

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

    func formatSP(_ sp: Int) -> String {
        if sp >= 1_000_000 { return String(format: "%.1fM", Double(sp) / 1_000_000) }
        if sp >= 1_000 { return String(format: "%.0fK", Double(sp) / 1_000) }
        return "\(sp) SP"
    }

    func formatDuration(_ seconds: Double) -> String {
        let total = Int(max(seconds, 0))
        if total == 0 { return "<1m" }
        let days = total / 86400
        let hours = (total % 86400) / 3600
        let minutes = (total % 3600) / 60
        if days > 0 { return "\(days)d \(hours)h \(minutes)m" }
        if hours > 0 { return "\(hours)h \(minutes)m" }
        return "\(minutes)m"
    }
}
