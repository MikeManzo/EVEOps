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

// MARK: - SplitDivider (NSView-backed for jitter-free dragging)
//
// SwiftUI's DragGesture can lose its internal translation state when the parent
// view re-renders mid-drag, causing the pane to snap back. By routing mouse
// events through NSView instead, startValue and startPoint live on a stable
// Objective-C object that SwiftUI never recreates during re-renders.

private class DragHandleNSView: NSView {
    var isHorizontal = true
    /// Updated by NSViewRepresentable.updateNSView on every render.
    var currentValue: CGFloat = 0
    var minValue: CGFloat = 0
    var maxValue: CGFloat = .greatestFiniteMagnitude
    var onDrag: ((CGFloat) -> Void)?
    var onEnd: (() -> Void)?

    private var startValue: CGFloat = 0   // pane size captured at mouseDown
    private var startPoint: NSPoint?
    private var trackingArea: NSTrackingArea?

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let ta = trackingArea { removeTrackingArea(ta) }
        let ta = NSTrackingArea(rect: bounds,
                                options: [.mouseEnteredAndExited, .activeInActiveApp],
                                owner: self, userInfo: nil)
        addTrackingArea(ta)
        trackingArea = ta
    }

    override func mouseEntered(with event: NSEvent) {
        (isHorizontal ? NSCursor.resizeLeftRight : NSCursor.resizeUpDown).push()
    }

    override func mouseExited(with event: NSEvent) {
        NSCursor.pop()
    }

    override func mouseDown(with event: NSEvent) {
        startValue = currentValue
        startPoint = event.locationInWindow
    }

    override func mouseDragged(with event: NSEvent) {
        guard let start = startPoint else { return }
        let pt = event.locationInWindow
        // NSView y=0 is at bottom: dragging DOWN decreases y → negative offset →
        // detailHeight shrinks, which is correct (divider moves toward detail pane).
        let offset = isHorizontal ? pt.x - start.x : pt.y - start.y
        let newValue = max(minValue, min(maxValue, startValue + offset))
        onDrag?(newValue)
    }

    override func mouseUp(with event: NSEvent) {
        startPoint = nil
        onEnd?()
    }
}

private struct DragHandle: NSViewRepresentable {
    let isHorizontal: Bool
    let value: CGFloat
    let minValue: CGFloat
    let maxValue: CGFloat
    let onChange: (CGFloat) -> Void
    var onEnd: (() -> Void)? = nil

    func makeNSView(context: Context) -> DragHandleNSView {
        let v = DragHandleNSView()
        apply(to: v)
        return v
    }

    func updateNSView(_ v: DragHandleNSView, context: Context) {
        apply(to: v)
    }

    private func apply(to v: DragHandleNSView) {
        v.isHorizontal = isHorizontal
        v.currentValue = value
        v.minValue = minValue
        v.maxValue = maxValue
        v.onDrag = onChange
        v.onEnd = onEnd
    }
}

private struct SplitDivider: View {
    enum Direction { case horizontal, vertical }
    let direction: Direction
    let value: CGFloat
    let minValue: CGFloat
    let maxValue: CGFloat
    let onChange: (CGFloat) -> Void
    var onEnd: (() -> Void)? = nil

    var body: some View {
        ZStack {
            // Visual separator (SwiftUI — adapts to dark/light mode automatically)
            Color(NSColor.separatorColor)
                .frame(width: direction == .horizontal ? 1 : nil,
                       height: direction == .vertical   ? 1 : nil)
            // Transparent NSView hit-target — handles all mouse events
            DragHandle(isHorizontal: direction == .horizontal,
                       value: value, minValue: minValue, maxValue: maxValue,
                       onChange: onChange, onEnd: onEnd)
        }
        .frame(width: direction == .horizontal ? 8 : nil,
               height: direction == .vertical   ? 8 : nil)
    }
}

// MARK: - MarketBrowserView

