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
import OSLog

enum ESIError: LocalizedError {
    case invalidURL
    case unauthorized
    case forbidden
    case rateLimited(retryAfter: Int)
    case serverError(statusCode: Int, message: String)
    case decodingError(Error)
    case networkError(Error)
    case noData

    var errorDescription: String? {
        switch self {
        case .invalidURL: return "Invalid URL"
        case .unauthorized: return "Authentication expired. Please log in again."
        case .forbidden: return "Access denied. Your character may lack the required ESI scope or permission."
        case .rateLimited(let retry): return "Rate limited. Retry after \(retry) seconds."
        case .serverError(let code, let msg): return "Server error (\(code)): \(msg)"
        case .decodingError(let err): return "Failed to decode response: \(err.localizedDescription)"
        case .networkError(let err): return "Network error: \(err.localizedDescription)"
        case .noData: return "No data received"
        }
    }
}

actor ESIClient {
    static let shared = ESIClient()

    // MARK: Configuration

    /// ESI host and route version kept separate so a future migration off `/latest`
    /// (or onto a pinned major) is a one-line change instead of a codebase sweep.
    private static let host = "https://esi.evetech.net"
    private static let apiVersion = "latest"
    private static let baseURL = "\(host)/\(apiVersion)"

    /// Appended to every request. `tranquility` is the live server.
    private static let datasource = URLQueryItem(name: "datasource", value: "tranquility")

    private let session: URLSession

    // MARK: Decoding

    // ESI dates are ISO 8601 ("2026-10-09T12:34:56Z"). Building a formatter is far
    // more expensive than using one, and a wallet journal alone carries thousands of
    // dates, so both are built once and shared. They're never mutated after setup,
    // which Foundation documents as safe to use from multiple threads.
    private nonisolated(unsafe) static let isoFormatter = ISO8601DateFormatter()
    private nonisolated static let fallbackFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd'T'HH:mm:ss'Z'"
        f.timeZone = TimeZone(identifier: "UTC")
        return f
    }()

    /// Decoding runs outside the actor (see `decode`) so one large response — a
    /// region's market orders, a full wallet journal — never stalls every other
    /// request waiting on `ESIClient`.
    private nonisolated static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.keyDecodingStrategy = .convertFromSnakeCase
        d.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let dateString = try container.decode(String.self)
            if let date = ESIClient.isoFormatter.date(from: dateString) ?? ESIClient.fallbackFormatter.date(from: dateString) {
                return date
            }
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Cannot decode date: \(dateString)")
        }
        return d
    }()

    private nonisolated static func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        do { return try decoder.decode(T.self, from: data) }
        catch { throw ESIError.decodingError(error) }
    }

    // MARK: Response cache

    /// In-memory response cache keyed by full URL string. Entries are kept past
    /// their `Expires` time as long as they carry an `ETag`, so a stale entry can
    /// be revalidated with a cheap `If-None-Match` request that returns `304` when
    /// nothing changed. `stored` bounds how long a revalidatable entry is retained.
    private var responseCache: [String: CachedResponse] = [:]

    /// Revalidatable (ETag-bearing) entries older than this are dropped by `pruneCache()`.
    private static let maxRevalidateAge: TimeInterval = 24 * 3600

    private struct CachedResponse: Codable, Sendable {
        let data: Data
        let expires: Date
        let etag: String?
        let stored: Date
    }

    // MARK: Disk persistence

    /// The in-memory cache is mirrored to disk so a relaunch starts warm: fresh
    /// entries are served immediately and stale-but-revalidatable ones turn into
    /// cheap `304` round-trips instead of full downloads (and error-budget spend).
    private static let cacheFileURL: URL = {
        let dir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
            .appendingPathComponent("EVEOps", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("esi_response_cache.json")
    }()

    /// Fresh 200 responses stored since the last disk write. Persisting every N
    /// keeps the on-disk copy close to live even without a clean termination.
    private var writesSincePersist = 0
    private static let persistThreshold = 25
    private var didWarmCache = false

    // MARK: In-flight request coalescing

    /// Concurrent unauthenticated GETs to the same URL (e.g. two accounts in the
    /// same corp both resolving that corp's name during prefetch) share one network
    /// round trip instead of firing a duplicate request each. Scoped to `token == nil`
    /// so an authenticated request's success/failure is never shared across accounts.
    private var pendingRequests: [String: Task<(Data, HTTPURLResponse), Error>] = [:]

    private func send(_ request: URLRequest, cacheKey: String, coalesce: Bool) async throws -> (Data, HTTPURLResponse) {
        if coalesce, let pending = pendingRequests[cacheKey] {
            return try await pending.value
        }

        let task = Task<(Data, HTTPURLResponse), Error> {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else { throw ESIError.noData }
            return (data, http)
        }
        if coalesce { pendingRequests[cacheKey] = task }
        defer { if coalesce { pendingRequests[cacheKey] = nil } }
        return try await task.value
    }

    /// Load the persisted cache from disk. Call once, before the first prefetch.
    /// Existing in-memory entries always win, so a request that raced ahead of
    /// this load is never clobbered by a staler disk entry.
    func warmCache() async {
        guard !didWarmCache else { return }
        didWarmCache = true

        let url = Self.cacheFileURL
        let now = Date()
        let maxAge = Self.maxRevalidateAge
        let restored: [String: CachedResponse] = await Task.detached(priority: .utility) {
            guard let data = try? Data(contentsOf: url),
                  let decoded = try? JSONDecoder().decode([String: CachedResponse].self, from: data)
            else { return [:] }
            return decoded.filter { _, entry in
                entry.expires > now || (entry.etag != nil && now.timeIntervalSince(entry.stored) < maxAge)
            }
        }.value

        guard !restored.isEmpty else { return }
        for (key, entry) in restored where responseCache[key] == nil {
            responseCache[key] = entry
        }
        await Logger.network.debug("ESI cache warmed — \(restored.count) entries restored from disk")
    }

    /// Write the current cache to disk. Prunes first so junk is never persisted.
    func persistCache() {
        writesSincePersist = 0
        pruneCache()
        let snapshot = responseCache
        let url = Self.cacheFileURL
        Task.detached(priority: .background) {
            guard let data = try? JSONEncoder().encode(snapshot) else { return }
            try? data.write(to: url, options: .atomic)
        }
    }

    private func notePersistableWrite() {
        writesSincePersist += 1
        if writesSincePersist >= Self.persistThreshold { persistCache() }
    }

    // MARK: Error-limit budget

    // ESI publishes a rolling error budget via response headers. Once it is
    // exhausted every request 420s for the remainder of the window, so we track
    // the budget and voluntarily pause new requests when it runs low rather than
    // discovering the wall by hitting it.
    private var errorLimitRemain = 100
    private var errorLimitResetAt = Date.distantPast
    private let errorLimitFloor = 10

    /// Current error budget, for diagnostics/UI. `remain` is requests left in the
    /// window; `resetAt` is when the window rolls over.
    func errorBudget() -> (remain: Int, resetAt: Date) {
        (errorLimitRemain, errorLimitResetAt)
    }

    // ISO8601 + RFC 1123 date formatters for parsing Expires header
    private static let httpDateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "EEE, dd MMM yyyy HH:mm:ss 'GMT'"
        f.timeZone = TimeZone(identifier: "GMT")
        return f
    }()

    private init() {
        let config = URLSessionConfiguration.default
        // No explicit Accept-Encoding: URLSession negotiates gzip and transparently
        // inflates the body only when the app does not set the header itself.
        config.httpAdditionalHeaders = [
            "Accept": "application/json",
            "User-Agent": HTTPClientInfo.userAgent
        ]
        self.session = URLSession(configuration: config)
    }

    // MARK: URL / request helpers

    private nonisolated func makeURL(_ endpoint: String, extra: [URLQueryItem]? = nil, page: Int? = nil) -> URL? {
        guard var components = URLComponents(string: "\(Self.baseURL)\(endpoint)") else { return nil }
        var items = [Self.datasource]
        if let extra { items.append(contentsOf: extra) }
        if let page { items.append(URLQueryItem(name: "page", value: String(page))) }
        components.queryItems = items
        return components.url
    }

    private nonisolated func makeRequest(_ url: URL, method: String, token: String?) -> URLRequest {
        var request = URLRequest(url: url)
        request.httpMethod = method
        if let token { request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
        return request
    }

    /// Pause if the ESI error budget is nearly spent and the window has not reset yet.
    private func awaitErrorBudget() async {
        guard errorLimitRemain <= errorLimitFloor else { return }
        let wait = errorLimitResetAt.timeIntervalSinceNow
        guard wait > 0 else { return }
        let capped = min(wait, 60)
        await Logger.network.warning("ESI error budget low (\(self.errorLimitRemain) left) — pausing \(String(format: "%.1f", capped))s until reset")
        try? await Task.sleep(nanoseconds: UInt64(capped * 1_000_000_000))
    }

    /// Fold the error-limit headers from every response back into the tracked budget.
    private func noteResponse(_ http: HTTPURLResponse) {
        if let remain = http.value(forHTTPHeaderField: "X-Esi-Error-Limit-Remain").flatMap(Int.init) {
            errorLimitRemain = remain
        }
        if let reset = http.value(forHTTPHeaderField: "X-Esi-Error-Limit-Reset").flatMap(Double.init) {
            errorLimitResetAt = Date().addingTimeInterval(reset)
        }
        if http.statusCode == 420 {
            errorLimitRemain = 0
            let retry = http.value(forHTTPHeaderField: "Retry-After").flatMap(Double.init) ?? 60
            errorLimitResetAt = Date().addingTimeInterval(retry)
        }
    }

    /// Map an HTTP status to `ESIError`. `304` is treated as success — callers that
    /// send `If-None-Match` handle it explicitly before reaching here.
    private func validate(_ http: HTTPURLResponse, data: Data, endpoint: String) async throws {
        switch http.statusCode {
        case 200...299, 304:
            return
        case 401:
            await Logger.network.error("ESI 401 Unauthorized: \(endpoint)")
            throw ESIError.unauthorized
        case 403:
            await Logger.network.error("ESI 403 Forbidden: \(endpoint)")
            throw ESIError.forbidden
        case 420:
            let retryAfter = Int(http.value(forHTTPHeaderField: "Retry-After") ?? "60") ?? 60
            await Logger.network.warning("ESI 420 Rate Limited: retry after \(retryAfter)s — \(endpoint)")
            throw ESIError.rateLimited(retryAfter: retryAfter)
        default:
            let body = String(data: data, encoding: .utf8) ?? "Unknown error"
            await Logger.network.error("ESI \(http.statusCode) for \(endpoint): \(body)")
            throw ESIError.serverError(statusCode: http.statusCode, message: body)
        }
    }

    /// Parse the `Expires` header; returns a date only when it is in the future.
    private static func futureExpiry(from http: HTTPURLResponse) -> Date? {
        guard let raw = http.value(forHTTPHeaderField: "Expires"),
              let date = httpDateFormatter.date(from: raw),
              date > Date() else { return nil }
        return date
    }

    // MARK: GET (single resource)

    /// A response body and where it came from. A cached body was stored by an earlier
    /// call that may have decoded a different type from the same URL, so a decode
    /// failure on one means "drop the entry and re-request", not "bad data".
    private struct RawResponse: Sendable {
        let data: Data
        let cacheKey: String
        let fromCache: Bool
        let totalPages: Int
    }

    /// Cache lookup, revalidation, network, and cache store for one GET — everything
    /// that touches actor state. Decoding is left to the nonisolated caller.
    /// `cacheMultiPage: false` stores only single-page results (see `fetchPages`).
    private func loadRaw(_ url: URL, endpoint: String, token: String?, bypassCache: Bool, cacheMultiPage: Bool) async throws -> RawResponse {
        let cacheKey = url.absoluteString
        let cached = responseCache[cacheKey]

        // Fast path: unexpired cache entry.
        if !bypassCache, let cached, cached.expires > Date() {
            return RawResponse(data: cached.data, cacheKey: cacheKey, fromCache: true, totalPages: 1)
        }

        await awaitErrorBudget()

        var request = makeRequest(url, method: "GET", token: token)
        if bypassCache {
            request.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        } else if let etag = cached?.etag {
            request.setValue(etag, forHTTPHeaderField: "If-None-Match")
        }

        let (data, http): (Data, HTTPURLResponse)
        do {
            (data, http) = try await send(request, cacheKey: cacheKey, coalesce: token == nil)
        } catch {
            if (error as? URLError)?.code != .cancelled {
                await Logger.network.error("ESI network error for \(endpoint): \(error.localizedDescription)")
            }
            throw ESIError.networkError(error)
        }

        noteResponse(http)

        // Not modified — serve the cached body, refresh its freshness window.
        if http.statusCode == 304, let cached {
            responseCache[cacheKey] = CachedResponse(
                data: cached.data,
                expires: Self.futureExpiry(from: http) ?? cached.expires,
                etag: http.value(forHTTPHeaderField: "ETag") ?? cached.etag,
                stored: Date()
            )
            return RawResponse(data: cached.data, cacheKey: cacheKey, fromCache: true, totalPages: 1)
        }

        try await validate(http, data: data, endpoint: endpoint)

        // Store: keep the ETag even without an Expires so the next call can revalidate.
        let totalPages = Int(http.value(forHTTPHeaderField: "X-Pages") ?? "1") ?? 1
        if cacheMultiPage || totalPages == 1 {
            let etag = http.value(forHTTPHeaderField: "ETag")
            if let expiry = Self.futureExpiry(from: http) {
                responseCache[cacheKey] = CachedResponse(data: data, expires: expiry, etag: etag, stored: Date())
                notePersistableWrite()
            } else if let etag {
                responseCache[cacheKey] = CachedResponse(data: data, expires: Date(), etag: etag, stored: Date())
                notePersistableWrite()
            }
        }

        return RawResponse(data: data, cacheKey: cacheKey, fromCache: false, totalPages: totalPages)
    }

    private func dropCacheEntry(_ key: String) {
        responseCache[key] = nil
    }

    @concurrent
    nonisolated func fetch<T: Decodable>(_ endpoint: String, token: String? = nil, queryItems: [URLQueryItem]? = nil, bypassCache: Bool = false) async throws -> T {
        guard let url = makeURL(endpoint, extra: queryItems) else { throw ESIError.invalidURL }
        let raw = try await loadRaw(url, endpoint: endpoint, token: token, bypassCache: bypassCache, cacheMultiPage: true)
        do {
            return try Self.decode(T.self, from: raw.data)
        } catch {
            guard raw.fromCache else { throw error }
            // Cached bytes don't match the requested type (two call sites, one URL):
            // drop the entry and re-request without revalidation.
            await dropCacheEntry(raw.cacheKey)
            return try await fetch(endpoint, token: token, queryItems: queryItems, bypassCache: true)
        }
    }

    // MARK: Mutating verbs

    @concurrent
    nonisolated func post<Body: Encodable, Response: Decodable>(_ endpoint: String, body: Body, token: String? = nil, queryItems: [URLQueryItem]? = nil) async throws -> Response {
        let data = try await postRaw(endpoint, body: body, token: token, queryItems: queryItems)
        return try Self.decode(Response.self, from: data)
    }

    private func postRaw<Body: Encodable>(_ endpoint: String, body: Body, token: String?, queryItems: [URLQueryItem]?) async throws -> Data {
        guard let url = makeURL(endpoint, extra: queryItems) else { throw ESIError.invalidURL }

        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        let bodyData: Data
        do { bodyData = try encoder.encode(body) } catch { throw ESIError.decodingError(error) }

        await awaitErrorBudget()

        var request = makeRequest(url, method: "POST", token: token)
        request.httpBody = bodyData
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let (data, response): (Data, URLResponse)
        do { (data, response) = try await session.data(for: request) } catch { throw ESIError.networkError(error) }

        guard let http = response as? HTTPURLResponse else { throw ESIError.noData }
        noteResponse(http)
        try await validate(http, data: data, endpoint: endpoint)
        return data
    }

    /// PUT with JSON body, discards response body (for 204 responses)
    func put<Body: Encodable>(_ endpoint: String, body: Body, token: String? = nil, queryItems: [URLQueryItem]? = nil) async throws {
        guard let url = makeURL(endpoint, extra: queryItems) else { throw ESIError.invalidURL }

        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        let bodyData: Data
        do { bodyData = try encoder.encode(body) } catch { throw ESIError.decodingError(error) }

        await awaitErrorBudget()

        var request = makeRequest(url, method: "PUT", token: token)
        request.httpBody = bodyData
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let (data, response): (Data, URLResponse)
        do { (data, response) = try await session.data(for: request) } catch { throw ESIError.networkError(error) }

        guard let http = response as? HTTPURLResponse else { throw ESIError.noData }
        noteResponse(http)
        try await validate(http, data: data, endpoint: endpoint)
    }

    /// DELETE with optional query items, no response body
    func delete(_ endpoint: String, token: String? = nil, queryItems: [URLQueryItem]? = nil) async throws {
        guard let url = makeURL(endpoint, extra: queryItems) else { throw ESIError.invalidURL }

        await awaitErrorBudget()

        let request = makeRequest(url, method: "DELETE", token: token)

        let (data, response): (Data, URLResponse)
        do { (data, response) = try await session.data(for: request) } catch { throw ESIError.networkError(error) }

        guard let http = response as? HTTPURLResponse else { throw ESIError.noData }
        noteResponse(http)
        try await validate(http, data: data, endpoint: endpoint)
    }

    /// POST with only query params and no body — used for UI endpoints like autopilot waypoint
    func postAction(_ endpoint: String, token: String? = nil, queryItems: [URLQueryItem]? = nil) async throws {
        guard let url = makeURL(endpoint, extra: queryItems) else { throw ESIError.invalidURL }

        await awaitErrorBudget()

        let request = makeRequest(url, method: "POST", token: token)

        let (data, response): (Data, URLResponse)
        do { (data, response) = try await session.data(for: request) } catch { throw ESIError.networkError(error) }

        guard let http = response as? HTTPURLResponse else { throw ESIError.noData }
        noteResponse(http)
        try await validate(http, data: data, endpoint: endpoint)
    }

    /// POST with JSON body, discards response body (for 204 responses)
    func postVoid<Body: Encodable>(_ endpoint: String, body: Body, token: String? = nil, queryItems: [URLQueryItem]? = nil) async throws {
        guard let url = makeURL(endpoint, extra: queryItems) else { throw ESIError.invalidURL }

        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        let bodyData: Data
        do { bodyData = try encoder.encode(body) } catch { throw ESIError.decodingError(error) }

        await awaitErrorBudget()

        var request = makeRequest(url, method: "POST", token: token)
        request.httpBody = bodyData
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let (data, response): (Data, URLResponse)
        do { (data, response) = try await session.data(for: request) } catch { throw ESIError.networkError(error) }

        guard let http = response as? HTTPURLResponse else { throw ESIError.noData }
        noteResponse(http)
        try await validate(http, data: data, endpoint: endpoint)
    }

    // MARK: GET (paginated)

    @concurrent
    nonisolated func fetchPages<T: Decodable>(_ endpoint: String, token: String? = nil, bypassCache: Bool = false) async throws -> [T] {
        guard let firstURL = makeURL(endpoint, page: 1) else { throw ESIError.invalidURL }
        // Only single-page results are ever cached; a multi-page set has no single
        // body to store and revalidate against.
        let first = try await loadRaw(firstURL, endpoint: endpoint, token: token, bypassCache: bypassCache, cacheMultiPage: false)

        var results: [T]
        do {
            results = try Self.decode([T].self, from: first.data)
        } catch {
            guard first.fromCache else { throw error }
            await dropCacheEntry(first.cacheKey)
            return try await fetchPages(endpoint, token: token, bypassCache: true)
        }

        guard first.totalPages > 1 else { return results }
        try await withThrowingTaskGroup(of: [T].self) { group in
            for page in 2...first.totalPages {
                group.addTask {
                    let pageData = try await self.loadPage(endpoint, page: page, token: token)
                    return try Self.decode([T].self, from: pageData)
                }
            }
            for try await pageResults in group {
                results.append(contentsOf: pageResults)
            }
        }
        return results
    }

    /// Pages 2…N of a paginated GET. Never cached — see `fetchPages`.
    private func loadPage(_ endpoint: String, page: Int, token: String?) async throws -> Data {
        await awaitErrorBudget()
        guard let pageURL = makeURL(endpoint, page: page) else { throw ESIError.invalidURL }
        let req = makeRequest(pageURL, method: "GET", token: token)
        let (pageData, pageResponse) = try await session.data(for: req)
        guard let pageHTTP = pageResponse as? HTTPURLResponse else { throw ESIError.noData }
        noteResponse(pageHTTP)
        guard pageHTTP.statusCode == 200 else {
            if pageHTTP.statusCode == 401 { throw ESIError.unauthorized }
            throw ESIError.noData
        }
        return pageData
    }

    // MARK: Cache maintenance

    /// Evict cache entries whose key contains the given path string
    func evictCache(matching path: String) {
        responseCache = responseCache.filter { !$0.key.contains(path) }
    }

    /// Evict entries that are neither fresh nor usefully revalidatable.
    func pruneCache() {
        let now = Date()
        responseCache = responseCache.filter { _, entry in
            entry.expires > now || (entry.etag != nil && now.timeIntervalSince(entry.stored) < Self.maxRevalidateAge)
        }
    }

    /// Clear the entire in-memory response cache
    func clearCache() {
        responseCache.removeAll()
    }

    /// Clear ALL response caches — the in-memory cache, the persisted disk mirror,
    /// and URLSession's HTTP disk cache. Call this before any forced refresh so
    /// stale responses never mask updated data.
    func clearAllCaches() {
        responseCache.removeAll()
        writesSincePersist = 0
        URLCache.shared.removeAllCachedResponses()
        let url = Self.cacheFileURL
        Task.detached(priority: .background) {
            try? FileManager.default.removeItem(at: url)
        }
    }
}
