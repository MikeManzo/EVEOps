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

// MARK:  Type Image (render → icon fallback, with caching)

enum TypeImageCache {
    static let shared = NSCache<NSNumber, NSImage>()
}

struct TypeImage: View {
    let typeId: Int
    let size: CGFloat
    let cornerRadius: CGFloat

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
                    .frame(width: size, height: size)
            } else {
                RoundedRectangle(cornerRadius: cornerRadius).fill(.quaternary)
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
        .task(id: typeId) {
            if let cached = TypeImageCache.shared.object(forKey: NSNumber(value: typeId)) {
                image = cached
                return
            }
            image = nil
            failed = false
            if let loaded = await loadBestImage() {
                TypeImageCache.shared.setObject(loaded, forKey: NSNumber(value: typeId))
                image = loaded
            } else {
                failed = true
            }
        }
    }

    private func loadBestImage() async -> NSImage? {
        if let url = EVEImageURL.typeRender(typeId, size: 256),
           let img = await fetch(url) { return img }
        if let url = EVEImageURL.typeIcon(typeId, size: 64),
           let img = await fetch(url) { return img }
        return nil
    }

    private func fetch(_ url: URL) async -> NSImage? {
        guard let (data, response) = try? await URLSession.shared.data(from: url),
              (response as? HTTPURLResponse)?.statusCode == 200 else { return nil }
        return NSImage(data: data)
    }
}

// MARK:  Window Input

struct GalaxyMarketSearchInput: Codable, Hashable {
    var typeId: Int?
    var typeName: String
}

// MARK:  Private Types

struct GalaxyTypeResult: Identifiable {
    let typeId: Int
    let name: String
    var id: Int { typeId }
}

struct GalaxyOrder: Identifiable {
    let order: ESIRegionMarketOrder
    let isBuyOrder: Bool
    let regionName: String
    let systemName: String
    let locationName: String
    let securityStatus: Double
    var jumps: Int?
    var id: Int { order.orderId }
}

enum SortColumn {
    case price, qty, location, region, sec, jumps
}

enum OrderTypeFilter: String {
    case sell, buy, all

    var apiValue: String {
        switch self {
        case .sell: return "sell"
        case .buy:  return "buy"
        case .all:  return "all"
        }
    }
}

// MARK:  GalaxyMarketSearchView

struct GalaxyMarketSearchView: View {
    let initialTypeId: Int?
    let initialTypeName: String

    @Environment(AccountManager.self) var accountManager
    @Environment(DashboardPrefetcher.self) var prefetcher
    @Environment(\.dismiss) var dismiss

    // Item selection
    @State var itemSearchText = ""
    @State var itemSearchResults: [GalaxyTypeResult] = []
    @State var isSearchingItems = false
    @State var itemSearchTask: Task<Void, Never>?
    @State var selectedTypeId: Int?
    @State var selectedTypeName = ""
    @State var selectedTypeInfo: ESIType?

    // Persisted filter preferences
    @AppStorage("galaxySearch.highSecOnly") var highSecOnly = false
    @AppStorage("galaxySearch.maxJumps")    var maxJumps = 0
    @AppStorage("galaxySearch.secureRoute") var secureRoute = false
    @AppStorage("galaxySearch.orderType")   var orderTypeFilter: OrderTypeFilter = .sell

    // Galaxy search state
    @State var orders: [GalaxyOrder] = []
    @State var isSearching = false
    @State var isComputingJumps = false
    @State var regionsSearched = 0
    @State var totalRegions = 0
    @State var searchError: String?
    @State var galaxyTask: Task<Void, Never>?

    // Jump routing
    @State var characterSystemId: Int?
    @State var jumpCache: [Int: Int] = [:]

    // Sorting
    @State var sortColumn: SortColumn = .price
    @State var sortAscending = true

    // Autopilot feedback
    @State var waypointMessage: String?

    var hasLocation: Bool { characterSystemId != nil }
    var canSearch: Bool { selectedTypeId != nil }
    var characterSkillMap: [Int: Int]? {
        guard let account = accountManager.selectedAccount else { return nil }
        // Access characterData directly (no 2-min freshness check) — a market session can
        // run longer than that window. This is safe because BackgroundMonitor refreshes
        // characterData on the user's configured poll interval, so staleness here is bounded
        // by that interval rather than by how long the view has been open.
        return prefetcher.characterData[account.characterID]
            .map { Dictionary(uniqueKeysWithValues: $0.skills.skills.map { ($0.skillId, $0.activeSkillLevel) }) }
    }

    var filteredOrders: [GalaxyOrder] {
        switch orderTypeFilter {
        case .sell: return orders.filter { !$0.isBuyOrder }
        case .buy:  return orders.filter {  $0.isBuyOrder }
        case .all:  return orders
        }
    }

    var sortedOrders: [GalaxyOrder] {
        filteredOrders.sorted { a, b in
            let asc = sortAscending
            switch sortColumn {
            case .price:    return asc ? a.order.price < b.order.price : a.order.price > b.order.price
            case .qty:      return asc ? a.order.volumeRemain < b.order.volumeRemain : a.order.volumeRemain > b.order.volumeRemain
            case .location: return asc ? a.locationName < b.locationName : a.locationName > b.locationName
            case .region:   return asc ? a.regionName < b.regionName : a.regionName > b.regionName
            case .sec:      return asc ? a.securityStatus < b.securityStatus : a.securityStatus > b.securityStatus
            case .jumps:
                let aj = a.jumps ?? Int.max
                let bj = b.jumps ?? Int.max
                return asc ? aj < bj : aj > bj
            }
        }
    }

    var sellCount: Int { orders.filter { !$0.isBuyOrder }.count }
    var buyCount:  Int { orders.filter {  $0.isBuyOrder }.count }

    func toggleSort(_ column: SortColumn) {
        if sortColumn == column {
            sortAscending.toggle()
        } else {
            sortColumn = column
            sortAscending = true
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            headerPanel
            Divider()
            contentArea
        }
        .frame(minWidth: 900, idealWidth: 1100, minHeight: 580)
        .onAppear {
            if let id = initialTypeId, !initialTypeName.isEmpty {
                selectedTypeId = id
                selectedTypeName = initialTypeName
                itemSearchText = initialTypeName
                Task {
                    async let search: Void = performGalaxySearch()
                    async let info = UniverseCache.shared.type(id: id)
                    await search
                    selectedTypeInfo = await info
                }
            }
            loadCharacterLocation()
        }
        .task {
            // Always fetch a fresh location on appear — the prefetcher value may be
            // stale if the character has moved since the last background refresh.
            await fetchCurrentLocation()
        }
        .onChange(of: prefetcher.lastRefresh) { _, _ in
            loadCharacterLocation()
        }
        .onChange(of: orderTypeFilter) { _, newType in
            // Auto-flip price sort direction to the natural default for each type
            guard sortColumn == .price else { return }
            sortAscending = newType != .buy
        }
    }

}
