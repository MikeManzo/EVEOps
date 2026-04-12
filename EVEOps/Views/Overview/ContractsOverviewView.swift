import SwiftUI

struct ContractsOverviewView: View {
    @Environment(AccountManager.self) private var accountManager
    @State private var contracts: [CharacterContractGroup] = []
    @State private var isLoading = true
    @State private var error: String?
    @State private var filterStatus = "all"

    var body: some View {
        LoadingStateView(isLoading: isLoading, error: error, isEmpty: contracts.isEmpty, emptyMessage: "No contracts found") {
            VStack(spacing: 0) {
                filterBar
                contractList
            }
        }
        .navigationTitle("Contracts Overview")
        .task { await loadContracts() }
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

    private func loadContracts() async {
        isLoading = true
        var groups: [CharacterContractGroup] = []
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
                // Skip
            }
        }
        contracts = groups
        isLoading = false
    }
}

struct CharacterContractGroup {
    let characterName: String
    let contracts: [ESIContract]
}
