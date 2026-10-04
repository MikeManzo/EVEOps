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

nonisolated enum SkillROIFilter: String, CaseIterable, Sendable {
    case all, fits, improves, slots

    /// Whether a goal belongs in this view — used for the ranked list and the plan alike.
    func includes(_ goal: SkillROIGoal) -> Bool {
        switch self {
        case .all:      true
        case .fits:     !goal.completes.isEmpty || !goal.advances.isEmpty
        case .improves: !goal.improves.isEmpty
        case .slots:    goal.capacity != nil
        }
    }

    var title: LocalizedStringResource {
        switch self {
        case .all:      "Everything"
        case .fits:     "Unlocks Fits"
        case .improves: "Improves Fits"
        case .slots:    "Adds Slots"
        }
    }
}

enum SkillROISort: String, CaseIterable {
    case value, shortest

    var title: LocalizedStringKey {
        switch self {
        case .value:    "Best Value"
        case .shortest: "Shortest Training"
        }
    }
}

/// How much training the plan may spend.
enum SkillROIPlanBudget: Int, CaseIterable {
    case week = 7, twoWeeks = 14, month = 30, quarter = 90

    var title: LocalizedStringKey {
        switch self {
        case .week:     "1 Week"
        case .twoWeeks: "2 Weeks"
        case .month:    "30 Days"
        case .quarter:  "90 Days"
        }
    }

    var seconds: Double { Double(rawValue) * 86400 }
}

// MARK:  Main View

/// "What should I train next?" — skill levels ranked by what they unlock in this pilot's
/// own hangar and slots per day of training: saved fits that become flyable, fits that get
/// closer, flyable fits that get better, and more industry, market, PI or clone slots where
/// the current ones are busy.
struct SkillROIView: View {
    @Environment(AccountManager.self) private var accountManager
    @Environment(DashboardPrefetcher.self) private var prefetcher
    @Environment(ThemeManager.self) private var themeManager
    @AppStorage("skillROI.filter") private var filterRaw = SkillROIFilter.all.rawValue
    @AppStorage("skillROI.sort") private var sortRaw = SkillROISort.value.rawValue
    @AppStorage("skillROI.planBudget") private var budgetRaw = SkillROIPlanBudget.twoWeeks.rawValue

    @State private var goals: [SkillROIGoal] = []
    @State private var isPreparing = false
    @State private var preparedFor: Int?
    /// The ranking's input, kept so the plan can be rebuilt when the budget changes.
    @State private var planInput: SkillROIInput?
    @State private var plan: SkillROIPlan?

    private var readyRoom: ReadyRoomService { .shared }
    private var palette: EVEPalette { themeManager.palette }
    private var characterID: Int? { accountManager.selectedCharacterID }
    private var snapshot: ReadyRoomSnapshot? { characterID.flatMap { readyRoom.snapshots[$0] } }
    private var filter: SkillROIFilter { SkillROIFilter(rawValue: filterRaw) ?? .all }
    private var sort: SkillROISort { SkillROISort(rawValue: sortRaw) ?? .value }
    private var budget: SkillROIPlanBudget { SkillROIPlanBudget(rawValue: budgetRaw) ?? .twoWeeks }
    private var isLoading: Bool { isPreparing || (characterID.map(readyRoom.isLoading) ?? false) }

    /// Changes whenever the board's fits or tiers do, so the ranking follows.
    private var boardKey: [String] {
        (snapshot?.reports.map { "\($0.id):\($0.tier.rawValue)" } ?? []) + ["\(String(describing: snapshot?.fittingCheck))"]
    }

    var body: some View {
        content
            .eveScreenHeader("Skill ROI", subtitle: subtitle, section: .skillROI) {
                FreshnessIndicator(isLoading: isLoading) { await load(force: true) }
            }
            .task(id: characterID) {
                goals = []
                plan = nil
                planInput = nil
                preparedFor = nil
                await load()
            }
            .onChange(of: boardKey) { _, _ in Task { await rank() } }
            .onChange(of: budgetRaw) { _, _ in Task { await buildPlan() } }
            .onChange(of: filterRaw) { _, _ in Task { await buildPlan() } }
            .onChange(of: AppRouter.shared.refreshTick) { _, _ in Task { await load(force: true) } }
    }

