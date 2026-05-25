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

struct SidebarView: View {
    @Bindable var accountManager: AccountManager
    @Binding var selectedSection: NavigationSection?

    @AppStorage("sidebar.pilotExpanded") private var pilotExpanded = true
    @AppStorage("sidebar.economyExpanded") private var economyExpanded = true
    @AppStorage("sidebar.combatExpanded") private var combatExpanded = true
    @AppStorage("sidebar.socialExpanded") private var socialExpanded = true
    @AppStorage("sidebar.universeExpanded") private var universeExpanded = true
    @AppStorage("sidebar.corpExpanded") private var corpExpanded = true
    @State private var todayEventCount = 0

    var body: some View {
        VStack(spacing: 0) {
            accountSwitcher

            let reauthAccounts = accountManager.accounts.filter { $0.needsReauth }
            if !reauthAccounts.isEmpty {
                reauthBanner(reauthAccounts)
            }

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

                    Section("Combat & Fleet", isExpanded: $combatExpanded) {
                        ForEach(NavigationSection.combatSections) { section in
                            Label(section.rawValue, systemImage: section.iconName)
                                .tag(section)
                        }
                    }

                    Section("Social & Comms", isExpanded: $socialExpanded) {
                        ForEach(NavigationSection.socialSections) { section in
                            Label(section.rawValue, systemImage: section.iconName)
                                .tag(section)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .overlay(alignment: .trailing) {
                                    if section == .calendar && todayEventCount > 0 {
                                        Circle()
                                            .fill(Color.blue)
                                            .frame(width: 7, height: 7)
                                    }
                                }
                        }
                    }

                    Section("Universe", isExpanded: $universeExpanded) {
                        ForEach(NavigationSection.universeSections) { section in
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
            } catch {}
        }
    }

    @ViewBuilder
    private func reauthBanner(_ accounts: [StoredAccount]) -> some View {
        VStack(spacing: 0) {
            ForEach(accounts, id: \.characterID) { account in
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                        .font(.caption)

                    VStack(alignment: .leading, spacing: 1) {
                        Text(account.characterName)
                            .font(.caption)
                            .fontWeight(.semibold)
                            .lineLimit(1)
                        Text("Session expired")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    Button("Fix") {
                        Task { await accountManager.reauthorize(account) }
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.mini)
                    .tint(.orange)
                    .disabled(accountManager.isLoading)
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
