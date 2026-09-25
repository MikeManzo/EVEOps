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

struct CorporationMarketOrdersView: View {
    @Environment(AccountManager.self) private var accountManager
    @Environment(ThemeManager.self) private var themeManager
    @State private var orders: [ESIMarketOrder] = []
    @State private var typeNames: [Int: String] = [:]
    @State private var isLoading = false
    @State private var error: String?
    @State private var selectedDivision: Int? = nil
    @State private var selection = Set<CorpOrderRow.ID>()
    @State private var sortOrder: [KeyPathComparator<CorpOrderRow>] = [
        KeyPathComparator(\.issued, order: .reverse)
    ]

    private var divisions: [Int] {
        Array(Set(orders.compactMap(\.walletDivision))).sorted()
    }

    private var filteredOrders: [ESIMarketOrder] {
        guard let div = selectedDivision else { return orders }
        return orders.filter { $0.walletDivision == div }
    }

    private var sellOrders: [ESIMarketOrder] { filteredOrders.filter { !($0.isBuyOrder ?? false) } }
    private var buyOrders: [ESIMarketOrder] { filteredOrders.filter { $0.isBuyOrder ?? false } }

    private var rows: [CorpOrderRow] {
        filteredOrders
            .map { CorpOrderRow(order: $0, typeName: typeNames[$0.typeId] ?? "Type #\($0.typeId)") }
            .sorted(using: sortOrder)
    }

    var body: some View {
        LoadingStateView(isLoading: isLoading, error: error, isEmpty: orders.isEmpty, emptyMessage: "None were found, or this character lacks the Accountant or Trader role.", emptyTitle: "No Corporation Market Orders", emptySystemImage: "cart") {
            VStack(spacing: 0) {
                toolbar
                summaryCards
                    .padding()
                ordersTable
            }
        }
        .eveScreenHeader("Corp Market Orders", section: .corpMarketOrders) {
            FreshnessIndicator(isLoading: isLoading) { await load() }
        }
        .task(id: accountManager.selectedCharacterID) { await load() }
    }

    private func load() async {
        guard let account = accountManager.selectedAccount else { return }
        isLoading = true
        error = nil
        do {
            let token = try await accountManager.validToken(for: account)
            let loaded: [ESIMarketOrder] = try await ESIClient.shared.fetchPages(
                "/corporations/\(account.corporationID)/orders/", token: token
            )
            orders = loaded
            let types = await UniverseCache.shared.types(ids: Array(Set(loaded.map(\.typeId))))
            typeNames = types.compactMapValues(\.name)
        } catch {
            self.error = error.localizedDescription
        }
        isLoading = false
    }

    private var toolbar: some View {
        HStack {
            if !divisions.isEmpty {
                Picker("Division", selection: $selectedDivision) {
                    Text("All Divisions").tag(nil as Int?)
                    ForEach(divisions, id: \.self) { div in
                        Text("Division \(div)").tag(Optional(div))
                    }
                }
                .pickerStyle(.menu)
                .frame(maxWidth: 200)
            }
            Spacer()
            Text("\(filteredOrders.count) orders")
                .font(.caption).foregroundStyle(.secondary)
        }
        .padding(10)
        .background(EVESurface.bar)
    }

    private var summaryCards: some View {
        HStack(spacing: 16) {
            summaryCard("Sell Orders", count: sellOrders.count,
                        value: sellOrders.reduce(0) { $0 + $1.price * Double($1.volumeRemain) }, color: .green)
            summaryCard("Buy Orders", count: buyOrders.count,
                        value: buyOrders.reduce(0) { $0 + $1.price * Double($1.volumeRemain) }, color: .orange)
            summaryCard("In Escrow", count: nil,
                        value: buyOrders.compactMap(\.escrow).reduce(0, +), color: themeManager.palette.accent)
        }
    }

    private func summaryCard(_ title: String, count: Int?, value: Double, color: Color) -> some View {
        VStack(spacing: 4) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            if let count { Text("\(count)").font(.eveStatCompact).foregroundStyle(color) }
            Text(EVEFormatters.formatISKShort(value)).font(.caption.monospacedDigit()).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(12)
        .eveCard(cornerRadius: EVERadius.lg)
    }

