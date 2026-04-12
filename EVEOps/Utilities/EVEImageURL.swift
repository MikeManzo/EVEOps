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
