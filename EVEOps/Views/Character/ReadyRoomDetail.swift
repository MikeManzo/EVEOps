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

// MARK:  Detail Pane

struct ReadyRoomDetailPane: View {
    let report: ReadyRoomReport
    let snapshot: ReadyRoomSnapshot

    @Environment(AccountManager.self) private var accountManager
    @Environment(DashboardPrefetcher.self) private var prefetcher
    @Environment(ThemeManager.self) private var themeManager
    @Environment(\.undoManager) private var undoManager
    @State private var showShop = false
    @State private var isSendingRoute = false
    @State private var route: [(systemID: Int, jumps: Int?)] = []
    @State private var hubQuotes: [StationQuote]?
    /// Part line ID → what buying it does against what's fitted today; nil while measuring.
    @State private var upgrades: [String: ReadyRoomUpgrade]?

    private var palette: EVEPalette { themeManager.palette }
    private var places: [Int: ReadyRoomPlace] { snapshot.places }
    private var jumps: [Int: Int] { snapshot.jumps }
    private var service: ReadyRoomService { .shared }
    private var isPinned: Bool { service.pinnedFittingIDs(for: snapshot.characterID).contains(report.fittingID) }

    var body: some View {
        VStack(spacing: 0) {
            hero
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: EVESpacing.xl) {
                    fittingSection
                    skillsSection
                    partsSection(title: "Parts", lines: report.requiredParts)
                    if !report.optionalParts.isEmpty {
                        partsSection(title: "Cargo (Optional)", lines: report.optionalParts)
                    }
                    stagingSection
                    if !report.collectionPlaceIDs.isEmpty {
                        collectionSection
                    }
                    if report.missingCount > 0 {
                        whereToBuySection
                    }
                    if accountManager.accounts.count > 1 {
                        otherPilotsSection
                    }
                }
                .padding(EVESpacing.lg)
            }
        }
        .sheet(isPresented: $showShop) {
            FittingShopView(input: shopInput)
                .environment(accountManager)
        }
        .task(id: RouteKey(fittingID: report.fittingID, stops: report.collectionPlaceIDs, origin: snapshot.pilot.currentSystemID)) {
            await planRoute()
        }
        .task(id: BuyKey(fittingID: report.fittingID, missing: report.missingCount)) {
            await quoteHubs()
        }
        .task(id: UpgradeKey(fittingID: report.fittingID, displaced: report.requiredParts.map(\.displaced))) {
            upgrades = nil
            upgrades = await ReadyRoomUpgrades.measure(report: report, snapshot: snapshot)
        }
    }

    private struct RouteKey: Hashable { let fittingID: Int; let stops: [Int]; let origin: Int }
    private struct BuyKey: Hashable { let fittingID: Int; let missing: Int }
    private struct UpgradeKey: Hashable { let fittingID: Int; let displaced: [[ReadyRoomPartLine.Displaced]] }

    // MARK:  Hero

    /// Same construction as the saved-fitting detail pane: content-sized, with the ship
    /// render and gradient as backgrounds so they always fill exactly the content's height.
    private var hero: some View {
        VStack(alignment: .leading, spacing: EVESpacing.md) {
            VStack(alignment: .leading, spacing: 3) {
                let tint = report.tier.color(palette)
                Label(report.tier.title, systemImage: report.tier.systemImage)
                    .font(.eveCaptionBold)
                    .foregroundStyle(tint)
                    .padding(.horizontal, EVESpacing.md)
                    .padding(.vertical, 3)
                    .background(.black.opacity(0.35), in: Capsule())
                    .overlay(Capsule().strokeBorder(tint.opacity(0.6), lineWidth: 0.5))
                    .padding(.bottom, EVESpacing.xs)
                Text(report.name)
                    .font(.headline)
                    .foregroundStyle(.white)
                Text(verbatim: "\(report.shipTypeName) · \(report.shipClassName)")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.7))
                if !report.fittingDescription.isEmpty {
                    Text(report.fittingDescription)
                        .font(.caption2)
                        .foregroundStyle(.white.opacity(0.5))
                        .lineLimit(2)
                }
            }
            FlowLayout(spacing: EVESpacing.md) {
                if let systemID = report.staging?.systemID, !report.isStagingCurrentLocation {
                    heroButton("Set Destination", systemImage: "location.north.line.fill") {
                        Task { await sendRoute([systemID], label: report.staging?.systemName) }
                    }
                    .disabled(isSendingRoute)
                    .help("Set the in-game autopilot destination to \(report.staging?.systemName ?? "the staging system")")
                }
                if report.missingCount > 0 {
                    heroButton("Shop Missing", systemImage: "cart.fill") { showShop = true }
                        .help("Compare trade hub prices for the parts you don't own")
                }
                heroButton(isPinned ? "Unpin" : "Pin", systemImage: isPinned ? "pin.slash.fill" : "pin.fill") {
                    withAnimation(EVEMotion.snappy) { service.togglePin(report.fittingID, characterID: snapshot.characterID) }
                }
                .help(isPinned ? "Remove from the top of the board" : "Keep this fit at the top of the board and on the Dashboard")
                heroButton("Show in Fittings", systemImage: "wrench.and.screwdriver") {
                    AppRouter.shared.pendingSavedFittingID = report.fittingID
                    AppRouter.shared.pendingSection = .fittings
                }
            }
        }
        .padding(EVESpacing.lg)
        .frame(maxWidth: .infinity, minHeight: 190, alignment: .bottomLeading)
        .background {
            LinearGradient(
                stops: [
                    .init(color: .clear, location: 0.0),
                    .init(color: .black.opacity(0.75), location: 1.0)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        }
        .background {
            GeometryReader { geo in
                CachedAsyncImage(url: EVEImageURL.typeRender(report.shipTypeID, size: 512)) { image in
                    image.resizable().aspectRatio(contentMode: .fill)
                } placeholder: {
                    Rectangle().fill(
                        LinearGradient(
                            colors: [Color(.darkGray).opacity(0.4), .black.opacity(0.6)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                }
                .frame(width: geo.size.width, height: geo.size.height)
                .clipped()
            }
        }
    }

    private func heroButton(_ title: LocalizedStringKey, systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .font(.caption.bold())
                .padding(.horizontal, 10)
                .padding(.vertical, EVESpacing.sm)
                .glassEffect(.regular, in: RoundedRectangle(cornerRadius: EVERadius.md))
                .foregroundStyle(.white)
                .eveHoverable(cornerRadius: EVERadius.md)
        }
        .buttonStyle(.plain)
    }

    // MARK:  Fitting

    @ViewBuilder
    private var fittingSection: some View {
        if let check = report.fitting {
            EVEInspectorSection("Fitting") {
                VStack(spacing: EVESpacing.sm) {
                    meter("CPU", used: check.cpuUsed, total: check.cpuTotal, unit: "tf")
                    meter("Powergrid", used: check.powerUsed, total: check.powerTotal, unit: "MW")
                    if check.calibrationTotal > 0 {
                        meter("Calibration", used: check.calibrationUsed, total: check.calibrationTotal, unit: "")
                    }
                }
                Group {
                    if check.fitsNow {
                        Text("Fits with your current skills and implants.")
                    } else if check.fitsWithTraining {
                        Text("Over budget today — the fitting skills marked below bring it within CPU and powergrid.")
                    } else {
                        Text("Over budget even with every fitting skill at V. A fitting implant, a CPU or powergrid rig or module, or a lighter fit would be needed.")
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            }
        } else if snapshot.fittingCheck == .unavailable {
            EVEInspectorSection("Fitting") {
                Text("CPU and powergrid weren't checked — the fitting engine's data couldn't be loaded. Opening the Simulator once downloads it.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func meter(_ label: LocalizedStringKey, used: Double, total: Double, unit: String) -> some View {
        let ratio = total > 0 ? used / total : 0
        let over = used > total + 0.05
        return VStack(alignment: .leading, spacing: EVESpacing.xxs) {
            HStack {
                Text(label).font(.callout)
                Spacer()
                Text(verbatim: "\(used.formatted(.number.precision(.fractionLength(0...1)))) / \(total.formatted(.number.precision(.fractionLength(0...1)))) \(unit)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(over ? .red : .secondary)
            }
            EVEProgressBar(value: ratio, tint: over ? .red : ratio > 0.9 ? .orange : .green, height: 4)
        }
        .accessibilityElement(children: .combine)
    }

    // MARK:  Skills

    private var skillsSection: some View {
        EVEInspectorSection("Skills") {
            if report.isFlyable {
                Label("Every skill for the hull, its modules and its fitting is trained.", systemImage: "checkmark.circle.fill")
                    .font(.callout)
                    .foregroundStyle(.green)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                VStack(spacing: EVESpacing.xs) {
                    ForEach(report.skillGaps) { gap in
                        skillRow(gap)
                    }
                }
                skillsFooter
            }
        }
    }

    private func skillRow(_ gap: ReadyRoomSkillGap) -> some View {
        HStack(spacing: EVESpacing.md) {
            Image(systemName: gap.isOmegaLocked ? "lock.fill"
                  : gap.isQueued ? "clock.fill"
                  : gap.trainedLevel == 0 ? "xmark.circle.fill" : "arrow.up.circle.fill")
                .font(.caption)
                .foregroundStyle(gap.isOmegaLocked ? .yellow
                                 : gap.isQueued ? palette.knowledge
                                 : gap.trainedLevel == 0 ? .red : .orange)
                .frame(width: 16)
                .accessibilityHidden(true)
            Text(gap.name)
                .font(.callout)
                .lineLimit(1)
                .eveTruncationHelp(gap.name)
            if gap.isForFitting {
                EVEChip(Text("Fitting"), tint: .orange)
                    .help("Needed to fit the modules within CPU and powergrid")
            }
            Spacer(minLength: EVESpacing.sm)
            Text(verbatim: "\(ReadyRoomFormat.roman(gap.trainedLevel)) → \(ReadyRoomFormat.roman(gap.requiredLevel))")
                .font(.eveCaptionSemibold.monospacedDigit())
                .foregroundStyle(.secondary)
            Group {
                if gap.isOmegaLocked {
                    Text("Omega")
                } else if let finish = gap.queuedFinish {
                    Text(ReadyRoomFormat.queuedDate(finish))
                } else if let seconds = gap.seconds {
                    Text(ReadyRoomFormat.duration(seconds))
                } else {
                    Text(verbatim: "—")
                }
            }
            .font(.caption.monospacedDigit())
            .foregroundStyle(.secondary)
            .frame(minWidth: 70, alignment: .trailing)
        }
        .padding(.vertical, EVESpacing.xxs)
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var skillsFooter: some View {
        let unqueued = report.unqueuedGaps
        VStack(alignment: .leading, spacing: EVESpacing.xs) {
            if report.needsOmega {
                Label("Some skills are trained but capped on an Alpha clone — they need Omega time, not training.",
                      systemImage: "lock.fill")
                    .foregroundStyle(.yellow)
            }
            if unqueued.isEmpty, let until = report.queuedUntil {
                Text("Already in your queue — flyable \(ReadyRoomFormat.queuedDate(until)).")
            } else if let seconds = report.trainingSeconds, !unqueued.isEmpty {
                Text("\(unqueued.count) skills · \(ReadyRoomFormat.duration(seconds)) at current attributes")
            }
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .fixedSize(horizontal: false, vertical: true)

        if !unqueued.isEmpty {
            HStack(spacing: EVESpacing.md) {
                Button("Add Missing Skills to Plan", systemImage: "text.badge.plus") { addToPlan(unqueued) }
                    .buttonStyle(.borderedProminent)
                    .tint(palette.accent)
                Button("Open Skill Planner") { AppRouter.shared.pendingSection = .skillPlanner }
                    .buttonStyle(.borderless)
            }
            .controlSize(.small)
            remapHint
        }
    }

    /// "An optimal remap saves 2d 6h" — only when a remap is available and worth it
    /// (at least 12 hours and a tenth of the training).
    @ViewBuilder
    private var remapHint: some View {
        if snapshot.pilot.isRemapAvailable,
           let total = report.trainingSeconds,
           let saving = remapSaving,
           saving.seconds >= 12 * 3600, saving.seconds >= total * 0.1 {
            HStack(alignment: .firstTextBaseline, spacing: EVESpacing.sm) {
                Image(systemName: "brain.filled.head.profile")
                    .foregroundStyle(palette.knowledge)
                Text("A remap is available — an optimal one for this fit saves \(ReadyRoomFormat.duration(saving.seconds)).")
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
                Button("Remap Advisor") { AppRouter.shared.pendingSection = .remapAdvisor }
                    .buttonStyle(.borderless)
            }
            .font(.caption)
            .padding(EVESpacing.md)
            .background(palette.knowledge.opacity(EVEOpacity.faint), in: RoundedRectangle(cornerRadius: EVERadius.md))
        }
    }

    /// Time an optimal remap would save on this fit's unqueued training — Training's own
    /// exhaustive remap search, run over just these skills.
    private var remapSaving: (seconds: Double, base: [EVEAttribute: Int])? {
        guard let attributes = snapshot.input.attributes else { return nil }
        let demand: [SkillTraining.Demand] = report.unqueuedGaps.compactMap { gap in
            guard gap.sp > 0, let info = snapshot.input.skillInfo[gap.skillID],
                  let primary = EVEAttribute(rawValue: info.primaryAttribute),
                  let secondary = EVEAttribute(rawValue: info.secondaryAttribute) else { return nil }
            return SkillTraining.Demand(primary: primary, secondary: secondary, sp: gap.sp)
        }
        let current = Dictionary(uniqueKeysWithValues: EVEAttribute.allCases.map { ($0, $0.value(in: attributes)) })
        guard let best = SkillTraining.optimalRemap(for: demand, implants: snapshot.pilot.implantBonuses) else { return nil }
        let saved = (SkillTraining.minutes(for: demand, totals: current) - best.minutes) * 60
        return saved > 0 ? (saved, best.base) : nil
    }

    /// Adds the gaps to the pilot's skill plan (prerequisites first — `skillGaps` is
    /// already in training order). Undoable with ⌘Z, like edits in the planner itself.
    private func addToPlan(_ gaps: [ReadyRoomSkillGap]) {
        let characterID = snapshot.characterID
        let previous = SkillPlanStore.load(characterID: characterID)
        let items = gaps.map {
            SkillPlanItem(skillId: $0.skillID, skillName: $0.name, fromLevel: $0.trainedLevel, targetLevel: $0.requiredLevel)
        }
        let changed = SkillPlanStore.merge(items, characterID: characterID)
        guard changed > 0 else {
            ToastCenter.shared.show(String(localized: "These skills are already in your plan"), style: .info)
            return
        }
        undoManager?.registerUndo(withTarget: SkillPlanUndoTarget.shared) { _ in
            SkillPlanStore.save(previous, characterID: characterID)
        }
        undoManager?.setActionName(String(localized: "Add Skills to Plan"))
        ToastCenter.shared.show(String(localized: "Added \(changed) skills to your plan for \(report.name)"),
                                systemImage: "text.badge.plus")
    }

    // MARK:  Parts

    private static let categoryOrder = [ReadyRoomEngine.hullCategory, "High Slots", "Med Slots", "Low Slots", "Rig Slots",
                                        "Subsystems", "Service Slots", "Drone Bay", "Fighter Bay", "Cargo"]

    private func partsSection(title: LocalizedStringKey, lines: [ReadyRoomPartLine]) -> some View {
        EVEInspectorSection(title) {
            let grouped = Dictionary(grouping: lines, by: \.category)
            VStack(alignment: .leading, spacing: EVESpacing.md) {
                ForEach(Self.categoryOrder.filter { grouped[$0] != nil }, id: \.self) { category in
                    VStack(alignment: .leading, spacing: EVESpacing.xxs) {
                        if grouped.count > 1 {
                            Text(category)
                                .font(.eveMicroBold)
                                .foregroundStyle(.tertiary)
                        }
                        ForEach(grouped[category]!) { line in
                            partRow(line)
                        }
                    }
                }
            }
        }
    }

    private func partRow(_ line: ReadyRoomPartLine) -> some View {
        VStack(alignment: .leading, spacing: EVESpacing.xxs) {
            partSummary(line)
            if !line.displaced.isEmpty {
                upgradeLine(line)
                    .padding(.leading, 24 + EVESpacing.md)
            }
        }
        .padding(.vertical, EVESpacing.xxs)
        .accessibilityElement(children: .combine)
    }

    private func partSummary(_ line: ReadyRoomPartLine) -> some View {
        HStack(spacing: EVESpacing.md) {
            CachedAsyncImage(url: EVEImageURL.typeIcon(line.typeID, size: 64)) { image in
                image.resizable()
            } placeholder: {
                RoundedRectangle(cornerRadius: EVERadius.xs).fill(.quaternary)
            }
            .frame(width: 24, height: 24)
            .clipShape(RoundedRectangle(cornerRadius: EVERadius.xs))

            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: EVESpacing.xs) {
                    Text(line.name)
                        .font(.callout)
                        .lineLimit(1)
                        .eveTruncationHelp(line.name)
                    if line.fromCorporation > 0 {
                        EVEChip(Text("Corp"), tint: .secondary)
                            .help("\(line.fromCorporation) from corporation hangars")
                    }
                }
                if line.required > 1 {
                    Text(verbatim: "×\(line.required)")
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                ForEach(line.substitutes, id: \.typeID) { substitute in
                    Label {
                        Text("Using \(substitute.quantity)× \(substitute.name)")
                    } icon: {
                        Image(systemName: "arrow.up.circle.fill")
                    }
                    .font(.caption2)
                    .foregroundStyle(.green)
                    .lineLimit(1)
                    .help("You own \(substitute.name), the Tech II version, and can use it — it covers \(substitute.quantity) of these.")
                }
            }
            Spacer(minLength: EVESpacing.sm)
            partStatus(line)
        }
    }

    // MARK:  Upgrade

    /// What the purchase replaces on the staged hull, and what it gains the fit.
    private func upgradeLine(_ line: ReadyRoomPartLine) -> some View {
        let upgrade = upgrades?[line.id]
        return HStack(alignment: .firstTextBaseline, spacing: EVESpacing.xs) {
            Image(systemName: "arrow.turn.down.right")
                .foregroundStyle(.tertiary)
            Text(replacesText(line.displaced))
                .foregroundStyle(.secondary)
                .lineLimit(2)
            if let upgrade {
                if upgrade.delta.isEmpty {
                    Text("· no change to DPS, tank or speed")
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                } else {
                    Text(verbatim: "· \(upgrade.delta.headlineText)")
                        .font(.eveCaptionBold)
                        .foregroundStyle(.green)
                        .lineLimit(1)
                }
            } else if upgrades == nil {
                ProgressView().controlSize(.mini)
            }
        }
        .font(.caption)
        .help(upgradeHelp(line, upgrade: upgrade))
    }

    /// "Replaces Damage Control I", "Replaces 2× Small Shield Booster I", "Fills an empty slot".
    private func replacesText(_ displaced: [ReadyRoomPartLine.Displaced]) -> String {
        var counts: [String: Int] = [:]
        var order: [String] = []
        var empty = 0
        for entry in displaced {
            guard let name = entry.name else { empty += 1; continue }
            if counts[name] == nil { order.append(name) }
            counts[name, default: 0] += 1
        }
        var parts = order.map { counts[$0]! > 1 ? "\(counts[$0]!)× \($0)" : $0 }
        if empty > 0 {
            parts.append(empty > 1 ? String(localized: "\(empty) empty slots") : String(localized: "an empty slot"))
        }
        if order.isEmpty {
            return empty > 1 ? String(localized: "Fills \(empty) empty slots") : String(localized: "Fills an empty slot")
        }
        return String(localized: "Replaces \(parts.formatted(.list(type: .and)))")
    }

    private func upgradeHelp(_ line: ReadyRoomPartLine, upgrade: ReadyRoomUpgrade?) -> String {
        let hull = report.staging.map { String(localized: "Your \(report.shipTypeName) in \($0.name) today:") }
            ?? String(localized: "Your \(report.shipTypeName) today:")
        var lines = [hull] + line.displaced.map { entry in
            "\(entry.flag): \(entry.name ?? String(localized: "empty"))"
        }
        if let upgrade {
            lines.append("")
            if upgrade.delta.isEmpty {
                lines.append(String(localized: "Buying \(line.name) doesn’t change DPS, EHP, repair, speed, align or lock range — it adds what the fit was built around."))
            } else {
                lines.append(String(localized: "With \(line.name):"))
                for stat in FitStatDelta.Stat.allCases where upgrade.delta.gain(stat) > 0 {
                    let gain = upgrade.delta.gain(stat).formatted(.percent.precision(.fractionLength(1)))
                    lines.append("\(stat.name) \(statValue(stat, upgrade.today)) → \(statValue(stat, upgrade.withPurchase)) (+\(gain))")
                }
                if upgrade.delta.becomesCapStable { lines.append(String(localized: "Becomes cap stable")) }
            }
        }
        return lines.joined(separator: "\n")
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

    @ViewBuilder
    private func partStatus(_ line: ReadyRoomPartLine) -> some View {
        VStack(alignment: .trailing, spacing: 1) {
            if line.atStaging == line.required {
                Label("Staged", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            } else {
                if line.atStaging > 0 {
                    Text("\(line.atStaging) staged").foregroundStyle(.green)
                }
                if let nearest = line.elsewhere.first {
                    let place = places[nearest.placeID]
                    let jumpCount = place?.systemID.flatMap { jumps[$0] }
                    Text(elsewhereLabel(quantity: line.elsewhereQuantity, place: place, jumps: jumpCount,
                                        more: Set(line.elsewhere.map(\.placeID)).count - 1))
                        .foregroundStyle(.cyan)
                        .help(line.elsewhere.map { "\($0.quantity) × \(places[$0.placeID]?.name ?? "Unknown location")\($0.isCorporation ? " (corp)" : "")" }
                            .joined(separator: "\n"))
                }
                if !line.incoming.isEmpty {
                    let quantity = line.incomingQuantity
                    let eta = line.incoming.compactMap(\.eta).max()
                    Group {
                        if let eta {
                            Text("\(quantity) arriving · \(EVEFormatters.timeUntil(eta))")
                        } else {
                            Text("\(quantity) on order")
                        }
                    }
                    .foregroundStyle(.teal)
                    .help(line.incoming.map { "\($0.quantity) × \($0.kind.title)\($0.placeID.flatMap { places[$0]?.name }.map { " → \($0)" } ?? "")" }
                        .joined(separator: "\n"))
                }
                if line.missing > 0 {
                    Group {
                        if let cost = line.missingCost {
                            Text("Buy \(line.missing) · \(EVEFormatters.formatISKShort(cost))")
                        } else {
                            Text("Buy \(line.missing)")
                        }
                    }
                    .foregroundStyle(.orange)
                }
            }
        }
        .font(.caption.monospacedDigit())
        .lineLimit(1)
    }

    private func elsewhereLabel(quantity: Int, place: ReadyRoomPlace?, jumps: Int?, more: Int) -> String {
        let name = place?.systemName ?? place?.name ?? String(localized: "elsewhere")
        var label = String(localized: "\(quantity) in \(name)")
        if let jumps { label += " · \(jumps)j" }
        if more > 0 { label += String(localized: " +\(more) more") }
        return label
    }

    // MARK:  Staging

    private var stagingSection: some View {
        EVEInspectorSection("Staging") {
            if let place = report.staging {
                VStack(alignment: .leading, spacing: EVESpacing.sm) {
                    HStack(spacing: EVESpacing.sm) {
                        if let security = place.security { EVESecurityBadge(status: security) }
                        Text(place.name)
                            .font(.callout.weight(.medium))
                            .lineLimit(2)
                            .textSelection(.enabled)
                    }
                    FlowLayout(spacing: EVESpacing.sm) {
                        if report.isStagingCurrentLocation {
                            EVEChip(Text("You're here"), tint: .green)
                        } else if let jumps = report.stagingJumps {
                            EVEChip(Text(ReadyRoomFormat.jumps(jumps)), tint: .cyan, monospacedDigits: true)
                        }
                        if report.stagedHullItemID != nil {
                            EVEChip(Text("Assembled hull"), tint: .secondary)
                        }
                        if report.hasJumpCloneAtStaging && !report.isStagingCurrentLocation {
                            if let readyAt = snapshot.pilot.cloneJumpReadyAt {
                                EVEChip(Text("Jump clone here · jump in \(EVEFormatters.timeUntil(readyAt))"), tint: .cyan)
                            } else {
                                EVEChip(Text("Jump clone here · ready to jump"), tint: .cyan)
                            }
                        }
                    }
                    Text(stagingExplanation)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            } else {
                Text("You don't own any part of this fit yet. Where to Buy compares the trade hubs below.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var stagingExplanation: String {
        let modules = report.requiredParts.filter { $0.category != ReadyRoomEngine.hullCategory }
        let moduleTotal = modules.reduce(0) { $0 + $1.required }
        let moduleHere = modules.reduce(0) { $0 + $1.atStaging }
        if report.hasHullAtStaging {
            return String(localized: "The hull and \(moduleHere) of \(moduleTotal) modules are here — more of this fit than anywhere else.")
        }
        return String(localized: "\(moduleHere) of \(moduleTotal) modules are here — more of this fit than anywhere else.")
    }

    // MARK:  Collection route

    @ViewBuilder
    private var collectionSection: some View {
        EVEInspectorSection("Collection Route") {
            if route.isEmpty {
                HStack(spacing: EVESpacing.sm) {
                    ProgressView().controlSize(.mini)
                    Text("Planning the pickup route…")
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            } else {
                VStack(alignment: .leading, spacing: EVESpacing.xs) {
                    ForEach(Array(route.enumerated()), id: \.offset) { index, stop in
                        routeRow(index: index, stop: stop, isLast: index == route.count - 1)
                    }
                }
                let total = route.compactMap(\.jumps).reduce(0, +)
                HStack {
                    Text("\(route.count) stops · \(total) jumps")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("Send Route to Autopilot", systemImage: "point.topleft.down.to.point.bottomright.curvepath") {
                        Task { await sendRoute(route.map(\.systemID), label: nil) }
                    }
                    .controlSize(.small)
                    .disabled(isSendingRoute)
                }
                cargoCheck
            }
        }
    }

    private func routeRow(index: Int, stop: (systemID: Int, jumps: Int?), isLast: Bool) -> some View {
        let stopPlaces = (report.collectionPlaceIDs + [report.staging?.id].compactMap { $0 })
            .compactMap { places[$0] }
            .filter { $0.systemID == stop.systemID }
        let system = stopPlaces.first
        return HStack(alignment: .firstTextBaseline, spacing: EVESpacing.md) {
            Text("\(index + 1)")
                .font(.eveMicroBold.monospacedDigit())
                .foregroundStyle(.white)
                .frame(width: 18, height: 18)
                .background(isLast ? Color.green : palette.accent, in: Circle())
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: EVESpacing.xs) {
                    if let security = system?.security { EVESecurityBadge(status: security, compact: true) }
                    Text(system?.systemName ?? String(localized: "System #\(stop.systemID)"))
                        .font(.callout)
                    if isLast { EVEChip(Text("Staging"), tint: .green) }
                }
                Text(stopPlaces.map(\.name).joined(separator: ", "))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            Spacer(minLength: EVESpacing.sm)
            if let legJumps = stop.jumps {
                Text(verbatim: "+\(legJumps)j")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
        }
    }

    /// Volume of the parts to pick up against the hold of the ship the pilot is flying.
    @ViewBuilder
    private var cargoCheck: some View {
        let volume = report.requiredParts
            .filter { $0.category != ReadyRoomEngine.hullCategory }
            .reduce(0.0) { $0 + Double($1.elsewhereQuantity) * (snapshot.volumes[$1.typeID] ?? 0) }
        if volume > 0 {
            let capacity = snapshot.pilot.shipCapacity
            let fits = capacity.map { volume <= $0 } ?? true
            Label {
                if let capacity, let ship = snapshot.pilot.shipTypeName {
                    Text("\(volume.formatted(.number.precision(.fractionLength(0...1)))) m³ to collect · your \(ship) holds \(capacity.formatted(.number.precision(.fractionLength(0)))) m³")
                } else {
                    Text("\(volume.formatted(.number.precision(.fractionLength(0...1)))) m³ to collect")
                }
            } icon: {
                Image(systemName: fits ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                    .foregroundStyle(fits ? .green : .orange)
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
    }

    private func planRoute() async {
        route = []
        let stops = Set(report.collectionPlaceIDs.compactMap { places[$0]?.systemID })
        guard !stops.isEmpty, let adjacency = await service.adjacency() else { return }
        let origin = snapshot.pilot.currentSystemID
        let destination = report.staging?.systemID
        route = await Task.detached(priority: .userInitiated) {
            ReadyRoomEngine.collectionRoute(origin: origin, stops: Array(stops), destination: destination, adjacency: adjacency)
        }.value
    }

    /// Sets the first system as the destination and appends the rest as waypoints.
    private func sendRoute(_ systems: [Int], label: String?) async {
        guard let first = systems.first else { return }
        isSendingRoute = true
        defer { isSendingRoute = false }
        var result = await AutopilotService.setDestination(systemId: first, accountManager: accountManager)
        for system in systems.dropFirst() {
            guard case .ok = result else { break }
            result = await AutopilotService.addWaypoint(systemId: system, accountManager: accountManager)
        }
        switch result {
        case .ok:
            ToastCenter.shared.show(systems.count == 1
                                    ? String(localized: "Destination set to \(label ?? "staging system")")
                                    : String(localized: "Route with \(systems.count) stops sent to EVE"),
                                    systemImage: "location.north.line.fill")
        case .notSignedIn:
            break
        case .missingScope:
            ToastCenter.shared.show(String(localized: "Setting waypoints needs updated permissions — re-add this pilot."), style: .failure)
        case .failed(let message):
            ToastCenter.shared.show(String(localized: "Couldn’t set destination: \(message)"), style: .failure)
        }
    }

    // MARK:  Where to buy

    private var whereToBuySection: some View {
        EVEInspectorSection("Where to Buy") {
            if let quotes = hubQuotes {
                if quotes.isEmpty {
                    Text("No trade hub prices right now.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    let complete = quotes.filter(\.isComplete)
                    let cheapest = complete.min { $0.totalISK < $1.totalISK }
                    let nearest = complete.min { (jumps[$0.systemId] ?? .max) < (jumps[$1.systemId] ?? .max) }
                    VStack(spacing: EVESpacing.xs) {
                        ForEach(quotes) { quote in
                            hubRow(quote, isCheapest: quote.id == cheapest?.id, isNearest: quote.id == nearest?.id)
                        }
                    }
                    if let cheapest, let nearest, cheapest.id != nearest.id,
                       let jc = jumps[cheapest.systemId], let jn = jumps[nearest.systemId], cheapest.totalISK > 0 {
                        let premium = (nearest.totalISK - cheapest.totalISK) / cheapest.totalISK
                        Text("\(nearest.systemName) is \(premium.formatted(.percent.precision(.fractionLength(0)))) pricier but \(jc - jn) jumps closer than \(cheapest.systemName).")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Button("Compare in Fitting Shop", systemImage: "cart") { showShop = true }
                        .buttonStyle(.borderless)
                        .controlSize(.small)
                }
            } else {
                HStack(spacing: EVESpacing.sm) {
                    ProgressView().controlSize(.mini)
                    Text("Checking the trade hubs…")
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
    }

    private func hubRow(_ quote: StationQuote, isCheapest: Bool, isNearest: Bool) -> some View {
        HStack(spacing: EVESpacing.md) {
            EVESecurityBadge(status: quote.securityStatus, compact: true)
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: EVESpacing.xs) {
                    Text(quote.systemName).font(.callout)
                    if isCheapest { EVEChip(Text("Cheapest"), tint: .green) }
                    if isNearest { EVEChip(Text("Nearest"), tint: .cyan) }
                    if snapshot.input.jumpClonePlaceIDs.contains(quote.locationId) {
                        Image(systemName: "person.crop.circle.badge.checkmark")
                            .foregroundStyle(.cyan)
                            .help("One of your jump clones is in this station")
                    }
                }
                Group {
                    if let hubJumps = jumps[quote.systemId] {
                        Text(ReadyRoomFormat.jumps(hubJumps))
                    } else {
                        Text(quote.regionName)
                    }
                }
                .font(.caption2)
                .foregroundStyle(.secondary)
            }
            Spacer(minLength: EVESpacing.sm)
            VStack(alignment: .trailing, spacing: 1) {
                Text(EVEFormatters.formatISKShort(quote.totalISK))
                    .font(.caption.monospacedDigit())
                if !quote.isComplete {
                    Text("\(quote.missingCount) not listed")
                        .font(.caption2)
                        .foregroundStyle(.orange)
                }
            }
        }
        .padding(.vertical, EVESpacing.xxs)
        .opacity(quote.isComplete ? 1 : 0.7)
        .accessibilityElement(children: .combine)
    }

    private func quoteHubs() async {
        hubQuotes = nil
        guard report.missingCount > 0 else { return }
        let items = report.requiredParts.filter { $0.missing > 0 }.map {
            FittingShopItem(typeId: $0.typeID, quantity: $0.missing, name: $0.name)
        }
        hubQuotes = await FittingMarketService.quickSearch(items: items)
    }

    // MARK:  Other pilots

    private var otherPilotsSection: some View {
        EVEInspectorSection("Other Pilots") {
            VStack(spacing: EVESpacing.xs) {
                ForEach(accountManager.accounts.filter { $0.characterID != snapshot.characterID }, id: \.characterID) { account in
                    pilotRow(account)
                }
            }
            Text("Skills to fly the hull and modules. Fittings and hangars are per pilot.")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
    }

    private func pilotRow(_ account: StoredAccount) -> some View {
        HStack(spacing: EVESpacing.md) {
            CachedAsyncImage(url: EVEImageURL.characterPortrait(account.characterID, size: 64)) { image in
                image.resizable()
            } placeholder: {
                Circle().fill(.quaternary)
            }
            .frame(width: 24, height: 24)
            .clipShape(Circle())
            Text(account.characterName)
                .font(.callout)
                .lineLimit(1)
            Spacer(minLength: EVESpacing.sm)
            pilotStatus(account)
            Button("Switch") { accountManager.selectedCharacterID = account.characterID }
                .buttonStyle(.borderless)
                .controlSize(.small)
                .help("Switch to \(account.characterName)")
        }
        .padding(.vertical, EVESpacing.xxs)
    }

    @ViewBuilder
    private func pilotStatus(_ account: StoredAccount) -> some View {
        if let data = prefetcher.data(for: account.characterID) {
            let skills = Dictionary(data.skills.skills.map {
                ($0.skillId, ReadyRoomSkillLevel(active: $0.activeSkillLevel, trained: $0.trainedSkillLevel, sp: $0.skillpointsInSkill))
            }, uniquingKeysWith: { a, _ in a })
            let gaps = ReadyRoomEngine.skillGaps(report.requiredSkills, skills: skills, skillInfo: snapshot.input.skillInfo,
                                                 attributes: data.attributes, queue: data.skillQueue)
            let toTrain = gaps.filter { !$0.isQueued && !$0.isOmegaLocked }
            Group {
                if gaps.isEmpty {
                    Label("Can fly", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
                } else if toTrain.isEmpty && gaps.contains(where: \.isOmegaLocked) {
                    Label("Omega", systemImage: "lock.fill").foregroundStyle(.yellow)
                } else if toTrain.isEmpty {
                    Label("In queue", systemImage: "clock.fill").foregroundStyle(palette.knowledge)
                } else {
                    let seconds = toTrain.compactMap(\.seconds).reduce(0, +)
                    Text("\(toTrain.count) skills · \(ReadyRoomFormat.duration(seconds))").foregroundStyle(.orange)
                }
            }
            .font(.caption.monospacedDigit())
        } else {
            Text("Not loaded yet")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    // MARK:  Actions

    private var shopInput: FittingShopInput {
        let items = report.requiredParts.filter { $0.missing > 0 }.map {
            FittingShopItem(typeId: $0.typeID, quantity: $0.missing, name: $0.name)
        }
        return FittingShopInput(fittingName: report.name, shipTypeId: report.shipTypeID, items: items)
    }
}

/// Undo target for plan edits made outside the Skill Planner (the plan lives in
/// `UserDefaults`, not in an object a view owns).
final class SkillPlanUndoTarget {
    static let shared = SkillPlanUndoTarget()
}
