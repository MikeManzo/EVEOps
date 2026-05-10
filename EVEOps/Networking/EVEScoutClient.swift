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

struct EVEScoutConnection: Identifiable, Sendable {
    let id: String
    let signatureId: String
    let wormholeType: String
    let maxShipSize: EVEScoutShipSize
    let massStatus: EVEScoutMassStatus
    let eolAt: Date?
    let estimatedEol: String?
    let sourceSystemId: Int
    let sourceSystemName: String
    let destinationSystemId: Int
    let destinationSystemName: String
    let destinationRegionName: String
    let destinationSecurity: String
    let outSig: String?

    var isNearEOL: Bool {
        guard let eol = eolAt else { return false }
        return eol.timeIntervalSinceNow < 7200
    }
}

enum EVEScoutShipSize: String, Sendable {
    case small, medium, large, xl, unknown

    nonisolated init(raw: String?) {
        switch raw?.lowercased() {
        case "small":  self = .small
        case "medium": self = .medium
        case "large":  self = .large
        case "xlarge", "xl", "capital": self = .xl
        default:       self = .unknown
        }
    }

    var label: String {
        switch self {
        case .small:   return "S"
        case .medium:  return "M"
        case .large:   return "L"
        case .xl:      return "XL"
        case .unknown: return "?"
        }
    }

    var tooltip: String {
        switch self {
        case .small:   return "Frigates / Destroyers only"
        case .medium:  return "Cruisers and below"
        case .large:   return "Battleships and below"
        case .xl:      return "Capitals / all sizes"
        case .unknown: return "Unknown size limit"
        }
    }
}

enum EVEScoutMassStatus: String, Sendable {
    case stable, destabilized, critical, unknown

    init(raw: String?) {
        self = EVEScoutMassStatus(rawValue: raw?.lowercased() ?? "") ?? .unknown
    }

    var label: String {
        switch self {
        case .stable:       return "Stable"
        case .destabilized: return "Destabilized"
        case .critical:     return "Critical"
        case .unknown:      return "Unknown"
        }
    }

    var tooltip: String { "Wormhole mass: \(label)" }
}

// MARK: Client

actor EVEScoutClient {
    static let shared = EVEScoutClient()

    private let session: URLSession
    private var cached: [EVEScoutConnection]?
    private var cacheExpiry: Date = .distantPast

    private init() {
        let config = URLSessionConfiguration.default
        config.httpAdditionalHeaders = [
            "Accept":     "application/json",
            "User-Agent": "EVEOps macOS App"
        ]
        session = URLSession(configuration: config)
    }

    func fetchConnections(forceRefresh: Bool = false) async throws -> [EVEScoutConnection] {
        if !forceRefresh, let cached, Date() < cacheExpiry {
            return cached
        }

        let url = URL(string: "https://api.eve-scout.com/v2/public/signatures?system_name=Thera")!
        let (data, response) = try await session.data(for: URLRequest(url: url))
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            let code = (response as? HTTPURLResponse)?.statusCode ?? -1
            throw EVEScoutError.httpError(code, url.absoluteString)
        }

        let connections = parseConnections(data)
        cached = connections
        cacheExpiry = Date().addingTimeInterval(300)
        return connections
    }

    // MARK: Parsing — api.eve-scout.com/v2/public/signatures

    private func parseConnections(_ data: Data) -> [EVEScoutConnection] {
        struct Entry: Decodable {
            let id: String
            let whType: String?
            let maxShipSize: String?
            let expiresAt: String?
            let remainingHours: Int?
            let outSystemId: Int?
            let outSystemName: String?
            let outSignature: String?
            let inSystemId: Int?
            let inSystemName: String?
            let inSystemClass: String?
            let inRegionName: String?
            let inSignature: String?
        }

        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        guard let entries = try? decoder.decode([Entry].self, from: data) else { return [] }

        let isoFrac = ISO8601DateFormatter()
        isoFrac.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let isoBasic = ISO8601DateFormatter()

        return entries.compactMap { r -> EVEScoutConnection? in
            guard let destId = r.inSystemId, let destName = r.inSystemName else { return nil }

            let eolAt = r.expiresAt.flatMap { isoFrac.date(from: $0) ?? isoBasic.date(from: $0) }

            let secStr: String
            switch r.inSystemClass?.lowercased() {
            case "hs":       secStr = "highsec"
            case "ls":       secStr = "lowsec"
            case "ns":       secStr = "nullsec"
            case "pochven":  secStr = "pochven"
            default:         secStr = "unknown"
            }

            return EVEScoutConnection(
                id:                    r.id,
                signatureId:           r.outSignature ?? r.inSignature ?? "???",
                wormholeType:          r.whType ?? "???",
                maxShipSize:           EVEScoutShipSize(raw: r.maxShipSize),
                massStatus:            .unknown,
                eolAt:                 eolAt,
                estimatedEol:          r.remainingHours.map { "\($0)h remaining" },
                sourceSystemId:        r.outSystemId ?? 31000005,
                sourceSystemName:      r.outSystemName ?? "Thera",
                destinationSystemId:   destId,
                destinationSystemName: destName,
                destinationRegionName: r.inRegionName ?? "Unknown Region",
                destinationSecurity:   secStr,
                outSig:                r.outSignature
            )
        }
    }
}

// MARK: Errors

enum EVEScoutError: LocalizedError {
    case httpError(Int, String)

    var errorDescription: String? {
        switch self {
        case .httpError(let code, let url):
            return "EVE Scout returned HTTP \(code) from \(url)"
        }
    }
}
