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

        _accountManager = State(initialValue: manager)
        _backgroundMonitor = State(initialValue: bg)
        _prefetcher = State(initialValue: pf)
        _apiStatusMonitor = State(initialValue: api)

        Task { @MainActor in
            bg.start(accountManager: manager)
            api.start()
            await pf.prefetchAll(accountManager: manager)
        }
    }

    var body: some Scene {
        Window("EVEOps", id: "main") {
            MainContentView()
                .environment(accountManager)
                .environment(prefetcher)
                .environment(apiStatusMonitor)
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
                .preferredColorScheme(resolvedColorScheme)
        }

        MenuBarExtra("EVEOps", systemImage: "aqi.medium") {
            MenuBarView()
                .environment(accountManager)
                .environment(prefetcher)
                .environment(apiStatusMonitor)
                .preferredColorScheme(resolvedColorScheme)
        }
        .menuBarExtraStyle(.window)
    }
}
