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

/// Builds URLs for CCP's Image Server (https://images.evetech.net).
///
/// Sizes must be powers of two in `[32, 1024]`; `size > 1024` returns HTTP 400.
/// Per-endpoint notes on where extra pixels stop buying real detail:
///   - portrait: genuine art up to 1024
///   - type render (ships/structures/drones): genuine art up to 1024
///   - type icon (modules/ammo/blueprints/skills): native 64×64 — larger just
///     upscales and looks soft; use `typeRender` for ship/structure hulls
///   - corp/alliance logo: vector-sourced, crisp at any size
enum EVEImageURL {
    /// Snaps to a valid power-of-two size within `[32, 1024]`.
    /// `nonisolated` to match the URL builders below, which are called off the main actor.
    nonisolated private static func clamp(_ size: Int) -> Int {
        let steps = [32, 64, 128, 256, 512, 1024]
        return steps.last(where: { $0 <= size }) ?? steps.first!
    }

    nonisolated static func characterPortrait(_ characterID: Int, size: Int = 512) -> URL? {
        URL(string: "https://images.evetech.net/characters/\(characterID)/portrait?size=\(clamp(size))")
    }

    nonisolated static func corporationLogo(_ corporationID: Int, size: Int = 256) -> URL? {
        URL(string: "https://images.evetech.net/corporations/\(corporationID)/logo?size=\(clamp(size))")
    }

    nonisolated static func allianceLogo(_ allianceID: Int, size: Int = 256) -> URL? {
        URL(string: "https://images.evetech.net/alliances/\(allianceID)/logo?size=\(clamp(size))")
    }

    /// Inventory-grid icon art. Native resolution is 64×64 — anything larger is upscaled.
    /// For ship/structure hulls use `typeRender` instead.
    nonisolated static func typeIcon(_ typeID: Int, size: Int = 64) -> URL? {
        URL(string: "https://images.evetech.net/types/\(typeID)/icon?size=\(clamp(size))")
    }

    /// Full 3D render (ships, structures, drones, deployables). Genuine art up to 1024×1024.
    nonisolated static func typeRender(_ typeID: Int, size: Int = 512) -> URL? {
        URL(string: "https://images.evetech.net/types/\(typeID)/render?size=\(clamp(size))")
    }
}
