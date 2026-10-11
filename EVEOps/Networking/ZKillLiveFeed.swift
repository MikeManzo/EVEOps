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

/// One killmail from zKillboard's R2Z2 feed: the raw ESI killmail plus zKillboard's metadata.
nonisolated struct ZKBLiveKill: Decodable, Sendable {
    let killmailId: Int
    let hash: String
    let esi: ESIKillmail
    let zkb: ZKBMeta
    let sequenceId: Int
}

/// Follows zKillboard's R2Z2 live feed (`r2z2.zkillboard.com/ephemeral/`): read the
/// current sequence number once, then fetch `{sequence}.json` one after another. A 404
/// means the feed hasn't reached that number yet, so wait at least six seconds as the docs
/// ask. Every kill in New Eden comes through here; callers filter by system.
actor ZKillLiveFeed {
    static let shared = ZKillLiveFeed()

    private static let base = "https://r2z2.zkillboard.com/ephemeral/"
    /// R2Z2 allows 15 requests a second per IP; stay well under while catching up.
    private static let catchUpSpacing: TimeInterval = 0.1
    private static let headWait: TimeInterval = 6
    private static let errorWait: TimeInterval = 15
    /// Further behind the head than this (after sleep, say), skip ahead rather than replay.
    private static let maxBacklog = 2000

    private let session: URLSession
    private let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.keyDecodingStrategy = .convertFromSnakeCase
        d.dateDecodingStrategy = .iso8601
        return d
    }()

    private init() {
        let config = URLSessionConfiguration.default
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        config.httpAdditionalHeaders = [
            "Accept": "application/json",
            "Accept-Encoding": "gzip",
            "User-Agent": HTTPClientInfo.userAgent
        ]
        session = URLSession(configuration: config)
    }

    /// Kills as they're posted, until the consumer stops iterating. Each call starts its
    /// own reader, so keep to one consumer.
    func kills() -> AsyncStream<ZKBLiveKill> {
        AsyncStream { continuation in
            let task = Task { await self.run(continuation) }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    private func run(_ continuation: AsyncStream<ZKBLiveKill>.Continuation) async {
        var sequence: Int?
        var lastHeadCheck = Date.distantPast

        while !Task.isCancelled {
            // (Re)read the head pointer at start, and every few minutes to notice a backlog.
            if sequence == nil || Date().timeIntervalSince(lastHeadCheck) > 300 {
                if let head = await headSequence() {
                    lastHeadCheck = Date()
                    if sequence == nil || head - sequence! > Self.maxBacklog { sequence = head }
                } else if sequence == nil {
                    await pause(Self.errorWait); continue
                }
            }
            guard let current = sequence else { continue }

            switch await fetch(current) {
            case .kill(let kill):
                continuation.yield(kill)
                sequence = current + 1
                await pause(Self.catchUpSpacing)
            case .skip:
                sequence = current + 1
            case .notYet:
                await pause(Self.headWait)
            case .failed:
                await pause(Self.errorWait)
            }
        }
        continuation.finish()
    }

    private enum FetchResult { case kill(ZKBLiveKill), skip, notYet, failed }

    private func fetch(_ sequence: Int) async -> FetchResult {
        guard let url = URL(string: "\(Self.base)\(sequence).json"),
              let (data, response) = try? await session.data(from: url),
              let http = response as? HTTPURLResponse else { return .failed }
        switch http.statusCode {
        case 200:
            // An entry that doesn't decode is skipped rather than stalling the feed.
            guard let kill = try? decoder.decode(ZKBLiveKill.self, from: data) else {
                await Logger.network.debug("R2Z2 \(sequence) did not decode; skipping")
                return .skip
            }
            return .kill(kill)
        case 404: return .notYet
        default:  return .failed
        }
    }

    private func headSequence() async -> Int? {
        struct Head: Decodable { let sequence: Int }
        guard let url = URL(string: "\(Self.base)sequence.json"),
              let (data, response) = try? await session.data(from: url),
              (response as? HTTPURLResponse)?.statusCode == 200 else { return nil }
        return try? decoder.decode(Head.self, from: data).sequence
    }

    private func pause(_ seconds: TimeInterval) async {
        try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
    }
}
