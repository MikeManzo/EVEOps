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

// MARK:  Market Hub

/// Reference market used to price offer rewards and required turn-in items.
/// Region-wide aggregates (not single-station), matching how `FuzzworkClient` already works.
private enum LPMarketHub: String, CaseIterable, Identifiable, Codable {
    case jita, amarr, dodixie, rens, hek

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .jita:    "Jita"
        case .amarr:   "Amarr"
        case .dodixie: "Dodixie"
        case .rens:    "Rens"
        case .hek:     "Hek"
        }
    }

    /// Region containing this hub's trade station.
    var regionId: Int {
        switch self {
        case .jita:    10000002 // The Forge
        case .amarr:   10000043 // Domain
        case .dodixie: 10000032 // Sinq Laison
        case .rens:    10000030 // Heimatar
        case .hek:     10000042 // Metropolis
        }
    }
}

// MARK:  Local Models

private struct ResolvedLPOffer: Identifiable {
    let offer: ESILPStoreOffer
    let typeName: String
    var marketSell: Double?
    /// Which hub `marketSell` was found at. Only set when priced via the galaxy-wide
    /// scan (`fetchLPStoreOffersAcrossHubs`); nil for the single-hub browse path.
    var bestSellHub: LPMarketHub?
    /// Market cost of items that must be turned in alongside LP/ISK, priced at the selected hub's sell price.
    /// Nil until priced; nil is treated as "unknown," not "free," when requiredItems is non-empty.
    var requiredItemsCost: Double?
    var id: Int { offer.offerId }

    /// Net ISK gained per exchange: (marketSell × qty) − iskCost − requiredItemsCost
    var netISK: Double? {
        guard let marketSell else { return nil }
        if !offer.requiredItems.isEmpty && requiredItemsCost == nil { return nil }
        let reqCost = requiredItemsCost ?? 0
        return (marketSell * Double(offer.quantity)) - Double(offer.iskCost) - reqCost
    }

    /// ISK earned per LP spent
    var iskPerLP: Double? {
        guard let net = netISK, net > 0, offer.lpCost > 0 else { return nil }
        return net / Double(offer.lpCost)
    }

    /// Same as `iskPerLP` but includes break-even/unprofitable offers (may be ≤ 0).
    /// Used to rank "closest to profitable" when nothing actually clears the bar.
    var rawISKPerLP: Double? {
        guard let net = netISK, offer.lpCost > 0 else { return nil }
        return net / Double(offer.lpCost)
    }
}

private struct AgentStation: Identifiable {
    let locationId: Int
    let stationName: String
    var id: Int { locationId }
}

private struct LPStoreOfferBundle {
    var offers: [ResolvedLPOffer]
    var requiredItemNames: [Int: String]
}

/// Fetches a corp's LP store offers, resolves names, and prices both the reward
/// items and any required turn-in items — against `regionId` — so `netISK`/`iskPerLP`
/// reflect the full cost at whichever hub the user has selected.
private func fetchLPStoreOffers(for corpId: Int, regionId: Int) async throws -> LPStoreOfferBundle {
    let raw: [ESILPStoreOffer] = try await ESIClient.shared.fetch("/loyalty/stores/\(corpId)/offers/")

    let offerTypeIds = Array(Set(raw.map(\.typeId)))
    let reqTypeIds   = Array(Set(raw.flatMap { $0.requiredItems.map(\.typeId) }))
    let allTypeIds   = Array(Set(offerTypeIds + reqTypeIds))
    let names        = await NameResolver.shared.resolve(ids: allTypeIds)

    let requiredItemNames = Dictionary(
        uniqueKeysWithValues: reqTypeIds.compactMap { id -> (Int, String)? in
            guard let name = names[id] else { return nil }
            return (id, name)
        }
    )

    var resolved = raw.map { offer in
        ResolvedLPOffer(offer: offer, typeName: names[offer.typeId] ?? "Item #\(offer.typeId)")
    }

    if !allTypeIds.isEmpty, let prices = try? await FuzzworkClient.shared.prices(typeIds: allTypeIds, regionId: regionId) {
        for i in resolved.indices {
            let tid = resolved[i].offer.typeId
            resolved[i].marketSell = prices[tid]?.sellPercentile

            let reqItems = resolved[i].offer.requiredItems
            if !reqItems.isEmpty {
                var total = 0.0
                var allKnown = true
                for req in reqItems {
                    guard let p = prices[req.typeId]?.sellPercentile else { allKnown = false; break }
                    total += p * Double(req.quantity)
                }
                resolved[i].requiredItemsCost = allKnown ? total : nil
            }
        }
    }

    return LPStoreOfferBundle(
        offers: resolved.sorted { ($0.iskPerLP ?? -1) > ($1.iskPerLP ?? -1) },
        requiredItemNames: requiredItemNames
    )
}

