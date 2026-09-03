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

// MARK:  MarketBrowserView

struct MarketBrowserView: View {
    @Environment(AccountManager.self) var accountManager
    @Environment(DashboardPrefetcher.self) var prefetcher

    // Region
    @AppStorage("market.selectedRegionId") var selectedRegionId: Int = 10000002
    @State var availableRegions: [(id: Int, name: String, factionId: Int?)] = []

    // Market group tree
    @State var fetchedGroups: [Int: ESIMarketGroup] = [:]
    @State var isLoadingGroups = false
    @State var rootNodes: [MarketGroupNode] = []
    @State var selectedGroupId: Int?
    @State var groupTypes: [MarketTypeResult] = []
    @State var isLoadingGroupTypes = false

    // Search
    @State var searchText = ""
    @State var searchResults: [MarketTypeResult] = []
    @State var isSearching = false
    @State var searchTask: Task<Void, Never>?

    // Last-viewed item, remembered only for the current app session so navigating
    // away from the Market tab and back restores it. Deliberately NOT @AppStorage:
    // persisting across launches made stale / no-longer-relevant items reappear on
    // a fresh start, and spurious List-selection writes made the remembered item
    // effectively random from run to run.
    static var sessionTypeId:   Int    = 0
    static var sessionTypeName: String = ""

    // Selected item
    @State var selectedTypeId: Int?
    @State var selectedTypeName = ""
    @State var selectedTypeInfo: ESIType?

    // Orders
    @State var sellOrders: [ResolvedOrder] = []
    @State var buyOrders: [ResolvedOrder] = []
    @State var isLoadingOrders = false
    @State var ordersError: String?

    // Price history
    @State var priceHistory: [ESIMarketHistory] = []
    @State var adjustedPrice: Double?
    @State var averagePrice: Double?
    @State var marketPrices: [Int: ESIMarketPrice] = [:]

    // Jump cache
    @State var characterSystemId: Int?
    @State var jumpCache: [Int: Int] = [:]
    @State var regionManuallyOverridden = false

    // UI state
    @State var selectedOrderTab = 0   // 0 = sell, 1 = buy, 2 = history
    @State var historyDays = 90
    @State var openInEVEMessage: String?
    @State var waypointMessage: String?
    @State var insightResetKey = ""
    @State var hoveredHistoryDate: Date?
    @State var showModelViewer = false

    // Order sort state (sell defaults: price asc; buy defaults: price desc)
    @State var sellSortKey: OrderSortKey = .price
    @State var sellSortAsc = true
    @State var buySortKey:  OrderSortKey = .price
    @State var buySortAsc  = false

    // Persisted pane sizes — written only on drag end to avoid UserDefaults
    // writes at 60 Hz, which would cause re-render jitter during dragging.
    @AppStorage("market.leftPaneWidth")    var savedLeftWidth:    Double = 240
    @AppStorage("market.detailPaneHeight") var savedDetailHeight: Double = 300

    // Live pixel values updated on every drag event (fast @State, no I/O).
    // Initialised directly from UserDefaults so the correct size is shown
    // on the very first frame, with no .onAppear flash.
    @State var leftWidth: CGFloat = {
        let v = UserDefaults.standard.double(forKey: "market.leftPaneWidth")
        return CGFloat(v > 0 ? v : 240)
    }()
    @State var detailHeight: CGFloat = {
        let v = UserDefaults.standard.double(forKey: "market.detailPaneHeight")
        return CGFloat(v > 0 ? v : 300)
    }()

    var body: some View {
        VStack(spacing: 0) {
            // ── Inline action bar ─────────────────────────────────────
            HStack(spacing: 8) {
                Spacer()
                Button {
                    WindowService.shared.showGalaxySearch(typeId: selectedTypeId, typeName: selectedTypeName)
                } label: {
                    Label("Galaxy Search", systemImage: "globe.europe.africa.fill")
                }
                .buttonStyle(.bordered)
                .help("Search cheapest sell orders across all k-space regions")
                Button {
                    WindowService.shared.showTradeHubComparison(typeId: selectedTypeId, typeName: selectedTypeName)
                } label: {
                    Label("Trade Hubs", systemImage: "building.2.fill")
                }
                .buttonStyle(.bordered)
                .help("Compare best sell and buy prices at Jita, Amarr, Dodixie, Rens, and Hek")
                Menu {
                    ForEach(availableRegions, id: \.id) { region in
                        Button {
                            selectedRegionId = region.id
                            onRegionChanged()
                        } label: {
                            Text("\(regionEmoji(region.id))  \(region.name)")
                        }
                    }
                } label: {
                    let current = availableRegions.first(where: { $0.id == selectedRegionId })
                    HStack(spacing: 5) {
                        Circle()
                            .fill(regionColor(current?.id ?? selectedRegionId))
                            .frame(width: 8, height: 8)
                        Text(current?.name ?? "Region")
                        Image(systemName: "chevron.up.chevron.down")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                .disabled(availableRegions.isEmpty)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(.bar)
            Divider()
            // ── Top row ───────────────────────────────────────────────
            HStack(spacing: 0) {
                leftPane
                    .frame(width: leftWidth)

                SplitDivider(direction: .horizontal,
                            value: leftWidth, minValue: 160, maxValue: 440,
                            onChange: { leftWidth = $0 },
                            onEnd: { savedLeftWidth = Double(leftWidth) })

                rightPane
                    .frame(maxWidth: .infinity)
            }
            .frame(maxHeight: .infinity)  // fills space above detail pane

            // ── Vertical resize handle ────────────────────────────────
            SplitDivider(direction: .vertical,
                         value: detailHeight, minValue: 160, maxValue: 640,
                         onChange: { detailHeight = $0 },
                         onEnd: { savedDetailHeight = Double(detailHeight) })

            // ── Detail pane (full width) ──────────────────────────────
            detailPane
                .frame(height: detailHeight)
        }
        .safeAreaInset(edge: .top, spacing: 0) {
            HStack {
                Text("Market Browser")
                    .font(.largeTitle.bold())
                Spacer()
            }
            .padding(.horizontal, 16)
//            .padding(.vertical, 12)
            .background(.background)
        }
        .navigationTitle("")
        .task { await loadInitialData() }
        .onChange(of: prefetcher.lastRefresh) { _, _ in
            // Prefetch completed after the view loaded — pick up the fresh location
            // and patch jump counts into any orders that are already on screen.
            guard let account = accountManager.selectedAccount,
                  let data = prefetcher.data(for: account.characterID) else { return }
            let wasNil = characterSystemId == nil
            characterSystemId = data.location.solarSystemId
            if wasNil && (!sellOrders.isEmpty || !buyOrders.isEmpty) {
                Task { await recalculateJumps() }
            }
        }
        .sheet(isPresented: $showModelViewer) {
            ShipModelSheet(shipName: selectedTypeName)
        }
    }

}
