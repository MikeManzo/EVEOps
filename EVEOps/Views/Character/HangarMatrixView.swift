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

enum HangarMatrixSort: String, CaseIterable {
    case coverage, name, hull, value

    var title: LocalizedStringKey {
        switch self {
        case .coverage: "Most Pilots Ready"
        case .name:     "Name"
        case .hull:     "Ship Class"
        case .value:    "Fit Value"
        }
    }
}

// MARK:  Main View

/// "Who can undock in this?" — every distinct saved fitting across all pilots against every
/// pilot: a cell per pair showing how close that pilot is (the Ready Room tier) and what's
/// in the way — jumps, ISK, or training.
struct HangarMatrixView: View {
    @Environment(AccountManager.self) private var accountManager
    @Environment(DashboardPrefetcher.self) private var prefetcher
    @Environment(ThemeManager.self) private var themeManager
    @AppStorage("hangarMatrix.sort") private var sortRaw = HangarMatrixSort.coverage.rawValue
    @AppStorage("hangarMatrix.flyableOnly") private var flyableOnly = false
    @AppStorage("hangarMatrix.showDetails") private var showDetails = true

    @State private var search = ""
    @State private var picked: CellID?
    /// A pilot picked in the strip: their column is highlighted and rows sort by how
    /// close they are.
    @State private var focusPilot: Int?

    private var service: HangarMatrixService { .shared }
    private var palette: EVEPalette { themeManager.palette }
    private var sort: HangarMatrixSort { HangarMatrixSort(rawValue: sortRaw) ?? .coverage }

    private let nameWidth: CGFloat = 250
    private let cellWidth: CGFloat = 72
    private let coverageWidth: CGFloat = 130
    private let valueWidth: CGFloat = 80
    private let contentsWidth: CGFloat = 96
    private let ownersWidth: CGFloat = 104

    struct CellID: Hashable {
        let row: String
        let pilot: Int
    }

