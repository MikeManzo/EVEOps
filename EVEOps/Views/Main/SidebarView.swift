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
import AppKit

struct SidebarView: View {
    @Bindable var accountManager: AccountManager
    @Binding var selectedSection: NavigationSection?

    @Environment(ThemeManager.self) private var themeManager
    @Environment(DashboardPrefetcher.self) private var prefetcher
    private var palette: EVEPalette { themeManager.palette }

    private enum NavScope: Hashable {
        case character
        case corporation
    }

    @AppStorage("sidebar.pinnedExpanded") private var pinnedExpanded = true
    @AppStorage("sidebar.pilotExpanded") private var pilotExpanded = true
    @AppStorage("sidebar.economyExpanded") private var economyExpanded = true
    @AppStorage("sidebar.combatExpanded") private var combatExpanded = true
    @AppStorage("sidebar.socialExpanded") private var socialExpanded = true
    @AppStorage("sidebar.universeExpanded") private var universeExpanded = true
    @AppStorage("sidebar.corpExpanded") private var corpExpanded = true
    @AppStorage("sidebar.utilityExpanded") private var utilityExpanded = true

    @AppStorage("sidebar.showPinned") private var showPinnedSection = true
    @AppStorage("sidebar.showPilot") private var showPilotSection = true
    @AppStorage("sidebar.showEconomy") private var showEconomySection = true
    @AppStorage("sidebar.showCombat") private var showCombatSection = true
    @AppStorage("sidebar.showSocial") private var showSocialSection = true
    @AppStorage("sidebar.showUniverse") private var showUniverseSection = true
    @AppStorage("sidebar.showCorp") private var showCorpSection = true
    @AppStorage("sidebar.showUtility") private var showUtilitySection = true
    @AppStorage("sidebar.pinnedSections") private var pinnedSectionsRaw =
        NavigationSection.quickJumpSlots.map(\.rawValue).joined(separator: ",")

    @AppStorage("sidebar.orderPilot") private var pilotOrderRaw = ""
    @AppStorage("sidebar.orderEconomy") private var economyOrderRaw = ""
    @AppStorage("sidebar.orderCombat") private var combatOrderRaw = ""
    @AppStorage("sidebar.orderSocial") private var socialOrderRaw = ""
    @AppStorage("sidebar.orderUniverse") private var universeOrderRaw = ""
    @AppStorage("sidebar.orderCorp") private var corpOrderRaw = ""
    @AppStorage("sidebar.orderUtility") private var utilityOrderRaw = ""

    private static let maxPinned = 9

    @State private var todayEventCount = 0
    @State private var filterText = ""
    @State private var showPilotPicker = false
    @State private var navScope: NavScope = .character

