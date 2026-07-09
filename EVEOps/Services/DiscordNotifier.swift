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

/// Fans out alert events to a user-configured Discord webhook, in addition to the
/// native macOS notification `NotificationService` already posts. Events queued in a
/// short window are batched into a single webhook POST (as multiple embeds) to stay
/// well under Discord's per-webhook rate limit (~5 requests / 2s) when several alerts
/// fire in the same background-poll cycle.
actor DiscordNotifier {
    static let shared = DiscordNotifier()

    static let webhookURLKeychainAccount = "discordWebhookURL"

    private let session: URLSession
    private var pending: [(title: String, body: String)] = []
    private var flushTask: Task<Void, Never>?
    private var retryNotBefore: Date?

    private static let flushDelay: Duration = .seconds(2)
    private static let embedColor = 0x2E86DE  // matches EVEOps accent-ish blue

    private init() {
        let config = URLSessionConfiguration.default
        config.httpAdditionalHeaders = ["Content-Type": "application/json"]
        session = URLSession(configuration: config)
    }

    /// Queues an alert for delivery. No-ops silently if Discord notifications are
    /// disabled or no webhook URL is configured — callers don't need to check first.
    func enqueue(title: String, body: String) async {
        guard UserDefaults.standard.bool(forKey: "discordNotificationsEnabled"),
              (try? await KeychainHelper.loadString(for: Self.webhookURLKeychainAccount)) != nil
        else { return }

        pending.append((title, body))
        scheduleFlush()
    }

    /// Posts a one-off test embed immediately (bypassing the batch queue) so Settings
    /// can give the user instant pass/fail feedback on a webhook URL they just typed.
    func sendTest() async -> Bool {
        guard let urlString = try? await KeychainHelper.loadString(for: Self.webhookURLKeychainAccount),
              let url = URL(string: urlString)
        else { return false }

        let payload = Self.embedPayload(for: [(
            title: String(localized: "EVEOps Test Notification"),
            body: String(localized: "If you can see this in Discord, your webhook is configured correctly.")
        )])
        return await post(payload, to: url)
    }

    // MARK: Batching

    private func scheduleFlush() {
        guard flushTask == nil else { return }
        flushTask = Task { [weak self] in
            try? await Task.sleep(for: Self.flushDelay)
            await self?.flush()
        }
    }

    private func flush() async {
        flushTask = nil
        guard !pending.isEmpty else { return }

        if let retryNotBefore, Date() < retryNotBefore {
            // Still rate-limited — reschedule for after the cooldown instead of dropping.
            scheduleFlush()
            return
        }

        guard let urlString = try? await KeychainHelper.loadString(for: Self.webhookURLKeychainAccount),
              let url = URL(string: urlString)
        else {
            pending.removeAll()
            return
        }

        let batch = pending
        pending.removeAll()

        let payload = Self.embedPayload(for: batch)
        _ = await post(payload, to: url)
    }

    // MARK: Networking

    @discardableResult
    private func post(_ payload: [String: Any], to url: URL) async -> Bool {
        guard let body = try? JSONSerialization.data(withJSONObject: payload) else { return false }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.httpBody = body

        do {
            let (_, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else { return false }

            if http.statusCode == 429 {
                let retryAfter = (response as? HTTPURLResponse)?
                    .value(forHTTPHeaderField: "Retry-After")
                    .flatMap(Double.init) ?? 2
                retryNotBefore = Date().addingTimeInterval(retryAfter)
                await Logger.discord.warning("[Discord] Rate limited — backing off \(retryAfter)s")
                return false
            }

            retryNotBefore = nil
            guard (200...299).contains(http.statusCode) else {
                await Logger.discord.error("[Discord] Webhook POST failed with HTTP \(http.statusCode)")
                return false
            }
            return true
        } catch {
            await Logger.discord.error("[Discord] Webhook POST error: \(error.localizedDescription)")
            return false
        }
    }

    // MARK: Payload

    private static func embedPayload(for items: [(title: String, body: String)]) -> [String: Any] {
        let embeds = items.prefix(10).map { item in
            [
                "title": item.title,
                "description": item.body,
                "color": embedColor
            ] as [String: Any]
        }
        return ["embeds": embeds]
    }
}
