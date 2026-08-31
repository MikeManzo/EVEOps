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
import UserNotifications
import OSLog

actor NotificationService {
    static let shared = NotificationService()
    private var lastCheckedNotifications: [Int: Int] = [:]  // characterID: last notificationID
    private var lastCheckedSkillQueues: [Int: Bool] = [:]   // characterID: was queue empty
    private var lastCheckedContracts: [Int: Set<String>] = [:]  // characterID: contract statuses
    private var lastQueueWarningSent: [Int: Date] = [:]     // characterID: last warning date
    private var lastFuelWarningSent: [Int: Date] = [:]      // structureID: last warning date

    func requestPermission() async {
        let center = UNUserNotificationCenter.current()
        do {
            let granted = try await center.requestAuthorization(options: [.alert, .sound, .badge])
            await Logger.updates.info("Notification permission request completed: granted=\(granted)")
        } catch {
            await Logger.updates.error("Notification permission request failed: \(error.localizedDescription)")
        }
    }

    /// Current system notification authorization status, so callers can warn the user
    /// when background alerts (like update notices) will silently fail to appear.
    func authorizationStatus() async -> UNAuthorizationStatus {
        await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
    }

    func checkForUpdates(
        accounts: [StoredAccount],
        getToken: @Sendable (StoredAccount) async throws -> String,
        onUnauthorized: @Sendable (StoredAccount) async -> Void = { _ in }
    ) async {
        var checkedCorporations: Set<Int> = []
        for account in accounts {
            do {
                let token = try await getToken(account)
                try await checkSkillQueue(for: account, token: token)
                try await checkNotifications(for: account, token: token)
                try await checkContracts(for: account, token: token)
                try await checkStandings(for: account, token: token)
                try await checkIndustryJobs(for: account, token: token)
                if checkedCorporations.insert(account.corporationID).inserted {
                    try await checkStructureFuel(for: account, token: token)
                }
            } catch ESIError.unauthorized {
                await onUnauthorized(account)
            } catch {
                // Skip this character
            }
        }
    }

    private func checkSkillQueue(for account: StoredAccount, token: String) async throws {
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
                    title: String(localized: "Training Queue Empty"),
                    body: String(localized: "\(account.characterName)'s training queue has become empty!"),
                    identifier: "skillqueue-\(account.characterID)"
                )
            }

            // Proactive warning: notify when queue will run out within the configured window
            let warningOn = UserDefaults.standard.object(forKey: "notifySkillQueueWarning") as? Bool ?? true
            if warningOn && !isEmpty {
                let warningHours = UserDefaults.standard.double(forKey: "skillQueueWarningHours")
                let warningInterval: TimeInterval = (warningHours > 0 ? warningHours : 24) * 3600
                if let queueEnd = activeSkills.compactMap(\.finishDate).max(),
                   queueEnd.timeIntervalSinceNow > 0,
                   queueEnd.timeIntervalSinceNow < warningInterval {
                    let lastSent = lastQueueWarningSent[account.characterID]
                    let cooldown: TimeInterval = 6 * 3600  // don't re-notify for 6h
                    if lastSent == nil || Date().timeIntervalSince(lastSent!) > cooldown {
                        let hoursLeft = Int(queueEnd.timeIntervalSinceNow / 3600) + 1
                        await sendNotification(
                            title: String(localized: "Skill Queue Alert — \(account.characterName)"),
                            body: String(localized: "Training queue completes in ~\(hoursLeft)h. Add skills to keep training!"),
                            identifier: "skillqueue-warning-\(account.characterID)-\(Int(queueEnd.timeIntervalSince1970))"
                        )
                        lastQueueWarningSent[account.characterID] = Date()
                    }
                }
            }

            lastCheckedSkillQueues[account.characterID] = isEmpty
        } catch ESIError.unauthorized {
            throw ESIError.unauthorized
        } catch {
            // Skip
        }
    }

    private func checkNotifications(for account: StoredAccount, token: String) async throws {
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
                        title: String(localized: "EVE: \(account.characterName)"),
                        body: formatNotificationType(notification.type),
                        identifier: "notification-\(notification.notificationId)"
                    )
                }
            }

            lastCheckedNotifications[account.characterID] = latest.notificationId
        } catch ESIError.unauthorized {
            throw ESIError.unauthorized
        } catch {
            // Skip
        }
    }

    private func checkIndustryJobs(for account: StoredAccount, token: String) async throws {
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
                    title: String(localized: "Industry Complete — \(account.characterName)"),
                    body: String(localized: "\(newlyDone.count) industry jobs finished"),
                    identifier: "industry-\(account.characterID)-\(Date().timeIntervalSince1970)"
                )
            }

            let currentIDs = justCompleted.map { $0.jobId }
            UserDefaults.standard.set(currentIDs, forKey: key)
        } catch ESIError.unauthorized {
            throw ESIError.unauthorized
        } catch {
            // Skip
        }
    }

    private func checkStructureFuel(for account: StoredAccount, token: String) async throws {
        guard UserDefaults.standard.object(forKey: "notificationsEnabled") as? Bool ?? true,
              UserDefaults.standard.object(forKey: "notifyStructureFuel") as? Bool ?? true else { return }
        do {
            let structures: [ESICorporationStructure] = try await ESIClient.shared.fetch(
                "/corporations/\(account.corporationID)/structures/", token: token
            )

            let warningHours = UserDefaults.standard.double(forKey: "structureFuelWarningHours")
            let warningInterval: TimeInterval = (warningHours > 0 ? warningHours : 48) * 3600
            let cooldown: TimeInterval = 12 * 3600  // don't re-notify for the same structure within 12h

            for structure in structures {
                guard let fuelExpires = structure.fuelExpires,
                      fuelExpires.timeIntervalSinceNow < warningInterval else { continue }

                let lastSent = lastFuelWarningSent[structure.structureId]
                if let lastSent, Date().timeIntervalSince(lastSent) < cooldown { continue }

                let systemName = await NameResolver.shared.resolve(id: structure.systemId)
                let body: String
                if fuelExpires.timeIntervalSinceNow > 0 {
                    let hoursLeft = Int(fuelExpires.timeIntervalSinceNow / 3600) + 1
                    body = String(localized: "\(structure.name) at \(systemName) — fuel runs out in ~\(hoursLeft)h")
                } else {
                    body = String(localized: "\(structure.name) at \(systemName) has run out of fuel!")
                }

                await sendNotification(
                    title: String(localized: "Structure Fuel Low — \(account.characterName)"),
                    body: body,
                    identifier: "structurefuel-\(structure.structureId)-\(Int(fuelExpires.timeIntervalSince1970))"
                )
                lastFuelWarningSent[structure.structureId] = Date()
            }
        } catch ESIError.unauthorized {
            throw ESIError.unauthorized
        } catch {
            // Skip — likely missing Station_Manager/Director role, or no structures
        }
    }

    func notifyServerRecovered() async {
        guard UserDefaults.standard.object(forKey: "notificationsEnabled") as? Bool ?? true,
              UserDefaults.standard.object(forKey: "notifyServerStatus") as? Bool ?? true else { return }
        await sendNotification(
            title: String(localized: "EVE Servers Online"),
            body: String(localized: "Tranquility is back up."),
            identifier: "server-status-online-\(Int(Date().timeIntervalSince1970))"
        )
    }

    func notifyPresenceChange(characterID: Int, characterName: String, cameOnline: Bool) async {
        guard UserDefaults.standard.object(forKey: "notificationsEnabled") as? Bool ?? true,
              UserDefaults.standard.object(forKey: "notifyContactPresence") as? Bool ?? true else { return }
        let title = cameOnline
            ? String(localized: "Contact Online")
            : String(localized: "Contact Offline")
        let body = cameOnline
            ? String(localized: "\(characterName) appears to be online.")
            : String(localized: "\(characterName) appears to have gone offline.")
        let suffix = cameOnline ? "online" : "offline"
        await sendNotification(
            title: title,
            body: body,
            identifier: "presence-\(characterID)-\(suffix)-\(Int(Date().timeIntervalSince1970))"
        )
    }

    private func checkContracts(for account: StoredAccount, token: String) async throws {
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
                                title: String(localized: "Contract Update - \(account.characterName)"),
                                body: String(localized: "A contract status changed to: \(status.replacingOccurrences(of: "_", with: " "))"),
                                identifier: "contract-\(change)"
                            )
                        }
                    }
                }
            }

            lastCheckedContracts[account.characterID] = currentStatuses
        } catch ESIError.unauthorized {
            throw ESIError.unauthorized
        } catch {
            // Skip
        }
    }

    /// Polls `/characters/{id}/standings/` (NPC faction / corp / agent standings) on the
    /// background cycle, persists a per-character snapshot in `UserDefaults`, and diffs
    /// consecutive pulls to surface increases and decreases. ESI only exposes the current
    /// value — there is no history endpoint and no causal reason — so this also catches
    /// derived-standing ripple effects without knowing which mission/agent action drove them.
    private func checkStandings(for account: StoredAccount, token: String) async throws {
        guard UserDefaults.standard.object(forKey: "notificationsEnabled") as? Bool ?? true,
              UserDefaults.standard.object(forKey: "notifyStandingsChanged") as? Bool ?? true else { return }
        do {
            let standings: [ESIStanding] = try await ESIClient.shared.fetch(
                "/characters/\(account.characterID)/standings/", token: token
            )

            let key = "lastStandingsSnapshot-\(account.characterID)"
            // Snapshot keyed "fromType/fromId" -> standing value.
            let current: [String: Double] = Dictionary(
                standings.map { ("\($0.fromType)/\($0.fromId)", $0.standing) },
                uniquingKeysWith: { _, last in last }
            )
            let previous = UserDefaults.standard.dictionary(forKey: key) as? [String: Double]

            // First run for this character: store a baseline, notify nothing.
            defer { UserDefaults.standard.set(current, forKey: key) }
            guard let previous else { return }

            // Floating-point noise guard — derived standings carry many decimals.
            let epsilon = 0.01
            struct Change { let standing: ESIStanding; let old: Double; let delta: Double }
            var changes: [Change] = []
            for standing in standings {
                let entryKey = "\(standing.fromType)/\(standing.fromId)"
                guard let old = previous[entryKey] else { continue }  // brand-new entity — skip, not a change
                let delta = standing.standing - old
                if abs(delta) >= epsilon {
                    changes.append(Change(standing: standing, old: old, delta: delta))
                }
            }
            guard !changes.isEmpty else { return }

            // Largest swings first so the summary line is the useful one.
            changes.sort { abs($0.delta) > abs($1.delta) }
            let stamp = Int(Date().timeIntervalSince1970)

            if changes.count <= 3 {
                for change in changes {
                    let name = await NameResolver.shared.resolve(id: change.standing.fromId)
                    let direction = change.delta > 0
                        ? String(localized: "increased")
                        : String(localized: "decreased")
                    await sendNotification(
                        title: String(localized: "Standing Change — \(account.characterName)"),
                        body: String(localized: "Standing with \(name) \(direction) by \(String(format: "%.2f", abs(change.delta))) (\(String(format: "%+.2f", change.old)) → \(String(format: "%+.2f", change.standing.standing)))"),
                        identifier: "standing-\(account.characterID)-\(change.standing.fromType)-\(change.standing.fromId)-\(stamp)"
                    )
                }
            } else {
                let top = changes.first!
                let topName = await NameResolver.shared.resolve(id: top.standing.fromId)
                let topDirection = top.delta > 0
                    ? String(localized: "up")
                    : String(localized: "down")
                await sendNotification(
                    title: String(localized: "Standings Changed — \(account.characterName)"),
                    body: String(localized: "\(changes.count) standings shifted. Largest: \(topName) \(topDirection) \(String(format: "%.2f", abs(top.delta)))."),
                    identifier: "standings-\(account.characterID)-\(stamp)"
                )
            }
        } catch ESIError.unauthorized {
            throw ESIError.unauthorized
        } catch {
            // Skip — likely missing the esi-characters.read_standings.v1 scope.
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
        await DiscordNotifier.shared.enqueue(title: title, body: body)
    }

    private func formatNotificationType(_ type: String) -> String {
        var result = type
        result = result.replacingOccurrences(of: "([a-z])([A-Z])", with: "$1 $2", options: .regularExpression)
        return result
    }
}
