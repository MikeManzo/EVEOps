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

/// EVE Online's daily downtime — always 11:00 UTC, lasting roughly 20–30 minutes.
enum EVEDowntime {
    static let hour = 11
    static let minute = 0

    /// The next occurrence of daily downtime at or after `date`.
    static func next(from date: Date = Date()) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        var components = calendar.dateComponents([.year, .month, .day], from: date)
        components.hour = hour
        components.minute = minute
        components.second = 0
        let todayDowntime = calendar.date(from: components) ?? date
        if todayDowntime > date {
            return todayDowntime
        }
        return calendar.date(byAdding: .day, value: 1, to: todayDowntime) ?? todayDowntime
    }
}

/// Monitors ESI API reachability/server status and exposes it for UI banners and widgets.
@MainActor
@Observable
final class APIStatusMonitor {
    private(set) var isReachable = true
    private(set) var statusMessage = ""

    /// Latest values from ESI `/status/` — nil until the first successful check.
    private(set) var playersOnline: Int?
    private(set) var serverVersion: String?
    private(set) var vipMode = false
    private(set) var serverStartTime: Date?
    private(set) var lastUpdated: Date?

    struct PopulationSample: Identifiable, Sendable {
        let date: Date
        let players: Int
        var id: Date { date }
    }

    /// Rolling population history, one sample per check, capped to keep ~an hour of trend data.
    private(set) var populationHistory: [PopulationSample] = []
    private let maxHistorySamples = 60

    private var monitorTask: Task<Void, Never>?
    private let checkInterval: TimeInterval = 60

    func start() {
        guard monitorTask == nil else { return }
        monitorTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.checkStatus()
                try? await Task.sleep(for: .seconds(self?.checkInterval ?? 60))
            }
        }
    }

    func stop() {
        monitorTask?.cancel()
        monitorTask = nil
    }

    func checkNow() async {
        await checkStatus()
    }

    private func checkStatus() async {
        let wasReachable = isReachable
        do {
            let status: ESIStatus = try await ESIClient.shared.fetch("/status/")
            if !wasReachable { Logger.api.info("API: EVE servers reachable") }
            isReachable = true
            statusMessage = ""
            playersOnline = status.players
            serverVersion = status.serverVersion
            vipMode = status.vip ?? false
            serverStartTime = status.startTime
            lastUpdated = Date()

            populationHistory.append(PopulationSample(date: lastUpdated!, players: status.players))
            if populationHistory.count > maxHistorySamples {
                populationHistory.removeFirst(populationHistory.count - maxHistorySamples)
            }

            if !wasReachable {
                await NotificationService.shared.notifyServerRecovered()
            }
        } catch let error as ESIError {
            if isReachable { Logger.api.error("API: EVE servers unreachable — \(error.localizedDescription)") }
            isReachable = false
            switch error {
            case .serverError(let code, _) where code == 503:
                Logger.api.warning("API: EVE servers unreachable — maintenance (503)")
                statusMessage = "EVE servers are undergoing maintenance"
            case .networkError(let underlying as URLError):
                switch underlying.code {
                case .notConnectedToInternet:
                    statusMessage = "No internet connection"
                case .timedOut:
                    statusMessage = "EVE API request timed out"
                default:
                    statusMessage = "Unable to reach EVE servers"
                }
            default:
                statusMessage = "Unable to reach EVE servers"
            }
        } catch {
            if isReachable { Logger.api.error("API: EVE servers unreachable — \(error.localizedDescription)") }
            isReachable = false
            statusMessage = "Unable to reach EVE servers"
        }
    }
}
