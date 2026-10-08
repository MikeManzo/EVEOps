//
// This file is part of EVEOps.
//
// EVEOps is free software: you can redistribute it and/or modify
// it under the terms of the GNU General Public License as published by
// the Free Software Foundation, version 3 or later.
//
// Copyright (c) 2026 CitizenCoder
//

import AppKit
import SwiftUI

/// The Ready Room's Hangar Forge tab: pick a hull you own and a goal, and get the strongest
/// fit you can put on it from parts you already own.
struct HangarForgeView: View {
    let snapshot: ReadyRoomSnapshot

    @Environment(AccountManager.self) private var accountManager
    @Environment(ThemeManager.self) private var themeManager
    @AppStorage("hangarForge.goal") private var goalRaw = HangarForgeGoal.balanced.rawValue
    @AppStorage("hangarForge.capStable") private var requireCapStable = false
    @AppStorage("hangarForge.anywhere") private var anywhere = false
    @AppStorage("hangarForge.stripShips") private var includeFittedElsewhere = false
    @AppStorage("hangarForge.utilities") private var utilitiesRaw = ""
    @AppStorage("hangarForge.buyBudget") private var buyBudget: Double = 0
    @State private var showUtilities = false
    @State private var className: String?
    @State private var hullItemID: Int?

    private var service: HangarForgeService { .shared }
    private var readyRoom: ReadyRoomService { .shared }
    private var palette: EVEPalette { themeManager.palette }
    private var characterID: Int { snapshot.characterID }
    private var catalog: HangarForgeCatalog? { service.catalogs[characterID] }
    private var run: HangarForgeRun? { service.runs[characterID] }
    private var goal: HangarForgeGoal { HangarForgeGoal(rawValue: goalRaw) ?? .balanced }

    private var utilities: Set<HangarForgeUtility> {
        Set(utilitiesRaw.split(separator: ",").compactMap { HangarForgeUtility(rawValue: String($0)) })
    }

    private var options: HangarForgeOptions {
        HangarForgeOptions(goal: goal, requireCapStable: requireCapStable, anywhere: anywhere,
                           includeFittedElsewhere: includeFittedElsewhere,
                           includeCorporation: readyRoom.includeCorporation,
                           utilities: utilities, buyBudget: buyBudget > 0 ? buyBudget : nil)
    }

    /// Budgets offered for buying modules; 0 builds from owned parts only.
    private static let budgets: [Double] = [0, 5_000_000, 20_000_000, 50_000_000, 100_000_000, 250_000_000, 1_000_000_000]

    var body: some View {
        VStack(alignment: .leading, spacing: EVESpacing.xl) {
            if let catalog, !catalog.hulls.isEmpty {
                controls(catalog)
                if let run {
                    runView(run, catalog: catalog)
                } else {
                    EVEEmptyState("Forge a Fit", systemImage: "hammer",
                                  message: Text("Pick a hull and a goal. The forge tries the modules, ammo and drones you own and builds the strongest fit it can."))
                        .frame(minHeight: 240)
                }
            } else if catalog != nil {
                EVEEmptyState("No Ships", systemImage: "ferry",
                              message: Text("You don't own a ship the forge can fit."))
                    .frame(minHeight: 240)
            } else if let error = service.catalogErrors[characterID] {
                EVEEmptyState(title: Text("Couldn’t Load Your Ships"), systemImage: "exclamationmark.triangle",
                              message: Text(error), tint: .orange)
            } else {
                EVELoadingPane("Finding your ships…")
                    .frame(minHeight: 240)
            }
        }
        .task(id: snapshot.input.holdings.hashValue) {
            guard let account = accountManager.selectedAccount,
                  let token = try? await accountManager.validToken(for: account) else { return }
            await service.loadCatalog(snapshot, token: token)
        }
        .onChange(of: run?.hullItemID, initial: true) { _, hullID in
            // A fit restored from last time: show its hull in the pickers.
            guard hullItemID == nil, let hullID,
                  let option = catalog?.hulls.first(where: { $0.id == hullID }) else { return }
            className = option.className
            hullItemID = hullID
        }
    }

    // MARK:  Controls

    private func hulls(in catalog: HangarForgeCatalog) -> [HangarForgeHullOption] {
        let name = selectedClass(catalog)
        return catalog.hulls.filter { $0.className == name }
    }

