import Foundation

enum NavigationSection: String, CaseIterable, Identifiable {
    case dashboard = "Dashboard"

    // Character
    case location = "Location"
    case training = "Training"
    case finances = "Finances"
    case assets = "Assets"
    case clones = "Clones"
    case colonies = "Colonies"
    case contracts = "Contracts"
    case industry = "Industry"
    case communications = "Communications"
    case mails = "Mails"
    case killmails = "Kill Mails"
    case fittings = "Fittings"
    case calendar = "Calendar"
    case standings = "Standings"
    case contacts = "Contacts"
    case routePlanner = "Route Planner"
    case market = "Market"
    case stationBrowser = "Station Browser"

    // Corporation
    case corpAssets = "Corp Assets"
    case corpIndustry = "Corp Industry"
    case corpMembers = "Corp Members"
    case corpStructures = "Corp Structures"
    case corpWallets = "Corp Wallets"
    case corpContracts = "Corp Contracts"
    case corpKillmails = "Corp Kill Mails"
    case corpMarketOrders = "Corp Market Orders"
    case corpMining = "Corp Mining"

    var id: String { rawValue }

    var iconName: String {
        switch self {
        case .dashboard: return "square.grid.2x2.fill"
        case .location: return "location.fill"
        case .training: return "graduationcap.fill"
        case .finances: return "banknote.fill"
        case .assets, .corpAssets: return "shippingbox.fill"
        case .clones: return "person.2.fill"
        case .colonies: return "globe.americas.fill"
        case .contracts: return "doc.text.fill"
        case .industry, .corpIndustry: return "hammer.fill"
        case .communications: return "bell.fill"
        case .mails: return "envelope.fill"
        case .killmails, .corpKillmails: return "flame.fill"
        case .fittings: return "wrench.and.screwdriver.fill"
        case .calendar: return "calendar"
        case .standings: return "star.fill"
        case .contacts: return "person.2.wave.2.fill"
        case .routePlanner: return "map.fill"
        case .corpWallets: return "creditcard.fill"
        case .corpMembers: return "person.3.fill"
        case .corpStructures: return "building.2.fill"
        case .corpContracts: return "doc.badge.arrow.up.fill"
        case .corpMarketOrders: return "cart.fill"
        case .corpMining: return "cylinder.fill"
        case .market: return "storefront"
        case .stationBrowser: return "building.2.crop.circle.fill"
        }
    }

    static var pilotSections: [NavigationSection] {
        [.location, .training, .clones]
    }

    static var economySections: [NavigationSection] {
        [.finances, .assets, .market, .stationBrowser, .contracts, .industry, .colonies]
    }

    static var combatSections: [NavigationSection] {
        [.fittings, .killmails]
    }

    static var socialSections: [NavigationSection] {
        [.mails, .communications, .calendar, .contacts, .standings, .routePlanner]
    }

    static var corporationSections: [NavigationSection] {
        [.corpAssets, .corpIndustry, .corpMembers, .corpStructures, .corpWallets,
         .corpContracts, .corpKillmails, .corpMarketOrders, .corpMining]
    }
}
