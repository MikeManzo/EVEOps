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
import AppKit

/// EVE Online security status → color, matching the in-game client's banding.
/// The single source of truth for security-status color across EVEOps — screens had
/// drifted onto four different gradients (some 3-tier, some 6-tier, different RGB per
/// band) before this. Reuse this rather than adding a local `securityColor` helper.
/// Deliberately not part of `EVEPalette` below — sec-status color is a universal game
/// convention, not something a faction theme should retint.
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
    status.map(eveSecurityColor) ?? EVEUniversalColor.warning
}

/// A pilot's personal security status (roughly -10...5), not a solar system's
/// (0.0...1.0) — a different scale entirely, so this is intentionally separate
/// from `eveSecurityColor` rather than sharing its gradient.
func pilotSecurityColor(_ status: Double) -> Color {
    if status >= 0.5 { return .green }
    if status > 0.0 { return .yellow }
    return EVEUniversalColor.critical
}

/// Colors whose meaning is a universal traffic-light signal (positive/caution/danger),
/// not a category label — these stay the same across every faction theme so "is this
/// good or bad" always reads the same way regardless of the chosen palette.
enum EVEUniversalColor {
    static let online = Color.green
    static let wallet = Color.green
    static let warning = Color.orange
    static let critical = Color.red
}

extension Color {
    /// A color that resolves differently by appearance, the same way the AccentColor
    /// asset does — needed here because faction palettes are defined in code rather
    /// than as catalog color sets.
    static func eveDynamic(light: (Double, Double, Double), dark: (Double, Double, Double)) -> Color {
        Color(NSColor(name: nil, dynamicProvider: { appearance in
            let isDark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            let c = isDark ? dark : light
            return NSColor(red: c.0, green: c.1, blue: c.2, alpha: 1)
        }))
    }
}

/// The full set of colors a screen can pull from — some vary per `FactionTheme`
/// (the "category" slots: accent, knowledge, location, industry, contracts, colonies),
/// others are fixed (`EVEUniversalColor`, folded in here so call sites don't need to
/// know which slots move and which don't).
struct EVEPalette: Equatable {
    let accent: Color
    let knowledge: Color   // skill points, training
    let location: Color
    let industry: Color
    let contracts: Color
    let colonies: Color

    let online: Color = EVEUniversalColor.online
    let wallet: Color = EVEUniversalColor.wallet
    let warning: Color = EVEUniversalColor.warning
    let critical: Color = EVEUniversalColor.critical

    static func == (lhs: EVEPalette, rhs: EVEPalette) -> Bool {
        // Color isn't reliably Equatable across dynamic providers; palettes are only
        // ever compared by which faction produced them, so identity via accent suffices
        // for SwiftUI's diffing purposes here.
        lhs.accent.description == rhs.accent.description
    }
}

