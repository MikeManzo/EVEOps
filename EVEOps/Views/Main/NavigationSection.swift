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
    case galaxyMap = "Galaxy Map"
    case careerAgents = "Career Agents"
    case fleetManager = "Fleet Manager"
    case market = "Market"
    case stationBrowser = "Station Browser"
    case skillPlanner = "Skill Planner"
    // Character — tools
    case remapAdvisor = "Remap Advisor"
    case research = "Research Agents"
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
    case corpWars = "Corp Wars"
    case corpMoonExtractions = "Moon Extractions"

    // Utility
    case diagnosticLogs = "Diagnostic Logs"

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
        case .galaxyMap: return "globe"
        case .careerAgents: return "person.badge.plus"
        case .fleetManager: return "dot.radiowaves.left.and.right"
        case .corpWallets: return "creditcard.fill"
        case .corpMembers: return "person.3.fill"
        case .corpStructures: return "building.2.fill"
        case .corpContracts: return "doc.badge.arrow.up.fill"
        case .corpMarketOrders: return "cart.fill"
        case .corpMining: return "cylinder.fill"
        case .corpWars: return "shield.lefthalf.filled"
        case .market: return "storefront"
        case .stationBrowser: return "building.2.crop.circle.fill"
        case .skillPlanner: return "checklist"
        case .remapAdvisor: return "brain.filled.head.profile"
        case .research: return "atom"
        case .corpMoonExtractions: return "moon.fill"
        case .diagnosticLogs: return "terminal"
        }
    }

    static var pilotSections: [NavigationSection] {
        [.location, .training, .skillPlanner, .clones, .research, .remapAdvisor]
    }

    static var economySections: [NavigationSection] {
        [.finances, .assets, .market, .contracts, .industry, .colonies]
    }

    static var combatSections: [NavigationSection] {
        [.fittings, .killmails, .fleetManager]
    }

    static var socialSections: [NavigationSection] {
        [.mails, .communications, .calendar, .contacts, .standings]
    }

    static var universeSections: [NavigationSection] {
        [.routePlanner, .galaxyMap, .stationBrowser, .careerAgents]
    }

    static var corporationSections: [NavigationSection] {
        [.corpAssets, .corpIndustry, .corpMembers, .corpStructures, .corpWallets,
         .corpContracts, .corpKillmails, .corpMarketOrders, .corpMining, .corpWars, .corpMoonExtractions]
    }

    static var utilitySections: [NavigationSection] {
        [.diagnosticLogs]
    }
}