/// Same as `fetchLPStoreOffers`, but instead of pricing against a single hub, queries all
/// five major trade hubs concurrently and picks the best price per item — the actual
/// "checking across the galaxy" the Optimize feature is meant to do. Reward items are priced
/// at whichever hub pays the most (`marketSell`/`bestSellHub`); required turn-in items are
/// priced at whichever hub sells them cheapest, since that minimizes cost.
private func fetchLPStoreOffersAcrossHubs(for corpId: Int) async throws -> LPStoreOfferBundle {
    let raw: [ESILPStoreOffer] = try await ESIClient.shared.fetch("/loyalty/stores/\(corpId)/offers/")

    let offerTypeIds = Array(Set(raw.map(\.typeId)))
    let reqTypeIds   = Array(Set(raw.flatMap { $0.requiredItems.map(\.typeId) }))
    let allTypeIds   = Array(Set(offerTypeIds + reqTypeIds))
    let names        = await NameResolver.shared.resolve(ids: allTypeIds)

    let requiredItemNames = Dictionary(
        uniqueKeysWithValues: reqTypeIds.compactMap { id -> (Int, String)? in
            guard let name = names[id] else { return nil }
            return (id, name)
        }
    )

    var resolved = raw.map { offer in
        ResolvedLPOffer(offer: offer, typeName: names[offer.typeId] ?? "Item #\(offer.typeId)")
    }

    if !allTypeIds.isEmpty {
        // Fetch every hub's prices for the full type list in parallel.
        let perHub: [(hub: LPMarketHub, prices: [Int: FuzzworkPrice])] = await withTaskGroup(
            of: (LPMarketHub, [Int: FuzzworkPrice]).self
        ) { group in
            for hub in LPMarketHub.allCases {
                group.addTask {
                    let prices = (try? await FuzzworkClient.shared.prices(typeIds: allTypeIds, regionId: hub.regionId)) ?? [:]
                    return (hub, prices)
                }
            }
            var results: [(LPMarketHub, [Int: FuzzworkPrice])] = []
            for await result in group { results.append(result) }
            return results
        }

        // Per type: best (highest) sell price for reward items, cheapest for required items.
        var bestSell: [Int: (price: Double, hub: LPMarketHub)] = [:]
        var cheapestBuy: [Int: Double] = [:]
        for (hub, prices) in perHub {
            for (typeId, price) in prices {
                if bestSell[typeId] == nil || price.sellPercentile > bestSell[typeId]!.price {
                    bestSell[typeId] = (price.sellPercentile, hub)
                }
                if cheapestBuy[typeId] == nil || price.sellPercentile < cheapestBuy[typeId]! {
                    cheapestBuy[typeId] = price.sellPercentile
                }
            }
        }

        for i in resolved.indices {
            let tid = resolved[i].offer.typeId
            resolved[i].marketSell = bestSell[tid]?.price
            resolved[i].bestSellHub = bestSell[tid]?.hub

            let reqItems = resolved[i].offer.requiredItems
            if !reqItems.isEmpty {
                var total = 0.0
                var allKnown = true
                for req in reqItems {
                    guard let p = cheapestBuy[req.typeId] else { allKnown = false; break }
                    total += p * Double(req.quantity)
                }
                resolved[i].requiredItemsCost = allKnown ? total : nil
            }
        }
    }

    return LPStoreOfferBundle(
        offers: resolved.sorted { ($0.iskPerLP ?? -1) > ($1.iskPerLP ?? -1) },
        requiredItemNames: requiredItemNames
    )
}

// MARK:  Private Formatting Helpers

private func lpFormatLP(_ value: Int) -> String {
    if value >= 1_000_000 { return String(format: "%.1fM", Double(value) / 1_000_000) }
    if value >= 1_000 { return String(format: "%.0fK", Double(value) / 1_000) }
    return "\(value)"
}

private func lpFormatISKPerLP(_ value: Double) -> String {
    if value >= 1_000_000 { return String(format: "%.1fM", value / 1_000_000) }
    if value >= 1_000 { return String(format: "%.0fK", value / 1_000) }
    return String(format: "%.0f", value)
}

private func lpISKPerLPColor(_ value: Double) -> Color {
    if value >= 1500 { return .green }
    if value >= 800  { return Color(hue: 0.25, saturation: 0.8, brightness: 0.75) }
    if value >= 400  { return .orange }
    return .red
}

// MARK:  EverMarks (Paragon)

/// Paragon is the NPC corporation whose loyalty points are branded in-game as "EverMarks" —
/// mostly ship/corp emblems and SKINs. Some SKINs *are* tradeable and carry real ISK value,
/// so pricing/optimization run the same as any other corp; `isEverMarks` is now only used for
/// cosmetic labeling ("EM" vs "LP", icon/color). Items with no market simply price as unknown,
/// the same way any illiquid item does elsewhere in this view.
private let paragonCorporationId = 1000419

private func lpCurrencyLabel(isEverMarks: Bool) -> String { isEverMarks ? "EM" : "LP" }
private func lpCurrencyIcon(isEverMarks: Bool) -> String { isEverMarks ? "sparkles" : "medal.fill" }
private func lpCurrencyColor(isEverMarks: Bool) -> Color { isEverMarks ? .purple : .yellow }

// MARK:  Image Views

private enum LPStoreImageCache {
    static let items = NSCache<NSNumber, NSImage>()
    static let corps = NSCache<NSNumber, NSImage>()
}

private struct LPTypeImage: View {
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
            if let cached = LPStoreImageCache.items.object(forKey: NSNumber(value: typeId)) {
                image = cached; return
            }
            image = nil; failed = false
            for urlOpt in [EVEImageURL.typeRender(typeId, size: 64), EVEImageURL.typeIcon(typeId, size: 64)] {
                guard let url = urlOpt,
                      let (data, resp) = try? await URLSession.shared.data(from: url),
                      (resp as? HTTPURLResponse)?.statusCode == 200,
                      let img = NSImage(data: data) else { continue }
                LPStoreImageCache.items.setObject(img, forKey: NSNumber(value: typeId))
                image = img
                return
            }
            failed = true
        }
    }
}

private struct CorpLogoImage: View {
    let corpId: Int
    let size: CGFloat

    @State private var image: NSImage?
    @State private var failed = false

    var body: some View {
        Group {
            if let image {
                Image(nsImage: image).resizable().scaledToFit()
            } else if failed {
                Image(systemName: "building.2")
                    .font(.system(size: size * 0.45))
                    .foregroundStyle(.tertiary)
            } else {
                RoundedRectangle(cornerRadius: size * 0.2).fill(.quaternary)
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: size * 0.2))
        .task(id: corpId) {
            if let cached = LPStoreImageCache.corps.object(forKey: NSNumber(value: corpId)) {
                image = cached; return
            }
            image = nil; failed = false
            guard let url = EVEImageURL.corporationLogo(corpId, size: 64),
                  let (data, resp) = try? await URLSession.shared.data(from: url),
                  (resp as? HTTPURLResponse)?.statusCode == 200,
                  let img = NSImage(data: data) else { failed = true; return }
            LPStoreImageCache.corps.setObject(img, forKey: NSNumber(value: corpId))
            image = img
        }
    }
}

// MARK:  Corp Holding Row (Left Panel)

private struct CorpHoldingRow: View {
    let corp: ResolvedLoyaltyPoints
    let isEverMarks: Bool
    let isSelected: Bool

    @State private var showSpendPlan = false

