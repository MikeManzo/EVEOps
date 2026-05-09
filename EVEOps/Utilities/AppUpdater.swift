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
import Sparkle
import UserNotifications

@Observable
@MainActor
final class AppUpdater: NSObject {
    @ObservationIgnored private var controller: SPUStandardUpdaterController!
    @ObservationIgnored private var kvoToken: NSKeyValueObservation?

    var updater: SPUUpdater { controller.updater }
    var canCheckForUpdates = false

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
                self?.canCheckForUpdates = updater.canCheckForUpdates
            }
        }
    }

    func checkForUpdates() {
        updater.checkForUpdates()
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
            UNUserNotificationCenter.current().add(request)
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
