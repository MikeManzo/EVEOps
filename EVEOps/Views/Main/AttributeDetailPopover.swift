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

// MARK:  Skill Training Attribute

/// The five neural attributes that drive skill training speed.
/// `dogmaID` is the value carried by dogma attributes 180 (primary) / 181 (secondary)
/// on a skill's type record.
enum SkillTrainingAttribute: String, CaseIterable, Identifiable {
    case intelligence, memory, perception, willpower, charisma

    var id: String { rawValue }

    /// ESI dogma attribute ID for this neural attribute.
    var dogmaID: Int {
        switch self {
        case .intelligence: 164
        case .charisma:     165
        case .memory:       166
        case .perception:   167
        case .willpower:    168
        }
    }

    static func from(dogmaID: Int) -> SkillTrainingAttribute? {
        allCases.first { $0.dogmaID == dogmaID }
    }

    var displayName: String {
        switch self {
        case .intelligence: "Intelligence"
        case .memory:       "Memory"
        case .perception:   "Perception"
        case .willpower:    "Willpower"
        case .charisma:     "Charisma"
        }
    }

    /// SF Symbol — matches the dashboard attribute pills.
    var icon: String {
        switch self {
        case .intelligence: "brain"
        case .memory:       "memorychip"
        case .perception:   "eye.fill"
        case .willpower:    "bolt.fill"
        case .charisma:     "person.wave.2.fill"
        }
    }

    var color: Color {
        switch self {
        case .intelligence: .blue
        case .memory:       .green
        case .perception:   .orange
        case .willpower:    .purple
        case .charisma:     .pink
        }
    }

    /// Key used in the implant-bonus dictionary (lowercased attribute name).
    var bonusKey: String { rawValue }

    func value(in attrs: ESICharacterAttributes) -> Int {
        switch self {
        case .intelligence: attrs.intelligence
        case .memory:       attrs.memory
        case .perception:   attrs.perception
        case .willpower:    attrs.willpower
        case .charisma:     attrs.charisma
        }
    }

    /// Short, static description of the skill groups this attribute governs.
    var skillDomains: String {
        switch self {
        case .intelligence:
            "Trains most support skills — Engineering, Science, Electronic Systems, "
            + "Navigation, Armor, Shields, Subsystems, Neural Enhancement and Planet "
            + "Management. The most broadly useful attribute."
        case .memory:
            "Secondary for most Intelligence skills, and primary for Industry and "
            + "Drones. High value for crafters and drone pilots."
        case .perception:
            "Primary for Gunnery, Missiles, Spaceship Command and Targeting. The core "
            + "combat attribute — remap here for ship and weapon training."
        case .willpower:
            "Secondary for every combat skill (Gunnery, Missiles, Spaceship Command), "
            + "and primary for Leadership and Social. Pairs with Perception for combat remaps."
        case .charisma:
            "Primary for Trade, Social, Corporation Management and Leadership. Used by "
            + "the fewest skills — usually the safest attribute to leave at its minimum."
        }
    }
}

// MARK:  Implant bonus resolution

// Dogma attribute IDs for attribute-enhancing implants (+1 through +5).
// Confirmed working: 175=cha, 176=mem, 177=per, 179=int.
// Willpower is unconfirmed — 178 (boost attr) and 168 (char attr ID) are both tried;
// a per-type max prevents double-counting when both fire on the same implant.
private let implantAttrDogmaIDs: [Int: String] = [
    168: "willpower",
    175: "charisma",
    176: "memory",
    177: "perception",
    178: "willpower",
    179: "intelligence",
]

/// Resolves the total attribute bonus each active implant contributes, keyed by
/// lowercased attribute name (matching `SkillTrainingAttribute.bonusKey`).
func resolveImplantAttributeBonuses(implantTypeIDs: [Int]) async -> [String: Int] {
    guard !implantTypeIDs.isEmpty else { return [:] }
    let typeMap = await UniverseCache.shared.types(ids: implantTypeIDs)
    var bonuses: [String: Int] = [:]
    for typeInfo in typeMap.values {
        guard let dogma = typeInfo.dogmaAttributes else { continue }
        var perType: [String: Int] = [:]
        for attr in dogma {
            if let name = implantAttrDogmaIDs[attr.attributeId] {
                perType[name] = max(perType[name, default: 0], Int(attr.value))
            }
        }
        for (name, bonus) in perType {
            bonuses[name, default: 0] += bonus
        }
    }
    return bonuses
}

