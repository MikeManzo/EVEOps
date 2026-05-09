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

enum EVEImageURL {
    nonisolated static func characterPortrait(_ characterID: Int, size: Int = 128) -> URL? {
        URL(string: "https://images.evetech.net/characters/\(characterID)/portrait?size=\(size)")
    }

    nonisolated static func corporationLogo(_ corporationID: Int, size: Int = 128) -> URL? {
        URL(string: "https://images.evetech.net/corporations/\(corporationID)/logo?size=\(size)")
    }

    nonisolated static func allianceLogo(_ allianceID: Int, size: Int = 128) -> URL? {
        URL(string: "https://images.evetech.net/alliances/\(allianceID)/logo?size=\(size)")
    }

    nonisolated static func typeIcon(_ typeID: Int, size: Int = 64) -> URL? {
        URL(string: "https://images.evetech.net/types/\(typeID)/icon?size=\(size)")
    }

    nonisolated static func typeRender(_ typeID: Int, size: Int = 256) -> URL? {
        URL(string: "https://images.evetech.net/types/\(typeID)/render?size=\(size)")
    }
}
