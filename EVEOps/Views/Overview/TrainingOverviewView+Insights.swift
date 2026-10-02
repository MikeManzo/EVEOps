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

// MARK: - Header insight blocks

extension TrainingOverviewView {
    /// Implant bonuses per attribute, from the implants' dogma.
    var implantBonuses: [EVEAttribute: Int] {
        var bonuses: [EVEAttribute: Int] = [:]
        for implant in implantTypes {
            for attr in EVEAttribute.allCases {
                if let v = implant.dogmaAttributes?.first(where: { $0.attributeId == attr.implantBonusDogmaID })?.value, v > 0 {
                    bonuses[attr, default: 0] += Int(v)
                }
            }
        }
        return bonuses
    }

    /// Remaining queue SP grouped by attribute pair.
    func queueDemand(_ info: CharacterTrainingInfo) -> [SkillTraining.Demand] {
        var byPair: [String: SkillTraining.Demand] = [:]
        for entry in info.queue {
            guard let end = entry.levelEndSP else { continue }
            let start = entry.isCurrentlyTraining
                ? Int(Double(entry.levelStartSP ?? 0) + levelProgress(entry, at: now) * Double(end - (entry.levelStartSP ?? 0)))
                : (entry.levelStartSP ?? end)
            let sp = max(end - start, 0)
            guard sp > 0 else { continue }
            let pair = SkillTraining.attributes(of: queueSkillTypes[entry.skillId])
            let key = "\(pair.primary.rawValue)-\(pair.secondary.rawValue)"
            let prior = byPair[key]?.sp ?? 0
            byPair[key] = .init(primary: pair.primary, secondary: pair.secondary, sp: prior + sp)
        }
        return Array(byPair.values)
    }

    // MARK: Remap payoff

    /// "Optimal remap PER 27 · WIL 21 finishes your queue 4d 6h sooner", or a note that
    /// the current attributes already fit the queue.
    @ViewBuilder
    func remapPayoff(_ info: CharacterTrainingInfo) -> some View {
        if let attrs = attributes, let best = remapResult {
            let current = Dictionary(uniqueKeysWithValues: EVEAttribute.allCases.map { ($0, $0.value(in: attrs)) })
            let currentMinutes = SkillTraining.minutes(for: best.demand, totals: current)
            let saved = (currentMinutes - best.minutes) * 60
            let raised = EVEAttribute.allCases
                .filter { best.base[$0, default: 17] > SkillTraining.baseAttribute }
                .sorted { best.base[$0, default: 0] > best.base[$1, default: 0] }
            if saved >= 3600 {
                VStack(alignment: .leading, spacing: EVESpacing.xs) {
                    HStack(alignment: .firstTextBaseline, spacing: EVESpacing.xs) {
                        Image(systemName: "lightbulb.fill")
                            .foregroundStyle(.yellow)
                        Text("Remap to \(raised.map { "\($0.abbreviation) \(best.base[$0]!)" }.joined(separator: " · "))")
                            .font(.caption.weight(.semibold))
                    }
                    Text("Finishes this queue \(formatDuration(saved)) sooner")
                        .font(.caption)
                        .foregroundStyle(.green)
                    Button("Open Remap Advisor") { AppRouter.shared.pendingSection = .remapAdvisor }
                        .buttonStyle(.link)
                        .font(.caption)
                }
                .help("Base values after remap; implant bonuses are added on top.")
            } else {
                Label("Attributes already suit this queue", systemImage: "checkmark.circle.fill")
                    .font(.caption)
                    .foregroundStyle(.green)
            }
        }
    }

    // MARK: Implants

    func implantsBlock() -> some View {
        let sorted = implantTypes.sorted { implantSlot($0) < implantSlot($1) }
        let attributeImplants = sorted.filter { implantSlot($0) <= 5 }
        let hardwirings = sorted.filter { implantSlot($0) > 5 }
        return VStack(alignment: .leading, spacing: EVESpacing.sm) {
            blockTitle("Implants")
            if !implantsLoaded {
                Text("Loading…").font(.caption).foregroundStyle(.secondary)
            } else if sorted.isEmpty {
                Text("No implants plugged in")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                VStack(alignment: .leading, spacing: EVESpacing.xs) {
                    ForEach(attributeImplants, id: \.typeId) { implant in
                        HStack(spacing: EVESpacing.sm) {
                            implantIcon(implant)
                            Text(implant.name)
                                .font(.caption)
                                .lineLimit(1)
                                .eveTruncationHelp(implant.name)
                            Spacer(minLength: EVESpacing.xs)
                            if let bonus = attributeBonus(of: implant) {
                                EVEChip(Text("+\(bonus.value) \(bonus.attribute.abbreviation)"), tint: palette.knowledge)
                            }
                        }
                        .eveContextMenu(.item(typeID: implant.typeId, name: implant.name))
                    }
                    if !hardwirings.isEmpty {
                        HStack(spacing: EVESpacing.xs) {
                            ForEach(hardwirings, id: \.typeId) { implant in
                                implantIcon(implant)
                                    .help("Slot \(implantSlot(implant)): \(implant.name)")
                                    .eveContextMenu(.item(typeID: implant.typeId, name: implant.name))
                            }
                            Text("\(hardwirings.count) hardwiring\(hardwirings.count == 1 ? "" : "s")")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .padding(.leading, EVESpacing.xxs)
                        }
                    }
                }
            }
        }
    }