// MARK:  Pill

/// A single tappable attribute pill on the dashboard hero card. Pure button —
/// selection state and the detail panel live in the parent (`CharacterHeroView`).
struct AttributePill: View {
    let attr: SkillTrainingAttribute
    let value: Int
    let isSelected: Bool
    let onTap: () -> Void

    @State private var hovering = false

    private var fillOpacity: Double {
        if isSelected { return 0.30 }
        return hovering ? 0.22 : 0.12
    }

    private var strokeOpacity: Double {
        if isSelected { return 0.65 }
        return hovering ? 0.45 : 0.25
    }

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 4) {
                Image(systemName: attr.icon)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(attr.color)
                Text(attr.displayName)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(attr.color)
                Text("\(value)")
                    .font(.system(size: 13, weight: .bold).monospacedDigit())
                    .foregroundStyle(.primary)
            }
            .padding(.horizontal, 9)
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity)
            .background(attr.color.opacity(fillOpacity), in: Capsule())
            .overlay(Capsule().strokeBorder(attr.color.opacity(strokeOpacity), lineWidth: isSelected ? 1 : 0.5))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.12), value: hovering)
    }
}

// MARK:  Detail panel

struct AttributeDetailPopover: View {
    let focus: SkillTrainingAttribute
    let attributes: ESICharacterAttributes
    /// Lowercased-attribute-name → implant bonus points.
    var implantBonuses: [String: Int] = [:]
    /// True once the implant list has actually been fetched (an empty `implantBonuses`
    /// then means "no attribute implants", not "still loading").
    var implantsResolved = false
    var trainingSkillName: String?
    var trainingPrimary: SkillTrainingAttribute?
    var trainingSecondary: SkillTrainingAttribute?
    /// Fixed width for popover presentation; nil lets the panel fill its container (inline use).
    var fixedWidth: CGFloat? = nil
    var onOpenRemapAdvisor: () -> Void

    private var effective: Int { focus.value(in: attributes) }
    private var implant: Int { max(0, implantBonuses[focus.bonusKey, default: 0]) }
    private var base: Int { max(0, effective - implant) }

    /// SP/min this attribute contributes to the current skill, or nil if it isn't used.
    private var trainingContribution: (role: String, spPerMin: Double)? {
        if let p = trainingPrimary, p == focus {
            return ("Primary", Double(p.value(in: attributes)))
        }
        if let s = trainingSecondary, s == focus {
            return ("Secondary", Double(s.value(in: attributes)) / 2)
        }
        return nil
    }

    private var currentRate: Double? {
        guard let p = trainingPrimary, let s = trainingSecondary else { return nil }
        return Double(p.value(in: attributes)) + Double(s.value(in: attributes)) / 2
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            Divider()
            breakdownSection
            Divider()
            domainsSection
            Divider()
            trainingSection
            Divider()
            remapSection
            Button {
                onOpenRemapAdvisor()
            } label: {
                Label("Open Remap Advisor", systemImage: "brain.filled.head.profile")
                    .font(.callout.weight(.medium))
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(focus.color)
        }
        .padding(fixedWidth == nil ? 12 : 16)
        .frame(width: fixedWidth)
        .frame(maxWidth: fixedWidth == nil ? .infinity : nil, alignment: .leading)
    }

    // MARK: Header

    private var header: some View {
        HStack(spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(focus.color.opacity(0.18))
                    .frame(width: 34, height: 34)
                Image(systemName: focus.icon)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(focus.color)
            }
            VStack(alignment: .leading, spacing: 1) {
                Text(focus.displayName)
                    .font(.headline)
                Text("Neural attribute")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Text("\(effective)")
                .font(.system(size: 24, weight: .bold).monospacedDigit())
                .foregroundStyle(focus.color)
        }
    }

    // MARK: Base vs implant

