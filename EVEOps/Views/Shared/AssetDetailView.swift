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

struct AssetDetailView: View {
    let asset: ResolvedAsset
    @State private var typeInfo: ESIType?
    @State private var groupName: String?
    @State private var categoryName: String?
    @State private var marketGroupName: String?
    @State private var isLoading = true
    @State private var jitaSellPrice: Double?
    @State private var jitaBuyPrice: Double?
    @State private var sellOrders: [ESIRegionMarketOrder] = []
    @State private var buyOrders: [ESIRegionMarketOrder] = []
    @State private var adjustedPrice: Double?
    @State private var averagePrice: Double?
    @State private var orderSystemNames: [Int: String] = [:]
    @State private var showMarketPopover = false
    @State private var fuzzworkPrice: FuzzworkPrice?
    @State private var isAppraising = false
    @State private var stationTypeId: Int?

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                // Header: render + icon + name
                headerSection

                VStack(alignment: .leading, spacing: 16) {
                    // Asset-specific info
                    assetInfoSection

                    Divider()

                    // Janice appraisal
                    janiceSection

                    // Market value
                    if jitaSellPrice != nil || jitaBuyPrice != nil {
                        Divider()
                        marketValueSection
                    }

                    // Type attributes
                    if let typeInfo {
                        typeAttributesSection(typeInfo)

                        if let desc = typeInfo.description, !desc.isEmpty {
                            Divider()
                            descriptionSection(desc)
                        }
                    }
                }
                .padding()
            }
        }
        .frame(minWidth: 280, idealWidth: 320)
        .task(id: asset.itemId) { await loadTypeInfo() }
        .task(id: asset.typeId) { await loadMarketPrice() }
    }

    // MARK:  Header

    private var headerSection: some View {
        ZStack(alignment: .bottom) {
            AsyncImage(url: EVEImageURL.typeRender(stationTypeId ?? asset.typeId, size: 1024)) { phase in
                if let image = phase.image {
                    image
                        .resizable()
                        .scaledToFill()
                        .frame(maxWidth: .infinity, maxHeight: 200)
                        .clipped()
                } else {
                    // Render not available (most non-ship items); show large icon instead
                    Rectangle()
                        .fill(Color(white: 0.1))
                        .frame(maxWidth: .infinity, minHeight: 200, maxHeight: 200)
                        .overlay {
                            AsyncImage(url: EVEImageURL.typeIcon(stationTypeId ?? asset.typeId, size: 256)) { iconPhase in
                                if let icon = iconPhase.image {
                                    icon.resizable()
                                        .interpolation(.high)
                                        .scaledToFit()
                                        .padding(36)
                                } else if iconPhase.error != nil {
                                    Image(systemName: "cube.box.fill")
                                        .font(.system(size: 48))
                                        .foregroundStyle(.quaternary)
                                } else {
                                    ProgressView().scaleEffect(0.8)
                                }
                            }
                        }
                }
            }

            // Name overlay at bottom
            VStack(alignment: .leading, spacing: 2) {
                Text(asset.typeName)
                    .font(.headline)
                    .foregroundStyle(.white)
                if let groupName {
                    Text(groupName)
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.7))
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .background(.ultraThinMaterial.opacity(0.8))
        }
    }

    // MARK:  Asset Info

    private var assetInfoSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Asset Details")
                .font(.subheadline.bold())
                .foregroundStyle(.secondary)

            if let name = asset.customName {
                infoRow(label: "Custom Name", value: name)
            }
            infoRow(label: "Quantity", value: "\(asset.quantity)")
            infoRow(label: "Location", value: asset.locationName)
            infoRow(label: "Location Flag", value: formatLocationFlag(asset.locationFlag))

            if asset.isBlueprintCopy {
                infoRow(label: "Blueprint", value: "Copy (BPC)")
            }
            if asset.isSingleton {
                infoRow(label: "Assembled", value: "Yes")
            }

            infoRow(label: "Type ID", value: "\(asset.typeId)")
            infoRow(label: "Item ID", value: "\(asset.itemId)")
        }
    }

    // MARK:  Market Value

    private var marketValueSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label("Market Value (Jita)", systemImage: "storefront")
                    .font(.subheadline.bold())
                    .foregroundStyle(.secondary)
                Spacer()
                Button {
                    showMarketPopover = true
                } label: {
                    Label("Orders", systemImage: "list.bullet.rectangle")
                        .font(.caption)
                }
                .buttonStyle(.bordered)
                .controlSize(.mini)
                .popover(isPresented: $showMarketPopover, arrowEdge: .leading) {
                    MarketOrdersPopover(
                        typeName: asset.typeName,
                        quantity: asset.quantity,
                        sellOrders: sellOrders,
                        buyOrders: buyOrders,
                        adjustedPrice: adjustedPrice,
                        averagePrice: averagePrice,
                        systemNames: orderSystemNames
                    )
                }
            }

            if let sell = jitaSellPrice {
                infoRow(label: "Sell (min)", value: EVEFormatters.formatISK(sell))
                if asset.quantity > 1 {
                    infoRow(label: "Total (\(asset.quantity)x)",
                            value: EVEFormatters.formatISK(sell * Double(asset.quantity)))
                }
            }
            if let buy = jitaBuyPrice {
                infoRow(label: "Buy (max)", value: EVEFormatters.formatISK(buy))
            }
            Text("Jita (The Forge) best orders")
                .font(.caption2).foregroundStyle(.tertiary)
        }
    }

    // MARK:  Type Attributes

    private func typeAttributesSection(_ type: ESIType) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Type Information")
                .font(.subheadline.bold())
                .foregroundStyle(.secondary)

            if let categoryName {
                infoRow(label: "Category", value: categoryName)
            }
            if let groupName {
                infoRow(label: "Group", value: groupName)
            }
            if let marketGroupName {
                infoRow(label: "Market Group", value: marketGroupName)
            }
            if let volume = type.volume, volume > 0 {
                infoRow(label: "Volume", value: String(format: "%.2f m\u{00B3}", volume))
            }
            if let packagedVolume = type.packagedVolume, packagedVolume > 0, packagedVolume != type.volume {
                infoRow(label: "Packaged Volume", value: String(format: "%.2f m\u{00B3}", packagedVolume))
            }
            if let mass = type.mass, mass > 0 {
                infoRow(label: "Mass", value: formatLargeNumber(mass) + " kg")
            }
            if let capacity = type.capacity, capacity > 0 {
                infoRow(label: "Capacity", value: String(format: "%.0f m\u{00B3}", capacity))
            }
            if let radius = type.radius, radius > 0 {
                infoRow(label: "Radius", value: formatLargeNumber(radius) + " m")
            }
            if let portionSize = type.portionSize, portionSize > 1 {
                infoRow(label: "Portion Size", value: "\(portionSize)")
            }

            // Total volume for stacked items
            if asset.quantity > 1, let vol = type.packagedVolume ?? type.volume, vol > 0 {
                let total = vol * Double(asset.quantity)
                infoRow(label: "Total Volume", value: String(format: "%.2f m\u{00B3}", total))
            }
        }
    }

    // MARK:  Description

    private func descriptionSection(_ description: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Description")
                .font(.subheadline.bold())
                .foregroundStyle(.secondary)

            Text(description.strippingEVEMarkup)
                .font(.caption)
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
        }
    }

    // MARK:  Helpers

    private func infoRow(label: String, value: String) -> some View {
        HStack(alignment: .top) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 110, alignment: .trailing)
            Text(value)
                .font(.caption)
                .textSelection(.enabled)
            Spacer()
        }
    }

    private func formatLocationFlag(_ flag: String) -> String {
        // Convert camelCase ESI flags to readable text
        switch flag {
        case "Hangar": return "Hangar"
        case "AssetSafety": return "Asset Safety"
        case "Deliveries": return "Deliveries"
        case "HangarAll": return "Hangar (All)"
        case "Cargo": return "Cargo Hold"
        case "DroneBay": return "Drone Bay"
        case "FighterBay": return "Fighter Bay"
        case "FleetHangar": return "Fleet Hangar"
        case "ShipHangar": return "Ship Hangar"
        case "SpecializedOreHold": return "Ore Hold"
        case "SpecializedFuelBay": return "Fuel Bay"
        case "SpecializedAmmoHold": return "Ammo Hold"
        case "SpecializedMineralHold": return "Mineral Hold"
        case "SpecializedSalvageHold": return "Salvage Hold"
        case "SpecializedShipHold": return "Ship Hold"
        case "SpecializedSmallShipHold": return "Small Ship Hold"
        case "SpecializedMediumShipHold": return "Medium Ship Hold"
        case "SpecializedLargeShipHold": return "Large Ship Hold"
        case "SpecializedIndustrialShipHold": return "Industrial Ship Hold"
        case "SpecializedCommandCenterHold": return "Command Center Hold"
        case "SpecializedPlanetaryCommoditiesHold": return "Planetary Commodities Hold"
        case "SpecializedMaterialBay": return "Material Bay"
        case "CorpSAG1": return "Corp Hangar 1"
        case "CorpSAG2": return "Corp Hangar 2"
        case "CorpSAG3": return "Corp Hangar 3"
        case "CorpSAG4": return "Corp Hangar 4"
        case "CorpSAG5": return "Corp Hangar 5"
        case "CorpSAG6": return "Corp Hangar 6"
        case "CorpSAG7": return "Corp Hangar 7"
        case "CorpDeliveries": return "Corp Deliveries"
        case "Implant": return "Implant"
        case "BoosterBay": return "Booster Bay"
        case "SubSystemSlot0": return "Subsystem Slot 1"
        case "SubSystemSlot1": return "Subsystem Slot 2"
        case "SubSystemSlot2": return "Subsystem Slot 3"
        case "SubSystemSlot3": return "Subsystem Slot 4"
        case "LoSlot0", "LoSlot1", "LoSlot2", "LoSlot3", "LoSlot4", "LoSlot5", "LoSlot6", "LoSlot7":
            let slot = flag.last.map(String.init) ?? "?"
            return "Low Slot \(Int(slot)! + 1)"
        case "MedSlot0", "MedSlot1", "MedSlot2", "MedSlot3", "MedSlot4", "MedSlot5", "MedSlot6", "MedSlot7":
            let slot = flag.last.map(String.init) ?? "?"
            return "Mid Slot \(Int(slot)! + 1)"
        case "HiSlot0", "HiSlot1", "HiSlot2", "HiSlot3", "HiSlot4", "HiSlot5", "HiSlot6", "HiSlot7":
            let slot = flag.last.map(String.init) ?? "?"
            return "High Slot \(Int(slot)! + 1)"
        case "RigSlot0", "RigSlot1", "RigSlot2":
            let slot = flag.last.map(String.init) ?? "?"
            return "Rig Slot \(Int(slot)! + 1)"
        default:
            return flag
        }
    }

    private func formatLargeNumber(_ value: Double) -> String {
        if value >= 1_000_000_000 {
            return String(format: "%.2fB", value / 1_000_000_000)
        } else if value >= 1_000_000 {
            return String(format: "%.2fM", value / 1_000_000)
        } else if value >= 1_000 {
            return String(format: "%.1fK", value / 1_000)
        }
        return String(format: "%.0f", value)
    }

    // MARK:  Market Appraisal

    private var janiceSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Appraisal (Jita)", systemImage: "tag.fill")
                .font(.subheadline.bold())
                .foregroundStyle(.secondary)

            if isAppraising {
                HStack(spacing: 6) {
                    ProgressView().controlSize(.small)
                    Text("Fetching appraisal…")
                        .font(.caption).foregroundStyle(.secondary)
                }
            } else if let price = fuzzworkPrice {
                let qty = Double(asset.quantity)
                infoRow(label: "Sell (immediate)", value: EVEFormatters.formatISK(price.buyMax * qty))
                infoRow(label: "Sell (listing)", value: EVEFormatters.formatISK(price.sellMin * qty))
                if asset.quantity > 1 {
                    infoRow(label: "Per unit", value: EVEFormatters.formatISK(price.buyMax))
                }
                Text("via Fuzzwork · Jita buy orders")
                    .font(.caption2).foregroundStyle(.tertiary)
            } else {
                Text("No appraisal available")
                    .font(.caption).foregroundStyle(.tertiary)
            }
        }
    }

    private func loadMarketPrice() async {
        fuzzworkPrice = nil
        isAppraising = true
        fuzzworkPrice = try? await FuzzworkClient.shared.prices(typeIds: [asset.typeId])[asset.typeId]
        isAppraising = false
    }

    // MARK:  Market Orders Popover

    private struct MarketOrdersPopover: View {
        let typeName: String
        let quantity: Int
        let sellOrders: [ESIRegionMarketOrder]
        let buyOrders: [ESIRegionMarketOrder]
        let adjustedPrice: Double?
        let averagePrice: Double?
        let systemNames: [Int: String]

        var body: some View {
            VStack(alignment: .leading, spacing: 0) {
                // Header
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(typeName)
                            .font(.headline)
                        Text("Jita / The Forge — Market Orders")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                }
                .padding()
                .background(.regularMaterial)

                Divider()

                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        // ESI reference prices
                        if adjustedPrice != nil || averagePrice != nil {
                            VStack(alignment: .leading, spacing: 6) {
                                Text("Reference Prices")
                                    .font(.caption.bold())
                                    .foregroundStyle(.secondary)
                                if let avg = averagePrice {
                                    priceRow(label: "ESI Average", value: avg, quantity: quantity, color: .primary)
                                }
                                if let adj = adjustedPrice {
                                    priceRow(label: "ESI Adjusted", value: adj, quantity: quantity, color: .secondary)
                                }
                            }

                            Divider()
                        }

                        // Sell orders
                        if !sellOrders.isEmpty {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Sell Orders (cheapest first)")
                                    .font(.caption.bold())
                                    .foregroundStyle(.secondary)
                                ForEach(sellOrders) { order in
                                    orderRow(order: order, isSell: true)
                                }
                            }

                            Divider()
                        }

                        // Buy orders
                        if !buyOrders.isEmpty {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Buy Orders (highest first)")
                                    .font(.caption.bold())
                                    .foregroundStyle(.secondary)
                                ForEach(buyOrders) { order in
                                    orderRow(order: order, isSell: false)
                                }
                            }
                        }

                        if sellOrders.isEmpty && buyOrders.isEmpty {
                            ContentUnavailableView("No Market Orders",
                                systemImage: "cart.badge.minus",
                                description: Text("No active orders in Jita"))
                        }
                    }
                    .padding()
                }
            }
            .frame(width: 360, height: 440)
        }

        private func priceRow(label: String, value: Double, quantity: Int, color: Color) -> some View {
            HStack {
                Text(label)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(width: 110, alignment: .trailing)
                VStack(alignment: .leading, spacing: 1) {
                    Text(EVEFormatters.formatISK(value))
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(color)
                    if quantity > 1 {
                        Text("Total: \(EVEFormatters.formatISK(value * Double(quantity)))")
                            .font(.caption2.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
            }
        }

        private func orderRow(order: ESIRegionMarketOrder, isSell: Bool) -> some View {
            HStack(spacing: 8) {
                Circle()
                    .fill(isSell ? Color.red.opacity(0.7) : Color.green.opacity(0.7))
                    .frame(width: 6, height: 6)

                VStack(alignment: .leading, spacing: 1) {
                    Text(systemNames[order.systemId] ?? "System \(order.systemId)")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Text("Vol: \(order.volumeRemain.formatted())")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
                .frame(width: 120, alignment: .leading)

                Spacer()

                Text(EVEFormatters.formatISK(order.price))
                    .font(.caption.monospacedDigit().bold())
                    .foregroundStyle(isSell ? .red : .green)
            }
            .padding(.vertical, 2)
        }
    }


    // MARK:  Data Loading

    private func loadTypeInfo() async {
        isLoading = true
        stationTypeId = nil
        jitaSellPrice = nil
        jitaBuyPrice = nil
        sellOrders = []
        buyOrders = []
        adjustedPrice = nil
        averagePrice = nil
        orderSystemNames = [:]
        do {
            guard let type = await UniverseCache.shared.type(id: asset.typeId) else {
                throw ESIError.noData
            }
            typeInfo = type

            // Fetch Jita market prices + ESI average prices in parallel
            async let fetchSells: [ESIRegionMarketOrder] = (try? ESIClient.shared.fetch(
                "/markets/10000002/orders/?order_type=sell&type_id=\(asset.typeId)"
            )) ?? []
            async let fetchBuys: [ESIRegionMarketOrder] = (try? ESIClient.shared.fetch(
                "/markets/10000002/orders/?order_type=buy&type_id=\(asset.typeId)"
            )) ?? []
            async let fetchPrices: [ESIMarketPrice] = (try? ESIClient.shared.fetch("/markets/prices/")) ?? []
            let (sells, buys, prices) = await (fetchSells, fetchBuys, fetchPrices)

            jitaSellPrice = sells.map(\.price).min()
            jitaBuyPrice = buys.map(\.price).max()

            // Store top orders for the popover
            sellOrders = Array(sells.sorted { $0.price < $1.price }.prefix(8))
            buyOrders = Array(buys.sorted { $0.price > $1.price }.prefix(8))

            // Store average/adjusted prices
            if let priceEntry = prices.first(where: { $0.typeId == asset.typeId }) {
                adjustedPrice = priceEntry.adjustedPrice
                averagePrice = priceEntry.averagePrice
            }

            // Resolve system names for top orders
            let systemIDs = Array(Set((sellOrders + buyOrders).map(\.systemId)))
            let resolved = await NameResolver.shared.resolve(ids: systemIDs)
            orderSystemNames = resolved

            // Load group info
            if let group = await UniverseCache.shared.group(id: type.groupId) {
                groupName = group.name

                // Load category info
                let category: ESICategory? = try? await ESIClient.shared.fetch("/universe/categories/\(group.categoryId)/")
                categoryName = category?.name
            }

            // Load market group if available
            if let mgID = type.marketGroupId {
                let mg: ESIMarketGroup? = try? await ESIClient.shared.fetch("/universe/market_groups/\(mgID)/")
                marketGroupName = mg?.name
            }
        } catch {
            // Partial info is fine
        }

        // For office assets the header image should show the containing station,
        // not the generic office type icon.
        if asset.locationFlag == "OfficeFolder",
           let station = await UniverseCache.shared.station(id: asset.locationId) {
            stationTypeId = station.typeId
        }

        isLoading = false
    }
}
