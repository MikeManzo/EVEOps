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

// MARK:  Trade Hub Definitions

private struct TradeHub: Sendable {
    let name: String
    let regionId: Int
    let stationId: Int
}

private let tradeHubs: [TradeHub] = [
    TradeHub(name: "Jita",    regionId: 10000002, stationId: 60003760),
    TradeHub(name: "Amarr",   regionId: 10000043, stationId: 60008494),
    TradeHub(name: "Dodixie", regionId: 10000032, stationId: 60011866),
    TradeHub(name: "Rens",    regionId: 10000030, stationId: 60004588),
    TradeHub(name: "Hek",     regionId: 10000042, stationId: 60005686),
]

// MARK:  Hub Prices Model

private struct HubPrices: Identifiable {
    let hub: TradeHub
    var bestSell: Double?
    var bestBuy: Double?
    var isLoading = false
    var error: String?
    var id: Int { hub.stationId }

    var spread: Double? {
        guard let sell = bestSell, let buy = bestBuy else { return nil }
        return sell - buy
    }

    var marginPercent: Double? {
        guard let sell = bestSell, let spread = spread, sell > 0 else { return nil }
        return (spread / sell) * 100.0
    }
}

// MARK:  Cached Type Image

private enum THCImageCache {
    static let shared = NSCache<NSNumber, NSImage>()
}

private struct THCTypeImage: View {
    let typeId: Int
    let size: CGFloat

    @State private var image: NSImage?
    @State private var failed = false

    var body: some View {
        Group {
            if let image {
                Image(nsImage: image).resizable().scaledToFit()
            } else if failed {
                Image(systemName: "cube.transparent")
                    .font(.system(size: size * 0.5))
                    .foregroundStyle(.tertiary)
            } else {
                RoundedRectangle(cornerRadius: size * 0.15).fill(.quaternary)
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: size * 0.15))
        .task(id: typeId) {
            if let cached = THCImageCache.shared.object(forKey: NSNumber(value: typeId)) {
                image = cached; return
            }
            image = nil; failed = false
            for urlOpt in [EVEImageURL.typeRender(typeId, size: 64), EVEImageURL.typeIcon(typeId, size: 64)] {
                guard let url = urlOpt,
                      let (data, resp) = try? await URLSession.shared.data(from: url),
                      (resp as? HTTPURLResponse)?.statusCode == 200,
                      let img = NSImage(data: data) else { continue }
                THCImageCache.shared.setObject(img, forKey: NSNumber(value: typeId))
                image = img
                return
            }
            failed = true
        }
    }
}

// MARK:  TradeHubComparisonView

struct TradeHubComparisonView: View {
    let initialTypeId: Int?
    let initialTypeName: String

    @Environment(AccountManager.self) private var accountManager
    @Environment(\.dismiss) private var dismiss

    @State private var itemSearchText = ""
    @State private var itemSearchResults: [(id: Int, name: String)] = []
    @State private var isSearchingItems = false
    @State private var searchTask: Task<Void, Never>?
    @State private var selectedTypeId: Int?
    @State private var selectedTypeName = ""

    @State private var hubPrices: [HubPrices] = tradeHubs.map { HubPrices(hub: $0) }
    @State private var fetchTask: Task<Void, Never>?
    @State private var isFetching = false
    @State private var hubsLoaded = 0

    var body: some View {
        VStack(spacing: 0) {
            headerPanel
            Divider()
            contentArea
        }
        .frame(minWidth: 700, idealWidth: 780, minHeight: 460)
        .onAppear {
            if let id = initialTypeId, !initialTypeName.isEmpty {
                selectedTypeId = id
                selectedTypeName = initialTypeName
                itemSearchText = initialTypeName
                Task { await fetchAllHubs(typeId: id) }
            }
        }
    }

    // MARK:  Header

