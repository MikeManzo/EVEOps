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


/// Reference market used to price offer rewards and required turn-in items.
/// Region-wide aggregates (not single-station), matching how `FuzzworkClient` already works.
enum LPMarketHub: String, CaseIterable, Identifiable, Codable {
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

struct ResolvedLPOffer: Identifiable {
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

struct AgentStation: Identifiable {
    let locationId: Int
    let stationName: String
    var id: Int { locationId }
}

struct LPStoreOfferBundle {
    var offers: [ResolvedLPOffer]
    var requiredItemNames: [Int: String]
}

/// Fetches a corp's LP store offers, resolves names, and prices both the reward
/// items and any required turn-in items — against `regionId` — so `netISK`/`iskPerLP`
/// reflect the full cost at whichever hub the user has selected.
func fetchLPStoreOffers(for corpId: Int, regionId: Int) async throws -> LPStoreOfferBundle {
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
func fetchLPStoreOffersAcrossHubs(for corpId: Int) async throws -> LPStoreOfferBundle {
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

func lpFormatLP(_ value: Int) -> String {
    if value >= 1_000_000 { return String(format: "%.1fM", Double(value) / 1_000_000) }
    if value >= 1_000 { return String(format: "%.0fK", Double(value) / 1_000) }
    return "\(value)"
}

func lpFormatISKPerLP(_ value: Double) -> String {
    if value >= 1_000_000 { return String(format: "%.1fM", value / 1_000_000) }
    if value >= 1_000 { return String(format: "%.0fK", value / 1_000) }
    return String(format: "%.0f", value)
}

func lpISKPerLPColor(_ value: Double) -> Color {
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
let paragonCorporationId = 1000419

func lpCurrencyLabel(isEverMarks: Bool) -> String { isEverMarks ? "EM" : "LP" }
func lpCurrencyIcon(isEverMarks: Bool) -> String { isEverMarks ? "sparkles" : "medal.fill" }
func lpCurrencyColor(isEverMarks: Bool) -> Color { isEverMarks ? .purple : .yellow }

// MARK:  Image Views

enum LPStoreImageCache {
    static let items = NSCache<NSNumber, NSImage>()
    static let corps = NSCache<NSNumber, NSImage>()
}

struct LPTypeImage: View {
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

struct CorpLogoImage: View {
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
