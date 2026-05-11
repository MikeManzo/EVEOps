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

private enum TypeImageCache {
    static let shared = NSCache<NSNumber, NSImage>()
}

private struct TypeImage: View {
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

private struct GalaxyTypeResult: Identifiable {
    let typeId: Int
    let name: String
    var id: Int { typeId }
}

private struct GalaxyOrder: Identifiable {
    let order: ESIRegionMarketOrder
    let isBuyOrder: Bool
    let regionName: String
    let systemName: String
    let locationName: String
    let securityStatus: Double
    var jumps: Int?
    var id: Int { order.orderId }
}

private enum SortColumn {
    case price, qty, location, region, sec, jumps
}

private enum OrderTypeFilter: String {
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

    @Environment(AccountManager.self) private var accountManager
    @Environment(DashboardPrefetcher.self) private var prefetcher
    @Environment(\.dismiss) private var dismiss

    // Item selection
    @State private var itemSearchText = ""
    @State private var itemSearchResults: [GalaxyTypeResult] = []
    @State private var isSearchingItems = false
    @State private var itemSearchTask: Task<Void, Never>?
    @State private var selectedTypeId: Int?
    @State private var selectedTypeName = ""

    // Persisted filter preferences
    @AppStorage("galaxySearch.highSecOnly") private var highSecOnly = false
    @AppStorage("galaxySearch.maxJumps")    private var maxJumps = 0
    @AppStorage("galaxySearch.secureRoute") private var secureRoute = false
    @AppStorage("galaxySearch.orderType")   private var orderTypeFilter: OrderTypeFilter = .sell

    // Galaxy search state
    @State private var orders: [GalaxyOrder] = []
    @State private var isSearching = false
    @State private var isComputingJumps = false
    @State private var regionsSearched = 0
    @State private var totalRegions = 0
    @State private var searchError: String?
    @State private var galaxyTask: Task<Void, Never>?

    // Jump routing
    @State private var characterSystemId: Int?
    @State private var jumpCache: [Int: Int] = [:]

    // Sorting
    @State private var sortColumn: SortColumn = .price
    @State private var sortAscending = true

    // Autopilot feedback
    @State private var waypointMessage: String?

    private var hasLocation: Bool { characterSystemId != nil }
    private var canSearch: Bool { selectedTypeId != nil && !isSearching }

    private var filteredOrders: [GalaxyOrder] {
        switch orderTypeFilter {
        case .sell: return orders.filter { !$0.isBuyOrder }
        case .buy:  return orders.filter {  $0.isBuyOrder }
        case .all:  return orders
        }
    }

    private var sortedOrders: [GalaxyOrder] {
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

    private var sellCount: Int { orders.filter { !$0.isBuyOrder }.count }
    private var buyCount:  Int { orders.filter {  $0.isBuyOrder }.count }

    private func toggleSort(_ column: SortColumn) {
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
                Task { await performGalaxySearch() }
            }
            loadCharacterLocation()
        }
        .task {
            // Fallback: if prefetcher had stale/missing data, fetch location directly
            if characterSystemId == nil {
                await fetchLocationFallback()
            }
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

    // MARK:  Header Panel

    private var headerPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("Galaxy Market Search", systemImage: "globe.europe.africa.fill")
                    .font(.title3.bold())
                Spacer()
                Button("Done") { dismiss() }
                    .keyboardShortcut(.escape)
            }

