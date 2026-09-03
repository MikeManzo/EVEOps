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

enum AgentTypeFilter: String, CaseIterable, Identifiable {
    case career      = "Career"
    case basic       = "Basic Mission"
    case research    = "R&D Research"
    case storyline   = "Storyline"
    case factWarfare = "Faction Warfare"
    case epicArc     = "Epic Arc"
    case locator     = "Locator"

    var id: String { rawValue }

    var agentTypeID: Int? {
        switch self {
        case .career:      return 12
        case .basic:       return 2
        case .research:    return 4
        case .storyline:   return 7
        case .factWarfare: return 9
        case .epicArc:     return 10
        case .locator:     return nil
        }
    }

    var isLocatorMode: Bool { self == .locator }

    var iconName: String {
        switch self {
        case .career:      return "graduationcap.fill"
        case .basic:       return "shield.fill"
        case .research:    return "atom"
        case .storyline:   return "book.fill"
        case .factWarfare: return "flag.fill"
        case .epicArc:     return "sparkles"
        case .locator:     return "magnifyingglass.circle.fill"
        }
    }

    var color: Color {
        switch self {
        case .career:      return .cyan
        case .basic:       return .blue
        case .research:    return .purple
        case .storyline:   return .orange
        case .factWarfare: return .red
        case .epicArc:     return .yellow
        case .locator:     return .green
        }
    }
}

// MARK:  Security Range Filter

enum SecurityRangeFilter: String, CaseIterable, Identifiable {
    case any  = "Any"
    case high = "High Sec"
    case low  = "Low Sec"
    case null = "Null Sec"

    var id: String { rawValue }

    var title: LocalizedStringKey {
        switch self {
        case .any:  "Any"
        case .high: "High Sec"
        case .low:  "Low Sec"
        case .null: "Null Sec"
        }
    }

    func matches(_ status: Double?) -> Bool {
        guard let s = status else { return self == .any }
        switch self {
        case .any:  return true
        case .high: return s >= 0.5
        case .low:  return s >= 0.1 && s < 0.5
        case .null: return s < 0.1
        }
    }
}

// MARK:  Agent Sort Order

enum AgentSortOrder: String, CaseIterable, Identifiable {
    case jumps = "Jumps"
    case level = "Level"
    var id: String { rawValue }
    var title: LocalizedStringKey {
        switch self {
        case .jumps: "Jumps"
        case .level: "Level"
        }
    }
}

// MARK:  Resolved Agent

struct ResolvedAgent: Identifiable {
    let agent: AgentDataManager.SDEAgent
    var name: String?
    var corpName: String?
    var systemID: Int?
    var systemName: String?
    var securityStatus: Double?
    var jumpCount: Int?
    var constellationName: String?
    var regionName: String?
    var access: AgentAccessResult?
    var id: Int { agent.agentID }

    var displayName: String   { name     ?? "Agent \(agent.agentID)" }
    var displayCorp: String   { corpName ?? "Corp \(agent.corporationID)" }
    var displaySystem: String { systemName ?? "Station \(agent.locationID)" }
}

// MARK:  Agent Finder View

