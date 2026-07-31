//
// This file is part of EVEOps.
//
// EVEOps is free software: you can redistribute it and/or modify
// it under the terms of the GNU General Public License as published by
// the Free Software Foundation, version 3 or later.
//
// Copyright (c) 2026 CitizenCoder
//

import AppKit
import OSLog
import Sparkle
import UserNotifications

@Observable
@MainActor
final class AppUpdater: NSObject {
    @ObservationIgnored private var controller: SPUStandardUpdaterController!
    @ObservationIgnored private var kvoToken: NSKeyValueObservation?
    @ObservationIgnored private var hasCheckedOnLaunch = false

    var updater: SPUUpdater { controller.updater }
    var canCheckForUpdates = false

    /// Whether the system has granted permission to show notifications. Background/scheduled
    /// update checks rely entirely on this — Sparkle's "gentle reminder" design shows no window
    /// for them, only a notification — so if this is false the user will never learn about an
    /// update found outside of manually clicking "Check for Updates".
    var notificationsAuthorized = true

    var updateAvailable: Bool {
        didSet { UserDefaults.standard.set(updateAvailable, forKey: "updateAvailable") }
    }

    var availableVersion: String? {
        didSet { UserDefaults.standard.set(availableVersion, forKey: "availableVersion") }
    }

    override init() {
        updateAvailable = UserDefaults.standard.bool(forKey: "updateAvailable")
        availableVersion = UserDefaults.standard.string(forKey: "availableVersion")
        super.init()

        controller = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: self,
            userDriverDelegate: self
        )

        kvoToken = controller.updater.observe(\.canCheckForUpdates, options: [.initial, .new]) { [weak self] updater, _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                let canCheck = updater.canCheckForUpdates
                self.canCheckForUpdates = canCheck
                if canCheck && !self.hasCheckedOnLaunch {
                    self.hasCheckedOnLaunch = true
                    Logger.updates.info("Launch check gate — automaticallyChecksForUpdates=\(updater.automaticallyChecksForUpdates), updateCheckInterval=\(Int(updater.updateCheckInterval))s, lastUpdateCheckDate=\(updater.lastUpdateCheckDate?.description ?? "nil")")
                    if updater.automaticallyChecksForUpdates {
                        updater.checkForUpdatesInBackground()
                    }
                }
            }
        }

        Task { @MainActor [weak self] in
            let status = await NotificationService.shared.authorizationStatus()
            guard let self else { return }
            self.notificationsAuthorized = (status == .authorized || status == .provisional)
            if !self.notificationsAuthorized {
                Logger.updates.warning("Notifications are not authorized (status: \(status.rawValue)) — background update checks won't be able to alert the user")
            }
        }
    }

    func checkForUpdates() {
        updater.checkForUpdates()
    }

    /// Backstop for Sparkle's own scheduled-check timer. EVEOps is a menu-bar-only app that
    /// isn't necessarily kept running for the full 24h check interval, so the timer can go
    /// a long time between opportunities to fire. This piggybacks on the app's existing
    /// periodic background-poll cycle and only checks once we're actually overdue per
    /// Sparkle's own interval/last-check bookkeeping, so it doesn't check any more often
    /// than the user's configured interval allows.
    func checkForUpdatesIfDue() {
        guard canCheckForUpdates, updater.automaticallyChecksForUpdates else {
            Logger.updates.debug("checkForUpdatesIfDue skipped — canCheckForUpdates=\(self.canCheckForUpdates), automaticallyChecksForUpdates=\(self.updater.automaticallyChecksForUpdates)")
            return
        }
        let interval = updater.updateCheckInterval
        let lastCheck = updater.lastUpdateCheckDate ?? .distantPast
        guard Date().timeIntervalSince(lastCheck) >= interval else { return }
        Logger.updates.info("Scheduled update-check interval elapsed during background poll — checking now")
        updater.checkForUpdatesInBackground()
    }
}

// Mark:  SPUUpdaterDelegate

extension AppUpdater: SPUUpdaterDelegate {
    nonisolated func updater(_ updater: SPUUpdater, didFindValidUpdate item: SUAppcastItem) {
        MainActor.assumeIsolated {
            updateAvailable = true
            availableVersion = item.displayVersionString
        }
    }

    nonisolated func updaterDidNotFindUpdate(_ updater: SPUUpdater) {
        MainActor.assumeIsolated {
            updateAvailable = false
            availableVersion = nil
        }
    }

    nonisolated func updater(_ updater: SPUUpdater, userDidMake choice: SPUUserUpdateChoice, forUpdate updateItem: SUAppcastItem, state: SPUUserUpdateState) {
        MainActor.assumeIsolated {
            if choice == .skip {
                updateAvailable = false
                availableVersion = nil
            }
        }
    }

    // Diagnostics for the "background checks never fire" investigation — these mirror
    // Sparkle's own internal scheduling decisions so we have first-party evidence of
    // whether/why its scheduler engages, instead of inferring from absent log lines.
    nonisolated func updater(_ updater: SPUUpdater, willScheduleUpdateCheckAfterDelay delay: TimeInterval) {
        Task { @MainActor in
            Logger.updates.info("Sparkle scheduled its next automatic check in \(Int(delay))s")
        }
    }

    nonisolated func updaterWillNotScheduleUpdateCheck(_ updater: SPUUpdater) {
        Task { @MainActor in
            Logger.updates.warning("Sparkle will NOT schedule any future automatic update check (automaticallyChecksForUpdates is currently false)")
        }
    }

    nonisolated func updater(_ updater: SPUUpdater, didFinishUpdateCycleFor updateCheck: SPUUpdateCheck, error: Error?) {
        Task { @MainActor in
            if let error {
                let nsError = error as NSError
                Logger.updates.error("Update check (type \(updateCheck.rawValue)) finished with error: \(nsError.domain) \(nsError.code) — \(nsError.localizedDescription)")
            } else {
                Logger.updates.info("Update check (type \(updateCheck.rawValue)) finished successfully")
            }
        }
    }
}

// Mark:  SPUStandardUserDriverDelegate

extension AppUpdater: SPUStandardUserDriverDelegate {
    nonisolated var supportsGentleScheduledUpdateReminders: Bool { true }

    nonisolated func standardUserDriverWillHandleShowingUpdate(
        _ handleShowingUpdate: Bool,
        forUpdate update: SUAppcastItem,
        state: SPUUserUpdateState
    ) {
        MainActor.assumeIsolated {
            updateAvailable = true
            availableVersion = update.displayVersionString

            NSApp.setActivationPolicy(.regular)
            NSApp.dockTile.badgeLabel = "1"

            let content = UNMutableNotificationContent()
            content.title = "EVEOps Update Available"
            content.body = "Version \(update.displayVersionString) is ready to install."
            let request = UNNotificationRequest(identifier: "eveops-update", content: content, trigger: nil)
            UNUserNotificationCenter.current().add(request) { error in
                guard let error else { return }
                let message = error.localizedDescription
                Task { @MainActor in
                    Logger.updates.error("Failed to post update-available notification: \(message)")
                }
            }
        }
    }

    nonisolated func standardUserDriverDidReceiveUserAttention(forUpdate update: SUAppcastItem) {
        MainActor.assumeIsolated {
            NSApp.dockTile.badgeLabel = nil
        }
    }

    nonisolated func standardUserDriverWillFinishUpdateSession() {
        _ = MainActor.assumeIsolated {
            NSApp.setActivationPolicy(.accessory)
        }
    }
}
