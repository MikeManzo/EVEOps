import SwiftUI

struct SidebarView: View {
    @Bindable var accountManager: AccountManager
    @Binding var selectedSection: NavigationSection?

    @AppStorage("sidebar.pilotExpanded") private var pilotExpanded = true
    @AppStorage("sidebar.economyExpanded") private var economyExpanded = true
    @AppStorage("sidebar.combatExpanded") private var combatExpanded = true
    @AppStorage("sidebar.socialExpanded") private var socialExpanded = true
    @AppStorage("sidebar.corpExpanded") private var corpExpanded = true

    var body: some View {
        VStack(spacing: 0) {
            accountSwitcher

            List(selection: $selectedSection) {
                Label("Dashboard", systemImage: "square.grid.2x2.fill")
                    .tag(NavigationSection.dashboard)

                if let account = accountManager.selectedAccount {
                    Section("Pilot — \(account.characterName)", isExpanded: $pilotExpanded) {
                        ForEach(NavigationSection.pilotSections) { section in
                            Label(section.rawValue, systemImage: section.iconName)
                                .tag(section)
                        }
                    }

                    Section("Economy", isExpanded: $economyExpanded) {
                        ForEach(NavigationSection.economySections) { section in
                            Label(section.rawValue, systemImage: section.iconName)
                                .tag(section)
                        }
                    }

                    Section("Combat", isExpanded: $combatExpanded) {
                        ForEach(NavigationSection.combatSections) { section in
                            Label(section.rawValue, systemImage: section.iconName)
                                .tag(section)
                        }
                    }

                    Section("Social", isExpanded: $socialExpanded) {
                        ForEach(NavigationSection.socialSections) { section in
                            Label(section.rawValue, systemImage: section.iconName)
                                .tag(section)
                        }
                    }

                    Section("Corporation — \(account.corporationName)", isExpanded: $corpExpanded) {
                        ForEach(NavigationSection.corporationSections) { section in
                            Label(displayName(for: section), systemImage: section.iconName)
                                .tag(section)
                        }
                    }
                }
            }
            .listStyle(.sidebar)

            Divider()

            addAccountButton
        }
        .frame(minWidth: 200)
    }

    @ViewBuilder
    private var accountSwitcher: some View {
        if !accountManager.accounts.isEmpty {
            Picker("Character", selection: $accountManager.selectedCharacterID) {
                ForEach(accountManager.accounts, id: \.characterID) { account in
                    Text(account.characterName)
                        .tag(Optional(account.characterID))
                }
            }
            .pickerStyle(.menu)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
    }

    private var addAccountButton: some View {
        Button {
            Task { await accountManager.addAccount() }
        } label: {
            Label("Add Character", systemImage: "plus.circle")
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .disabled(accountManager.isLoading)
    }

    private func displayName(for section: NavigationSection) -> String {
        switch section {
        case .corpAssets: return "Assets"
        case .corpIndustry: return "Industry"
        case .corpMembers: return "Members"
        case .corpStructures: return "Structures"
        case .corpWallets: return "Wallets"
        case .corpContracts: return "Contracts"
        case .corpKillmails: return "Kill Mails"
        case .corpMarketOrders: return "Market Orders"
        case .corpMining: return "Mining"
        default: return section.rawValue
        }
    }
}
