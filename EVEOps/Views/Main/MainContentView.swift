import SwiftUI
import SwiftData

struct MainContentView: View {
    @Environment(AccountManager.self) private var accountManager
    @State private var selectedSection: NavigationSection? = .dashboard

    var body: some View {
        @Bindable var am = accountManager

        NavigationSplitView {
            SidebarView(accountManager: am, selectedSection: $selectedSection)
        } detail: {
            detailView
                .frame(maxWidth: .infinity, maxHeight: .infinity)
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
            case .wealth:
                WealthOverviewView()
            case .wallet:
                CharacterWalletView()
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
            }
        } else {
            DashboardView()
        }
    }
}
