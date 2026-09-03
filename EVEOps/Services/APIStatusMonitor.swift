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

// MARK:  Service-status models

/// Subset of the Atlassian Statuspage `summary.json` served at status.eveonline.com.
struct StatuspageSummary: Decodable, Sendable {
    struct Status: Decodable, Sendable {
        let indicator: String     // none | minor | major | critical
        let description: String
    }
    struct Incident: Decodable, Sendable, Identifiable {
        let id: String
        let name: String
        let status: String        // investigating | identified | monitoring | resolved | postmortem
        let impact: String        // none | minor | major | critical
        let shortlink: String?
        let updatedAt: Date?
        let incidentUpdates: [Update]?

        struct Update: Decodable, Sendable {
            let body: String
            let createdAt: Date?
            private enum CodingKeys: String, CodingKey { case body, createdAt = "created_at" }
        }
        private enum CodingKeys: String, CodingKey {
            case id, name, status, impact, shortlink
            case updatedAt = "updated_at"
            case incidentUpdates = "incident_updates"
        }

        var latestUpdate: String? { incidentUpdates?.first?.body }
    }
    struct Maintenance: Decodable, Sendable, Identifiable {
        let id: String
        let name: String
        let status: String        // scheduled | in_progress | verifying | completed
        let impact: String
        let shortlink: String?
        let scheduledFor: Date?
        let scheduledUntil: Date?
        private enum CodingKeys: String, CodingKey {
            case id, name, status, impact, shortlink
            case scheduledFor = "scheduled_for"
            case scheduledUntil = "scheduled_until"
        }
    }

    let status: Status
    let incidents: [Incident]
    let scheduledMaintenances: [Maintenance]
    private enum CodingKeys: String, CodingKey {
        case status, incidents
        case scheduledMaintenances = "scheduled_maintenances"
    }
}

/// One route's health from `esi.evetech.net/status.json`.
struct ESIRouteStatus: Decodable, Sendable, Identifiable {
    let endpoint: String
    let method: String
    let route: String
    let status: String            // green | yellow | red
    let tags: [String]?
    var id: String { "\(method) \(route)" }
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

    // MARK: Service status (status.eveonline.com + esi.evetech.net/status.json)

    private(set) var statusIndicator = "none"          // none | minor | major | critical
    private(set) var statusDescription = ""
    private(set) var activeIncidents: [StatuspageSummary.Incident] = []
    private(set) var maintenance: [StatuspageSummary.Maintenance] = []

    private(set) var esiRoutesGreen = 0
    private(set) var esiRoutesYellow = 0
    private(set) var esiRoutesRed = 0
    private(set) var degradedRoutes: [ESIRouteStatus] = []

    private(set) var esiErrorBudgetRemain = 100
    private(set) var esiErrorBudgetResetAt: Date = .distantPast
    private(set) var serviceLastUpdated: Date?

    /// A real, actionable problem the user should be told about.
    var hasServiceIssue: Bool {
        statusIndicator == "major" || statusIndicator == "critical"
            || activeIncidents.contains { $0.impact == "major" || $0.impact == "critical" }
            || maintenanceInProgress != nil
    }

    var maintenanceInProgress: StatuspageSummary.Maintenance? {
        maintenance.first { $0.status == "in_progress" || $0.status == "verifying" }
    }

    var nextMaintenance: StatuspageSummary.Maintenance? {
        maintenance
            .filter { $0.status == "scheduled" }
            .min { ($0.scheduledFor ?? .distantFuture) < ($1.scheduledFor ?? .distantFuture) }
    }

    /// One-line summary for the top-of-window banner, or nil when nothing to report.
    var serviceBannerText: String? {
        if let m = maintenanceInProgress {
            return "EVE maintenance in progress: \(m.name)"
        }
        if statusIndicator == "critical" || statusIndicator == "major" {
            if let inc = activeIncidents.first { return "EVE service incident: \(inc.name)" }
            return "EVE service disruption: \(statusDescription)"
        }
        if let inc = activeIncidents.first(where: { $0.impact == "major" || $0.impact == "critical" }) {
            return "EVE service incident: \(inc.name)"
        }
        return nil
    }