    @ViewBuilder
    private var breakdownSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Composition")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            if !implantsResolved {
                Text("\(effective) effective")
                    .font(.callout.monospacedDigit())
                Text("Loading implant breakdown…")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            } else {
                GeometryReader { geo in
                    let total = max(effective, 1)
                    let baseW = geo.size.width * CGFloat(base) / CGFloat(total)
                    HStack(spacing: 2) {
                        RoundedRectangle(cornerRadius: 3)
                            .fill(focus.color.opacity(0.45))
                            .frame(width: max(baseW, 2))
                        if implant > 0 {
                            RoundedRectangle(cornerRadius: 3)
                                .fill(focus.color)
                        }
                    }
                }
                .frame(height: 10)

                HStack(spacing: 12) {
                    legendItem(color: focus.color.opacity(0.45), label: "Base", value: base)
                    if implant > 0 {
                        legendItem(color: focus.color, label: "Implant", value: implant)
                    }
                    Spacer()
                }
                if implant == 0 {
                    Text("No attribute implant in this slot")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
        }
    }

    private func legendItem(color: Color, label: String, value: Int) -> some View {
        HStack(spacing: 4) {
            Circle().fill(color).frame(width: 7, height: 7)
            Text("\(label) \(value)")
                .font(.caption2.monospacedDigit())
                .foregroundStyle(.secondary)
        }
    }

    // MARK: Skill domains

    private var domainsSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("What it trains")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(focus.skillDomains)
                .font(.caption)
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: Current training

    private var trainingSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Current training")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            if let skill = trainingSkillName, trainingPrimary != nil {
                if let contribution = trainingContribution {
                    (
                        Text("\(contribution.role) attribute for ")
                        + Text(skill).fontWeight(.semibold)
                    )
                    .font(.caption)
                    .fixedSize(horizontal: false, vertical: true)

                    Text("Driving \(fmt(contribution.spPerMin)) SP/min"
                         + (currentRate.map { " of \(fmt($0)) SP/min total" } ?? ""))
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.secondary)
                } else {
                    (
                        Text("Not used by ")
                        + Text(skill).fontWeight(.semibold)
                        + Text(" — training speed is unaffected by this attribute right now.")
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                }
            } else {
                Text("No skill in training.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: Remap status

    private var remapSection: some View {
        let status = RemapStatus(attributes: attributes)
        return VStack(alignment: .leading, spacing: 5) {
            Text("Remap status")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            Label {
                Text(status.bonusRemaps == 1
                     ? "1 bonus remap available"
                     : "\(status.bonusRemaps) bonus remaps available")
            } icon: {
                Image(systemName: status.bonusRemaps > 0 ? "checkmark.circle.fill" : "circle")
            }
            .font(.caption)
            .foregroundStyle(status.bonusRemaps > 0 ? .green : .secondary)

            Label {
                Text(status.annualText)
            } icon: {
                Image(systemName: status.annualAvailable ? "checkmark.circle.fill" : "clock")
            }
            .font(.caption)
            .foregroundStyle(status.annualAvailable ? .green : .secondary)

            if let last = status.lastRemapDate {
                Label {
                    Text("Last remap \(EVEFormatters.dateFormatter.string(from: last))")
                } icon: {
                    Image(systemName: "calendar")
                }
                .font(.caption2)
                .foregroundStyle(.tertiary)
            } else {
                Label("Never remapped", systemImage: "calendar")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
    }

    private func fmt(_ value: Double) -> String {
        value == value.rounded()
            ? String(format: "%.0f", value)
            : String(format: "%.1f", value)
    }
}

// MARK:  Remap status helper

private struct RemapStatus {
    let bonusRemaps: Int
    let lastRemapDate: Date?
    /// True when the annual remap is available now.
    let annualAvailable: Bool
    /// Human-readable annual-remap line.
    let annualText: String

    init(attributes: ESICharacterAttributes) {
        bonusRemaps = attributes.bonusRemaps ?? 0
        lastRemapDate = attributes.lastRemapDate

        let now = Date()
        var nextAnnual: Date?
        if let apiCooldown = attributes.accruedRemapCooldownDate {
            if apiCooldown > now { nextAnnual = apiCooldown }
        } else if let last = attributes.lastRemapDate,
                  let candidate = Calendar.current.date(byAdding: .year, value: 1, to: last),
                  candidate > now {
            nextAnnual = candidate
        }

        if let nextAnnual {
            annualAvailable = false
            annualText = "Annual remap in \(EVEFormatters.timeUntil(nextAnnual))"
        } else {
            annualAvailable = true
            annualText = "Annual remap available now"
        }
    }
}