            // Item search + order type + search button
            HStack(spacing: 10) {
                if let typeId = selectedTypeId {
                    TypeImage(typeId: typeId, size: 28, cornerRadius: 4)
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
                        Button { clearItemSelection() } label: {
                            Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(7)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
                .frame(maxWidth: 320)

                // Order type picker
                Picker("Order Type", selection: $orderTypeFilter) {
                    Text("Sell").tag(OrderTypeFilter.sell)
                    Text("Buy").tag(OrderTypeFilter.buy)
                    Text("Both").tag(OrderTypeFilter.all)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: 160)
                .help("Choose which order types to search for")

                Button {
                    Task { await performGalaxySearch() }
                } label: {
                    Label("Search Galaxy", systemImage: "magnifyingglass.circle.fill")
                }
                .buttonStyle(.borderedProminent)
                .disabled(!canSearch)
                .help(selectedTypeId == nil ? "Select an item first" : "Search all k-space regions")
            }

            // Filters row
            HStack(spacing: 20) {
                Toggle("High-sec stations only", isOn: $highSecOnly)
                    .toggleStyle(.checkbox)
                    .help("Only show orders in systems with security status ≥ 0.5")

                if hasLocation {
                    Divider().frame(height: 16)

                    HStack(spacing: 6) {
                        Text("Max jumps:")
                            .foregroundStyle(.secondary)
                        Stepper(value: $maxJumps, in: 0...100, step: 5) {
                            Text(maxJumps == 0 ? "Unlimited" : "\(maxJumps)")
                                .font(.subheadline.bold().monospacedDigit())
                                .frame(minWidth: 60, alignment: .leading)
                        }
                    }

                    if maxJumps > 0 {
                        Divider().frame(height: 16)
                        Toggle("High-sec route", isOn: $secureRoute)
                            .toggleStyle(.checkbox)
                            .help("Measure distance only through high-sec systems")
                    }
                } else {
                    Text("Log in a character to enable jump-distance filtering")
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundStyle(.orange)
                }

                Spacer()

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
                } else if isComputingJumps {
                    HStack(spacing: 6) {
                        ProgressView().controlSize(.mini)
                        Text("Computing jump distances…")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                } else if !orders.isEmpty {
                    orderCountSummary
                }
            }
            .font(.subheadline)
        }
        .padding(16)
        .fixedSize(horizontal: false, vertical: true)
    }

    private var orderCountSummary: some View {
        HStack(spacing: 8) {
            if sellCount > 0 {
                HStack(spacing: 4) {
                    Circle().fill(Color.green).frame(width: 6, height: 6)
                    Text("\(sellCount) sell")
                }
            }
            if buyCount > 0 {
                HStack(spacing: 4) {
                    Circle().fill(Color.orange).frame(width: 6, height: 6)
                    Text("\(buyCount) buy")
                }
            }
            Text("across \(regionsSearched) region\(regionsSearched == 1 ? "" : "s")")
        }
        .font(.caption)
        .foregroundStyle(.secondary)
    }

    // MARK:  Content Area

    @ViewBuilder
    private var contentArea: some View {
        if isSearching {
            searchingView
        } else if !itemSearchResults.isEmpty && selectedTypeId == nil {
            itemSearchList
        } else if !orders.isEmpty {
            resultsTable
        } else {
            emptyStateView
        }
    }

    // MARK:  Item Search List

    private var itemSearchList: some View {
        List(itemSearchResults, id: \.id) { result in
            Button {
                selectedTypeId = result.typeId
                selectedTypeName = result.name
                itemSearchText = result.name
                itemSearchResults = []
            } label: {
                HStack(spacing: 14) {
                    TypeImage(typeId: result.typeId, size: 48, cornerRadius: 6)
                    Text(result.name).font(.title3)
                    Spacer()
                }
                .padding(.vertical, 4)
            }
            .buttonStyle(.plain)
        }
        .listStyle(.plain)
    }

    // MARK:  Searching Progress

