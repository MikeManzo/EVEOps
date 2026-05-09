import Foundation

// Mark:  Models

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
    let npc: Bool?
    let solo: Bool?
    let awox: Bool?
    let points: Int?

    var isNPC: Bool  { npc  ?? false }
    var isSolo: Bool { solo ?? false }
    var isAWOX: Bool { awox ?? false }
}

// Mark:  Client

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

    /// Fetches recent kills from active PvP regions (The Forge + Domain) concurrently.
    /// zKillboard requires an entity filter — bare /api/kills/ is not permitted.
    func fetchRecentKillRefs() async throws -> [ZKBRef] {
        // 10000002 = The Forge (Jita), 10000043 = Domain (Amarr) — both confirmed active
        let regionIds = [10000002, 10000043]
        return try await withThrowingTaskGroup(of: [ZKBRef].self) { group in
            for regionId in regionIds {
                group.addTask {
                    let decoder = JSONDecoder()
                    decoder.keyDecodingStrategy = .convertFromSnakeCase
                    let url = URL(string: "https://zkillboard.com/api/kills/regionID/\(regionId)/page/1/")!
                    let (data, response) = try await self.session.data(for: URLRequest(url: url))
                    guard let http = response as? HTTPURLResponse, http.statusCode == 200 else { return [] }
                    return (try? decoder.decode([ZKBRef].self, from: data)) ?? []
                }
            }
            var all: [ZKBRef] = []
            for try await refs in group { all.append(contentsOf: refs) }
            // Deduplicate in case the same kill appears in both regions
            var seen = Set<Int>()
            return all.filter { seen.insert($0.killmailId).inserted }
        }
    }

    /// Fetches the first page of loss refs for a ship type from zKillboard (community losses).
    func fetchLossRefs(shipTypeID: Int) async throws -> [ZKBRef] {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let url = URL(string: "https://zkillboard.com/api/losses/shipTypeID/\(shipTypeID)/page/1/")!
        let (data, response) = try await session.data(for: URLRequest(url: url))
        guard let http = response as? HTTPURLResponse else { return [] }
        if http.statusCode == 429 {
            try await Task.sleep(nanoseconds: 5_000_000_000)
            return try await fetchLossRefs(shipTypeID: shipTypeID)
        }
        guard http.statusCode == 200 else { return [] }
        return (try? decoder.decode([ZKBRef].self, from: data)) ?? []
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