    var body: some View {
        HStack(spacing: 10) {
            CorpLogoImage(corpId: corp.corporationId, size: 38)

            VStack(alignment: .leading, spacing: 3) {
                Text(corp.corporationName)
                    .font(.subheadline.bold())
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: 3) {
                    Image(systemName: lpCurrencyIcon(isEverMarks: isEverMarks))
                        .font(.system(size: 9))
                        .foregroundStyle(lpCurrencyColor(isEverMarks: isEverMarks))
                    Text(lpFormatLP(corp.loyaltyPoints) + " " + lpCurrencyLabel(isEverMarks: isEverMarks))
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }

            Spacer(minLength: 4)

            if corp.loyaltyPoints > 0 {
                Button {
                    showSpendPlan = true
                } label: {
                    Image(systemName: "wand.and.stars")
                        .font(.system(size: 12))
                        // accentColor washes out against the selection highlight,
                        // which is also blue — switch to white when the row is selected.
                        .foregroundStyle(isSelected ? .white : Color.accentColor)
                }
                .buttonStyle(.plain)
                .help("Optimize LP spend for maximum ISK")
                .popover(isPresented: $showSpendPlan, arrowEdge: .trailing) {
                    LPSpendPlanPopover(corp: corp)
                }
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK:  Offer Detail Popover

private struct LPOfferDetailPopover: View {
    let resolved: ResolvedLPOffer
    let requiredItemNames: [Int: String]
    let isEverMarks: Bool
    let hubName: String
    let showPricing: Bool

    private var offer: ESILPStoreOffer { resolved.offer }

    @State private var typeInfo: ESIType?
    @State private var groupName: String?
    @State private var categoryName: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {

                // Header — large thumbnail + name + classification
                HStack(alignment: .top, spacing: 12) {
                    LPTypeImage(typeId: offer.typeId, size: 72)
                        .shadow(color: .black.opacity(0.2), radius: 4, x: 0, y: 2)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(resolved.typeName)
                            .font(.headline)
                            .fixedSize(horizontal: false, vertical: true)
                        if let cat = categoryName, let grp = groupName {
                            Text("\(cat) › \(grp)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        } else if let grp = groupName {
                            Text(grp)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        } else {
                            Text("Type #\(offer.typeId)")
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                        }
                        Text("Offer #\(offer.offerId)")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                    Spacer(minLength: 0)
                }
                .padding(16)

                // Physical properties row (volume / portion size)
                let hasVolume   = (typeInfo?.volume ?? 0) > 0
                let hasPortion  = (typeInfo?.portionSize ?? 1) > 1
                if hasVolume || hasPortion {
                    HStack(spacing: 12) {
                        if hasVolume, let vol = typeInfo?.volume {
                            Label(String(format: "%.2f m³", vol), systemImage: "cube")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        if hasPortion, let ps = typeInfo?.portionSize {
                            Label("Portion: \(ps)", systemImage: "square.stack.3d.up")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 10)
                }

                Divider()

                // Description
                if let desc = typeInfo?.description, !desc.isEmpty {
                    VStack(alignment: .leading, spacing: 2) {
                        sectionLabel("DESCRIPTION")
                        Text(desc.strippingEVEMarkup)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                            .textSelection(.enabled)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 4)
                    }
                    .padding(.bottom, 6)
                    Divider()
                } else if typeInfo == nil {
                    HStack {
                        ProgressView().scaleEffect(0.7)
                        Text("Loading item details…")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    Divider()
                }

                // Exchange Cost
                VStack(alignment: .leading, spacing: 2) {
                    sectionLabel("EXCHANGE COST")
                    detailRow(isEverMarks ? "EverMarks Cost" : "LP Cost") {
                        HStack(spacing: 4) {
                            Image(systemName: lpCurrencyIcon(isEverMarks: isEverMarks))
                                .font(.caption)
                                .foregroundStyle(lpCurrencyColor(isEverMarks: isEverMarks))
                            Text(lpFormatLP(offer.lpCost) + " " + lpCurrencyLabel(isEverMarks: isEverMarks))
                                .foregroundStyle(Color(hue: 0.13, saturation: 0.85, brightness: 0.9))
                                .fontWeight(.semibold)
                        }
                    }
                    if showPricing {
                        detailRow("ISK Cost") {
                            Text(offer.iskCost > 0
                                 ? EVEFormatters.formatISK(Double(offer.iskCost))
                                 : "—")
                                .foregroundStyle(.secondary)
                        }
                    }
                    if let ak = offer.akCost {
                        detailRow("AK Cost") {
                            Text("\(ak) AK").foregroundStyle(.secondary)
                        }
                    }
                    if !offer.requiredItems.isEmpty {
                        detailRow("Required Items") {
                            if let reqCost = resolved.requiredItemsCost {
                                Text(EVEFormatters.formatISK(reqCost)).foregroundStyle(.secondary)
                            } else {
                                Text("Loading…").foregroundStyle(.tertiary)
                            }
                        }
                    }
                }
                .padding(.bottom, 8)

                Divider()

                // Reward
                VStack(alignment: .leading, spacing: 2) {
                    sectionLabel("REWARD")
                    detailRow("Quantity") {
                        Text("×\(offer.quantity)").foregroundStyle(.primary)
                    }
                    if showPricing {
                        if let sell = resolved.marketSell {
                            detailRow("\(hubName) Sell") {
                                Text(EVEFormatters.formatISK(sell)).foregroundStyle(.green)
                            }
                            if offer.quantity > 1 {
                                detailRow("Total Value") {
                                    Text(EVEFormatters.formatISK(sell * Double(offer.quantity)))
                                        .foregroundStyle(.green)
                                }
                            }
                            if let net = resolved.netISK {
                                detailRow("Net ISK") {
                                    Text((net >= 0 ? "+" : "") + EVEFormatters.formatISK(net))
                                        .foregroundStyle(net >= 0 ? .green : .red)
                                        .fontWeight(.semibold)
                                }
                            }
                        } else {
                            detailRow("\(hubName) Sell") {
                                Text("No market data").foregroundStyle(.tertiary)
                            }
                        }
                    }
                }
                .padding(.bottom, 8)

                // ISK/LP badge
                if showPricing, let iskLP = resolved.iskPerLP {
                    let color = lpISKPerLPColor(iskLP)
                    HStack {
                        Spacer()
                        VStack(spacing: 2) {
                            Text(lpFormatISKPerLP(iskLP))
                                .font(.title2.bold().monospacedDigit())
                                .foregroundStyle(.white)
                            Text("ISK / LP")
                                .font(.caption2.bold())
                                .foregroundStyle(.white.opacity(0.75))
                        }
                        .padding(.horizontal, 20)
                        .padding(.vertical, 10)
                        .background(color, in: RoundedRectangle(cornerRadius: 12))
                        .shadow(color: color.opacity(0.45), radius: 6, x: 0, y: 2)
                        Spacer()
                    }
                    .padding(.vertical, 12)
                }

                // Required items
                if !offer.requiredItems.isEmpty {
                    Divider()
                    VStack(alignment: .leading, spacing: 2) {
                        sectionLabel("REQUIRED ITEMS (\(offer.requiredItems.count))")
                        ForEach(offer.requiredItems, id: \.typeId) { item in
                            HStack(spacing: 8) {
                                Text("×\(item.quantity)")
                                    .font(.caption.monospacedDigit())
                                    .foregroundStyle(.secondary)
                                    .frame(width: 44, alignment: .trailing)
                                Text(requiredItemNames[item.typeId] ?? "Item #\(item.typeId)")
                                    .font(.caption)
                                    .foregroundStyle(.primary)
                                Spacer(minLength: 0)
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 3)
                        }
                    }
                    .padding(.bottom, 10)
                }
            }
        }
        .frame(minWidth: 300, maxWidth: 360, minHeight: 200, maxHeight: 520)
        .task(id: offer.typeId) { await loadTypeInfo() }
    }

    private func sectionLabel(_ title: String) -> some View {
        Text(title)
            .font(.caption2.bold())
            .foregroundStyle(.tertiary)
            .padding(.horizontal, 16)
            .padding(.top, 10)
            .padding(.bottom, 2)
    }

    private func detailRow<Content: View>(
        _ label: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .frame(width: 100, alignment: .leading)
            content()
                .font(.subheadline)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 3)
    }

    private func loadTypeInfo() async {
        typeInfo = nil
        groupName = nil
        categoryName = nil
        guard let type = await UniverseCache.shared.type(id: offer.typeId) else { return }
        typeInfo = type
        guard let group = await UniverseCache.shared.group(id: type.groupId) else { return }
        groupName = group.name
        if let cat = await UniverseCache.shared.category(id: group.categoryId) {
            categoryName = cat.name
        }
    }
}

// MARK:  Spend Plan Popover (Holdings Optimizer)

private struct LPSpendPlanEntry: Identifiable {
    let offer: ResolvedLPOffer
    let redemptions: Int
    var id: Int { offer.id }

    var lpUsed: Int { offer.offer.lpCost * redemptions }
    var iskGained: Double { (offer.netISK ?? 0) * Double(redemptions) }
}

/// Why the greedy planner couldn't build a spend plan — these are two distinct
/// situations that call for different next steps, so they're kept separate rather
/// than folded into one generic "no offers" message.
private enum LPSpendPlanEmptyReason {
    /// None of this store's rewards have any market data at all (e.g. Paragon/EverMarks —
    /// mostly account-bound cosmetics). There's no ISK angle to optimize for here.
    case noMarketData
    /// Some offers are priced, but nothing clears break-even. `closest` are the
    /// least-unprofitable offers (may be ≤ 0 ISK/LP) shown for context.
    case noProfitableOffers(closest: [ResolvedLPOffer])
    /// At least one offer is profitable, but the corp's LP balance can't afford
    /// even one redemption of the cheapest of them.
    case lpTooLow(cheapest: ResolvedLPOffer, shortfall: Int)
}

/// Greedily fills the corp's LP balance with the highest ISK/LP offers it can afford,
/// in order, spilling leftover LP into the next-best affordable offer. This is an
/// approximation (not an exact knapsack solve) but matches the ranking already shown
/// in the offer list and needs no extra state to reason about.
private struct LPSpendPlanPopover: View {
    let corp: ResolvedLoyaltyPoints

    @State private var isLoading = true
    @State private var loadError: String?
    @State private var plan: [LPSpendPlanEntry] = []
    @State private var emptyReason: LPSpendPlanEmptyReason?
    @State private var lpUsed = 0
    @State private var totalISK: Double = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            if isLoading {
                HStack(spacing: 8) {
                    ProgressView().scaleEffect(0.7)
                    Text("Calculating best value…")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(16)
            } else if let loadError {
                Text(loadError)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(16)
            } else if let emptyReason {
                emptyStateView(emptyReason)
            } else {
                Text(planSummarySentence)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                Divider()
                ScrollView {
                    planList
                }
                Divider()
                summary
            }
        }
        .frame(minWidth: 360, maxWidth: 440, minHeight: 160, maxHeight: 420)
        // List(.sidebar) — the ancestor presenting this popover — sets an implicit
        // .lineLimit(1) on its row content, which popovers inherit from their
        // presenting view's environment. Reset it here so multi-line text below
        // (e.g. the empty-state message) isn't silently truncated to one line.
        .lineLimit(nil)
        .task(id: corp.corporationId) { await buildPlan() }
    }

    @ViewBuilder
    private func emptyStateView(_ reason: LPSpendPlanEmptyReason) -> some View {
        switch reason {
        case .noMarketData:
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "xmark.seal")
                        .foregroundStyle(.tertiary)
                    Text("None of \(corp.corporationName)'s rewards are tradeable on the market — there's no ISK value to optimize for here.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(16)

        case .noProfitableOffers(let closest):
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "chart.line.downtrend.xyaxis")
                        .foregroundStyle(.tertiary)
                    Text("None of \(corp.corporationName)'s offers clear break-even at current prices, even checking every major hub.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if !closest.isEmpty {
                    Divider()
                    VStack(alignment: .leading, spacing: 4) {
                        Text("CLOSEST TO PROFITABLE")
                            .font(.caption2.bold())
                            .foregroundStyle(.tertiary)
                        ForEach(closest) { offer in
                            HStack(spacing: 8) {
                                Text(offer.typeName)
                                    .font(.caption)
                                    .lineLimit(1)
                                Spacer(minLength: 8)
                                if let ratio = offer.rawISKPerLP {
                                    Text(lpFormatISKPerLP(ratio) + " ISK/LP")
                                        .font(.caption.monospacedDigit().bold())
                                        .foregroundStyle(ratio > 0 ? .green : .red)
                                }
                            }
                        }
                    }
                    Text("Prices move — check back later, or redeem manually for an item's use value rather than resale profit.")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(16)

        case .lpTooLow(let cheapest, let shortfall):
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "medal")
                        .foregroundStyle(.tertiary)
                    Text("You don't have enough LP yet for a profitable redemption.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Divider()
                VStack(alignment: .leading, spacing: 4) {
                    Text("CHEAPEST PROFITABLE OFFER")
                        .font(.caption2.bold())
                        .foregroundStyle(.tertiary)
                    HStack(spacing: 8) {
                        Text(cheapest.typeName)
                            .font(.caption.bold())
                            .lineLimit(1)
                        Spacer(minLength: 8)
                        Text(lpFormatLP(cheapest.offer.lpCost) + " LP")
                            .font(.caption.monospacedDigit())
                    }
                    if let net = cheapest.netISK {
                        Text("+" + EVEFormatters.formatISK(net) + " net ISK")
                            .font(.caption2.monospacedDigit())
                            .foregroundStyle(.green)
                    }
                }
                Text("You need \(lpFormatLP(shortfall)) more LP to afford it.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(16)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Optimized LP Spend")
                .font(.headline)
            Text("\(corp.corporationName) · \(lpFormatLP(corp.loyaltyPoints)) LP available")
                .font(.caption)
                .foregroundStyle(.secondary)
            Text("Best price across Jita, Amarr, Dodixie, Rens & Hek")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .padding(16)
    }

    private var planList: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(plan) { entry in
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text("×\(entry.redemptions)")
                        .font(.caption.monospacedDigit().bold())
                        .foregroundStyle(.secondary)
                        .frame(minWidth: 28, alignment: .leading)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(entry.offer.typeName)
                            .font(.caption)
                            .lineLimit(2)
                            .fixedSize(horizontal: false, vertical: true)
                        if let hub = entry.offer.bestSellHub {
                            Text("sell at \(hub.displayName)")
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    VStack(alignment: .trailing, spacing: 1) {
                        Text("+" + EVEFormatters.formatISK(entry.iskGained))
                            .font(.caption.monospacedDigit().bold())
                            .foregroundStyle(.green)
                        Text(lpFormatLP(entry.lpUsed) + " LP")
                            .font(.caption2.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                    .fixedSize()
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 6)
            }
        }
        .padding(.vertical, 6)
    }

    /// Plain-English readout of the plan, generated by templating the numbers we
    /// already computed — no model call, so it's exact and always available.
    private var planSummarySentence: String {
        let lpText  = "\(lpFormatLP(lpUsed))/\(lpFormatLP(corp.loyaltyPoints)) LP"
        let iskText = "+" + EVEFormatters.formatISK(totalISK)

        if plan.count == 1, let only = plan.first {
            return "Redeem ×\(only.redemptions) \(only.offer.typeName) for \(lpText), netting \(iskText)."
        }
        let leader = plan.max { ($0.offer.iskPerLP ?? 0) < ($1.offer.iskPerLP ?? 0) }
        let ledBy = leader.map { " led by \($0.offer.typeName)" } ?? ""
        return "Redeem \(plan.count) offers\(ledBy) using \(lpText) for a projected \(iskText)."
    }

    private var summary: some View {
        VStack(spacing: 6) {
            HStack {
                Text("LP Used")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Text("\(lpFormatLP(lpUsed)) / \(lpFormatLP(corp.loyaltyPoints))")
                    .font(.caption.monospacedDigit())
            }
            HStack {
                Text("Projected ISK")
                    .font(.subheadline.bold())
                Spacer()
                Text("+" + EVEFormatters.formatISK(totalISK))
                    .font(.subheadline.bold().monospacedDigit())
                    .foregroundStyle(.green)
            }
        }
        .padding(16)
    }

    private func buildPlan() async {
        isLoading = true
        loadError = nil
        emptyReason = nil
        do {
            let bundle = try await fetchLPStoreOffersAcrossHubs(for: corp.corporationId)
            let candidates = bundle.offers
                .filter { ($0.iskPerLP ?? 0) > 0 && $0.offer.lpCost > 0 }
                .sorted { ($0.iskPerLP ?? 0) > ($1.iskPerLP ?? 0) }

            guard !candidates.isEmpty else {
                let priced = bundle.offers.filter { $0.rawISKPerLP != nil }
                plan = []
                if priced.isEmpty {
                    emptyReason = .noMarketData
                } else {
                    let closest = priced.sorted { $0.rawISKPerLP! > $1.rawISKPerLP! }.prefix(3)
                    emptyReason = .noProfitableOffers(closest: Array(closest))
                }
                isLoading = false
                return
            }

            var remainingLP = corp.loyaltyPoints
            var entries: [LPSpendPlanEntry] = []
            for offer in candidates {
                let count = remainingLP / offer.offer.lpCost
                guard count > 0 else { continue }
                entries.append(LPSpendPlanEntry(offer: offer, redemptions: count))
                remainingLP -= count * offer.offer.lpCost
            }

            if entries.isEmpty {
                let cheapest = candidates.min { $0.offer.lpCost < $1.offer.lpCost }!
                plan = []
                emptyReason = .lpTooLow(cheapest: cheapest, shortfall: cheapest.offer.lpCost - corp.loyaltyPoints)
            } else {
                plan = entries
                lpUsed = corp.loyaltyPoints - remainingLP
                totalISK = entries.reduce(0) { $0 + $1.iskGained }
            }
        } catch {
            loadError = "Could not load LP store offers."
        }
        isLoading = false
    }
}

// MARK:  Offer Row

private struct LPOfferRow: View {
    let resolved: ResolvedLPOffer
    let isEven: Bool
    let requiredItemNames: [Int: String]
    let agentStations: [AgentStation]
    let isLoadingStations: Bool
    let isEverMarks: Bool
    let hubName: String
    let showPricing: Bool
    let onSetWaypoint: (Int) -> Void

    @State private var showPopover = false

    private var offer: ESILPStoreOffer { resolved.offer }

    var body: some View {
        HStack(spacing: 0) {

            // Icon (tappable for popover) + name
            HStack(spacing: 10) {
                LPTypeImage(typeId: offer.typeId, size: 44)
                    .shadow(color: .black.opacity(0.15), radius: 2, x: 0, y: 1)
                    .onTapGesture { showPopover = true }
                    .popover(isPresented: $showPopover, arrowEdge: .trailing) {
                        LPOfferDetailPopover(
                            resolved: resolved,
                            requiredItemNames: requiredItemNames,
                            isEverMarks: isEverMarks,
                            hubName: hubName,
                            showPricing: showPricing
                        )
                    }
                VStack(alignment: .leading, spacing: 2) {
                    Text(resolved.typeName)
                        .font(.subheadline.bold())
                        .lineLimit(1)
                    if !offer.requiredItems.isEmpty {
                        Label(
                            "\(offer.requiredItems.count) required item\(offer.requiredItems.count == 1 ? "" : "s")",
                            systemImage: "bag"
                        )
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.leading, 12)

            // LP / EverMarks cost
            HStack(spacing: 3) {
                Image(systemName: lpCurrencyIcon(isEverMarks: isEverMarks))
                    .font(.system(size: 9))
                    .foregroundStyle(lpCurrencyColor(isEverMarks: isEverMarks))
                Text(lpFormatLP(offer.lpCost))
                    .font(.caption.monospacedDigit().bold())
                    .foregroundStyle(Color(hue: 0.13, saturation: 0.85, brightness: 0.9))
            }
            .frame(width: 90, alignment: .trailing)

            if showPricing {
                // ISK cost
                Text(offer.iskCost > 0 ? EVEFormatters.formatISKShort(Double(offer.iskCost)) : "—")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .frame(width: 100, alignment: .trailing)
            }

            // Quantity
            Text("×\(offer.quantity)")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.tertiary)
                .frame(width: 44, alignment: .trailing)
                .padding(.trailing, showPricing ? 0 : 16)

            if showPricing {
                // Market sell price at the selected hub
                Group {
                    if let sell = resolved.marketSell {
                        Text(EVEFormatters.formatISKShort(sell))
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.green)
                    } else {
                        Text("—").foregroundStyle(.tertiary)
                    }
                }
                .frame(width: 110, alignment: .trailing)

                // ISK/LP badge
                iskPerLPBadge
                    .frame(width: 110, alignment: .trailing)
                    .padding(.trailing, 16)
            }
        }
        .padding(.vertical, 9)
        .background(isEven ? Color.clear : Color(NSColor.separatorColor).opacity(0.07))
        .contentShape(Rectangle())
        .contextMenu {
            if isLoadingStations {
                Label("Set Destination (loading stations…)", systemImage: "location")
                    .foregroundStyle(.secondary)
            } else if agentStations.isEmpty {
                Label("Set Destination (no stations found)", systemImage: "location.slash")
                    .foregroundStyle(.secondary)
            } else if agentStations.count == 1 {
                Button {
                    onSetWaypoint(agentStations[0].locationId)
                } label: {
                    Label("Set Destination: \(agentStations[0].stationName)", systemImage: "location.fill")
                }
            } else {
                Menu {
                    ForEach(agentStations) { station in
                        Button(station.stationName) {
                            onSetWaypoint(station.locationId)
                        }
                    }
                } label: {
                    Label("Set Destination", systemImage: "location.fill")
                }
            }
        }
    }

    @ViewBuilder
    private var iskPerLPBadge: some View {
        if let iskLP = resolved.iskPerLP {
            let color = lpISKPerLPColor(iskLP)
            Text(lpFormatISKPerLP(iskLP))
                .font(.caption.monospacedDigit().bold())
                .foregroundStyle(.white)
                .padding(.horizontal, 9)
                .padding(.vertical, 4)
                .background(color, in: Capsule())
                .shadow(color: color.opacity(0.4), radius: 3, x: 0, y: 1)
        } else if resolved.marketSell == nil {
            Text("—")
                .font(.caption)
                .foregroundStyle(.tertiary)
        } else {
            Text("≤0")
                .font(.caption.bold())
                .foregroundStyle(.white)
                .padding(.horizontal, 9)
                .padding(.vertical, 4)
                .background(Color.red.opacity(0.75), in: Capsule())
        }
    }
}

// MARK:  LoyaltyPointStoreView

struct LoyaltyPointStoreView: View {
    @Environment(AccountManager.self) private var accountManager
    @Environment(DashboardPrefetcher.self) private var prefetcher

    @State private var lpData: [ResolvedLoyaltyPoints] = []
    @State private var selectedCorpId: Int?
    @State private var offers: [ResolvedLPOffer] = []
    @State private var isLoadingLP = false
    @State private var isLoadingOffers = false
    @State private var offersError: String?
    @State private var searchText = ""
    @State private var sortByISKLP = true
    @AppStorage("lpStoreMarketHub") private var selectedHub: LPMarketHub = .jita

    // Required item names resolved alongside offer type names
    @State private var requiredItemNames: [Int: String] = [:]

    // Agent stations for the selected corp (for "Set Destination")
    @State private var agentStations: [AgentStation] = []
    @State private var isLoadingStations = false

    // Waypoint feedback toast
    @State private var waypointMessage: String?
    @State private var waypointIsSuccess = false

    private var selectedCorp: ResolvedLoyaltyPoints? {
        lpData.first { $0.corporationId == selectedCorpId }
    }

    private var isEverMarks: Bool { selectedCorpId == paragonCorporationId }

    /// Whether any currently-loaded offer actually has market pricing. Some NPC-corp
    /// reward stores (e.g. Paragon/EverMarks) turn out to be entirely non-tradeable
    /// items — detected from real fetch results rather than assumed from corp identity,
    /// so pricing UI hides itself for any store like that and reappears automatically
    /// if that ever changes, without hardcoding a corp ID.
    private var offersHaveMarketData: Bool {
        offers.contains { $0.marketSell != nil }
    }

    private var filteredOffers: [ResolvedLPOffer] {
        var result = offers
        if !searchText.isEmpty {
            result = result.filter { $0.typeName.localizedCaseInsensitiveContains(searchText) }
        }
        if sortByISKLP {
            result = result.sorted { ($0.iskPerLP ?? -1) > ($1.iskPerLP ?? -1) }
        } else {
            result = result.sorted { $0.offer.lpCost < $1.offer.lpCost }
        }
        return result
    }

    private var totalLP: Int { lpData.reduce(0) { $0 + $1.loyaltyPoints } }

    var body: some View {
        HStack(spacing: 0) {
            corpList
                .frame(width: 240)
            Divider()
            offerPanel
        }
        .safeAreaInset(edge: .top, spacing: 0) {
            HStack {
                Text("LP Store")
                    .font(.largeTitle.bold())
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(.background)
        }
        .navigationTitle("")
        .task(id: accountManager.selectedCharacterID) {
            await loadLP()
        }
        .onChange(of: selectedCorpId) { _, id in
            if let id {
                sortByISKLP = true
                Task { await loadOffers(for: id) }
                Task { await loadAgentStations(for: id) }
            }
        }
        .onChange(of: selectedHub) { _, _ in
            if let id = selectedCorpId {
                Task { await loadOffers(for: id) }
            }
        }
    }

    // MARK:  Corp List (Left Panel)

    private var corpList: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Holdings")
                        .font(.subheadline.bold())
                    if !lpData.isEmpty {
                        HStack(spacing: 3) {
                            Image(systemName: "medal.fill")
                                .font(.system(size: 9))
                                .foregroundStyle(.yellow)
                            Text("\(lpFormatLP(totalLP)) total LP")
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.top, 10)
            .padding(.bottom, 8)
            .background(.bar)

            Divider()

            if isLoadingLP {
                VStack(spacing: 10) {
                    ProgressView()
                    Text("Loading LP…")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if lpData.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "medal")
                        .font(.system(size: 36))
                        .foregroundStyle(.tertiary)
                    Text("No Loyalty Points")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Text("Earn LP by running missions for NPC corporations.")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 12)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(lpData, id: \.corporationId, selection: Binding(
                    get: { selectedCorpId },
                    set: { selectedCorpId = $0 }
                )) { lp in
                    CorpHoldingRow(
                        corp: lp,
                        isEverMarks: lp.corporationId == paragonCorporationId,
                        isSelected: lp.corporationId == selectedCorpId
                    )
                    .tag(lp.corporationId)
                }
                .listStyle(.sidebar)
            }
        }
        .background(Color(NSColor.controlBackgroundColor))
    }

    // MARK:  Offer Panel (Right Panel)

    @ViewBuilder
    private var offerPanel: some View {
        if selectedCorpId == nil {
            VStack(spacing: 14) {
                Image(systemName: "storefront.fill")
                    .font(.system(size: 52))
                    .foregroundStyle(.tertiary)
                Text("Select a Corporation")
                    .font(.headline)
                    .foregroundStyle(.secondary)
                Text("Choose a corporation on the left to browse their LP store offers.")
                    .font(.subheadline)
                    .foregroundStyle(.tertiary)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if isLoadingOffers {
            VStack(spacing: 14) {
                ProgressView()
                Text("Loading LP store offers…")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let err = offersError {
            VStack(spacing: 14) {
                Image(systemName: "exclamationmark.triangle")
                    .font(.system(size: 38))
                    .foregroundStyle(.orange)
                Text(err)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                Button("Retry") {
                    if let id = selectedCorpId { Task { await loadOffers(for: id) } }
                }
                .buttonStyle(.bordered)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            offerList
        }
    }

    private var offerList: some View {
        VStack(spacing: 0) {
            offerToolbar
            Divider()
            offerColumnHeader
            Divider()
            if filteredOffers.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 32))
                        .foregroundStyle(.tertiary)
                    Text(searchText.isEmpty ? "No offers available" : "No results for \"\(searchText)\"")
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .lineLimit(nil)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: 280)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(Array(filteredOffers.enumerated()), id: \.element.id) { index, offer in
                            LPOfferRow(
                                resolved: offer,
                                isEven: index % 2 == 0,
                                requiredItemNames: requiredItemNames,
                                agentStations: agentStations,
                                isLoadingStations: isLoadingStations,
                                isEverMarks: isEverMarks,
                                hubName: selectedHub.displayName,
                                showPricing: offersHaveMarketData,
                                onSetWaypoint: { locationId in
                                    Task { await setWaypoint(locationId: locationId) }
                                }
                            )
                            Divider()
                                .padding(.leading, 64)
                                .opacity(0.5)
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var offerToolbar: some View {
        HStack(spacing: 10) {
            // Search field
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                    .font(.subheadline)
                TextField("Search offers…", text: $searchText)
                    .textFieldStyle(.plain)
                if !searchText.isEmpty {
                    Button { searchText = "" } label: {
                        Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(7)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
            .frame(maxWidth: 260)

            // Result count
            if !offers.isEmpty {
                Text("\(filteredOffers.count) offer\(filteredOffers.count == 1 ? "" : "s")")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .monospacedDigit()
            }

            Spacer()

            // Waypoint feedback toast
            if let msg = waypointMessage {
                HStack(spacing: 4) {
                    Image(systemName: waypointIsSuccess
                          ? "checkmark.circle.fill"
                          : "exclamationmark.triangle.fill")
                        .foregroundStyle(waypointIsSuccess ? .green : .orange)
                        .font(.caption)
                    Text(msg)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .transition(.opacity)
            }

            // LP / EverMarks balance badge for selected corp
            if let corp = selectedCorp {
                HStack(spacing: 4) {
                    Image(systemName: lpCurrencyIcon(isEverMarks: isEverMarks))
                        .foregroundStyle(lpCurrencyColor(isEverMarks: isEverMarks))
                        .font(.caption)
                    Text(lpFormatLP(corp.loyaltyPoints) + " " + lpCurrencyLabel(isEverMarks: isEverMarks))
                        .font(.caption.bold().monospacedDigit())
                        .foregroundStyle(.primary)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(lpCurrencyColor(isEverMarks: isEverMarks).opacity(0.12), in: Capsule())
                .overlay(Capsule().strokeBorder(lpCurrencyColor(isEverMarks: isEverMarks).opacity(0.3), lineWidth: 1))
            }

            // Market hub / sort — hidden when this store's rewards have no market data at all
            // (e.g. Paragon/EverMarks — checked from the actual fetch, not assumed from corp ID).
            if offersHaveMarketData {
                HStack(spacing: 4) {
                    Image(systemName: "building.columns")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Picker("Market", selection: $selectedHub) {
                        ForEach(LPMarketHub.allCases) { hub in
                            Text(hub.displayName).tag(hub)
                        }
                    }
                    .pickerStyle(.menu)
                    .labelsHidden()
                    .frame(width: 80)
                }
                .help("Reference market for reward and required-item prices")

                Picker("Sort", selection: $sortByISKLP) {
                    Text("ISK/LP").tag(true)
                    Text("LP Cost").tag(false)
                }
                .pickerStyle(.segmented)
                .frame(width: 150)
                .labelsHidden()
                .help("Sort by estimated ISK per LP or by LP cost")
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .animation(.easeInOut(duration: 0.25), value: waypointMessage)
    }

    private var offerColumnHeader: some View {
        HStack(spacing: 0) {
            Text("Item")
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.leading, 64)

            HStack(spacing: 3) {
                Text(isEverMarks ? "EM Cost" : "LP Cost")
                if !sortByISKLP {
                    Image(systemName: "chevron.up")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(Color.accentColor)
                }
            }
            .frame(width: 90, alignment: .trailing)

            if offersHaveMarketData {
                Text("ISK Cost")
                    .frame(width: 100, alignment: .trailing)
            }

            Text("Qty")
                .frame(width: 44, alignment: .trailing)
                .padding(.trailing, offersHaveMarketData ? 0 : 16)

            if offersHaveMarketData {
                Text("\(selectedHub.displayName) Sell")
                    .frame(width: 110, alignment: .trailing)

                HStack(spacing: 3) {
                    Text("ISK/LP")
                    if sortByISKLP {
                        Image(systemName: "chevron.down")
                            .font(.system(size: 8, weight: .bold))
                            .foregroundStyle(Color.accentColor)
                    }
                }
                .frame(width: 110, alignment: .trailing)
                .padding(.trailing, 16)
            }
        }
        .font(.caption.bold())
        .foregroundStyle(.secondary)
        .padding(.vertical, 6)
        .background(Color(NSColor.separatorColor).opacity(0.12))
    }

    // MARK:  Data Loading

    private func loadLP() async {
        isLoadingLP = true
        selectedCorpId = nil
        offers = []
        agentStations = []
        requiredItemNames = [:]

        if let account = accountManager.selectedAccount,
           let prefetched = prefetcher.data(for: account.characterID) {
            let corpIDs = prefetched.loyaltyPoints.map(\.corporationId)
            let names = await NameResolver.shared.resolve(ids: corpIDs)
            lpData = prefetched.loyaltyPoints
                .map { lp in
                    ResolvedLoyaltyPoints(
                        corporationId: lp.corporationId,
                        corporationName: names[lp.corporationId] ?? "Corp #\(lp.corporationId)",
                        loyaltyPoints: lp.loyaltyPoints
                    )
                }
                .sorted { $0.loyaltyPoints > $1.loyaltyPoints }
            isLoadingLP = false
            if let first = lpData.first { selectedCorpId = first.corporationId }
            return
        }

        guard let account = accountManager.selectedAccount,
              let token = try? await accountManager.validToken(for: account) else {
            isLoadingLP = false
            return
        }
        do {
            let raw: [ESILoyaltyPoints] = try await ESIClient.shared.fetch(
                "/characters/\(account.characterID)/loyalty/points/", token: token
            )
            let corpIDs = raw.map(\.corporationId)
            let names = await NameResolver.shared.resolve(ids: corpIDs)
            lpData = raw
                .map { lp in
                    ResolvedLoyaltyPoints(
                        corporationId: lp.corporationId,
                        corporationName: names[lp.corporationId] ?? "Corp #\(lp.corporationId)",
                        loyaltyPoints: lp.loyaltyPoints
                    )
                }
                .sorted { $0.loyaltyPoints > $1.loyaltyPoints }
        } catch {
            lpData = []
        }
        isLoadingLP = false
        if let first = lpData.first { selectedCorpId = first.corporationId }
    }

    private func loadOffers(for corpId: Int) async {
        isLoadingOffers = true
        offersError = nil
        offers = []
        requiredItemNames = [:]

        do {
            let bundle = try await fetchLPStoreOffers(for: corpId, regionId: selectedHub.regionId)
            offers = bundle.offers
            requiredItemNames = bundle.requiredItemNames
        } catch {
            offersError = "Could not load LP store. This corporation may not have a public LP store."
        }
        isLoadingOffers = false
    }

    private func loadAgentStations(for corpId: Int) async {
        isLoadingStations = true
        agentStations = []

        await AgentDataManager.shared.ensureLoaded()

        let allAgents = await AgentDataManager.shared.agents
        let locationIds = Array(Set(
            allAgents
                .filter { $0.corporationID == corpId && $0.agentTypeID != 1 }
                .map(\.locationID)
        ))

        guard !locationIds.isEmpty else {
            isLoadingStations = false
            return
        }

        let names = await NameResolver.shared.resolve(ids: locationIds)
        agentStations = locationIds
            .compactMap { id -> AgentStation? in
                guard let name = names[id] else { return nil }
                return AgentStation(locationId: id, stationName: name)
            }
            .sorted { $0.stationName < $1.stationName }

        isLoadingStations = false
    }

    // MARK:  Waypoint

    private func setWaypoint(locationId: Int) async {
        guard let account = accountManager.selectedAccount,
              let token = try? await accountManager.validToken(for: account) else {
            withAnimation { waypointMessage = "No character logged in." }
            waypointIsSuccess = false
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            withAnimation { waypointMessage = nil }
            return
        }
        do {
            try await ESIClient.shared.postAction(
                "/ui/autopilot/waypoint/",
                token: token,
                queryItems: [
                    URLQueryItem(name: "add_to_beginning",     value: "false"),
                    URLQueryItem(name: "clear_other_waypoints", value: "true"),
                    URLQueryItem(name: "destination_id",        value: "\(locationId)")
                ]
            )
            withAnimation { waypointMessage = "Destination set in EVE client." }
            waypointIsSuccess = true
        } catch {
            withAnimation { waypointMessage = "Requires esi-ui.write_waypoint.v1 scope." }
            waypointIsSuccess = false
        }
        try? await Task.sleep(nanoseconds: 3_000_000_000)
        withAnimation { waypointMessage = nil }
    }
}