    private var headerPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("Trade Hub Comparison", systemImage: "building.2.fill")
                    .font(.title3.bold())
                Spacer()
                Button("Done") { dismiss() }
                    .keyboardShortcut(.escape)
            }

            HStack(spacing: 10) {
                if let typeId = selectedTypeId {
                    THCTypeImage(typeId: typeId, size: 28)
                }

                HStack(spacing: 6) {
                    if selectedTypeId == nil {
                        Image(systemName: "magnifyingglass")
                            .foregroundStyle(.secondary)
                            .font(.subheadline)
                    }
                    TextField("Search for an item…", text: $itemSearchText)
                        .textFieldStyle(.plain)
                        .onChange(of: itemSearchText) { _, v in onItemSearchChanged(v) }
                    if isSearchingItems {
                        ProgressView().controlSize(.mini)
                    } else if !itemSearchText.isEmpty {
                        Button { clearSelection() } label: {
                            Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(7)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
                .frame(maxWidth: 360)

                Spacer()

                if isFetching {
                    HStack(spacing: 6) {
                        ProgressView().controlSize(.mini)
                        Text("\(hubsLoaded)/\(tradeHubs.count) hubs…")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .padding(16)
        .fixedSize(horizontal: false, vertical: true)
    }

    // MARK:  Content

    @ViewBuilder
    private var contentArea: some View {
        if !itemSearchResults.isEmpty && selectedTypeId == nil {
            itemSearchList
        } else if selectedTypeId != nil {
            hubTable
        } else {
            emptyState
        }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "building.2.fill")
                .font(.system(size: 44))
                .foregroundStyle(.tertiary)
            Text("Compare prices across trade hubs")
                .font(.headline)
                .foregroundStyle(.secondary)
            Text("Search for an item to see best sell and buy prices at\nJita, Amarr, Dodixie, Rens, and Hek simultaneously.")
                .font(.subheadline)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK:  Item Search List

    private var itemSearchList: some View {
        List(itemSearchResults, id: \.id) { result in
            Button {
                selectedTypeId = result.id
                selectedTypeName = result.name
                itemSearchText = result.name
                itemSearchResults = []
                Task { await fetchAllHubs(typeId: result.id) }
            } label: {
                HStack(spacing: 14) {
                    THCTypeImage(typeId: result.id, size: 40)
                    Text(result.name).font(.title3)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
                .padding(.vertical, 4)
            }
            .buttonStyle(.plain)
        }
        .listStyle(.plain)
    }

    // MARK:  Hub Table

    private var hubTable: some View {
        VStack(spacing: 0) {
            // Column header row
            HStack(spacing: 0) {
                Text("Hub")
                    .frame(width: 80, alignment: .leading)
                Text("Best Sell")
                    .frame(width: 150, alignment: .trailing)
                Text("Best Buy")
                    .frame(width: 150, alignment: .trailing)
                Text("Spread")
                    .frame(width: 140, alignment: .trailing)
                Text("Margin")
                    .frame(maxWidth: .infinity, alignment: .trailing)
                    .padding(.trailing, 16)
            }
            .font(.subheadline.bold())
            .foregroundStyle(.secondary)
            .padding(.leading, 16)
            .padding(.vertical, 8)
            .background(Color(NSColor.separatorColor).opacity(0.15))

            Divider()

            LazyVStack(spacing: 0) {
                ForEach(Array(hubPrices.enumerated()), id: \.element.id) { index, hub in
                    hubRow(hub, isEven: index % 2 == 0)
                    if index < hubPrices.count - 1 {
                        Divider()
                    }
                }
            }

            Divider()

            Text("Prices reflect the best sell/buy orders at the hub's primary station.")
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 16)
                .padding(.vertical, 6)
        }
    }

    private func hubRow(_ hub: HubPrices, isEven: Bool) -> some View {
        HStack(spacing: 0) {
            // Hub name
            VStack(alignment: .leading, spacing: 1) {
                Text(hub.hub.name)
                    .font(.headline)
            }
            .frame(width: 80, alignment: .leading)

            if hub.isLoading {
                HStack(spacing: 6) {
                    ProgressView().controlSize(.mini)
                    Text("Fetching…")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
            } else if let err = hub.error {
                Text(err)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity)
            } else {
                // Best sell
                priceCell(hub.bestSell, color: .green, label: "sell")
                    .frame(width: 150, alignment: .trailing)

                // Best buy
                priceCell(hub.bestBuy, color: .orange, label: "buy")
                    .frame(width: 150, alignment: .trailing)

                // Spread
                if let spread = hub.spread {
                    Text(EVEFormatters.formatISK(spread))
                        .font(.subheadline.monospacedDigit())
                        .foregroundStyle(spread > 0 ? .primary : .secondary)
                        .frame(width: 140, alignment: .trailing)
                } else {
                    Text("—").foregroundStyle(.tertiary)
                        .frame(width: 140, alignment: .trailing)
                }

                // Margin %
                if let margin = hub.marginPercent {
                    Text(String(format: "%.1f%%", margin))
                        .font(.subheadline.monospacedDigit().bold())
                        .foregroundStyle(marginColor(margin))
                        .frame(maxWidth: .infinity, alignment: .trailing)
                        .padding(.trailing, 16)
                } else {
                    Text("—").foregroundStyle(.tertiary)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                        .padding(.trailing, 16)
                }
            }
        }
        .padding(.leading, 16)
        .padding(.vertical, 16)
        .background(isEven ? Color.clear : Color(NSColor.separatorColor).opacity(0.06))
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder
    private func priceCell(_ price: Double?, color: Color, label: String) -> some View {
        if let price {
            Text(EVEFormatters.formatISK(price))
                .font(.subheadline.monospacedDigit().bold())
                .foregroundStyle(color)
        } else {
            Text("No \(label) orders")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
    }

    private func marginColor(_ margin: Double) -> Color {
        if margin >= 20 { return .green }
        if margin >= 10 { return Color(hue: 0.28, saturation: 0.8, brightness: 0.85) }
        if margin >= 5  { return .orange }
        return .red
    }

    // MARK:  Fetch Logic

    private func fetchAllHubs(typeId: Int) async {
        fetchTask?.cancel()
        isFetching = true
        hubsLoaded = 0
        for i in hubPrices.indices {
            hubPrices[i].isLoading = true
            hubPrices[i].error = nil
            hubPrices[i].bestSell = nil
            hubPrices[i].bestBuy = nil
        }

        let hubs = tradeHubs
        fetchTask = Task {
            await withTaskGroup(of: (Int, Double?, Double?, String?).self) { group in
                for (i, hub) in hubs.enumerated() {
                    let hubCopy = hub
                    group.addTask {
                        do {
                            let (sell, buy) = try await Self.fetchHubPrices(typeId: typeId, hub: hubCopy)
                            return (i, sell, buy, nil)
                        } catch {
                            return (i, nil, nil, "No data")
                        }
                    }
                }
                for await (index, sell, buy, err) in group {
                    guard !Task.isCancelled else { break }
                    hubPrices[index].bestSell = sell
                    hubPrices[index].bestBuy = buy
                    hubPrices[index].error = err
                    hubPrices[index].isLoading = false
                    hubsLoaded += 1
                }
            }
            isFetching = false
        }
    }

    private static func fetchHubPrices(typeId: Int, hub: TradeHub) async throws -> (Double?, Double?) {
        let orders: [ESIRegionMarketOrder] = try await ESIClient.shared.fetch(
            "/markets/\(hub.regionId)/orders/",
            queryItems: [
                URLQueryItem(name: "type_id", value: String(typeId)),
                URLQueryItem(name: "order_type", value: "all")
            ]
        )
        let atStation = orders.filter { $0.locationId == hub.stationId }
        let bestSell = atStation.filter { !$0.isBuyOrder }.map(\.price).min()
        let bestBuy  = atStation.filter {  $0.isBuyOrder }.map(\.price).max()
        return (bestSell, bestBuy)
    }

    // MARK:  Search

    private func onItemSearchChanged(_ value: String) {
        searchTask?.cancel()
        if selectedTypeId != nil && value == selectedTypeName { return }
        selectedTypeId = nil
        guard value.count >= 3 else {
            if value.isEmpty { itemSearchResults = [] }
            isSearchingItems = false
            return
        }
        isSearchingItems = true
        searchTask = Task {
            try? await Task.sleep(for: .milliseconds(400))
            guard !Task.isCancelled else { return }
            await performSearch(value)
        }
    }

    private func performSearch(_ query: String) async {
        struct SearchResp: Decodable { let inventoryType: [Int]? }
        struct NameEntry: Decodable { let id: Int; let name: String }

        var ids: [Int] = []
        if let account = accountManager.selectedAccount,
           let token = try? await accountManager.validToken(for: account) {
            let resp: SearchResp? = try? await ESIClient.shared.fetch(
                "/characters/\(account.characterID)/search/", token: token,
                queryItems: [
                    URLQueryItem(name: "categories", value: "inventory_type"),
                    URLQueryItem(name: "search", value: query),
                    URLQueryItem(name: "strict", value: "false")
                ]
            )
            ids = Array((resp?.inventoryType ?? []).prefix(40))
        }

        guard !ids.isEmpty else { itemSearchResults = []; isSearchingItems = false; return }
        let names: [NameEntry] = (try? await ESIClient.shared.post("/universe/names/", body: ids)) ?? []
        itemSearchResults = names.map { (id: $0.id, name: $0.name) }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        isSearchingItems = false
    }

    private func clearSelection() {
        itemSearchText = ""
        itemSearchResults = []
        selectedTypeId = nil
        selectedTypeName = ""
        for i in hubPrices.indices {
            hubPrices[i].bestSell = nil
            hubPrices[i].bestBuy = nil
            hubPrices[i].isLoading = false
            hubPrices[i].error = nil
        }
        fetchTask?.cancel()
        isFetching = false
        hubsLoaded = 0
    }
}
