import SwiftUI
import SwiftData

struct MainContentView: View {
    @Environment(AccountManager.self) private var accountManager
    @Environment(APIStatusMonitor.self) private var apiStatus
    @State private var selectedSection: NavigationSection? = .dashboard

    var body: some View {
        @Bindable var am = accountManager

        NavigationSplitView {
            SidebarView(accountManager: am, selectedSection: $selectedSection)
        } detail: {
            detailView
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .safeAreaInset(edge: .top) {
                    if !apiStatus.isReachable {
                        APIStatusBanner(message: apiStatus.statusMessage)
                    }
                }
        }
        .navigationSplitViewStyle(.balanced)
        .frame(minWidth: 900, minHeight: 600)
        .onChange(of: accountManager.accounts.count) {
            if accountManager.accounts.isEmpty {
                selectedSection = nil
            } else if selectedSection == nil {
                selectedSection = .dashboard
            }
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
            }
        } else {
            DashboardView()
        }
    }
}

// MARK: - API Status Banner

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
