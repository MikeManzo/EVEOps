import SwiftUI
import SwiftData

@main
struct EVEOpsApp: App {
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

        Settings {
            SettingsView()
                .environment(accountManager)
                .environment(prefetcher)
                .environment(appUpdater)
                .preferredColorScheme(resolvedColorScheme)
        }

        MenuBarExtra("EVEOps", image: "EveOpsTemplate" /*systemImage: "aqi.medium"*/) {
            MenuBarView()
                .environment(accountManager)
                .environment(prefetcher)
                .environment(apiStatusMonitor)
                .preferredColorScheme(resolvedColorScheme)
        }
        .menuBarExtraStyle(.window)
    }
}
