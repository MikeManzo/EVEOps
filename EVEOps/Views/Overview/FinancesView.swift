import SwiftUI
import Charts

struct FinancesView: View {
    @Environment(AccountManager.self) private var accountManager
    @Environment(DashboardPrefetcher.self) private var prefetcher
    @State private var characterFinances: [CharacterFinanceData] = []
    @State private var isLoading = false
    @State private var error: String?
    @State private var selectedCharacterID: Int?
    @State private var selectedTab = 0
    @State private var typeNames: [Int: String] = [:]

    private var totalWealth: Double {
        characterFinances.reduce(0) { $0 + $1.balance }
    }

    private var totalEscrow: Double {
        characterFinances.reduce(0) { $0 + $1.totalEscrow }
    }

    private var totalSellOrderValue: Double {
        characterFinances.reduce(0) { $0 + $1.totalSellOrderValue }
    }

    private var totalBuyOrderValue: Double {
        characterFinances.reduce(0) { $0 + $1.totalBuyOrderValue }
    }

    private var netWorth: Double {
        totalWealth + totalEscrow + totalSellOrderValue
    }

    private var selectedFinance: CharacterFinanceData? {
        if let id = selectedCharacterID {
            return characterFinances.first { $0.characterID == id }
        }
        return characterFinances.first
    }

    var body: some View {
        LoadingStateView(isLoading: isLoading, error: error, isEmpty: characterFinances.isEmpty, emptyMessage: "No financial data") {
            ScrollView {
                VStack(spacing: 20) {
                    summaryCards
                    wealthDistribution
                    characterSelector
                    if let finance = selectedFinance {
                        characterDetail(finance)
                    }
                }
                .padding()
            }
        }
        .navigationTitle("Finances")
        .task(id: accountManager.selectedCharacterID) {
            if buildFromPrefetcher() {
                await resolveTypeNames()
                return
            }
            isLoading = true
            await loadAllFinances()
            await resolveTypeNames()
        }
    }

    // MARK:  Summary Cards

    private var summaryCards: some View {
        HStack(spacing: 16) {
            summaryCard("Wallet Balance", value: totalWealth, color: .blue)
            summaryCard("Sell Orders", value: totalSellOrderValue, color: .green)
            summaryCard("Buy Orders (Escrow)", value: totalEscrow, color: .orange)
            summaryCard("Net Worth", value: netWorth, color: .purple)
        }
    }

