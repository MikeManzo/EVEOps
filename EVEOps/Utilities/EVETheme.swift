//
// This file is part of EVEOps.
//
// EVEOps is free software: you can redistribute it and/or modify
// it under the terms of the GNU General Public License as published by
// the Free Software Foundation, version 3 or later.
//
// Copyright (c) 2026 CitizenCoder
//

import SwiftUI

/// EVE Online security status → color, matching the in-game client's banding.
/// The single source of truth for security-status color across EVEOps — screens had
/// drifted onto four different gradients (some 3-tier, some 6-tier, different RGB per
/// band) before this. Reuse this rather than adding a local `securityColor` helper.
func eveSecurityColor(_ status: Double) -> Color {
    switch status {
    case 0.9...: return Color(red: 0.3, green: 0.9, blue: 1.0)
    case 0.8..<0.9: return Color(red: 0.0, green: 0.9, blue: 0.8)
    case 0.7..<0.8: return Color(red: 0.0, green: 0.9, blue: 0.4)
    case 0.6..<0.7: return Color(red: 0.4, green: 0.9, blue: 0.0)
    case 0.5..<0.6: return Color(red: 0.9, green: 0.9, blue: 0.0)
    case 0.4..<0.5: return Color(red: 1.0, green: 0.6, blue: 0.0)
    case 0.3..<0.4: return Color(red: 1.0, green: 0.4, blue: 0.0)
    case 0.2..<0.3: return Color(red: 1.0, green: 0.2, blue: 0.0)
    case 0.1..<0.2: return Color(red: 0.9, green: 0.0, blue: 0.0)
    default: return Color(red: 0.6, green: 0.0, blue: 0.0)
    }
}

/// Overload for call sites that only have an optional security status on hand
/// (e.g. a summary that hasn't loaded yet). Unknown reads as a caution amber.
func eveSecurityColor(_ status: Double?) -> Color {
    status.map(eveSecurityColor) ?? EVETheme.warning
}

/// A pilot's personal security status (roughly -10...5), not a solar system's
/// (0.0...1.0) — a different scale entirely, so this is intentionally separate
/// from `eveSecurityColor` rather than sharing its gradient.
func pilotSecurityColor(_ status: Double) -> Color {
    if status >= 0.5 { return .green }
    if status > 0.0 { return .yellow }
    return EVETheme.critical
}

/// EVEOps' cross-app semantic palette — ties a color to a domain (finance, knowledge,
/// industry, ...) so the same concept reads the same color everywhere, instead of each
/// screen picking its own. Extend this rather than reaching for a literal SwiftUI color
/// when adding a new status/domain indicator.
enum EVETheme {
    static let wallet = Color.green
    static let online = Color.green
    static let knowledge = Color.blue      // skill points, training
    static let location = Color.cyan
    static let industry = Color.purple
    static let contracts = Color.teal
    static let colonies = Color.mint
    static let warning = Color.orange
    static let critical = Color.red
}
