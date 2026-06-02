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
import SwiftUI
import SwiftData

/// Manages all app windows programmatically so the @main struct can declare
/// only a MenuBarExtra — no Window, WindowGroup, or Settings scene that
/// macOS Tahoe reserves dock resources for or auto-opens at startup.
@MainActor
final class WindowService {
    static let shared = WindowService()
    private init() {}

    private var accountManager: AccountManager?
    private var prefetcher: DashboardPrefetcher?
    private var apiStatusMonitor: APIStatusMonitor?
    private var presenceTracker: PresenceTracker?
    private var modelContainer: ModelContainer?
    private var appUpdater: AppUpdater?

    private var mainWindow: NSWindow?
    private var galaxySearchWindow: NSWindow?
    private var settingsWindow: NSWindow?

    func configure(
        accountManager: AccountManager,
        prefetcher: DashboardPrefetcher,
        apiStatusMonitor: APIStatusMonitor,
        presenceTracker: PresenceTracker,
        modelContainer: ModelContainer,
        appUpdater: AppUpdater
    ) {
        self.accountManager = accountManager
        self.prefetcher = prefetcher
        self.apiStatusMonitor = apiStatusMonitor
        self.presenceTracker = presenceTracker
        self.modelContainer = modelContainer
        self.appUpdater = appUpdater
    }

    // MARK: Main Window

    func showMain() {
        if let window = mainWindow {
            if window.isMiniaturized { window.deminiaturize(nil) }
            window.makeKeyAndOrderFront(nil)
            NSApp.setActivationPolicy(.accessory)
            return
        }

        guard let am = accountManager, let pf = prefetcher,
              let api = apiStatusMonitor, let pt = presenceTracker,
              let mc = modelContainer else { return }

        let content = MainContentView()
            .environment(am)
            .environment(pf)
            .environment(api)
            .environment(pt)
            .modelContainer(mc)
            .preferredColorScheme(resolvedColorScheme)

        let controller = NSHostingController(rootView: content)
        let window = NSWindow(contentViewController: controller)
        window.title = "EVEOps"
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView]
        window.minSize = NSSize(width: 900, height: 600)
        window.setContentSize(NSSize(width: 1100, height: 700))
        window.isReleasedWhenClosed = false
        let hasSavedFrame = window.setFrameUsingName("EVEOpsMainWindow")
        window.setFrameAutosaveName("EVEOpsMainWindow")
        if !hasSavedFrame {
            window.center()
        }

        mainWindow = window
        window.makeKeyAndOrderFront(nil)
        NSApp.setActivationPolicy(.accessory)
    }

    // MARK: Galaxy Market Search

    func showGalaxySearch(typeId: Int? = nil, typeName: String = "") {
        if let window = galaxySearchWindow {
            if window.isMiniaturized { window.deminiaturize(nil) }
            window.makeKeyAndOrderFront(nil)
            NSApp.setActivationPolicy(.accessory)
            return
        }

        guard let am = accountManager, let pf = prefetcher else { return }

        let content = GalaxyMarketSearchView(initialTypeId: typeId, initialTypeName: typeName)
            .environment(am)
            .environment(pf)
            .preferredColorScheme(resolvedColorScheme)

        let controller = NSHostingController(rootView: content)
        let window = NSWindow(contentViewController: controller)
        window.title = "Galaxy Market Search"
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
        window.minSize = NSSize(width: 800, height: 500)
        window.setContentSize(NSSize(width: 1100, height: 680))
        window.isReleasedWhenClosed = false
        window.setFrameAutosaveName("EVEOpsGalaxySearchWindow")
        window.center()

        galaxySearchWindow = window
        window.makeKeyAndOrderFront(nil)
        NSApp.setActivationPolicy(.accessory)
    }

    // MARK: Settings

    func showSettings() {
        if let window = settingsWindow {
            if window.isMiniaturized { window.deminiaturize(nil) }
            window.makeKeyAndOrderFront(nil)
            NSApp.setActivationPolicy(.accessory)
            return
        }

        guard let am = accountManager, let pf = prefetcher, let au = appUpdater else { return }

        let content = SettingsView()
            .environment(am)
            .environment(pf)
            .environment(au)
            .preferredColorScheme(resolvedColorScheme)

        let controller = NSHostingController(rootView: content)
        let window = NSWindow(contentViewController: controller)
        window.title = "Settings"
        window.styleMask = [.titled, .closable]
        window.isReleasedWhenClosed = false
        window.setFrameAutosaveName("EVEOpsSettingsWindow")
        window.center()

        settingsWindow = window
        window.makeKeyAndOrderFront(nil)
        NSApp.setActivationPolicy(.accessory)
    }

    // MARK: Helpers

    private var resolvedColorScheme: ColorScheme? {
        switch UserDefaults.standard.string(forKey: "colorScheme") ?? "system" {
        case "light": return .light
        case "dark":  return .dark
        default:      return nil
        }
    }
}
