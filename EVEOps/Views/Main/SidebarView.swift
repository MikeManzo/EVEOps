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
    @State private var navScope: NavScope = .character

    var body: some View {
        VStack(spacing: 0) {
            accountSwitcher

            let reauthAccounts = accountManager.accounts.filter { $0.needsReauth }
            if !reauthAccounts.isEmpty {
                reauthBanner(reauthAccounts)
            }

            if accountManager.selectedAccount != nil {
                scopePicker
                filterField
            }

            List(selection: $selectedSection) {
                Label("Dashboard", systemImage: "square.grid.2x2.fill")
                    .tag(NavigationSection.dashboard)

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
        HStack(spacing: 6) {
            Label(section.title, systemImage: section.iconName)
            if section == .calendar && todayEventCount > 0 {
                Circle()
                    .fill(Color.blue)
                    .frame(width: 7, height: 7)
                    .accessibilityHidden(true)
            }
        }
        .padding(.leading, 10)
        .tag(section)
        .accessibilityValue(
            section == .calendar && todayEventCount > 0 ? "\(todayEventCount) events today" : ""
        )
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

    @ViewBuilder
    private var scopePicker: some View {
        if showCorpSection {
            Picker("", selection: $navScope) {
                Image(systemName: "person.fill")
                    .accessibilityLabel("Character")
                    .tag(NavScope.character)
                Image(systemName: "building.2.fill")
                    .accessibilityLabel("Corporation")
                    .tag(NavScope.corporation)
            }
            .labelsHidden()
            .pickerStyle(.segmented)
            .padding(.horizontal, 10)
            .padding(.top, 6)
            .accessibilityLabel("Sidebar scope")
        }
    }

    private var filterField: some View {
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
        .padding(.vertical, 5)
        .background(RoundedRectangle(cornerRadius: 6).fill(.quaternary.opacity(0.5)))
        .padding(.horizontal, 10)
        .padding(.top, 6)
        .padding(.bottom, 4)
        .accessibilityLabel("Filter sidebar")
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
        if accountManager.accounts.count > 1 {
            HStack {
                Spacer(minLength: 3)
                Text("Pilot")
                    .font(.title)
                Menu {
                    ForEach(accountManager.accounts, id: \.characterID) { account in
                        Button {
                            accountManager.selectedCharacterID = account.characterID
                        } label: {
                            Label {
                                Text(account.characterName)
                            } icon: {
                                CachedAsyncImage(url: EVEImageURL.characterPortrait(account.characterID, size: 32)) { image in
                                    image.resizable()
                                        .aspectRatio(contentMode: .fill)
                                        .frame(width: 16, height: 16)
                                        .clipShape(Circle())
                                } placeholder: {
                                    Circle().fill(.secondary.opacity(0.3))
                                        .frame(width: 16, height: 16)
                                }
                            }
                        }
                    }
                } label: {
                    HStack(spacing: 6) {
                        if let account = accountManager.selectedAccount {
                            CachedAsyncImage(url: EVEImageURL.characterPortrait(account.characterID, size: 32)) { image in
                                image.resizable()
                                    .aspectRatio(contentMode: .fill)
                                    .frame(width: 20, height: 20)
                                    .clipShape(Circle())
                            } placeholder: {
                                Circle().fill(.secondary.opacity(0.3))
                                    .frame(width: 20, height: 20)
                            }
                            .accessibilityHidden(true)
                            Text(account.characterName)
                                .lineLimit(1)
                                .font(.title2)
                        }
                        Spacer()
                        Image(systemName: "chevron.up.chevron.down")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .accessibilityHidden(true)
                    }
                    .frame(maxWidth: .infinity)
                }
                .menuStyle(.borderlessButton)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .accessibilityLabel("Switch pilot")
                .accessibilityValue(accountManager.selectedAccount?.characterName ?? "")
                Spacer()
            }
        }
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
