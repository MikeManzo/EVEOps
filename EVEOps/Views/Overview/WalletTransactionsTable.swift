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

/// Flattened, sortable view of a wallet market transaction for the transactions table.
struct TransactionRow: Identifiable {
    let tx: ESIWalletTransaction
    let typeName: String

    var id: Int { tx.transactionId }
    var date: Date { tx.date }
    var side: String { tx.isBuy ? String(localized: "Buy") : String(localized: "Sell") }
    var quantity: Int { tx.quantity }
    var unitPrice: Double { tx.unitPrice }
    /// Signed from the wallet's point of view: buys cost, sells earn.
    var total: Double { (tx.isBuy ? -1 : 1) * tx.unitPrice * Double(tx.quantity) }

    /// Tab-separated line for ⌘C, so rows paste cleanly into a spreadsheet.
    var copyText: String {
        [tx.date.formatted(.iso8601), typeName, side, String(tx.quantity),
         String(tx.unitPrice), String(abs(total))].joined(separator: "\t")
    }
}

/// Wallet market transactions as a native table — sortable columns, search, multi-select
/// and ⌘C — with the buy/sell/net summary above it. Sits inside the Finances page's
/// scroll view, so it takes a fixed height and scrolls itself.
struct WalletTransactionsTable: View {
    let transactions: [ESIWalletTransaction]
    let typeNames: [Int: String]

    @State private var searchText = ""
    @State private var selection = Set<TransactionRow.ID>()
    @State private var sortOrder: [KeyPathComparator<TransactionRow>] = [KeyPathComparator(\.date, order: .reverse)]

    private var rows: [TransactionRow] {
        transactions
            .map { TransactionRow(tx: $0, typeName: typeNames[$0.typeId] ?? "Type #\($0.typeId)") }
            .filter { searchText.isEmpty || $0.typeName.localizedCaseInsensitiveContains(searchText) }
            .sorted(using: sortOrder)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: EVESpacing.md) {
            if transactions.isEmpty {
                EVEEmptyState("No Transactions", systemImage: "cart")
                    .frame(height: 160)
            } else {
                summary
                HStack(spacing: EVESpacing.sm) {
                    Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                    TextField("Search items", text: $searchText).eveFindTarget().textFieldStyle(.plain)
                }
                .padding(.horizontal, EVESpacing.md)
                .padding(.vertical, 5)
                .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: EVERadius.sm))
                .frame(maxWidth: 280)

                table
                    .frame(height: 420)
                    .clipShape(RoundedRectangle(cornerRadius: EVERadius.xl))
            }
        }
    }

    private var summary: some View {
        let buys = transactions.filter(\.isBuy)
        let sells = transactions.filter { !$0.isBuy }
        let buyTotal = buys.reduce(0.0) { $0 + $1.unitPrice * Double($1.quantity) }
        let sellTotal = sells.reduce(0.0) { $0 + $1.unitPrice * Double($1.quantity) }
        let net = sellTotal - buyTotal
        return HStack(spacing: EVESpacing.xl) {
            tile("Bought", buyTotal, .orange, footnote: "\(buys.count) transactions")
            tile("Sold", sellTotal, .green, footnote: "\(sells.count) transactions")
            tile("Net", net, net >= 0 ? .green : .red, footnote: nil)
        }
    }

    private func tile(_ title: LocalizedStringKey, _ value: Double, _ color: Color, footnote: String?) -> some View {
        VStack(spacing: 2) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Text(EVEFormatters.formatISKShort(value))
                .font(.subheadline.bold().monospacedDigit())
                .foregroundStyle(eveAmountStyle(value, color))
                .eveNumeric(value)
            if let footnote {
                Text(footnote).font(.caption2).foregroundStyle(.tertiary)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(EVESpacing.md + 2)
        .eveCard(cornerRadius: EVERadius.md)
    }

    private var table: some View {
        Table(rows, selection: $selection, sortOrder: $sortOrder) {
            TableColumn("When", value: \.date) { row in
                Text(EVEDates.short(row.date))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .help(EVEDates.full(row.date))
            }
            .width(min: 80, ideal: 100)

            TableColumn("Item", value: \.typeName) { row in
                HStack(spacing: EVESpacing.md) {
                    CachedAsyncImage(url: EVEImageURL.typeIcon(row.tx.typeId, size: 64)) { image in
                        image.resizable()
                    } placeholder: {
                        RoundedRectangle(cornerRadius: EVERadius.xs).fill(.quaternary)
                    }
                    .frame(width: 20, height: 20)
                    .clipShape(RoundedRectangle(cornerRadius: EVERadius.xs))
                    Text(row.typeName).lineLimit(1).eveTruncationHelp(row.typeName)
                }
                .eveContextMenu(.item(typeID: row.tx.typeId, name: row.typeName))
            }
            .width(min: 180, ideal: 260)

            TableColumn("Side", value: \.side) { row in
                Text(row.side)
                    .font(.eveLabelSemibold)
                    .foregroundStyle(row.tx.isBuy ? .orange : .green)
            }
            .width(44)

            TableColumn("Qty", value: \.quantity) { row in
                Text(row.quantity.formatted())
                    .monospacedDigit()
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
            .width(min: 50, ideal: 70)

            TableColumn("Unit Price", value: \.unitPrice) { row in
                Text(EVEFormatters.formatISK(row.unitPrice))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
            .width(min: 110, ideal: 140)

            TableColumn("Total", value: \.total) { row in
                Text(EVEFormatters.formatISKShort(row.total))
                    .fontWeight(.semibold)
                    .monospacedDigit()
                    .foregroundStyle(eveAmountStyle(row.total, row.total >= 0 ? .green : .red))
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
            .width(min: 80, ideal: 100)
        }
        .tableStyle(.inset(alternatesRowBackgrounds: true))
        .copyable(rows.filter { selection.contains($0.id) }.map(\.copyText))
    }
}
