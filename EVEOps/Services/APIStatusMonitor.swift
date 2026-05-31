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

/// Monitors ESI API reachability and exposes status for UI banners.
@MainActor
@Observable
final class APIStatusMonitor {
    private(set) var isReachable = true
    private(set) var statusMessage = ""

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

    private nonisolated func checkStatus() async {
        let url = URL(string: "https://esi.evetech.net/latest/status/?datasource=tranquility")!
        var request = URLRequest(url: url)
        request.timeoutInterval = 10

        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                await MainActor.run {
                    if self.isReachable { Logger.api.error("API: EVE servers unreachable — invalid HTTP response") }
                    self.isReachable = false
                    self.statusMessage = "Unable to reach EVE servers"
                }
                return
            }
            await MainActor.run {
                if (200...299).contains(http.statusCode) {
                    if !self.isReachable { Logger.api.info("API: EVE servers reachable") }
                    self.isReachable = true
                    self.statusMessage = ""
                } else if http.statusCode == 503 {
                    if self.isReachable { Logger.api.warning("API: EVE servers unreachable — maintenance (503)") }
                    self.isReachable = false
                    self.statusMessage = "EVE servers are undergoing maintenance"
                } else {
                    if self.isReachable { Logger.api.error("API: EVE servers unreachable — HTTP \(http.statusCode)") }
                    self.isReachable = false
                    self.statusMessage = "EVE API returned an error (\(http.statusCode))"
                }
            }
        } catch let error as URLError {
            await MainActor.run {
                if self.isReachable { Logger.api.error("API: EVE servers unreachable — \(error.localizedDescription)") }
                self.isReachable = false
                switch error.code {
                case .notConnectedToInternet:
                    self.statusMessage = "No internet connection"
                case .timedOut:
                    self.statusMessage = "EVE API request timed out"
                default:
                    self.statusMessage = "Unable to reach EVE servers"
                }
            }
        } catch {
            await MainActor.run {
                if self.isReachable { Logger.api.error("API: EVE servers unreachable — \(error.localizedDescription)") }
                self.isReachable = false
                self.statusMessage = "Unable to reach EVE servers"
            }
        }
    }
}