struct MarketBrowserView: View {
    @Environment(AccountManager.self) private var accountManager
    @Environment(DashboardPrefetcher.self) private var prefetcher

    // Region
    @State private var selectedRegionId: Int = 10000002   // The Forge (Jita)
    @State private var availableRegions: [(id: Int, name: String, factionId: Int?)] = []

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

    // Persisted pane sizes — written only on drag end to avoid UserDefaults
    // writes at 60 Hz, which would cause re-render jitter during dragging.
    @AppStorage("market.leftPaneWidth")    private var savedLeftWidth:    Double = 240
    @AppStorage("market.detailPaneHeight") private var savedDetailHeight: Double = 300

    // Live pixel values updated on every drag event (fast @State, no I/O).
    // Initialised directly from UserDefaults so the correct size is shown
    // on the very first frame, with no .onAppear flash.
    @State private var leftWidth: CGFloat = {
        let v = UserDefaults.standard.double(forKey: "market.leftPaneWidth")
        return CGFloat(v > 0 ? v : 240)
    }()
    @State private var detailHeight: CGFloat = {
        let v = UserDefaults.standard.double(forKey: "market.detailPaneHeight")
        return CGFloat(v > 0 ? v : 300)
    }()

    var body: some View {
        VStack(spacing: 0) {
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
        .navigationTitle("Market Browser")
        .toolbar { toolbarContent }
        .task { await loadInitialData() }
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .automatic) {
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
    }

    private func onRegionChanged() {
        jumpCache.removeAll()
        if let typeId = selectedTypeId {
            Task {
                await withTaskGroup(of: Void.self) { group in
                    group.addTask { await self.loadOrders(typeId: typeId) }
                    group.addTask { await self.loadPriceHistory(typeId: typeId) }
                }
            }
        }
    }

    // MARK: - Left Pane (search bar + group tree)

    private var leftPane: some View {
        VStack(spacing: 0) {
            searchBar
                .padding(10)
            Divider()
            groupTree
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

    // MARK: - Right Pane (items list — search results or group contents)

    @ViewBuilder
    private var rightPane: some View {
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
            .listStyle(.plain)
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
                    if node.group.parentGroupId == nil {
                        // Root category — distinctive icon + color from marketGroupIcon
                        let (symbol, color) = marketGroupIcon(node.group.name)
                        Image(systemName: symbol)
                            .foregroundStyle(color)
                    } else if node.children != nil {
                        Image(systemName: "folder.fill")
                            .foregroundStyle(Color.blue.opacity(0.75))
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

    // MARK: - Type Row (shared)

    private func typeRow(typeId: Int, name: String) -> some View {
        HStack(spacing: 8) {
            AsyncImage(url: EVEImageURL.typeIcon(typeId, size: 256)) { image in
                image.resizable()
            } placeholder: {
                RoundedRectangle(cornerRadius: 3).fill(.quaternary)
            }
            .frame(width: 22, height: 22)
            .clipShape(RoundedRectangle(cornerRadius: 3))
            Text(name)
                .font(.headline)
                .lineLimit(1)
        }
    }

    // MARK: - Detail Pane (bottom, full width)

    @ViewBuilder
    private var detailPane: some View {
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
            .listStyle(.sidebar)
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
                    ForEach(Array(orders.enumerated()), id: \.element.id) { index, resolved in
                        orderRow(resolved, isBuy: isBuy, isEven: index % 2 == 0)
                        Divider()
                            .padding(.leading, 15)
                    }
                }
            }
        }
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private func orderRow(_ resolved: ResolvedOrder, isBuy: Bool, isEven: Bool) -> some View {
        let order = resolved.order
        let priceColor: Color = isBuy ? .orange : .green
        let sec = resolved.securityStatus
        let fillRatio = CGFloat(order.volumeRemain) / CGFloat(max(1, order.volumeTotal))

        return HStack(spacing: 0) {
            // Left accent bar — green for sell, orange for buy
            Rectangle()
                .fill(priceColor.opacity(0.75))
                .frame(width: 3)

            HStack(spacing: 0) {
                Text(EVEFormatters.formatISK(order.price))
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(priceColor)
                    .frame(width: 120, alignment: .trailing)

                // Qty with volume fill bar
                VStack(alignment: .trailing, spacing: 2) {
                    Text(formatCount(order.volumeRemain))
                        .font(.subheadline.monospacedDigit())
                    Text("/ \(formatCount(order.volumeTotal))")
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.tertiary)
                    ZStack(alignment: .trailing) {
                        RoundedRectangle(cornerRadius: 1)
                            .fill(Color.primary.opacity(0.08))
                        RoundedRectangle(cornerRadius: 1)
                            .fill(priceColor.opacity(0.55))
                            .frame(width: 80 * fillRatio)
                    }
                    .frame(width: 80, height: 2)
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

                // Security status pill badge
                Text(String(format: "%.1f", max(0, sec)))
                    .font(.system(size: 9, weight: .bold).monospacedDigit())
                    .foregroundStyle(.white)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(securityColor(sec), in: Capsule())
                    .frame(width: 36, alignment: .center)

                // Jumps with colored proximity dot
                Group {
                    if let jumps = resolved.jumps {
                        HStack(spacing: 3) {
                            Circle()
                                .fill(jumps == 0 ? Color.green : jumps < 5 ? Color.yellow : Color.orange)
                                .frame(width: 5, height: 5)
                            Text(jumps == 0 ? "Here" : "\(jumps)")
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(jumps == 0 ? .green : jumps < 5 ? .primary : .secondary)
                        }
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
        .background(isEven ? Color.primary.opacity(0.03) : Color.clear)
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
                let eveTeal = Color(red: 0.2, green: 0.75, blue: 0.8)
                Chart(history) { entry in
                    if let date = parseHistoryDate(entry.date) {
                        RectangleMark(
                            x: .value("Date", date),
                            yStart: .value("Low", entry.lowest),
                            yEnd: .value("High", entry.highest),
                            width: 4
                        )
                        .foregroundStyle(eveTeal.opacity(0.4))

                        LineMark(
                            x: .value("Date", date),
                            y: .value("Average", entry.average)
                        )
                        .foregroundStyle(eveTeal)
                        .lineStyle(StrokeStyle(lineWidth: 1.5))

                        AreaMark(
                            x: .value("Date", date),
                            y: .value("Average", entry.average)
                        )
                        .foregroundStyle(eveTeal.opacity(0.12))
                    }
                }
                .chartYAxis {
                    AxisMarks { value in
                        AxisGridLine()
                        if let v = value.as(Double.self) {
                            AxisValueLabel { Text(EVEFormatters.formatISKShort(v)).font(.caption2) }
                        }
                    }
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
                        .foregroundStyle(Color(red: 0.15, green: 0.55, blue: 0.4).opacity(0.85))
                    }
                }
                .chartYAxis {
                    AxisMarks(values: .automatic(desiredCount: 3)) { value in
                        AxisGridLine()
                        if let v = value.as(Int.self) {
                            AxisValueLabel { Text(formatCount(v)).font(.caption2) }
                        }
                    }
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
        availableRegions = await UniverseCache.shared.knownSpaceRegions()

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

        guard let ids: [Int] = try? await ESIClient.shared.fetch("/markets/groups/") else {
            isLoadingGroups = false
            return
        }
        allGroupIds = ids

        // Fetch groups in batches of 30 to avoid spawning ~2000 concurrent tasks,
        // which causes a CPU/network burst on first load.
        let batchSize = 30
        let batches = stride(from: 0, to: ids.count, by: batchSize).map {
            Array(ids[$0..<min($0 + batchSize, ids.count)])
        }

        for batch in batches {
            await withTaskGroup(of: (Int, ESIMarketGroup?).self) { group in
                for id in batch {
                    group.addTask {
                        let g: ESIMarketGroup? = try? await ESIClient.shared.fetch("/markets/groups/\(id)/")
                        return (id, g)
                    }
                }
                for await (id, g) in group {
                    if let g { fetchedGroups[id] = g }
                }
            }
            rebuildTree()
            isLoadingGroups = false   // show partial tree; loading continues silently
        }
        isLoadingGroups = false
    }

    /// O(n) tree rebuild using a parent→children map rather than scanning all
    /// groups for each node (previously O(n²), called ~60 times during load).
    private func rebuildTree() {
        var childrenByParent: [Int: [ESIMarketGroup]] = [:]
        var rootGroups: [ESIMarketGroup] = []

        for g in fetchedGroups.values {
            if let parentId = g.parentGroupId, fetchedGroups[parentId] != nil {
                childrenByParent[parentId, default: []].append(g)
            } else {
                rootGroups.append(g)
            }
        }

        func buildNode(_ group: ESIMarketGroup) -> MarketGroupNode {
            let children = (childrenByParent[group.marketGroupId] ?? [])
                .sorted { $0.name < $1.name }
                .map { buildNode($0) }
            return MarketGroupNode(group: group, children: children.isEmpty ? nil : children)
        }

        rootNodes = rootGroups.sorted { $0.name < $1.name }.map { buildNode($0) }
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
                let info = await UniverseCache.shared.type(id: typeId)
                await MainActor.run { self.selectedTypeInfo = info }
            }
            group.addTask { await self.loadPriceHistory(typeId: typeId) }
        }
    }

    private func loadOrders(typeId: Int) async {
        isLoadingOrders = true
        ordersError = nil
        sellOrders = []
        buyOrders = []

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
            isLoadingOrders = false
            return
        }

        // Show prices/quantities immediately; location and system names resolve below.
        let sortedSell = orders.filter { !$0.isBuyOrder }.sorted { $0.price < $1.price }
        let sortedBuy  = orders.filter {  $0.isBuyOrder }.sorted { $0.price > $1.price }
        sellOrders = sortedSell.map { ResolvedOrder(order: $0, locationName: "…", systemName: "…", securityStatus: 0, jumps: nil) }
        buyOrders  = sortedBuy .map { ResolvedOrder(order: $0, locationName: "…", systemName: "…", securityStatus: 0, jumps: nil) }
        isLoadingOrders = false

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

        sellOrders = sortedSell.map(resolve)
        buyOrders  = sortedBuy.map(resolve)
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

    // DateFormatter is expensive to construct; share a single static instance.
    private static let historyDateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.timeZone = TimeZone(identifier: "UTC")
        return f
    }()

    private func parseHistoryDate(_ str: String) -> Date? {
        Self.historyDateFormatter.date(from: str)
    }

    private func historyDateString(_ date: Date) -> String {
        Self.historyDateFormatter.string(from: date)
    }

    private func fiveDayAvgVolume(_ history: [ESIMarketHistory]) -> String {
        let recent = history.suffix(5)
        guard !recent.isEmpty else { return "—" }
        let avg = recent.map { Double($0.volume) }.reduce(0, +) / Double(recent.count)
        return formatCount(Int(avg))
    }

    /// Maps top-level market group names to EVE-relevant SF Symbols and accent colors.
    private func marketGroupIcon(_ name: String) -> (symbol: String, color: Color) {
        let lower = name.lowercased()
        if lower.contains("ship")                                   { return ("airplane", Color(red: 0.35, green: 0.65, blue: 0.90)) }
        if lower.contains("module") || lower.contains("fitting")    { return ("cpu", .orange) }
        if lower.contains("ammo") || lower.contains("charge") || lower.contains("missile") { return ("bolt.fill", .yellow) }
        if lower.contains("drone")                                  { return ("ant.fill", .green) }
        if lower.contains("structure")                              { return ("building.2.fill", Color(red: 0.6, green: 0.6, blue: 0.7)) }
        if lower.contains("skill")                                  { return ("book.fill", Color(red: 0.35, green: 0.65, blue: 0.90)) }
        if lower.contains("implant") || lower.contains("booster")  { return ("brain.head.profile", .purple) }
        if lower.contains("blueprint")                              { return ("doc.fill", Color(red: 0.2, green: 0.75, blue: 0.8)) }
        if lower.contains("apparel") || lower.contains("clothing")  { return ("tshirt.fill", .pink) }
        if lower.contains("deployable")                             { return ("antenna.radiowaves.left.and.right", .cyan) }
        if lower.contains("fuel")                                   { return ("flame.fill", .orange) }
        if lower.contains("planetary") || lower.contains("colony") { return ("globe", .teal) }
        if lower.contains("commodity") || lower.contains("material") { return ("cube.fill", Color(red: 0.65, green: 0.5, blue: 0.35)) }
        if lower.contains("plex") || lower.contains("token")       { return ("creditcard.fill", .yellow) }
        return ("tag.fill", .secondary)
    }

    private func securityColor(_ sec: Double) -> Color {
        switch sec {
        case 0.45...: return .green
        case 0.0..<0.45: return .orange
        default: return .red
        }
    }

    private func regionEmoji(_ regionId: Int) -> String {
        switch regionId {
        case 10000002, 10000016, 10000033, 10000069:                    return "🔵" // Caldari
        case 10000036, 10000038, 10000043, 10000052, 10000054, 10000065: return "🟡" // Amarr
        case 10000032, 10000037, 10000044, 10000048, 10000064, 10000068: return "🟢" // Gallente
        case 10000028, 10000030, 10000042:                              return "🔴" // Minmatar
        case 10000001, 10000049:                                        return "🟡" // Ammatar/Khanid
        case 10000015:                                                  return "🟠" // Thukker
        default:                                                        return "⚫" // null-sec
        }
    }

    // Hardcoded region → faction color. Region faction affiliations are static
    // game data that essentially never changes between EVE patches.
    private func regionColor(_ regionId: Int) -> Color {
        switch regionId {
        // Caldari — blue
        case 10000002, 10000016, 10000033, 10000069:
            return Color(red: 0.35, green: 0.65, blue: 0.90)
        // Amarr — gold
        case 10000036, 10000038, 10000043, 10000052, 10000054, 10000065:
            return Color(red: 0.90, green: 0.75, blue: 0.20)
        // Gallente — green
        case 10000032, 10000037, 10000044, 10000048, 10000064, 10000068:
            return Color(red: 0.25, green: 0.70, blue: 0.35)
        // Minmatar — red
        case 10000028, 10000030, 10000042:
            return Color(red: 0.85, green: 0.35, blue: 0.25)
        // Ammatar Mandate (Amarr-aligned) — dark gold
        case 10000001:
            return Color(red: 0.75, green: 0.60, blue: 0.15)
        // Khanid Kingdom — dark gold
        case 10000049:
            return Color(red: 0.75, green: 0.60, blue: 0.15)
        // Thukker Tribe lowsec — orange
        case 10000015:
            return Color(red: 0.85, green: 0.50, blue: 0.20)
        // Null-sec / NPC null / unaffiliated
        default:
            return Color.secondary
        }
    }

    private static let countNumberFormatter: NumberFormatter = {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        return f
    }()

    private func formatCount(_ value: Int) -> String {
        let abs = value < 0 ? -value : value
        switch abs {
        case 1_000_000_000...: return String(format: "%.1fB", Double(value) / 1_000_000_000)
        case 1_000_000...:     return String(format: "%.1fM", Double(value) / 1_000_000)
        case 10_000...:        return String(format: "%.1fK", Double(value) / 1_000)
        default:
            return Self.countNumberFormatter.string(from: NSNumber(value: value)) ?? "\(value)"
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
