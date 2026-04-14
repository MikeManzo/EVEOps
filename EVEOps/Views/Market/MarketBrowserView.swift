import SwiftUI
import Charts

// MARK: - Supporting Types

private struct MarketGroupNode: Identifiable {
    let group: ESIMarketGroup
    var children: [MarketGroupNode]?
    var id: Int { group.marketGroupId }
}

private struct MarketTypeResult: Identifiable {
    let typeId: Int
    let name: String
    var id: Int { typeId }
}

private struct ResolvedOrder: Identifiable {
    let order: ESIRegionMarketOrder
    var locationName: String
    var systemName: String
    var securityStatus: Double
    var jumps: Int?
    var id: Int { order.orderId }
}

// MARK: - MarketBrowserView

struct MarketBrowserView: View {
    @Environment(AccountManager.self) private var accountManager
    @Environment(DashboardPrefetcher.self) private var prefetcher

    // Region
    @State private var selectedRegionId: Int = 10000002   // The Forge (Jita)
    @State private var availableRegions: [(id: Int, name: String)] = []

    // Market group tree
    @State private var allGroupIds: [Int] = []
    @State private var fetchedGroups: [Int: ESIMarketGroup] = [:]
    @State private var isLoadingGroups = false
    @State private var rootNodes: [MarketGroupNode] = []
    @State private var selectedGroupId: Int?
    @State private var groupTypes: [MarketTypeResult] = []
    @State private var isLoadingGroupTypes = false

    // Search
    @State private var searchText = ""
    @State private var searchResults: [MarketTypeResult] = []
    @State private var isSearching = false
    @State private var searchTask: Task<Void, Never>?

    // Selected item
    @State private var selectedTypeId: Int?
    @State private var selectedTypeName = ""
    @State private var selectedTypeInfo: ESIType?

    // Orders
    @State private var sellOrders: [ResolvedOrder] = []
    @State private var buyOrders: [ResolvedOrder] = []
    @State private var isLoadingOrders = false
    @State private var ordersError: String?

    // Price history
    @State private var priceHistory: [ESIMarketHistory] = []
    @State private var adjustedPrice: Double?
    @State private var averagePrice: Double?
    @State private var marketPrices: [Int: ESIMarketPrice] = [:]

    // Jump cache
    @State private var characterSystemId: Int?
    @State private var jumpCache: [Int: Int] = [:]

    // UI state
    @State private var selectedOrderTab = 0   // 0 = sell, 1 = buy, 2 = history
    @State private var historyDays = 90

