import Foundation

/// Persistent disk cache for static ESI universe data (types, groups, systems, constellations, regions, stations, stars).
/// This data changes only on game patches, so we cache aggressively with a 7-day TTL.
actor UniverseCache {
    static let shared = UniverseCache()

    private static let ttl: TimeInterval = 7 * 24 * 3600 // 7 days
    private static let schemaVersion = 3

    private var types: [Int: ESIType] = [:]
    private var groups: [Int: ESIGroup] = [:]
    private var systems: [Int: ESISolarSystem] = [:]
    private var constellations: [Int: ESIConstellation] = [:]
    private var regions: [Int: ESIRegion] = [:]
    private var stations: [Int: ESIStation] = [:]
    private var stars: [Int: ESIStar] = [:]
    private var marketGroups: [Int: ESIMarketGroup] = [:]

    // In-memory cache of all k-space regions (loaded once per app session)
    private var cachedKnownSpaceRegions: [(id: Int, name: String, factionId: Int?)]? = nil

    private var dirty = false

    private static let cacheDir: URL = {
        let dir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
            .appendingPathComponent("EVEOps/universe", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()

    private init() {
        let meta: CacheMeta? = Self.loadMeta()
        if let saved = meta?.savedDate, Date().timeIntervalSince(saved) > Self.ttl {
            Self.clearDiskCacheFiles()
        } else {
            types = Self.loadCache("types.json") ?? [:]
            groups = Self.loadCache("groups.json") ?? [:]
            systems = Self.loadCache("systems.json") ?? [:]
            constellations = Self.loadCache("constellations.json") ?? [:]
            // Only load regions if schema version matches; otherwise evict so they
            // re-fetch with the new factionId field.
            if meta?.schemaVersion == Self.schemaVersion {
                regions = Self.loadCache("regions.json") ?? [:]
            }
            stations = Self.loadCache("stations.json") ?? [:]
            stars = Self.loadCache("stars.json") ?? [:]
            marketGroups = Self.loadCache("marketGroups.json") ?? [:]
        }
    }

    // MARK: - Public API

    func type(id: Int) async -> ESIType? {
        if let cached = types[id] { return cached }
        guard let fetched: ESIType = try? await ESIClient.shared.fetch("/universe/types/\(id)/") else { return nil }
        types[id] = fetched
        dirty = true
        scheduleSave()
        return fetched
    }

    func group(id: Int) async -> ESIGroup? {
        if let cached = groups[id] { return cached }
        guard let fetched: ESIGroup = try? await ESIClient.shared.fetch("/universe/groups/\(id)/") else { return nil }
        groups[id] = fetched
        dirty = true
        scheduleSave()
        return fetched
    }

    func solarSystem(id: Int) async -> ESISolarSystem? {
        if let cached = systems[id] { return cached }
        guard let fetched: ESISolarSystem = try? await ESIClient.shared.fetch("/universe/systems/\(id)/") else { return nil }
        systems[id] = fetched
        dirty = true
        scheduleSave()
        return fetched
    }

    func constellation(id: Int) async -> ESIConstellation? {
        if let cached = constellations[id] { return cached }
        guard let fetched: ESIConstellation = try? await ESIClient.shared.fetch("/universe/constellations/\(id)/") else { return nil }
        constellations[id] = fetched
        dirty = true
        scheduleSave()
        return fetched
    }

    func region(id: Int) async -> ESIRegion? {
        if let cached = regions[id] { return cached }
        guard let fetched: ESIRegion = try? await ESIClient.shared.fetch("/universe/regions/\(id)/") else { return nil }
        regions[id] = fetched
        dirty = true
        scheduleSave()
        return fetched
    }

    func station(id: Int) async -> ESIStation? {
        if let cached = stations[id] { return cached }
        guard let fetched: ESIStation = try? await ESIClient.shared.fetch("/universe/stations/\(id)/") else { return nil }
        stations[id] = fetched
        dirty = true
        scheduleSave()
        return fetched
    }

    func star(id: Int) async -> ESIStar? {
        if let cached = stars[id] { return cached }
        guard let fetched: ESIStar = try? await ESIClient.shared.fetch("/universe/stars/\(id)/") else { return nil }
        stars[id] = fetched
        dirty = true
        scheduleSave()
        return fetched
    }

    /// Returns all k-space regions (excludes wormhole space), sorted by name.
    /// Result is cached in memory for the lifetime of the app session.
    func knownSpaceRegions() async -> [(id: Int, name: String, factionId: Int?)] {
        if let cached = cachedKnownSpaceRegions { return cached }

        guard let regionIds: [Int] = try? await ESIClient.shared.fetch("/universe/regions/") else { return [] }
        let kspaceIds = regionIds.filter { $0 < 11000001 }

        var result: [(id: Int, name: String, factionId: Int?)] = []
        await withTaskGroup(of: (Int, String?, Int?).self) { group in
            for id in kspaceIds {
                group.addTask {
                    let r = await UniverseCache.shared.region(id: id)
                    return (id, r?.name, r?.factionId)
                }
            }
            for await (id, name, factionId) in group {
                if let name { result.append((id: id, name: name, factionId: factionId)) }
            }
        }

        result.sort { $0.name < $1.name }
        cachedKnownSpaceRegions = result
        return result
    }

    /// Batch-fetch multiple types concurrently, returning all resolved types
    func types(ids: [Int]) async -> [Int: ESIType] {
        let uncached = ids.filter { types[$0] == nil }

        if !uncached.isEmpty {
            let results = await withTaskGroup(of: (Int, ESIType?).self) { group in
                for id in uncached {
                    group.addTask {
                        let fetched: ESIType? = try? await ESIClient.shared.fetch("/universe/types/\(id)/")
                        return (id, fetched)
                    }
                }
                var out: [(Int, ESIType?)] = []
                for await result in group { out.append(result) }
                return out
            }
            for (id, typeInfo) in results {
                if let typeInfo { types[id] = typeInfo }
            }
            dirty = true
            scheduleSave()
        }

        var result: [Int: ESIType] = [:]
        for id in ids {
            if let t = types[id] { result[id] = t }
        }
        return result
    }

    /// Batch-fetch multiple groups concurrently
    func groups(ids: Set<Int>) async -> [Int: ESIGroup] {
        let uncached = ids.filter { groups[$0] == nil }

        if !uncached.isEmpty {
            let results = await withTaskGroup(of: (Int, ESIGroup?).self) { group in
                for id in uncached {
                    group.addTask {
                        let fetched: ESIGroup? = try? await ESIClient.shared.fetch("/universe/groups/\(id)/")
                        return (id, fetched)
                    }
                }
                var out: [(Int, ESIGroup?)] = []
                for await result in group { out.append(result) }
                return out
            }
            for (id, groupInfo) in results {
                if let groupInfo { groups[id] = groupInfo }
            }
            dirty = true
            scheduleSave()
        }

        var result: [Int: ESIGroup] = [:]
        for id in ids {
            if let g = groups[id] { result[id] = g }
        }
        return result
    }

    /// Fetches and caches the complete market group tree (~2,000 entries).
    /// After the first load the data is served from the 7-day disk cache, making
    /// subsequent opens instant without any network requests.
    func allMarketGroups() async -> [Int: ESIMarketGroup] {
        guard marketGroups.isEmpty else { return marketGroups }

        guard let ids: [Int] = try? await ESIClient.shared.fetch("/markets/groups/") else {
            return [:]
        }

        let missing = ids.filter { marketGroups[$0] == nil }
        if !missing.isEmpty {
            await withTaskGroup(of: (Int, ESIMarketGroup?).self) { group in
                for id in missing {
                    group.addTask {
                        let g: ESIMarketGroup? = try? await ESIClient.shared.fetch("/markets/groups/\(id)/")
                        return (id, g)
                    }
                }
                for await (id, g) in group {
                    if let g { marketGroups[id] = g }
                }
            }
            dirty = true
            scheduleSave()
        }

        return marketGroups
    }

    // MARK: - Persistence

    private var saveTask: Task<Void, Never>?

    private func scheduleSave() {
        saveTask?.cancel()
        saveTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled else { return }
            await self?.saveAll()
        }
    }

    private func saveAll() {
        guard dirty else { return }
        Self.saveCache(types, to: "types.json")
        Self.saveCache(groups, to: "groups.json")
        Self.saveCache(systems, to: "systems.json")
        Self.saveCache(constellations, to: "constellations.json")
        Self.saveCache(regions, to: "regions.json")
        Self.saveCache(stations, to: "stations.json")
        Self.saveCache(stars, to: "stars.json")
        Self.saveCache(marketGroups, to: "marketGroups.json")
        Self.saveMeta()
        dirty = false
    }

    private nonisolated static func saveCache<T: Encodable>(_ dict: [Int: T], to filename: String) {
        let url = cacheDir.appendingPathComponent(filename)
        let wrapped = Dictionary(uniqueKeysWithValues: dict.map { (String($0.key), $0.value) })
        guard let data = try? JSONEncoder().encode(wrapped) else { return }
        try? data.write(to: url, options: .atomic)
    }

    private nonisolated static func loadCache<T: Decodable>(_ filename: String) -> [Int: T]? {
        let url = cacheDir.appendingPathComponent(filename)
        guard let data = try? Data(contentsOf: url),
              let wrapped = try? JSONDecoder().decode([String: T].self, from: data) else { return nil }
        return Dictionary(uniqueKeysWithValues: wrapped.compactMap { key, value in
            guard let id = Int(key) else { return nil }
            return (id, value)
        })
    }

    private struct CacheMeta: Codable {
        let savedDate: Date
        var schemaVersion: Int?
    }

    private nonisolated static func saveMeta() {
        let url = cacheDir.appendingPathComponent("meta.json")
        let meta = CacheMeta(savedDate: Date(), schemaVersion: schemaVersion)
        if let data = try? JSONEncoder().encode(meta) {
            try? data.write(to: url, options: .atomic)
        }
    }

    private nonisolated static func loadMeta() -> CacheMeta? {
        let url = cacheDir.appendingPathComponent("meta.json")
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(CacheMeta.self, from: data)
    }

    private nonisolated static func clearDiskCacheFiles() {
        try? FileManager.default.removeItem(at: cacheDir)
        try? FileManager.default.createDirectory(at: cacheDir, withIntermediateDirectories: true)
    }

    func clearDiskCache() {
        types.removeAll()
        groups.removeAll()
        systems.removeAll()
        constellations.removeAll()
        regions.removeAll()
        stations.removeAll()
        stars.removeAll()
        marketGroups.removeAll()
        Self.clearDiskCacheFiles()
    }
}
