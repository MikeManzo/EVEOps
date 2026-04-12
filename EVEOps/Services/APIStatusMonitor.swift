import Foundation

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
                    self.isReachable = false
                    self.statusMessage = "Unable to reach EVE servers"
                }
                return
            }
            await MainActor.run {
                if (200...299).contains(http.statusCode) {
                    self.isReachable = true
                    self.statusMessage = ""
                } else if http.statusCode == 503 {
                    self.isReachable = false
                    self.statusMessage = "EVE servers are undergoing maintenance"
                } else {
                    self.isReachable = false
                    self.statusMessage = "EVE API returned an error (\(http.statusCode))"
                }
            }
        } catch let error as URLError {
            await MainActor.run {
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
                self.isReachable = false
                self.statusMessage = "Unable to reach EVE servers"
            }
        }
    }
}
