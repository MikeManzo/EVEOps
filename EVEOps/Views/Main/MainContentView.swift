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
import SwiftData

struct MainContentView: View {
    @Environment(AccountManager.self) private var accountManager
    @Environment(APIStatusMonitor.self) private var apiStatus
    @Environment(\.scenePhase) private var scenePhase
    @Environment(ThemeManager.self) private var themeManager
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage("appearance.ambientBackground") private var ambientBackground = false
    @AppStorage(EVERowDensity.storageKey) private var rowDensity: EVERowDensity = .comfortable
    /// Last-viewed section, restored across launches. `nil` (fresh install or all
    /// characters removed) falls through to the Dashboard.
    @AppStorage("nav.lastSection") private var selectedSection: NavigationSection?
    @State private var showCommandPalette = false
    @State private var showOnboarding = false
    @State private var showShortcuts = false
    @AppStorage(OnboardingView.completedKey) private var onboardingCompleted = false

    var body: some View {
        @Bindable var am = accountManager

        NavigationSplitView {
            SidebarView(accountManager: am, selectedSection: $selectedSection)
        } detail: {
            ZStack {
                detailView
                    .id(selectedSection)
                    .transition(.eveSection)
            }
                .animation(reduceMotion ? nil : EVEMotion.section, value: selectedSection)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background {
                    if ambientBackground { EVEAmbientBackground() }
                }
                .safeAreaInset(edge: .top) {
                    VStack(spacing: 0) {
                        if !apiStatus.isReachable {
                            APIStatusBanner(message: apiStatus.statusMessage, severity: .unreachable)
                        } else if let service = apiStatus.serviceBannerText {
                            APIStatusBanner(message: service, severity: .service)
                        }
                        ForEach(accountManager.notices) { notice in
                            AccountNoticeBanner(notice: notice) {
                                accountManager.dismissNotice(notice)
                            }
                        }
                        if accountManager.hasAccountsNeedingReauth {
                            ReauthBanner(characterNames: accountManager.reauthNeededCharacterNames)
                        }
                    }
                }
        }
        .navigationSplitViewStyle(.balanced)
        .environment(\.eveRowDensity, rowDensity)
        .toolbarVisibility(.visible, for: .windowToolbar)
        .toolbar {
            ToolbarItem(placement: .automatic) {
                QuickSwitcherField { showCommandPalette = true }
            }
            ToolbarItem(placement: .automatic) {
                Button {
                    WindowService.shared.showSettings()
                } label: {
                    Image(systemName: "gear")
                }
                .help("Settings")
                .accessibilityLabel("Settings")
            }
        }
        .sheet(isPresented: $showOnboarding) {
            OnboardingView(characterName: accountManager.accounts.first?.characterName) {
                onboardingCompleted = true
                showOnboarding = false
            }
            .interactiveDismissDisabled()
        }
        .sheet(isPresented: $showCommandPalette) {
            CommandPaletteView(
                selectedSection: $selectedSection,
                onRun: handlePaletteAction,
                dismiss: { showCommandPalette = false }
            )
            .environment(accountManager)
        }
        .frame(minWidth: 900, minHeight: 600)
        .task {
            // Give the sidebar a visible selection on a cold launch when nothing
            // was persisted yet.
            if !accountManager.accounts.isEmpty && selectedSection == nil {
                selectedSection = .dashboard
            }
            // Existing pilots upgrading to a build with onboarding already know the app —
            // mark it seen instead of greeting them with a first-run walkthrough.
            if !accountManager.accounts.isEmpty && !onboardingCompleted {
                onboardingCompleted = true
            }
        }
        .onChange(of: accountManager.accounts.count) { oldCount, newCount in
            if oldCount == 0 && newCount > 0 && !onboardingCompleted {
                showOnboarding = true
            }
            if accountManager.accounts.isEmpty {
                selectedSection = nil
            } else if selectedSection == nil {
                selectedSection = .dashboard
            }
        }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .background {
                Task { await ESIClient.shared.persistCache() }
                DiagnosticLogStore.shared.flushNow()
            }
        }
        .onChange(of: AppRouter.shared.pendingEFTURL) { _, url in
            if url != nil { selectedSection = .fittings }
        }
        .onChange(of: AppRouter.shared.pendingCharacterID) { _, id in
            guard let id else { return }
            if accountManager.accounts.contains(where: { $0.characterID == id }) {
                accountManager.selectedCharacterID = id
            }
            AppRouter.shared.pendingCharacterID = nil
        }
        .onChange(of: AppRouter.shared.pendingSection) { _, section in
            guard let section else { return }
            selectedSection = section
            AppRouter.shared.pendingSection = nil
        }
        .onChange(of: AppRouter.shared.commandPaletteTick) { _, _ in
            showCommandPalette = true
        }
        .onChange(of: AppRouter.shared.shortcutsTick) { _, _ in
            showShortcuts = true
        }
        .sheet(isPresented: $showShortcuts) {
            KeyboardShortcutsView { showShortcuts = false }
        }
        .onChange(of: AppRouter.shared.addCharacterTick) { _, _ in
            Task { await accountManager.addAccount() }
        }
        .onChange(of: AppRouter.shared.sectionStep) { _, step in
            guard step != 0 else { return }
            stepSection(step)
            AppRouter.shared.sectionStep = 0
        }
    }

    /// Advance the selected section by `delta` positions through the sidebar's
    /// declared order, wrapping at both ends.
    private func stepSection(_ delta: Int) {
        guard !accountManager.accounts.isEmpty else { return }
        let all = NavigationSection.allCases
        let current = selectedSection ?? .dashboard
        guard let index = all.firstIndex(of: current) else {
            selectedSection = .dashboard
            return
        }
        selectedSection = all[(index + delta + all.count) % all.count]
    }

    private func handlePaletteAction(_ action: PaletteAction) {
        switch action {
        case .openSettings:
            WindowService.shared.showSettings()
        case .addCharacter:
            Task { await accountManager.addAccount() }
        case .refresh:
            AppRouter.shared.requestRefresh()
        case .diagnostics:
            selectedSection = .diagnosticLogs
        }
    }

    @ViewBuilder
    private var detailView: some View {
        if accountManager.accounts.isEmpty {
            WelcomeView()
        } else if let section = selectedSection {
            switch section {
            case .dashboard:
                DashboardView()

            // Character
            case .location:
                LocationOverviewView()
            case .training:
                TrainingOverviewView()
            case .skillPlanner:
                SkillPlannerView()
            case .finances:
                FinancesView()
            case .assets:
                AssetBrowser(kind: .character)
            case .clones:
                CharacterClonesView()
            case .colonies:
                ColoniesOverviewView()
            case .lpStore:
                LoyaltyPointStoreView()
            case .contracts:
                ContractsOverviewView()
            case .industry:
                IndustryOverviewView()
            case .communications:
                CharacterCommunicationsView()
            case .mails:
                CharacterMailsView()

            // Corporation
            case .corpAssets:
                AssetBrowser(kind: .corporation)
            case .corpHangars:
                CorporationHangarsView()
            case .corpIndustry:
                CorporationIndustryView()
            case .corpMembers:
                CorporationMembersView()
            case .corpStructures:
                CorporationStructuresView()
            case .corpWallets:
                CorporationWalletsView()
            case .corpContracts:
                CorporationContractsView()
            case .corpKillmails:
                CorporationKillmailsView()
            case .corpMarketOrders:
                CorporationMarketOrdersView()
            case .corpMining:
                CorporationMiningView()

            // Character extras
            case .killmails:
                CharacterKillmailsView()
            case .fittings:
                CharacterFittingsView()
            case .localIntel:
                LocalIntelView()
            case .calendar:
                CharacterCalendarView()
            case .standings:
                CharacterStandingsView()
            case .contacts:
                CharacterContactsView()
            case .routePlanner:
                RoutePlannerView()
            case .galaxyMap:
                GalaxyMapView()
            case .incursions:
                IncursionsView()
            case .sovereignty:
                SovereigntyView()
            case .explorationCodex:
                ExplorationCodexView()
            case .careerAgents:
                AgentFinderView()
            case .fleetManager:
                FleetManagerView()
            case .market:
                MarketBrowserView()
            case .stationBrowser:
                RegionStationBrowserView(onNavigateToMarket: { selectedSection = .market })
            case .remapAdvisor:
                AttributeRemapView()
            case .research:
                CharacterResearchAgentsView()
            case .medals:
                CharacterMedalsView()
            case .factionWarfare:
                CharacterFWStatsView()
            case .corpWars:
                CorporationWarsView()
            case .corpMoonExtractions:
                CorporationMoonExtractionsView()

            // Utility
            case .diagnosticLogs:
                DiagnosticPaneView()
            }
        } else {
            DashboardView()
        }
    }
}

