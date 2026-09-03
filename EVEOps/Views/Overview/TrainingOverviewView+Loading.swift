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
    // MARK:  Prefetcher Fast Path

    func buildFromPrefetcher() -> Bool {
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

    func loadTraining() async {
        if trainingData.isEmpty { isLoading = true }
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
        lastRefresh = Date()
        isLoading = false
    }
}
