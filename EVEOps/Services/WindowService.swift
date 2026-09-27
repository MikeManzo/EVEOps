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
final class WindowService: NSObject {
    static let shared = WindowService()
    private override init() {}

    private var accountManager: AccountManager?
    private var prefetcher: DashboardPrefetcher?
    private var apiStatusMonitor: APIStatusMonitor?
    private var presenceTracker: PresenceTracker?
    private var modelContainer: ModelContainer?
    private var appUpdater: AppUpdater?
    private var launchManager: EVELaunchManager?
    private var themeManager: ThemeManager?

    private var mainWindow: NSWindow?
    private var galaxySearchWindow: NSWindow?
    private var tradeHubWindow: NSWindow?
    private var itemSkillTreeWindow: NSWindow?
    private var settingsWindow: NSWindow?
    private var aboutWindow: NSWindow?
    private var shipModelWindows: [String: NSWindow] = [:]
    private var defaultsObserver: NSObjectProtocol?

    func configure(
        accountManager: AccountManager,
        prefetcher: DashboardPrefetcher,
        apiStatusMonitor: APIStatusMonitor,
        presenceTracker: PresenceTracker,
        modelContainer: ModelContainer,
        appUpdater: AppUpdater,
        launchManager: EVELaunchManager,
        themeManager: ThemeManager
    ) {
        self.accountManager = accountManager
        self.prefetcher = prefetcher
        self.apiStatusMonitor = apiStatusMonitor
        self.presenceTracker = presenceTracker
        self.modelContainer = modelContainer
        self.appUpdater = appUpdater
        self.launchManager = launchManager
        self.themeManager = themeManager

        defaultsObserver = NotificationCenter.default.addObserver(
            forName: UserDefaults.didChangeNotification,
            object: UserDefaults.standard,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.updateAppearance() }
        }
    }

    // MARK: Main Window

    func showMain() {
        if let window = mainWindow {
            if window.isMiniaturized { window.deminiaturize(nil) }
            bringToFront(window)
            return
        }

        guard let am = accountManager, let pf = prefetcher,
              let api = apiStatusMonitor, let pt = presenceTracker,
              let mc = modelContainer, let tm = themeManager else { return }

        let content = ThemedRoot {
            MainContentView()
                .environment(am)
                .environment(pf)
                .environment(api)
                .environment(pt)
                .modelContainer(mc)
        }
        .environment(tm)

        let controller = NSHostingController(rootView: content)
        let window = NSWindow(contentViewController: controller)
        window.appearance = resolvedNSAppearance
        window.title = ""//"EVEOps"
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
        bringToFront(window)
    }

    func showMainIfNeeded() {
        guard mainWindow == nil || mainWindow?.isVisible == false else { return }
        showMain()
    }

    // MARK: Galaxy Market Search

    func showGalaxySearch(typeId: Int? = nil, typeName: String = "") {
        // When a specific item is requested while a window already exists,
        // close it so it recreates with the new item preloaded.
        if typeId != nil, let existing = galaxySearchWindow {
            existing.close()
            galaxySearchWindow = nil
        } else if let window = galaxySearchWindow {
            if window.isMiniaturized { window.deminiaturize(nil) }
            bringToFront(window)
            return
        }

        guard let am = accountManager, let pf = prefetcher, let tm = themeManager else { return }

        let window = makeWindow(
            title: "Galaxy Market Search",
            autosaveName: "EVEOpsGalaxySearchWindow",
            contentSize: NSSize(width: 1100, height: 680),
            minSize: NSSize(width: 800, height: 500),
            theme: tm
        ) {
            GalaxyMarketSearchView(initialTypeId: typeId, initialTypeName: typeName)
                .environment(am)
                .environment(pf)
        }

        galaxySearchWindow = window
        bringToFront(window)
    }

    // MARK: Trade Hub Comparison

    func showTradeHubComparison(typeId: Int? = nil, typeName: String = "") {
        if typeId != nil, let existing = tradeHubWindow {
            existing.close()
            tradeHubWindow = nil
        } else if let window = tradeHubWindow {
            if window.isMiniaturized { window.deminiaturize(nil) }
            bringToFront(window)
            return
        }

        guard let am = accountManager, let tm = themeManager else { return }

        let window = makeWindow(
            title: "Trade Hub Comparison",
            autosaveName: "EVEOpsTradeHubWindow",
            contentSize: NSSize(width: 780, height: 520),
            minSize: NSSize(width: 680, height: 440),
            theme: tm
        ) {
            TradeHubComparisonView(initialTypeId: typeId, initialTypeName: typeName)
                .environment(am)
        }

        tradeHubWindow = window
        bringToFront(window)
    }

    // MARK: Item Skill Tree

    func showItemSkillTree(typeId: Int, typeName: String) {
        // Always reopen fresh so the new item preloads, matching Galaxy Search's pattern.
        if let existing = itemSkillTreeWindow {
            existing.close()
            itemSkillTreeWindow = nil
        }

        guard let am = accountManager, let pf = prefetcher, let tm = themeManager else { return }

        let characterSkills: [Int: Int]? = am.selectedAccount.flatMap { account in
            pf.characterData[account.characterID].map {
                Dictionary(uniqueKeysWithValues: $0.skills.skills.map { ($0.skillId, $0.activeSkillLevel) })
            }
        }

        let window = makeWindow(
            title: "Skill Tree — \(typeName)",
            autosaveName: "EVEOpsItemSkillTreeWindow",
            contentSize: NSSize(width: 820, height: 620),
            minSize: NSSize(width: 640, height: 480),
            theme: tm
        ) {
            ItemSkillTreeView(
                characterSkills: characterSkills,
                initialTypeId: typeId,
                initialTypeName: typeName
            )
            .environment(am)
        }

        itemSkillTreeWindow = window
        bringToFront(window)
    }

    // MARK: Ship Model Viewer

    func showShipModel(shipName: String, shipClass: String = "") {
        if let existing = shipModelWindows[shipName] {
            if existing.isMiniaturized { existing.deminiaturize(nil) }
            bringToFront(existing)
            return
        }

        guard let tm = themeManager else { return }

        // One autosave slot for every ship window: a per-ship name would leave a
        // stale frame in defaults for every hull ever opened.
        let window = makeWindow(
            title: shipName,
            subtitle: "3D Ship Model",
            autosaveName: "EVEOpsShipModelWindow",
            contentSize: NSSize(width: 800, height: 600),
            minSize: NSSize(width: 680, height: 520),
            theme: tm
        ) {
            ShipModelSheet(shipName: shipName, shipClass: shipClass)
        }

        shipModelWindows[shipName] = window
        bringToFront(window)
    }

    // MARK: Settings

    func showSettings() {
        if let window = settingsWindow {
            if window.isMiniaturized { window.deminiaturize(nil) }
            bringToFront(window)
            return
        }

        guard let am = accountManager, let pf = prefetcher, let au = appUpdater,
              let lm = launchManager, let tm = themeManager else { return }

        let content = ThemedRoot {
            SettingsView(openToUpdate: au.updateAvailable)
                .environment(am)
                .environment(pf)
                .environment(au)
                .environment(lm)
        }
        .environment(tm)

        let controller = NSHostingController(rootView: content)
        let window = NSWindow(contentViewController: controller)
        window.appearance = resolvedNSAppearance
        window.title = "Settings"
        window.styleMask = [.titled, .closable]
        window.isReleasedWhenClosed = false
        let hasSavedFrame = window.setFrameUsingName("EVEOpsSettingsWindow")
        window.setFrameAutosaveName("EVEOpsSettingsWindow")
        window.delegate = self
        if !hasSavedFrame { window.center() }

        settingsWindow = window
        bringToFront(window)
    }

    // MARK: About

    /// Standalone About window (App menu > About EVEOps) — the same content as the
    /// Settings > About tab, in a compact titlebar-less window so the starfield hero runs
    /// edge to edge, like the About panels of Apple's own apps.
    func showAbout() {
        if let window = aboutWindow {
            bringToFront(window)
            return
        }
        guard let tm = themeManager else { return }

        let content = ThemedRoot {
            AboutTab()
                .frame(width: 440, height: 560)
                .ignoresSafeArea()
        }
        .environment(tm)

        let controller = NSHostingController(rootView: content)
        let window = NSWindow(contentViewController: controller)
        window.appearance = resolvedNSAppearance
        window.title = "About EVEOps"
        window.styleMask = [.titled, .closable, .fullSizeContentView]
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.isMovableByWindowBackground = true
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.center()

        aboutWindow = window
        bringToFront(window)
    }

    // MARK: Helpers

    /// Builds a standard, resizable document-style window. Every secondary window goes
    /// through here so they share one chrome: full-size content view (content runs up
    /// under a unified titlebar, like the main window), the resolved light/dark
    /// appearance, the faction tint, and a remembered frame — `center()` only on first
    /// open, so a window the user moved comes back where they left it.
    private func makeWindow<Content: View>(
        title: String,
        subtitle: String = "",
        autosaveName: String,
        contentSize: NSSize,
        minSize: NSSize,
        theme: ThemeManager,
        @ViewBuilder content: @escaping () -> Content
    ) -> NSWindow {
        let host = EVEHostWindow()
        let root = ThemedRoot { content().environment(\.hostWindow, host) }
            .environment(theme)

        let window = NSWindow(contentViewController: NSHostingController(rootView: root))
        host.window = window
        window.appearance = resolvedNSAppearance
        window.title = title
        window.subtitle = subtitle
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView]
        window.toolbarStyle = .unified
        window.minSize = minSize
        window.setContentSize(contentSize)
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.tabbingMode = .disallowed
        let hasSavedFrame = window.setFrameUsingName(autosaveName)
        window.setFrameAutosaveName(autosaveName)
        if !hasSavedFrame { window.center() }
        return window
    }

    // MenuBarExtra popovers dismiss *after* the button action returns, so
    // activate/makeKeyAndOrderFront called synchronously get overridden when
    // MenuBarExtra popovers dismiss after the button action returns, and macOS
    // then restores focus to the previously active app — sending our window to
    // the bottom. A short asyncAfter clears that focus-restoration cycle, and
    // orderFrontRegardless() bypasses app-activation checks entirely so the
    // window lands on top regardless of which app holds focus.
    private func bringToFront(_ window: NSWindow) {
        applyActivationPolicy()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            NSApp.activate(ignoringOtherApps: true)
            window.makeKeyAndOrderFront(nil)
            window.orderFrontRegardless()
        }
    }

    func updateAppearance() {
        let appearance = resolvedNSAppearance
        mainWindow?.appearance = appearance
        galaxySearchWindow?.appearance = appearance
        tradeHubWindow?.appearance = appearance
        itemSkillTreeWindow?.appearance = appearance
        settingsWindow?.appearance = appearance
        aboutWindow?.appearance = appearance
        shipModelWindows.values.forEach { $0.appearance = appearance }
    }

    func applyActivationPolicy() {
        let showDock = UserDefaults.standard.bool(forKey: "showDockIcon")
        NSApp.setActivationPolicy(showDock ? .regular : .accessory)
    }

    private var resolvedNSAppearance: NSAppearance? {
        switch UserDefaults.standard.string(forKey: "colorScheme") ?? "system" {
        case "light": return NSAppearance(named: .aqua)
        case "dark":  return NSAppearance(named: .darkAqua)
        default:      return nil
        }
    }
}