    private func implantIcon(_ implant: ESIType) -> some View {
        CachedAsyncImage(url: EVEImageURL.typeIcon(implant.typeId, size: 64)) { image in
            image.resizable()
        } placeholder: {
            RoundedRectangle(cornerRadius: EVERadius.xs).fill(.quaternary)
        }
        .frame(width: 18, height: 18)
        .background(EVEFill.iconWell, in: RoundedRectangle(cornerRadius: EVERadius.xs))
        .clipShape(RoundedRectangle(cornerRadius: EVERadius.xs))
    }

    private func implantSlot(_ implant: ESIType) -> Int {
        implant.dogmaAttributes?.first { $0.attributeId == 331 }.map { Int($0.value) } ?? 99
    }

    private func attributeBonus(of implant: ESIType) -> (attribute: EVEAttribute, value: Int)? {
        for attr in EVEAttribute.allCases {
            if let v = implant.dogmaAttributes?.first(where: { $0.attributeId == attr.implantBonusDogmaID })?.value, v > 0 {
                return (attr, Int(v))
            }
        }
        return nil
    }

    // MARK: Skill plan

    func planBlock(_ info: CharacterTrainingInfo) -> some View {
        let items = savedPlan
        let seconds: Double = {
            guard let attrs = attributes else { return 0 }
            return items.reduce(0) { sum, item in
                let type = planSkillTypes[item.skillId]
                let rank = SkillTraining.rank(of: type)
                let sp = SkillTraining.sp(forLevel: item.targetLevel, rank: rank) - SkillTraining.sp(forLevel: item.fromLevel, rank: rank)
                let pair = SkillTraining.attributes(of: type)
                let rate = Double(pair.primary.value(in: attrs)) + Double(pair.secondary.value(in: attrs)) / 2
                return sum + (rate > 0 ? Double(max(sp, 0)) / rate * 60 : 0)
            }
        }()
        let startsAt = max(info.queueEndDate ?? now, now)
        return VStack(alignment: .leading, spacing: EVESpacing.sm) {
            blockTitle("Skill Plan")
            if items.isEmpty {
                Text("No saved plan")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                VStack(alignment: .leading, spacing: EVESpacing.xxs) {
                    Text("\(items.count) skill\(items.count == 1 ? "" : "s")\(attributes != nil ? " · \(formatDuration(seconds))" : "")")
                        .font(.callout.weight(.semibold).monospacedDigit())
                    if attributes != nil {
                        Text("Done \(EVEDates.short(startsAt.addingTimeInterval(seconds), now: now)) after the queue")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .help(EVEDates.full(startsAt.addingTimeInterval(seconds)))
                    }
                }
            }
            Button(items.isEmpty ? "Build a Plan" : "Open Skill Planner") {
                AppRouter.shared.pendingSection = .skillPlanner
            }
            .buttonStyle(.link)
            .font(.caption)
        }
    }

    // MARK: Milestones & injectors

    func milestonesBlock(_ info: CharacterTrainingInfo) -> some View {
        let sp = info.totalSP + info.unallocatedSP
        let step = sp < 10_000_000 ? 5_000_000 : 10_000_000
        let milestone = (sp / step + 1) * step
        let rate = currentSPPerHour(info)
        let injector = SkillTraining.largeInjectorYield(totalSP: sp)
        let queued = queueDemand(info).reduce(0) { $0 + $1.sp }
        return VStack(alignment: .leading, spacing: EVESpacing.sm) {
            blockTitle("Milestones")
            VStack(alignment: .leading, spacing: EVESpacing.xxs) {
                Text("\(formatSP(milestone)) SP")
                    .font(.callout.weight(.semibold).monospacedDigit())
                if let rate, rate > 0 {
                    let eta = now.addingTimeInterval(Double(milestone - sp) / rate * 3600)
                    Text("in ~\(EVEFormatters.timeUntil(eta)) at this rate")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .help("Around \(EVEDates.full(eta))")
                } else {
                    Text("\(formatSP(milestone - sp)) to go")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            VStack(alignment: .leading, spacing: EVESpacing.xxs) {
                Label("Large injector: +\(formatSP(injector)) SP", systemImage: "syringe")
                if queued > 0 {
                    Text("Queue ≈ \((Double(queued) / Double(injector)).formatted(.number.precision(.fractionLength(1)))) large injectors")
                        .foregroundStyle(.secondary)
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .help("Large Skill Injector yield drops at 5M, 50M and 80M total SP")
        }
    }

    // MARK: Loading

    /// Implants, queue-skill types (ranks and attribute pairs) and the saved plan.
    func loadInsights() async {
        guard let info = trainingData.first,
              let account = accountManager.accounts.first(where: { $0.characterID == info.characterID }) else { return }

        async let queueTypes = UniverseCache.shared.types(ids: Array(Set(info.queue.map(\.skillId))))

        let plan: [SkillPlanItem] = UserDefaults.standard.data(forKey: "skillPlan-\(info.characterID)")
            .flatMap { try? JSONDecoder().decode([SkillPlanItem].self, from: $0) } ?? []
        async let planTypes = UniverseCache.shared.types(ids: plan.map(\.skillId))

        if !implantsLoaded, let token = try? await accountManager.validToken(for: account) {
            let ids: [Int] = (try? await ESIClient.shared.fetch("/characters/\(info.characterID)/implants/", token: token)) ?? []
            implantTypes = Array(await UniverseCache.shared.types(ids: ids).values)
        }
        implantsLoaded = true
        queueSkillTypes = await queueTypes
        savedPlan = plan
        planSkillTypes = await planTypes

        let demand = queueDemand(info)
        let implants = implantBonuses
        let best = await Task.detached(priority: .userInitiated) {
            SkillTraining.optimalRemap(for: demand, implants: implants)
        }.value
        remapResult = best.map { RemapResult(demand: demand, base: $0.base, minutes: $0.minutes) }
    }
}
