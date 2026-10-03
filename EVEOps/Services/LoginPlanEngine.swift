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

// MARK:  Models

/// Something that needs a pilot logged in: a queue that empties, a slot that frees, an
/// extractor that stops, a listing that expires. `date` at or before `now` means it is
/// already idle.
nonisolated struct LoginPlanItem: Sendable, Hashable {
    let characterID: Int
    let kind: IdleCapacityKind
    let date: Date
}

/// How the plan may schedule logins.
nonisolated struct LoginPlanSettings: Sendable, Equatable {
    /// How long something may sit idle before it has to be dealt with.
    var tolerance: TimeInterval = 4 * 3600
    /// How far ahead to plan.
    var horizon: TimeInterval = 3 * 86400
    /// Local hours the pilot can log in: from `dayStartHour` up to `dayEndHour`. Equal
    /// hours mean any time; a start after the end wraps past midnight (18 → 2).
    var dayStartHour = 8
    var dayEndHour = 23

    var isAlwaysAvailable: Bool { dayStartHour == dayEndHour }
}

/// One login: when, and everything that has come due by then.
nonisolated struct LoginSession: Sendable, Identifiable {
    let date: Date
    let items: [LoginPlanItem]
    /// Idle time the items run up waiting for this login.
    let waitTime: TimeInterval
    /// Extra idle time if this login is skipped and its items roll to the next one; nil for
    /// the last login in the plan.
    let skipCost: TimeInterval?

    var id: Date { date }

    /// Pilots to log in, in the order their first item came due.
    var characterIDs: [Int] {
        var seen = Set<Int>()
        return items.sorted { $0.date < $1.date }.map(\.characterID).filter { seen.insert($0).inserted }
    }

    /// Items that were already idle when the plan was made.
    func overdueCount(now: Date) -> Int { items.filter { $0.date <= now }.count }
}

nonisolated struct LoginPlan: Sendable {
    let sessions: [LoginSession]
    /// Logins needed to react to every item the moment it came due (items within a few
    /// minutes of each other share one).
    let reactiveLogins: Int
    let horizonEnd: Date

    var totalWait: TimeInterval { sessions.reduce(0) { $0 + $1.waitTime } }
    var itemCount: Int { sessions.reduce(0) { $0 + $1.items.count } }
}

// MARK:  Engine

