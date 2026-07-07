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

// MARK: Model

struct FuzzworkPrice: Sendable {
    let typeId: Int
    /// Highest active buy order — what someone will pay you immediately.
    let buyMax: Double
    /// 95th-percentile buy order — realistic immediate-sell estimate.
    let buyPercentile: Double
    /// Lowest active sell order.
    let sellMin: Double
    /// 5th-percentile sell order — realistic immediate-buy estimate.
    let sellPercentile: Double
}

// MARK: Client

actor FuzzworkClient {
    static let shared = FuzzworkClient()

    private let session: URLSession
    private var cache: [Int: (price: FuzzworkPrice, expiry: Date)] = [:]
    private var stationCache: [Int: [Int: (price: FuzzworkPrice, expiry: Date)]] = [:]

    private init() {
        let config = URLSessionConfiguration.default
        config.httpAdditionalHeaders = [
            "Accept":     "application/json",
            "User-Agent": "EVEOps macOS App"
        ]
        session = URLSession(configuration: config)
    }

    /// Fetches Jita (default) market aggregates for the given type IDs.
    /// Caches results for 10 minutes; batches uncached IDs in a single request.
    func prices(typeIds: [Int], regionId: Int = 10000002) async throws -> [Int: FuzzworkPrice] {
        let now = Date()
        let uncached = typeIds.filter { cache[$0].map { $0.expiry <= now } ?? true }

        if !uncached.isEmpty {
            let typeString = uncached.map(String.init).joined(separator: ",")
            guard let url = URL(string: "https://market.fuzzwork.co.uk/aggregates/?region=\(regionId)&types=\(typeString)") else {
                throw URLError(.badURL)
            }
            let (data, response) = try await session.data(for: URLRequest(url: url))
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                throw URLError(.badServerResponse)
            }
            let fetched = try parsePrices(data)
            let expiry = now.addingTimeInterval(600)
            for price in fetched {
                cache[price.typeId] = (price: price, expiry: expiry)
            }
        }

        var result: [Int: FuzzworkPrice] = [:]
        for id in typeIds {
            if let entry = cache[id], entry.expiry > Date() {
                result[id] = entry.price
            }
        }
        return result
    }

    /// Fetches market aggregates for a specific station (e.g. Jita 4-4: 60003760).
    /// Same JSON schema as the region endpoint; cached per station for 10 minutes.
    func stationPrices(stationId: Int, typeIds: [Int]) async throws -> [Int: FuzzworkPrice] {
        let now = Date()
        var entry = stationCache[stationId] ?? [:]
        let uncached = typeIds.filter { entry[$0].map { $0.expiry <= now } ?? true }

        if !uncached.isEmpty {
            let typeString = uncached.map(String.init).joined(separator: ",")
            guard let url = URL(string: "https://market.fuzzwork.co.uk/aggregates/?station=\(stationId)&types=\(typeString)") else {
                throw URLError(.badURL)
            }
            let (data, response) = try await session.data(for: URLRequest(url: url))
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                throw URLError(.badServerResponse)
            }
            let fetched = try parsePrices(data)
            let expiry = now.addingTimeInterval(600)
            for price in fetched {
                entry[price.typeId] = (price: price, expiry: expiry)
            }
            stationCache[stationId] = entry
        }

        var result: [Int: FuzzworkPrice] = [:]
        for id in typeIds {
            if let e = stationCache[stationId]?[id], e.expiry > Date() {
                result[id] = e.price
            }
        }
        return result
    }

    private func parsePrices(_ data: Data) throws -> [FuzzworkPrice] {
        struct Side: Decodable {
            let weightedAverage: String
            let max: String
            let min: String
            let stddev: String
            let median: String
            let percentile: String
        }
        struct TypeAgg: Decodable {
            let buy: Side
            let sell: Side
        }

        let raw = try JSONDecoder().decode([String: TypeAgg].self, from: data)
        return raw.compactMap { key, agg -> FuzzworkPrice? in
            guard let typeId     = Int(key),
                  let buyMax     = Double(agg.buy.max),
                  let buyPct     = Double(agg.buy.percentile),
                  let sellMin    = Double(agg.sell.min),
                  let sellPct    = Double(agg.sell.percentile)
            else { return nil }
            return FuzzworkPrice(
                typeId:         typeId,
                buyMax:         buyMax,
                buyPercentile:  buyPct,
                sellMin:        sellMin,
                sellPercentile: sellPct
            )
        }
    }
}
