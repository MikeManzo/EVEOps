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

// EVE dogma attribute ID pairs that encode required skills on an item type.
private let skillAttrPairs: [(skillAttr: Int, levelAttr: Int)] = [
    (182, 277), (183, 278), (184, 279),
    (1285, 1289), (1286, 1290), (1287, 1291)
]

private struct ResolvedSkillReq: Identifiable {
    let skillTypeId: Int
    let requiredLevel: Int
    var skillName: String
    var id: Int { skillTypeId }
}

/// Compact row of skill-requirement pills for any market item.
/// Green = requirement met, orange = skill too low, red = not trained, grey = no character.
struct SkillRequirementsView: View {
    /// Type ID — used as the task key so the view refreshes on every selection change.
    let typeId: Int?
    /// ESIType from the parent if already loaded. Used as a fast path to avoid an extra
    /// network round-trip, but only if its dogmaAttributes are present.
    let typeInfo: ESIType?
    /// Active skill levels keyed by skill type ID. Pass nil when no character is logged in.
    let characterSkills: [Int: Int]?

    @State private var requirements: [ResolvedSkillReq] = []

    var body: some View {
        HStack(spacing: requirements.isEmpty ? 0 : 6) {
            if !requirements.isEmpty {
                Image(systemName: "graduationcap.fill")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                ForEach(requirements) { req in
                    skillPill(req)
                }
            }
        }
        .task(id: typeId) {
            await resolveRequirements()
        }
    }

    @ViewBuilder
    private func skillPill(_ req: ResolvedSkillReq) -> some View {
        let have = characterSkills?[req.skillTypeId] ?? 0
        let met  = have >= req.requiredLevel
        let partial = !met && have > 0

        let color: Color = characterSkills == nil ? .secondary
                         : met     ? .green
                         : partial ? .orange
                         :           .red

        let icon: String = characterSkills == nil ? "questionmark"
                         : met     ? "checkmark"
                         : partial ? "arrow.up"
                         :           "xmark"

        let label = partial
            ? "\(req.skillName) \(roman(have))→\(roman(req.requiredLevel))"
            : "\(req.skillName) \(roman(req.requiredLevel))"

        HStack(spacing: 3) {
            Image(systemName: icon)
                .font(.system(size: 7, weight: .bold))
            Text(label)
                .font(.system(size: 10, weight: .medium))
                .lineLimit(1)
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .background(color.opacity(characterSkills == nil ? 0.45 : 0.85), in: Capsule())
        .help(helpText(for: req, have: have))
    }

    private func helpText(for req: ResolvedSkillReq, have: Int) -> String {
        guard let _ = characterSkills else {
            return "\(req.skillName) \(roman(req.requiredLevel)) required (no character logged in)"
        }
        if have >= req.requiredLevel {
            return "\(req.skillName) \(roman(req.requiredLevel)) — satisfied (you have level \(have))"
        }
        if have > 0 {
            return "\(req.skillName) \(roman(req.requiredLevel)) required — you have level \(have)"
        }
        return "\(req.skillName) \(roman(req.requiredLevel)) required — not trained"
    }

    private func resolveRequirements() async {
        requirements = []
        guard let typeId else { return }

        // Fast path: use dogmaAttributes from the parent's ESIType if present.
        // Fallback: fetch fresh from ESI with bypassCache so we always get dogma data
        // even when UniverseCache holds a version that was saved without it.
        let attrs: [ESIDogmaAttribute]
        if let a = typeInfo?.dogmaAttributes {
            attrs = a
        } else {
            guard let fetched: ESIType = try? await ESIClient.shared.fetch(
                "/universe/types/\(typeId)/", bypassCache: true)
            else { return }
            guard let a = fetched.dogmaAttributes else { return }
            attrs = a
        }

        guard !Task.isCancelled else { return }

        let attrMap = Dictionary(attrs.map { ($0.attributeId, $0.value) },
                                 uniquingKeysWith: { a, _ in a })

        var parsed: [ResolvedSkillReq] = []
        for pair in skillAttrPairs {
            guard let rawSkill = attrMap[pair.skillAttr],
                  let rawLevel = attrMap[pair.levelAttr] else { continue }
            let skillId = Int(rawSkill)
            let level   = Int(rawLevel)
            guard skillId > 0, level > 0 else { continue }
            parsed.append(ResolvedSkillReq(skillTypeId: skillId, requiredLevel: level, skillName: "…"))
        }

        guard !parsed.isEmpty else { return }
        requirements = parsed

        let names = await withTaskGroup(of: (Int, String).self) { group in
            for req in parsed {
                let id = req.skillTypeId
                group.addTask {
                    (id, await UniverseCache.shared.type(id: id)?.name ?? "Unknown Skill")
                }
            }
            var out: [Int: String] = [:]
            for await (id, name) in group { out[id] = name }
            return out
        }

        guard !Task.isCancelled else { return }

        requirements = parsed.map { req in
            var r = req
            r.skillName = names[req.skillTypeId] ?? "Unknown Skill"
            return r
        }
    }

    private func roman(_ level: Int) -> String {
        let table = ["0", "I", "II", "III", "IV", "V"]
        return level < table.count ? table[level] : "\(level)"
    }
}
