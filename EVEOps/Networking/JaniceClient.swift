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

// MARK: Models

struct JaniceAppraisalItem: Sendable {
    let typeId: Int
    let name: String
    let amount: Int
    let buyTotal: Double    // total ISK at buy orders for the full stack
    let sellTotal: Double   // total ISK at sell orders for the full stack

    var buyPerUnit: Double  { amount > 0 ? buyTotal  / Double(amount) : 0 }
    var sellPerUnit: Double { amount > 0 ? sellTotal / Double(amount) : 0 }
}

struct JaniceAppraisal: Sendable {
    let items: [JaniceAppraisalItem]
    let unknownItems: [String]
    let totalBuy: Double
    let totalSell: Double
}

// MARK: Market

enum JaniceMarket: Int, CaseIterable, Identifiable {
    case jita    = 2
    case amarr   = 3
    case dodixie = 4
    case hek     = 5
    case rens    = 6

    var id: Int { rawValue }

    var displayName: String {
        switch self {
        case .jita:    return "Jita"
        case .amarr:   return "Amarr"
        case .dodixie: return "Dodixie"
        case .hek:     return "Hek"
        case .rens:    return "Rens"
        }
    }
}

// MARK: Client

actor JaniceClient {
    static let shared = JaniceClient()

    private let session: URLSession

    private init() {
        let config = URLSessionConfiguration.default
        config.httpAdditionalHeaders = [
            "Accept": "application/json",
            "User-Agent": "EVEOps macOS App"
        ]
        session = URLSession(configuration: config)
    }

    /// Appraises plain-text EVE item list against Janice live pricing.
    /// The text format is the same as EVE's clipboard export: "Item Name\tQty" per line.
    func appraise(_ text: String, market: JaniceMarket = .jita) async throws -> JaniceAppraisal {
        guard var components = URLComponents(string: "https://janice.e-351.com/api/rest/v2/appraisal") else {
            throw URLError(.badURL)
        }
        components.queryItems = [
            URLQueryItem(name: "market",  value: "\(market.rawValue)"),
            URLQueryItem(name: "persist", value: "0")
        ]
        guard let url = components.url else { throw URLError(.badURL) }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("text/plain",        forHTTPHeaderField: "Content-Type")
        request.httpBody = Data(text.utf8)

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw URLError(.badServerResponse)
        }
        return try parseAppraisal(data)
    }

    private func parseAppraisal(_ data: Data) throws -> JaniceAppraisal {
        struct RawItemType: Decodable {
            let eid: Int
            let name: String
        }
        struct RawItem: Decodable {
            let itemType: RawItemType
            let amount: Int
            let buyPrice: Double
            let sellPrice: Double
        }
        struct RawResponse: Decodable {
            let items: [RawItem]
            let unknownItems: [String]?
            let totalBuyPrice: Double
            let totalSellPrice: Double
        }

        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let raw = try decoder.decode(RawResponse.self, from: data)

        let items = raw.items.map { r in
            JaniceAppraisalItem(
                typeId:    r.itemType.eid,
                name:      r.itemType.name,
                amount:    r.amount,
                buyTotal:  r.buyPrice,
                sellTotal: r.sellPrice
            )
        }
        return JaniceAppraisal(
            items:        items,
            unknownItems: raw.unknownItems ?? [],
            totalBuy:     raw.totalBuyPrice,
            totalSell:    raw.totalSellPrice
        )
    }
}
