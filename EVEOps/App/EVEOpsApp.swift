//
// This file is part of EVEOps.
//
// EVEOps is free software: you can redistribute it and/or modify
// it under the terms of the GNU General Public License as published by
// the Free Software Foundation, version 3 or later.
//
// Copyright (c) 2026 CitizenCoder
//

import SwiftUI
import SwiftData
import OSLog
import UserNotifications
import CoreServices

// Shared routing state — lets AppDelegate hand a file URL to any view in the hierarchy.
@Observable
final class AppRouter {
    static let shared = AppRouter()
    private init() {}
    var pendingEFTURL: URL?

    /// Set by any view that wants MainContentView to switch the selected sidebar section.
    /// MainContentView consumes it and resets it to nil.
    var pendingSection: NavigationSection?

    /// Set alongside `pendingSection` when a request is about a specific pilot (e.g. a
    /// notification click): MainContentView selects that character first.
    var pendingCharacterID: Int?

    /// A route request handed to the Route Planner from another view (e.g. the
    /// Exploration Codex quiet-systems list). RoutePlannerView resolves the system
    /// IDs, fills its origin/destination fields, and clears this back to nil.
    struct PendingRoute: Equatable {
        var originId: Int?
        var destinationId: Int?
        /// Plot immediately once both endpoints resolve.
        var autoPlot: Bool = true
    }
    var pendingRoute: PendingRoute?

    /// Bumped by the "Refresh Current View" command (⌘K) and the ⌘R shortcut.
    /// Views that show live data observe this and re-fetch.
    var refreshTick = 0

    /// Bumped by the ⌘K menu command; MainContentView opens the quick switcher.
    var commandPaletteTick = 0

    /// Bumped by the "Add Character…" menu command (⌘N).
    var addCharacterTick = 0
    var shortcutsTick = 0

    /// −1 / +1 from the Previous/Next Section commands (⌘[ / ⌘]); consumed and
    /// reset to 0 by MainContentView, which owns the ordered section list.
    var sectionStep = 0

    func requestRefresh() { refreshTick &+= 1 }
    func openCommandPalette() { commandPaletteTick &+= 1 }
    func requestAddCharacter() { addCharacterTick &+= 1 }
    func showKeyboardShortcuts() { shortcutsTick &+= 1 }
    func stepSection(_ delta: Int) { sectionStep = delta }
}

// Sets itself as the UNUserNotificationCenter delegate so banners are shown
// even while the app is active. Without this, macOS silently routes all
// notifications straight to Notification Center with no banner.
class AppDelegate: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate {
    func applicationWillFinishLaunching(_ notification: Notification) {
        // Lock the activation policy before SwiftUI scenes (Settings) can promote the app
        // to .regular. Calling this in didFinishLaunching is too late — scenes init first.
        let showDock = UserDefaults.standard.bool(forKey: "showDockIcon")
        NSApp.setActivationPolicy(showDock ? .regular : .accessory)
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        let showDock = UserDefaults.standard.bool(forKey: "showDockIcon")
        NSApp.setActivationPolicy(showDock ? .regular : .accessory)
        
        // Set the delegate to handle foreground notifications
        UNUserNotificationCenter.current().delegate = self

        // Register the actionable "Install Update" notification button.
        AppUpdater.registerNotificationCategories()

        // Request permission immediately on launch
        Task {
            do {
                await NotificationService.shared.requestPermission()
            }
        }

        // Re-register UTIs (including the .eft document type icon) with Launch Services
        // on every launch so Finder always shows the correct icon without manual lsregister.
        LSRegisterURL(Bundle.main.bundleURL as CFURL, true)
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        guard UserDefaults.standard.bool(forKey: "showDockIcon") else { return }
        WindowService.shared.showMainIfNeeded()
    }

    func applicationWillTerminate(_ notification: Notification) {
        DiagnosticLogStore.shared.flushSync()
        // Best-effort: give the actor a moment to mirror the cache to disk. The
        // count-based persist during the session is the real guarantee here.
        Task { await ESIClient.shared.persistCache() }
        Task { await DiscordRichPresence.shared.disconnect() }
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        if let url = urls.first(where: { $0.pathExtension.lowercased() == "eft" }) {
            AppRouter.shared.pendingEFTURL = url
        }
    }