    var body: some View {
        content
            .eveScreenHeader("Hangar Matrix", subtitle: subtitle, section: .hangarMatrix) {
                if let progress = service.progress {
                    HStack(spacing: EVESpacing.xs) {
                        ProgressView().controlSize(.mini)
                        Text(verbatim: progress)
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
                FreshnessIndicator(isLoading: service.isLoading) { await load(force: true) }
            }
            .task(id: accountManager.accounts.map(\.characterID)) {
                await load()
            }
            .onChange(of: AppRouter.shared.refreshTick) { _, _ in Task { await load(force: true) } }
    }

    private func load(force: Bool = false) async {
        if prefetcher.characterData.isEmpty { await prefetcher.prefetchAll(accountManager: accountManager) }
        await service.refresh(accountManager: accountManager, prefetcher: prefetcher, force: force)
    }

    private var subtitle: Text? {
        guard !service.rows.isEmpty else { return nil }
        return Text("\(service.rows.count) fits × \(service.pilotIDs.count) pilots")
    }

    private func name(_ characterID: Int) -> String {
        accountManager.accounts.first { $0.characterID == characterID }?.characterName ?? "#\(characterID)"
    }

    // MARK: Rows

    private var visibleRows: [HangarMatrixRow] {
        let needle = search.trimmingCharacters(in: .whitespacesAndNewlines)
        return service.rows
            .filter { !flyableOnly || $0.flyableCount > 0 }
            .filter {
                needle.isEmpty || $0.name.localizedCaseInsensitiveContains(needle)
                    || $0.shipTypeName.localizedCaseInsensitiveContains(needle)
                    || $0.shipClassName.localizedCaseInsensitiveContains(needle)
            }
            .sorted { a, b in
                func byName() -> Bool { a.name.localizedStandardCompare(b.name) == .orderedAscending }
                if let focusPilot {
                    switch (a.cells[focusPilot], b.cells[focusPilot]) {
                    case let (ra?, rb?):
                        // `closer` with equal IDs is false both ways only for a true tie.
                        let ab = HangarMatrixEngine.closer(ra, rb, idA: 0, idB: 0)
                        if ab != HangarMatrixEngine.closer(rb, ra, idA: 0, idB: 0) { return ab }
                    case (.some, nil): return true
                    case (nil, .some): return false
                    case (nil, nil): break
                    }
                }
                switch sort {
                case .coverage:
                    if a.readyCount != b.readyCount { return a.readyCount > b.readyCount }
                    if a.flyableCount != b.flyableCount { return a.flyableCount > b.flyableCount }
                    return byName()
                case .name:
                    return byName()
                case .hull:
                    let order = a.shipClassName.localizedStandardCompare(b.shipClassName)
                    return order != .orderedSame ? order == .orderedAscending : byName()
                case .value:
                    let va = a.fitValue ?? -1, vb = b.fitValue ?? -1
                    return va != vb ? va > vb : byName()
                }
            }
    }

    // MARK: Content

    @ViewBuilder
    private var content: some View {
        if service.rows.isEmpty {
            if service.isLoading {
                LoadingSkeleton()
            } else {
                EVEEmptyState("No Saved Fittings", systemImage: "square.grid.3x3",
                              message: Text("Save fittings in EVE or from Ships & Fittings on any pilot, and the matrix shows which of your pilots can fly each one.")) {
                    Button("Open Fittings") { AppRouter.shared.pendingSection = .fittings }
                        .buttonStyle(.borderedProminent)
                        .tint(palette.accent)
                }
            }
        } else {
            VStack(alignment: .leading, spacing: EVESpacing.lg) {
                if !service.failedPilots.isEmpty {
                    Label("Couldn’t load \(service.failedPilots.formatted(.list(type: .and))) — not shown.",
                          systemImage: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
                totals
                pilotStrip
                filterBar
                matrix
            }
            .padding()
        }
    }

    // MARK: Totals

    private var totals: some View {
        let rows = service.rows
        let readyAnywhere = rows.filter { $0.readyCount > 0 }.count
        let nobody = rows.filter { $0.flyableCount == 0 }.count
        let readyByPilot = Dictionary(grouping: rows.flatMap { row in row.cells.filter { $0.value.tier == .ready }.map(\.key) },
                                      by: { $0 }).mapValues(\.count)
        let top = readyByPilot.max { $0.value != $1.value ? $0.value < $1.value : $0.key > $1.key }
        return InsightStatRow {
            InsightStat(label: String(localized: "Distinct Fits"), value: "\(rows.count)",
                        detail: String(localized: "duplicates across pilots merged"))
            InsightStat(label: String(localized: "Undock Now"), value: "\(readyAnywhere)",
                        detail: String(localized: "fits some pilot is ready in"),
                        tint: ReadyRoomTier.ready.color(palette))
            InsightStat(label: String(localized: "Nobody Can Fly"), value: "\(nobody)",
                        detail: String(localized: "every pilot needs training"),
                        tint: nobody > 0 ? ReadyRoomTier.train.color(palette) : .secondary)
            InsightStat(label: String(localized: "Most Ready"),
                        value: top.map { name($0.key) } ?? "—",
                        detail: top.map { String(localized: "\($0.value) fits ready to undock") } ?? String(localized: "No pilot ready yet"),
                        tint: palette.accent)
        }
    }

    // MARK: Pilots

    /// One card per pilot: where they are, what they're in, clone status, SP, and how many
    /// fits they're ready for. Clicking one focuses their column.
    private var pilotStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: EVESpacing.md) {
                ForEach(service.pilotIDs.compactMap { service.pilots[$0] }) { pilot in
                    Button {
                        withAnimation(EVEMotion.snappy) { focusPilot = focusPilot == pilot.id ? nil : pilot.id }
                    } label: {
                        HangarMatrixPilotCard(pilot: pilot)
                            .eveSelectionGlow(isActive: focusPilot == pilot.id, cornerRadius: EVERadius.xl)
                    }
                    .buttonStyle(.plain)
                    .eveHoverable(cornerRadius: EVERadius.xl)
                    .help(focusPilot == pilot.id ? Text("Stop sorting for \(pilot.name)")
                                                 : Text("Sort the matrix by how close \(pilot.name) is"))
                    .accessibilityAddTraits(focusPilot == pilot.id ? .isSelected : [])
                }
            }
            .padding(.vertical, EVESpacing.xxs)
        }
    }

    // MARK: Filters

    private var filterBar: some View {
        HStack(spacing: EVESpacing.md) {
            EVESearchField("Search fits, hulls or classes", text: $search)
                .frame(maxWidth: 300)
            InsightToggleChip(title: Text("Flyable by someone"), systemImage: "person.fill.checkmark",
                              isOn: flyableOnly, tint: palette.accent) {
                withAnimation(EVEMotion.snappy) { flyableOnly.toggle() }
            }
            InsightToggleChip(title: Text("Fit details"), systemImage: "list.bullet.rectangle",
                              isOn: showDetails, tint: palette.accent) {
                withAnimation(EVEMotion.snappy) { showDetails.toggle() }
            }
            .help("Show each fit's value, contents, required skills and who saved it")
            if let focusPilot {
                Button {
                    withAnimation(EVEMotion.snappy) { self.focusPilot = nil }
                } label: {
                    HStack(spacing: EVESpacing.xs) {
                        Text("Sorted for \(name(focusPilot))")
                        Image(systemName: "xmark").font(.eveNanoBold)
                    }
                }
                .buttonStyle(.plain)
                .modifier(ReadyRoomChipStyle(tint: palette.accent))
                .help("Stop sorting for this pilot")
            }
            if !service.fitChecksDone && !service.isLoading {
                Label("CPU/PG not checked", systemImage: "cpu")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .help("The fitting engine's data couldn't be loaded, so fits aren't checked against CPU and powergrid.")
            }
            Spacer()
            legend
            EVEMenuPicker("Sort", selection: Binding(get: { sort }, set: { sortRaw = $0.rawValue }),
                          options: HangarMatrixSort.allCases.map { EVEMenuOption($0, $0.title) })
        }
    }

    private var legend: some View {
        HStack(spacing: EVESpacing.sm) {
            ForEach(ReadyRoomTier.allCases, id: \.self) { tier in
                Image(systemName: tier.systemImage)
                    .font(.caption)
                    .foregroundStyle(tier.color(palette))
                    .help(Text(tier.title))
            }
        }
    }

    // MARK: Matrix

    private var matrix: some View {
        ScrollView([.vertical, .horizontal]) {
            LazyVStack(alignment: .leading, spacing: 0, pinnedViews: [.sectionHeaders]) {
                Section {
                    ForEach(visibleRows) { row in
                        matrixRow(row)
                        Divider().opacity(0.4)
                    }
                } header: {
                    headerRow
                }
            }
            // Size the stack to hold a whole row. Left to itself it can come out narrower
            // than the rows (with many pilots), and the rows then draw in one place but
            // take clicks and hover at another — the wrong pilot's tile, several columns
            // off, by an amount that changes with the window width.
            .containerRelativeFrame(.horizontal, alignment: .leading) { length, _ in
                max(length, rowWidth)
            }
            .padding(.bottom, EVESpacing.md)
        }
        .eveCard(cornerRadius: EVERadius.xl)
        .frame(maxHeight: .infinity)
    }

    /// Full width of a header or matrix row: the fit column, the detail columns when
    /// shown, one cell per pilot, and the coverage column, with their paddings.
    private var rowWidth: CGFloat {
        EVESpacing.lg + nameWidth
            + (showDetails ? valueWidth + contentsWidth + ownersWidth : 0)
            + CGFloat(service.pilotIDs.count) * cellWidth
            + EVESpacing.md + coverageWidth
    }

    private var headerRow: some View {
        HStack(spacing: 0) {
            Text("Fit")
                .font(.eveCaptionBold)
                .foregroundStyle(.secondary)
                .frame(width: nameWidth, alignment: .leading)
                .padding(.leading, EVESpacing.lg)
            if showDetails {
                headerLabel("Value", width: valueWidth)
                headerLabel("Contents", width: contentsWidth)
                headerLabel("Saved By", width: ownersWidth)
            }
            ForEach(service.pilotIDs, id: \.self) { pilot in
                Button {
                    withAnimation(EVEMotion.snappy) { focusPilot = focusPilot == pilot ? nil : pilot }
                } label: {
                    VStack(spacing: 2) {
                        PilotPortrait(characterID: pilot, size: 28, ring: focusPilot == pilot ? palette.accent : nil)
                        Text(verbatim: name(pilot).components(separatedBy: " ").first ?? "")
                            .font(.eveMicro)
                            .lineLimit(1)
                            .foregroundStyle(focusPilot == pilot ? palette.accent : .secondary)
                        if let info = service.pilots[pilot] {
                            Text(verbatim: "\(info.readyCount)✓ · \(info.flyableCount)")
                                .font(.eveNano.monospacedDigit())
                                .foregroundStyle(.tertiary)
                        }
                    }
                    .frame(width: cellWidth)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(pilotHelp(pilot))
            }
            Text("Coverage")
                .font(.eveCaptionBold)
                .foregroundStyle(.secondary)
                .frame(width: coverageWidth, alignment: .leading)
                .padding(.leading, EVESpacing.md)
        }
        .padding(.vertical, EVESpacing.sm)
        .background(.bar)
    }

    private func headerLabel(_ title: LocalizedStringKey, width: CGFloat) -> some View {
        Text(title)
            .font(.eveCaptionBold)
            .foregroundStyle(.secondary)
            .frame(width: width, alignment: .leading)
    }

    private func pilotHelp(_ pilot: Int) -> Text {
        guard let info = service.pilots[pilot] else { return Text(verbatim: name(pilot)) }
        var parts = [info.name]
        if let location = info.location { parts.append(location.name) }
        if let ship = info.shipTypeName { parts.append(String(localized: "In a \(ship)")) }
        parts.append(String(localized: "\(info.readyCount) ready · \(info.flyableCount) flyable"))
        parts.append(String(localized: "Click to sort for this pilot"))
        return Text(verbatim: parts.joined(separator: "\n"))
    }

    private func matrixRow(_ row: HangarMatrixRow) -> some View {
        HStack(spacing: 0) {
            HStack(spacing: EVESpacing.md) {
                CachedAsyncImage(url: EVEImageURL.typeIcon(row.fit.fitting.shipTypeId, size: 64)) { image in
                    image.resizable()
                } placeholder: {
                    RoundedRectangle(cornerRadius: EVERadius.xs).fill(.quaternary)
                }
                .frame(width: 28, height: 28)
                .clipShape(RoundedRectangle(cornerRadius: EVERadius.xs))
                VStack(alignment: .leading, spacing: 1) {
                    Text(verbatim: row.name)
                        .font(.eveCalloutSemibold)
                        .lineLimit(1)
                        .eveTruncationHelp(row.name)
                    Text(verbatim: "\(row.shipTypeName) · \(row.shipClassName)")
                        .font(.eveMicro)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            .frame(width: nameWidth, alignment: .leading)
            .padding(.leading, EVESpacing.lg)
            .help(row.fit.fitting.description.isEmpty ? Text(verbatim: row.name)
                  : Text(verbatim: "\(row.name)\n\n\(row.fit.fitting.description)"))

            if showDetails {
                detailColumns(row)
            }

            ForEach(service.pilotIDs, id: \.self) { pilot in
                cell(row, pilot: pilot)
                    .frame(width: cellWidth, height: 40)
                    .background(focusPilot == pilot ? palette.accent.opacity(EVEOpacity.faint) : .clear)
            }

            VStack(alignment: .leading, spacing: 1) {
                Text("\(row.flyableCount)/\(service.pilotIDs.count) can fly")
                    .font(.eveCaptionMedium.monospacedDigit())
                    .foregroundStyle(row.flyableCount > 0 ? .primary : .secondary)
                if row.readyCount > 0 {
                    Text("\(row.readyCount) ready now")
                        .font(.eveMicro)
                        .foregroundStyle(ReadyRoomTier.ready.color(palette))
                } else if let best = row.bestPilot, let report = row.cells[best], report.tier < .train {
                    Text("Closest: \(name(best).components(separatedBy: " ").first ?? "")")
                        .font(.eveMicro)
                        .foregroundStyle(.secondary)
                } else if let training = row.shortestTraining {
                    Text("\(name(training.characterID).components(separatedBy: " ").first ?? "") in \(ReadyRoomFormat.duration(training.seconds))")
                        .font(.eveMicro)
                        .foregroundStyle(ReadyRoomTier.train.color(palette))
                        .help(Text("Shortest training to fly it"))
                }
            }
            .frame(width: coverageWidth, alignment: .leading)
            .padding(.leading, EVESpacing.md)
        }
        .padding(.vertical, EVESpacing.xs)
    }

    @ViewBuilder
    private func detailColumns(_ row: HangarMatrixRow) -> some View {
        Text(verbatim: row.fitValue.map { EVEFormatters.formatISKShort($0) } ?? "—")
            .font(.eveCaptionMedium.monospacedDigit())
            .foregroundStyle(row.fitValue == nil ? .tertiary : .primary)
            .frame(width: valueWidth, alignment: .leading)
            .help(Text("Jita value of the hull, modules, drones and cargo"))
        VStack(alignment: .leading, spacing: 1) {
            Text("\(row.moduleCount) modules")
            Text("\(row.requiredSkillCount) skills")
                .foregroundStyle(.tertiary)
        }
        .font(.eveMicro.monospacedDigit())
        .foregroundStyle(.secondary)
        .frame(width: contentsWidth, alignment: .leading)
        HStack(spacing: -7) {
            ForEach(row.ownerIDs.prefix(3), id: \.self) { owner in
                PilotPortrait(characterID: owner, size: 28, ring: Color(nsColor: .windowBackgroundColor))
            }
            if row.ownerIDs.count > 3 {
                Text(verbatim: "+\(row.ownerIDs.count - 3)")
                    .font(.eveCaptionMedium)
                    .foregroundStyle(.secondary)
                    .padding(.leading, 10)
            }
        }
        .frame(width: ownersWidth, alignment: .leading)
        .help(Text("Saved by \(row.ownerIDs.map(name).formatted(.list(type: .and)))"))
    }

    @ViewBuilder
    private func cell(_ row: HangarMatrixRow, pilot: Int) -> some View {
        if let report = row.cells[pilot] {
            let id = CellID(row: row.id, pilot: pilot)
            let isOwner = row.fit.owners[pilot] != nil
            Button {
                picked = id
            } label: {
                VStack(spacing: 1) {
                    Image(systemName: report.tier.systemImage)
                        .font(.caption)
                    Text(verbatim: cellCaption(report))
                        .font(.eveNano.monospacedDigit())
                        .lineLimit(1)
                }
                .foregroundStyle(report.tier.color(palette))
                .frame(width: cellWidth - 10, height: 34)
                .background(report.tier.color(palette).opacity(EVEOpacity.soft), in: RoundedRectangle(cornerRadius: EVERadius.sm))
                .overlay(alignment: .topTrailing) {
                    if isOwner {
                        Circle().fill(palette.accent).frame(width: 5, height: 5).padding(3)
                    }
                }
            }
            .buttonStyle(.plain)
            .eveHoverable(cornerRadius: EVERadius.sm)
            .help(Text("\(name(pilot)) · \(Text(report.tier.title))"))
            .popover(isPresented: Binding(get: { picked == id }, set: { if !$0 { picked = nil } }), arrowEdge: .trailing) {
                HangarMatrixCellDetail(report: report, pilotName: name(pilot), ownerFittingID: row.fit.owners[pilot],
                                       fitValue: row.fitValue) {
                    picked = nil
                    accountManager.selectedCharacterID = pilot
                    if let own = row.fit.owners[pilot] { AppRouter.shared.pendingReadyRoomFittingID = own }
                    AppRouter.shared.pendingSection = .readyRoom
                }
            }
        } else {
            Text(verbatim: "—").foregroundStyle(.tertiary)
        }
    }

    private func cellCaption(_ report: ReadyRoomReport) -> String {
        switch report.tier {
        case .ready:
            return String(localized: "Here")
        case .travel:
            return report.stagingJumps.map { String(localized: "\($0)j") } ?? String(localized: "Travel")
        case .waiting:
            let eta = report.requiredParts.flatMap(\.incoming).compactMap(\.eta).max()
            return eta.map { EVEFormatters.timeUntil($0) } ?? String(localized: "Incoming")
        case .buy:
            return report.missingISK.map { EVEFormatters.formatISKShort($0) } ?? String(localized: "Buy")
        case .train:
            if report.needsOmega && report.unqueuedGaps.isEmpty { return String(localized: "Ω") }
            return report.trainingSeconds.map { ReadyRoomFormat.duration($0) } ?? String(localized: "Train")
        case .blocked:
            return String(localized: "No fit")
        }
    }
}

// MARK:  Cell detail

private struct HangarMatrixCellDetail: View {
    let report: ReadyRoomReport
    let pilotName: String
    let ownerFittingID: Int?
    var fitValue: Double? = nil
    let openReadyRoom: () -> Void

    @Environment(ThemeManager.self) private var themeManager

    var body: some View {
        VStack(alignment: .leading, spacing: EVESpacing.md) {
            HStack(spacing: EVESpacing.sm) {
                Image(systemName: report.tier.systemImage)
                    .foregroundStyle(report.tier.color(themeManager.palette))
                Text(report.tier.title).font(.eveRowTitle)
            }
            Text(verbatim: "\(pilotName) · \(report.name)")
                .font(.caption)
                .foregroundStyle(.secondary)

            Grid(alignment: .leading, horizontalSpacing: EVESpacing.lg, verticalSpacing: EVESpacing.xs) {
                if let staging = report.staging {
                    row("Staging", staging.name)
                    if report.isStagingCurrentLocation {
                        row("Distance", String(localized: "Pilot is here"))
                    } else if let jumps = report.stagingJumps {
                        row("Distance", ReadyRoomFormat.jumps(jumps))
                    }
                    if report.hasJumpCloneAtStaging { row("Jump clone", String(localized: "At staging")) }
                }
                row("Parts", String(localized: "\(report.atStagingCount) here · \(report.ownedCount - report.atStagingCount) elsewhere · \(report.missingCount) missing"))
                if !report.collectionPlaceIDs.isEmpty {
                    row("Pick up from", String(localized: "\(report.collectionPlaceIDs.count) other stations"))
                }
                if report.corporationCount > 0 { row("From corp", String(localized: "\(report.corporationCount) parts")) }
                if report.incomingCount > 0 {
                    let eta = report.requiredParts.flatMap(\.incoming).compactMap(\.eta).max()
                    row("On the way", eta.map { String(localized: "\(report.incomingCount) parts · last in \(EVEFormatters.timeUntil($0))") }
                        ?? String(localized: "\(report.incomingCount) parts"))
                }
                if let isk = report.missingISK, isk > 0 { row("To buy", EVEFormatters.formatISK(isk)) }
                if let fitValue { row("Fit value", EVEFormatters.formatISK(fitValue)) }
                if let seconds = report.trainingSeconds, seconds > 0 { row("Training", ReadyRoomFormat.duration(seconds)) }
                if let queued = report.queuedUntil { row("Queued until", ReadyRoomFormat.queuedDate(queued)) }
                if report.needsOmega { row("Clone", String(localized: "Needs Omega")) }
                if let check = report.fitting {
                    row("CPU", usage(check.cpuUsed, check.cpuTotal, unit: "tf"))
                    row("Powergrid", usage(check.powerUsed, check.powerTotal, unit: "MW"))
                    if check.calibrationTotal > 0 { row("Calibration", usage(check.calibrationUsed, check.calibrationTotal, unit: "")) }
                    if !check.skillsToFit.isEmpty {
                        row("To fit", String(localized: "\(check.skillsToFit.count) fitting skills to train"))
                    }
                }
            }
            .font(.caption)

            if !report.unqueuedGaps.isEmpty {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(report.unqueuedGaps.prefix(5)) { gap in
                        Text(verbatim: "\(gap.name) \(ReadyRoomFormat.roman(gap.requiredLevel))")
                            .font(.caption)
                    }
                    if report.unqueuedGaps.count > 5 {
                        Text("+\(report.unqueuedGaps.count - 5) more skills")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Button(ownerFittingID == nil ? "Switch to \(pilotName)" : "Open in Ready Room", action: openReadyRoom)
                .help(ownerFittingID == nil
                      ? Text("This pilot hasn't saved this fit — save it to them to see it in their Ready Room.")
                      : Text("Opens this fit in \(pilotName)'s Ready Room"))
        }
        .padding()
        .frame(width: 300, alignment: .leading)
    }

    private func row(_ label: LocalizedStringKey, _ value: String) -> some View {
        GridRow {
            Text(label).foregroundStyle(.secondary)
            Text(verbatim: value).lineLimit(2)
        }
    }

    private func usage(_ used: Double, _ total: Double, unit: String) -> String {
        let percent = total > 0 ? Int((used / total * 100).rounded()) : 0
        let numbers = "\(used.formatted(.number.precision(.fractionLength(0)))) / \(total.formatted(.number.precision(.fractionLength(0)))) \(unit)"
        return "\(numbers.trimmingCharacters(in: .whitespaces)) · \(percent)%"
    }
}

// MARK:  Pilot card

private struct HangarMatrixPilotCard: View {
    let pilot: HangarMatrixPilot

    @Environment(ThemeManager.self) private var themeManager

    var body: some View {
        VStack(alignment: .leading, spacing: EVESpacing.sm) {
            HStack(spacing: EVESpacing.md) {
                PilotPortrait(characterID: pilot.characterID, size: 34)
                VStack(alignment: .leading, spacing: 1) {
                    Text(verbatim: pilot.name)
                        .font(.eveCalloutSemibold)
                        .lineLimit(1)
                    if let sp = pilot.totalSP {
                        Text(verbatim: EVEFormatters.formatSP(sp))
                            .font(.eveMicro)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            if let location = pilot.location {
                HStack(spacing: EVESpacing.xs) {
                    if let security = location.security { EVESecurityBadge(status: security, compact: true) }
                    Text(verbatim: location.name)
                        .lineLimit(1)
                }
                .font(.eveMicro)
                .foregroundStyle(.secondary)
                .help(Text(verbatim: location.name))
            }
            if let ship = pilot.shipTypeName {
                HStack(spacing: EVESpacing.xs) {
                    if let typeID = pilot.shipTypeID {
                        CachedAsyncImage(url: EVEImageURL.typeIcon(typeID, size: 64)) { image in
                            image.resizable()
                        } placeholder: {
                            RoundedRectangle(cornerRadius: 3).fill(.quaternary)
                        }
                        .frame(width: 14, height: 14)
                        .clipShape(RoundedRectangle(cornerRadius: 3))
                    }
                    Text(verbatim: ship).lineLimit(1)
                }
                .font(.eveMicro)
                .foregroundStyle(.secondary)
            }
            HStack(spacing: EVESpacing.xs) {
                EVEChip(Text("\(pilot.readyCount) ready"),
                        tint: pilot.readyCount > 0 ? ReadyRoomTier.ready.color(themeManager.palette) : .secondary)
                EVEChip(Text("\(pilot.flyableCount) flyable"), tint: .secondary)
            }
            HStack(spacing: EVESpacing.xs) {
                Image(systemName: "person.2.fill")
                if pilot.jumpCloneCount == 0 {
                    Text("No jump clones")
                } else if let ready = pilot.cloneJumpReadyAt {
                    Text("\(pilot.jumpCloneCount) clones · jump in \(EVEFormatters.timeUntil(ready))")
                } else {
                    Text("\(pilot.jumpCloneCount) clones · jump ready")
                }
            }
            .font(.eveMicro)
            .foregroundStyle(pilot.jumpCloneCount > 0 && pilot.cloneJumpReadyAt == nil ? Color.green : .secondary)
            if pilot.implantCount > 0 || pilot.isRemapAvailable {
                HStack(spacing: EVESpacing.xs) {
                    if pilot.implantCount > 0 {
                        Label("\(pilot.implantCount) implants", systemImage: "cpu")
                    }
                    if pilot.isRemapAvailable {
                        Label("Remap", systemImage: "arrow.triangle.2.circlepath")
                            .foregroundStyle(themeManager.palette.knowledge)
                    }
                }
                .font(.eveMicro)
                .foregroundStyle(.secondary)
            }
        }
        .padding(EVESpacing.md)
        .frame(width: 210, alignment: .leading)
        .eveCard(cornerRadius: EVERadius.xl)
    }
}
