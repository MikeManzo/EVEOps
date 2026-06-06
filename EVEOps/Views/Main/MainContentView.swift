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
    @State private var selectedSection: NavigationSection? = .dashboard

    var body: some View {
        @Bindable var am = accountManager

        NavigationSplitView {
            SidebarView(accountManager: am, selectedSection: $selectedSection)
        } detail: {
            detailView
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .safeAreaInset(edge: .top) {
                    VStack(spacing: 0) {
                        if !apiStatus.isReachable {
                            APIStatusBanner(message: apiStatus.statusMessage)
                        }
                        if accountManager.hasAccountsNeedingReauth {
                            ReauthBanner(characterNames: accountManager.reauthNeededCharacterNames)
                        }
                    }
                }
        }
        .navigationSplitViewStyle(.balanced)
        .toolbarVisibility(.visible, for: .windowToolbar)
        .toolbar {
            ToolbarItem(placement: .automatic) {
                Button {
                    WindowService.shared.showSettings()
                } label: {
                    Image(systemName: "gear")
                }
            }
        }
        .frame(minWidth: 900, minHeight: 600)
        .onChange(of: accountManager.accounts.count) {
            if accountManager.accounts.isEmpty {
                selectedSection = nil
            } else if selectedSection == nil {
                selectedSection = .dashboard
            }
        }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .background {
                Task { await ESIClient.shared.pruneCache() }
                DiagnosticLogStore.shared.flushNow()
            }
        }
        .onChange(of: AppRouter.shared.pendingEFTURL) { _, url in
            if url != nil { selectedSection = .fittings }
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
                CharacterAssetsView()
            case .clones:
                CharacterClonesView()
            case .colonies:
                ColoniesOverviewView()
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
                CorporationAssetsView()
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
            case .careerAgents:
                CareerAgentsView()
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
    @Environment(\.openSettings) private var openSettings

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
                openSettings()
            }
            .font(.callout)
            .buttonStyle(.plain)
            .foregroundStyle(.red)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.red.opacity(0.10))
        .transition(.move(edge: .top).combined(with: .opacity))
    }
}

// MARK:  API Status Banner

struct APIStatusBanner: View {
    let message: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "wifi.exclamationmark")
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
    }
}