// MARK:  Reauth Banner

struct ReauthBanner: View {
    let characterNames: [String]

    private var names: String {
        characterNames.joined(separator: ", ")
    }

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "lock.trianglebadge.exclamationmark.fill")
                .foregroundStyle(.red)
            Text("Re-authentication required: \(names)")
                .font(.callout)
            Spacer()
            Button("Settings") {
                WindowService.shared.showSettings()
            }
            .font(.callout)
            .buttonStyle(.plain)
            .foregroundStyle(.red)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.red.opacity(0.10))
        .transition(.move(edge: .top).combined(with: .opacity))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Re-authentication required for \(names)")
    }
}

// MARK:  API Status Banner

struct APIStatusBanner: View {
    let message: String
    var severity: Severity = .unreachable

    enum Severity { case unreachable, service }

    private var icon: String {
        severity == .unreachable ? "wifi.exclamationmark" : "exclamationmark.triangle.fill"
    }

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .foregroundStyle(.orange)
            Text(message.isEmpty ? "Unable to reach EVE servers" : message)
                .font(.callout)
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.orange.opacity(0.12))
        .transition(.move(edge: .top).combined(with: .opacity))
        .animation(.easeInOut(duration: 0.3), value: message)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(message.isEmpty ? "Unable to reach EVE servers" : message)
    }
}

// MARK:  Quick Switcher Field

/// Toolbar affordance for the ⌘K command palette, drawn as a search field (in the spirit of
/// Xcode's Open Quickly) so the palette is discoverable without knowing the shortcut.
/// It's a button, not a real text field — typing happens in the palette sheet.
private struct QuickSwitcherField: View {
    let action: () -> Void
    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: EVESpacing.sm) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                Text("Jump to\u{2026}")
                    .foregroundStyle(.secondary)
                Spacer(minLength: EVESpacing.xl)
                Text("\u{2318}K")
                    .font(.eveLabelMedium)
                    .foregroundStyle(.tertiary)
                    .padding(.horizontal, EVESpacing.xs)
                    .padding(.vertical, 1)
                    .background(.quaternary.opacity(0.6), in: RoundedRectangle(cornerRadius: EVERadius.xs))
            }
            .font(.callout)
            .padding(.horizontal, EVESpacing.md)
            .frame(width: 200, height: 24)
            .background(
                RoundedRectangle(cornerRadius: EVERadius.sm)
                    .fill(Color.primary.opacity(isHovering ? 0.09 : 0.05))
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .help("Quick switcher (\u{2318}K)")
        .accessibilityLabel("Quick switcher")
    }
}
