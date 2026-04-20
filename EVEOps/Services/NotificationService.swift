import Foundation
import UserNotifications

actor NotificationService {
    static let shared = NotificationService()
    private var lastCheckedNotifications: [Int: Int] = [:]  // characterID: last notificationID
    private var lastCheckedSkillQueues: [Int: Bool] = [:]   // characterID: was queue empty
    private var lastCheckedContracts: [Int: Set<String>] = [:]  // characterID: contract statuses

    func requestPermission() async {
        let center = UNUserNotificationCenter.current()
        _ = try? await center.requestAuthorization(options: [.alert, .sound, .badge])
    }

    func checkForUpdates(accounts: [StoredAccount], getToken: @Sendable (StoredAccount) async throws -> String) async {
        for account in accounts {
            do {
                let token = try await getToken(account)
                await checkSkillQueue(for: account, token: token)
                await checkNotifications(for: account, token: token)
                await checkContracts(for: account, token: token)
                await checkIndustryJobs(for: account, token: token)
            } catch {
                // Skip this character
            }
        }
    }

    private func checkSkillQueue(for account: StoredAccount, token: String) async {
        guard UserDefaults.standard.object(forKey: "notificationsEnabled") as? Bool ?? true,
              UserDefaults.standard.object(forKey: "notifySkillQueueEmpty") as? Bool ?? true else { return }
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
        guard UserDefaults.standard.object(forKey: "notificationsEnabled") as? Bool ?? true else { return }
        let structureAlertsOn = UserDefaults.standard.object(forKey: "notifyStructureAlerts") as? Bool ?? true
        let warAlertsOn = UserDefaults.standard.object(forKey: "notifyWarAlerts") as? Bool ?? true
        guard structureAlertsOn || warAlertsOn else { return }

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
                let isStructure = type.contains("structure") || type.contains("attack") || type.contains("reinforce") || type.contains("tower") || type.contains("moonmining")
                let isWar = type.contains("wardec") || type.contains("allyjoined") || type.contains("war") && (type.contains("declared") || type.contains("started") || type.contains("surrender"))
                let isPIExpiry = type.contains("pi") || type.contains("planet") || type.contains("extractor")

                if (structureAlertsOn && (isStructure || isPIExpiry)) || (warAlertsOn && isWar) {
                    await sendNotification(
                        title: "EVE: \(account.characterName)",
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

    private func checkIndustryJobs(for account: StoredAccount, token: String) async {
        guard UserDefaults.standard.object(forKey: "notificationsEnabled") as? Bool ?? true,
              UserDefaults.standard.object(forKey: "notifyIndustryFinished") as? Bool ?? true else { return }
        do {
            let jobs: [ESIIndustryJob] = try await ESIClient.shared.fetch(
                "/characters/\(account.characterID)/industry/jobs/", token: token
            )
            let justCompleted = jobs.filter { $0.status == "delivered" || ($0.status == "ready" && $0.endDate < Date()) }
            let key = "lastIndustryJobIDs-\(account.characterID)"
            let lastIDs = Set((UserDefaults.standard.array(forKey: key) as? [Int]) ?? [])
            let newlyDone = justCompleted.filter { !lastIDs.contains($0.jobId) }

            if !newlyDone.isEmpty {
                await sendNotification(
                    title: "Industry Complete — \(account.characterName)",
                    body: "\(newlyDone.count) job\(newlyDone.count == 1 ? "" : "s") finished",
                    identifier: "industry-\(account.characterID)-\(Date().timeIntervalSince1970)"
                )
            }

            let currentIDs = justCompleted.map { $0.jobId }
            UserDefaults.standard.set(currentIDs, forKey: key)
        } catch {
            // Skip
        }
    }

    private func checkContracts(for account: StoredAccount, token: String) async {
        guard UserDefaults.standard.object(forKey: "notificationsEnabled") as? Bool ?? true,
              UserDefaults.standard.object(forKey: "notifyContractsUpdated") as? Bool ?? true else { return }
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