    struct PopulationSample: Identifiable, Sendable {
        let date: Date
        let players: Int
        var id: Date { date }
    }

    /// Rolling population history, one sample per check, capped to keep ~an hour of trend data.
    private(set) var populationHistory: [PopulationSample] = []
    private let maxHistorySamples = 60

    private var monitorTask: Task<Void, Never>?
    private var serviceTask: Task<Void, Never>?
    private let checkInterval: TimeInterval = 60
    private let serviceCheckInterval: TimeInterval = 300

    private static let serviceSession: URLSession = {
        let cfg = URLSessionConfiguration.default
        cfg.timeoutIntervalForRequest = 15
        cfg.httpAdditionalHeaders = ["Accept": "application/json", "User-Agent": HTTPClientInfo.userAgent]
        return URLSession(configuration: cfg)
    }()

    private static let serviceDecoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .custom { decoder in
            let raw = try decoder.singleValueContainer().decode(String.self)
            let withFraction = ISO8601DateFormatter()
            withFraction.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let date = withFraction.date(from: raw) { return date }
            let plain = ISO8601DateFormatter()
            if let date = plain.date(from: raw) { return date }
            throw DecodingError.dataCorruptedError(
                in: try decoder.singleValueContainer(),
                debugDescription: "Unrecognised date: \(raw)")
        }
        return d
    }()

    func start() {
        guard monitorTask == nil else { return }
        monitorTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.checkStatus()
                try? await Task.sleep(for: .seconds(self?.checkInterval ?? 60))
            }
        }
        serviceTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.checkServiceStatus()
                try? await Task.sleep(for: .seconds(self?.serviceCheckInterval ?? 300))
            }
        }
    }

    func stop() {
        monitorTask?.cancel()
        monitorTask = nil
        serviceTask?.cancel()
        serviceTask = nil
    }

    func checkNow() async {
        await checkStatus()
        await checkServiceStatus()
    }

    // MARK: Service status

    private func fetchServiceJSON<T: Decodable>(_ urlString: String) async -> T? {
        guard let url = URL(string: urlString) else { return nil }
        do {
            let (data, response) = try await Self.serviceSession.data(from: url)
            guard (response as? HTTPURLResponse)?.statusCode == 200 else { return nil }
            return try Self.serviceDecoder.decode(T.self, from: data)
        } catch {
            return nil
        }
    }

    func checkServiceStatus() async {
        if let summary: StatuspageSummary = await fetchServiceJSON("https://status.eveonline.com/api/v2/summary.json") {
            statusIndicator = summary.status.indicator
            statusDescription = summary.status.description
            activeIncidents = summary.incidents.filter { $0.status != "resolved" && $0.status != "postmortem" }
            maintenance = summary.scheduledMaintenances
                .filter { $0.status == "scheduled" || $0.status == "in_progress" || $0.status == "verifying" }
                .sorted { ($0.scheduledFor ?? .distantFuture) < ($1.scheduledFor ?? .distantFuture) }
        }

        if let routes: [ESIRouteStatus] = await fetchServiceJSON("https://esi.evetech.net/status.json") {
            esiRoutesGreen = routes.filter { $0.status == "green" }.count
            esiRoutesYellow = routes.filter { $0.status == "yellow" }.count
            esiRoutesRed = routes.filter { $0.status == "red" }.count
            degradedRoutes = routes
                .filter { $0.status != "green" }
                .sorted { lhs, rhs in
                    if lhs.status != rhs.status { return lhs.status == "red" }   // red first
                    return lhs.route < rhs.route
                }
        }

        let budget = await ESIClient.shared.errorBudget()
        esiErrorBudgetRemain = budget.remain
        esiErrorBudgetResetAt = budget.resetAt
        serviceLastUpdated = Date()
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
