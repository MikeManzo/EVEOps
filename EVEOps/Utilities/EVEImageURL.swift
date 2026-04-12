import Foundation

enum EVEImageURL {
    static func characterPortrait(_ characterID: Int, size: Int = 128) -> URL? {
        URL(string: "https://images.evetech.net/characters/\(characterID)/portrait?size=\(size)")
    }

    static func corporationLogo(_ corporationID: Int, size: Int = 128) -> URL? {
        URL(string: "https://images.evetech.net/corporations/\(corporationID)/logo?size=\(size)")
    }

    static func allianceLogo(_ allianceID: Int, size: Int = 128) -> URL? {
        URL(string: "https://images.evetech.net/alliances/\(allianceID)/logo?size=\(size)")
    }

    static func typeIcon(_ typeID: Int, size: Int = 64) -> URL? {
        URL(string: "https://images.evetech.net/types/\(typeID)/icon?size=\(size)")
    }

    static func typeRender(_ typeID: Int, size: Int = 256) -> URL? {
        URL(string: "https://images.evetech.net/types/\(typeID)/render?size=\(size)")
    }
}