    var body: some View {
        VStack(spacing: 0) {
            accountSwitcher

            let reauthAccounts = accountManager.accounts.filter { $0.needsReauth }
            if !reauthAccounts.isEmpty {
                reauthBanner(reauthAccounts)
            }

            if accountManager.selectedAccount != nil {
                scopeAndFilterRow
            }

            // Plain List, no `selection:` binding — deliberately. On macOS, a
            // `List(selection:)`'s native "selected row" highlight paints *on top of*
            // whatever `.listRowBackground`/`.listItemTint` supply, so no color we set
            // ever fully takes; screenshots across several attempts kept showing the
            // system's own color winning. Managing selection ourselves (state + tap
            // gesture + a plain, non-competing row background) sidesteps that fight
            // entirely — the same pattern already working correctly elsewhere in the app
            // for lists that don't use `selection:`. Trade-off: native arrow-key row
            // navigation in the sidebar is lost.
            List {
                Label {
                    Text("Dashboard")
                } icon: {
                    Image(systemName: "square.grid.2x2.fill")
                        .foregroundStyle(selectedSection == .dashboard ? .white : palette.accent)
                }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                    .onTapGesture { selectedSection = .dashboard }
                    .foregroundStyle(selectedSection == .dashboard ? .white : .primary)
                    .listRowBackground(
                        selectedSection == .dashboard
                            ? RoundedRectangle(cornerRadius: EVERadius.sm).fill(palette.accent)
                            : nil
                    )

                if let account = accountManager.selectedAccount {
                    if navScope == .character || !showCorpSection {
                        if showPinnedSection && shouldShow(pinnedSections) {
                            Section(
                                isExpanded: expandedBinding($pinnedExpanded),
                                content: {
                                    ForEach(rows(filtered(pinnedSections), group: "pinned")) { row in
                                        navRow(row.section)
                                    }
                                    .onMove { indices, offset in
                                        let updated = reordered(pinnedSections, move: indices, to: offset)
                                        pinnedSectionsRaw = updated.map(\.rawValue).joined(separator: ",")
                                    }
                                    .moveDisabled(!filterText.isEmpty)
                                },
                                header: {
                                    sectionHeader("Pinned (\(pinnedSections.count)/\(Self.maxPinned))", systemImage: "pin.fill", tint: .pinAccent)
                                }
                            )
                        }

                        if showPilotSection && shouldShow(pilotSectionsOrdered) {
                            Section(
                                isExpanded: expandedBinding($pilotExpanded),
                                content: {
                                    ForEach(rows(filtered(pilotSectionsOrdered), group: "pilot")) { row in
                                        navRow(row.section)
                                    }
                                    .onMove { indices, offset in
                                        let updated = reordered(pilotSectionsOrdered, move: indices, to: offset)
                                        pilotOrderRaw = updated.map(\.rawValue).joined(separator: ",")
                                    }
                                    .moveDisabled(!filterText.isEmpty)
                                },
                                header: {
                                    sectionHeader("Pilot — \(account.characterName)", systemImage: "person.fill", tint: .teal)
                                }
                            )
                        }

                        if showEconomySection && shouldShow(economySectionsOrdered) {
                            Section(
                                isExpanded: expandedBinding($economyExpanded),
                                content: {
                                    ForEach(rows(filtered(economySectionsOrdered), group: "economy")) { row in
                                        navRow(row.section)
                                    }
                                    .onMove { indices, offset in
                                        let updated = reordered(economySectionsOrdered, move: indices, to: offset)
                                        economyOrderRaw = updated.map(\.rawValue).joined(separator: ",")
                                    }
                                    .moveDisabled(!filterText.isEmpty)
                                },
                                header: {
                                    sectionHeader("Economy", systemImage: "banknote.fill", tint: .green)
                                }
                            )
                        }

                        if showCombatSection && shouldShow(combatSectionsOrdered) {
                            Section(
                                isExpanded: expandedBinding($combatExpanded),
                                content: {
                                    ForEach(rows(filtered(combatSectionsOrdered), group: "combat")) { row in
                                        navRow(row.section)
                                    }
                                    .onMove { indices, offset in
                                        let updated = reordered(combatSectionsOrdered, move: indices, to: offset)
                                        combatOrderRaw = updated.map(\.rawValue).joined(separator: ",")
                                    }
                                    .moveDisabled(!filterText.isEmpty)
                                },
                                header: {
                                    sectionHeader("Combat & Fleet", systemImage: "bolt.shield.fill", tint: .red)
                                }
                            )
                        }

                        if showSocialSection && shouldShow(socialSectionsOrdered) {
                            Section(
                                isExpanded: expandedBinding($socialExpanded),
                                content: {
                                    ForEach(rows(filtered(socialSectionsOrdered), group: "social")) { row in
                                        navRow(row.section)
                                    }
                                    .onMove { indices, offset in
                                        let updated = reordered(socialSectionsOrdered, move: indices, to: offset)
                                        socialOrderRaw = updated.map(\.rawValue).joined(separator: ",")
                                    }
                                    .moveDisabled(!filterText.isEmpty)
                                },
                                header: {
                                    sectionHeader("Social & Comms", systemImage: "bubble.left.and.bubble.right.fill", tint: .purple)
                                }
                            )
                        }

                        if showUniverseSection && shouldShow(universeSectionsOrdered) {
                            Section(
                                isExpanded: expandedBinding($universeExpanded),
                                content: {
                                    ForEach(rows(filtered(universeSectionsOrdered), group: "universe")) { row in
                                        navRow(row.section)
                                    }
                                    .onMove { indices, offset in
                                        let updated = reordered(universeSectionsOrdered, move: indices, to: offset)
                                        universeOrderRaw = updated.map(\.rawValue).joined(separator: ",")
                                    }
                                    .moveDisabled(!filterText.isEmpty)
                                },
                                header: {
                                    sectionHeader("Universe", systemImage: "globe", tint: .cyan)
                                }
                            )
                        }
                    }

                    if showCorpSection && navScope == .corporation && shouldShow(corporationSectionsOrdered) {
                        Section(
                            isExpanded: expandedBinding($corpExpanded),
                            content: {
                                ForEach(rows(filtered(corporationSectionsOrdered), group: "corp")) { row in
                                    navRow(row.section)
                                }
                                .onMove { indices, offset in
                                    let updated = reordered(corporationSectionsOrdered, move: indices, to: offset)
                                    corpOrderRaw = updated.map(\.rawValue).joined(separator: ",")
                                }
                                .moveDisabled(!filterText.isEmpty)
                            },
                            header: {
                                sectionHeader("Corp: \(account.corporationName)", systemImage: "building.2.fill", tint: .brown)
                            }
                        )
                    }
                }

                if showUtilitySection && shouldShow(utilitySectionsOrdered) {
                    Section(
                        isExpanded: expandedBinding($utilityExpanded),
                        content: {
                            ForEach(rows(filtered(utilitySectionsOrdered), group: "utility")) { row in
                                navRow(row.section)
                            }
                            .onMove { indices, offset in
                                let updated = reordered(utilitySectionsOrdered, move: indices, to: offset)
                                utilityOrderRaw = updated.map(\.rawValue).joined(separator: ",")
                            }
                            .moveDisabled(!filterText.isEmpty)
                        },
                        header: {
                            sectionHeader("Utility", systemImage: "terminal")
                        }
                    )
                }

                if filterHasNoMatches {
                    noFilterMatchesRow
                }
            }
            .listStyle(.sidebar)
            .animation(.easeInOut(duration: 0.2), value: navScope)
            .focusable()
            .onKeyPress(.upArrow) { moveSelection(-1); return .handled }
            .onKeyPress(.downArrow) { moveSelection(1); return .handled }

            Divider()

            addAccountButton
        }
        .frame(minWidth: 200)
        .background(SplitViewAutosaver())
        .task(id: accountManager.selectedCharacterID) {
            todayEventCount = 0
            guard let account = accountManager.selectedAccount else { return }
            do {
                let token = try await accountManager.validToken(for: account)
                let events: [ESICalendarEvent] = try await ESIClient.shared.fetch(
                    "/characters/\(account.characterID)/calendar/", token: token
                )
                let today = Calendar.current.startOfDay(for: Date())
                todayEventCount = events.filter { event in
                    guard let d = event.eventDate else { return false }
                    return Calendar.current.startOfDay(for: d) == today
                }.count
            } catch {
                logSuppressed(error, "Sidebar: today's calendar event count")
            }
        }
    }