    private var subtitle: Text? {
        guard let account = accountManager.selectedAccount, !goals.isEmpty else { return nil }
        return Text("\(goals.count) skill levels ranked for \(account.characterName)")
    }

    // MARK: Loading

    private func load(force: Bool = false) async {
        guard let account = accountManager.selectedAccount else { return }
        if force || readyRoom.snapshots[account.characterID] == nil {
            await readyRoom.refresh(account, accountManager: accountManager, prefetcher: prefetcher, force: force)
        }
        if IdleCapacityService.shared.jobHistory[account.characterID] == nil {
            await IdleCapacityService.shared.loadExtras(accountManager: accountManager, prefetcher: prefetcher, includeHistory: true)
        }
        await rank()
    }

    /// Builds the engine input from the Ready Room board and the pilot's capacity, fetching
    /// prerequisites and training data for every candidate skill, then ranks.
    private func rank() async {
        guard let characterID, let snapshot = readyRoom.snapshots[characterID] else { return }
        isPreparing = true
        defer { isPreparing = false }

        let capacity = prefetcher.characterData[characterID].map {
            IdleCapacityEngine.report(IdleCapacityService.shared.input(characterID: characterID, data: $0))
        }
        var input = SkillROIInput(
            reports: snapshot.reports,
            pinnedFittingIDs: readyRoom.pinnedFittingIDs(for: characterID),
            skills: snapshot.input.skills,
            skillQueue: snapshot.input.skillQueue,
            attributes: snapshot.input.attributes,
            skillInfo: snapshot.input.skillInfo,
            capacity: capacity,
            performance: await SkillPerformanceService.shared.deltas(for: snapshot)
        )
        guard characterID == self.characterID else { return }
        let candidates = Set(SkillROIEngine.candidateLevels(input).map(\.skillID))
        let prerequisites = await SkillPrerequisites.shared.requirements(for: Array(candidates))
        let involved = candidates.union(prerequisites.values.flatMap(\.keys)).subtracting(input.skillInfo.keys)
        input.prerequisites = prerequisites
        input.skillInfo.merge(await SkillPrerequisites.shared.trainingInfo(for: Array(involved))) { a, _ in a }

        let ranked = await Task.detached(priority: .userInitiated) { [input] in SkillROIEngine.goals(input) }.value
        guard characterID == self.characterID else { return }
        withAnimation(EVEMotion.snappy) { goals = ranked }
        preparedFor = characterID
        planInput = input
        await buildPlan()
    }

    /// The best set of picks within the budget, re-ranked after each one, drawn from the
    /// goals the current filter shows.
    private func buildPlan() async {
        guard let characterID, let input = planInput else { return }
        let budget = budget.seconds
        let filter = filter
        let remeasure = SkillPerformanceService.shared.remeasure(for: characterID)
        let built = await Task.detached(priority: .userInitiated) {
            SkillROIEngine.plan(input, budget: budget, include: filter.includes) { remeasure?($0, $1) ?? [:] }
        }.value
        guard characterID == self.characterID else { return }
        withAnimation(EVEMotion.snappy) { plan = built }
    }

    /// When training in the plan can start: after everything already queued.
    private var queueEnd: Date {
        max(snapshot?.input.skillQueue.compactMap(\.finishDate).max() ?? .now, .now)
    }

    // MARK: Content

    private var visibleGoals: [SkillROIGoal] {
        let filtered = goals.filter(filter.includes)
        switch sort {
        case .value:    return filtered
        case .shortest: return filtered.sorted { ($0.seconds ?? .infinity) < ($1.seconds ?? .infinity) }
        }
    }