/// Plans the fewest logins that keep every pilot's capacity working: each item has to be
/// dealt with within `tolerance` of coming due, at an hour the pilot is available.
///
/// It's interval point cover. Each item can be handled anywhere from when it comes due to
/// the latest available moment within its tolerance (or, when its whole window falls in
/// off-hours, the first available moment after it). Repeatedly taking the item whose
/// window closes first and logging in at that last moment covers every other item already
/// due by then — and is optimal, since any plan needs a login inside that first window and
/// none is later.
nonisolated enum LoginPlanEngine {
    /// Kinds a login actually fixes. Clone jumps, remaps, unallocated SP, research points
    /// and unused planets don't come due at a moment.
    static let plannableKinds: Set<IdleCapacityKind> = [
        .training, .manufacturing, .science, .reactions, .extractors, .market, .contracts,
    ]

    /// Logins snap to this grid so times read cleanly ("19:15", not "19:07").
    static let grid: TimeInterval = 15 * 60
    /// Items this close together count as one login when reacting to each.
    static let clusterWindow: TimeInterval = 15 * 60

    // MARK: Items

    /// A pilot's items: what is idle now (from the report) plus what comes due within the
    /// horizon (from the timeline). Market and contract lines with free slots are left
    /// out — an unused slot doesn't come due; only expiring listings do.
    static func items(characterID: Int, report: IdleCapacityReport, events: [IdleCapacityEvent],
                      kinds: Set<IdleCapacityKind> = plannableKinds, now: Date) -> [LoginPlanItem] {
        var out: [LoginPlanItem] = []
        for line in report.lines where line.status == .idle && kinds.contains(line.kind) {
            switch line.kind {
            case .market, .contracts:
                continue
            default:
                out.append(LoginPlanItem(characterID: characterID, kind: line.kind, date: min(line.idleSince ?? now, now)))
            }
        }
        for event in events where kinds.contains(event.kind) && event.date > now {
            out.append(LoginPlanItem(characterID: characterID, kind: event.kind, date: event.date))
        }
        return out
    }

    // MARK: Plan

    static func plan(_ items: [LoginPlanItem], settings: LoginPlanSettings, now: Date,
                     calendar: Calendar = .current) -> LoginPlan {
        let horizonEnd = now.addingTimeInterval(settings.horizon)
        let windows = Availability(settings: settings, calendar: calendar)

        struct Window { let item: LoginPlanItem; let release: Date; let latest: Date }
        var open: [Window] = items
            .filter { $0.date <= horizonEnd }
            .map { item in
                let release = max(item.date, now)
                let deadline = release.addingTimeInterval(settings.tolerance)
                let latest = windows.latest(from: release, to: deadline) ?? windows.first(after: release)
                return Window(item: item, release: release, latest: latest)
            }
            .sorted { ($0.latest, $0.item.date) < ($1.latest, $1.item.date) }

        var picks: [(date: Date, items: [LoginPlanItem])] = []
        while let first = open.first {
            let login = first.latest
            let covered = open.filter { $0.release <= login }
            open.removeAll { $0.release <= login }
            picks.append((login, covered.map(\.item).sorted { $0.date < $1.date }))
        }

        var sessions: [LoginSession] = []
        for (index, pick) in picks.enumerated() {
            let wait = pick.items.reduce(0) { $0 + pick.date.timeIntervalSince(max($1.date, now)) }
            let skip = index + 1 < picks.count
                ? Double(pick.items.count) * picks[index + 1].date.timeIntervalSince(pick.date)
                : nil
            sessions.append(LoginSession(date: pick.date, items: pick.items, waitTime: max(wait, 0), skipCost: skip))
        }
        return LoginPlan(sessions: sessions, reactiveLogins: reactiveLogins(items, now: now, until: horizonEnd),
                         horizonEnd: horizonEnd)
    }

    /// Logins it would take to answer every item as it comes due.
    static func reactiveLogins(_ items: [LoginPlanItem], now: Date, until end: Date) -> Int {
        let dates = items.map { max($0.date, now) }.filter { $0 <= end }.sorted()
        var count = 0
        var clusterStart: Date?
        for date in dates {
            if let start = clusterStart, date.timeIntervalSince(start) <= clusterWindow { continue }
            clusterStart = date
            count += 1
        }
        return count
    }

    // MARK: Availability

    /// The pilot's available hours, as a membership test plus searches on the grid.
    struct Availability {
        let settings: LoginPlanSettings
        let calendar: Calendar

        func contains(_ date: Date) -> Bool {
            guard !settings.isAlwaysAvailable else { return true }
            let parts = calendar.dateComponents([.hour, .minute], from: date)
            let minutes = (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
            let start = settings.dayStartHour * 60, end = settings.dayEndHour * 60
            // The end hour itself still counts, so "until 23" allows a 23:00 login.
            return start < end ? (minutes >= start && minutes <= end) : (minutes >= start || minutes <= end)
        }

        /// The latest available moment in `from…to`, on the grid when the grid has a point
        /// in range; nil when the whole range is off-hours.
        func latest(from: Date, to: Date) -> Date? {
            guard from <= to else { return nil }
            var candidate = floorToGrid(to)
            if candidate < from { return contains(to) ? to : nil }
            while candidate >= from {
                if contains(candidate) { return candidate }
                candidate = candidate.addingTimeInterval(-LoginPlanEngine.grid)
            }
            return contains(from) ? from : nil
        }

        /// The first available moment at or after `date`.
        func first(after date: Date) -> Date {
            if contains(date) { return date }
            var candidate = ceilToGrid(date)
            for _ in 0..<(3 * 24 * 4) {
                if contains(candidate) { return candidate }
                candidate = candidate.addingTimeInterval(LoginPlanEngine.grid)
            }
            return date
        }

        private func floorToGrid(_ date: Date) -> Date {
            let t = date.timeIntervalSinceReferenceDate
            return Date(timeIntervalSinceReferenceDate: (t / LoginPlanEngine.grid).rounded(.down) * LoginPlanEngine.grid)
        }

        private func ceilToGrid(_ date: Date) -> Date {
            let t = date.timeIntervalSinceReferenceDate
            return Date(timeIntervalSinceReferenceDate: (t / LoginPlanEngine.grid).rounded(.up) * LoginPlanEngine.grid)
        }
    }
}
