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

// MARK:  Input

struct FittingShopInput: Sendable {
    let fittingName: String
    let shipTypeId: Int
    let items: [FittingShopItem]

    func multiBuyString() -> String {
        items.map { "\($0.name)\t\($0.quantity)" }.joined(separator: "\n")
    }
}

// MARK:  Main View

struct FittingShopView: View {
    let input: FittingShopInput

    @Environment(AccountManager.self) private var accountManager
    @Environment(\.dismiss) private var dismiss

    @State private var quotes: [StationQuote] = []
    @State private var isSearchingHubs = false
    @State private var isSearchingGalaxy = false
    @State private var galaxyTask: Task<Void, Never>?
    @State private var galaxySearched = 0
    @State private var galaxyTotal = 0
    @State private var selectedQuoteId: Int?
    @State private var waypointMessage: String?
    @State private var waypointIsSuccess = false
    @State private var popoverItem: ItemQuote?
    @State private var deselectedTypeIds: Set<Int> = []

    private var selectedQuote: StationQuote? { quotes.first { $0.id == selectedQuoteId } }

    private var filteredTotal: Double {
        guard let quote = selectedQuote else { return 0 }
        return quote.itemQuotes
            .filter { !deselectedTypeIds.contains($0.typeId) && $0.canFill }
            .reduce(0) { $0 + $1.totalPrice }
    }

    private var selectedItemCount: Int {
        guard let quote = selectedQuote else { return 0 }
        return quote.itemQuotes.filter { !deselectedTypeIds.contains($0.typeId) }.count
    }

    var body: some View {
        VStack(spacing: 0) {
            headerBar
            Divider()
            HStack(spacing: 0) {
                leftPanel
                if let quote = selectedQuote {
                    Divider()
                    itemDetailPane(quote)
                        .frame(width: 388)
                }
            }
            .frame(minHeight: 475)
            Divider()
            actionBar
        }
        .frame(minWidth: selectedQuote != nil ? 950 : 575, idealWidth: 1025, minHeight: 650)
        .task { await startHubSearch() }
    }

    // MARK: Header

    private var headerBar: some View {
        HStack(spacing: 15) {
            AsyncImage(url: EVEImageURL.typeRender(input.shipTypeId, size: 128)) { image in
                image.resizable().aspectRatio(contentMode: .fill)
            } placeholder: {
                RoundedRectangle(cornerRadius: 6).fill(.quaternary)
            }
            .frame(width: 45, height: 45)
            .clipShape(RoundedRectangle(cornerRadius: 6))

            VStack(alignment: .leading, spacing: 2) {
                Text("Shop This Fitting")
                    .font(.title3.bold())
                Text("\(input.fittingName) · \(input.items.count) items")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()
            Button("Done") { dismiss() }
                .keyboardShortcut(.escape)
        }
        .padding(20)
    }

    // MARK: Left Panel

    private var leftPanel: some View {
        VStack(spacing: 0) {
            controlBar
            Divider()
            if quotes.isEmpty && !isSearchingHubs {
                emptyState
            } else {
                resultsTable
            }
        }
    }

    private var controlBar: some View {
        HStack(spacing: 12) {
            if isSearchingHubs {
                ProgressView().controlSize(.mini)
                Text("Searching trade hubs…")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else if isSearchingGalaxy {
                ProgressView(value: Double(galaxySearched), total: max(Double(galaxyTotal), 1))
                    .progressViewStyle(.linear)
                    .frame(width: 175)
                Text(galaxyTotal > 0
                     ? "\(galaxySearched) / \(galaxyTotal)"
                     : "Loading regions…")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                Button("Cancel") {
                    galaxyTask?.cancel()
                    isSearchingGalaxy = false
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            } else {
                Text(quotes.isEmpty ? "No results" : "\(quotes.count) station\(quotes.count == 1 ? "" : "s")")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button {
                Task { await startGalaxySearch() }
            } label: {
                Label("Full Galaxy Search", systemImage: "globe.europe.africa.fill")
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
            .disabled(isSearchingHubs || isSearchingGalaxy)
            .help("Search all k-space regions for the cheapest station — takes 30–60 seconds")
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
    }

    // MARK: Results Table

    private var resultsTable: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                Text("Station / System")
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.leading, 27)
                Text("Total ISK")
                    .frame(width: 163, alignment: .trailing)
                Text("Items")
                    .frame(width: 85, alignment: .center)
                Text("Sec")
                    .frame(width: 55, alignment: .center)
                    .padding(.trailing, 20)
            }
            .font(.subheadline.bold())
            .foregroundStyle(.secondary)
            .padding(.vertical, 8)
            .background(Color(NSColor.separatorColor).opacity(0.15))

            Divider()

            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(Array(quotes.enumerated()), id: \.element.id) { index, quote in
                        quoteRow(quote, isEven: index % 2 == 0)
                            .contentShape(Rectangle())
                            .onTapGesture { selectedQuoteId = quote.id }
                        Divider().padding(.leading, 20)
                    }
                }
            }
        }
    }