    @ViewBuilder
    private var content: some View {
        if goals.isEmpty {
            if isLoading || preparedFor != characterID {
                LoadingSkeleton()
            } else {
                EVEEmptyState("Nothing to Rank", systemImage: "chart.line.uptrend.xyaxis",
                              message: Text("Every saved fit is already flyable (or queued), and no slot skill would add capacity you use. Save more fittings to see what to train for them.")) {
                    Button("Open Ready Room") { AppRouter.shared.pendingSection = .readyRoom }
                        .buttonStyle(.borderedProminent)
                        .tint(palette.accent)
                }
            }
        } else {
            ScrollView {
                VStack(alignment: .leading, spacing: EVESpacing.xl) {
                    totals
                    if let plan {
                        SkillROIPlanCard(plan: plan, start: queueEnd, filter: filter,
                                         budget: Binding(get: { budget }, set: { budgetRaw = $0.rawValue }),
                                         summary: summary) {
                            copy(plan.picks)
                        }
                    }
                    filterBar
                    LazyVStack(alignment: .leading, spacing: EVESpacing.md) {
                        ForEach(Array(visibleGoals.enumerated()), id: \.element.id) { index, goal in
                            SkillROICard(goal: goal, rank: index + 1, best: goals.first?.score ?? 1,
                                         pinned: characterID.map(readyRoom.pinnedFittingIDs) ?? [],
                                         reports: reportsByID) {
                                copy([goal])
                            }
                            .eveScrollReveal()
                        }
                    }
                    Text("Value counts fits made flyable (pinned fits double), fits brought closer, how much flyable fits improve (DPS, tank, speed, lock range, capacitor — measured with your skills and implants), and extra slots weighted by how busy your current ones are — divided by training days.")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
                .padding()
            }
        }
    }

    private var reportsByID: [Int: ReadyRoomReport] {
        Dictionary(snapshot?.reports.map { ($0.fittingID, $0) } ?? [], uniquingKeysWith: { a, _ in a })
    }

    private func copy(_ picked: [SkillROIGoal]) {
        guard let snapshot else { return }
        let text = SkillROIEngine.eveSkillPlan(picked, skills: snapshot.input.skills)
        let count = text.split(separator: "\n").count
        InsightClipboard.copy(text, toast: String(localized: "Copied \(count) skill levels — paste into EVE's skill queue"))
    }

    // MARK: Totals

    private var totals: some View {
        let best = goals.first
        let quick = goals.filter(\.isQuickWin)
        let oneAway = Set(goals.flatMap { $0.completes.map(\.fittingID) })
        let busySlots = goals.filter { ($0.capacity?.busyShare ?? 0) >= 0.8 }
        return InsightStatRow {
            InsightStat(label: String(localized: "Best Pick"),
                        value: best.map { "\($0.name) \(ReadyRoomFormat.roman($0.level))" } ?? "—",
                        detail: best.map { summary($0) } ?? "",
                        tint: palette.accent)
            InsightStat(label: String(localized: "Quick Wins"), value: "\(quick.count)",
                        detail: String(localized: "pay off in under a day of training"),
                        tint: quick.isEmpty ? .secondary : .green)
            InsightStat(label: String(localized: "Fits One Goal Away"), value: "\(oneAway.count)",
                        detail: String(localized: "flyable after a single pick"),
                        tint: ReadyRoomTier.train.color(palette))
            InsightStat(label: String(localized: "Busy Slots"), value: "\(busySlots.count)",
                        detail: String(localized: "slot skills where you're 80%+ full"),
                        tint: busySlots.isEmpty ? .secondary : IdleCapacityStatus.soon.color)
        }
    }

    private func summary(_ goal: SkillROIGoal) -> String {
        let time = goal.seconds.map { ReadyRoomFormat.duration($0) } ?? "?"
        if !goal.completes.isEmpty { return String(localized: "\(goal.completes.count) fits flyable · \(time)") }
        if let capacity = goal.capacity { return String(localized: "+\(capacity.added) \(String(localized: capacity.kind.titleResource)) · \(time)") }
        if !goal.improves.isEmpty { return String(localized: "\(goal.improves.count) fits better · \(time)") }
        return String(localized: "\(goal.advances.count) fits closer · \(time)")
    }

    // MARK: Filters

    private var filterBar: some View {
        HStack(spacing: EVESpacing.md) {
            ForEach(SkillROIFilter.allCases, id: \.self) { option in
                InsightToggleChip(title: Text(option.title), isOn: filter == option, tint: palette.accent) {
                    withAnimation(EVEMotion.snappy) { filterRaw = option.rawValue }
                }
            }
            Spacer()
            Button {
                copy(Array(visibleGoals.prefix(5)))
            } label: {
                Label("Copy Top 5 for EVE", systemImage: "doc.on.clipboard")
            }
            .help("Copies the top five picks as a skill plan — prerequisites first — to paste into EVE's skill queue.")
            EVEMenuPicker("Sort", selection: Binding(get: { sort }, set: { sortRaw = $0.rawValue }),
                          options: SkillROISort.allCases.map { EVEMenuOption($0, $0.title) })
        }
    }
}

// MARK:  Plan

/// The plan builder's answer: the best picks that fit the chosen budget, in training order,
/// with when each one lands after the current queue.
private struct SkillROIPlanCard: View {
    let plan: SkillROIPlan
    let start: Date
    let filter: SkillROIFilter
    @Binding var budget: SkillROIPlanBudget
    let summary: (SkillROIGoal) -> String
    let copy: () -> Void

