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

// MARK:  Sort

enum ReadyRoomSort: String, CaseIterable {
    case readiness, nearest, cheapest, training, name

    var title: LocalizedStringKey {
        switch self {
        case .readiness: "Closest to Ready"
        case .nearest:   "Nearest"
        case .cheapest:  "Cheapest to Complete"
        case .training:  "Shortest Training"
        case .name:      "Name"
        }
    }

    var systemImage: String {
        switch self {
        case .readiness: "checkmark.seal"
        case .nearest:   "location"
        case .cheapest:  "banknote"
        case .training:  "graduationcap"
        case .name:      "textformat"
        }
    }
}

// MARK:  Tab

enum ReadyRoomTab: String, CaseIterable {
    case fits, forge

    var title: LocalizedStringKey {
        switch self {
        case .fits:  "Saved Fits"
        case .forge: "Hangar Forge"
        }
    }

    var systemImage: String {
        switch self {
        case .fits:  "bookmark.fill"
        case .forge: "hammer.fill"
        }
    }
}

// MARK:  Main View

/// "What can I fly right now?" — every saved fitting checked against the pilot's skills,
/// skill queue, assets, location and fitting budget, grouped by how close it is to undocking.
struct ReadyRoomView: View {
    @Environment(AccountManager.self) private var accountManager
    @Environment(DashboardPrefetcher.self) private var prefetcher
    @Environment(ThemeManager.self) private var themeManager
    @AppStorage("backgroundPollInterval") private var pollInterval: Double = 300
    @AppStorage("readyRoom.sort") private var sortRaw = ReadyRoomSort.readiness.rawValue
    @AppStorage("collapsedReadyRoomSections") private var collapsedRaw = ""
    @AppStorage("readyRoom.tab") private var tabRaw = ReadyRoomTab.fits.rawValue

    @State private var selectedID: Int?
    /// A fit another screen linked to, to bring into view once the board shows it.
    @State private var scrollTarget: Int?
    @State private var search = ""
    @State private var tierFilter: ReadyRoomTier?

    private var service: ReadyRoomService { .shared }
    private var palette: EVEPalette { themeManager.palette }
    private var characterID: Int? { accountManager.selectedCharacterID }
    private var snapshot: ReadyRoomSnapshot? { characterID.flatMap { service.snapshots[$0] } }
    private var isLoading: Bool { characterID.map(service.isLoading) ?? false }
    private var error: String? { characterID.flatMap { service.errors[$0] } }
    private var reports: [ReadyRoomReport] { snapshot?.reports ?? [] }
    private var pinned: Set<Int> { characterID.map(service.pinnedFittingIDs) ?? [] }
    private var sort: ReadyRoomSort { ReadyRoomSort(rawValue: sortRaw) ?? .readiness }
    private var tab: ReadyRoomTab { ReadyRoomTab(rawValue: tabRaw) ?? .fits }

    var body: some View {
        LoadingStateView(
            isLoading: isLoading && snapshot == nil,
            error: snapshot == nil ? error : nil,
            hasContent: snapshot != nil,
            onRetry: { Task { await load(force: true) } }
        ) {
            switch tab {
            case .fits:
                content
            case .forge:
                if let snapshot {
                    ScrollView {
                        HangarForgeView(snapshot: snapshot)
                            .padding()
                    }
                }
            }
        }
        .eveScreenHeader("Ready Room", subtitle: tab == .fits ? subtitle : nil, section: .readyRoom) {
            HStack(spacing: EVESpacing.md) {
                tabSwitcher
                FreshnessIndicator(isLoading: isLoading) { await load(force: true) }
            }
        }
        .eveInspector(item: $selectedID, minWidth: 340, idealWidth: 380, maxWidth: 440) { id in
            if let snapshot, let report = snapshot.reports.first(where: { $0.id == id }) {
                ReadyRoomDetailPane(report: report, snapshot: snapshot)
            }
        }
        .task(id: characterID) {
            selectedID = nil
            // A link from another screen is set before this one appears, so `onChange`
            // never sees it — take it from the board already loaded, or the fresh one.
            consumePendingFitting()
            if let characterID { service.markSeen(characterID) }
            await load()
            consumePendingFitting()
        }
        .autoRefresh(every: pollInterval) { await load() }
        .onChange(of: prefetcher.lastRefresh) { _, _ in Task { await load() } }
        .onChange(of: AppRouter.shared.refreshTick) { _, _ in Task { await load(force: true) } }
        .onChange(of: service.includeCorporation) { _, _ in Task { await load() } }
        .onChange(of: characterID.flatMap { service.unseenReady[$0]?.count }) { _, count in
            // Fits that turned ready in the background while this screen is open are seen.
            if let characterID, (count ?? 0) > 0 { service.markSeen(characterID) }
        }
        .onChange(of: snapshot?.reports.map(\.id)) { _, _ in consumePendingFitting() }
        .onChange(of: AppRouter.shared.pendingReadyRoomFittingID) { _, _ in consumePendingFitting() }
        .onChange(of: tabRaw) { _, _ in selectedID = nil }
    }

