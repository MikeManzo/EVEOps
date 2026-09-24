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

nonisolated enum EVEFormatters {
    static let iskFormatter: NumberFormatter = {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.maximumFractionDigits = 2
        f.minimumFractionDigits = 2
        return f
    }()

    static func formatISK(_ value: Double) -> String {
        let formatted = iskFormatter.string(from: NSNumber(value: value)) ?? String(format: "%.2f", value)
        return "\(formatted) ISK"
    }

    static func formatISKShort(_ value: Double) -> String {
        let abs = abs(value)
        let sign = value < 0 ? "-" : ""
        switch abs {
        case 1_000_000_000_000...:
            return "\(sign)\(String(format: "%.1fT", abs / 1_000_000_000_000)) ISK"
        case 1_000_000_000...:
            return "\(sign)\(String(format: "%.1fB", abs / 1_000_000_000)) ISK"
        case 1_000_000...:
            return "\(sign)\(String(format: "%.1fM", abs / 1_000_000)) ISK"
        case 1_000...:
            return "\(sign)\(String(format: "%.1fK", abs / 1_000)) ISK"
        case ..<0.5:
            // Zero (and sub-half-ISK dust) reads as a plain "0 ISK" rather than "0.00 ISK".
            return "0 ISK"
        default:
            // Under 1K the cents are noise in a summary figure: "450 ISK", not "450.00 ISK".
            return "\(sign)\(Int(abs.rounded())) ISK"
        }
    }

    /// Skill points, abbreviated: "12.3M SP", "450K SP", "900 SP". Pass `unit: false` where
    /// the "SP" suffix is already in the label (e.g. a "Skill Points" tile).
    static func formatSP(_ sp: Int, unit: Bool = true) -> String {
        let suffix = unit ? " SP" : ""
        if sp >= 1_000_000 { return String(format: "%.1fM", Double(sp) / 1_000_000) + suffix }
        if sp >= 1_000 { return String(format: "%.0fK", Double(sp) / 1_000) + suffix }
        return "\(sp)" + suffix
    }

    /// True for amounts that display as zero — used to render them neutral rather than as
    /// a gain or loss.
    static func isZeroISK(_ value: Double) -> Bool { Swift.abs(value) < 0.5 }

    static func formatDuration(_ seconds: Int) -> String {
        let days = seconds / 86400
        let hours = (seconds % 86400) / 3600
        let minutes = (seconds % 3600) / 60

        if days > 0 {
            return "\(days)d \(hours)h \(minutes)m"
        } else if hours > 0 {
            return "\(hours)h \(minutes)m"
        } else {
            return "\(minutes)m"
        }
    }

    static func timeUntil(_ date: Date) -> String {
        let interval = date.timeIntervalSinceNow
        if interval <= 0 { return "Done" }
        return formatDuration(Int(interval))
    }

    static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .short
        return f
    }()
}