/// A selectable app-wide color scheme themed after one of EVE's four playable empires
/// (plus EVEOps' own neutral default) — independent of light/dark appearance, which is
/// still controlled separately in Settings.
enum FactionTheme: String, CaseIterable, Identifiable, Sendable {
    case eveOps
    case caldari
    case gallente
    case amarr
    case minmatar

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .eveOps: return "Default"
        case .caldari: return "Caldari"
        case .gallente: return "Gallente"
        case .amarr: return "Amarr"
        case .minmatar: return "Minmatar"
        }
    }

    var tagline: String {
        switch self {
        case .eveOps: return "EVEOps' own neutral cyan-teal palette."
        case .caldari: return "Cool corporate blue — State Protectorate."
        case .gallente: return "Bio-tech green — Federation."
        case .amarr: return "Imperial gold — Amarr Empire."
        case .minmatar: return "Rust and scrap — Minmatar Republic."
        }
    }

    /// CCP's faction ID for the crest shown in the theme picker — `nil` for EVEOps'
    /// own default, which isn't one of the four playable empires.
    var factionID: Int? {
        switch self {
        case .eveOps: return nil
        case .caldari: return 500001
        case .minmatar: return 500002
        case .amarr: return 500003
        case .gallente: return 500004
        }
    }

    // Hue anchors below were sampled (canvas pixel analysis, not eyeballed) from CCP's own
    // promotional faction art (eveonline.com frontline portraits) and ship hull renders
    // (images.evetech.net) — not invented. Caldari (~210°, steel blue) and Gallente
    // (~145-150°, spring green) matched the original guesses closely; Amarr came back
    // warmer/more bronze than assumed (~30-35°, not ~45° gold-yellow), and Minmatar came
    // back as true oxblood red (~0-8°), not the orange-rust (~20°) originally guessed — the
    // biggest correction. Saturation/lightness are still hand-tuned for UI legibility, since
    // the source art is deliberately dark and moody, not usable as flat accent colors as-is.
    var palette: EVEPalette {
        switch self {
        case .eveOps:
            return EVEPalette(
                accent: .eveDynamic(light: (0.00, 0.55, 0.65), dark: (0.20, 0.80, 0.90)),
                knowledge: .blue,
                location: .cyan,
                industry: .purple,
                contracts: .teal,
                colonies: .mint
            )
        case .caldari:
            return EVEPalette(
                accent: .eveDynamic(light: (0.00, 0.38, 0.80), dark: (0.35, 0.62, 1.00)),
                knowledge: .eveDynamic(light: (0.08, 0.42, 0.85), dark: (0.50, 0.72, 1.00)),
                location: .eveDynamic(light: (0.00, 0.50, 0.78), dark: (0.25, 0.80, 1.00)),
                industry: .eveDynamic(light: (0.18, 0.22, 0.60), dark: (0.45, 0.50, 0.92)),
                contracts: .eveDynamic(light: (0.02, 0.40, 0.58), dark: (0.30, 0.72, 0.90)),
                colonies: .eveDynamic(light: (0.15, 0.50, 0.58), dark: (0.42, 0.80, 0.88))
            )
        case .gallente:
            return EVEPalette(
                accent: .eveDynamic(light: (0.00, 0.48, 0.24), dark: (0.20, 0.85, 0.50)),
                knowledge: .eveDynamic(light: (0.02, 0.44, 0.32), dark: (0.30, 0.82, 0.60)),
                location: .eveDynamic(light: (0.00, 0.48, 0.40), dark: (0.20, 0.85, 0.68)),
                industry: .eveDynamic(light: (0.02, 0.32, 0.12), dark: (0.22, 0.60, 0.35)),
                contracts: .eveDynamic(light: (0.05, 0.48, 0.34), dark: (0.35, 0.85, 0.62)),
                colonies: .eveDynamic(light: (0.28, 0.50, 0.06), dark: (0.62, 0.85, 0.30))
            )
        case .amarr:
            return EVEPalette(
                accent: .eveDynamic(light: (0.62, 0.38, 0.02), dark: (0.92, 0.62, 0.18)),
                knowledge: .eveDynamic(light: (0.66, 0.44, 0.08), dark: (0.96, 0.72, 0.32)),
                location: .eveDynamic(light: (0.55, 0.32, 0.02), dark: (0.88, 0.58, 0.20)),
                industry: .eveDynamic(light: (0.42, 0.26, 0.04), dark: (0.68, 0.48, 0.20)),
                contracts: .eveDynamic(light: (0.55, 0.34, 0.00), dark: (0.90, 0.60, 0.18)),
                colonies: .eveDynamic(light: (0.58, 0.44, 0.20), dark: (0.90, 0.75, 0.48))
            )
        case .minmatar:
            return EVEPalette(
                accent: .eveDynamic(light: (0.62, 0.18, 0.10), dark: (0.90, 0.35, 0.22)),
                knowledge: .eveDynamic(light: (0.56, 0.22, 0.14), dark: (0.85, 0.42, 0.30)),
                location: .eveDynamic(light: (0.58, 0.14, 0.08), dark: (0.88, 0.30, 0.18)),
                industry: .eveDynamic(light: (0.44, 0.10, 0.06), dark: (0.70, 0.25, 0.15)),
                contracts: .eveDynamic(light: (0.50, 0.18, 0.12), dark: (0.80, 0.38, 0.26)),
                colonies: .eveDynamic(light: (0.55, 0.30, 0.22), dark: (0.85, 0.55, 0.42))
            )
        }
    }
}
