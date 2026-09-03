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

/// Fetches and caches daily market history (`GET /markets/{region_id}/history/`).
///
/// `ESIClient` already honours the endpoint's hourly `Expires` header; this actor
/// adds a typed, pre-parsed result (dates decoded, sorted ascending) with median /
/// average-volume helpers, and coalesces concurrent requests for the same
/// region + type so a screen that shows several items doesn't stampede.
actor MarketHistoryService {
    static let shared = MarketHistoryService()

    /// The Forge — Jita's region, the default price reference used across the app.
    static let jitaRegionId = 10000002

    struct Point: Sendable, Identifiable {
        let date: Date
        let average: Double
        let lowest: Double
        let highest: Double
        let volume: Int
        var id: Date { date }
    }

    struct Series: Sendable {
        let regionId: Int
        let typeId: Int
        let points: [Point]          // ascending by date
        let fetchedAt: Date

        var latest: Point? { points.last }

        /// Median daily *average* price over the last `days` days of available data.
        func median(days: Int) -> Double? {
            let recent = points.suffix(days).map(\.average).sorted()
            guard !recent.isEmpty else { return nil }
            let mid = recent.count / 2
            return recent.count.isMultiple(of: 2) ? (recent[mid - 1] + recent[mid]) / 2 : recent[mid]
        }

        /// Mean daily traded volume over the last `days` days of available data.
        func averageVolume(days: Int) -> Double? {
            let recent = points.suffix(days)
            guard !recent.isEmpty else { return nil }
            return Double(recent.reduce(0) { $0 + $1.volume }) / Double(recent.count)
        }
    }

    private struct Key: Hashable { let region: Int; let type: Int }

    private var cache: [Key: Series] = [:]
    private var inFlight: [Key: Task<Series, Error>] = [:]
    private let ttl: TimeInterval = 3600

    func series(typeId: Int, regionId: Int = jitaRegionId, forceRefresh: Bool = false) async throws -> Series {
        let key = Key(region: regionId, type: typeId)

        if !forceRefresh, let hit = cache[key], Date().timeIntervalSince(hit.fetchedAt) < ttl {
            return hit
        }
        if let running = inFlight[key] { return try await running.value }

        let task = Task { () throws -> Series in
            let raw: [ESIMarketHistory] = try await ESIClient.shared.fetch(
                "/markets/\(regionId)/history/",
                queryItems: [URLQueryItem(name: "type_id", value: String(typeId))],
                bypassCache: forceRefresh
            )

            let fmt = DateFormatter()
            fmt.locale = Locale(identifier: "en_US_POSIX")
            fmt.timeZone = TimeZone(identifier: "UTC")
            fmt.dateFormat = "yyyy-MM-dd"

            let points = raw.compactMap { h -> Point? in
                guard let d = fmt.date(from: h.date) else { return nil }
                return Point(date: d, average: h.average, lowest: h.lowest, highest: h.highest, volume: h.volume)
            }.sorted { $0.date < $1.date }

            return Series(regionId: regionId, typeId: typeId, points: points, fetchedAt: Date())
        }
        inFlight[key] = task
        defer { inFlight[key] = nil }

        do {
            let series = try await task.value
            cache[key] = series
            return series
        } catch {
            if let hit = cache[key] { return hit }   // serve stale rather than nothing
            throw error
        }
    }
}
