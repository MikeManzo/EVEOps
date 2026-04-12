import Foundation

@MainActor
@Observable
final class BackgroundMonitor {
    var isMonitoring = false
    private var monitorTask: Task<Void, Never>?
    private let pollInterval: TimeInterval = 300 // 5 minutes

    func start(accountManager: AccountManager) {
        guard !isMonitoring else { return }
        isMonitoring = true

        Task {
            await NotificationService.shared.requestPermission()
        }

        monitorTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(self?.pollInterval ?? 300))
                guard !Task.isCancelled else { break }

                let accounts = accountManager.accounts
                await NotificationService.shared.checkForUpdates(accounts: accounts) { account in
                    try await accountManager.validToken(for: account)
                }
            }
        }
    }

    func stop() {
        monitorTask?.cancel()
        monitorTask = nil
        isMonitoring = false
    }
}