    // MARK:  User-defined ordering

    private var pilotSectionsOrdered: [NavigationSection] {
        applyCustomOrder(NavigationSection.pilotSections, raw: pilotOrderRaw)
    }
    private var economySectionsOrdered: [NavigationSection] {
        applyCustomOrder(NavigationSection.economySections, raw: economyOrderRaw)
    }
    private var combatSectionsOrdered: [NavigationSection] {
        applyCustomOrder(NavigationSection.combatSections, raw: combatOrderRaw)
    }
    private var socialSectionsOrdered: [NavigationSection] {
        applyCustomOrder(NavigationSection.socialSections, raw: socialOrderRaw)
    }
    private var universeSectionsOrdered: [NavigationSection] {
        applyCustomOrder(NavigationSection.universeSections, raw: universeOrderRaw)
    }
    private var corporationSectionsOrdered: [NavigationSection] {
        applyCustomOrder(NavigationSection.corporationSections, raw: corpOrderRaw)
    }
    private var utilitySectionsOrdered: [NavigationSection] {
        applyCustomOrder(NavigationSection.utilitySections, raw: utilityOrderRaw)
    }

    /// Applies a stored custom order on top of a section's default array, dropping
    /// any stale entries and appending items the user hasn't touched (new sections
    /// added in an app update) to the end in their default order.
    private func applyCustomOrder(_ base: [NavigationSection], raw: String) -> [NavigationSection] {
        guard !raw.isEmpty else { return base }
        let stored = raw.split(separator: ",").compactMap { NavigationSection(rawValue: String($0)) }
        var ordered = stored.filter { base.contains($0) }
        ordered.append(contentsOf: base.filter { !ordered.contains($0) })
        return ordered
    }

