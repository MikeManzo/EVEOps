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
    @State private var orders: [ESIMarketOrder] = []
    @State private var isLoading = false
    @State private var error: String?
    @State private var selectedDivision: Int? = nil

    private var divisions: [Int] {
        Array(Set(orders.compactMap(\.walletDivision))).sorted()
    }

    private var filteredOrders: [ESIMarketOrder] {
        guard let div = selectedDivision else { return orders }
        return orders.filter { $0.walletDivision == div }
    }

    private var sellOrders: [ESIMarketOrder] { filteredOrders.filter { !($0.isBuyOrder ?? false) } }
    private var buyOrders: [ESIMarketOrder] { filteredOrders.filter { $0.isBuyOrder ?? false } }

    var body: some View {
        LoadingStateView(isLoading: isLoading, error: error, isEmpty: orders.isEmpty, emptyMessage: "No corp market orders found or insufficient roles") {
            VStack(spacing: 0) {
                toolbar
                ScrollView {
                    VStack(spacing: 16) {
                        summaryCards
                        if !sellOrders.isEmpty { orderSection("Sell Orders", orders: sellOrders, color: .green) }
                        if !buyOrders.isEmpty { orderSection("Buy Orders", orders: buyOrders, color: .orange) }
                    }
                    .padding()
                }
            }
        }
        .navigationTitle("Corp Market Orders")
        .task(id: accountManager.selectedCharacterID) {
            guard let account = accountManager.selectedAccount else { return }
            isLoading = true
            error = nil
            do {
                let token = try await accountManager.validToken(for: account)
                let loaded: [ESIMarketOrder] = try await ESIClient.shared.fetchPages(
                    "/corporations/\(account.corporationID)/orders/", token: token
                )
                orders = loaded.sorted { $0.issued > $1.issued }
            } catch {
                self.error = error.localizedDescription
            }
            isLoading = false
        }
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
        .background(.bar)
    }

    private var summaryCards: some View {
        HStack(spacing: 16) {
            summaryCard("Sell Orders", count: sellOrders.count,
                        value: sellOrders.reduce(0) { $0 + $1.price * Double($1.volumeRemain) }, color: .green)
            summaryCard("Buy Orders", count: buyOrders.count,
                        value: buyOrders.reduce(0) { $0 + $1.price * Double($1.volumeRemain) }, color: .orange)
            summaryCard("In Escrow", count: nil,
                        value: buyOrders.compactMap(\.escrow).reduce(0, +), color: .blue)
        }
    }

    private func summaryCard(_ title: String, count: Int?, value: Double, color: Color) -> some View {
        VStack(spacing: 4) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            if let count { Text("\(count)").font(.title3.bold()).foregroundStyle(color) }
            Text(EVEFormatters.formatISKShort(value)).font(.caption.monospacedDigit()).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(12)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
    }

    private func orderSection(_ title: String, orders: [ESIMarketOrder], color: Color) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.subheadline.bold())
            LazyVStack(spacing: 1) {
                ForEach(orders) { order in
                    CorpMarketOrderRow(order: order, color: color)
                }
            }
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
        }
    }
}

struct CorpMarketOrderRow: View {
    let order: ESIMarketOrder
    let color: Color
    @State private var typeName = ""

    var body: some View {
        HStack(spacing: 10) {
            AsyncImage(url: EVEImageURL.typeIcon(order.typeId, size: 64)) { image in
                image.resizable()
            } placeholder: {
                RoundedRectangle(cornerRadius: 4).fill(.quaternary)
            }
            .frame(width: 32, height: 32)
            .clipShape(RoundedRectangle(cornerRadius: 4))

            VStack(alignment: .leading, spacing: 2) {
                Text(typeName.isEmpty ? "Type #\(order.typeId)" : typeName).font(.subheadline)
                Text("\(order.volumeRemain)/\(order.volumeTotal) remaining")
                    .font(.caption).foregroundStyle(.secondary)
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 2).fill(.quaternary)
                        RoundedRectangle(cornerRadius: 2).fill(color)
                            .frame(width: geo.size.width * Double(order.volumeTotal - order.volumeRemain) / max(Double(order.volumeTotal), 1))
                    }
                }
                .frame(height: 4)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 2) {
                Text(EVEFormatters.formatISK(order.price)).font(.subheadline.monospacedDigit())
                if let div = order.walletDivision {
                    Text("Div \(div)").font(.caption2).foregroundStyle(.secondary)
                }
                Text("\(order.duration)d • \(order.range)").font(.caption2).foregroundStyle(.tertiary)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .task { typeName = (await UniverseCache.shared.type(id: order.typeId))?.name ?? "" }
    }
}