    @Environment(ThemeManager.self) private var themeManager
    @AppStorage("skillROI.planExpanded") private var isExpanded = true

    var body: some View {
        VStack(alignment: .leading, spacing: EVESpacing.md) {
            header
            if isExpanded {
                if plan.picks.isEmpty {
                    (filter == .all
                     ? Text("Nothing fits in \(Text(budget.title)) — try a longer budget.")
                     : Text("Nothing in “\(Text(filter.title))” fits in \(Text(budget.title)) — try a longer budget or another filter."))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    VStack(alignment: .leading, spacing: EVESpacing.sm) {
                        ForEach(Array(rows.enumerated()), id: \.element.goal.id) { index, row in
                            planRow(index + 1, row.goal, finish: row.finish)
                        }
                    }
                }
            }
        }
        .padding(EVESpacing.lg)
        .eveCard(cornerRadius: EVERadius.xl)
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: EVESpacing.md) {
            Button {
                withAnimation(EVEMotion.snappy) { isExpanded.toggle() }
            } label: {
                HStack(spacing: EVESpacing.sm) {
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .rotationEffect(.degrees(isExpanded ? 90 : 0))
                        .foregroundStyle(.secondary)
                    Label("Training Plan", systemImage: "list.number")
                        .font(.eveRowTitle)
                }
            }
            .buttonStyle(.plain)
            Text(totals)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Spacer()
            EVEMenuPicker("Budget", selection: $budget,
                          options: SkillROIPlanBudget.allCases.map { EVEMenuOption($0, $0.title) })
                .help("Training time the plan may use, after your current queue")
            Button(action: copy) {
                Label("Copy Plan for EVE", systemImage: "doc.on.clipboard")
            }
            .disabled(plan.picks.isEmpty)
            .help("Copies the plan in order — prerequisites first — to paste into EVE's skill queue.")
        }
    }

    private var totals: String {
        guard !plan.picks.isEmpty else { return "" }
        var parts = [
            filter == .all ? String(localized: "\(plan.picks.count) picks")
                           : String(localized: "\(plan.picks.count) picks from “\(String(localized: filter.title))”"),
            ReadyRoomFormat.duration(plan.seconds),
            String(localized: "done \(start.addingTimeInterval(plan.seconds).formatted(date: .abbreviated, time: .omitted))"),
        ]
        if !plan.fitsCompleted.isEmpty { parts.append(String(localized: "\(plan.fitsCompleted.count) fits flyable")) }
        if !plan.fitsImproved.isEmpty { parts.append(String(localized: "\(plan.fitsImproved.count) fits better")) }
        return parts.joined(separator: " · ")
    }

    private var rows: [(goal: SkillROIGoal, finish: Date)] {
        var elapsed = 0.0
        return plan.picks.map { goal in
            elapsed += goal.seconds ?? 0
            return (goal, start.addingTimeInterval(elapsed))
        }
    }

    private func planRow(_ number: Int, _ goal: SkillROIGoal, finish: Date) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: EVESpacing.md) {
            Text(verbatim: "\(number)")
                .font(.eveCaptionBold.monospacedDigit())
                .foregroundStyle(.tertiary)
                .frame(width: 20, alignment: .trailing)
            VStack(alignment: .leading, spacing: 1) {
                Text(verbatim: "\(goal.name) \(ReadyRoomFormat.roman(goal.level))")
                    .font(.eveCaptionBold)
                if goal.plan.count > 1 {
                    Text("with \(goal.plan.filter { $0.skillID != goal.skillID }.map { "\($0.name) \(ReadyRoomFormat.roman($0.requiredLevel))" }.joined(separator: ", "))")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }
            }
            Text(summary(goal))
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Spacer()
            Text(finish.formatted(date: .abbreviated, time: .shortened))
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
                .help("Finishes, training the plan in order after your current queue")
        }
    }
}

