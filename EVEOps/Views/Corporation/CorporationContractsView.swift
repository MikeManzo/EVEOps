import SwiftUI

struct CorporationContractsView: View {
    @Environment(AccountManager.self) private var accountManager
    @State private var contracts: [ESIContract] = []
    @State private var isLoading = false
    @State private var error: String?
    @State private var filterStatus = "all"

    var body: some View {
        LoadingStateView(isLoading: isLoading, error: error, isEmpty: contracts.isEmpty, emptyMessage: "No corp contracts found or insufficient roles") {
            VStack(spacing: 0) {
                filterBar
                contractList
            }
        }
        .navigationTitle("Corp Contracts")
        .task(id: accountManager.selectedCharacterID) {
            guard let account = accountManager.selectedAccount else { return }
            isLoading = true
            error = nil
            do {
                let token = try await accountManager.validToken(for: account)
                let loaded: [ESIContract] = try await ESIClient.shared.fetchPages(
                    "/corporations/\(account.corporationID)/contracts/", token: token
                )
                contracts = loaded.sorted { $0.dateIssued > $1.dateIssued }
            } catch {
                self.error = error.localizedDescription
            }
            isLoading = false
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
            Text("\(filteredContracts.count) contracts")
                .font(.caption).foregroundStyle(.secondary)
        }
        .padding(10)
        .background(.bar)
    }

    private var filteredContracts: [ESIContract] {
        filterStatus == "all" ? contracts : contracts.filter { $0.status == filterStatus }
    }

    private var contractList: some View {
        List(filteredContracts) { contract in
            CorpContractRow(contract: contract)
        }
    }
}

struct CorpContractRow: View {
    let contract: ESIContract
    @State private var issuerName = ""

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: contractIcon(contract.type))
                .foregroundStyle(statusColor(contract.status))
                .font(.title3)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 2) {
                Text(contract.title ?? "\(contract.type.capitalized) Contract")
                    .font(.subheadline)
                HStack(spacing: 4) {
                    Text(contract.type.replacingOccurrences(of: "_", with: " ").capitalized)
                    Text("•")
                    Text(contract.status.replacingOccurrences(of: "_", with: " ").capitalized)
                }
                .font(.caption).foregroundStyle(.secondary)
                if !issuerName.isEmpty {
                    Text("From: \(issuerName)").font(.caption2).foregroundStyle(.tertiary)
                }
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 2) {
                if let price = contract.price, price > 0 {
                    Text(EVEFormatters.formatISKShort(price))
                        .font(.caption.monospacedDigit())
                }
                Text(contract.dateIssued, style: .date)
                    .font(.caption2).foregroundStyle(.secondary)
                Text("Exp: ").font(.caption2).foregroundStyle(.tertiary) +
                Text(contract.dateExpired, style: .date).font(.caption2).foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 2)
        .task { issuerName = await NameResolver.shared.resolve(id: contract.issuerId) }
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
}
