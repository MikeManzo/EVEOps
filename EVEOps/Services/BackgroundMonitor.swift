import Foundation

@MainActor
@Observable
final class BackgroundMonitor {
    var isMonitoring = false
    private var monitorTask: Task<Void, Never>?
    private var intervalObserver: AnyObject?
    private var lastKnownInterval: TimeInterval = 0

    private var pollInterval: TimeInterval {
        let stored = UserDefaults.standard.double(forKey: "backgroundPollInterval")
        return stored >= 60 ? stored : 300
    }

    func start(accountManager: AccountManager) {
        guard !isMonitoring else { return }
        isMonitoring = true

        Task {
            await NotificationService.shared.requestPermission()
        }

        launchTask(accountManager: accountManager)

        // Restart the task immediately when the poll interval setting changes
        intervalObserver = NotificationCenter.default.addObserver(
            forName: UserDefaults.didChangeNotification,
            object: UserDefaults.standard,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.launchTask(accountManager: accountManager)
            }
        }
    }

    func stop() {
        monitorTask?.cancel()
        monitorTask = nil
        isMonitoring = false
        if let obs = intervalObserver {
            NotificationCenter.default.removeObserver(obs)
            intervalObserver = nil
        }
    }

    private func launchTask(accountManager: AccountManager) {
        let current = pollInterval
        guard current != lastKnownInterval || monitorTask == nil else { return }
        lastKnownInterval = current

        monitorTask?.cancel()
        monitorTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(self?.pollInterval ?? 300))
                guard !Task.isCancelled else { break }

                await accountManager.refreshPublicInfo()
                let accounts = accountManager.accounts
                await NotificationService.shared.checkForUpdates(accounts: accounts) { account in
                    try await accountManager.validToken(for: account)
                }
            }
        }
    }
}
