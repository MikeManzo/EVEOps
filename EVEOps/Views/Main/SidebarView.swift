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

    @AppStorage("sidebar.pilotExpanded") private var pilotExpanded = true
    @AppStorage("sidebar.economyExpanded") private var economyExpanded = true
    @AppStorage("sidebar.combatExpanded") private var combatExpanded = true
    @AppStorage("sidebar.socialExpanded") private var socialExpanded = true
    @AppStorage("sidebar.universeExpanded") private var universeExpanded = true
    @AppStorage("sidebar.corpExpanded") private var corpExpanded = true
    @AppStorage("sidebar.utilityExpanded") private var utilityExpanded = true

    @AppStorage("sidebar.showPilot") private var showPilotSection = true
    @AppStorage("sidebar.showEconomy") private var showEconomySection = true
    @AppStorage("sidebar.showCombat") private var showCombatSection = true
    @AppStorage("sidebar.showSocial") private var showSocialSection = true
    @AppStorage("sidebar.showUniverse") private var showUniverseSection = true
    @AppStorage("sidebar.showCorp") private var showCorpSection = true
    @AppStorage("sidebar.showUtility") private var showUtilitySection = true
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
//                    Section("Pilot — \(account.characterName)", isExpanded: $pilotExpanded) {
//                        ForEach(NavigationSection.pilotSections) { section in
//                            Label(section.rawValue, systemImage: section.iconName)
//                                .tag(section)
//                        }
//                    }

                    if showPilotSection {
                        Section(
                            isExpanded: $pilotExpanded,
                            content: {
                                ForEach(NavigationSection.pilotSections) { section in
                                    Label(section.rawValue, systemImage: section.iconName)
                                        .tag(section)
                                }
                            },
                            header: {
                                Text("Pilot — \(account.characterName)")
                                    .font(.title3)
                                    .textCase(.none)
                            }
                        )
                    }
                    
//                    Section("Economy", isExpanded: $economyExpanded) {
//                        ForEach(NavigationSection.economySections) { section in
//                            Label(section.rawValue, systemImage: section.iconName)
//                                .tag(section)
//                        }
//                    }

                    if showEconomySection {
                        Section(
                            isExpanded: $economyExpanded,
                            content: {
                                ForEach(NavigationSection.economySections) { section in
                                    Label(section.rawValue, systemImage: section.iconName)
                                        .tag(section)
                                }
                            },
                            header: {
                                Text("Economy")
                                    .font(.title3)
                                    .textCase(.none)
                            }
                        )
                    }

                    
//                   Section("Combat & Fleet", isExpanded: $combatExpanded) {
//                       ForEach(NavigationSection.combatSections) { section in
//                           Label(section.rawValue, systemImage: section.iconName)
//                                .tag(section)
//                        }
//                    }

                    if showCombatSection {
                        Section(
                            isExpanded: $combatExpanded,
                            content: {
                                ForEach(NavigationSection.combatSections) { section in
                                    Label(section.rawValue, systemImage: section.iconName)
                                        .tag(section)
                                }
                            },
                            header: {
                                Text("Combat & Fleet")
                                    .font(.title3)
                                    .textCase(.none)
                            }
                        )
                    }

/*
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
*/
                    
                    if showSocialSection {
                        Section(
                            isExpanded: $socialExpanded,
                            content: {
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
                            },
                            header: {
                                Text("Social & Comms")
                                    .font(.title3)
                                    .textCase(.none)
                            }
                        )
                    }
                    
//                    Section("Universe", isExpanded: $universeExpanded) {
//                        ForEach(NavigationSection.universeSections) { section in
//                            Label(section.rawValue, systemImage: section.iconName)
//                                .tag(section)
//                        }
//                    }

                    if showUniverseSection {
                        Section(
                            isExpanded: $universeExpanded,
                            content: {
                                ForEach(NavigationSection.universeSections) { section in
                                    Label(section.rawValue, systemImage: section.iconName)
                                        .tag(section)
                                }
                            },
                            header: {
                                Text("Universe")
                                    .font(.title3)
                                    .textCase(.none)
                            }
                        )
                    }

                    
//                   Section("Corporation — \(account.corporationName)", isExpanded: $corpExpanded) {
//                        ForEach(NavigationSection.corporationSections) { section in
//                            Label(displayName(for: section), systemImage: section.iconName)
//                                .tag(section)
//                        }
//                    }
                    
                    if showCorpSection {
                        Section(
                            isExpanded: $corpExpanded,
                            content: {
                                ForEach(NavigationSection.corporationSections) { section in
                                    Label(section.rawValue, systemImage: section.iconName)
                                        .tag(section)
                                }
                            },
                            header: {
                                Text("Corp: \(account.corporationName)")
                                    .font(.title3)
                                    .textCase(.none)
                            }
                        )
                    }
                }

                if showUtilitySection {
                    Section(
                        isExpanded: $utilityExpanded,
                        content: {
                            ForEach(NavigationSection.utilitySections) { section in
                                Label(section.rawValue, systemImage: section.iconName)
                                    .tag(section)
                            }
                        },
                        header: {
                            Text("Utility")
                                .font(.title3)
                                .textCase(.none)
                        }
                    )
                }
            }
            .listStyle(.sidebar)

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
                                AsyncImage(url: EVEImageURL.characterPortrait(account.characterID, size: 32)) { image in
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
                            AsyncImage(url: EVEImageURL.characterPortrait(account.characterID, size: 32)) { image in
                                image.resizable()
                                    .aspectRatio(contentMode: .fill)
                                    .frame(width: 20, height: 20)
                                    .clipShape(Circle())
                            } placeholder: {
                                Circle().fill(.secondary.opacity(0.3))
                                    .frame(width: 20, height: 20)
                            }
                            Text(account.characterName)
                                .lineLimit(1)
                                .font(.title2)
                        }
                        Spacer()
                        Image(systemName: "chevron.up.chevron.down")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                }
                .menuStyle(.borderlessButton)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
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
