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
import OSLog

// MARK: Models

/// A single result from EVERef's type-name search.
struct EVERefTypeResult: Identifiable, Sendable {
    let typeId: Int
    let name: String
    var id: Int { typeId }
}

/// A single material or product line inside a blueprint activity.
struct EVERefBlueprintMaterial: Sendable {
    let typeId: Int
    let quantity: Int
}

struct EVERefBlueprintProduct: Sendable {
    let typeId: Int
    let quantity: Int
    let probability: Double?    // nil for guaranteed products; 0–1 for invention outputs
}

/// One activity within a blueprint (manufacturing, copying, research, invention, reaction).
struct EVERefBlueprintActivity: Sendable {
    let materials: [EVERefBlueprintMaterial]
    let products: [EVERefBlueprintProduct]
    let time: Int               // base duration in seconds
}

/// All activities defined on a single blueprint type.
struct EVERefBlueprint: Sendable {
    let blueprintTypeId: Int
    let manufacturing: EVERefBlueprintActivity?
    let copying: EVERefBlueprintActivity?
    let researchMaterial: EVERefBlueprintActivity?
    let researchTime: EVERefBlueprintActivity?
    let invention: EVERefBlueprintActivity?
    let reaction: EVERefBlueprintActivity?

    /// Convenience: the primary output type ID from manufacturing, if any.
    var productTypeId: Int? { manufacturing?.products.first?.typeId }
}

// MARK: Client

/// Thin client for the EVERef reference-data API.
///
/// Two base hosts are used:
///   - ref-data.everef.net  — bulk SDE/ESI reference data (blueprints, types, market groups)
///   - api.everef.net        — higher-level endpoints (search, industry cost)
///
/// The API carries no authentication requirement and is rate-limit-friendly for
/// per-item reads. Blueprint responses are cached in memory for 7 days since
/// the data only changes on game patches.
actor EVERefClient {
    static let shared = EVERefClient()

    private let refDataBase = "https://ref-data.everef.net"
    private let apiBase     = "https://api.everef.net"
    private let session: URLSession

    // In-memory blueprint cache: blueprintTypeId → (result, expiry)
    private var blueprintCache: [Int: (blueprint: EVERefBlueprint, expiry: Date)] = [:]
    private static let blueprintTTL: TimeInterval = 7 * 24 * 3600

    private init() {
        let config = URLSessionConfiguration.default
        config.httpAdditionalHeaders = [
            "Accept":     "application/json",
            "User-Agent": "EVEOps macOS App"
        ]
        session = URLSession(configuration: config)
    }

    // MARK: Search

    /// Searches EVERef for published inventory types whose name contains `query`.
    /// Requires at least 3 characters. Results are sorted: exact match first,
    /// then prefix matches, then alphabetical.
    func search(query: String) async throws -> [EVERefTypeResult] {
        guard query.count >= 3 else { return [] }
        guard var comps = URLComponents(string: "\(apiBase)/v1/search") else {
            throw URLError(.badURL)
        }
        comps.queryItems = [URLQueryItem(name: "query", value: query)]
        guard let url = comps.url else { throw URLError(.badURL) }

        await Logger.eveRef.info("EVERefClient search: \"\(query)\"")
        let (data, response) = try await session.data(from: url)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            let code = (response as? HTTPURLResponse)?.statusCode ?? -1
            throw EVERefError.httpError(code, url.absoluteString)
        }

        return try parseSearchResults(data, query: query)
    }

    // MARK: Blueprints

    /// Returns the blueprint definition for `typeId`, or nil if EVERef has no
    /// record for it (e.g., the ID is a product type, not a blueprint type).
    /// Results are cached in memory for 7 days.
    func blueprint(typeId: Int) async throws -> EVERefBlueprint? {
        let now = Date()
        if let cached = blueprintCache[typeId], cached.expiry > now {
            return cached.blueprint
        }

        guard let url = URL(string: "\(refDataBase)/blueprints/\(typeId)") else {
            throw URLError(.badURL)
        }

        await Logger.eveRef.info("EVERefClient blueprint fetch: typeId=\(typeId)")
        let (data, response) = try await session.data(from: url)
        guard let http = response as? HTTPURLResponse else { throw URLError(.badServerResponse) }
        guard http.statusCode == 200 else {
            // 404 is normal — many type IDs are not blueprints.
            if http.statusCode != 404 {
                await Logger.eveRef.error("EVERefClient blueprint HTTP \(http.statusCode) for typeId=\(typeId)")
            }
            return nil
        }

        guard let bp = try? parseBlueprint(data) else { return nil }
        blueprintCache[typeId] = (blueprint: bp, expiry: now.addingTimeInterval(Self.blueprintTTL))
        return bp
    }

    // MARK: Parsing

    private func parseSearchResults(_ data: Data, query: String) throws -> [EVERefTypeResult] {
        struct RawResult: Decodable {
            let typeId: Int
            let name: String
        }
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let raw = try decoder.decode([RawResult].self, from: data)

        let lower = query.lowercased()
        return raw
            .map { EVERefTypeResult(typeId: $0.typeId, name: $0.name) }
            .sorted { a, b in
                let aL = a.name.lowercased()
                let bL = b.name.lowercased()
                if (aL == lower) != (bL == lower) { return aL == lower }
                if aL.hasPrefix(lower) != bL.hasPrefix(lower) { return aL.hasPrefix(lower) }
                return aL < bL
            }
    }

    private func parseBlueprint(_ data: Data) throws -> EVERefBlueprint {
        struct RawMaterial: Decodable {
            let typeId: Int
            let quantity: Int
        }
        struct RawProduct: Decodable {
            let typeId: Int
            let quantity: Int
            let probability: Double?
        }
        struct RawActivity: Decodable {
            let materials: [RawMaterial]?
            let products: [RawProduct]?
            let time: Int?
        }
        struct RawActivities: Decodable {
            let manufacturing: RawActivity?
            let copying: RawActivity?
            let researchMaterial: RawActivity?
            let researchTime: RawActivity?
            let invention: RawActivity?
            let reaction: RawActivity?
        }
        struct RawBlueprint: Decodable {
            let blueprintTypeId: Int
            let activities: RawActivities
        }

        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let raw = try decoder.decode(RawBlueprint.self, from: data)

        func mapActivity(_ a: RawActivity?) -> EVERefBlueprintActivity? {
            guard let a else { return nil }
            return EVERefBlueprintActivity(
                materials: (a.materials ?? []).map {
                    EVERefBlueprintMaterial(typeId: $0.typeId, quantity: $0.quantity)
                },
                products: (a.products ?? []).map {
                    EVERefBlueprintProduct(typeId: $0.typeId, quantity: $0.quantity, probability: $0.probability)
                },
                time: a.time ?? 0
            )
        }

        return EVERefBlueprint(
            blueprintTypeId:  raw.blueprintTypeId,
            manufacturing:    mapActivity(raw.activities.manufacturing),
            copying:          mapActivity(raw.activities.copying),
            researchMaterial: mapActivity(raw.activities.researchMaterial),
            researchTime:     mapActivity(raw.activities.researchTime),
            invention:        mapActivity(raw.activities.invention),
            reaction:         mapActivity(raw.activities.reaction)
        )
    }
}

// MARK: Errors

enum EVERefError: LocalizedError {
    case httpError(Int, String)

    var errorDescription: String? {
        switch self {
        case .httpError(let code, let url):
            return "EVERef returned HTTP \(code) from \(url)"
        }
    }
}