    private func reordered(_ current: [NavigationSection], move indices: IndexSet, to offset: Int) -> [NavigationSection] {
        var updated = current
        updated.move(fromOffsets: indices, toOffset: offset)
        return updated
    }

    /// A section can appear in more than one group (Pinned duplicates items from
    /// their home section). `NavigationSection`'s own id is shared in that case,
    /// and two `ForEach`s in the same `List` sharing ids confuses SwiftUI's
    /// diffing — a drag in one group can get misattributed to the other. Scoping
    /// the id by group keeps every `ForEach`'s rows uniquely identified.
    private struct SidebarRow: Identifiable {
        let id: String
        let section: NavigationSection
    }

    private func rows(_ sections: [NavigationSection], group: String) -> [SidebarRow] {
        sections.map { SidebarRow(id: "\(group).\($0.rawValue)", section: $0) }
    }

    // MARK:  Pinning

    private var pinnedSections: [NavigationSection] {
        pinnedSectionsRaw
            .split(separator: ",")
            .compactMap { NavigationSection(rawValue: String($0)) }
    }

    /// A section header: a small, tinted icon beside the title, sized so it
    /// doesn't outweigh the row icons nested under it. Each section keeps its
    /// own hue — distinct from `.accentColor` (row selection) and `.orange`
    /// (warnings) — so a section is identifiable by color alone.
    @ViewBuilder
    private func sectionHeader(_ title: String, systemImage: String, tint: Color = .secondary) -> some View {
        Label {
            Text(title)
                .font(.title3)
        } icon: {
            Image(systemName: systemImage)
                .font(.subheadline)
                .foregroundStyle(tint)
        }
        .textCase(.none)
    }

    /// One sidebar row: the destination's label and an optional "today" badge.
    /// The pin toggle itself lives on the destination's own page now, not here —
    /// it was too much visual noise repeated across every row. Indented under
    /// its section header so the row hierarchy reads clearly.
    @ViewBuilder
    private func navRow(_ section: NavigationSection) -> some View {
        let isSelected = section == selectedSection
        HStack(spacing: 6) {
            // macOS's sidebar List style auto-tints Label icons with the app's static
            // AccentColor asset regardless of ancestor `.foregroundStyle`/`.tint` — an
            // explicit icon closure is what actually overrides that.
            Label {
                Text(section.title)
            } icon: {
                Image(systemName: section.iconName)
                    .foregroundStyle(isSelected ? .white : palette.accent)
            }
            if section == .calendar && todayEventCount > 0 {
                Circle()
                    .fill(isSelected ? .white : palette.accent)
                    .frame(width: 7, height: 7)
                    .accessibilityHidden(true)
            }
            if let badge = badge(for: section) {
                Spacer(minLength: 4)
                badgeView(badge, isSelected: isSelected)
            }
        }
        .padding(.leading, 10)
        // Stretch to the full row width so the whole row — not just the label's
        // text/icon — is the tap target.
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .onTapGesture { selectedSection = section }
        .foregroundStyle(isSelected ? .white : .primary)
        .listRowBackground(
            isSelected
                ? RoundedRectangle(cornerRadius: EVERadius.sm).fill(palette.accent)
                : nil
        )
        .accessibilityValue(
            section == .calendar && todayEventCount > 0
                ? "\(todayEventCount) events today"
                : (badge(for: section)?.accessibilityText ?? "")
        )
    }