// MARK:  Card

private struct SkillROICard: View {
    let goal: SkillROIGoal
    let rank: Int
    let best: Double
    let pinned: Set<Int>
    let reports: [Int: ReadyRoomReport]
    let copy: () -> Void

    @Environment(ThemeManager.self) private var themeManager

    var body: some View {
        HStack(alignment: .top, spacing: EVESpacing.lg) {
            Text(verbatim: "\(rank)")
                .font(.eveStatCompact)
                .foregroundStyle(.tertiary)
                .frame(width: 32, alignment: .trailing)

            VStack(alignment: .leading, spacing: EVESpacing.sm) {
                HStack(alignment: .firstTextBaseline, spacing: EVESpacing.md) {
                    Text(verbatim: "\(goal.name) \(ReadyRoomFormat.roman(goal.level))")
                        .font(.eveRowTitle)
                    if goal.isQuickWin { EVEChip(Text("Quick win"), tint: .green) }
                    Spacer()
                    Text(goal.seconds.map { ReadyRoomFormat.duration($0) } ?? String(localized: "Time unknown"))
                        .font(.eveCalloutSemibold.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                valueBar
                if goal.plan.count > 1 {
                    Text("Trains \(goal.plan.map { "\($0.name) \(ReadyRoomFormat.roman($0.requiredLevel))" }.joined(separator: " → "))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                unlocks
            }

            Button(action: copy) {
                Image(systemName: "doc.on.clipboard")
            }
            .buttonStyle(.borderless)
            .help("Copy this pick as an EVE skill plan")
        }
        .padding(EVESpacing.lg)
        .eveCard(cornerRadius: EVERadius.xl)
    }

    /// Length is the score against the best pick; segments show where the value comes from.
    private var valueBar: some View {
        let parts = valueParts
        let value = max(goal.breakdown.value, 0.0001)
        return GeometryReader { proxy in
            let width = proxy.size.width * min(goal.score / max(best, 0.0001), 1)
            ZStack(alignment: .leading) {
                Capsule().fill(.quaternary)
                HStack(spacing: 1) {
                    ForEach(parts, id: \.label) { part in
                        Rectangle().fill(part.color).frame(width: max(width * part.value / value - 1, 1))
                    }
                }
                .frame(width: width, alignment: .leading)
                .clipShape(Capsule())
            }
        }
        .frame(height: 4)
        .frame(maxWidth: 240)
        .help(Text(parts.map { "\($0.label) \(Int(($0.value / value * 100).rounded()))%" }.joined(separator: " · ")))
        .accessibilityHidden(true)
    }

    private var valueParts: [(label: String, value: Double, color: Color)] {
        let palette = themeManager.palette
        let b = goal.breakdown
        return [
            (String(localized: "Makes flyable"), b.completes, ReadyRoomTier.ready.color(palette)),
            (String(localized: "Brings closer"), b.advances, ReadyRoomTier.train.color(palette)),
            (String(localized: "Improves"), b.performance, palette.accent),
            (String(localized: "Slots"), b.capacity, IdleCapacityStatus.soon.color),
        ].filter { $0.1 > 0 }
    }

    @ViewBuilder
    private var unlocks: some View {
        VStack(alignment: .leading, spacing: EVESpacing.xs) {
            if !goal.completes.isEmpty {
                fitLine(Text("Makes flyable"), fits: goal.completes, tint: ReadyRoomTier.ready.color(themeManager.palette))
            }
            if !goal.advances.isEmpty {
                fitLine(Text("Brings closer"), fits: goal.advances, tint: ReadyRoomTier.train.color(themeManager.palette))
            }
            if !goal.improves.isEmpty {
                improvesLine
            }
            if let capacity = goal.capacity {
                HStack(spacing: EVESpacing.sm) {
                    Image(systemName: capacity.kind.systemImage)
                        .foregroundStyle(IdleCapacityStatus.soon.color)
                    Text("+\(capacity.added) \(Text(capacity.kind.title)) slots")
                        .font(.eveCaptionBold)
                    Text("on \(capacity.limit) · \(Int((capacity.busyShare * 100).rounded()))% busy")
                        .font(.caption)
                        .foregroundStyle(capacity.busyShare >= 0.8 ? IdleCapacityStatus.soon.color : .secondary)
                }
            }
        }
    }

    private var improvesLine: some View {
        let tint = themeManager.palette.accent
        let shown = goal.improves.prefix(4).compactMap { delta in reports[delta.fittingID].map { (delta, $0) } }
        return HStack(spacing: EVESpacing.sm) {
            Text("Improves")
                .font(.eveCaptionBold)
                .foregroundStyle(tint)
            ForEach(shown, id: \.0.fittingID) { delta, report in
                Button {
                    AppRouter.shared.pendingReadyRoomFittingID = report.fittingID
                    AppRouter.shared.pendingSection = .readyRoom
                } label: {
                    HStack(spacing: EVESpacing.xs) {
                        CachedAsyncImage(url: EVEImageURL.typeIcon(report.shipTypeID, size: 64)) { image in
                            image.resizable()
                        } placeholder: {
                            RoundedRectangle(cornerRadius: 3).fill(.quaternary)
                        }
                        .frame(width: 14, height: 14)
                        .clipShape(RoundedRectangle(cornerRadius: 3))
                        if pinned.contains(report.fittingID) {
                            Image(systemName: "pin.fill").font(.eveNano)
                        }
                        Text(verbatim: report.name).lineLimit(1)
                        Text(delta.headlineText)
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                }
                .buttonStyle(.plain)
                .modifier(ReadyRoomChipStyle(tint: tint))
                .help(Text(delta.detailsText))
            }
            if goal.improves.count > shown.count {
                Text("+\(goal.improves.count - shown.count)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func fitLine(_ label: Text, fits: [ReadyRoomReport], tint: Color) -> some View {
        HStack(spacing: EVESpacing.sm) {
            label
                .font(.eveCaptionBold)
                .foregroundStyle(tint)
            ForEach(fits.prefix(4)) { report in
                Button {
                    AppRouter.shared.pendingReadyRoomFittingID = report.fittingID
                    AppRouter.shared.pendingSection = .readyRoom
                } label: {
                    HStack(spacing: EVESpacing.xs) {
                        CachedAsyncImage(url: EVEImageURL.typeIcon(report.shipTypeID, size: 64)) { image in
                            image.resizable()
                        } placeholder: {
                            RoundedRectangle(cornerRadius: 3).fill(.quaternary)
                        }
                        .frame(width: 14, height: 14)
                        .clipShape(RoundedRectangle(cornerRadius: 3))
                        if pinned.contains(report.fittingID) {
                            Image(systemName: "pin.fill").font(.eveNano)
                        }
                        Text(verbatim: report.name).lineLimit(1)
                    }
                }
                .buttonStyle(.plain)
                .modifier(ReadyRoomChipStyle(tint: tint))
                .help(Text("Open \(report.name) in the Ready Room"))
            }
            if fits.count > 4 {
                Text("+\(fits.count - 4)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

// MARK:  Stat delta text

extension FitStatDelta {
    /// "+3.2% DPS" — the stat that improves most, or "Cap stable".
    var headlineText: String {
        if let best = headline {
            return "+\(best.gain.formatted(.percent.precision(.fractionLength(1)))) \(best.stat.name)"
        }
        return becomesCapStable ? String(localized: "Cap stable") : ""
    }

    /// Every stat that improves, for a tooltip.
    var detailsText: String {
        var parts = Stat.allCases.filter { gain($0) > 0 }.map {
            "\($0.name) +\(gain($0).formatted(.percent.precision(.fractionLength(1))))"
        }
        if becomesCapStable { parts.append(String(localized: "becomes cap stable")) }
        return parts.joined(separator: " · ")
    }
}

extension FitStatDelta.Stat {
    var name: String {
        switch self {
        case .dps:       String(localized: "DPS")
        case .ehp:       String(localized: "EHP")
        case .tank:      String(localized: "repair")
        case .speed:     String(localized: "speed")
        case .align:     String(localized: "align")
        case .lockRange: String(localized: "lock range")
        }
    }
}
