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

struct CorporationWalletsView: View {
    @Environment(AccountManager.self) private var accountManager
    @State private var wallets: [CorpWalletDivision] = []
    @State private var journal: [ESIWalletJournalEntry] = []
    @State private var isLoading = true
    @State private var error: String?
    @State private var selectedDivision: Int = 1
    @State private var selectedTab = 0

    private var totalBalance: Double {
        wallets.reduce(0) { $0 + $1.balance }
    }

    var body: some View {
        LoadingStateView(isLoading: isLoading, error: error, isEmpty: wallets.isEmpty, emptyMessage: "No wallet data or insufficient permissions") {
            VStack(spacing: 0) {
                walletHeader
                divisionPicker
                tabPicker
                tabContent
            }
        }
        .safeAreaInset(edge: .top, spacing: 0) {
            HStack {
                Text("Corp Wallets")
                    .font(.largeTitle.bold())
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(.background)
        }
        .navigationTitle("Corp Wallets")
        .task(id: accountManager.selectedCharacterID) {
            wallets = []
            journal = []
            isLoading = true
            await loadWallets()
        }
    }

    private var walletHeader: some View {
        HStack {
            VStack(alignment: .leading) {
                Text("Total Corporation Balance")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(EVEFormatters.formatISK(totalBalance))
                    .font(.title2.bold().monospacedDigit())
            }
            Spacer()
        }
        .padding()
        .background(.regularMaterial)
    }

    private var divisionPicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(wallets, id: \.division) { wallet in
                    Button {
                        selectedDivision = wallet.division
                        Task { await loadJournal() }
                    } label: {
                        VStack(spacing: 2) {
                            Text("Division \(wallet.division)")
                                .font(.caption)
                            Text(EVEFormatters.formatISKShort(wallet.balance))
                                .font(.caption2.monospacedDigit())
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(
                            selectedDivision == wallet.division ? Color.accentColor.opacity(0.2) : Color.clear,
                            in: RoundedRectangle(cornerRadius: 8)
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
        }
        .background(.bar)
    }

    private var tabPicker: some View {
        Picker("View", selection: $selectedTab) {
            Text("Balances").tag(0)
            Text("Journal").tag(1)
        }
        .pickerStyle(.segmented)
        .padding(10)
        .frame(maxWidth: 250)
    }

    @ViewBuilder
    private var tabContent: some View {
        if selectedTab == 0 {
            balancesView
        } else {
            journalView
        }
    }

    private var balancesView: some View {
        List(wallets, id: \.division) { wallet in
            HStack {
                Image(systemName: "banknote.fill")
                    .foregroundStyle(.green)
                Text("Division \(wallet.division)")
                    .font(.body)
                Spacer()
                Text(EVEFormatters.formatISK(wallet.balance))
                    .font(.body.monospacedDigit())
            }
        }
    }

    private var journalView: some View {
        List(journal) { entry in
            HStack {
                Image(systemName: (entry.amount ?? 0) >= 0 ? "arrow.down.circle.fill" : "arrow.up.circle.fill")
                    .foregroundStyle((entry.amount ?? 0) >= 0 ? .green : .red)
                VStack(alignment: .leading, spacing: 2) {
                    Text(entry.refType.replacingOccurrences(of: "_", with: " ").capitalized)
                        .font(.subheadline)
                    Text(entry.description)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer()
                VStack(alignment: .trailing) {
                    if let amount = entry.amount {
                        Text(EVEFormatters.formatISKShort(amount))
                            .font(.subheadline.monospacedDigit())
                            .foregroundStyle(amount >= 0 ? .green : .red)
                    }
                    Text(entry.date, style: .date)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
        }
    }

    private func loadWallets() async {
        guard let account = accountManager.selectedAccount else { return }
        isLoading = true
        do {
            let token = try await accountManager.validToken(for: account)
            let rawWallets: [CorpWalletResponse] = try await ESIClient.shared.fetch(
                "/corporations/\(account.corporationID)/wallets/", token: token
            )
            wallets = rawWallets.map {
                CorpWalletDivision(division: $0.division, balance: $0.balance)
            }.sorted { $0.division < $1.division }
            await loadJournal()
        } catch {
            self.error = error.localizedDescription
        }
        isLoading = false
    }

    private func loadJournal() async {
        guard let account = accountManager.selectedAccount else { return }
        do {
            let token = try await accountManager.validToken(for: account)
            journal = try await ESIClient.shared.fetch(
                "/corporations/\(account.corporationID)/wallets/\(selectedDivision)/journal/", token: token
            )
            journal.sort { $0.date > $1.date }
        } catch {
            // Keep existing journal data
        }
    }
}

struct CorpWalletResponse: Codable {
    let balance: Double
    let division: Int
}

struct CorpWalletDivision {
    let division: Int
    let balance: Double
}
