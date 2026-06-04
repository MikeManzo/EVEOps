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

struct ContractsOverviewView: View {
    @Environment(AccountManager.self) private var accountManager
    @Environment(DashboardPrefetcher.self) private var prefetcher
    @State private var contracts: [CharacterContractGroup] = []
    @State private var isLoading = false
    @State private var error: String?
    @State private var filterStatus = "all"

    var body: some View {
        LoadingStateView(isLoading: isLoading, error: error, isEmpty: contracts.isEmpty, emptyMessage: "No contracts found") {
            VStack(spacing: 0) {
                filterBar
                contractList
            }
        }
        .safeAreaInset(edge: .top, spacing: 0) {
            HStack {
                Text("Contracts Overview")
                    .font(.largeTitle.bold())
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(.background)
        }
        .navigationTitle("Contracts Overview")
        .task {
            if buildFromPrefetcher() { return }
            isLoading = true
            await loadContracts()
        }
    }

    private var filterBar: some View {
        HStack {
            Picker("Status", selection: $filterStatus) {
                Text("All").tag("all")
                Text("Outstanding").tag("outstanding")
                Text("In Progress").tag("in_progress")
                Text("Completed").tag("finished")
            }
            .pickerStyle(.segmented)
            .frame(maxWidth: 400)
            Spacer()
        }
        .padding(10)
        .background(.bar)
    }

    private var contractList: some View {
        List {
            ForEach(filteredContracts, id: \.characterName) { group in
                Section(group.characterName) {
                    ForEach(group.contracts) { contract in
                        HStack {
                            Image(systemName: contractIcon(contract.type))
                                .foregroundStyle(statusColor(contract.status))
                            VStack(alignment: .leading, spacing: 2) {
                                Text(contract.title ?? "\(contract.type.capitalized) Contract")
                                    .font(.body)
                                Text("\(contract.type.capitalized) - \(contract.status.replacingOccurrences(of: "_", with: " ").capitalized)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            VStack(alignment: .trailing, spacing: 2) {
                                if let price = contract.price, price > 0 {
                                    Text(EVEFormatters.formatISKShort(price))
                                        .font(.caption.monospacedDigit())
                                }
                                Text(contract.dateIssued, style: .date)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
        }
    }

    private var filteredContracts: [CharacterContractGroup] {
        if filterStatus == "all" { return contracts }
        return contracts.compactMap { group in
            let filtered = group.contracts.filter { $0.status == filterStatus }
            if filtered.isEmpty { return nil }
            return CharacterContractGroup(characterName: group.characterName, contracts: filtered)
        }
    }

    private func contractIcon(_ type: String) -> String {
        switch type {
        case "item_exchange": return "arrow.left.arrow.right"
        case "courier": return "shippingbox"
        case "auction": return "hammer"
        default: return "doc.text"
        }
    }

    private func statusColor(_ status: String) -> Color {
        switch status {
        case "outstanding": return .blue
        case "in_progress": return .orange
        case "finished", "finished_issuer", "finished_contractor": return .green
        case "cancelled", "rejected", "failed", "deleted": return .red
        default: return .secondary
        }
    }

    private func buildFromPrefetcher() -> Bool {
        var groups: [CharacterContractGroup] = []
        for account in accountManager.accounts {
            guard let prefetched = prefetcher.data(for: account.characterID) else { return false }
            if !prefetched.contracts.isEmpty {
                groups.append(CharacterContractGroup(
                    characterName: account.characterName,
                    contracts: prefetched.contracts.sorted { $0.dateIssued > $1.dateIssued }
                ))
            }
        }
        contracts = groups
        return true
    }

    private func loadContracts() async {
        if contracts.isEmpty { isLoading = true }
        error = nil
        var groups: [CharacterContractGroup] = []
        var lastError: Error?
        for account in accountManager.accounts {
            do {
                let token = try await accountManager.validToken(for: account)
                let rawContracts: [ESIContract] = try await ESIClient.shared.fetch(
                    "/characters/\(account.characterID)/contracts/", token: token
                )
                if !rawContracts.isEmpty {
                    groups.append(CharacterContractGroup(
                        characterName: account.characterName,
                        contracts: rawContracts.sorted { $0.dateIssued > $1.dateIssued }
                    ))
                }
            } catch {
                lastError = error
            }
        }
        contracts = groups
        if groups.isEmpty, let lastError {
            self.error = lastError.localizedDescription
        }
        isLoading = false
    }
}

struct CharacterContractGroup {
    let characterName: String
    let contracts: [ESIContract]
}