    var body: some View {
        HSplitView {
            leftPanel
                .frame(minWidth: 200, idealWidth: 250, maxWidth: 320)
            rightPanel
                .frame(minWidth: 420)
        }
        .navigationTitle("Market Browser")
        .toolbar { toolbarContent }
        .task { await loadInitialData() }
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .automatic) {
            Picker("Region", selection: $selectedRegionId) {
                ForEach(availableRegions, id: \.id) { region in
                    Text(region.name).tag(region.id)
                }
            }
            .frame(minWidth: 160)
            .disabled(availableRegions.isEmpty)
            .onChange(of: selectedRegionId) { _, _ in
                jumpCache.removeAll()
                if let typeId = selectedTypeId {
                    Task { await loadOrders(typeId: typeId) }
                }
            }
        }
    }

    // MARK: - Left Panel

    private var leftPanel: some View {
        VStack(spacing: 0) {
            searchBar
                .padding(10)
            Divider()
            if !searchText.isEmpty {
                searchResultsList
            } else {
                groupTree
            }
        }
        .background(Color(NSColor.controlBackgroundColor))
    }

    // MARK: - Search Bar

    private var searchBar: some View {
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

    // MARK: - Search Results List

    @ViewBuilder
    private var searchResultsList: some View {
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
            .listStyle(.sidebar)
        }
    }

    // MARK: - Group Tree

    @ViewBuilder
    private var groupTree: some View {
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
                    Image(systemName: node.children == nil ? "tag.fill" : "folder.fill")
                        .foregroundStyle(node.children == nil ? Color.secondary : Color.blue)
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

    // MARK: - Type Row (shared)

    private func typeRow(typeId: Int, name: String) -> some View {
        HStack(spacing: 8) {
            AsyncImage(url: EVEImageURL.typeIcon(typeId, size: 64)) { image in
                image.resizable()
            } placeholder: {
                RoundedRectangle(cornerRadius: 3).fill(.quaternary)
            }
            .frame(width: 22, height: 22)
            .clipShape(RoundedRectangle(cornerRadius: 3))
            Text(name)
                .font(.subheadline)
                .lineLimit(1)
        }
    }

    // MARK: - Right Panel

    @ViewBuilder
    private var rightPanel: some View {
        if let typeId = selectedTypeId {
            itemDetailView(typeId: typeId)
        } else if selectedGroupId != nil {
            groupTypesPanel
        } else {
            placeholderView
        }
    }

    private var placeholderView: some View {
        VStack(spacing: 12) {
            Image(systemName: "storefront")
                .font(.system(size: 48))
                .foregroundStyle(.tertiary)
            Text("Select an item to view market data")
                .font(.title3)
                .foregroundStyle(.secondary)
            Text("Browse market groups on the left, or search by item name")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Group Types Panel

    @ViewBuilder
    private var groupTypesPanel: some View {
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
            .listStyle(.plain)
        }
    }

    // MARK: - Item Detail View

    private func itemDetailView(typeId: Int) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                itemHeader(typeId: typeId)

                if adjustedPrice != nil || !sellOrders.isEmpty || !buyOrders.isEmpty {
                    marketStatsBar
                }

                Picker("View", selection: $selectedOrderTab) {
                    Text("Sell Orders (\(sellOrders.count))").tag(0)
                    Text("Buy Orders (\(buyOrders.count))").tag(1)
                    Text("Price History").tag(2)
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 500)

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

    // MARK: - Item Header

    private func itemHeader(typeId: Int) -> some View {
        HStack(spacing: 16) {
            AsyncImage(url: EVEImageURL.typeRender(typeId, size: 256)) { image in
                image.resizable()
            } placeholder: {
                AsyncImage(url: EVEImageURL.typeIcon(typeId, size: 128)) { image in
                    image.resizable()
                } placeholder: {
                    RoundedRectangle(cornerRadius: 8).fill(.quaternary)
                }
            }
            .frame(width: 64, height: 64)
            .clipShape(RoundedRectangle(cornerRadius: 8))

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
                        Text(desc)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(4)
                    }
                }
            }

            Spacer()

            if let account = accountManager.selectedAccount, !account.isTokenExpired {
                let token = account.accessToken
                Button {
                    Task { await openInEVE(typeId: typeId, token: token) }
                } label: {
                    Label("Open in EVE", systemImage: "arrow.up.right.square")
                }
                .buttonStyle(.bordered)
            }
        }
        .padding()
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - Market Stats Bar

    private var marketStatsBar: some View {
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
                statCard("Spread", value: String(format: "%.1f%%", spread), color: .secondary)
            }
        }
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
    }

    private func statCard(_ title: String, value: String, color: Color) -> some View {
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

    // MARK: - Orders Table

    private func ordersTable(orders: [ResolvedOrder], isBuy: Bool) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 0) {
                Text("Price")
                    .frame(width: 120, alignment: .trailing)
                Text("Qty")
                    .frame(width: 80, alignment: .trailing)
                    .padding(.leading, 12)
                Text("Min")
                    .frame(width: 60, alignment: .trailing)
                    .padding(.leading, 12)
                Text("Location")
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.leading, 12)
                Text("Sec")
                    .frame(width: 36, alignment: .center)
                Text("Jumps")
                    .frame(width: 48, alignment: .center)
                if isBuy {
                    Text("Range")
                        .frame(width: 80, alignment: .leading)
                        .padding(.leading, 8)
                }
            }
            .font(.caption.bold())
            .foregroundStyle(.secondary)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(Color(NSColor.separatorColor).opacity(0.15))

            if orders.isEmpty {
                Text("No \(isBuy ? "buy" : "sell") orders in this region")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 80)
                    .multilineTextAlignment(.center)
                    .padding()
            } else {
                LazyVStack(spacing: 0) {
                    ForEach(orders) { resolved in
                        orderRow(resolved, isBuy: isBuy)
                        Divider()
                            .padding(.leading, 12)
                    }
                }
            }
        }
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private func orderRow(_ resolved: ResolvedOrder, isBuy: Bool) -> some View {
        let order = resolved.order
        let priceColor: Color = isBuy ? .orange : .green
        let sec = resolved.securityStatus

        return HStack(spacing: 0) {
            Text(EVEFormatters.formatISK(order.price))
                .font(.subheadline.monospacedDigit())
                .foregroundStyle(priceColor)
                .frame(width: 120, alignment: .trailing)

            VStack(alignment: .trailing, spacing: 1) {
                Text(formatCount(order.volumeRemain))
                    .font(.subheadline.monospacedDigit())
                Text("/ \(formatCount(order.volumeTotal))")
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.tertiary)
            }
            .frame(width: 80, alignment: .trailing)
            .padding(.leading, 12)

            Text(formatCount(order.minVolume))
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: 60, alignment: .trailing)
                .padding(.leading, 12)

            VStack(alignment: .leading, spacing: 1) {
                Text(resolved.locationName)
                    .font(.subheadline)
                    .lineLimit(1)
                Text(resolved.systemName)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.leading, 12)

            Text(String(format: "%.1f", max(0, sec)))
                .font(.caption.bold().monospacedDigit())
                .foregroundStyle(securityColor(sec))
                .frame(width: 36, alignment: .center)

            Group {
                if let jumps = resolved.jumps {
                    Text(jumps == 0 ? "Here" : "\(jumps)")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(jumps == 0 ? .green : jumps < 5 ? .primary : .secondary)
                } else {
                    Text("—")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }
            .frame(width: 48, alignment: .center)

            if isBuy {
                Text(formatRange(order.range))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .frame(width: 80, alignment: .leading)
                    .padding(.leading, 8)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
    }

    // MARK: - Price History

    @ViewBuilder
    private var priceHistoryView: some View {
        let history = filteredHistory

        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Price History")
                    .font(.headline)
                Spacer()
                Picker("Range", selection: $historyDays) {
                    Text("30d").tag(30)
                    Text("90d").tag(90)
                    Text("1y").tag(365)
                }
                .pickerStyle(.segmented)
                .frame(width: 160)
            }

            if history.isEmpty {
                Text("No price history available")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 200)
            } else {
                // Price chart — low/high band + average line
                Chart(history) { entry in
                    if let date = parseHistoryDate(entry.date) {
                        RectangleMark(
                            x: .value("Date", date),
                            yStart: .value("Low", entry.lowest),
                            yEnd: .value("High", entry.highest),
                            width: 2
                        )
                        .foregroundStyle(.blue.opacity(0.25))

                        LineMark(
                            x: .value("Date", date),
                            y: .value("Average", entry.average)
                        )
                        .foregroundStyle(.blue)

                        AreaMark(
                            x: .value("Date", date),
                            y: .value("Average", entry.average)
                        )
                        .foregroundStyle(.blue.opacity(0.08))
                    }
                }
                .chartYAxis {
                    AxisMarks(format: .number.notation(.compactName))
                }
                .frame(height: 200)
                .padding()
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))

                // Volume bars
                Chart(history) { entry in
                    if let date = parseHistoryDate(entry.date) {
                        BarMark(
                            x: .value("Date", date),
                            y: .value("Volume", entry.volume)
                        )
                        .foregroundStyle(.green.opacity(0.6))
                    }
                }
                .chartYAxis {
                    AxisMarks(format: .number.notation(.compactName))
                }
                .frame(height: 70)
                .padding()
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))

                // History summary stats
                if let last = history.last {
                    HStack(spacing: 0) {
                        statCard("5d Avg Vol", value: fiveDayAvgVolume(history), color: .primary)
                        Divider()
                        statCard("Last High", value: EVEFormatters.formatISKShort(last.highest), color: .green)
                        Divider()
                        statCard("Last Low", value: EVEFormatters.formatISKShort(last.lowest), color: .red)
                        Divider()
                        statCard("Last Avg", value: EVEFormatters.formatISKShort(last.average), color: .blue)
                        Divider()
                        statCard("Orders", value: "\(last.orderCount)", color: .secondary)
                    }
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
                }
            }
        }
    }

    // MARK: - Data Loading

    private func loadInitialData() async {
        if let account = accountManager.selectedAccount,
           let data = prefetcher.data(for: account.characterID) {
            characterSystemId = data.location.solarSystemId
        }

        await withTaskGroup(of: Void.self) { group in
            group.addTask { await self.loadRegions() }
            group.addTask { await self.loadMarketGroups() }
            group.addTask { await self.loadMarketPrices() }
        }
    }

    private func loadRegions() async {
        guard availableRegions.isEmpty else { return }
        guard let regionIds: [Int] = try? await ESIClient.shared.fetch("/universe/regions/") else { return }

        // Wormhole regions start at 11000001 — exclude them
        let kspaceIds = regionIds.filter { $0 < 11000001 }

        var regions: [(id: Int, name: String)] = []
        await withTaskGroup(of: (Int, String?).self) { group in
            for id in kspaceIds {
                group.addTask {
                    let r = await UniverseCache.shared.region(id: id)
                    return (id, r?.name)
                }
            }
            for await (id, name) in group {
                if let name { regions.append((id: id, name: name)) }
            }
        }

        availableRegions = regions.sorted { $0.name < $1.name }

        // Default to the character's current region if available
        if let sysId = characterSystemId,
           let system = await UniverseCache.shared.solarSystem(id: sysId),
           let constellation = await UniverseCache.shared.constellation(id: system.constellationId) {
            let regionId = constellation.regionId
            if availableRegions.contains(where: { $0.id == regionId }) {
                selectedRegionId = regionId
            }
        }
    }

    private func loadMarketGroups() async {
        guard allGroupIds.isEmpty else { return }
        isLoadingGroups = true
        defer { isLoadingGroups = false }

        guard let ids: [Int] = try? await ESIClient.shared.fetch("/markets/groups/") else { return }
        allGroupIds = ids

        // Fetch the first 600 sorted IDs — lower IDs tend to be parent/root groups
        let toFetch = Array(ids.sorted().prefix(600))

        let results = await withTaskGroup(of: (Int, ESIMarketGroup?).self) { group in
            for id in toFetch {
                group.addTask {
                    let g: ESIMarketGroup? = try? await ESIClient.shared.fetch("/markets/groups/\(id)/")
                    return (id, g)
                }
            }
            var out: [(Int, ESIMarketGroup?)] = []
            for await result in group { out.append(result) }
            return out
        }

        var newGroups: [Int: ESIMarketGroup] = [:]
        for (id, g) in results {
            if let g { newGroups[id] = g }
        }
        fetchedGroups = newGroups
        rebuildTree()
    }

    private func rebuildTree() {
        let groupIdSet = Set(allGroupIds)
        let roots = fetchedGroups.values
            .filter { g in
                guard let parentId = g.parentGroupId else { return true }
                return !groupIdSet.contains(parentId)
            }
            .sorted { $0.name < $1.name }

        rootNodes = roots.map { buildNode($0) }
    }

    private func buildNode(_ group: ESIMarketGroup) -> MarketGroupNode {
        let children = fetchedGroups.values
            .filter { $0.parentGroupId == group.marketGroupId }
            .sorted { $0.name < $1.name }
            .map { buildNode($0) }

        return MarketGroupNode(
            group: group,
            children: children.isEmpty ? nil : children
        )
    }

    private func loadGroupTypes(group: ESIMarketGroup) async {
        groupTypes = []
        guard !group.types.isEmpty else { return }

        isLoadingGroupTypes = true
        defer { isLoadingGroupTypes = false }

        let typeMap = await UniverseCache.shared.types(ids: group.types)
        groupTypes = group.types.compactMap { typeId in
            guard let info = typeMap[typeId], info.published else { return nil }
            return MarketTypeResult(typeId: typeId, name: info.name)
        }.sorted { $0.name < $1.name }
    }

    private func performSearch(_ query: String) async {
        struct SearchBody: Encodable { let names: [String] }
        struct SearchResponse: Decodable { let inventoryTypes: [ESIIDName]? }

        let result: SearchResponse? = try? await ESIClient.shared.post(
            "/universe/ids/",
            body: SearchBody(names: [query])
        )

        searchResults = (result?.inventoryTypes ?? [])
            .map { MarketTypeResult(typeId: $0.id, name: $0.name) }
            .sorted { $0.name < $1.name }
        isSearching = false
    }

    // MARK: - Type Selection & Order Loading

    private func selectType(_ typeId: Int, name: String) async {
        selectedTypeId = typeId
        selectedTypeName = name
        selectedOrderTab = 0
        selectedTypeInfo = nil
        priceHistory = []
        sellOrders = []
        buyOrders = []

        await withTaskGroup(of: Void.self) { group in
            group.addTask { await self.loadOrders(typeId: typeId) }
            group.addTask {
                self.selectedTypeInfo = await UniverseCache.shared.type(id: typeId)
            }
            group.addTask { await self.loadPriceHistory(typeId: typeId) }
        }
    }

    private func loadOrders(typeId: Int) async {
        isLoadingOrders = true
        ordersError = nil
        sellOrders = []
        buyOrders = []
        defer { isLoadingOrders = false }

        // Capture auth token on main actor before launching child tasks
        let token = accountManager.selectedAccount.flatMap {
            !$0.isTokenExpired ? $0.accessToken : nil
        }
        let originId = characterSystemId

        let orders: [ESIRegionMarketOrder]
        do {
            orders = try await ESIClient.shared.fetch(
                "/markets/\(selectedRegionId)/orders/",
                queryItems: [
                    URLQueryItem(name: "type_id", value: "\(typeId)"),
                    URLQueryItem(name: "order_type", value: "all")
                ]
            )
        } catch {
            ordersError = error.localizedDescription
            return
        }

        let uniqueLocationIds = Set(orders.map { $0.locationId })
        let uniqueSystemIds = Set(orders.map { $0.systemId })

        async let locationNamesTask = resolveLocations(ids: uniqueLocationIds, token: token)
        async let systemDataTask = resolveSystems(ids: uniqueSystemIds)
        async let jumpsTask = resolveJumps(systemIds: uniqueSystemIds, originId: originId)

        let (locationNames, systemData, jumps) = await (locationNamesTask, systemDataTask, jumpsTask)

        for (sysId, count) in jumps { jumpCache[sysId] = count }

        func resolve(_ order: ESIRegionMarketOrder) -> ResolvedOrder {
            let (sysName, sec) = systemData[order.systemId] ?? ("Unknown", 0.0)
            return ResolvedOrder(
                order: order,
                locationName: locationNames[order.locationId] ?? "Unknown Location",
                systemName: sysName,
                securityStatus: sec,
                jumps: jumps[order.systemId]
            )
        }

        sellOrders = orders.filter { !$0.isBuyOrder }.sorted { $0.price < $1.price }.map(resolve)
        buyOrders  = orders.filter { $0.isBuyOrder  }.sorted { $0.price > $1.price }.map(resolve)
    }

    private func resolveLocations(ids: Set<Int>, token: String?) async -> [Int: String] {
        var result: [Int: String] = [:]
        await withTaskGroup(of: (Int, String?).self) { group in
            for locationId in ids {
                group.addTask {
                    if locationId < 1_000_000_000 {
                        let station = await UniverseCache.shared.station(id: locationId)
                        return (locationId, station?.name)
                    } else if let token {
                        let structure: ESIStructure? = try? await ESIClient.shared.fetch(
                            "/universe/structures/\(locationId)/", token: token
                        )
                        return (locationId, structure?.name ?? "Player Structure")
                    } else {
                        return (locationId, "Player Structure")
                    }
                }
            }
            for await (id, name) in group {
                if let name { result[id] = name }
            }
        }
        return result
    }

    private func resolveSystems(ids: Set<Int>) async -> [Int: (String, Double)] {
        var result: [Int: (String, Double)] = [:]
        await withTaskGroup(of: (Int, ESISolarSystem?).self) { group in
            for sysId in ids {
                group.addTask {
                    (sysId, await UniverseCache.shared.solarSystem(id: sysId))
                }
            }
            for await (id, sys) in group {
                if let sys { result[id] = (sys.name, sys.securityStatus) }
            }
        }
        return result
    }

    private func resolveJumps(systemIds: Set<Int>, originId: Int?) async -> [Int: Int] {
        guard let origin = originId else { return [:] }
        var result: [Int: Int] = [:]
        var toFetch: [Int] = []

        for sysId in systemIds {
            if sysId == origin {
                result[sysId] = 0
            } else if let cached = jumpCache[sysId] {
                result[sysId] = cached
            } else {
                toFetch.append(sysId)
            }
        }

        // Cap route fetches to avoid hammering the API
        let limited = Array(toFetch.prefix(30))
        let routes = await withTaskGroup(of: (Int, Int?).self) { group in
            for destId in limited {
                group.addTask {
                    let route: [Int]? = try? await ESIClient.shared.fetch("/route/\(origin)/\(destId)/")
                    return (destId, route.map { max(0, $0.count - 1) })
                }
            }
            var out: [(Int, Int?)] = []
            for await r in group { out.append(r) }
            return out
        }

        for (sysId, jumps) in routes {
            if let jumps { result[sysId] = jumps }
        }
        return result
    }

    private func loadMarketPrices() async {
        guard marketPrices.isEmpty else { return }
        let prices: [ESIMarketPrice]? = try? await ESIClient.shared.fetch("/markets/prices/")
        if let prices {
            var map: [Int: ESIMarketPrice] = [:]
            for price in prices { map[price.typeId] = price }
            marketPrices = map
        }
    }

    private func loadPriceHistory(typeId: Int) async {
        let history: [ESIMarketHistory]? = try? await ESIClient.shared.fetch(
            "/markets/\(selectedRegionId)/history/",
            queryItems: [URLQueryItem(name: "type_id", value: "\(typeId)")]
        )
        priceHistory = (history ?? []).sorted { $0.date < $1.date }

        if let price = marketPrices[typeId] {
            adjustedPrice = price.adjustedPrice
            averagePrice = price.averagePrice
        } else {
            adjustedPrice = nil
            averagePrice = nil
        }
    }

    private func openInEVE(typeId: Int, token: String) async {
        try? await ESIClient.shared.postAction(
            "/ui/openwindow/marketdetails/",
            token: token,
            queryItems: [URLQueryItem(name: "type_id", value: "\(typeId)")]
        )
    }

    // MARK: - Computed Helpers

    private var filteredHistory: [ESIMarketHistory] {
        guard let cutoff = Calendar.current.date(byAdding: .day, value: -historyDays, to: Date()) else {
            return priceHistory
        }
        let cutoffStr = historyDateString(cutoff)
        return priceHistory.filter { $0.date >= cutoffStr }
    }

    private func parseHistoryDate(_ str: String) -> Date? {
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy-MM-dd"
        fmt.timeZone = TimeZone(identifier: "UTC")
        return fmt.date(from: str)
    }

    private func historyDateString(_ date: Date) -> String {
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy-MM-dd"
        fmt.timeZone = TimeZone(identifier: "UTC")
        return fmt.string(from: date)
    }

    private func fiveDayAvgVolume(_ history: [ESIMarketHistory]) -> String {
        let recent = history.suffix(5)
        guard !recent.isEmpty else { return "—" }
        let avg = recent.map { Double($0.volume) }.reduce(0, +) / Double(recent.count)
        return formatCount(Int(avg))
    }

    private func securityColor(_ sec: Double) -> Color {
        switch sec {
        case 0.45...: return .green
        case 0.0..<0.45: return .orange
        default: return .red
        }
    }

    private func formatCount(_ value: Int) -> String {
        let abs = value < 0 ? -value : value
        switch abs {
        case 1_000_000_000...: return String(format: "%.1fB", Double(value) / 1_000_000_000)
        case 1_000_000...:     return String(format: "%.1fM", Double(value) / 1_000_000)
        case 10_000...:        return String(format: "%.1fK", Double(value) / 1_000)
        default:
            let f = NumberFormatter()
            f.numberStyle = .decimal
            return f.string(from: NSNumber(value: value)) ?? "\(value)"
        }
    }

    private func formatRange(_ range: String) -> String {
        switch range {
        case "station":    return "Station"
        case "solarsystem": return "System"
        case "region":     return "Region"
        case "1":          return "1 jump"
        case "2":          return "2 jumps"
        case "3":          return "3 jumps"
        case "4":          return "4 jumps"
        case "5":          return "5 jumps"
        case "10":         return "10 jumps"
        case "20":         return "20 jumps"
        case "30":         return "30 jumps"
        case "40":         return "40 jumps"
        default:           return range
        }
    }
}
