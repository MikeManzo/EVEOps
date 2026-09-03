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
