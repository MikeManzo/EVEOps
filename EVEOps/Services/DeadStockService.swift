//
// This file is part of EVEOps.
//
// EVEOps is free software: you can redistribute it and/or modify
// it under the terms of the GNU General Public License as published by
// the Free Software Foundation, version 3 or later.
//
// Copyright (c) 2026 CitizenCoder
//

import Foundation

// MARK:  First-seen history

/// When each asset stack was first seen, per pilot. ESI says what you own, never since
/// when; noting each item ID the first time it shows up is what lets Dead Stock say
/// "untouched for 60 days". Items that leave the asset list are dropped, so the file only
/// ever holds what's currently owned.
nonisolated struct DeadStockHistory: Codable, Sendable {
    /// Character → item → first seen.
    var items: [Int: [Int: Date]] = [:]
    /// Character → when tracking began.
    var trackingSince: [Int: Date] = [:]

    private static var url: URL? {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appendingPathComponent("EVEOps", isDirectory: true)
            .appendingPathComponent("dead-stock-history.json")
    }

    static func load() -> DeadStockHistory {
        guard let url, let data = try? Data(contentsOf: url),
              let decoded = try? JSONDecoder().decode(DeadStockHistory.self, from: data) else { return DeadStockHistory() }
        return decoded
    }

    func save() {
        guard let url = Self.url, let data = try? JSONEncoder().encode(self) else { return }
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: url, options: .atomic)
    }

    /// Notes new items, forgets ones no longer owned. Items on a pilot's first record get
    /// `.distantPast` — they were already there, for who knows how long.
    mutating func record(characterID: Int, itemIDs: [Int], now: Date = .now) {
        let isFirst = trackingSince[characterID] == nil
        if isFirst { trackingSince[characterID] = now }
        let previous = items[characterID] ?? [:]
        var next: [Int: Date] = [:]
        for id in itemIDs {
            next[id] = previous[id] ?? (isFirst ? .distantPast : now)
        }
        items[characterID] = next
    }

    /// Item → first seen, for every pilot.
    var flattened: [Int: Date] {
        items.values.reduce(into: [:]) { out, dates in out.merge(dates) { a, _ in a } }
    }
}

// MARK:  Service

/// Loads every pilot's assets and fittings, prices them, and runs the Dead Stock engine.
@MainActor
@Observable
final class DeadStockService {
    static let shared = DeadStockService()

    private(set) var report: DeadStockReport?
    private(set) var places: [Int: ReadyRoomPlace] = [:]
    /// Type → average daily Jita volume over 30 days, for the most valuable lines.
    private(set) var dailyVolume: [Int: Double] = [:]
    private(set) var isLoading = false
    private(set) var progress: String?
    private(set) var error: String?
    /// Pilots whose assets couldn't be read, by name.
    private(set) var skippedPilots: [String] = []
    private(set) var trackingSince: Date?

    private init() {}

