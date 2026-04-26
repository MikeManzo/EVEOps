import Foundation

// Mark:  Signal Configuration

/// Describes one observable activity signal: its maximum contribution and decay rate.
nonisolated struct SignalConfig: Sendable {
    let id: String
    /// Maximum contribution to the aggregate score (0–1).
    let weight: Double
    /// Seconds after which the contribution halves (t½).
    let halfLife: TimeInterval

    /// λ = ln(2) / t½  — the exponential decay constant.
    var decayConstant: Double { log(2.0) / halfLife }

    /// Decayed score: weight × e^(−λ × age).
    /// At age=0 → weight; at age=t½ → weight/2; at age→∞ → 0.
    func score(age: TimeInterval) -> Double {
        guard age >= 0 else { return weight }
        return weight * exp(-decayConstant * age)
    }
}

// Mark:  Presence State

enum PresenceState: String, Sendable {
    case activeNow      = "Active Now"
    case recentlyActive = "Recently Active"
    case idle           = "Idle"
    case offline        = "Offline"

    static func from(score: Double) -> PresenceState {
        switch score {
        case 0.75...: return .activeNow
        case 0.40...: return .recentlyActive
        case 0.15...: return .idle
        default:      return .offline
        }
    }
}

// Mark:  Activity Event

/// A single observable activity event persisted to disk for decay computation.
nonisolated struct ActivityEvent: Codable, Sendable {
    let characterID: Int
    let signalID: String
    let occurredAt: Date
}

// Mark:  Presence Score

/// The computed presence result for a single character.
nonisolated struct PresenceScore: Sendable {
    let characterID: Int
    /// Normalized aggregate 0.0–1.0 via probabilistic-OR of decayed signal scores.
    let score: Double
    let state: PresenceState
    /// Which signal contributed the most to the current score.
    let dominantSignal: String?
    /// Timestamp of the most recent recorded event.
    let latestEventAt: Date?
    let computedAt: Date

    var tooltipText: String {
        var lines: [String] = [state.rawValue, String(format: "Score: %.0f%%", score * 100)]
        if let sig = dominantSignal {
            lines.append("Signal: \(sig)")
        }
        if let t = latestEventAt {
            let age = Date().timeIntervalSince(t)
            lines.append("Last seen: \(formatAge(age))")
        }
        return lines.joined(separator: "\n")
    }

    private func formatAge(_ seconds: TimeInterval) -> String {
        switch seconds {
        case ..<60:      return "just now"
        case ..<3600:    return "\(Int(seconds / 60))m ago"
        case ..<86400:   return "\(Int(seconds / 3600))h ago"
        default:         return "\(Int(seconds / 86400))d ago"
        }
    }
}

// Mark:  Presence Engine