    private func quoteRow(_ quote: StationQuote, isEven: Bool) -> some View {
        let isSelected = selectedQuoteId == quote.id
        let accentColor: Color = quote.isComplete ? .green : .orange

        return HStack(spacing: 0) {
            Rectangle()
                .fill(accentColor.opacity(0.75))
                .frame(width: 4)

            HStack(spacing: 0) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(quote.stationName)
                        .font(.callout)
                        .lineLimit(1)
                    HStack(spacing: 5) {
                        Text(quote.systemName)
                        if !quote.regionName.isEmpty {
                            Text("·")
                            Text(quote.regionName)
                        }
                    }
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.leading, 12)

                Text(quote.isComplete ? EVEFormatters.formatISKShort(quote.totalISK) : "—")
                    .font(.subheadline.monospacedDigit().bold())
                    .foregroundStyle(quote.isComplete ? .green : .secondary)
                    .frame(width: 163, alignment: .trailing)

                Group {
                    if quote.isComplete {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                            .font(.body)
                    } else {
                        Text("\(quote.missingCount) missing")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 3)
                            .background(.orange, in: Capsule())
                    }
                }
                .frame(width: 85, alignment: .center)

                Text(String(format: "%.1f", max(0, quote.securityStatus)))
                    .font(.system(size: 11, weight: .bold).monospacedDigit())
                    .foregroundStyle(.white)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(securityColor(quote.securityStatus), in: Capsule())
                    .frame(width: 55, alignment: .center)
                    .padding(.trailing, 20)
            }
            .padding(.vertical, 11)
        }
        .background(isSelected
            ? Color.accentColor.opacity(0.15)
            : (isEven ? Color.primary.opacity(0.03) : Color.clear))
        .overlay(
            isSelected
                ? RoundedRectangle(cornerRadius: 0)
                    .strokeBorder(Color.accentColor.opacity(0.4), lineWidth: 1)
                : nil
        )
    }

    // MARK: Item Detail Pane

    private func itemDetailPane(_ quote: StationQuote) -> some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(quote.stationName)
                        .font(.caption.bold())
                        .lineLimit(1)
                    Text(quote.systemName + (quote.regionName.isEmpty ? "" : " · " + quote.regionName))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button {
                    if deselectedTypeIds.isEmpty {
                        // Deselect all
                        deselectedTypeIds = Set(quote.itemQuotes.map(\.typeId))
                    } else {
                        // Select all
                        deselectedTypeIds.removeAll()
                    }
                } label: {
                    Text(deselectedTypeIds.isEmpty ? "Deselect All" : "Select All")
                        .font(.caption)
                }
                .buttonStyle(.plain)
                .tint(.accentColor)
                .foregroundStyle(Color.accentColor)
            }
            .padding(.horizontal, 15)
            .padding(.top, 12)
            .padding(.bottom, 10)

            Divider()

            ScrollView {
                VStack(spacing: 0) {
                    ForEach(quote.itemQuotes, id: \.typeId) { item in
                        let included = !deselectedTypeIds.contains(item.typeId)
                        HStack(spacing: 0) {
                            Button {
                                if deselectedTypeIds.contains(item.typeId) {
                                    deselectedTypeIds.remove(item.typeId)
                                } else {
                                    deselectedTypeIds.insert(item.typeId)
                                }
                            } label: {
                                Image(systemName: included ? "checkmark.square.fill" : "square")
                                    .font(.system(size: 15))
                                    .foregroundStyle(included ? Color.accentColor : Color.secondary.opacity(0.4))
                                    .frame(width: 38, alignment: .center)
                            }
                            .buttonStyle(.plain)
                            .padding(.leading, 8)

                            itemQuoteRow(item)
                                .opacity(included ? 1 : 0.4)
                                .frame(maxWidth: .infinity)
                                .contentShape(Rectangle())
                                .onTapGesture {
                                    popoverItem = popoverItem?.typeId == item.typeId ? nil : item
                                }
                                .popover(isPresented: Binding(
                                    get: { popoverItem?.typeId == item.typeId },
                                    set: { if !$0 { popoverItem = nil } }
                                )) {
                                    ItemShopPopover(item: item)
                                }
                        }
                        Divider()
                    }
                }
            }

            if quote.isComplete || !deselectedTypeIds.isEmpty {
                Divider()
                HStack {
                    if !deselectedTypeIds.isEmpty {
                        Text("\(selectedItemCount) of \(quote.itemQuotes.count) items")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        Text("Total")
                            .font(.caption.bold())
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text(EVEFormatters.formatISK(filteredTotal))
                        .font(.caption.bold().monospacedDigit())
                        .foregroundStyle(deselectedTypeIds.isEmpty ? .green : .primary)
                }
                .padding(.horizontal, 15)
                .padding(.vertical, 10)
            }
        }
    }

    private func itemQuoteRow(_ item: ItemQuote) -> some View {
        HStack(spacing: 10) {
            AsyncImage(url: EVEImageURL.typeIcon(item.typeId, size: 32)) { image in
                image.resizable()
            } placeholder: {
                RoundedRectangle(cornerRadius: 3).fill(.quaternary)
            }
            .frame(width: 30, height: 30)
            .clipShape(RoundedRectangle(cornerRadius: 3))
            .opacity(item.canFill ? 1 : 0.4)

            VStack(alignment: .leading, spacing: 1) {
                Text(item.name)
                    .font(.caption)
                    .lineLimit(1)
                    .foregroundStyle(item.canFill ? .primary : .secondary)
                if item.canFill {
                    Text("\(item.quantity) × \(EVEFormatters.formatISKShort(item.unitPrice))")
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.secondary)
                } else {
                    Text("Not available")
                        .font(.caption2)
                        .foregroundStyle(.orange)
                }
            }

            Spacer(minLength: 5)

            if item.canFill {
                Text(EVEFormatters.formatISKShort(item.totalPrice))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .padding(.leading, 4)
        .padding(.trailing, 15)
        .padding(.vertical, 6)
    }

    // MARK: Empty State

    private var emptyState: some View {
        VStack(spacing: 15) {
            Image(systemName: "cart.badge.questionmark")
                .font(.system(size: 45))
                .foregroundStyle(.tertiary)
            Text("No market data found")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: Action Bar

    private var actionBar: some View {
        HStack(spacing: 15) {
            if let quote = selectedQuote {
                VStack(alignment: .leading, spacing: 2) {
                    Text(quote.stationName)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    if quote.isComplete {
                        Text(EVEFormatters.formatISK(filteredTotal))
                            .font(.subheadline.bold().monospacedDigit())
                            .foregroundStyle(deselectedTypeIds.isEmpty ? .primary : .secondary)
                    } else {
                        Text("\(quote.missingCount) item\(quote.missingCount == 1 ? "" : "s") not available at this station")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                if let msg = waypointMessage {
                    HStack(spacing: 6) {
                        Image(systemName: waypointIsSuccess ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                            .foregroundStyle(waypointIsSuccess ? .green : .orange)
                        Text(msg)
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .transition(.opacity)
                }

                Button {
                    Task { await setDestination(locationId: quote.locationId) }
                } label: {
                    Label("Set Destination", systemImage: "location.fill")
                }
                .buttonStyle(.bordered)

                Button {
                    copyMultiBuy()
                } label: {
                    Label("Copy Multi-Buy", systemImage: "doc.on.clipboard")
                }
                .buttonStyle(.borderedProminent)

            } else {
                Text("Select a station to set destination or copy the shopping list")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 15)
    }

    // MARK: Hub Search

    private func startHubSearch() async {
        isSearchingHubs = true
        quotes = []
        let results = await FittingMarketService.quickSearch(items: input.items)
        quotes = results
        isSearchingHubs = false
        selectedQuoteId = results.first(where: { $0.isComplete })?.id ?? results.first?.id
    }

    // MARK: Galaxy Search

    private func startGalaxySearch() async {
        galaxyTask?.cancel()
        isSearchingGalaxy = true
        galaxySearched = 0
        galaxyTotal = 0
        quotes = []
        selectedQuoteId = nil

        galaxyTask = Task { await runGalaxySearch() }
        await galaxyTask?.value
    }

    private func runGalaxySearch() async {
        let regions = await UniverseCache.shared.knownSpaceRegions()
        let typeIds = Array(Set(input.items.map(\.typeId)))
        galaxyTotal = regions.count * typeIds.count

        let accumulator = GalaxyOrderAccumulator()

        await withTaskGroup(of: Void.self) { group in
            for typeId in typeIds {
                for region in regions {
                    let rid = region.id
                    let tid = typeId
                    group.addTask {
                        let orders: [ESIRegionMarketOrder] = (try? await ESIClient.shared.fetch(
                            "/markets/\(rid)/orders/",
                            queryItems: [
                                URLQueryItem(name: "type_id", value: "\(tid)"),
                                URLQueryItem(name: "order_type", value: "sell")
                            ]
                        )) ?? []
                        await accumulator.add(typeId: tid, orders: orders)
                    }
                }
            }
            for await _ in group {
                galaxySearched += 1
            }
        }

        guard !Task.isCancelled else {
            isSearchingGalaxy = false
            return
        }

        let index = await accumulator.index

        // Build: locationId → systemId (from first order seen there)
        var stationSystemMap: [Int: Int] = [:]
        var allStationIds = Set<Int>()
        for typeOrders in index.values {
            for (stationId, orders) in typeOrders {
                allStationIds.insert(stationId)
                if stationSystemMap[stationId] == nil, let first = orders.first {
                    stationSystemMap[stationId] = first.systemId
                }
            }
        }

        // Compute item quotes per station (greedy cheapest-fill)
        var rawQuotes: [(locationId: Int, systemId: Int, totalISK: Double, itemQuotes: [ItemQuote])] = []
        for stationId in allStationIds {
            var itemQuotes: [ItemQuote] = []
            var total = 0.0

            for item in input.items {
                let orders = (index[item.typeId]?[stationId] ?? []).sorted { $0.price < $1.price }
                if orders.isEmpty {
                    itemQuotes.append(ItemQuote(typeId: item.typeId, name: item.name,
                        quantity: item.quantity, unitPrice: 0, totalPrice: 0, canFill: false))
                } else {
                    var remaining = item.quantity
                    var cost = 0.0
                    for order in orders {
                        if remaining <= 0 { break }
                        let take = min(remaining, order.volumeRemain)
                        cost += Double(take) * order.price
                        remaining -= take
                    }
                    let canFill = remaining <= 0
                    let unitPrice = (canFill && item.quantity > 0) ? cost / Double(item.quantity) : orders[0].price
                    itemQuotes.append(ItemQuote(typeId: item.typeId, name: item.name,
                        quantity: item.quantity, unitPrice: unitPrice,
                        totalPrice: canFill ? cost : 0, canFill: canFill))
                    if canFill { total += cost }
                }
            }
            rawQuotes.append((locationId: stationId, systemId: stationSystemMap[stationId] ?? 0,
                               totalISK: total, itemQuotes: itemQuotes))
        }

        // Prefer complete stations; fall back to fewest-missing if none
        let complete = rawQuotes.filter { q in q.itemQuotes.allSatisfy { $0.canFill } }
            .sorted { $0.totalISK < $1.totalISK }
        let toResolve = complete.isEmpty
            ? Array(rawQuotes.sorted { lhs, rhs in
                let lm = lhs.itemQuotes.filter { !$0.canFill }.count
                let rm = rhs.itemQuotes.filter { !$0.canFill }.count
                return lm != rm ? lm < rm : lhs.totalISK < rhs.totalISK
              }.prefix(50))
            : Array(complete.prefix(50))

        // Resolve station and system names
        let uniqueStations = Set(toResolve.map(\.locationId))
        let uniqueSystems  = Set(toResolve.map(\.systemId).filter { $0 != 0 })

        async let stationDataTask = resolveStations(ids: uniqueStations)
        async let systemDataTask  = resolveSystems(ids: uniqueSystems)
        let (stationData, systemData) = await (stationDataTask, systemDataTask)

        var finalQuotes: [StationQuote] = []
        for raw in toResolve {
            guard !Task.isCancelled else { break }
            let station  = stationData[raw.locationId]
            let sysId    = station?.systemId ?? raw.systemId
            let sys      = systemData[sysId]
            let name     = station?.name ?? (raw.locationId >= 1_000_000_000 ? "Player Structure" : "Station #\(raw.locationId)")
            let sysName  = sys?.name ?? (sysId > 0 ? "#\(sysId)" : "Unknown")

            finalQuotes.append(StationQuote(locationId: raw.locationId, stationName: name,
                systemName: sysName, regionName: "",
                securityStatus: sys?.securityStatus ?? 0, totalISK: raw.totalISK,
                itemQuotes: raw.itemQuotes))
        }

        quotes = finalQuotes.sorted { a, b in
            if a.isComplete != b.isComplete { return a.isComplete && !b.isComplete }
            return a.totalISK < b.totalISK
        }
        isSearchingGalaxy = false
        selectedQuoteId = quotes.first(where: { $0.isComplete })?.id ?? quotes.first?.id
    }

    private func resolveStations(ids: Set<Int>) async -> [Int: ESIStation] {
        var result: [Int: ESIStation] = [:]
        await withTaskGroup(of: (Int, ESIStation?).self) { group in
            for id in ids where id < 1_000_000_000 {
                group.addTask { (id, await UniverseCache.shared.station(id: id)) }
            }
            for await (id, s) in group { if let s { result[id] = s } }
        }
        return result
    }

    private func resolveSystems(ids: Set<Int>) async -> [Int: ESISolarSystem] {
        var result: [Int: ESISolarSystem] = [:]
        await withTaskGroup(of: (Int, ESISolarSystem?).self) { group in
            for id in ids {
                group.addTask { (id, await UniverseCache.shared.solarSystem(id: id)) }
            }
            for await (id, s) in group { if let s { result[id] = s } }
        }
        return result
    }

    // MARK: Actions

    private func setDestination(locationId: Int) async {
        guard let account = accountManager.selectedAccount else {
            waypointMessage = "No character logged in."
            waypointIsSuccess = false
            return
        }
        waypointMessage = nil
        do {
            let token = try await accountManager.validToken(for: account)
            try await ESIClient.shared.postAction(
                "/ui/autopilot/waypoint/",
                token: token,
                queryItems: [
                    URLQueryItem(name: "add_to_beginning",      value: "false"),
                    URLQueryItem(name: "clear_other_waypoints", value: "true"),
                    URLQueryItem(name: "destination_id",        value: "\(locationId)")
                ]
            )
            waypointMessage = "Destination set in EVE client."
            waypointIsSuccess = true
        } catch ESIError.unauthorized {
            waypointMessage = "Requires esi-ui.write_waypoint.v1 scope."
            waypointIsSuccess = false
        } catch {
            waypointMessage = error.localizedDescription
            waypointIsSuccess = false
        }
    }

    private func copyMultiBuy() {
        let text = input.items
            .filter { !deselectedTypeIds.contains($0.typeId) }
            .map { "\($0.name)\t\($0.quantity)" }
            .joined(separator: "\n")
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    private func securityColor(_ sec: Double) -> Color {
        switch sec {
        case 0.45...: return .green
        case 0.0..<0.45: return .orange
        default: return .red
        }
    }
}

// MARK:  Item Shop Popover

private struct ItemShopPopover: View {
    let item: ItemQuote

    @State private var typeInfo: ESIUniverseType?
    @State private var isLoading = true

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header: icon + name + availability
            HStack(spacing: 12) {
                AsyncImage(url: EVEImageURL.typeIcon(item.typeId, size: 64)) { image in
                    image.resizable().aspectRatio(contentMode: .fit)
                } placeholder: {
                    RoundedRectangle(cornerRadius: 8).fill(.quaternary)
                }
                .frame(width: 64, height: 64)
                .clipShape(RoundedRectangle(cornerRadius: 8))

                VStack(alignment: .leading, spacing: 4) {
                    Text(item.name)
                        .font(.headline)
                        .lineLimit(2)
                    availabilityBadge
                }
                Spacer(minLength: 0)
            }
            .padding(16)

            Divider()

            // Description
            if let desc = typeInfo?.description, !desc.isEmpty {
                Text(desc)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(6)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                Divider()
            } else if isLoading {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("Loading item data…")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                Divider()
            }

            // Stats + pricing grid
            Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 8) {
                GridRow {
                    Text("Qty Needed")
                        .foregroundStyle(.secondary)
                    Text("\(item.quantity)")
                        .fontWeight(.medium)
                }
                if let vol = typeInfo?.packagedVolume ?? typeInfo?.volume {
                    GridRow {
                        Text("Volume")
                            .foregroundStyle(.secondary)
                        Text(formatVolume(vol))
                            .fontWeight(.medium)
                    }
                }
                if let mass = typeInfo?.mass, mass > 0 {
                    GridRow {
                        Text("Mass")
                            .foregroundStyle(.secondary)
                        Text(formatMass(mass))
                            .fontWeight(.medium)
                    }
                }

                Divider()
                    .gridCellUnsizedAxes(.horizontal)
                    .padding(.vertical, 2)

                if item.canFill {
                    GridRow {
                        Text("Unit Price")
                            .foregroundStyle(.secondary)
                        Text(EVEFormatters.formatISK(item.unitPrice))
                            .fontWeight(.medium)
                    }
                    GridRow {
                        Text("Total")
                            .foregroundStyle(.secondary)
                        Text(EVEFormatters.formatISK(item.totalPrice))
                            .fontWeight(.semibold)
                            .foregroundStyle(.green)
                    }
                } else {
                    GridRow {
                        Text("Status")
                            .foregroundStyle(.secondary)
                        Label("Not stocked here", systemImage: "xmark.circle.fill")
                            .foregroundStyle(.orange)
                    }
                }
            }
            .font(.subheadline)
            .padding(16)
        }
        .frame(minWidth: 280, maxWidth: 360)
        .task {
            typeInfo = try? await ESIClient.shared.fetch("/universe/types/\(item.typeId)/")
            isLoading = false
        }
    }

    @ViewBuilder private var availabilityBadge: some View {
        if item.canFill {
            Label("Available", systemImage: "checkmark.circle.fill")
                .font(.caption.bold())
                .foregroundStyle(.green)
        } else {
            Label("Not available", systemImage: "xmark.circle.fill")
                .font(.caption.bold())
                .foregroundStyle(.orange)
        }
    }

    private func formatVolume(_ v: Double) -> String {
        if v < 0.01 { return String(format: "%.4f m³", v) }
        if v < 1    { return String(format: "%.2f m³", v) }
        let fmt = NumberFormatter()
        fmt.numberStyle = .decimal
        fmt.maximumFractionDigits = 2
        return (fmt.string(from: NSNumber(value: v)) ?? String(format: "%.2f", v)) + " m³"
    }

    private func formatMass(_ m: Double) -> String {
        let fmt = NumberFormatter()
        fmt.numberStyle = .decimal
        fmt.maximumFractionDigits = 0
        return (fmt.string(from: NSNumber(value: m)) ?? String(format: "%.0f", m)) + " kg"
    }
}

// MARK:  Thread-safe order accumulator

private actor GalaxyOrderAccumulator {
    private(set) var index: [Int: [Int: [ESIRegionMarketOrder]]] = [:]

    func add(typeId: Int, orders: [ESIRegionMarketOrder]) {
        for order in orders where !order.isBuyOrder {
            index[typeId, default: [:]][order.locationId, default: []].append(order)
        }
    }
}