    private func summaryCard(_ title: String, value: Double, color: Color) -> some View {
        VStack(spacing: 6) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(EVEFormatters.formatISKShort(value))
                .font(.title3.bold().monospacedDigit())
                .foregroundStyle(color)
        }
        .frame(maxWidth: .infinity)
        .padding()
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
    }

    // MARK:  Wealth Distribution

    private var wealthDistribution: some View {
        HStack(alignment: .top, spacing: 20) {
            // Pie chart
            VStack(alignment: .leading) {
                Text("Wealth Distribution")
                    .font(.headline)
                if characterFinances.count > 1 {
                    Chart(characterFinances, id: \.characterID) { data in
                        SectorMark(
                            angle: .value("ISK", data.balance),
                            innerRadius: .ratio(0.5),
                            angularInset: 2
                        )
                        .foregroundStyle(by: .value("Character", data.characterName))
                        .cornerRadius(4)
                    }
                    .frame(height: 220)
                } else if let first = characterFinances.first {
                    Text(EVEFormatters.formatISK(first.balance))
                        .font(.title2.bold().monospacedDigit())
                        .frame(maxWidth: .infinity, minHeight: 100, alignment: .center)
                }
            }
            .padding()
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))

            // Breakdown list
            VStack(alignment: .leading, spacing: 10) {
                Text("By Character")
                    .font(.headline)
                ForEach(characterFinances.sorted(by: { $0.balance > $1.balance }), id: \.characterID) { data in
                    HStack(spacing: 10) {
                        AsyncImage(url: EVEImageURL.characterPortrait(data.characterID, size: 128)) { image in
                            image.resizable()
                        } placeholder: {
                            RoundedRectangle(cornerRadius: 4).fill(.quaternary)
                        }
                        .frame(width: 32, height: 32)
                        .clipShape(RoundedRectangle(cornerRadius: 4))

                        VStack(alignment: .leading, spacing: 2) {
                            Text(data.characterName)
                                .font(.subheadline)
                            Text(data.corporationName)
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                        }

                        Spacer()

                        VStack(alignment: .trailing, spacing: 2) {
                            Text(EVEFormatters.formatISKShort(data.balance))
                                .font(.subheadline.monospacedDigit())
                            if totalWealth > 0 {
                                Text(String(format: "%.1f%%", (data.balance / totalWealth) * 100))
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
            .padding()
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
        }
    }

    // MARK:  Character Selector

    private var characterSelector: some View {
        VStack(spacing: 0) {
            if characterFinances.count > 1 {
                Picker("Character", selection: $selectedCharacterID) {
                    ForEach(characterFinances, id: \.characterID) { finance in
                        Text(finance.characterName).tag(Optional(finance.characterID))
                    }
                }
                .pickerStyle(.segmented)
                .padding(.bottom, 8)
            }
        }
    }

    // MARK:  Character Detail

    @ViewBuilder
    private func characterDetail(_ finance: CharacterFinanceData) -> some View {
        // Balance header with sparkline
        balanceHeader(finance)

        // Tab content
        Picker("View", selection: $selectedTab) {
            Text("Journal (\(finance.journal.count))").tag(0)
            Text("Transactions (\(finance.transactions.count))").tag(1)
            Text("Market Orders (\(finance.marketOrders.count))").tag(2)
            Text("Loyalty Points (\(finance.loyaltyPoints.count))").tag(3)
        }
        .pickerStyle(.segmented)
        .frame(maxWidth: 600)

        switch selectedTab {
        case 0: journalSection(finance.journal)
        case 1: transactionSection(finance.transactions)
        case 2: marketOrdersSection(finance.marketOrders)
        case 3: loyaltyPointsSection(finance.loyaltyPoints)
        default: EmptyView()
        }
    }

    private func balanceHeader(_ finance: CharacterFinanceData) -> some View {
        HStack(spacing: 20) {
            AsyncImage(url: EVEImageURL.characterPortrait(finance.characterID, size: 256)) { image in
                image.resizable()
            } placeholder: {
                RoundedRectangle(cornerRadius: 8).fill(.quaternary)
            }
            .frame(width: 64, height: 64)
            .clipShape(RoundedRectangle(cornerRadius: 8))

            VStack(alignment: .leading, spacing: 4) {
                Text(finance.characterName)
                    .font(.title3.bold())
                Text(EVEFormatters.formatISK(finance.balance))
                    .font(.title.bold().monospacedDigit())
                    .foregroundStyle(.blue)
            }

            Spacer()

            // Balance sparkline from journal
            if !finance.journal.isEmpty {
                balanceSparkline(finance.journal)
            }

            VStack(alignment: .trailing, spacing: 6) {
                Label("\(finance.marketOrders.filter { !($0.isBuyOrder ?? false) }.count) sell", systemImage: "arrow.up.circle.fill")
                    .font(.caption)
                    .foregroundStyle(.green)
                Label("\(finance.marketOrders.filter { $0.isBuyOrder ?? false }.count) buy", systemImage: "arrow.down.circle.fill")
                    .font(.caption)
                    .foregroundStyle(.orange)
                Label(EVEFormatters.formatISKShort(finance.totalEscrow), systemImage: "lock.fill")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
    }

    @ViewBuilder
    private func balanceSparkline(_ journal: [ESIWalletJournalEntry]) -> some View {
        let points = journal.prefix(50).reversed().compactMap { entry -> BalancePoint? in
            guard let bal = entry.balance else { return nil }
            return BalancePoint(date: entry.date, balance: bal)
        }
        if points.count > 1 {
            Chart(points, id: \.date) { point in
                LineMark(x: .value("Date", point.date), y: .value("Balance", point.balance))
                    .foregroundStyle(.blue)
                AreaMark(x: .value("Date", point.date), y: .value("Balance", point.balance))
                    .foregroundStyle(.blue.opacity(0.1))
            }
            .chartXAxis(.hidden)
            .chartYAxis(.hidden)
            .frame(width: 220, height: 60)
        }
    }

    // MARK:  Journal

    private func journalSection(_ journal: [ESIWalletJournalEntry]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            if journal.isEmpty {
                Text("No journal entries")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 100)
            } else {
                // Summary by ref type
                let grouped = Dictionary(grouping: journal) { $0.refType }
                let topTypes = grouped.sorted { a, b in
                    let aTotal = a.value.compactMap(\.amount).map(abs).reduce(0, +)
                    let bTotal = b.value.compactMap(\.amount).map(abs).reduce(0, +)
                    return aTotal > bTotal
                }.prefix(5)

                if !topTypes.isEmpty {
                    HStack(spacing: 12) {
                        ForEach(Array(topTypes), id: \.key) { refType, entries in
                            let total = entries.compactMap(\.amount).reduce(0, +)
                            VStack(spacing: 2) {
                                Text(formatRefType(refType))
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                                Text(EVEFormatters.formatISKShort(total))
                                    .font(.caption.bold().monospacedDigit())
                                    .foregroundStyle(total >= 0 ? .green : .red)
                                Text("\(entries.count)x")
                                    .font(.caption2)
                                    .foregroundStyle(.tertiary)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(8)
                            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
                        }
                    }
                }

                // Journal entries list
                LazyVStack(spacing: 1) {
                    ForEach(journal) { entry in
                        journalRow(entry)
                    }
                }
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
            }
        }
    }

    private func journalRow(_ entry: ESIWalletJournalEntry) -> some View {
        HStack(spacing: 10) {
            Image(systemName: (entry.amount ?? 0) >= 0 ? "arrow.down.circle.fill" : "arrow.up.circle.fill")
                .foregroundStyle((entry.amount ?? 0) >= 0 ? .green : .red)
                .font(.title3)

            VStack(alignment: .leading, spacing: 2) {
                Text(formatRefType(entry.refType))
                    .font(.subheadline)
                if !entry.description.isEmpty {
                    Text(entry.description)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                if let reason = entry.reason, !reason.isEmpty {
                    Text(reason)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 2) {
                if let amount = entry.amount {
                    Text((amount >= 0 ? "+" : "") + EVEFormatters.formatISKShort(amount))
                        .font(.subheadline.bold().monospacedDigit())
                        .foregroundStyle(amount >= 0 ? .green : .red)
                }
                if let balance = entry.balance {
                    Text(EVEFormatters.formatISKShort(balance))
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                Text(EVEFormatters.dateFormatter.string(from: entry.date))
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    // MARK:  Transactions

    private func transactionSection(_ transactions: [ESIWalletTransaction]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            if transactions.isEmpty {
                Text("No transactions")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 100)
            } else {
                // Summary
                let buyTotal = transactions.filter(\.isBuy).reduce(0.0) { $0 + $1.unitPrice * Double($1.quantity) }
                let sellTotal = transactions.filter { !$0.isBuy }.reduce(0.0) { $0 + $1.unitPrice * Double($1.quantity) }

                HStack(spacing: 16) {
                    VStack(spacing: 2) {
                        Text("Bought")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(EVEFormatters.formatISKShort(buyTotal))
                            .font(.subheadline.bold().monospacedDigit())
                            .foregroundStyle(.orange)
                        Text("\(transactions.filter(\.isBuy).count) orders")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(10)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))

                    VStack(spacing: 2) {
                        Text("Sold")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(EVEFormatters.formatISKShort(sellTotal))
                            .font(.subheadline.bold().monospacedDigit())
                            .foregroundStyle(.green)
                        Text("\(transactions.filter { !$0.isBuy }.count) orders")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(10)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))

                    VStack(spacing: 2) {
                        Text("Net")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        let net = sellTotal - buyTotal
                        Text(EVEFormatters.formatISKShort(net))
                            .font(.subheadline.bold().monospacedDigit())
                            .foregroundStyle(net >= 0 ? .green : .red)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(10)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
                }

                LazyVStack(spacing: 1) {
                    ForEach(transactions) { tx in
                        transactionRow(tx)
                    }
                }
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
            }
        }
    }

    private func transactionRow(_ tx: ESIWalletTransaction) -> some View {
        HStack(spacing: 10) {
            AsyncImage(url: EVEImageURL.typeIcon(tx.typeId, size: 64)) { image in
                image.resizable()
            } placeholder: {
                RoundedRectangle(cornerRadius: 4).fill(.quaternary)
            }
            .frame(width: 32, height: 32)
            .clipShape(RoundedRectangle(cornerRadius: 4))

            VStack(alignment: .leading, spacing: 2) {
                Text(typeNames[tx.typeId] ?? "Type #\(tx.typeId)")
                    .font(.subheadline)
                Text("\(tx.quantity)x @ \(EVEFormatters.formatISK(tx.unitPrice))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 2) {
                let total = tx.unitPrice * Double(tx.quantity)
                Text(EVEFormatters.formatISKShort(total))
                    .font(.subheadline.bold().monospacedDigit())
                    .foregroundStyle(tx.isBuy ? .red : .green)
                Text(tx.isBuy ? "Buy" : "Sell")
                    .font(.caption2)
                    .foregroundStyle(tx.isBuy ? .orange : .green)
                Text(EVEFormatters.dateFormatter.string(from: tx.date))
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    // MARK:  Market Orders

    private func marketOrdersSection(_ orders: [ESIMarketOrder]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            if orders.isEmpty {
                Text("No active market orders")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 100)
            } else {
                let sellOrders = orders.filter { !($0.isBuyOrder ?? false) }
                let buyOrders = orders.filter { $0.isBuyOrder ?? false }

                // Summary
                HStack(spacing: 16) {
                    VStack(spacing: 2) {
                        Text("Sell Orders")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text("\(sellOrders.count)")
                            .font(.title3.bold())
                            .foregroundStyle(.green)
                        Text(EVEFormatters.formatISKShort(sellOrders.reduce(0) { $0 + $1.price * Double($1.volumeRemain) }))
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(10)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))

                    VStack(spacing: 2) {
                        Text("Buy Orders")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text("\(buyOrders.count)")
                            .font(.title3.bold())
                            .foregroundStyle(.orange)
                        Text(EVEFormatters.formatISKShort(buyOrders.reduce(0) { $0 + $1.price * Double($1.volumeRemain) }))
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(10)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))

                    VStack(spacing: 2) {
                        Text("In Escrow")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(EVEFormatters.formatISKShort(buyOrders.compactMap(\.escrow).reduce(0, +)))
                            .font(.title3.bold().monospacedDigit())
                            .foregroundStyle(.orange)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(10)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
                }

                // Order list
                if !sellOrders.isEmpty {
                    Text("Sell Orders")
                        .font(.subheadline.bold())
                        .padding(.top, 4)
                    LazyVStack(spacing: 1) {
                        ForEach(sellOrders) { order in
                            marketOrderRow(order)
                        }
                    }
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
                }

                if !buyOrders.isEmpty {
                    Text("Buy Orders")
                        .font(.subheadline.bold())
                        .padding(.top, 4)
                    LazyVStack(spacing: 1) {
                        ForEach(buyOrders) { order in
                            marketOrderRow(order)
                        }
                    }
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
                }
            }
        }
    }

    private func marketOrderRow(_ order: ESIMarketOrder) -> some View {
        let isBuy = order.isBuyOrder ?? false
        return HStack(spacing: 10) {
            AsyncImage(url: EVEImageURL.typeIcon(order.typeId, size: 64)) { image in
                image.resizable()
            } placeholder: {
                RoundedRectangle(cornerRadius: 4).fill(.quaternary)
            }
            .frame(width: 32, height: 32)
            .clipShape(RoundedRectangle(cornerRadius: 4))

            VStack(alignment: .leading, spacing: 2) {
                Text(typeNames[order.typeId] ?? "Type #\(order.typeId)")
                    .font(.subheadline)
                Text("\(order.volumeRemain)/\(order.volumeTotal) remaining")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                // Progress bar
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 2)
                            .fill(.quaternary)
                        RoundedRectangle(cornerRadius: 2)
                            .fill(isBuy ? .orange : .green)
                            .frame(width: geo.size.width * Double(order.volumeTotal - order.volumeRemain) / max(Double(order.volumeTotal), 1))
                    }
                }
                .frame(height: 4)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 2) {
                Text(EVEFormatters.formatISK(order.price))
                    .font(.subheadline.monospacedDigit())
                Text(EVEFormatters.formatISKShort(order.price * Double(order.volumeRemain)))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                Text("\(order.duration)d \u{2022} \(order.range)")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                Text("Issued: \(EVEFormatters.dateFormatter.string(from: order.issued))")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    // MARK:  Loyalty Points

    private func loyaltyPointsSection(_ lp: [ResolvedLoyaltyPoints]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            if lp.isEmpty {
                Text("No loyalty points")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 100)
            } else {
                let totalLP = lp.reduce(0) { $0 + $1.loyaltyPoints }
                HStack {
                    Text("Total LP")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text("\(totalLP.formatted()) LP")
                        .font(.title3.bold().monospacedDigit())
                        .foregroundStyle(.purple)
                }
                .padding()
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))

                LazyVStack(spacing: 1) {
                    ForEach(lp.sorted(by: { $0.loyaltyPoints > $1.loyaltyPoints }), id: \.corporationId) { entry in
                        HStack(spacing: 10) {
                            AsyncImage(url: EVEImageURL.corporationLogo(entry.corporationId, size: 64)) { image in
                                image.resizable()
                            } placeholder: {
                                RoundedRectangle(cornerRadius: 4).fill(.quaternary)
                            }
                            .frame(width: 32, height: 32)
                            .clipShape(RoundedRectangle(cornerRadius: 4))

                            Text(entry.corporationName)
                                .font(.subheadline)

                            Spacer()

                            Text("\(entry.loyaltyPoints.formatted()) LP")
                                .font(.subheadline.bold().monospacedDigit())
                                .foregroundStyle(.purple)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                    }
                }
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
            }
        }
    }

    // MARK:  Type Name Resolution

    private func resolveTypeNames() async {
        var allTypeIDs = Set<Int>()
        for finance in characterFinances {
            finance.transactions.forEach { allTypeIDs.insert($0.typeId) }
            finance.marketOrders.forEach { allTypeIDs.insert($0.typeId) }
        }
        guard !allTypeIDs.isEmpty else { return }
        let types = await UniverseCache.shared.types(ids: Array(allTypeIDs))
        typeNames = types.mapValues { $0.name }
    }

    // MARK:  Helpers

    private func formatRefType(_ refType: String) -> String {
        refType.replacingOccurrences(of: "_", with: " ").capitalized
    }

    // MARK:  Prefetcher Fast Path

    private func buildFromPrefetcher() -> Bool {
        var results: [CharacterFinanceData] = []
        for account in accountManager.accounts {
            guard let prefetched = prefetcher.data(for: account.characterID) else { return false }

            // Resolve LP corporation names from prefetcher
            let resolvedLP = prefetched.loyaltyPoints.map { entry in
                ResolvedLoyaltyPoints(
                    corporationId: entry.corporationId,
                    corporationName: prefetcher.resolvedNames[entry.corporationId] ?? "Corporation #\(entry.corporationId)",
                    loyaltyPoints: entry.loyaltyPoints
                )
            }

            results.append(CharacterFinanceData(
                characterID: account.characterID,
                characterName: account.characterName,
                corporationName: account.corporationName,
                balance: prefetched.wallet,
                journal: prefetched.journal.sorted { $0.date > $1.date },
                transactions: prefetched.transactions.sorted { $0.date > $1.date },
                marketOrders: prefetched.marketOrders,
                loyaltyPoints: resolvedLP
            ))
        }
        characterFinances = results.sorted { $0.balance > $1.balance }
        if selectedCharacterID == nil {
            selectedCharacterID = characterFinances.first?.characterID
        }
        return !results.isEmpty
    }

    // MARK:  Data Loading

    private func loadAllFinances() async {
        isLoading = true
        self.error = nil
        var results: [CharacterFinanceData] = []
        var lastError: Error?

        for account in accountManager.accounts {
            do {
                let data = try await loadFinance(for: account)
                results.append(data)
            } catch {
                lastError = error
            }
        }

        characterFinances = results.sorted { $0.balance > $1.balance }
        if results.isEmpty, let lastError {
            self.error = lastError.localizedDescription
        }
        if selectedCharacterID == nil {
            selectedCharacterID = characterFinances.first?.characterID
        }
        isLoading = false
    }

    private func loadFinance(for account: StoredAccount) async throws -> CharacterFinanceData {
        let token = try await accountManager.validToken(for: account)
        let charID = account.characterID

        // Fetch each independently so one failure doesn't block others
        var balance: Double = 0
        var journal: [ESIWalletJournalEntry] = []
        var transactions: [ESIWalletTransaction] = []
        var orders: [ESIMarketOrder] = []
        var lp: [ESILoyaltyPoints] = []

        do { balance = try await ESIClient.shared.fetch("/characters/\(charID)/wallet/", token: token) } catch {}
        do { journal = try await ESIClient.shared.fetch("/characters/\(charID)/wallet/journal/", token: token) } catch {}
        do { transactions = try await ESIClient.shared.fetch("/characters/\(charID)/wallet/transactions/", token: token) } catch {}
        do { orders = try await ESIClient.shared.fetch("/characters/\(charID)/orders/", token: token) } catch {}
        do { lp = try await ESIClient.shared.fetch("/characters/\(charID)/loyalty/points/", token: token) } catch {}

        // Resolve LP corporation names
        let corpIDs = lp.map(\.corporationId)
        let names = await NameResolver.shared.resolve(ids: corpIDs)
        let resolvedLP = lp.map { entry in
            ResolvedLoyaltyPoints(
                corporationId: entry.corporationId,
                corporationName: names[entry.corporationId] ?? "Corporation #\(entry.corporationId)",
                loyaltyPoints: entry.loyaltyPoints
            )
        }

        return CharacterFinanceData(
            characterID: charID,
            characterName: account.characterName,
            corporationName: account.corporationName,
            balance: balance,
            journal: journal.sorted { $0.date > $1.date },
            transactions: transactions.sorted { $0.date > $1.date },
            marketOrders: orders,
            loyaltyPoints: resolvedLP
        )
    }
}

// MARK:  Data Models

struct CharacterFinanceData {
    let characterID: Int
    let characterName: String
    let corporationName: String
    let balance: Double
    let journal: [ESIWalletJournalEntry]
    let transactions: [ESIWalletTransaction]
    let marketOrders: [ESIMarketOrder]
    let loyaltyPoints: [ResolvedLoyaltyPoints]

    var totalEscrow: Double {
        marketOrders.filter { $0.isBuyOrder ?? false }.compactMap(\.escrow).reduce(0, +)
    }

    var totalSellOrderValue: Double {
        marketOrders.filter { !($0.isBuyOrder ?? false) }.reduce(0) { $0 + $1.price * Double($1.volumeRemain) }
    }

    var totalBuyOrderValue: Double {
        marketOrders.filter { $0.isBuyOrder ?? false }.reduce(0) { $0 + $1.price * Double($1.volumeRemain) }
    }
}

struct ResolvedLoyaltyPoints {
    let corporationId: Int
    let corporationName: String
    let loyaltyPoints: Int
}

struct BalancePoint {
    let date: Date
    let balance: Double
}