    private var searchingView: some View {
        VStack(spacing: 16) {
            if totalRegions > 0 {
                ProgressView(value: Double(regionsSearched), total: Double(totalRegions))
                    .progressViewStyle(.linear)
                    .frame(maxWidth: 420)
            } else {
                ProgressView()
                    .progressViewStyle(.linear)
                    .frame(maxWidth: 420)
            }

            Text(totalRegions > 0
                 ? "Searching region \(regionsSearched) of \(totalRegions)…"
                 : "Loading region list…")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Button("Cancel") {
                galaxyTask?.cancel()
                isSearching = false
            }
            .buttonStyle(.bordered)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK:  Results Table

    private var resultsTable: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                // Type indicator column — only shown when displaying both order types
                if orderTypeFilter == .all {
                    Text("Type")
                        .frame(width: 40, alignment: .center)
                }
                columnHeader("Price", column: .price, alignment: .trailing)
                    .frame(width: 130)
                columnHeader("Qty", column: .qty, alignment: .trailing)
                    .frame(width: 60)
                    .padding(.leading, 10)
                columnHeader("Station / System", column: .location, alignment: .leading)
                    .frame(maxWidth: .infinity)
                    .padding(.leading, 10)
                columnHeader("Region", column: .region, alignment: .leading)
                    .frame(width: 96)
                    .padding(.leading, 8)
                columnHeader("Sec", column: .sec, alignment: .center)
                    .frame(width: 36)
                if hasLocation {
                    columnHeader("Jumps", column: .jumps, alignment: .center)
                        .frame(width: 60)
                        .padding(.trailing, 4)
                }
            }
            .font(.subheadline.bold())
            .foregroundStyle(.secondary)
            .padding(.leading, 19)  // 16 base + 3 to align with data rows (which have a 3pt accent bar before their 16pt inner padding)
            .padding(.trailing, 16)
            .padding(.vertical, 6)
            .background(Color(NSColor.separatorColor).opacity(0.15))

            Divider()

            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(Array(sortedOrders.enumerated()), id: \.element.id) { index, order in
                        orderRow(order, isEven: index % 2 == 0)
                            .contextMenu {
                                let destId = order.order.locationId
                                let name = order.locationName
                                Button {
                                    Task { await setWaypoint(destinationId: destId, clear: true) }
                                } label: {
                                    Label("Set Destination: \(name)", systemImage: "location.fill")
                                }
                                Button {
                                    Task { await setWaypoint(destinationId: destId, clear: false) }
                                } label: {
                                    Label("Add Waypoint: \(name)", systemImage: "plus.circle")
                                }
                            }
                        Divider().padding(.leading, 16)
                    }
                }
            }
        }
    }

    private func columnHeader(_ title: String, column: SortColumn, alignment: Alignment) -> some View {
        Button { toggleSort(column) } label: {
            HStack(spacing: 3) {
                if alignment == .trailing { Spacer() }
                Text(title)
                    .lineLimit(1)
                    .foregroundStyle(sortColumn == column ? .primary : .secondary)
                if sortColumn == column {
                    Image(systemName: sortAscending ? "chevron.up" : "chevron.down")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(.secondary)
                }
                if alignment == .leading || alignment == .center { Spacer() }
            }
        }
        .buttonStyle(.plain)
        .help("Sort by \(title)")
    }

    private func orderRow(_ resolved: GalaxyOrder, isEven: Bool) -> some View {
        let order = resolved.order
        let sec = resolved.securityStatus
        let accentColor: Color = resolved.isBuyOrder ? .orange : .green

        return HStack(spacing: 0) {
            Rectangle()
                .fill(accentColor.opacity(0.75))
                .frame(width: 3)

            HStack(spacing: 0) {
                // Type badge — only when showing both
                if orderTypeFilter == .all {
                    Text(resolved.isBuyOrder ? "Buy" : "Sell")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(accentColor, in: Capsule())
                        .frame(width: 40, alignment: .center)
                }

                Text(EVEFormatters.formatISK(order.price))
                    .font(.subheadline.monospacedDigit().bold())
                    .foregroundStyle(accentColor)
                    .frame(width: 130, alignment: .trailing)

                Text(formatCount(order.volumeRemain))
                    .font(.callout.monospacedDigit())
                    .frame(width: 60, alignment: .trailing)
                    .padding(.leading, 10)

                VStack(alignment: .leading, spacing: 2) {
                    Text(resolved.locationName)
                        .font(.callout)
                        .lineLimit(1)
                    HStack(spacing: 4) {
                        Text(resolved.systemName)
                        if resolved.isBuyOrder {
                            Text("·")
                            Text(formatRange(order.range))
                        }
                    }
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.leading, 10)

                Text(resolved.regionName)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .frame(width: 96, alignment: .leading)
                    .padding(.leading, 8)

                Text(String(format: "%.1f", max(0, sec)))
                    .font(.system(size: 9, weight: .bold).monospacedDigit())
                    .foregroundStyle(.white)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(securityColor(sec), in: Capsule())
                    .frame(width: 36, alignment: .center)

                if hasLocation {
                    jumpBadge(jumps: resolved.jumps)
                        .frame(width: 52, alignment: .center)
                        .padding(.trailing, 4)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 9)
        }
        .background(isEven ? Color.primary.opacity(0.03) : Color.clear)
    }

    @ViewBuilder
    private func jumpBadge(jumps: Int?) -> some View {
        if let jumps {
            HStack(spacing: 3) {
                Circle()
                    .fill(jumps == 0 ? Color.green : jumps <= 5 ? Color.yellow : Color.orange)
                    .frame(width: 5, height: 5)
                Text(jumps == 0 ? "Here" : "\(jumps)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(jumps == 0 ? .green : jumps <= 5 ? .primary : .secondary)
            }
        } else if isComputingJumps {
            ProgressView()
                .scaleEffect(0.55)
                .frame(width: 16, height: 16)
        } else {
            Text("—")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
    }

    // MARK:  Empty State

    @ViewBuilder
    private var emptyStateView: some View {
        if let error = searchError {
            VStack(spacing: 12) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 36))
                    .foregroundStyle(.orange)
                Text("Search Failed")
                    .font(.headline)
                Text(error)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 400)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            VStack(spacing: 14) {
                Image(systemName: "globe.europe.africa.fill")
                    .font(.system(size: 48))
                    .foregroundStyle(Color(red: 0.2, green: 0.75, blue: 0.8).opacity(0.5))
                Text("Galaxy Market Search")
                    .font(.title3.bold())
                    .foregroundStyle(.secondary)
                VStack(spacing: 4) {
                    Text("Search sell orders, buy orders, or both across all k-space regions.")
                    Text("Filter by high-sec stations and jump distance from your location.")
                }
                .font(.subheadline)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    // MARK:  Item Search Logic

    private func onItemSearchChanged(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        if trimmed == selectedTypeName, selectedTypeId != nil { return }
        if selectedTypeId != nil {
            selectedTypeId = nil
            selectedTypeName = ""
        }
        itemSearchTask?.cancel()
        guard trimmed.count >= 3 else {
            itemSearchResults = []
            isSearchingItems = false
            return
        }
        isSearchingItems = true
        itemSearchTask = Task {
            try? await Task.sleep(for: .milliseconds(400))
            guard !Task.isCancelled else { return }
            await searchItems(trimmed)
        }
    }

    private func clearItemSelection() {
        selectedTypeId = nil
        selectedTypeName = ""
        itemSearchText = ""
        itemSearchResults = []
        orders = []
        searchError = nil
    }

    private func searchItems(_ query: String) async {
        struct SearchResp: Decodable { let inventoryType: [Int]? }
        struct NameEntry: Decodable { let id: Int; let name: String }

        if let account = accountManager.selectedAccount,
           let token = try? await accountManager.validToken(for: account) {
            // Authenticated prefix search — works with 3+ chars
            let resp: SearchResp? = try? await ESIClient.shared.fetch(
                "/characters/\(account.characterID)/search/",
                token: token,
                queryItems: [
                    URLQueryItem(name: "categories", value: "inventory_type"),
                    URLQueryItem(name: "search",     value: query),
                    URLQueryItem(name: "strict",     value: "false")
                ]
            )
            // Take up to 100 IDs so relevant items (e.g. the base ship) aren't
            // truncated before names are resolved — ESI returns them in arbitrary order.
            let ids = Array((resp?.inventoryType ?? []).prefix(100))
            guard !ids.isEmpty else {
                isSearchingItems = false
                itemSearchResults = []
                return
            }
            let names: [NameEntry] = (try? await ESIClient.shared.post("/universe/names/", body: ids)) ?? []
            isSearchingItems = false
            let lower = query.lowercased()
            itemSearchResults = names
                .map { GalaxyTypeResult(typeId: $0.id, name: $0.name) }
                .sorted { a, b in
                    let aL = a.name.lowercased(), bL = b.name.lowercased()
                    let aExact = aL == lower,  bExact = bL == lower
                    if aExact != bExact { return aExact }
                    let aPrefix = aL.hasPrefix(lower), bPrefix = bL.hasPrefix(lower)
                    if aPrefix != bPrefix { return aPrefix }
                    return aL < bL
                }
        } else {
            // Fallback for unauthenticated: exact name match only
            struct IDResp: Decodable { let inventoryTypes: [ESIIDName]? }
            let resp: IDResp? = try? await ESIClient.shared.post("/universe/ids/", body: [query])
            isSearchingItems = false
            itemSearchResults = (resp?.inventoryTypes ?? [])
                .map { GalaxyTypeResult(typeId: $0.id, name: $0.name) }
                .sorted { $0.name < $1.name }
        }
    }

    // MARK:  Galaxy Search Logic

    private func performGalaxySearch() async {
        guard let typeId = selectedTypeId else { return }
        galaxyTask?.cancel()
        isSearching = true
        isComputingJumps = false
        searchError = nil
        orders = []
        regionsSearched = 0
        // Set natural sort direction for the selected order type
        if sortColumn == .price {
            sortAscending = orderTypeFilter != .buy
        }

        galaxyTask = Task { await runGalaxySearch(typeId: typeId) }
    }

    private func runGalaxySearch(typeId: Int) async {
        let regions = await UniverseCache.shared.knownSpaceRegions()
        totalRegions = regions.count

        // Always fetch "all" from ESI — filter locally so switching the picker
        // doesn't require a second network pass.
        let allPairs: [(regionId: Int, order: ESIRegionMarketOrder)] =
            await withTaskGroup(of: [(Int, ESIRegionMarketOrder)].self) { group in
                for region in regions {
                    let rid = region.id
                    group.addTask {
                        let fetched: [ESIRegionMarketOrder] = (try? await ESIClient.shared.fetch(
                            "/markets/\(rid)/orders/",
                            queryItems: [
                                URLQueryItem(name: "type_id", value: "\(typeId)"),
                                URLQueryItem(name: "order_type", value: "all")
                            ]
                        )) ?? []
                        return fetched.map { (rid, $0) }
                    }
                }
                var out: [(Int, ESIRegionMarketOrder)] = []
                for await chunk in group {
                    out.append(contentsOf: chunk)
                    regionsSearched += 1
                }
                return out
            }

        guard !Task.isCancelled else {
            isSearching = false
            return
        }

        // Sort: sell orders cheapest first, buy orders highest first
        let sorted = allPairs.sorted {
            if $0.order.isBuyOrder != $1.order.isBuyOrder {
                return !$0.order.isBuyOrder  // sell before buy in combined view
            }
            return $0.order.isBuyOrder
                ? $0.order.price > $1.order.price   // highest buy first
                : $0.order.price < $1.order.price   // lowest sell first
        }

        // Resolve system security/name for every unique system
        let uniqueSystemIds = Set(sorted.map { $0.order.systemId })
        var systemData: [Int: (name: String, sec: Double)] = [:]
        await withTaskGroup(of: (Int, ESISolarSystem?).self) { group in
            for sysId in uniqueSystemIds {
                group.addTask { (sysId, await UniverseCache.shared.solarSystem(id: sysId)) }
            }
            for await (id, sys) in group {
                if let sys { systemData[id] = (sys.name, sys.securityStatus) }
            }
        }

        // Apply high-sec filter
        let secFiltered = highSecOnly
            ? sorted.filter { (systemData[$0.order.systemId]?.sec ?? 0) >= 0.45 }
            : sorted

        // Cap to top 200 sell + top 200 buy to bound downstream work
        let topSell = Array(secFiltered.filter { !$0.order.isBuyOrder }.prefix(200))
        let topBuy  = Array(secFiltered.filter {  $0.order.isBuyOrder }.prefix(200))
        let topPairs = topSell + topBuy

        // Resolve station / structure names
        let token = accountManager.selectedAccount.flatMap {
            !$0.isTokenExpired ? $0.accessToken : nil
        }
        let uniqueLocations = Set(topPairs.map { $0.order.locationId })
        var locationNames: [Int: String] = [:]
        await withTaskGroup(of: (Int, String?).self) { group in
            for locId in uniqueLocations {
                group.addTask {
                    if locId < 1_000_000_000 {
                        return (locId, await UniverseCache.shared.station(id: locId)?.name)
                    } else if let token {
                        let s: ESIStructure? = try? await ESIClient.shared.fetch(
                            "/universe/structures/\(locId)/", token: token
                        )
                        return (locId, s?.name ?? "Player Structure")
                    } else {
                        return (locId, "Player Structure")
                    }
                }
            }
            for await (id, name) in group {
                if let name { locationNames[id] = name }
            }
        }

        let regionNames = Dictionary(uniqueKeysWithValues: regions.map { ($0.id, $0.name) })

        let initialOrders: [GalaxyOrder] = topPairs.map { (regionId, order) in
            let sys = systemData[order.systemId]
            return GalaxyOrder(
                order: order,
                isBuyOrder: order.isBuyOrder,
                regionName: regionNames[regionId] ?? "Unknown",
                systemName: sys?.name ?? "Unknown",
                locationName: locationNames[order.locationId] ?? "Unknown Location",
                securityStatus: sys?.sec ?? 0.0,
                jumps: nil
            )
        }
        orders = initialOrders
        isSearching = false

        guard let originId = characterSystemId else { return }

        isComputingJumps = true
        let uniqueDestSystems = Array(Set(topPairs.map { $0.order.systemId }))
        let routeFlag = secureRoute ? "secure" : "shortest"
        var newCache = jumpCache

        var toFetch: [Int] = []
        for destId in uniqueDestSystems {
            if destId == originId {
                newCache[destId] = 0
            } else if newCache[destId] == nil {
                toFetch.append(destId)
            }
        }

        let jumpResults = await withTaskGroup(of: (Int, Int?).self) { group in
            for destId in toFetch {
                group.addTask {
                    let route: [Int]? = try? await ESIClient.shared.fetch(
                        "/route/\(originId)/\(destId)/",
                        queryItems: [URLQueryItem(name: "flag", value: routeFlag)]
                    )
                    return (destId, route.map { max(0, $0.count - 1) })
                }
            }
            var out: [(Int, Int?)] = []
            for await r in group { out.append(r) }
            return out
        }
        for (sysId, j) in jumpResults { if let j { newCache[sysId] = j } }
        jumpCache = newCache

        var withJumps: [GalaxyOrder] = initialOrders.map { order in
            var updated = order
            updated.jumps = newCache[order.order.systemId]
            return updated
        }
        if maxJumps > 0 {
            withJumps = withJumps.filter { ($0.jumps ?? Int.max) <= maxJumps }
        }
        orders = withJumps
        isComputingJumps = false
    }

    // MARK:  Location Helpers

    private func loadCharacterLocation() {
        if let account = accountManager.selectedAccount,
           let data = prefetcher.data(for: account.characterID) {
            characterSystemId = data.location.solarSystemId
        }
    }

    private func fetchLocationFallback() async {
        guard characterSystemId == nil,
              let account = accountManager.selectedAccount,
              let token = try? await accountManager.validToken(for: account) else { return }
        let loc: ESICharacterLocation? = try? await ESIClient.shared.fetch(
            "/characters/\(account.characterID)/location/", token: token
        )
        if let sysId = loc?.solarSystemId {
            characterSystemId = sysId
        }
    }

    // MARK:  Autopilot

    private func setWaypoint(destinationId: Int, clear: Bool) async {
        guard let account = accountManager.selectedAccount else {
            waypointMessage = "No character logged in."
            return
        }
        waypointMessage = nil
        do {
            let token = try await accountManager.validToken(for: account)
            try await ESIClient.shared.postAction(
                "/ui/autopilot/waypoint/",
                token: token,
                queryItems: [
                    URLQueryItem(name: "add_to_beginning", value: "false"),
                    URLQueryItem(name: "clear_other_waypoints", value: clear ? "true" : "false"),
                    URLQueryItem(name: "destination_id", value: "\(destinationId)")
                ]
            )
            waypointMessage = clear ? "Destination set in EVE client." : "Waypoint added in EVE client."
        } catch ESIError.unauthorized {
            waypointMessage = "Requires esi-ui.write_waypoint.v1 scope — re-add your character to grant autopilot access."
        } catch {
            waypointMessage = error.localizedDescription
        }
    }

    // MARK:  Helpers

    private func securityColor(_ sec: Double) -> Color {
        switch sec {
        case 0.45...: return .green
        case 0.0..<0.45: return .orange
        default: return .red
        }
    }

    private func formatCount(_ value: Int) -> String {
        switch value {
        case 1_000_000_000...: return String(format: "%.1fB", Double(value) / 1_000_000_000)
        case 1_000_000...:     return String(format: "%.1fM", Double(value) / 1_000_000)
        case 10_000...:        return String(format: "%.1fK", Double(value) / 1_000)
        default:               return "\(value)"
        }
    }

    private func formatRange(_ range: String) -> String {
        switch range {
        case "station":     return "Station"
        case "solarsystem": return "System"
        case "region":      return "Region"
        case "1":           return "1 jump"
        case "2":           return "2 jumps"
        case "3":           return "3 jumps"
        case "4":           return "4 jumps"
        case "5":           return "5 jumps"
        case "10":          return "10 jumps"
        case "20":          return "20 jumps"
        case "30":          return "30 jumps"
        case "40":          return "40 jumps"
        default:            return range
        }
    }
}