    // MARK:  Row badges

    /// Status surfaced next to a sidebar row for the selected character — alerts (things
    /// that need attention) render as a filled pill, plain counts as quiet trailing digits
    /// in the style of Mail's unread counts.
    private enum RowBadge {
        case alert(String, Color, accessibility: String)
        case count(Int, accessibility: String)

        var accessibilityText: String {
            switch self {
            case .alert(_, _, let text), .count(_, let text): return text
            }
        }
    }

    private func badge(for section: NavigationSection) -> RowBadge? {
        guard let id = accountManager.selectedAccount?.characterID,
              let s = prefetcher.menuBarSummaries[id],
              s.loadError == nil else { return nil }
        switch section {
        case .training:
            // totalSP > 0 guards against a summary that hasn't finished loading yet,
            // whose `isQueueEmpty` still holds its default `true`.
            return s.isQueueEmpty && s.totalSP > 0
                ? .alert("!", .orange, accessibility: String(localized: "Skill queue empty"))
                : nil
        case .colonies:
            return s.expiredExtractorCount > 0
                ? .alert("\(s.expiredExtractorCount)", .red, accessibility: String(localized: "\(s.expiredExtractorCount) extractors offline"))
                : nil
        case .industry:
            return s.activeIndustryJobCount > 0
                ? .count(s.activeIndustryJobCount, accessibility: String(localized: "\(s.activeIndustryJobCount) active jobs"))
                : nil
        case .contracts:
            return s.activeContractCount > 0
                ? .count(s.activeContractCount, accessibility: String(localized: "\(s.activeContractCount) active contracts"))
                : nil
        default:
            return nil
        }
    }

    @ViewBuilder
    private func badgeView(_ badge: RowBadge, isSelected: Bool) -> some View {
        switch badge {
        case .alert(let text, let color, _):
            Text(text)
                .font(.eveLabelSemibold.monospacedDigit())
                .foregroundStyle(isSelected ? color : .white)
                .padding(.horizontal, EVESpacing.sm)
                .padding(.vertical, 1)
                .background(isSelected ? .white : color, in: Capsule())
                .accessibilityHidden(true)
        case .count(let n, _):
            Text("\(n)")
                .font(.callout.monospacedDigit())
                .foregroundStyle(isSelected ? .white.opacity(0.85) : .secondary)
                .accessibilityHidden(true)
        }
    }

    // MARK:  Filtering & scope helpers

    /// Narrows a section group to entries matching `filterText`; returns the group
    /// unchanged when the filter is empty.
    private func filtered(_ sections: [NavigationSection]) -> [NavigationSection] {
        guard !filterText.isEmpty else { return sections }
        return sections.filter { $0.rawValue.localizedCaseInsensitiveContains(filterText) }
    }

    private func shouldShow(_ sections: [NavigationSection]) -> Bool {
        !filtered(sections).isEmpty
    }

