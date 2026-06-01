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
}

// Sets itself as the UNUserNotificationCenter delegate so banners are shown
// even while the app is active. Without this, macOS silently routes all
// notifications straight to Notification Center with no banner.
class AppDelegate: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate {
    func applicationWillFinishLaunching(_ notification: Notification) {
        // Replaces LSUIElement = YES so iconservicesd can serve our UTI icons
        // while keeping the app hidden from the Dock and App Switcher.
        NSApp.setActivationPolicy(.accessory)
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        UNUserNotificationCenter.current().delegate = self
        // Re-register UTIs (including the .eft document type icon) with Launch Services
        // on every launch so Finder always shows the correct icon without manual lsregister.
        LSRegisterURL(Bundle.main.bundleURL as CFURL, true)
    }

    func applicationWillTerminate(_ notification: Notification) {
        DiagnosticLogStore.shared.flushSync()
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        if let url = urls.first(where: { $0.pathExtension.lowercased() == "eft" }) {
            AppRouter.shared.pendingEFTURL = url
        }
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound, .list])
    }
}

@main
struct EVEOpsApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    var sharedModelContainer: ModelContainer = {
        let schema = Schema([
            StoredAccount.self,
            CachedName.self
        ])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
        do {
            return try ModelContainer(for: schema, configurations: [config])
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }()

    @State private var accountManager: AccountManager
    @State private var backgroundMonitor: BackgroundMonitor
    @State private var prefetcher: DashboardPrefetcher
    @State private var apiStatusMonitor: APIStatusMonitor
    @State private var presenceTracker: PresenceTracker
    @State private var appUpdater = AppUpdater()
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

        _accountManager = State(initialValue: manager)
        _backgroundMonitor = State(initialValue: bg)
        _prefetcher = State(initialValue: pf)
        _apiStatusMonitor = State(initialValue: api)
        _presenceTracker = State(initialValue: tracker)

        Task { @MainActor in
            bg.start(accountManager: manager)
            api.start()
            DiagnosticLogStore.shared.load()
            Logger.app.info("EVEOps started — diagnostic log active")

            // Configure presence tracker before starting the poll loop so it
            // has access to accounts and prefetched data from the first cycle.
            tracker.configure(accountManager: manager, prefetcher: pf)
            tracker.startPolling()

            // Refresh public info (corp/alliance) concurrently with the full prefetch
            // so the correct names are visible as soon as possible without waiting
            // for the heavier prefetchAll to complete.
            async let publicInfo: Void = manager.refreshPublicInfo()
            async let prefetch: Void = pf.prefetchAll(accountManager: manager)
            _ = await (publicInfo, prefetch)
        }
    }

    var body: some Scene {
        Window("EVEOps", id: "main") {
            MainContentView()
                .environment(accountManager)
                .environment(prefetcher)
                .environment(apiStatusMonitor)
                .environment(presenceTracker)
                .preferredColorScheme(resolvedColorScheme)
        }
        .modelContainer(sharedModelContainer)
        .windowStyle(.automatic)
        .defaultSize(width: 1100, height: 700)
        .defaultLaunchBehavior(.suppressed)

        WindowGroup(for: GalaxyMarketSearchInput.self) { $input in
            GalaxyMarketSearchView(
                initialTypeId: input?.typeId,
                initialTypeName: input?.typeName ?? ""
            )
            .environment(accountManager)
            .environment(prefetcher)
            .preferredColorScheme(resolvedColorScheme)
        }
        .defaultSize(width: 1100, height: 680)

        Settings {
            SettingsView()
                .environment(accountManager)
                .environment(prefetcher)
                .environment(appUpdater)
                .preferredColorScheme(resolvedColorScheme)
        }

        MenuBarExtra {
            MenuBarView()
                .environment(accountManager)
                .environment(prefetcher)
                .environment(apiStatusMonitor)
                .environment(appUpdater)
                .preferredColorScheme(resolvedColorScheme)
        } label: {
            MenuBarIconLabel(updateAvailable: appUpdater.updateAvailable)
        }
        .menuBarExtraStyle(.window)
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