// MARK: Themed Root

/// Applies the faction accent as a live tint. `showX()` methods below run once per window
/// (they early-return on subsequent calls while the window stays open), so a plain
/// `.tint(themeManager.palette.accent)` computed inline there is a value baked in at that
/// one moment — it would never update after a later theme change. Reading the palette from
/// this view's own `body` instead keeps it wired into SwiftUI's observation graph, so every
/// open window re-tints immediately when `ThemeManager.faction` changes anywhere.
///
/// `.tint(_:)` alone doesn't reach `List` row selection on macOS — the sidebar and any
/// other `List(selection:)` keep the system/app accent for their highlight regardless of
/// `.tint()`. `.listItemTint(_:)` is the modifier Apple specifically ships for recoloring
/// list-row selection (the mechanism behind Reminders/Notes' colored sidebar lists), so it's
/// applied here too, at the same root, to reach every `List` in the app in one place.
private struct ThemedRoot<Content: View>: View {
    @Environment(ThemeManager.self) private var themeManager
    @ViewBuilder let content: () -> Content

    var body: some View {
        content()
            .tint(themeManager.palette.accent)
            .listItemTint(themeManager.palette.accent)
            .eveToastOverlay()
    }
}

// MARK: NSWindowDelegate

extension WindowService: NSWindowDelegate {
    nonisolated func windowWillClose(_ notification: Notification) {
        guard let window = notification.object as? NSWindow else { return }
        MainActor.assumeIsolated {
            if window === settingsWindow { settingsWindow = nil }
            if window === aboutWindow { aboutWindow = nil }
            if window === tradeHubWindow { tradeHubWindow = nil }
            if window === galaxySearchWindow { galaxySearchWindow = nil }
            if window === itemSkillTreeWindow { itemSkillTreeWindow = nil }
            shipModelWindows = shipModelWindows.filter { $0.value !== window }
        }
    }
}

// MARK: Host window

/// The AppKit window a view is hosted in, when it was opened as a standalone window by
/// `WindowService` rather than presented as a sheet. `DismissAction` is a no-op for a
/// root view in an `NSHostingController`, so views that double as sheets and windows
/// read this to close themselves and to hide sheet-only chrome (close buttons, "open in
/// window").
@MainActor
final class EVEHostWindow {
    weak var window: NSWindow?
    func close() { window?.performClose(nil) }
}

extension EnvironmentValues {
    @Entry var hostWindow: EVEHostWindow? = nil
}