    // nonisolated: notification center calls this from its own private queue.
    // Without this, the @MainActor dispatch introduced by NSApplicationDelegate
    // conformance causes an async hop that races against the system's completion-
    // handler deadline, silently suppressing the banner on LSUIElement apps.
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound, .list])
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        // Tapping the "update available" banner (or its "Install Update" action)
        // opens the Sparkle update flow.
        if response.notification.request.content.userInfo[NotificationRoute.sectionKey] != nil {
            Task { @MainActor in _ = NotificationRoute.handle(response) }
        } else if response.notification.request.identifier == AppUpdater.updateNotificationID,
           response.actionIdentifier == AppUpdater.installActionID
            || response.actionIdentifier == UNNotificationDefaultActionIdentifier {
            Task { @MainActor in
                AppUpdater.shared?.checkForUpdates()
            }
        }
        completionHandler()
    }
}

@main
struct EVEOpsApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    var sharedModelContainer: ModelContainer = EVEOpsApp.makeModelContainer()

    /// Build the SwiftData store. If the on-disk store can't be opened, `StoreBootstrap`
    /// moves it aside and starts fresh rather than crashing; `AccountManager` then brings
    /// the pilots back from `PilotArchive` (Keychain). Account tokens are in the store,
    /// not the Keychain, which is why that archive exists.
    private static func makeModelContainer() -> ModelContainer {
        let schema = Schema([
            StoredAccount.self,
            CachedName.self,
            LauncherAccount.self
        ])
        let result = StoreBootstrap.makeContainer(schema: schema)
        StoreBootstrap.lastOutcome = result.outcome
        return result.container
    }

    @State private var accountManager: AccountManager
    @State private var backgroundMonitor: BackgroundMonitor
    @State private var prefetcher: DashboardPrefetcher
    @State private var apiStatusMonitor: APIStatusMonitor
    @State private var presenceTracker: PresenceTracker
    @State private var appUpdater: AppUpdater
    @State private var launcherAccountManager: LauncherAccountManager
    @State private var launchManager: EVELaunchManager
    @State private var themeManager: ThemeManager
    @AppStorage("colorScheme") private var colorSchemePref: String = "system"

    private var resolvedColorScheme: ColorScheme? {
        switch colorSchemePref {
        case "light": return .light
        case "dark": return .dark
        default: return nil
        }
    }

    init() {
        let manager = AccountManager(modelContext: sharedModelContainer.mainContext)
        let bg = BackgroundMonitor()
        let pf = DashboardPrefetcher()
        let api = APIStatusMonitor()
        let tracker = PresenceTracker()
        let updater = AppUpdater()
        let launcherAccounts = LauncherAccountManager(modelContext: sharedModelContainer.mainContext)
        let launch = EVELaunchManager(accountManager: launcherAccounts)
        let theme = ThemeManager()

        _accountManager = State(initialValue: manager)
        _backgroundMonitor = State(initialValue: bg)
        _prefetcher = State(initialValue: pf)
        _apiStatusMonitor = State(initialValue: api)
        _presenceTracker = State(initialValue: tracker)
        _appUpdater = State(initialValue: updater)
        _launcherAccountManager = State(initialValue: launcherAccounts)
        _launchManager = State(initialValue: launch)
        _themeManager = State(initialValue: theme)

        WindowService.shared.configure(
            accountManager: manager,
            prefetcher: pf,
            apiStatusMonitor: api,
            presenceTracker: tracker,
            modelContainer: sharedModelContainer,
            appUpdater: updater,
            launchManager: launch,
            themeManager: theme
        )

        Task { @MainActor in
            bg.start(accountManager: manager, prefetcher: pf, appUpdater: updater)
            api.start()
            await DiagnosticLogStore.shared.load()
            Logger.app.info("EVEOps started — diagnostic log active")

            // Configure presence tracker before starting the poll loop so it
            // has access to accounts and prefetched data from the first cycle.
            tracker.configure(accountManager: manager, prefetcher: pf)
            tracker.startPolling()

            // Restore the persisted ESI response cache before any prefetch so a
            // relaunch serves fresh entries straight from disk and revalidates the
            // rest with cheap 304s instead of full re-downloads.
            await ESIClient.shared.warmCache()

            // Refresh public info (corp/alliance) concurrently with the full prefetch
            // so the correct names are visible as soon as possible without waiting
            // for the heavier prefetchAll to complete.
            async let publicInfo: Void = manager.refreshPublicInfo()
            async let prefetch: Void = pf.prefetchAll(accountManager: manager)
            _ = await (publicInfo, prefetch)

            // BackgroundMonitor's poll loop only runs its first cycle after a full
            // `backgroundPollInterval` (minutes away) — without this, Rich Presence
            // wouldn't show anything until then, even though the data it needs just
            // became available above.
            await DiscordRichPresence.refresh(accountManager: manager, prefetcher: pf)

            // Warm caches for slow-changing reference data (game-patch cadence, not
            // minute-to-minute) so the first visit to Market Browser, Career Agents,
            // or anything faction-labeled doesn't stall on a cold fetch.
            Task(priority: .utility) { await AgentDataManager.shared.ensureLoaded() }
            Task(priority: .utility) { _ = await UniverseCache.shared.allMarketGroups() }
            Task(priority: .utility) { await UniverseCache.shared.warmFactions() }

            // The app spends most of its life idling in the menu bar — a great time
            // to have EVE News ready before Dashboard is ever opened.
            Task(priority: .utility) { _ = try? await EVENewsClient.shared.fetchNews() }

            // Same idle-time logic for the Daily Briefing's AI insights — runs only
            // if the user has AI Insights (and briefing) enabled in Settings.
            Task(priority: .utility) { await pf.prefetchAIInsights(accountManager: manager) }

            // Warm the 3D model + textures for each character's current ship so
            // opening the ship viewer for "your ship" doesn't stall on a cold,
            // multi-MB download. Deduped by name since alts often fly the same hull.
            let currentShipNames = Set(pf.characterData.values.compactMap { pf.resolvedTypes[$0.ship.shipTypeId]?.name })
            for shipName in currentShipNames {
                Task(priority: .utility) {
                    _ = try? await ShipModelService.shared.modelURL(for: shipName)
                    async let albedo = try? await ShipModelService.shared.localAlbedoURL(for: shipName)
                    async let normal = try? await ShipModelService.shared.localNormalURL(for: shipName)
                    async let rough = try? await ShipModelService.shared.localRoughnessURL(for: shipName)
                    async let emissive = try? await ShipModelService.shared.localEmissiveURL(for: shipName)
                    _ = await (albedo, normal, rough, emissive)
                }
            }
        }
    }

    var body: some Scene {
        MenuBarExtra {
            MenuBarView()
                .environment(accountManager)
                .environment(prefetcher)
                .environment(apiStatusMonitor)
                .environment(appUpdater)
                .environment(themeManager)
                .tint(themeManager.palette.accent)
                .preferredColorScheme(resolvedColorScheme)
        } label: {
            MenuBarIconLabel(updateAvailable: appUpdater.updateAvailable)
        }
        .menuBarExtraStyle(.window)
        .commands { AppCommands(updater: appUpdater) }
    }
}

private struct MenuBarIconLabel: View {
    let updateAvailable: Bool
    @State private var pulsing = false

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Image("EveOpsTemplate")
            if updateAvailable {
                Circle()
                    .fill(Color.orange)
                    .frame(width: 5, height: 5)
                    .opacity(pulsing ? 0.2 : 1.0)
                    .offset(x: 3, y: -3)
                    .onAppear {
                        withAnimation(.easeInOut(duration: 1.2).repeatForever(autoreverses: true)) {
                            pulsing = true
                        }
                    }
            }
        }
    }
}