/// Core actor that owns the event store, decay math, and all network fetches.
///
/// Scoring uses **exponential decay** (S(t) = w × e^(−λt)) and **probabilistic-OR aggregation**:
///   P = 1 − ∏(1 − Sᵢ(t))
/// This caps at 1.0, handles missing signals gracefully, and avoids erratic
/// jumps because each signal can only push the total up, never down.
actor PresenceEngine {
    static let shared = PresenceEngine()

    // MARK: Signal catalogue
    //
    // Weights and half-lives are tuned so that:
    //   onlineNow:    Score ≥ 0.75 for ~5 min after detection  → "Active Now"
    //   kill:         Score ≥ 0.75 for ~31 min after kill       → "Active Now"
    //   location:     Score ≥ 0.75 for ~8 min after move        → "Active Now"
    //   transaction:  Score < 0.75 alone (medium confidence)
    //   Two medium signals together can reach "Active Now".
    let signals: [String: SignalConfig] = [
        "onlineNow":    SignalConfig(id: "onlineNow",    weight: 1.00, halfLife:   300),  // 5 min
        "kill":         SignalConfig(id: "kill",         weight: 0.95, halfLife:  5400),  // 1.5 h
        "location":     SignalConfig(id: "location",     weight: 0.90, halfLife:  1800),  // 30 min
        "transaction":  SignalConfig(id: "transaction",  weight: 0.70, halfLife:  3600),  // 1 h
        "industryJob":  SignalConfig(id: "industryJob",  weight: 0.60, halfLife:  7200),  // 2 h
        "marketOrder":  SignalConfig(id: "marketOrder",  weight: 0.55, halfLife:  5400),  // 1.5 h
        "notification": SignalConfig(id: "notification", weight: 0.35, halfLife: 14400),  // 4 h
        "mail":         SignalConfig(id: "mail",         weight: 0.25, halfLife: 21600),  // 6 h
    ]

    // MARK: Private state
    private var events: [Int: [ActivityEvent]] = [:]
    /// Per-character timestamp of last zKillboard fetch (5-min per-character rate limit).
    private var lastFetchedKills: [Int: Date] = [:]
    /// Last known system per character — location change detection.
    private var lastKnownLocations: [Int: Int] = [:]
    /// Earliest time the next zKillboard request may fire (global 2-s rate limit).
    private var zkillNextAllowed: Date = .distantPast

    private let eventTTL: TimeInterval = 172_800  // 48 hours
    private let killPerCharMinInterval: TimeInterval = 300   // 5 min
    private let zkillGlobalMinInterval: TimeInterval = 2.0   // 2 s

    private let cacheURL: URL

    private init() {
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
        let dir = caches.appendingPathComponent("EVEOps/presence", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent("events.json")
        cacheURL = url
        // Static call avoids actor-isolation restriction during init before self is fully set up.
        events = Self.loadEvents(from: url, ttl: 172_800)
    }

    // Mark:  Event Recording

    func record(_ event: ActivityEvent) {
        var charEvents = events[event.characterID] ?? []

        // Deduplicate: ignore events within 60 s of an existing one on the same signal.
        let isDuplicate = charEvents.contains {
            $0.signalID == event.signalID &&
            abs($0.occurredAt.timeIntervalSince(event.occurredAt)) < 60
        }
        guard !isDuplicate else { return }

        charEvents.append(event)
        charEvents = charEvents.filter { Date().timeIntervalSince($0.occurredAt) < eventTTL }
        events[event.characterID] = charEvents
        persistEvents()
    }

    // Mark:  Scoring

    /// Compute the current presence score by decaying all stored events.
    func score(for characterID: Int) -> PresenceScore {
        let now = Date()
        let charEvents = events[characterID] ?? []

        // Keep only the most recent event per signal.
        var latestPerSignal: [String: Date] = [:]
        for event in charEvents {
            if let existing = latestPerSignal[event.signalID] {
                if event.occurredAt > existing { latestPerSignal[event.signalID] = event.occurredAt }
            } else {
                latestPerSignal[event.signalID] = event.occurredAt
            }
        }

        // Probabilistic-OR aggregation: P = 1 − ∏(1 − sᵢ)
        var missChance = 1.0
        var latestEvent: Date?
        var dominantSignal: String?
        var dominantScore = 0.0

        for (signalID, eventDate) in latestPerSignal {
            guard let config = signals[signalID] else { continue }
            let age = now.timeIntervalSince(eventDate)
            let s = config.score(age: age)
            missChance *= (1.0 - s)
            if s > dominantScore { dominantScore = s; dominantSignal = signalID }
            if latestEvent == nil || eventDate > latestEvent! { latestEvent = eventDate }
        }

        let aggregate = min(1.0, max(0.0, 1.0 - missChance))
        let state: PresenceState
        switch aggregate {
        case 0.75...: state = .activeNow
        case 0.40...: state = .recentlyActive
        case 0.15...: state = .idle
        default:      state = .offline
        }
        return PresenceScore(
            characterID: characterID,
            score: aggregate,
            state: state,
            dominantSignal: dominantSignal,
            latestEventAt: latestEvent,
            computedAt: now
        )
    }

    // Mark:  zKillboard Integration

    /// Fetches the most recent kill activity for a character from zKillboard.
    ///
    /// Rate limiting (two-tier):
    ///   - Per-character: minimum 5 minutes between fetches.
    ///   - Global: minimum 2 seconds between any two zKillboard requests.
    ///
    /// Returns `true` if a network request was actually made (caller should
    /// inject a 2-second sleep before the next call to respect the global limit).
    func fetchKillsFromZKillboard(for characterID: Int) async -> Bool {
        let now = Date()

        // Per-character rate limit
        if let last = lastFetchedKills[characterID], now.timeIntervalSince(last) < killPerCharMinInterval {
            return false
        }

        // Global rate limit — skip rather than block the actor.
        guard now >= zkillNextAllowed else { return false }

        // Claim the rate-limit slot before releasing the actor during network I/O.
        zkillNextAllowed = now.addingTimeInterval(zkillGlobalMinInterval)
        lastFetchedKills[characterID] = now

        guard let url = URL(string: "https://zkillboard.com/api/kills/characterID/\(characterID)/") else {
            return true
        }
        var request = URLRequest(url: url)
        request.setValue("EVEOps macOS App", forHTTPHeaderField: "User-Agent")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 15

        guard let (data, _) = try? await URLSession.shared.data(for: request) else { return true }

        // zKillboard mirrors the ESI killmail format; we only need killmail_time.
        struct ZKBEntry: Decodable {
            let killmailTime: String?
        }

        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        guard let entries = try? decoder.decode([ZKBEntry].self, from: data) else { return true }

        let iso = ISO8601DateFormatter()
        for entry in entries.prefix(5) {
            guard let timeStr = entry.killmailTime,
                  let date = iso.date(from: timeStr),
                  Date().timeIntervalSince(date) < eventTTL else { continue }
            record(ActivityEvent(characterID: characterID, signalID: "kill", occurredAt: date))
        }
        return true
    }

    // Mark:  ESI Signal Ingestion (own characters)

    /// Extracts all available signals from a freshly-prefetched character dataset.
    /// Called by PresenceTracker after each DashboardPrefetcher cycle.
    func ingestPrefetchedData(_ data: DashboardPrefetcher.PrefetchedCharacterData, for characterID: Int) {
        let now = Date()

        // Online status — strongest possible signal for own characters.
        if data.online.online {
            record(ActivityEvent(characterID: characterID, signalID: "onlineNow", occurredAt: now))
        }

        // Location change — even a single system hop shows active gameplay.
        let currentSystem = data.location.solarSystemId
        if let last = lastKnownLocations[characterID], last != currentSystem {
            record(ActivityEvent(characterID: characterID, signalID: "location", occurredAt: now))
        }
        lastKnownLocations[characterID] = currentSystem

        // Wallet transactions within 24 h.
        for tx in data.transactions where now.timeIntervalSince(tx.date) < 86_400 {
            record(ActivityEvent(characterID: characterID, signalID: "transaction", occurredAt: tx.date))
        }

        // Market-related journal entries within 24 h.
        let marketRefs: Set<String> = ["market_escrow", "brokers_fee", "transaction_tax", "market_transaction"]
        for entry in data.journal
            where marketRefs.contains(entry.refType) && now.timeIntervalSince(entry.date) < 86_400 {
            record(ActivityEvent(characterID: characterID, signalID: "marketOrder", occurredAt: entry.date))
        }

        // Active industry jobs started within 24 h.
        for job in data.industryJobs
            where job.status == "active" && now.timeIntervalSince(job.startDate) < 86_400 {
            record(ActivityEvent(characterID: characterID, signalID: "industryJob", occurredAt: job.startDate))
        }

        // Market orders issued within 24 h.
        for order in data.marketOrders where now.timeIntervalSince(order.issued) < 86_400 {
            record(ActivityEvent(characterID: characterID, signalID: "marketOrder", occurredAt: order.issued))
        }
    }

    // Mark:  Cache Management

    func clearEvents(for characterID: Int) {
        events.removeValue(forKey: characterID)
        persistEvents()
    }

    func clearAllEvents() {
        events.removeAll()
        persistEvents()
    }

    // Mark:  Disk Persistence

    private static func loadEvents(from url: URL, ttl: TimeInterval) -> [Int: [ActivityEvent]] {
        guard let data = try? Data(contentsOf: url) else { return [:] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let loaded = try? decoder.decode([Int: [ActivityEvent]].self, from: data) else { return [:] }
        let cutoff = Date().addingTimeInterval(-ttl)
        return loaded.compactMapValues { arr in
            let filtered = arr.filter { $0.occurredAt > cutoff }
            return filtered.isEmpty ? nil : filtered
        }
    }

    private func persistEvents() {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(events) else { return }
        try? data.write(to: cacheURL, options: .atomic)
    }
}
