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
import Charts
import FoundationModels

extension MarketBrowserView {
    func onRegionChanged() {
        regionManuallyOverridden = true
        jumpCache.removeAll()
        insightResetKey = ""
        let regionId = selectedRegionId
        if let typeId = selectedTypeId {
            Task {
                await withTaskGroup(of: Void.self) { group in
                    group.addTask { await self.loadOrders(typeId: typeId, regionOverride: regionId) }
                    group.addTask { await self.loadPriceHistory(typeId: typeId, regionOverride: regionId) }
                }
                insightResetKey = "\(typeId)-\(regionId)"
            }
        }
    }

    // MARK:  Left Pane (search bar + group tree)

    var leftPane: some View {
        VStack(spacing: 0) {
            searchBar
                .padding(10)
            Divider()
            groupTree
        }
        .background(Color(NSColor.controlBackgroundColor))
    }

    // MARK:  Search Bar

    var searchBar: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
                .font(.subheadline)
            TextField("Search items...", text: $searchText)
                .textFieldStyle(.plain)
                .font(.subheadline)
            if !searchText.isEmpty {
                Button {
                    searchText = ""
                    searchResults = []
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(6)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
        .onChange(of: searchText) { _, newValue in
            searchTask?.cancel()
            // Clear any previously selected item so the detail pane doesn't show stale data
            if !newValue.isEmpty {
                selectedTypeId = nil
                selectedTypeName = ""
                selectedTypeInfo = nil
                sellOrders = []
                buyOrders = []
                priceHistory = []
                adjustedPrice = nil
                averagePrice = nil
                ordersError = nil
                insightResetKey = ""
            }
            guard newValue.count >= 3 else {
                searchResults = []
                isSearching = false
                return
            }
            isSearching = true
            searchTask = Task {
                try? await Task.sleep(for: .milliseconds(400))
                guard !Task.isCancelled else { return }
                await performSearch(newValue)
            }
        }
    }

    // MARK:  Right Pane (items list — search results or group contents)

    @ViewBuilder
    var rightPane: some View {
        if searchText.count >= 3 {
            searchResultsList
        } else if selectedGroupId != nil {
            groupTypesPanel
        } else {
            VStack(spacing: 10) {
                Image(systemName: "chart.xyaxis.line")
                    .font(.system(size: 40))
                    .foregroundStyle(Color(red: 0.2, green: 0.75, blue: 0.8).opacity(0.6))
                Text("Select a group from the registry")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.secondary)
                Text("or search by name to find an item")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    // MARK:  Search Results List

    @ViewBuilder
    var searchResultsList: some View {
        if isSearching {
            ProgressView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if searchResults.isEmpty {
            Text("No results found")
                .foregroundStyle(.secondary)
                .font(.caption)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            List(searchResults, selection: Binding(
                get: { selectedTypeId },
                set: { id in
                    if let id, let result = searchResults.first(where: { $0.typeId == id }) {
                        Task { await selectType(id, name: result.name) }
                    }
                }
            )) { result in
                typeRow(typeId: result.typeId, name: result.name)
                    .tag(result.typeId)
            }
            .listStyle(.plain)
        }
    }

    // MARK:  Group Tree

    @ViewBuilder
    var groupTree: some View {
        if isLoadingGroups {
            VStack(spacing: 8) {
                ProgressView()
                Text("Loading market groups...")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            List(rootNodes, children: \.children, selection: $selectedGroupId) { node in
                Label {
                    Text(node.group.name)
                        .font(.subheadline)
                } icon: {
                    if node.group.parentGroupId == nil {
                        // Root category — distinctive icon + color from marketGroupIcon
                        let (symbol, color) = marketGroupIcon(node.group.name)
                        Image(systemName: symbol)
                            .foregroundStyle(color)
                    } else if node.children != nil {
                        Image(systemName: "folder.fill")
                            .foregroundStyle(Color.blue.opacity(0.75))
                    } else if let firstType = node.group.types.first {
                        CachedAsyncImage(url: EVEImageURL.typeIcon(firstType, size: 64)) { image in
                            image.resizable().scaledToFit()
                        } placeholder: {
                            Image(systemName: "tag.fill")
                                .foregroundStyle(Color.secondary)
                        }
                        .frame(width: 16, height: 16)
                    } else {
                        Image(systemName: "tag.fill")
                            .foregroundStyle(Color.secondary)
                    }
                }
            }
            .listStyle(.sidebar)
            .onChange(of: selectedGroupId) { _, newId in
                if let id = newId, let group = fetchedGroups[id] {
                    selectedTypeId = nil
                    Task { await loadGroupTypes(group: group) }
                }
            }
        }
    }

    // MARK:  Type Row (shared)

    func typeRow(typeId: Int, name: String) -> some View {
        HStack(spacing: 8) {
            MarketTypeImage(typeId: typeId, size: 22, cornerRadius: 3)
            Text(name)
                .font(.headline)
                .lineLimit(1)
        }
    }

    // MARK:  Detail Pane (bottom, full width)

    @ViewBuilder
    var detailPane: some View {
        if let typeId = selectedTypeId {
            itemDetailView(typeId: typeId)
        } else {
            VStack(spacing: 10) {
                Image(systemName: "chart.line.uptrend.xyaxis")
                    .font(.system(size: 44))
                    .foregroundStyle(Color(red: 0.2, green: 0.75, blue: 0.8).opacity(0.5))
                Text("No item selected")
                    .font(.headline)
                    .foregroundStyle(.secondary)
                Text("Browse the market registry or search by name\nto analyze orders and pricing.")
                    .font(.subheadline)
                    .foregroundStyle(.tertiary)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    // MARK:  Group Types Panel

    @ViewBuilder
    var groupTypesPanel: some View {
        if isLoadingGroupTypes {
            ProgressView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if groupTypes.isEmpty {
            Text("No tradeable items in this group")
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            List(groupTypes, selection: Binding(
                get: { selectedTypeId },
                set: { id in
                    if let id, let result = groupTypes.first(where: { $0.typeId == id }) {
                        Task { await selectType(id, name: result.name) }
                    }
                }
            )) { result in
                typeRow(typeId: result.typeId, name: result.name)
                    .tag(result.typeId)
            }
            .listStyle(.sidebar)
        }
    }

    // MARK:  Item Detail View

    func itemDetailView(typeId: Int) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                itemHeader(typeId: typeId)

                if adjustedPrice != nil || !sellOrders.isEmpty || !buyOrders.isEmpty {
                    marketStatsBar
                }

                if #available(macOS 26.0, *), IntelligenceService.isSupported {
                    let regionName = availableRegions.first(where: { $0.id == selectedRegionId })?.name ?? "Unknown Region"
                    MarketAIInsightCard(
                        itemName: selectedTypeName,
                        regionName: regionName,
                        resetKey: insightResetKey,
                        sellOrders: sellOrders,
                        buyOrders: buyOrders,
                        priceHistory: priceHistory,
                        adjustedPrice: adjustedPrice,
                        averagePrice: averagePrice
                    )
                }

                HStack(spacing: 12) {
                    Picker("View", selection: $selectedOrderTab) {
                        Text("Sell Orders (\(sellOrders.count))").tag(0)
                        Text("Buy Orders (\(buyOrders.count))").tag(1)
                        Text("Price History").tag(2)
                    }
                    .pickerStyle(.segmented)
                    .frame(maxWidth: 500)

                    if let msg = waypointMessage {
                        HStack(spacing: 5) {
                            Image(systemName: msg.hasPrefix("Destination") || msg.hasPrefix("Waypoint")
                                  ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                                .foregroundStyle(msg.hasPrefix("Destination") || msg.hasPrefix("Waypoint")
                                                 ? .green : .orange)
                            Text(msg)
                        }
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .transition(.opacity)
                    }
                }

                if isLoadingOrders {
                    ProgressView("Loading market data...")
                        .frame(maxWidth: .infinity, minHeight: 200)
                } else if let error = ordersError {
                    Text("Error: \(error)")
                        .foregroundStyle(.red)
                        .frame(maxWidth: .infinity)
                } else {
                    switch selectedOrderTab {
                    case 0: ordersTable(orders: sellOrders, isBuy: false)
                    case 1: ordersTable(orders: buyOrders, isBuy: true)
                    case 2: priceHistoryView
                    default: EmptyView()
                    }
                }
            }
            .padding(20)
        }
    }

    // MARK:  Item Header

    func itemHeader(typeId: Int) -> some View {
        HStack(spacing: 16) {
            CachedAsyncImage(url: EVEImageURL.typeRender(typeId, size: 256)) { image in
                image.resizable()
            } placeholder: {
                CachedAsyncImage(url: EVEImageURL.typeIcon(typeId, size: 128)) { image in
                    image.resizable()
                } placeholder: {
                    RoundedRectangle(cornerRadius: 8).fill(.quaternary)
                }
            }
            .frame(width: 96, height: 96)
            .clipShape(RoundedRectangle(cornerRadius: 10))

            VStack(alignment: .leading, spacing: 4) {
                Text(selectedTypeName)
                    .font(.title2.bold())
                if let info = selectedTypeInfo {
                    HStack(spacing: 12) {
                        if let vol = info.volume {
                            Label(String(format: "%.2f m³", vol), systemImage: "cube")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        if let mass = info.mass {
                            Label(String(format: "%.0f kg", mass), systemImage: "scalemass")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    if let desc = info.description, !desc.isEmpty {
                        Text(desc.strippingEVEMarkup)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                // Own row, not squeezed against the buttons via a Spacer — the skill
                // pills need real width to show name+level, not just their icon.
                SkillRequirementsView(typeId: typeId, typeInfo: selectedTypeInfo, characterSkills: characterSkillMap)
                HStack(spacing: 8) {
                    if let info = selectedTypeInfo, CharacterFittingsView.eveShipGroupIds.contains(info.groupId) {
                        Button { showModelViewer = true } label: {
                            Label("View 3D", systemImage: "cube.transparent")
                        }
                        .buttonStyle(.bordered)
                    }

                    if let account = accountManager.selectedAccount, !account.isTokenExpired {
                        let token = account.accessToken
                        VStack(alignment: .leading, spacing: 4) {
                            Button {
                                Task { await openInEVE(typeId: typeId, token: token) }
                            } label: {
                                Label("Open in EVE", systemImage: "arrow.up.right.square")
                            }
                            .buttonStyle(.bordered)
                            if let msg = openInEVEMessage {
                                Text(msg)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }

            Spacer()
        }
        .padding()
        .background {
            ZStack {
                RoundedRectangle(cornerRadius: 12)
                    .fill(.regularMaterial)
                RadialGradient(
                    colors: [Color(red: 0.2, green: 0.75, blue: 0.8).opacity(0.14), .clear],
                    center: .init(x: 0.04, y: 0.5),
                    startRadius: 0,
                    endRadius: 180
                )
                .clipShape(RoundedRectangle(cornerRadius: 12))
            }
        }
    }

    // MARK:  Market Stats Bar

    var marketStatsBar: some View {
        HStack(spacing: 0) {
            if let adj = adjustedPrice {
                statCard("Adjusted", value: EVEFormatters.formatISKShort(adj), color: .blue)
                Divider()
            }
            if let avg = averagePrice {
                statCard("Avg Price", value: EVEFormatters.formatISKShort(avg), color: .purple)
                Divider()
            }
            if let bestSell = sellOrders.first?.order.price {
                statCard("Best Sell", value: EVEFormatters.formatISKShort(bestSell), color: .green)
                Divider()
            }
            if let bestBuy = buyOrders.first?.order.price {
                statCard("Best Buy", value: EVEFormatters.formatISKShort(bestBuy), color: .orange)
            }
            if let bestSell = sellOrders.first?.order.price,
               let bestBuy = buyOrders.first?.order.price,
               bestSell > 0 {
                Divider()
                let spread = ((bestSell - bestBuy) / bestSell) * 100
                statCard("Spread", value: (spread / 100).formatted(.percent.precision(.fractionLength(1))), color: .secondary)
            }
        }
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
    }

    func legendItem(color: Color, symbol: String, label: String) -> some View {
        HStack(spacing: 3) {
            Image(systemName: symbol)
                .foregroundStyle(color)
            Text(label)
        }
    }

    func statCard(_ title: String, value: String, color: Color) -> some View {
        VStack(spacing: 0) {
            Rectangle()
                .fill(color)
                .frame(height: 3)
            VStack(spacing: 4) {
                Text(title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(value)
                    .font(.subheadline.bold().monospacedDigit())
                    .foregroundStyle(color)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .padding(.horizontal, 8)
        }
        .frame(maxWidth: .infinity)
    }

}
