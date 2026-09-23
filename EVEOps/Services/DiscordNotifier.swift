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

/// Groups alerts by source so Discord embeds can be color- and icon-coded, matching
/// the categories in `NotificationsTab`.
/// `nonisolated` so the static payload builder can read `emoji`/`color` off the main actor.
nonisolated enum DiscordAlertCategory {
    case skillQueue
    case industry
    case contracts
    case structureAlert
    case structureFuel
    case war
    case standings
    case presence
    case serverStatus
    case test
    case general

    var color: Int {
        switch self {
        case .skillQueue: return 0x3498DB
        case .industry: return 0xF39C12
        case .contracts: return 0x9B59B6
        case .structureAlert: return 0xE74C3C
        case .structureFuel: return 0xE67E22
        case .war: return 0xC0392B
        case .standings: return 0x1ABC9C
        case .presence: return 0x2ECC71
        case .serverStatus: return 0x95A5A6
        case .test: return 0x2E86DE
        case .general: return 0x2E86DE
        }
    }

    var emoji: String {
        switch self {
        case .skillQueue: return "📚"
        case .industry: return "🏭"
        case .contracts: return "📜"
        case .structureAlert: return "🛡️"
        case .structureFuel: return "⛽"
        case .war: return "⚔️"
        case .standings: return "🤝"
        case .presence: return "🟢"
        case .serverStatus: return "🖥️"
        case .test: return "🧪"
        case .general: return "🔔"
        }
    }
}

/// Fans out alert events to a user-configured Discord webhook, in addition to the
/// native macOS notification `NotificationService` already posts. Events queued in a
/// short window are batched into a single webhook POST (as multiple embeds) to stay
/// well under Discord's per-webhook rate limit (~5 requests / 2s) when several alerts
/// fire in the same background-poll cycle.
actor DiscordNotifier {
    static let shared = DiscordNotifier()

    static let webhookURLKeychainAccount = "discordWebhookURL"

    private struct PendingAlert {
        let title: String
        let body: String
        let category: DiscordAlertCategory
        let characterName: String?
    }

    private let session: URLSession
    private var pending: [PendingAlert] = []
    private var flushTask: Task<Void, Never>?
    private var retryNotBefore: Date?

    private static let flushDelay: Duration = .seconds(2)

    private init() {
        let config = URLSessionConfiguration.default
        config.httpAdditionalHeaders = ["Content-Type": "application/json"]
        session = URLSession(configuration: config)
    }

    /// Queues an alert for delivery. No-ops silently if Discord notifications are
    /// disabled or no webhook URL is configured — callers don't need to check first.
    func enqueue(
        title: String,
        body: String,
        category: DiscordAlertCategory = .general,
        characterName: String? = nil
    ) async {
        guard UserDefaults.standard.bool(forKey: "discordNotificationsEnabled"),
              (try? await KeychainHelper.loadString(for: Self.webhookURLKeychainAccount)) != nil
        else { return }

        pending.append(PendingAlert(title: title, body: body, category: category, characterName: characterName))
        scheduleFlush()
    }

    /// Posts a one-off test embed immediately (bypassing the batch queue) so Settings
    /// can give the user instant pass/fail feedback on a webhook URL they just typed.
    func sendTest() async -> Bool {
        guard let urlString = try? await KeychainHelper.loadString(for: Self.webhookURLKeychainAccount),
              let url = URL(string: urlString)
        else { return false }

        let payload = Self.embedPayload(for: [PendingAlert(
            title: String(localized: "EVEOps Test Notification"),
            body: String(localized: "If you can see this in Discord, your webhook is configured correctly."),
            category: .test,
            characterName: nil
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

    private static func embedPayload(for items: [PendingAlert]) -> [String: Any] {
        let timestamp = ISO8601DateFormatter().string(from: Date())
        let embeds = items.prefix(10).map { item -> [String: Any] in
            var embed: [String: Any] = [
                "title": "\(item.category.emoji) \(item.title)",
                "description": item.body,
                "color": item.category.color,
                "timestamp": timestamp,
                "footer": ["text": "EVEOps"]
            ]
            if let characterName = item.characterName {
                embed["author"] = ["name": characterName]
            }
            return embed
        }
        return ["embeds": embeds]
    }
}
