import Foundation
import UserNotifications

actor NotificationService {
    static let shared = NotificationService()
    private var lastCheckedNotifications: [Int: Int] = [:]  // characterID: last notificationID
    private var lastCheckedSkillQueues: [Int: Bool] = [:]   // characterID: was queue empty
    private var lastCheckedContracts: [Int: Set<String>] = [:]  // characterID: contract statuses

    func requestPermission() async {
        let center = UNUserNotificationCenter.current()
        try? await center.requestAuthorization(options: [.alert, .sound, .badge])
    }

    func checkForUpdates(accounts: [StoredAccount], getToken: @Sendable (StoredAccount) async throws -> String) async {
        for account in accounts {
            do {
                let token = try await getToken(account)
                await checkSkillQueue(for: account, token: token)
                await checkNotifications(for: account, token: token)
                await checkContracts(for: account, token: token)
            } catch {
                // Skip this character
            }
        }
    }

    private func checkSkillQueue(for account: StoredAccount, token: String) async {
        do {
            let queue: [ESISkillQueue] = try await ESIClient.shared.fetch(
                "/characters/\(account.characterID)/skillqueue/", token: token
            )
            let activeSkills = queue.filter { ($0.finishDate ?? .distantPast) > Date() }
            let isEmpty = activeSkills.isEmpty
            let wasEmpty = lastCheckedSkillQueues[account.characterID]

            if isEmpty && wasEmpty == false {
                await sendNotification(
                    title: "Training Queue Empty",
                    body: "\(account.characterName)'s training queue has become empty!",
                    identifier: "skillqueue-\(account.characterID)"
                )
            }
            lastCheckedSkillQueues[account.characterID] = isEmpty
        } catch {
            // Skip
        }
    }

    private func checkNotifications(for account: StoredAccount, token: String) async {
        do {
            let notifications: [ESINotification] = try await ESIClient.shared.fetch(
                "/characters/\(account.characterID)/notifications/", token: token
            )
            let sorted = notifications.sorted { $0.notificationId > $1.notificationId }
            guard let latest = sorted.first else { return }

            let lastSeen = lastCheckedNotifications[account.characterID] ?? latest.notificationId
            let newNotifications = sorted.filter { $0.notificationId > lastSeen }

            for notification in newNotifications {
                let type = notification.type.lowercased()
                if type.contains("structure") || type.contains("attack") || type.contains("reinforce") {
                    await sendNotification(
                        title: "EVE Communication - \(account.characterName)",
                        body: formatNotificationType(notification.type),
                        identifier: "notification-\(notification.notificationId)"
                    )
                }
            }

            lastCheckedNotifications[account.characterID] = latest.notificationId
        } catch {
            // Skip
        }
    }

    private func checkContracts(for account: StoredAccount, token: String) async {
        do {
            let contracts: [ESIContract] = try await ESIClient.shared.fetch(
                "/characters/\(account.characterID)/contracts/", token: token
            )
            let currentStatuses = Set(contracts.map { "\($0.contractId):\($0.status)" })
            let previousStatuses = lastCheckedContracts[account.characterID]

            if let previous = previousStatuses {
                let changed = currentStatuses.subtracting(previous)
                for change in changed {
                    let parts = change.split(separator: ":")
                    if parts.count == 2 {
                        let status = String(parts[1])
                        if ["finished", "finished_issuer", "finished_contractor", "rejected", "failed"].contains(status) {
                            await sendNotification(
                                title: "Contract Update - \(account.characterName)",
                                body: "A contract status changed to: \(status.replacingOccurrences(of: "_", with: " "))",
                                identifier: "contract-\(change)"
                            )
                        }
                    }
                }
            }

            lastCheckedContracts[account.characterID] = currentStatuses
        } catch {
            // Skip
        }
    }

    private func sendNotification(title: String, body: String, identifier: String) async {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: identifier,
            content: content,
            trigger: nil
        )

        try? await UNUserNotificationCenter.current().add(request)
    }

    private func formatNotificationType(_ type: String) -> String {
        var result = type
        result = result.replacingOccurrences(of: "([a-z])([A-Z])", with: "$1 $2", options: .regularExpression)
        return result
    }
}
