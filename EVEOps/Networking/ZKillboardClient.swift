import Foundation

// MARK: - Models

struct ZKBRef: Decodable, Sendable {
    let killmailId: Int
    let zkb: ZKBMeta
}

struct ZKBMeta: Decodable, Sendable {
    let hash: String
    let locationID: Int?
    let totalValue: Double?
    let fittedValue: Double?
    let droppedValue: Double?
    let destroyedValue: Double?
    let npc: Int?   // 0 or 1
    let solo: Int?  // 0 or 1
    let awox: Int?  // 0 or 1
    let points: Int?

    var isNPC: Bool  { (npc  ?? 0) == 1 }
    var isSolo: Bool { (solo ?? 0) == 1 }
    var isAWOX: Bool { (awox ?? 0) == 1 }
}

// MARK: - Client

actor ZKillboardClient {
    static let shared = ZKillboardClient()

    private let session: URLSession

    private init() {
        let config = URLSessionConfiguration.default
        config.httpAdditionalHeaders = [
            "Accept": "application/json",
            "User-Agent": "EVEOps macOS App"
        ]
        session = URLSession(configuration: config)
    }

    /// Fetches all killmail refs for a character from zKillboard, page by page.
    /// Returns newest-first, matching ESI ordering. Stops on empty page.
    func fetchKillRefs(characterID: Int) async throws -> [ZKBRef] {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase

        var allRefs: [ZKBRef] = []
        var page = 1

        while true {
            let url = URL(string: "https://zkillboard.com/api/characterID/\(characterID)/page/\(page)/")!
            let (data, response) = try await session.data(for: URLRequest(url: url))
            guard let httpResponse = response as? HTTPURLResponse else { break }

            if httpResponse.statusCode == 429 {
                try await Task.sleep(nanoseconds: 5_000_000_000)
                continue
            }
            guard httpResponse.statusCode == 200 else { break }

            let refs = try decoder.decode([ZKBRef].self, from: data)
            if refs.isEmpty { break }

            allRefs.append(contentsOf: refs)
            page += 1

            // Respect zKillboard's rate limit between pages
            try await Task.sleep(nanoseconds: 200_000_000)
        }

        return allRefs
    }
}
