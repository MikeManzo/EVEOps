import SwiftUI

struct SidebarView: View {
    @Bindable var accountManager: AccountManager
    @Binding var selectedSection: NavigationSection?

    var body: some View {
        List(selection: $selectedSection) {
            Label("Dashboard", systemImage: "square.grid.2x2.fill")
                .tag(NavigationSection.dashboard)

            if let account = accountManager.selectedAccount {
                Section("Character: \(account.characterName)") {
                    ForEach(NavigationSection.characterSections) { section in
                        Label(section.rawValue, systemImage: section.iconName)
                            .tag(section)
                    }
                }

                Section("Corporation: \(account.corporationName)") {
                    ForEach(NavigationSection.corporationSections) { section in
                        Label(displayName(for: section), systemImage: section.iconName)
                            .tag(section)
                    }
                }
            }
        }
        .listStyle(.sidebar)
        .frame(minWidth: 200)
        .safeAreaInset(edge: .top) {
            accountSwitcher
        }
        .safeAreaInset(edge: .bottom) {
            addAccountButton
        }
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
        default: return section.rawValue
        }
    }
}