    private func selectedClass(_ catalog: HangarForgeCatalog) -> String {
        let classes = catalog.classes.map(\.name)
        if let className, classes.contains(className) { return className }
        // Default to the class of the ship being flown, else the first.
        let flying = catalog.hulls.first { $0.hull.typeID == snapshot.pilot.shipTypeID }?.className
        return flying ?? classes.first ?? ""
    }

    private func selectedHull(_ catalog: HangarForgeCatalog) -> HangarForgeHullOption? {
        let options = hulls(in: catalog)
        return options.first { $0.id == hullItemID } ?? options.first { $0.hull.isFlyable } ?? options.first
    }

    private func controls(_ catalog: HangarForgeCatalog) -> some View {
        let hull = selectedHull(catalog)
        let isRunning = run?.isRunning == true
        return VStack(alignment: .leading, spacing: EVESpacing.md) {
            HStack(spacing: EVESpacing.md) {
                EVEMenuPicker("Class", selection: Binding(get: { selectedClass(catalog) }, set: {
                    className = $0
                    hullItemID = nil
                }), options: catalog.classes.map { EVEMenuOption($0.name, verbatim: "\($0.name) (\($0.count))") })
                EVEMenuPicker("Hull", selection: Binding(get: { hull?.id ?? 0 }, set: { hullItemID = $0 }),
                              options: hulls(in: catalog).map { option in
                                  EVEMenuOption(option.id, verbatim: hullLabel(option),
                                                systemImage: option.hull.isFlyable ? nil : "lock.fill")
                              })
                Spacer()
                Picker("Goal", selection: $goalRaw) {
                    ForEach(HangarForgeGoal.allCases) { Text($0.title).tag($0.rawValue) }
                }
                .labelsHidden()
                .eveSegmentedPicker()
                .fixedSize()
                .help(goalHelp)
            }
            HStack(spacing: EVESpacing.sm) {
                toggleChip("Cap Stable", systemImage: "bolt.batteryblock", isOn: goal.requiresCapStable || requireCapStable,
                           help: goal.requiresCapStable ? "Kiting fits are always cap stable"
                                                        : "Only fits that can run every module indefinitely") {
                    requireCapStable.toggle()
                }
                .disabled(goal.requiresCapStable)
                toggleChip("Any Station", systemImage: "map", isOn: anywhere,
                           help: anywhere ? "Using parts from every station — the result lists what to haul"
                                          : "Using only parts in the hull's station") { anywhere.toggle() }
                toggleChip("Strip Other Ships", systemImage: "wrench.adjustable", isOn: includeFittedElsewhere,
                           help: "Also use modules fitted to your other ships") { includeFittedElsewhere.toggle() }
                toggleChip("Corp Hangars", systemImage: "building.2", isOn: readyRoom.includeCorporation,
                           help: "Also use parts in corporation hangars (needs the Director role)") {
                    readyRoom.includeCorporation.toggle()
                }
                utilityChip
                EVEMenuPicker("Buy", selection: $buyBudget, options: Self.budgets.map { budget in
                    EVEMenuOption(budget, verbatim: budget == 0 ? String(localized: "Owned parts only")
                                                                : String(localized: "Buy up to \(EVEFormatters.formatISKShort(budget))"),
                                  systemImage: budget == 0 ? "shippingbox" : "cart")
                })
                .help("Let the forge buy modules and rigs at Jita prices to fill empty or weak slots")
                Spacer()
                if isRunning {
                    Button("Stop") { service.cancel(characterID) }
                }
                Button {
                    forge(hull)
                } label: {
                    Label("Forge", systemImage: "hammer.fill")
                }
                .buttonStyle(.borderedProminent)
                .tint(palette.accent)
                .disabled(hull.map { !$0.hull.isFlyable || !$0.hull.isSupported } ?? true || isRunning)
                .keyboardShortcut(.return, modifiers: .command)
            }
            if let hull { hullNote(hull, catalog: catalog) }
        }
        .padding(EVESpacing.lg)
        .eveCard(cornerRadius: EVERadius.xl)
    }

