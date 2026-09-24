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
import Observation

/// Daily net-worth snapshots per character, kept locally. ESI only reports net worth
/// *now*; recording one point per day (the latest valuation of that day wins) is what
/// lets Finances draw a trend. Stored in UserDefaults — at most ~400 small points per
/// character, well within its comfortable size.
@MainActor
@Observable
final class NetWorthHistory {
    static let shared = NetWorthHistory()

    struct Point: Codable, Identifiable, Equatable {
        /// Start of the local day the snapshot represents.
        let date: Date
        let netWorth: Double
        let wallet: Double
        var id: Date { date }
    }

    private static let storageKey = "history.netWorth.v1"
    private static let retentionDays = 400

    /// characterID → day key ("2026-09-24") → point.
    private var store: [Int: [String: Point]]

    private init() {
        if let data = UserDefaults.standard.data(forKey: Self.storageKey),
           let decoded = try? JSONDecoder().decode([Int: [String: Point]].self, from: data) {
            store = decoded
        } else {
            store = [:]
        }
    }

    /// Records today's valuation for a character, replacing any earlier one from today.
    func record(characterID: Int, netWorth: Double, wallet: Double, at date: Date = .now) {
        guard netWorth > 0 else { return }
        let day = Calendar.current.startOfDay(for: date)
        var points = store[characterID] ?? [:]
        points[Self.key(for: day)] = Point(date: day, netWorth: netWorth, wallet: wallet)
        if let cutoff = Calendar.current.date(byAdding: .day, value: -Self.retentionDays, to: day) {
            points = points.filter { $0.value.date >= cutoff }
        }
        store[characterID] = points
        persist()
    }

    /// Snapshots for a character in date order, limited to the last `days` days (nil = all).
    func points(characterID: Int, days: Int? = nil) -> [Point] {
        let all = (store[characterID] ?? [:]).values.sorted { $0.date < $1.date }
        guard let days,
              let cutoff = Calendar.current.date(byAdding: .day, value: -days,
                                                 to: Calendar.current.startOfDay(for: .now)) else { return all }
        return all.filter { $0.date >= cutoff }
    }

    /// Fractional change in net worth over the last `days` days, when there's a snapshot
    /// old enough to compare against.
    func change(characterID: Int, overDays days: Int) -> Double? {
        let series = points(characterID: characterID)
        guard let latest = series.last,
              let target = Calendar.current.date(byAdding: .day, value: -days, to: latest.date),
              let baseline = series.last(where: { $0.date <= target }),
              baseline.netWorth > 0 else { return nil }
        return (latest.netWorth - baseline.netWorth) / baseline.netWorth
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(store) {
            UserDefaults.standard.set(data, forKey: Self.storageKey)
        }
    }

    private static func key(for day: Date) -> String {
        let c = Calendar.current.dateComponents([.year, .month, .day], from: day)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }
}
