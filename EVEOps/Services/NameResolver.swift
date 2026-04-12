import Foundation

actor NameResolver {
    static let shared = NameResolver()

    private var cache: [Int: String] = [:]
    private var dirty = false
    private static let cacheFileURL: URL = {
        let dir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
            .appendingPathComponent("EVEOps", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("name_cache.json")
    }()

    private init() {
        guard let data = try? Data(contentsOf: Self.cacheFileURL),
              let stored = try? JSONDecoder().decode([String: String].self, from: data) else { return }
        for (key, value) in stored {
            if let id = Int(key) {
                cache[id] = value
            }
        }
    }

    func clearCache() {
        cache.removeAll()
        try? FileManager.default.removeItem(at: Self.cacheFileURL)
        dirty = false
    }

    func saveToDisk() {
        guard dirty else { return }
        let encoded = Dictionary(uniqueKeysWithValues: cache.map { (String($0.key), $0.value) })
        if let data = try? JSONEncoder().encode(encoded) {
            try? data.write(to: Self.cacheFileURL, options: .atomic)
        }
        dirty = false
    }

    // MARK: - Resolution

    /// Batch-resolve IDs to names using universe/names endpoint.
    func resolve(ids: [Int]) async -> [Int: String] {
        let unknownIDs = ids.filter { cache[$0] == nil }

        if !unknownIDs.isEmpty {
            let smallIDs = unknownIDs.filter { $0 > 0 && $0 < Int(Int32.max) }

            for batch in stride(from: 0, to: smallIDs.count, by: 1000) {
                let end = min(batch + 1000, smallIDs.count)
                let chunk = Array(smallIDs[batch..<end])
                do {
                    let url = URL(string: "https://esi.evetech.net/latest/universe/names/?datasource=tranquility")!
                    var request = URLRequest(url: url)
                    request.httpMethod = "POST"
                    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                    request.httpBody = try JSONEncoder().encode(chunk)

                    let (data, response) = try await URLSession.shared.data(for: request)
                    guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
                        continue
                    }
                    let names = try JSONDecoder().decode([UniverseName].self, from: data)
                    for name in names {
                        cache[name.id] = name.name
                    }
                    dirty = true
                } catch {
                    // Continue with next batch
                }
            }

            // Persist after resolving new names
            if dirty { saveToDisk() }
        }

        var result: [Int: String] = [:]
        for id in ids {
            result[id] = cache[id]
        }
        return result
    }

    func resolve(id: Int) async -> String {
        let result = await resolve(ids: [id])
        return result[id] ?? "#\(id)"
    }

    /// Resolves a location ID to a name. Handles NPC stations, player structures, and solar systems.
    func resolveLocation(id: Int, token: String? = nil) async -> String {
        if let cached = cache[id] { return cached }

        // Solar system IDs: 30000000 - 33000000
        if id >= 30_000_000 && id < 33_000_000 {
            if let system: ESISolarSystem = try? await ESIClient.shared.fetch("/universe/systems/\(id)/") {
                cache[id] = system.name
                dirty = true
                saveToDisk()
                return system.name
            }
        }
        // NPC station IDs: 60000000 - 64000000
        else if id >= 60_000_000 && id < 64_000_000 {
            if let station: ESIStation = try? await ESIClient.shared.fetch("/universe/stations/\(id)/") {
                cache[id] = station.name
                dirty = true
                saveToDisk()
                return station.name
            }
        }
        // Player-owned structure IDs: large 64-bit values
        else if id > 1_000_000_000, let token {
            if let structure: ESIStructure = try? await ESIClient.shared.fetch(
                "/universe/structures/\(id)/", token: token
            ) {
                cache[id] = structure.name
                dirty = true
                saveToDisk()
                return structure.name
            }
        }

        // Fallback to universe/names for anything else in int32 range
        if id > 0 && id < Int(Int32.max) {
            let resolved = await resolve(ids: [id])
            if let name = resolved[id] { return name }
        }

        return "#\(id)"
    }

    /// Pre-seed the cache with known name mappings (e.g., from prior lookups)
    func seed(_ names: [Int: String]) {
        for (id, name) in names {
            cache[id] = name
        }
        dirty = true
    }

    private struct UniverseName: Codable {
        let category: String
        let id: Int
        let name: String
    }
}