    private var utilityChip: some View {
        let count = utilities.count
        return Button {
            showUtilities.toggle()
        } label: {
            Label(count == 0 ? String(localized: "Utility") : String(localized: "Utility (\(count))"),
                  systemImage: "wrench.and.screwdriver")
        }
        .buttonStyle(.plain)
        .modifier(ReadyRoomChipStyle(tint: count > 0 ? palette.accent : .secondary))
        .help("Keep slots for tackle, ewar, a prop mod or other jobs damage and tank don't measure")
        .popover(isPresented: $showUtilities, arrowEdge: .bottom) {
            VStack(alignment: .leading, spacing: EVESpacing.sm) {
                Text("Keep a slot for")
                    .font(.eveCaptionBold)
                    .foregroundStyle(.secondary)
                ForEach(HangarForgeUtility.allCases) { role in
                    Toggle(isOn: Binding(get: { utilities.contains(role) }, set: { _ in toggleUtility(role) })) {
                        Label(role.title, systemImage: role.systemImage)
                    }
                    .toggleStyle(.checkbox)
                }
            }
            .padding(EVESpacing.lg)
        }
    }

    private func toggleUtility(_ role: HangarForgeUtility) {
        var set = utilities
        if set.contains(role) { set.remove(role) } else { set.insert(role) }
        utilitiesRaw = set.map(\.rawValue).sorted().joined(separator: ",")
    }

    private func hullLabel(_ option: HangarForgeHullOption) -> String {
        let packaged = option.hull.isAssembled ? "" : String(localized: " · packaged")
        return "\(option.displayName) · \(option.placeName)\(packaged)"
    }

    private var goalHelp: String {
        switch goal {
        case .balanced: String(localized: "Damage and tank weighted equally")
        case .damage:   String(localized: "Most damage, with some tank where slots allow")
        case .tank:     String(localized: "Most effective HP and repair, with some damage")
        case .kite:     String(localized: "Fastest, cap stable, with damage next")
        }
    }

    @ViewBuilder
    private func hullNote(_ option: HangarForgeHullOption, catalog: HangarForgeCatalog) -> some View {
        if !option.hull.isSupported {
            note(Text("Strategic Cruisers aren’t supported yet — their slots come from subsystems."), tint: .orange)
        } else if !option.hull.isFlyable {
            let names = option.hull.missingSkills.sorted { $0.key < $1.key }.map { skill, level in
                "\(catalog.skillNames[skill] ?? String(localized: "Skill \(skill)")) \(ReadyRoomFormat.roman(level))"
            }
            note(Text("Train \(names.formatted(.list(type: .and))) to fly this hull."), tint: .orange)
        }
    }

    private func note(_ text: Text, tint: Color) -> some View {
        Label { text } icon: { Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(tint) }
            .font(.caption)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func toggleChip(_ title: LocalizedStringKey, systemImage: String, isOn: Bool, help: LocalizedStringKey,
                            action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
        }
        .buttonStyle(.plain)
        .modifier(ReadyRoomChipStyle(tint: isOn ? palette.accent : .secondary))
        .help(help)
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }

    private func forge(_ option: HangarForgeHullOption?) {
        guard let option else { return }
        hullItemID = option.id
        Task {
            guard let account = accountManager.selectedAccount,
                  let token = try? await accountManager.validToken(for: account) else { return }
            service.forge(option.hull, options: options, snapshot: snapshot, token: token)
        }
    }

    // MARK:  Run

    @ViewBuilder
    private func runView(_ run: HangarForgeRun, catalog: HangarForgeCatalog) -> some View {
        if let result = run.result {
            HangarForgeResultView(result: result, catalog: catalog, places: run.places, holdings: snapshot.input.holdings,
                                  types: run.types.merging(catalog.types) { run, _ in run },
                                  comparisons: run.comparisons,
                                  isRestored: run.isRestored,
                                  isStale: run.options != options || selectedHull(catalog)?.id != run.hullItemID)
        } else if let error = run.error {
            EVEEmptyState(title: Text("Couldn’t Forge a Fit"), systemImage: "exclamationmark.triangle",
                          message: Text(error), tint: .orange)
                .frame(minHeight: 240)
        } else {
            VStack(alignment: .leading, spacing: EVESpacing.sm) {
                HStack {
                    Text(run.phase ?? String(localized: "Trying fits…"))
                    Spacer()
                    Text(verbatim: "\(run.done.formatted()) / \(run.budget.formatted())")
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
                .font(.callout)
                EVEProgressBar(value: run.fraction, tint: palette.accent, height: 4)
            }
            .padding(EVESpacing.lg)
            .eveCard(cornerRadius: EVERadius.xl)
        }
    }
}

// MARK:  Result

private struct HangarForgeResultView: View {
    let result: HangarForgeResult
    let catalog: HangarForgeCatalog
    let places: [Int: ReadyRoomPlace]
    let holdings: [ReadyRoomHolding]
    /// Names for every type the result mentions.
    let types: [Int: ESIType]
    /// The pilot's saved fits for this hull, to compare against.
    let comparisons: [HangarForgeComparison]
    /// Brought back from an earlier launch.
    let isRestored: Bool
    /// The controls no longer match what this result was built with.
    let isStale: Bool