    /// True when a filter is active and every group currently in view (given
    /// the character/corporation scope) came up empty — the sidebar would
    /// otherwise just go blank with no explanation.
    private var filterHasNoMatches: Bool {
        guard !filterText.isEmpty, accountManager.selectedAccount != nil else { return false }
        let visibleGroups: [[NavigationSection]]
        if navScope == .character || !showCorpSection {
            visibleGroups = [
                pinnedSections, pilotSectionsOrdered, economySectionsOrdered,
                combatSectionsOrdered, socialSectionsOrdered, universeSectionsOrdered,
                utilitySectionsOrdered
            ]
        } else {
            visibleGroups = [corporationSectionsOrdered, utilitySectionsOrdered]
        }
        return visibleGroups.allSatisfy { !shouldShow($0) }
    }

    // MARK:  Keyboard navigation

    /// Every navigable row currently on screen, top to bottom — mirrors the List body's
    /// own visibility logic (scope, show/hide toggles, filter, collapsed sections) exactly,
    /// since arrow-key movement needs to land only on rows the user can actually see.
    private var visibleSections: [NavigationSection] {
        var result: [NavigationSection] = [.dashboard]
        guard accountManager.selectedAccount != nil else { return result }

        if navScope == .character || !showCorpSection {
            if showPinnedSection && pinnedExpanded && shouldShow(pinnedSections) {
                result += filtered(pinnedSections)
            }
            if showPilotSection && pilotExpanded && shouldShow(pilotSectionsOrdered) {
                result += filtered(pilotSectionsOrdered)
            }
            if showEconomySection && economyExpanded && shouldShow(economySectionsOrdered) {
                result += filtered(economySectionsOrdered)
            }
            if showCombatSection && combatExpanded && shouldShow(combatSectionsOrdered) {
                result += filtered(combatSectionsOrdered)
            }
            if showSocialSection && socialExpanded && shouldShow(socialSectionsOrdered) {
                result += filtered(socialSectionsOrdered)
            }
            if showUniverseSection && universeExpanded && shouldShow(universeSectionsOrdered) {
                result += filtered(universeSectionsOrdered)
            }
        }

        if showCorpSection && navScope == .corporation && corpExpanded && shouldShow(corporationSectionsOrdered) {
            result += filtered(corporationSectionsOrdered)
        }

        if showUtilitySection && utilityExpanded && shouldShow(utilitySectionsOrdered) {
            result += filtered(utilitySectionsOrdered)
        }

        return result
    }

    /// Moves `selectedSection` by `delta` rows through `visibleSections`, clamped at both
    /// ends (matching how a native list responds to arrow keys at its boundary, rather than
    /// wrapping — that's `stepSection`'s job, for ⌘[ / ⌘]). Selecting nothing yet, the first
    /// press lands on the top or bottom row depending on direction.
    private func moveSelection(_ delta: Int) {
        let sections = visibleSections
        guard !sections.isEmpty else { return }
        guard let current = selectedSection, let index = sections.firstIndex(of: current) else {
            selectedSection = delta > 0 ? sections.first : sections.last
            return
        }
        selectedSection = sections[max(0, min(sections.count - 1, index + delta))]
    }

