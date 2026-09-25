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

/// The one rule for showing when something happened, so every list reads the same way
/// (the app had drifted across "Sep 22, 2026 at 10:09 PM", "2h ago", bare times, …):
///
/// - under a minute: "just now"
/// - under an hour: "12m ago"
/// - earlier today: the time — "10:09 PM"
/// - yesterday: "Yesterday"
/// - the past week: the weekday — "Tuesday"
/// - tomorrow / the coming week: "Tomorrow, 9:40 PM" / "Friday, 2:15 PM"
/// - this year: "Sep 12"
/// - older: "Sep 12, 2025"
///
/// Anything showing a date should also carry the full timestamp as a tooltip
/// (`EVEDates.full`).
nonisolated enum EVEDates {
    static func short(_ date: Date, now: Date = .now) -> String {
        let cal = Calendar.current
        let elapsed = now.timeIntervalSince(date)
        if elapsed >= 0 && elapsed < 60 { return String(localized: "just now") }
        if elapsed >= 0 && elapsed < 3600 { return String(localized: "\(Int(elapsed / 60))m ago") }
        if cal.isDate(date, inSameDayAs: now) { return date.formatted(date: .omitted, time: .shortened) }
        if cal.isDateInYesterday(date) { return String(localized: "Yesterday") }
        // Future moments (skill finishes, cooldowns) keep their time — it's what matters.
        if cal.isDateInTomorrow(date) {
            return String(localized: "Tomorrow, \(date.formatted(date: .omitted, time: .shortened))")
        }
        if date > now,
           let days = cal.dateComponents([.day], from: cal.startOfDay(for: now), to: cal.startOfDay(for: date)).day,
           days < 7 {
            return date.formatted(.dateTime.weekday(.wide).hour().minute())
        }
        if let days = cal.dateComponents([.day], from: cal.startOfDay(for: date), to: cal.startOfDay(for: now)).day,
           days > 0, days < 7 {
            return date.formatted(.dateTime.weekday(.wide))
        }
        if cal.isDate(date, equalTo: now, toGranularity: .year) {
            return date.formatted(.dateTime.month(.abbreviated).day())
        }
        return date.formatted(.dateTime.month(.abbreviated).day().year())
    }

    /// Heading for a group of same-day rows: "Today", "Yesterday", "Tuesday, Sep 22",
    /// or "Sep 22, 2025" for past years.
    static func dayHeader(_ date: Date, now: Date = .now) -> String {
        let cal = Calendar.current
        if cal.isDate(date, inSameDayAs: now) { return String(localized: "Today") }
        if cal.isDateInYesterday(date) { return String(localized: "Yesterday") }
        if cal.isDate(date, equalTo: now, toGranularity: .year) {
            return date.formatted(.dateTime.weekday(.wide).month(.abbreviated).day())
        }
        return date.formatted(.dateTime.month(.abbreviated).day().year())
    }

    /// Time of day only — for rows already grouped under a day header.
    static func time(_ date: Date) -> String {
        date.formatted(date: .omitted, time: .shortened)
    }

    /// Full timestamp for tooltips: "Tuesday, September 22, 2026 at 10:09 PM".
    static func full(_ date: Date) -> String {
        date.formatted(date: .complete, time: .shortened)
    }
}