    @Environment(ThemeManager.self) private var themeManager
    @State private var copied = false
    @State private var copiedMultibuy = false

    private var palette: EVEPalette { themeManager.palette }
    private var hullOption: HangarForgeHullOption? { catalog.hulls.first { $0.id == result.hull.itemID } }
    private var hullName: String { hullOption?.displayName ?? name(result.hull.typeID) }

    private func name(_ typeID: Int) -> String {
        types[typeID]?.name ?? String(localized: "Type \(typeID)")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: EVESpacing.lg) {
            header
            if isRestored && !isStale {
                Label("Your last forged fit, recalculated with today’s skills and assets.", systemImage: "clock.arrow.circlepath")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if isStale {
                Label("Options changed since this fit was forged — press Forge to rebuild.", systemImage: "arrow.clockwise")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if !result.missingUtilities.isEmpty {
                Label("No slot kept for \(result.missingUtilities.map(\.title).formatted(.list(type: .and))) — nothing you own (or can buy) for it fits this hull within CPU and powergrid.",
                      systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }
            statTiles
            HStack(alignment: .top, spacing: EVESpacing.xl) {
                VStack(alignment: .leading, spacing: EVESpacing.lg) {
                    slotsSection
                    dronesSection
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                VStack(alignment: .leading, spacing: EVESpacing.lg) {
                    fittingSection
                    buySection
                    haulSection
                }
                // As wide as its longest line, so pickup locations show in full.
                .frame(minWidth: 260, alignment: .leading)
                .fixedSize(horizontal: true, vertical: false)
            }
            comparisonSection
            footer
        }
        .padding(EVESpacing.lg)
        .eveCard(cornerRadius: EVERadius.xl)
    }

    // MARK: Header

    private var header: some View {
        HStack(spacing: EVESpacing.md) {
            CachedAsyncImage(url: EVEImageURL.typeRender(result.hull.typeID, size: 128)) { image in
                image.resizable()
            } placeholder: {
                RoundedRectangle(cornerRadius: EVERadius.md).fill(.quaternary)
            }
            .frame(width: 56, height: 56)
            .clipShape(RoundedRectangle(cornerRadius: EVERadius.md))
            VStack(alignment: .leading, spacing: EVESpacing.xxs) {
                HStack(spacing: EVESpacing.sm) {
                    Text(hullName).font(.title2.bold())
                    EVEChip(Text(result.options.goal.title), tint: palette.accent, size: .regular)
                }
                Text(verbatim: [hullOption?.className, hullOption?.placeName].compactMap(\.self).joined(separator: " · "))
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(EFTSerializer.export(fitting: entry, typeNames: types.mapValues(\.name)),
                                               forType: .string)
                copied = true
            } label: {
                Label(copied ? "Copied" : "Copy EFT", systemImage: copied ? "checkmark" : "doc.on.doc")
            }
            .help("Copy the fit in EFT format, to paste into EVE or another fitting tool")
            Button {
                var charges: [String: Int] = [:]
                for pick in result.picks { charges[pick.flag] = pick.chargeTypeID }
                AppRouter.shared.pendingSimulatorFitting = SimulatorHandoff(fitting: entry, charges: charges)
                AppRouter.shared.pendingSection = .fittings
            } label: {
                Label("Open in Simulator", systemImage: "slider.horizontal.3")
            }
            .buttonStyle(.borderedProminent)
            .tint(palette.accent)
        }
        .onChange(of: result.evaluations) { _, _ in
            copied = false
            copiedMultibuy = false
        }
    }

    /// The fit as a saved-fitting entry — modules in their slots, ammo in cargo, drones in
    /// the bay — for the Simulator and EFT export.
    private var entry: SavedFittingEntry {
        var items = result.picks.map { ESIFittingItem(flag: $0.flag, quantity: 1, typeId: $0.typeID) }
        var charges: [Int] = []
        for pick in result.picks { if let charge = pick.chargeTypeID, !charges.contains(charge) { charges.append(charge) } }
        items += charges.map { ESIFittingItem(flag: "Cargo", quantity: result.needs[$0] ?? 1, typeId: $0) }
        let drones = Dictionary(grouping: result.drones, by: \.self)
        items += drones.keys.sorted().map { ESIFittingItem(flag: "DroneBay", quantity: drones[$0]!.count, typeId: $0) }
        return SavedFittingEntry(
            characterID: 0, characterName: "", fittingId: 0,
            name: String(localized: "\(hullName) — \(result.options.goal.title) (Hangar Forge)"),
            fittingDescription: "", shipTypeId: result.hull.typeID, shipTypeName: name(result.hull.typeID),
            shipClassName: hullOption?.className ?? "", items: items
        )
    }

    // MARK: Stats

    private var statTiles: some View {
        let performance = result.performance
        let stats = result.stats
        return HStack(spacing: EVESpacing.md) {
            MetricTileView(icon: "flame.fill", color: .orange,
                           value: performance.dps.formatted(.number.precision(.fractionLength(0))),
                           label: String(localized: "DPS"),
                           subLabel: stats.droneDPS > 0
                               ? String(localized: "\(stats.droneDPS.formatted(.number.precision(.fractionLength(0)))) from drones") : nil)
            MetricTileView(icon: "shield.fill", color: .blue,
                           value: performance.ehp.formatted(.number.notation(.compactName).precision(.significantDigits(3))),
                           label: String(localized: "EHP"), subLabel: String(localized: "average of damage types"))
            MetricTileView(icon: "cross.case.fill", color: .green,
                           value: performance.tank.formatted(.number.precision(.fractionLength(1))),
                           label: String(localized: "Repair HP/s"))
            MetricTileView(icon: "speedometer", color: .cyan,
                           value: performance.speed.formatted(.number.precision(.fractionLength(0))),
                           label: String(localized: "m/s"),
                           subLabel: String(localized: "align \(performance.alignTime.formatted(.number.precision(.fractionLength(1)))) s"))
            MetricTileView(icon: "bolt.fill", color: performance.capStable ? .yellow : .red,
                           value: performance.capStable ? String(localized: "Stable") : capRunsDry(stats),
                           label: String(localized: "Capacitor"))
        }
    }

    private func capRunsDry(_ stats: SimStats) -> String {
        guard let seconds = stats.capDepletesIn else { return String(localized: "Unstable") }
        return ReadyRoomFormat.duration(seconds)
    }

    // MARK: Slots

    private var slotsSection: some View {
        EVEInspectorSection("Modules") {
            VStack(alignment: .leading, spacing: EVESpacing.md) {
                ForEach([SimSlotCategory.high, .medium, .low, .rig], id: \.self) { category in
                    let picks = result.picks.filter { $0.category == category }
                    let open = result.openSlots[category] ?? 0
                    if !picks.isEmpty || open > 0 {
                        VStack(alignment: .leading, spacing: EVESpacing.xxs) {
                            Text(category.displayName)
                                .font(.eveMicroBold)
                                .foregroundStyle(.tertiary)
                            ForEach(picks) { pick in pickRow(pick) }
                            if open > 0 { openRow(open) }
                        }
                    }
                }
            }
        }
    }

    private func pickRow(_ pick: HangarForgePick) -> some View {
        var badges: [Badge] = []
        if let role = pick.utility {
            badges.append(Badge(text: role.title, tint: palette.accent,
                                help: String(localized: "Kept for \(role.title) — the search doesn't take it out")))
        }
        if pick.isPurchase, let price = result.prices[pick.typeID] {
            badges.append(Badge(text: String(localized: "Buy · \(EVEFormatters.formatISKShort(price))"), tint: .orange,
                                help: String(localized: "You don't own this one — about \(EVEFormatters.formatISKShort(price)) ISK in Jita")))
        }
        return row(typeID: pick.typeID, title: name(pick.typeID),
                   detail: pick.chargeTypeID.map { String(localized: "Loaded with \(name($0))") },
                   without: pick.without, badges: badges)
    }

    private struct Badge: Hashable {
        let text: String
        let tint: Color
        let help: String
    }

    private func openRow(_ count: Int) -> some View {
        HStack(spacing: EVESpacing.md) {
            RoundedRectangle(cornerRadius: EVERadius.xs)
                .strokeBorder(.quaternary, style: StrokeStyle(lineWidth: 1, dash: [3]))
                .frame(width: 24, height: 24)
            Text(count == 1 ? "1 slot left open" : "\(count) slots left open")
                .font(.callout)
                .foregroundStyle(.secondary)
            Spacer()
        }
        .help("Nothing you own improves the fit in this slot. Use Utility to keep it for tackle, ewar or a prop mod, or Buy to fill it from the market")
        .padding(.vertical, EVESpacing.xxs)
    }

    /// A module or drone line: icon, name, an optional detail, and what it adds to the fit.
    private func row(typeID: Int, title: String, detail: String?, without: FitPerformance?,
                     badges: [Badge] = []) -> some View {
        let delta = without.map { SkillPerformanceEngine.delta(fittingID: 0, from: $0, to: result.performance) }
        return HStack(spacing: EVESpacing.md) {
            CachedAsyncImage(url: EVEImageURL.typeIcon(typeID, size: 64)) { image in
                image.resizable()
            } placeholder: {
                RoundedRectangle(cornerRadius: EVERadius.xs).fill(.quaternary)
            }
            .frame(width: 24, height: 24)
            .clipShape(RoundedRectangle(cornerRadius: EVERadius.xs))
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: EVESpacing.xs) {
                    Text(title).font(.callout).lineLimit(1).eveTruncationHelp(title)
                    ForEach(badges, id: \.self) { badge in
                        EVEChip(Text(badge.text), tint: badge.tint).help(badge.help)
                    }
                }
                if let detail {
                    Text(detail).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                }
            }
            Spacer(minLength: EVESpacing.sm)
            if let delta, !delta.isEmpty {
                Text(contributionText(delta, without: without))
                    .font(.eveCaptionBold)
                    .foregroundStyle(.green)
                    .help(delta.detailsText)
            } else if delta != nil {
                Text("support")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .help("Doesn’t raise DPS, tank or speed by itself — the fit needs it, for CPU or powergrid or to work alongside another module")
            }
        }
        .padding(.vertical, EVESpacing.xxs)
        .accessibilityElement(children: .combine)
    }

    /// "+29.4% EHP" — the stat the goal values most in what this part adds, falling back
    /// to its biggest percentage gain when the goal values none of it.
    private func contributionText(_ delta: FitStatDelta, without: FitPerformance?) -> String {
        guard let without,
              let stat = HangarForgeEngine.headline(without: without, with: result.performance, goal: result.options.goal),
              delta.gain(stat) > 0 else { return delta.headlineText }
        return "+\(delta.gain(stat).formatted(.percent.precision(.fractionLength(1)))) \(stat.name)"
    }

    @ViewBuilder
    private var dronesSection: some View {
        if !result.drones.isEmpty {
            EVEInspectorSection("Drones") {
                let counts = Dictionary(grouping: result.drones, by: \.self)
                VStack(alignment: .leading, spacing: EVESpacing.xxs) {
                    ForEach(counts.keys.sorted(), id: \.self) { typeID in
                        row(typeID: typeID, title: "\(counts[typeID]!.count)× \(name(typeID))", detail: nil,
                            without: result.withoutDrones[typeID])
                    }
                }
            }
        }
    }

    // MARK: Fitting

    private var fittingSection: some View {
        EVEInspectorSection("Fitting") {
            VStack(spacing: EVESpacing.sm) {
                meter("CPU", used: result.stats.cpuUsed, total: result.stats.cpuTotal, unit: "tf")
                meter("Powergrid", used: result.stats.powerUsed, total: result.stats.powerTotal, unit: "MW")
                if result.stats.calibrationTotal > 0 {
                    meter("Calibration", used: result.stats.calibrationUsed, total: result.stats.calibrationTotal, unit: "")
                }
            }
        }
    }

    private func meter(_ label: LocalizedStringKey, used: Double, total: Double, unit: String) -> some View {
        let ratio = total > 0 ? used / total : 0
        return VStack(alignment: .leading, spacing: EVESpacing.xxs) {
            HStack {
                Text(label).font(.callout)
                Spacer()
                Text(verbatim: "\(used.formatted(.number.precision(.fractionLength(0...1)))) / \(total.formatted(.number.precision(.fractionLength(0...1)))) \(unit)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            EVEProgressBar(value: ratio, tint: ratio > 0.9 ? .orange : .green, height: 4)
        }
        .accessibilityElement(children: .combine)
    }

    // MARK: Buy

    @ViewBuilder
    private var buySection: some View {
        if !result.purchases.isEmpty {
            EVEInspectorSection("Buy") {
                VStack(alignment: .leading, spacing: EVESpacing.xs) {
                    ForEach(result.purchases.keys.sorted { name($0) < name($1) }, id: \.self) { typeID in
                        let quantity = result.purchases[typeID] ?? 0
                        HStack {
                            Text(verbatim: "\(quantity)× \(name(typeID))")
                                .font(.callout)
                                .lineLimit(1)
                            Spacer(minLength: EVESpacing.md)
                            Text(EVEFormatters.formatISKShort(Double(quantity) * (result.prices[typeID] ?? 0)))
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(.secondary)
                        }
                    }
                    Divider()
                    HStack {
                        Text("Total").font(.callout.bold())
                        Spacer()
                        Text(EVEFormatters.formatISKShort(result.purchaseCost))
                            .font(.callout.bold().monospacedDigit())
                    }
                    Button {
                        let lines = result.purchases.keys.sorted { name($0) < name($1) }
                            .map { "\(name($0)) \(result.purchases[$0] ?? 0)" }
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(lines.joined(separator: "\n"), forType: .string)
                        copiedMultibuy = true
                    } label: {
                        Label(copiedMultibuy ? "Copied" : "Copy Multibuy", systemImage: copiedMultibuy ? "checkmark" : "cart")
                    }
                    .help("Copy the list in EVE's Multibuy format")
                    Text("Jita lowest sell prices.")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
        }
    }

    // MARK: Compare

    /// The forged fit beside each saved fit for this hull type, with the forged fit's
    /// change on every stat.
    @ViewBuilder
    private var comparisonSection: some View {
        if !comparisons.isEmpty {
            EVEInspectorSection("Against Your Saved Fits") {
                Grid(alignment: .trailing, horizontalSpacing: EVESpacing.lg, verticalSpacing: EVESpacing.sm) {
                    GridRow {
                        Text("").gridColumnAlignment(.leading)
                        ForEach(Self.compared, id: \.self) { stat in
                            Text(stat.name.capitalized).font(.eveMicroBold).foregroundStyle(.tertiary)
                        }
                    }
                    GridRow {
                        VStack(alignment: .leading, spacing: 0) {
                            Text("Forged fit").font(.callout.bold())
                            if let className = hullOption?.className {
                                Text(className).font(.caption2).foregroundStyle(.secondary)
                            }
                        }
                        ForEach(Self.compared, id: \.self) { stat in
                            Text(statValue(stat, result.performance)).font(.callout.monospacedDigit())
                        }
                    }
                    ForEach(comparisons) { comparison in
                        Divider().gridCellUnsizedAxes(.horizontal)
                        comparisonRow(comparison)
                    }
                }
                Text("Saved fits are calculated with your current skills and implants. The percentage is how the forged fit compares — green where it's better.")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private static let compared: [FitStatDelta.Stat] = [.dps, .ehp, .tank, .speed]

    private func comparisonRow(_ comparison: HangarForgeComparison) -> some View {
        GridRow {
            Button {
                AppRouter.shared.pendingReadyRoomFittingID = comparison.fittingID
            } label: {
                HStack(spacing: EVESpacing.xs) {
                    Text(comparison.name).font(.callout).lineLimit(1)
                    if let tier = comparison.tier {
                        Image(systemName: tier.systemImage)
                            .foregroundStyle(tier.color(palette))
                            .help(Text(tier.title))
                    }
                    if !comparison.fitsNow {
                        EVEChip(Text("Over CPU/PG"), tint: .red)
                    }
                }
            }
            .buttonStyle(.plain)
            .help("Show this fit in Saved Fits")
            ForEach(Self.compared, id: \.self) { stat in
                VStack(alignment: .trailing, spacing: 0) {
                    Text(statValue(stat, comparison.performance)).font(.callout.monospacedDigit())
                    change(stat, saved: comparison.performance)
                }
            }
        }
    }

    /// "+12%" in green when the forged fit is better on `stat`, "−8%" in red when worse.
    @ViewBuilder
    private func change(_ stat: FitStatDelta.Stat, saved: FitPerformance) -> some View {
        let before = value(stat, saved), after = value(stat, result.performance)
        if before > 0, abs(after / before - 1) >= 0.005 {
            let ratio = after / before - 1
            Text(verbatim: "\(ratio > 0 ? "+" : "")\(ratio.formatted(.percent.precision(.fractionLength(0))))")
                .font(.caption2.bold().monospacedDigit())
                .foregroundStyle(ratio > 0 ? .green : .red)
        } else {
            Text(verbatim: before > 0 || after == 0 ? "=" : "new")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
    }

    private func value(_ stat: FitStatDelta.Stat, _ performance: FitPerformance) -> Double {
        switch stat {
        case .dps:       performance.dps
        case .ehp:       performance.ehp
        case .tank:      performance.tank
        case .speed:     performance.speed
        case .align:     performance.alignTime
        case .lockRange: performance.lockRange
        }
    }

    private func statValue(_ stat: FitStatDelta.Stat, _ performance: FitPerformance) -> String {
        switch stat {
        case .dps:       performance.dps.formatted(.number.precision(.fractionLength(0)))
        case .ehp:       performance.ehp.formatted(.number.notation(.compactName).precision(.significantDigits(3)))
        case .tank:      String(localized: "\(performance.tank.formatted(.number.precision(.fractionLength(1)))) HP/s")
        case .speed:     String(localized: "\(performance.speed.formatted(.number.precision(.fractionLength(0)))) m/s")
        case .align:     String(localized: "\(performance.alignTime.formatted(.number.precision(.fractionLength(1)))) s")
        case .lockRange: String(localized: "\((performance.lockRange / 1000).formatted(.number.precision(.fractionLength(1)))) km")
        }
    }

    // MARK: Haul

    /// A part the fit takes from somewhere other than the hull's own station hangar.
    private struct Pickup: Identifiable {
        let typeID: Int
        let quantity: Int
        let where_: String
        var id: String { "\(typeID)-\(where_)" }
    }

    private var pickups: [Pickup] {
        var out: [Pickup] = []
        for (typeID, need) in result.needs.sorted(by: { $0.key < $1.key }) {
            var left = need
            // Closest first: already on the hull, then this station, then elsewhere.
            let sources = (result.sources[typeID] ?? []).sorted { rank($0) < rank($1) }
            for source in sources where left > 0 {
                let take = min(left, source.quantity)
                left -= take
                if rank(source) > 1 { out.append(Pickup(typeID: typeID, quantity: take, where_: describe(source))) }
            }
        }
        return out
    }

    private func rank(_ source: HangarForgeSource) -> Int {
        if source.fittedToItemID == result.hull.itemID { return 0 }
        if source.placeID == result.hull.placeID && source.fittedToItemID == nil && !source.isCorporation { return 1 }
        return source.placeID == result.hull.placeID ? 2 : 3
    }

    private func describe(_ source: HangarForgeSource) -> String {
        let place = places[source.placeID]?.name ?? String(localized: "another location")
        if let shipID = source.fittedToItemID,
           let ship = holdings.first(where: { $0.itemID == shipID }) {
            let shipName = catalog.hulls.first { $0.id == shipID }?.displayName ?? name(ship.typeID)
            return String(localized: "fitted to your \(shipName) · \(place)")
        }
        return source.isCorporation ? String(localized: "corp hangar · \(place)") : place
    }

    @ViewBuilder
    private var haulSection: some View {
        let list = pickups
        if !list.isEmpty {
            EVEInspectorSection("Collect First") {
                VStack(alignment: .leading, spacing: EVESpacing.xs) {
                    ForEach(list) { pickup in
                        VStack(alignment: .leading, spacing: 1) {
                            Text(verbatim: "\(pickup.quantity.formatted())× \(name(pickup.typeID))")
                                .font(.callout)
                                .lineLimit(1)
                            Text(pickup.where_)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }
                }
            }
        }
    }

    private var footer: some View {
        Text(result.hitBudget
             ? "Tried \(result.evaluations.formatted()) fits and stopped at the search limit — another module mix might do slightly better."
             : "Tried \(result.evaluations.formatted()) fits with your current skills and implants. Assets can be up to an hour behind the game.")
            .font(.caption)
            .foregroundStyle(.tertiary)
            .fixedSize(horizontal: false, vertical: true)
    }
}