    private var noFilterMatchesRow: some View {
        VStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.tertiary)
            Text("No matches for \"\(filterText)\"")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 20)
        .listRowSeparator(.hidden)
    }

    /// While filtering, sections stay expanded (so matches are visible) without
    /// overwriting the user's own collapsed/expanded preference underneath.
    private func expandedBinding(_ base: Binding<Bool>) -> Binding<Bool> {
        Binding(
            get: { filterText.isEmpty ? base.wrappedValue : true },
            set: { newValue in
                if filterText.isEmpty { base.wrappedValue = newValue }
            }
        )
    }

    /// Search field and character/corporation scope toggle share one row —
    /// the scope toggle used to sit on its own full-width row above the filter,
    /// which looked sparse for just two small icons. A compact segmented
    /// control beside the search field reads as one cohesive control bar.
    private var scopeAndFilterRow: some View {
        HStack(spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                    .font(.caption)
                    .accessibilityHidden(true)
                TextField("Filter", text: $filterText)
                    .textFieldStyle(.plain)
                    .font(.callout)
                if !filterText.isEmpty {
                    Button {
                        filterText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Clear filter")
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(RoundedRectangle(cornerRadius: EVERadius.sm).fill(.quaternary.opacity(0.5)))
            .accessibilityLabel("Filter sidebar")

            if showCorpSection {
                Picker("", selection: $navScope) {
                    Image(systemName: "person.fill")
                        .accessibilityLabel("Character")
                        .help("Character")
                        .tag(NavScope.character)
                    Image(systemName: "building.2.fill")
                        .accessibilityLabel("Corporation")
                        .help("Corporation")
                        .tag(NavScope.corporation)
                }
                .labelsHidden()
                .pickerStyle(.segmented)
                .fixedSize()
                .accessibilityLabel("Sidebar scope")
            }
        }
        .padding(.horizontal, 10)
        .padding(.top, 6)
        .padding(.bottom, 4)
    }

    @ViewBuilder
    private func reauthBanner(_ accounts: [StoredAccount]) -> some View {
        VStack(spacing: 0) {
            ForEach(accounts, id: \.characterID) { account in
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                        .font(.caption)
                        .accessibilityHidden(true)

                    VStack(alignment: .leading, spacing: 1) {
                        Text(account.characterName)
                            .font(.caption)
                            .fontWeight(.semibold)
                            .lineLimit(1)
                        Text("Session expired")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    .accessibilityElement(children: .combine)

                    Spacer()

                    Button("Fix") {
                        Task { await accountManager.reauthorize(account) }
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.mini)
                    .tint(.orange)
                    .disabled(accountManager.isLoading)
                    .accessibilityLabel("Re-authenticate \(account.characterName)")
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
            }
        }
        .background(.orange.opacity(0.08))
        .overlay(alignment: .bottom) {
            Divider()
        }
    }

    @ViewBuilder
    private var accountSwitcher: some View {
        if accountManager.accounts.count > 1, let account = accountManager.selectedAccount {
            VStack(spacing: 0) {
                HStack(spacing: 12) {
                    // Plain image, entirely outside the Menu — a `Menu`'s custom label
                    // is measured by AppKit's own button-sizing pass, which does not
                    // reliably respect SwiftUI `.frame()` on an async-loaded image
                    // (confirmed: it rendered at the image's native pixel size no
                    // matter where `.frame`/`.clipShape` were applied inside the
                    // label). Keeping the portrait out of the label sidesteps that
                    // entirely — its size is governed by ordinary SwiftUI layout.
                    CachedAsyncImage(url: EVEImageURL.characterPortrait(account.characterID, size: 128)) { image in
                        image.resizable().aspectRatio(contentMode: .fill)
                    } placeholder: {
                        RoundedRectangle(cornerRadius: EVERadius.md).fill(.secondary.opacity(0.3))
                    }
                    .frame(width: 40, height: 40)
                    .clipShape(RoundedRectangle(cornerRadius: EVERadius.md))
                    .overlay(RoundedRectangle(cornerRadius: EVERadius.md).strokeBorder(.white.opacity(0.15), lineWidth: 1))
                    .accessibilityHidden(true)

                    VStack(alignment: .leading, spacing: 2) {
                        Text("PILOT")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)

                        // A plain Button + .popover instead of Menu — Menu/.borderlessButton
                        // forces its own accent tint onto label text regardless of
                        // .foregroundStyle, and appears to add its own native disclosure
                        // indicator alongside a manually-added chevron. A plain button is
                        // ordinary SwiftUI content top to bottom, so it renders exactly as styled.
                        Button {
                            showPilotPicker = true
                        } label: {
                            HStack(spacing: 5) {
                                Text(account.characterName)
                                    .font(.title3.weight(.semibold))
                                    .foregroundStyle(.primary)
                                    .lineLimit(1)
                                Image(systemName: "chevron.down")
                                    .font(.eveCaptionSemibold)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .buttonStyle(.plain)
                        .popover(isPresented: $showPilotPicker, arrowEdge: .bottom) {
                            VStack(alignment: .leading, spacing: 0) {
                                ForEach(accountManager.accounts, id: \.characterID) { acct in
                                    Button {
                                        accountManager.selectedCharacterID = acct.characterID
                                        showPilotPicker = false
                                    } label: {
                                        HStack {
                                            Text(acct.characterName)
                                            Spacer()
                                            if acct.characterID == account.characterID {
                                                Image(systemName: "checkmark")
                                                    .foregroundStyle(.secondary)
                                            }
                                        }
                                        .padding(.horizontal, 12)
                                        .padding(.vertical, 6)
                                        .contentShape(Rectangle())
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                            .padding(.vertical, 4)
                            .frame(minWidth: 160)
                        }
                        .accessibilityLabel("Switch pilot")
                        .accessibilityValue(account.characterName)
                    }

                    Spacer(minLength: 8)

                    VStack(alignment: .leading, spacing: 5) {
                        // Rendered unconditionally (with a "Loading…" placeholder) rather
                        // than omitted while `data(for:)` is still nil — on first launch,
                        // the initial prefetch hasn't completed yet, and hiding the row
                        // made the sidebar look broken (Discord status with a gap above it)
                        // for the several seconds that takes.
                        HStack(spacing: 5) {
                            if let online = prefetcher.data(for: account.characterID)?.online.online {
                                Circle()
                                    .fill(online ? Color.green : Color.gray)
                                    .frame(width: 8, height: 8)
                                    .overlay(Circle().strokeBorder(.white.opacity(0.25), lineWidth: 1))
                                    .frame(width: 14, alignment: .center)
                                Text(online ? "Online" : "Offline")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            } else {
                                ProgressView()
                                    .controlSize(.mini)
                                    .frame(width: 14, alignment: .center)
                                Text("Loading…")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .accessibilityElement(children: .combine)

                        let discordConnected = DiscordRichPresenceStatus.shared.state == .connected
                        HStack(spacing: 5) {
                            discordStatusIndicator
                            Text(discordConnected ? "Connected" : "Disconnected")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .accessibilityElement(children: .combine)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 14)

                Divider()
            }
        }
    }

    /// Static status glyph mirroring `MenuBarView.discordStatusIndicator` — Discord's
    /// brand blurple when Rich Presence is actually connected, secondary gray otherwise
    /// (covers both "disabled" and "enabled but not reaching Discord" as one glyph).
    private var discordStatusIndicator: some View {
        let isConnected = DiscordRichPresenceStatus.shared.state == .connected
        return Image("DiscordGlyph")
            .resizable()
            .scaledToFit()
            .frame(width: 14, height: 14)
            .foregroundStyle(isConnected ? Color(red: 0x58/255, green: 0x65/255, blue: 0xF2/255) : .secondary)
            .help(isConnected ? "Discord: Connected" : "Discord: Not connected")
    }

    private var addAccountButton: some View {
        Button {
            Task { await accountManager.addAccount() }
        } label: {
            Label("Character", systemImage: "plus.circle")
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .disabled(accountManager.isLoading)
        .accessibilityLabel("Add character")
    }

}

// MARK:  NSSplitView width persistence

private struct SplitViewAutosaver: NSViewRepresentable {
    func makeNSView(context: Context) -> AutosaveProbeView { AutosaveProbeView() }
    func updateNSView(_ nsView: AutosaveProbeView, context: Context) {}
}

private class AutosaveProbeView: NSView {
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard window != nil else { return }
        installAutosave()
    }

    private func installAutosave() {
        var current: NSView? = superview
        while let view = current {
            if let splitView = view as? NSSplitView, splitView.autosaveName == nil {
                splitView.autosaveName = .init("EVEOpsMainSidebar")
                return
            }
            current = view.superview
        }
        // Retry if the NSSplitView wasn't in the hierarchy yet
        DispatchQueue.main.async { [weak self] in self?.installAutosave() }
    }
}
