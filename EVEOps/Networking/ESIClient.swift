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

    private let baseURL = "https://esi.evetech.net/latest"
    private let session: URLSession
    private let decoder: JSONDecoder

    // In-memory response cache keyed by full URL string
    private var responseCache: [String: CachedResponse] = [:]

    private struct CachedResponse {
        let data: Data
        let expires: Date
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
        config.httpAdditionalHeaders = [
            "Accept": "application/json",
            "User-Agent": "EVEOps macOS App"
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

    func fetch<T: Decodable>(_ endpoint: String, token: String? = nil, queryItems: [URLQueryItem]? = nil, bypassCache: Bool = false) async throws -> T {
        guard var components = URLComponents(string: "\(baseURL)\(endpoint)") else {
            throw ESIError.invalidURL
        }
        var allItems = queryItems ?? []
        allItems.append(URLQueryItem(name: "datasource", value: "tranquility"))
        components.queryItems = allItems

        guard let url = components.url else {
            throw ESIError.invalidURL
        }

        let cacheKey = url.absoluteString

        // Check in-memory cache unless explicitly bypassed
        if !bypassCache, let cached = responseCache[cacheKey], cached.expires > Date() {
            do {
                return try decoder.decode(T.self, from: cached.data)
            } catch {
                // Cache decode failed (type mismatch), fall through to network
            }
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        // Bypass both our cache and URLSession's HTTP disk cache when forced
        if bypassCache {
            request.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        }
        if let token = token {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw ESIError.networkError(error)
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            throw ESIError.noData
        }

        switch httpResponse.statusCode {
        case 200...299:
            break
        case 401: throw ESIError.unauthorized
        case 403: throw ESIError.forbidden
        case 420:
            let retryAfter = Int(httpResponse.value(forHTTPHeaderField: "Retry-After") ?? "60") ?? 60
            throw ESIError.rateLimited(retryAfter: retryAfter)
        default:
            let body = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw ESIError.serverError(statusCode: httpResponse.statusCode, message: body)
        }

        // Cache the response using the Expires header
        if let expiresString = httpResponse.value(forHTTPHeaderField: "Expires"),
           let expiresDate = Self.httpDateFormatter.date(from: expiresString),
           expiresDate > Date() {
            responseCache[cacheKey] = CachedResponse(data: data, expires: expiresDate)
        }

        do {
            return try decoder.decode(T.self, from: data)
        } catch {
            throw ESIError.decodingError(error)
        }
    }

    func post<Body: Encodable, Response: Decodable>(_ endpoint: String, body: Body, token: String? = nil, queryItems: [URLQueryItem]? = nil) async throws -> Response {
        guard var components = URLComponents(string: "\(baseURL)\(endpoint)") else {
            throw ESIError.invalidURL
        }
        var allItems = [URLQueryItem(name: "datasource", value: "tranquility")]
        if let extra = queryItems { allItems.append(contentsOf: extra) }
        components.queryItems = allItems
        guard let url = components.url else { throw ESIError.invalidURL }

        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        let bodyData: Data
        do { bodyData = try encoder.encode(body) } catch { throw ESIError.decodingError(error) }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.httpBody = bodyData
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let token { request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }

        let (data, response): (Data, URLResponse)
        do { (data, response) = try await session.data(for: request) } catch { throw ESIError.networkError(error) }

        guard let httpResponse = response as? HTTPURLResponse else { throw ESIError.noData }
        switch httpResponse.statusCode {
        case 200...299: break
        case 401: throw ESIError.unauthorized
        case 403: throw ESIError.forbidden
        case 420:
            let retryAfter = Int(httpResponse.value(forHTTPHeaderField: "Retry-After") ?? "60") ?? 60
            throw ESIError.rateLimited(retryAfter: retryAfter)
        default:
            let msg = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw ESIError.serverError(statusCode: httpResponse.statusCode, message: msg)
        }
        do { return try decoder.decode(Response.self, from: data) } catch { throw ESIError.decodingError(error) }
    }

    /// PUT with JSON body, discards response body (for 204 responses)
    func put<Body: Encodable>(_ endpoint: String, body: Body, token: String? = nil, queryItems: [URLQueryItem]? = nil) async throws {
        guard var components = URLComponents(string: "\(baseURL)\(endpoint)") else { throw ESIError.invalidURL }
        var allItems = [URLQueryItem(name: "datasource", value: "tranquility")]
        if let extra = queryItems { allItems.append(contentsOf: extra) }
        components.queryItems = allItems
        guard let url = components.url else { throw ESIError.invalidURL }

        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        let bodyData: Data
        do { bodyData = try encoder.encode(body) } catch { throw ESIError.decodingError(error) }

        var request = URLRequest(url: url)
        request.httpMethod = "PUT"
        request.httpBody = bodyData
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let token { request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }

        let (data, response): (Data, URLResponse)
        do { (data, response) = try await session.data(for: request) } catch { throw ESIError.networkError(error) }

        guard let httpResponse = response as? HTTPURLResponse else { throw ESIError.noData }
        switch httpResponse.statusCode {
        case 200...299: break
        case 401: throw ESIError.unauthorized
        case 403: throw ESIError.forbidden
        case 420:
            let retryAfter = Int(httpResponse.value(forHTTPHeaderField: "Retry-After") ?? "60") ?? 60
            throw ESIError.rateLimited(retryAfter: retryAfter)
        default:
            let msg = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw ESIError.serverError(statusCode: httpResponse.statusCode, message: msg)
        }
    }

    /// DELETE with optional query items, no response body
    func delete(_ endpoint: String, token: String? = nil, queryItems: [URLQueryItem]? = nil) async throws {
        guard var components = URLComponents(string: "\(baseURL)\(endpoint)") else { throw ESIError.invalidURL }
        var allItems = [URLQueryItem(name: "datasource", value: "tranquility")]
        if let extra = queryItems { allItems.append(contentsOf: extra) }
        components.queryItems = allItems
        guard let url = components.url else { throw ESIError.invalidURL }

        var request = URLRequest(url: url)
        request.httpMethod = "DELETE"
        if let token { request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }

        let (data, response): (Data, URLResponse)
        do { (data, response) = try await session.data(for: request) } catch { throw ESIError.networkError(error) }

        guard let httpResponse = response as? HTTPURLResponse else { throw ESIError.noData }
        switch httpResponse.statusCode {
        case 200...299: break
        case 401: throw ESIError.unauthorized
        case 403: throw ESIError.forbidden
        case 420:
            let retryAfter = Int(httpResponse.value(forHTTPHeaderField: "Retry-After") ?? "60") ?? 60
            throw ESIError.rateLimited(retryAfter: retryAfter)
        default:
            let msg = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw ESIError.serverError(statusCode: httpResponse.statusCode, message: msg)
        }
    }

    /// POST with only query params and no body — used for UI endpoints like autopilot waypoint
    func postAction(_ endpoint: String, token: String? = nil, queryItems: [URLQueryItem]? = nil) async throws {
        guard var components = URLComponents(string: "\(baseURL)\(endpoint)") else { throw ESIError.invalidURL }
        var allItems = [URLQueryItem(name: "datasource", value: "tranquility")]
        if let extra = queryItems { allItems.append(contentsOf: extra) }
        components.queryItems = allItems
        guard let url = components.url else { throw ESIError.invalidURL }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        if let token { request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }

        let (data, response): (Data, URLResponse)
        do { (data, response) = try await session.data(for: request) } catch { throw ESIError.networkError(error) }

        guard let httpResponse = response as? HTTPURLResponse else { throw ESIError.noData }
        switch httpResponse.statusCode {
        case 200...299: break
        case 401: throw ESIError.unauthorized
        case 403: throw ESIError.forbidden
        case 420:
            let retryAfter = Int(httpResponse.value(forHTTPHeaderField: "Retry-After") ?? "60") ?? 60
            throw ESIError.rateLimited(retryAfter: retryAfter)
        default:
            let msg = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw ESIError.serverError(statusCode: httpResponse.statusCode, message: msg)
        }
    }

    /// POST with JSON body, discards response body (for 204 responses)
    func postVoid<Body: Encodable>(_ endpoint: String, body: Body, token: String? = nil, queryItems: [URLQueryItem]? = nil) async throws {
        guard var components = URLComponents(string: "\(baseURL)\(endpoint)") else { throw ESIError.invalidURL }
        var allItems = [URLQueryItem(name: "datasource", value: "tranquility")]
        if let extra = queryItems { allItems.append(contentsOf: extra) }
        components.queryItems = allItems
        guard let url = components.url else { throw ESIError.invalidURL }

        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        let bodyData: Data
        do { bodyData = try encoder.encode(body) } catch { throw ESIError.decodingError(error) }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.httpBody = bodyData
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let token { request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }

        let (data, response): (Data, URLResponse)
        do { (data, response) = try await session.data(for: request) } catch { throw ESIError.networkError(error) }

        guard let httpResponse = response as? HTTPURLResponse else { throw ESIError.noData }
        switch httpResponse.statusCode {
        case 200...299: break
        case 401: throw ESIError.unauthorized
        case 403: throw ESIError.forbidden
        case 420:
            let retryAfter = Int(httpResponse.value(forHTTPHeaderField: "Retry-After") ?? "60") ?? 60
            throw ESIError.rateLimited(retryAfter: retryAfter)
        default:
            let msg = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw ESIError.serverError(statusCode: httpResponse.statusCode, message: msg)
        }
    }

    func fetchPages<T: Decodable>(_ endpoint: String, token: String? = nil) async throws -> [T] {
        guard var components = URLComponents(string: "\(baseURL)\(endpoint)") else {
            throw ESIError.invalidURL
        }
        components.queryItems = [URLQueryItem(name: "datasource", value: "tranquility"), URLQueryItem(name: "page", value: "1")]

        guard let url = components.url else { throw ESIError.invalidURL }

        let cacheKey = url.absoluteString

        // Check cache for page 1
        if let cached = responseCache[cacheKey], cached.expires > Date() {
            // For paginated responses we only cache single-page results
            if let results = try? decoder.decode([T].self, from: cached.data) {
                return results
            }
        }

        var request = URLRequest(url: url)
        if let token = token {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw ESIError.noData
        }

        var results: [T] = try decoder.decode([T].self, from: data)
        let totalPages = Int(httpResponse.value(forHTTPHeaderField: "X-Pages") ?? "1") ?? 1

        // Cache single-page results
        if totalPages == 1,
           let expiresString = httpResponse.value(forHTTPHeaderField: "Expires"),
           let expiresDate = Self.httpDateFormatter.date(from: expiresString),
           expiresDate > Date() {
            responseCache[cacheKey] = CachedResponse(data: data, expires: expiresDate)
        }

        if totalPages > 1 {
            try await withThrowingTaskGroup(of: [T].self) { group in
                for page in 2...totalPages {
                    group.addTask {
                        var pageComponents = URLComponents(string: "\(self.baseURL)\(endpoint)")!
                        pageComponents.queryItems = [
                            URLQueryItem(name: "datasource", value: "tranquility"),
                            URLQueryItem(name: "page", value: "\(page)")
                        ]
                        var req = URLRequest(url: pageComponents.url!)
                        if let token = token {
                            req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
                        }
                        let (pageData, _) = try await self.session.data(for: req)
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

    /// Evict cache entries whose key contains the given path string
    func evictCache(matching path: String) {
        responseCache = responseCache.filter { !$0.key.contains(path) }
    }

    /// Evict all expired entries from the cache
    func pruneCache() {
        let now = Date()
        responseCache = responseCache.filter { $0.value.expires > now }
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
