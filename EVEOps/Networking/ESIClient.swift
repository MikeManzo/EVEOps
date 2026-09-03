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
    private let decoder: JSONDecoder

    // MARK: Response cache

    /// In-memory response cache keyed by full URL string. Entries are kept past
    /// their `Expires` time as long as they carry an `ETag`, so a stale entry can
    /// be revalidated with a cheap `If-None-Match` request that returns `304` when
    /// nothing changed. `stored` bounds how long a revalidatable entry is retained.
    private var responseCache: [String: CachedResponse] = [:]

    /// Revalidatable (ETag-bearing) entries older than this are dropped by `pruneCache()`.
    private static let maxRevalidateAge: TimeInterval = 24 * 3600

    private struct CachedResponse {
        let data: Data
        let expires: Date
        let etag: String?
        let stored: Date
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

        self.decoder = JSONDecoder()
        self.decoder.keyDecodingStrategy = .convertFromSnakeCase
        self.decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let dateString = try container.decode(String.self)
            if let date = ISO8601DateFormatter().date(from: dateString) {
                return date
            }
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss'Z'"
            formatter.timeZone = TimeZone(identifier: "UTC")
            if let date = formatter.date(from: dateString) {
                return date
            }
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Cannot decode date: \(dateString)")
        }
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

    func fetch<T: Decodable>(_ endpoint: String, token: String? = nil, queryItems: [URLQueryItem]? = nil, bypassCache: Bool = false) async throws -> T {
        guard let url = makeURL(endpoint, extra: queryItems) else { throw ESIError.invalidURL }
        let cacheKey = url.absoluteString
        let cached = responseCache[cacheKey]

        // Fast path: unexpired cache entry.
        if !bypassCache, let cached, cached.expires > Date(),
           let decoded = try? decoder.decode(T.self, from: cached.data) {
            return decoded
        }

        await awaitErrorBudget()

        var request = makeRequest(url, method: "GET", token: token)
        if bypassCache {
            request.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        } else if let etag = cached?.etag {
            request.setValue(etag, forHTTPHeaderField: "If-None-Match")
        }

        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            if (error as? URLError)?.code != .cancelled {
                await Logger.network.error("ESI network error for \(endpoint): \(error.localizedDescription)")
            }
            throw ESIError.networkError(error)
        }

        guard let http = response as? HTTPURLResponse else { throw ESIError.noData }
        noteResponse(http)

        // Not modified — serve the cached body, refresh its freshness window.
        if http.statusCode == 304, let cached {
            if let decoded = try? decoder.decode(T.self, from: cached.data) {
                responseCache[cacheKey] = CachedResponse(
                    data: cached.data,
                    expires: Self.futureExpiry(from: http) ?? cached.expires,
                    etag: http.value(forHTTPHeaderField: "ETag") ?? cached.etag,
                    stored: Date()
                )
                return decoded
            }
            // Cached bytes don't match the requested type (two call sites, one URL):
            // drop the entry and re-request without revalidation.
            responseCache[cacheKey] = nil
            return try await fetch(endpoint, token: token, queryItems: queryItems, bypassCache: true)
        }

        try await validate(http, data: data, endpoint: endpoint)

        // Store: keep the ETag even without an Expires so the next call can revalidate.
        let etag = http.value(forHTTPHeaderField: "ETag")
        if let expiry = Self.futureExpiry(from: http) {
            responseCache[cacheKey] = CachedResponse(data: data, expires: expiry, etag: etag, stored: Date())
        } else if let etag {
            responseCache[cacheKey] = CachedResponse(data: data, expires: Date(), etag: etag, stored: Date())
        }

        do { return try decoder.decode(T.self, from: data) }
        catch { throw ESIError.decodingError(error) }
    }

    // MARK: Mutating verbs

    func post<Body: Encodable, Response: Decodable>(_ endpoint: String, body: Body, token: String? = nil, queryItems: [URLQueryItem]? = nil) async throws -> Response {
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
        do { return try decoder.decode(Response.self, from: data) } catch { throw ESIError.decodingError(error) }
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

    func fetchPages<T: Decodable>(_ endpoint: String, token: String? = nil, bypassCache: Bool = false) async throws -> [T] {
        guard let firstURL = makeURL(endpoint, page: 1) else { throw ESIError.invalidURL }
        let cacheKey = firstURL.absoluteString
        let cached = responseCache[cacheKey]

        // Fast path — only single-page results are ever cached (see below).
        if !bypassCache, let cached, cached.expires > Date(),
           let results = try? decoder.decode([T].self, from: cached.data) {
            return results
        }

        await awaitErrorBudget()

        var request = makeRequest(firstURL, method: "GET", token: token)
        if bypassCache {
            request.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        } else if let etag = cached?.etag {
            request.setValue(etag, forHTTPHeaderField: "If-None-Match")
        }

        let (data, response): (Data, URLResponse)
        do { (data, response) = try await session.data(for: request) } catch { throw ESIError.networkError(error) }

        guard let http = response as? HTTPURLResponse else { throw ESIError.noData }
        noteResponse(http)

        if http.statusCode == 304, let cached {
            if let results = try? decoder.decode([T].self, from: cached.data) {
                responseCache[cacheKey] = CachedResponse(
                    data: cached.data,
                    expires: Self.futureExpiry(from: http) ?? cached.expires,
                    etag: http.value(forHTTPHeaderField: "ETag") ?? cached.etag,
                    stored: Date()
                )
                return results
            }
            responseCache[cacheKey] = nil
            return try await fetchPages(endpoint, token: token, bypassCache: true)
        }

        try await validate(http, data: data, endpoint: endpoint)

        var results: [T] = try decoder.decode([T].self, from: data)
        let totalPages = Int(http.value(forHTTPHeaderField: "X-Pages") ?? "1") ?? 1

        // Only single-page responses are cached; a multi-page set has no single
        // body to store and revalidate against.
        if totalPages == 1 {
            let etag = http.value(forHTTPHeaderField: "ETag")
            if let expiry = Self.futureExpiry(from: http) {
                responseCache[cacheKey] = CachedResponse(data: data, expires: expiry, etag: etag, stored: Date())
            } else if let etag {
                responseCache[cacheKey] = CachedResponse(data: data, expires: Date(), etag: etag, stored: Date())
            }
        }

        if totalPages > 1 {
            try await withThrowingTaskGroup(of: [T].self) { group in
                for page in 2...totalPages {
                    group.addTask {
                        await self.awaitErrorBudget()
                        guard let pageURL = self.makeURL(endpoint, page: page) else { throw ESIError.invalidURL }
                        let req = self.makeRequest(pageURL, method: "GET", token: token)
                        let (pageData, pageResponse) = try await self.session.data(for: req)
                        guard let pageHTTP = pageResponse as? HTTPURLResponse else { throw ESIError.noData }
                        await self.noteResponse(pageHTTP)
                        guard pageHTTP.statusCode == 200 else {
                            if pageHTTP.statusCode == 401 { throw ESIError.unauthorized }
                            throw ESIError.noData
                        }
                        return try self.decoder.decode([T].self, from: pageData)
                    }
                }
                for try await pageResults in group {
                    results.append(contentsOf: pageResults)
                }
            }
        }

        return results
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

    /// Clear ALL response caches — both the in-memory cache and URLSession's HTTP disk cache.
    /// Call this before any forced refresh so stale HTTP responses never mask updated data.
    func clearAllCaches() {
        responseCache.removeAll()
        URLCache.shared.removeAllCachedResponses()
    }
}
