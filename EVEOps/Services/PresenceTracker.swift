import Foundation

/// @MainActor observable service that drives the presence polling lifecycle
/// and exposes scored results to the SwiftUI view layer.
///
/// Polling architecture (two-tier):
///   Network tier  — every 5 min: ingest ESI data for own chars + fetch zKillboard for contacts.
///   Score tier    — every 30 s:  recompute decayed scores from the in-memory event store
///                                (no network, just math — keeps UI fresh as events age out).
///
/// Inject via `.environment(presenceTracker)` and access with
/// `@Environment(PresenceTracker.self)`.
@MainActor
@Observable
final class PresenceTracker {

    // MARK: Published state

    /// Presence score keyed by EVE character ID. Updated every 30 s.
    private(set) var scores: [Int: PresenceScore] = [:]
    /// True while a network-fetch cycle is in progress.
    private(set) var isFetching = false

    // MARK: Configuration (set before startPolling)

    private var accountManager: AccountManager?
    private var prefetcher: DashboardPrefetcher?

    // MARK: Private

    /// Character contacts (type == "character") the tracker maintains zKillboard data for.
    private var contactIDs: Set<Int> = []
    private var pollTask: Task<Void, Never>?

    private let networkInterval: TimeInterval = 300   // 5 min between zKillboard cycles
    private let scoreInterval:   TimeInterval = 30    // 30 s between score recomputations

    // MARK: - Setup

    /// Must be called once before startPolling so the tracker knows which accounts and
    /// prefetched data to use.
    func configure(accountManager: AccountManager, prefetcher: DashboardPrefetcher) {
        self.accountManager = accountManager
        self.prefetcher = prefetcher
    }

    // MARK: - Lifecycle

    func startPolling() {
        guard pollTask == nil else { return }
        pollTask = Task { await pollingLoop() }
    }

    func stopPolling() {
        pollTask?.cancel()
        pollTask = nil
    }

    // MARK: - Contact Management

    /// Replace the full set of character contact IDs to track.
    /// Call this whenever the contacts list is (re)loaded.
    func updateContactIDs(_ ids: [Int]) {
        contactIDs = Set(ids)
    }

    // MARK: - Manual Refresh

    /// Trigger an immediate network fetch + score recompute (e.g. from a Refresh button).
    func triggerRefresh() async {
        await performNetworkCycle()
        await recomputeScores()
    }

    // MARK: - Score Access

    func score(for characterID: Int) -> PresenceScore {
        if let cached = scores[characterID] { return cached }
        return PresenceScore(
            characterID: characterID,
            score: 0,
            state: .offline,
            dominantSignal: nil,
            latestEventAt: nil,
            computedAt: .now
        )
    }

    // MARK: - Polling Loop

    private func pollingLoop() async {
        // Immediate first cycle so contacts have data as soon as the view appears.
        await performNetworkCycle()

        // After the initial fetch, alternate between fast score refreshes and full network cycles.
        // Layout:  [score × 10 (5 min)] → [network] → [score × 10] → …
        while !Task.isCancelled {
            let refreshsPerNetworkCycle = Int(networkInterval / scoreInterval)  // 10
            for _ in 0..<refreshsPerNetworkCycle {
                try? await Task.sleep(for: .seconds(scoreInterval))
                guard !Task.isCancelled else { return }
                await recomputeScores()
            }
            await performNetworkCycle()
        }
    }

    // MARK: - Network Cycle

    /// Ingests ESI data for own characters then fetches zKillboard for all tracked contacts.
    /// The 2-second inter-request delay required by zKillboard is enforced here, outside
    /// the PresenceEngine actor, to avoid actor reentrancy issues during Task.sleep.
    private func performNetworkCycle() async {
        guard let accountManager, let prefetcher else { return }
        isFetching = true
        defer { isFetching = false }

        let engine = PresenceEngine.shared

        // Step 1 — Ingest ESI signals for own characters from prefetcher snapshot.
        for account in accountManager.accounts {
            if let data = prefetcher.data(for: account.characterID) {
                await engine.ingestPrefetchedData(data, for: account.characterID)
            }
        }

        // Step 2 — Fetch zKillboard for own characters (so kills appear even without ESI auth).
        for account in accountManager.accounts {
            guard !Task.isCancelled else { break }
            let fetched = await engine.fetchKillsFromZKillboard(for: account.characterID)
            if fetched { try? await Task.sleep(nanoseconds: 2_000_000_000) }
        }

        // Step 3 — Fetch zKillboard for contacts (serialized; PresenceEngine enforces per-character
        // rate limit, so only characters past their 5-min window actually make network requests).
        for id in contactIDs {
            guard !Task.isCancelled else { break }
            let fetched = await engine.fetchKillsFromZKillboard(for: id)
            if fetched { try? await Task.sleep(nanoseconds: 2_000_000_000) }
        }

        await recomputeScores()
    }

    // MARK: - Score Recomputation

    /// Recomputes all scores from the current event store. Pure math, no network.
    private func recomputeScores() async {
        let engine = PresenceEngine.shared
        var updated: [Int: PresenceScore] = [:]

        for id in contactIDs {
            updated[id] = await engine.score(for: id)
        }
        if let accountManager {
            for account in accountManager.accounts {
                updated[account.characterID] = await engine.score(for: account.characterID)
            }
        }
        scores = updated
    }
}
