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

/// Owns the app's selected faction theme, persisted across launches. One instance is
/// created in EVEOpsApp and injected into every window/popover, the same way
/// AccountManager and the other environment-shared services are — so every screen
/// reads the same live palette instead of each window picking its own.
@Observable
final class ThemeManager {
    private static let storageKey = "factionTheme"

    var faction: FactionTheme {
        didSet {
            guard faction != oldValue else { return }
            UserDefaults.standard.set(faction.rawValue, forKey: Self.storageKey)
        }
    }

    var palette: EVEPalette { faction.palette }

    init() {
        let raw = UserDefaults.standard.string(forKey: Self.storageKey) ?? FactionTheme.eveOps.rawValue
        faction = FactionTheme(rawValue: raw) ?? .eveOps
    }
}