    // MARK: Table

    private var ordersTable: some View {
        Table(rows, selection: $selection, sortOrder: $sortOrder) {
            TableColumn("Item", value: \.typeName) { row in
                HStack(spacing: EVESpacing.md) {
                    CachedAsyncImage(url: EVEImageURL.typeIcon(row.order.typeId, size: 64)) { image in
                        image.resizable()
                    } placeholder: {
                        RoundedRectangle(cornerRadius: EVERadius.xs).fill(.quaternary)
                    }
                    .frame(width: 20, height: 20)
                    .clipShape(RoundedRectangle(cornerRadius: EVERadius.xs))
                    Text(row.typeName).lineLimit(1).eveTruncationHelp(row.typeName)
                }
                .eveContextMenu(.item(typeID: row.order.typeId, name: row.typeName))
            }
            .width(min: 180, ideal: 260)

            TableColumn("Side", value: \.sideSortKey) { row in
                Text(row.isBuy ? "Buy" : "Sell")
                    .font(.eveLabelSemibold)
                    .foregroundStyle(row.isBuy ? .orange : .green)
            }
            .width(44)

            TableColumn("Price", value: \.price) { row in
                Text(EVEFormatters.formatISK(row.price))
                    .monospacedDigit()
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
            .width(min: 110, ideal: 140)

            TableColumn("Remaining", value: \.fillFraction) { row in
                HStack(spacing: EVESpacing.sm) {
                    EVEProgressBar(value: 1 - row.fillFraction, tint: row.isBuy ? .orange : .green, height: 4)
                        .frame(width: 44)
                    Text("\(row.order.volumeRemain.formatted()) / \(row.order.volumeTotal.formatted())")
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
            }
            .width(min: 140, ideal: 170)

            TableColumn("Value", value: \.remainingValue) { row in
                Text(EVEFormatters.formatISKShort(row.remainingValue))
                    .monospacedDigit()
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
            .width(min: 80, ideal: 100)

            TableColumn("Div", value: \.divisionSortKey) { row in
                Text(row.order.walletDivision.map { "\($0)" } ?? "—")
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
            .width(36)

            TableColumn("Range", value: \.order.range) { row in
                Text(row.order.range.capitalized).foregroundStyle(.secondary)
            }
            .width(min: 60, ideal: 80)

            TableColumn("Issued", value: \.issued) { row in
                Text(row.issued, format: .dateTime.month(.abbreviated).day().hour().minute())
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
            .width(min: 100, ideal: 120)

            TableColumn("Expires", value: \.expires) { row in
                Text(row.expires, style: .relative)
                    .monospacedDigit()
                    .foregroundStyle(row.expires < .now.addingTimeInterval(86_400) ? .orange : .secondary)
            }
            .width(min: 80, ideal: 100)
        }
        .tableStyle(.inset(alternatesRowBackgrounds: true))
        .copyable(selectedRows.map(\.copyText))
    }

    private var selectedRows: [CorpOrderRow] {
        rows.filter { selection.contains($0.id) }
    }
}

/// Flattened, sortable view of a corporation market order for the orders table.
struct CorpOrderRow: Identifiable {
    let order: ESIMarketOrder
    let typeName: String

    var id: Int { order.orderId }
    var isBuy: Bool { order.isBuyOrder ?? false }
    var sideSortKey: Int { isBuy ? 1 : 0 }
    var price: Double { order.price }
    var issued: Date { order.issued }
    var expires: Date { order.issued.addingTimeInterval(Double(order.duration) * 86_400) }
    var remainingValue: Double { order.price * Double(order.volumeRemain) }
    var divisionSortKey: Int { order.walletDivision ?? 0 }
    /// Fraction of the order already filled.
    var fillFraction: Double {
        guard order.volumeTotal > 0 else { return 0 }
        return Double(order.volumeTotal - order.volumeRemain) / Double(order.volumeTotal)
    }

    /// Tab-separated line for ⌘C, so rows paste cleanly into a spreadsheet.
    var copyText: String {
        [typeName, isBuy ? "Buy" : "Sell", String(order.price),
         String(order.volumeRemain), String(order.volumeTotal), order.range]
            .joined(separator: "\t")
    }
}
