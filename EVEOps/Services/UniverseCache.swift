import Foundation

/// Persistent disk cache for static ESI universe data (types, groups, systems, constellations, regions, stations, stars).
/// This data changes only on game patches, so we cache aggressively with a 7-day TTL.
actor UniverseCache {
    static let shared = UniverseCache()

    private static let ttl: TimeInterval = 7 * 24 * 3600 // 7 days

    private var types: [Int: ESIType] = [:]
    private var groups: [Int: ESIGroup] = [:]
    private var systems: [Int: ESISolarSystem] = [:]
    private var constellations: [Int: ESIConstellation] = [:]
    private var regions: [Int: ESIRegion] = [:]
    private var stations: [Int: ESIStation] = [:]
    private var stars: [Int: ESIStar] = [:]

    private var dirty = false

    private static let cacheDir: URL = {
        let dir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
            .appendingPathComponent("EVEOps/universe", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()

    private init() {
        loadAll()
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
        save(types, to: "types.json")
        save(groups, to: "groups.json")
        save(systems, to: "systems.json")
        save(constellations, to: "constellations.json")
        save(regions, to: "regions.json")
        save(stations, to: "stations.json")
        save(stars, to: "stars.json")
        dirty = false
    }

    private func loadAll() {
        let meta = loadMeta()
        // If cache is older than TTL, start fresh
        if let saved = meta?.savedDate, Date().timeIntervalSince(saved) > Self.ttl {
            clearDiskCache()
            return
        }

        types = load("types.json") ?? [:]
        groups = load("groups.json") ?? [:]
        systems = load("systems.json") ?? [:]
        constellations = load("constellations.json") ?? [:]
        regions = load("regions.json") ?? [:]
        stations = load("stations.json") ?? [:]
        stars = load("stars.json") ?? [:]
    }

    private func save<T: Encodable>(_ dict: [Int: T], to filename: String) {
        let url = Self.cacheDir.appendingPathComponent(filename)
        let wrapped = Dictionary(uniqueKeysWithValues: dict.map { (String($0.key), $0.value) })
        guard let data = try? JSONEncoder().encode(wrapped) else { return }
        try? data.write(to: url, options: .atomic)
        saveMeta()
    }

    private func load<T: Decodable>(_ filename: String) -> [Int: T]? {
        let url = Self.cacheDir.appendingPathComponent(filename)
        guard let data = try? Data(contentsOf: url),
              let wrapped = try? JSONDecoder().decode([String: T].self, from: data) else { return nil }
        return Dictionary(uniqueKeysWithValues: wrapped.compactMap { key, value in
            guard let id = Int(key) else { return nil }
            return (id, value)
        })
    }

    private struct CacheMeta: Codable {
        let savedDate: Date
    }

    private func saveMeta() {
        let url = Self.cacheDir.appendingPathComponent("meta.json")
        let meta = CacheMeta(savedDate: Date())
        if let data = try? JSONEncoder().encode(meta) {
            try? data.write(to: url, options: .atomic)
        }
    }

    private func loadMeta() -> CacheMeta? {
        let url = Self.cacheDir.appendingPathComponent("meta.json")
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(CacheMeta.self, from: data)
    }

    func clearDiskCache() {
        types.removeAll()
        groups.removeAll()
        systems.removeAll()
        constellations.removeAll()
        regions.removeAll()
        stations.removeAll()
        stars.removeAll()
        try? FileManager.default.removeItem(at: Self.cacheDir)
        try? FileManager.default.createDirectory(at: Self.cacheDir, withIntermediateDirectories: true)
    }
}