    func refresh(accountManager: AccountManager, prefetcher: DashboardPrefetcher, force: Bool = false) async {
        guard !isLoading else { return }
        isLoading = true
        error = nil
        defer {
            isLoading = false
            progress = nil
        }

        let accounts = accountManager.accounts.filter { !$0.needsReauth }
        var assets: [Int: [ESIAsset]] = [:]
        var fittings: [ESIFitting] = []
        var tokens: [Int: String] = [:]
        var skipped: [String] = []

        for (index, account) in accounts.enumerated() {
            progress = String(localized: "Reading assets · \(index + 1) of \(accounts.count)")
            guard let token = try? await accountManager.validToken(for: account) else {
                skipped.append(account.characterName)
                continue
            }
            tokens[account.characterID] = token
            async let assetRequest: [ESIAsset] = ESIClient.shared.fetchPages(
                "/characters/\(account.characterID)/assets/", token: token, bypassCache: force
            )
            async let fittingRequest: [ESIFitting]? = try? ESIClient.shared.fetch(
                "/characters/\(account.characterID)/fittings/", token: token, bypassCache: force
            )
            do {
                var seen = Set<Int>()
                assets[account.characterID] = try await assetRequest.filter { seen.insert($0.itemId).inserted }
            } catch {
                skipped.append(account.characterName)
            }
            fittings += await fittingRequest ?? []
        }
        skippedPilots = skipped
        guard !assets.isEmpty else {
            error = String(localized: "Couldn’t read any pilot’s assets.")
            return
        }

        // First sightings.
        var history = DeadStockHistory.load()
        for (characterID, list) in assets { history.record(characterID: characterID, itemIDs: list.map(\.itemId)) }
        history.save()
        trackingSince = history.trackingSince.filter { assets[$0.key] != nil }.values.min()

        progress = String(localized: "Looking up item types…")
        let typeIDs = Set(assets.values.flatMap { $0.map(\.typeId) })
            .union(fittings.flatMap { [$0.shipTypeId] + $0.items.map(\.typeId) })
        let types = await UniverseCache.shared.types(ids: Array(typeIDs))
        let groups = await UniverseCache.shared.groups(ids: Set(types.values.map(\.groupId)))

        var pilotedShips: [Int: ESICharacterShip] = [:]
        var industrialists: Set<Int> = []
        for account in accounts {
            let data = prefetcher.characterData[account.characterID]
            if let ship = data?.ship { pilotedShips[account.characterID] = ship }
            let ownsBlueprints = assets[account.characterID]?.contains {
                types[$0.typeId].flatMap { groups[$0.groupId]?.categoryId } == DeadStockEngine.Category.blueprint
            } ?? false
            let hasJobs = !(data?.industryJobs.isEmpty ?? true)
                || !(IdleCapacityService.shared.jobHistory[account.characterID]?.isEmpty ?? true)
            if ownsBlueprints || hasJobs { industrialists.insert(account.characterID) }
        }

        var input = DeadStockInput(
            assets: assets,
            pilotedShips: pilotedShips,
            fittings: fittings,
            categories: types.compactMapValues { groups[$0.groupId]?.categoryId },
            typeNames: types.mapValues(\.name),
            volumes: types.compactMapValues { $0.packagedVolume ?? $0.volume },
            firstSeen: history.flattened,
            industrialists: industrialists
        )
        report = await Task.detached(priority: .userInitiated) { [input] in DeadStockEngine.report(input) }.value

        // Prices for what's dead, in chunks the aggregates endpoint handles comfortably.
        progress = String(localized: "Pricing…")
        let deadTypes = report?.lines.map(\.typeID) ?? []
        var prices: [Int: DeadStockPrice] = [:]
        for start in stride(from: 0, to: deadTypes.count, by: 200) {
            let chunk = Array(deadTypes[start..<min(start + 200, deadTypes.count)])
            if let batch = try? await FuzzworkClient.shared.prices(typeIds: chunk) {
                for (typeID, price) in batch { prices[typeID] = DeadStockPrice(buy: price.buyMax, sell: price.sellMin) }
            }
        }
        input.prices = prices
        let priced = await Task.detached(priority: .userInitiated) { [input] in DeadStockEngine.report(input) }.value
        report = priced

        // Names for the places holding it.
        progress = String(localized: "Finding stations…")
        let placeIDs = Set(priced.lines.flatMap { $0.stacks.map(\.placeID) }).subtracting(places.keys)
        if let token = tokens.values.first, !placeIDs.isEmpty {
            places.merge(await ReadyRoomPlaces.resolve(placeIDs, token: token)) { _, new in new }
        }

        // How fast the most valuable lines would sell.
        progress = String(localized: "Checking market volume…")
        let top = priced.lines.prefix(40).map(\.typeID).filter { dailyVolume[$0] == nil }
        await withTaskGroup(of: (Int, Double?).self) { group in
            for typeID in top {
                group.addTask {
                    let series = try? await MarketHistoryService.shared.series(typeId: typeID)
                    return (typeID, series.map { $0.averageVolume(days: 30) ?? 0 })
                }
            }
            for await (typeID, volume) in group {
                if let volume { dailyVolume[typeID] = volume }
            }
        }
    }
}