    /// Saved Fits / Hangar Forge, as icons with their names in tooltips. Buttons rather
    /// than a segmented picker: AppKit's segmented control drops a Label's icon.
    private var tabSwitcher: some View {
        HStack(spacing: EVESpacing.xxs) {
            ForEach(ReadyRoomTab.allCases, id: \.self) { option in
                let isSelected = tab == option
                Button {
                    tabRaw = option.rawValue
                } label: {
                    Label(option.title, systemImage: option.systemImage)
                        .labelStyle(.iconOnly)
                        .font(.subheadline)
                        .padding(.horizontal, 10)
                        .padding(.vertical, EVESpacing.xs)
                        .background(isSelected ? palette.accent : Color.clear,
                                    in: RoundedRectangle(cornerRadius: EVERadius.sm))
                        .foregroundStyle(isSelected ? .white : .primary)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(option.title)
                .accessibilityAddTraits(isSelected ? .isSelected : [])
            }
        }
        .padding(3)
        .background(.quaternary, in: RoundedRectangle(cornerRadius: EVERadius.md))
        .fixedSize()
    }

    private func load(force: Bool = false) async {
        guard let account = accountManager.selectedAccount else { return }
        await service.refresh(account, accountManager: accountManager, prefetcher: prefetcher, force: force)
    }

    private var subtitle: Text? {
        guard !reports.isEmpty else { return nil }
        let ready = reports.filter { $0.tier == .ready }.count
        return Text("\(reports.count) fits · \(ready) ready to undock")
    }

    // MARK:  Content

    @ViewBuilder
    private var content: some View {
        if reports.isEmpty {
            if isLoading {
                LoadingSkeleton()
            } else if let error {
                EVEEmptyState(title: Text("Something Went Wrong"), systemImage: "exclamationmark.triangle",
                              message: Text(error), tint: .orange) {
                    Button("Try Again", systemImage: "arrow.clockwise") { Task { await load(force: true) } }
                        .buttonStyle(.borderedProminent)
                        .tint(palette.accent)
                }
            } else {
                EVEEmptyState("No Saved Fittings", systemImage: "wrench.and.screwdriver",
                              message: Text("Save a fitting in EVE or from Ships & Fittings, and the Ready Room will check whether you can fly it.")) {
                    Button("Open Fittings") { AppRouter.shared.pendingSection = .fittings }
                        .buttonStyle(.borderedProminent)
                        .tint(palette.accent)
                }
            }
        } else {
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: EVESpacing.xl) {
                        if let error {
                            banner(Text("Couldn’t refresh — showing earlier results. \(error)"))
                        }
                        if let note = snapshot?.corporationNote {
                            banner(Text(note))
                        }
                        summaryStrip
                        filterBar
                        let sections = visibleSections
                        if sections.isEmpty {
                            EVEEmptyState("No Matching Fits", systemImage: "line.3.horizontal.decrease.circle",
                                          message: Text("Try a different search or clear the filter.")) {
                                Button("Clear Filters") {
                                    search = ""
                                    tierFilter = nil
                                }
                            }
                            .frame(minHeight: 260)
                        } else {
                            ForEach(sections, id: \.key) { section in
                                boardSection(section)
                            }
                        }
                    }
                    .padding()
                }
                .eveKeyboardSelection(visibleIDs, selection: selectedID) { selectedID = $0 }
                .onChange(of: scrollTarget) { _, target in
                    guard let target else { return }
                    // Let an expanded section lay out before scrolling into it.
                    DispatchQueue.main.async {
                        withAnimation(EVEMotion.snappy) { proxy.scrollTo(target, anchor: .center) }
                        scrollTarget = nil
                    }
                }
            }
        }
    }

    private func banner(_ text: Text) -> some View {
        Label {
            text
        } icon: {
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
        }
        .font(.caption)
        .padding(EVESpacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.orange.opacity(EVEOpacity.faint), in: RoundedRectangle(cornerRadius: EVERadius.md))
    }

    // MARK:  Summary

    private var summaryStrip: some View {
        let byTier = Dictionary(grouping: reports, by: \.tier)
        func count(_ tier: ReadyRoomTier) -> Int { byTier[tier]?.count ?? 0 }
        let nearestTravel = byTier[.travel]?.compactMap(\.stagingJumps).min()
        let cheapestBuy = byTier[.buy]?.compactMap(\.missingISK).min()
        let shortestTraining = byTier[.train]?.compactMap(\.trainingSeconds).filter { $0 > 0 }.min()
        let soonestArrival = byTier[.waiting]?.flatMap { $0.requiredParts.flatMap(\.incoming) }.compactMap(\.eta).min()

        return HStack(spacing: EVESpacing.md) {
            filterTile(.ready, value: count(.ready),
                       subLabel: count(.ready) == 0 ? nil : String(localized: "in this station"))
            filterTile(.travel, value: count(.travel),
                       subLabel: nearestTravel.map { String(localized: "nearest \(ReadyRoomFormat.jumps($0).lowercased())") })
            if count(.waiting) > 0 {
                filterTile(.waiting, value: count(.waiting),
                           subLabel: soonestArrival.map { String(localized: "first in \(EVEFormatters.timeUntil($0))") })
            }
            filterTile(.buy, value: count(.buy),
                       subLabel: cheapestBuy.map { String(localized: "from \(EVEFormatters.formatISKShort($0))") })
            filterTile(.train, value: count(.train),
                       subLabel: shortestTraining.map { String(localized: "shortest \(ReadyRoomFormat.duration($0))") })
            if count(.blocked) > 0 {
                filterTile(.blocked, value: count(.blocked), subLabel: String(localized: "over CPU or PG"))
            }
        }
    }

    /// A summary tile that filters the board to its tier; clicking it again clears the filter.
    private func filterTile(_ tier: ReadyRoomTier, value: Int, subLabel: String?) -> some View {
        let isActive = tierFilter == tier
        return Button {
            withAnimation(EVEMotion.snappy) { tierFilter = isActive ? nil : tier }
        } label: {
            MetricTileView(icon: tier.systemImage,
                           color: value > 0 ? tier.color(palette) : .secondary,
                           value: "\(value)",
                           label: tier.shortTitle,
                           subLabel: subLabel)
                .eveSelectionGlow(isActive: isActive, cornerRadius: EVERadius.xl)
        }
        .buttonStyle(.plain)
        .eveHoverable(cornerRadius: EVERadius.xl)
        .help(isActive ? Text("Show all fits") : Text("Show only “\(Text(tier.title))”"))
        .accessibilityAddTraits(isActive ? .isSelected : [])
    }

    // MARK:  Filter bar

    private var filterBar: some View {
        HStack(spacing: EVESpacing.md) {
            EVESearchField("Search fits, hulls or classes", text: $search)
                .frame(maxWidth: 320)
            if let tierFilter {
                Button {
                    withAnimation(EVEMotion.snappy) { self.tierFilter = nil }
                } label: {
                    HStack(spacing: EVESpacing.xs) {
                        Text(tierFilter.title)
                        Image(systemName: "xmark")
                            .font(.eveNanoBold)
                    }
                }
                .buttonStyle(.plain)
                .modifier(ReadyRoomChipStyle(tint: tierFilter.color(palette)))
                .help("Clear filter")
                .transition(.opacity.combined(with: .scale(scale: 0.9)))
            }
            fitCheckStatus
            Spacer()
            Button {
                service.includeCorporation.toggle()
            } label: {
                Label("Corp Hangars", systemImage: service.includeCorporation ? "building.2.fill" : "building.2")
            }
            .buttonStyle(.plain)
            .modifier(ReadyRoomChipStyle(tint: service.includeCorporation ? palette.accent : .secondary))
            .help(service.includeCorporation
                  ? "Counting parts in corporation hangars — click to count only your own"
                  : "Also count parts in corporation hangars (needs the Director role)")
            .accessibilityAddTraits(service.includeCorporation ? .isSelected : [])
            EVEMenuPicker("Sort", selection: Binding(get: { sort }, set: { sortRaw = $0.rawValue }),
                          options: ReadyRoomSort.allCases.map { EVEMenuOption($0, $0.title, systemImage: $0.systemImage) })
        }
    }

    @ViewBuilder
    private var fitCheckStatus: some View {
        switch snapshot?.fittingCheck {
        case .pending?:
            HStack(spacing: EVESpacing.xs) {
                ProgressView().controlSize(.mini)
                Text("Checking CPU and powergrid…")
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        case .unavailable?:
            Label("Fit check unavailable", systemImage: "cpu")
                .font(.caption)
                .foregroundStyle(.secondary)
                .help("The fitting engine's data couldn't be loaded. Open the Simulator once to download it.")
        default:
            EmptyView()
        }
    }

    // MARK:  Sections

    private struct BoardSection {
        let key: String
        let tier: ReadyRoomTier?
        let reports: [ReadyRoomReport]
    }

    private var filteredReports: [ReadyRoomReport] {
        let needle = search.trimmingCharacters(in: .whitespacesAndNewlines)
        return reports.filter { report in
            (tierFilter == nil || report.tier == tierFilter)
                && (needle.isEmpty
                    || report.name.localizedCaseInsensitiveContains(needle)
                    || report.shipTypeName.localizedCaseInsensitiveContains(needle)
                    || report.shipClassName.localizedCaseInsensitiveContains(needle))
        }
    }

    /// Pinned fits first in their own section, then the rest by tier.
    private var visibleSections: [BoardSection] {
        let pins = pinned
        let filtered = filteredReports
        var sections: [BoardSection] = []
        let pinnedReports = filtered.filter { pins.contains($0.fittingID) }
        if !pinnedReports.isEmpty {
            sections.append(BoardSection(key: "pinned", tier: nil,
                                         reports: pinnedReports.sorted { $0.tier != $1.tier ? $0.tier < $1.tier : ordering($0, $1) }))
        }
        let grouped = Dictionary(grouping: filtered.filter { !pins.contains($0.fittingID) }, by: \.tier)
        for tier in ReadyRoomTier.allCases {
            guard let list = grouped[tier], !list.isEmpty else { continue }
            sections.append(BoardSection(key: "\(tier.rawValue)", tier: tier, reports: list.sorted(by: ordering)))
        }
        return sections
    }

    /// Cards in expanded sections, in display order — the ↑/↓ navigation order.
    private var visibleIDs: [Int] {
        visibleSections.filter { !isCollapsed($0.key) }.flatMap { $0.reports.map(\.id) }
    }

    private func ordering(_ a: ReadyRoomReport, _ b: ReadyRoomReport) -> Bool {
        func byName() -> Bool { a.name.localizedStandardCompare(b.name) == .orderedAscending }
        func compare<T: Comparable>(_ x: T?, _ y: T?) -> Bool {
            switch (x, y) {
            case let (x?, y?): return x != y ? x < y : byName()
            case (.some, nil): return true
            case (nil, .some): return false
            case (nil, nil):   return byName()
            }
        }
        switch sort {
        case .readiness:
            // Within a tier, the fit with the least left to do first.
            let ra = Double(a.missingCount) + (a.trainingSeconds ?? 0) / 3600 + Double(a.stagingJumps ?? 0)
            let rb = Double(b.missingCount) + (b.trainingSeconds ?? 0) / 3600 + Double(b.stagingJumps ?? 0)
            return ra != rb ? ra < rb : byName()
        case .nearest:  return compare(a.isStagingCurrentLocation ? -1 : a.stagingJumps, b.isStagingCurrentLocation ? -1 : b.stagingJumps)
        case .cheapest: return compare(a.missingISK, b.missingISK)
        case .training: return compare(a.trainingSeconds, b.trainingSeconds)
        case .name:     return byName()
        }
    }

    private func isCollapsed(_ key: String) -> Bool {
        collapsedRaw.split(separator: ",").contains(Substring(key))
    }

    private func toggleCollapsed(_ key: String) {
        var set = Set(collapsedRaw.split(separator: ",").map(String.init))
        if set.contains(key) { set.remove(key) } else { set.insert(key) }
        collapsedRaw = set.sorted().joined(separator: ",")
    }

    private func boardSection(_ section: BoardSection) -> some View {
        let collapsed = isCollapsed(section.key)
        return VStack(alignment: .leading, spacing: EVESpacing.md) {
            Button {
                withAnimation(EVEMotion.section) { toggleCollapsed(section.key) }
            } label: {
                HStack(spacing: EVESpacing.md) {
                    Image(systemName: "chevron.right")
                        .font(.caption.bold())
                        .foregroundStyle(.secondary)
                        .rotationEffect(.degrees(collapsed ? 0 : 90))
                    if let tier = section.tier {
                        Image(systemName: tier.systemImage)
                            .foregroundStyle(tier.color(palette))
                        Text(tier.title).font(.title2.bold())
                    } else {
                        Image(systemName: "pin.fill")
                            .foregroundStyle(palette.accent)
                        Text("Pinned").font(.title2.bold())
                    }
                    Spacer()
                    if section.tier == nil {
                        let ready = section.reports.filter { $0.tier == .ready }.count
                        Text("\(ready) of \(section.reports.count) ready")
                            .font(.subheadline.monospacedDigit())
                            .foregroundStyle(.secondary)
                    } else {
                        Text("\(section.reports.count)")
                            .font(.subheadline.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityAddTraits(.isHeader)
            .accessibilityValue(collapsed ? Text("Collapsed") : Text("Expanded"))

            if !collapsed {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 300), spacing: EVESpacing.md)],
                          spacing: EVESpacing.md) {
                    ForEach(section.reports) { report in
                        card(report)
                    }
                }
                .transition(.opacity)
            }
        }
    }

    private func card(_ report: ReadyRoomReport) -> some View {
        let isPinned = pinned.contains(report.fittingID)
        return Button {
            selectedID = report.id
        } label: {
            ReadyRoomCard(report: report, isSelected: selectedID == report.id, isPinned: isPinned,
                          fitCheck: snapshot?.fittingCheck ?? .pending)
        }
        .buttonStyle(.plain)
        .id(report.id)
        .eveScrollReveal()
        .contextMenu {
            if let characterID {
                Button(isPinned ? "Unpin" : "Pin to Top", systemImage: isPinned ? "pin.slash" : "pin") {
                    withAnimation(EVEMotion.snappy) { service.togglePin(report.fittingID, characterID: characterID) }
                }
            }
            Button("Show in Fittings", systemImage: "wrench.and.screwdriver") {
                AppRouter.shared.pendingSavedFittingID = report.fittingID
                AppRouter.shared.pendingSection = .fittings
            }
        }
    }

    // MARK:  Deep link

    /// Selects the fitting the Fittings screen asked for, once its report exists.
    private func consumePendingFitting() {
        guard let pending = AppRouter.shared.pendingReadyRoomFittingID,
              let report = reports.first(where: { $0.fittingID == pending }) else { return }
        AppRouter.shared.pendingReadyRoomFittingID = nil
        tabRaw = ReadyRoomTab.fits.rawValue
        search = ""
        tierFilter = nil
        let key = pinned.contains(report.fittingID) ? "pinned" : "\(report.tier.rawValue)"
        if isCollapsed(key) { toggleCollapsed(key) }
        selectedID = report.id
        scrollTarget = report.id
    }
}

/// A small tinted capsule control in the filter bar — `EVEChip`'s shape, as a button.
struct ReadyRoomChipStyle: ViewModifier {
    let tint: Color

    func body(content: Content) -> some View {
        content
            .font(.eveCaptionBold)
            .foregroundStyle(tint)
            .padding(.horizontal, EVESpacing.md)
            .padding(.vertical, 3)
            .background(tint.opacity(EVEOpacity.soft), in: Capsule())
            .eveHoverable(cornerRadius: 20)
    }
}
