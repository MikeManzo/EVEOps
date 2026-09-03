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

/// The three social skills that shift *effective* standing for agent access.
struct StandingSkills: Sendable, Equatable {
    var connections = 0          // raises positive standings (non-pirate)
    var criminalConnections = 0  // raises positive standings with pirate factions
    var diplomacy = 0            // raises (less-negative) negative standings

    static let connectionsSkillID = 3359
    static let criminalConnectionsSkillID = 3361
    static let diplomacySkillID = 3357

    init() {}

    init(skills: [ESISkill]) {
        for s in skills {
            switch s.skillId {
            case Self.connectionsSkillID:         connections = s.activeSkillLevel
            case Self.criminalConnectionsSkillID: criminalConnections = s.activeSkillLevel
            case Self.diplomacySkillID:           diplomacy = s.activeSkillLevel
            default: break
            }
        }
    }
}

/// Result of checking whether a character can talk to a given agent.
struct AgentAccessResult: Sendable, Equatable {
    enum Basis: String, Sendable {
        case faction = "Faction"
        case corporation = "Corporation"
        case agent = "Agent"
        case neutral = "Neutral"
    }

    let level: Int
    let requiredStanding: Double
    let effectiveStanding: Double
    /// Which underlying standing produced the best effective value.
    let basis: Basis
    /// Raw (unmodified) standing for `basis` before skills.
    let baseStanding: Double
    /// True when at least one real faction/corp/agent standing entry existed.
    let hasStandingData: Bool
    /// Social skill applied to the winning standing, and its trained level.
    let skillName: String
    let skillLevel: Int

    var canAccess: Bool { level <= 1 || effectiveStanding >= requiredStanding }
    /// How much more effective standing is needed (0 when already accessible).
    var gap: Double { max(0, requiredStanding - effectiveStanding) }
}

enum AgentAccess {
    /// Factions whose positive standings are boosted by Criminal Connections rather than Connections.
    static let pirateFactionIDs: Set<Int> = [500017, 500018, 500019, 500020, 500021]

    /// Minimum effective standing to accept missions from an agent of the given level.
    /// Level 1 agents have no requirement.
    static func requiredStanding(forLevel level: Int) -> Double {
        switch level {
        case ...1: return 0.0
        case 2:    return 1.0
        case 3:    return 3.0
        case 4:    return 5.0
        default:   return 7.0
        }
    }

    /// Applies Connections / Criminal Connections / Diplomacy to a base standing.
    /// `effective = base + (10 - base) * 0.04 * skillLevel`
    static func effective(base: Double, skills: StandingSkills, pirate: Bool) -> Double {
        let level = base < 0 ? skills.diplomacy : (pirate ? skills.criminalConnections : skills.connections)
        guard level > 0 else { return base }
        return base + (10.0 - base) * 0.04 * Double(level)
    }

    /// Picks the most favourable of the faction / corp / agent standings (each run
    /// through the skill formula) and reports whether it clears the level gate.
    static func evaluate(
        level: Int,
        factionBase: Double?,
        corpBase: Double?,
        agentBase: Double?,
        skills: StandingSkills,
        pirateFaction: Bool
    ) -> AgentAccessResult {
        let inputs: [(AgentAccessResult.Basis, Double?)] = [
            (.faction, factionBase),
            (.corporation, corpBase),
            (.agent, agentBase),
        ]

        var bestBasis: AgentAccessResult.Basis = .neutral
        var bestBase = 0.0
        var bestEff = effective(base: 0, skills: skills, pirate: pirateFaction)
        var hasData = false

        for (basis, value) in inputs {
            guard let base = value else { continue }
            hasData = true
            let eff = effective(base: base, skills: skills, pirate: pirateFaction)
            if eff > bestEff {
                bestEff = eff
                bestBasis = basis
                bestBase = base
            }
        }

        let usedDiplomacy = bestBase < 0
        let skillName = usedDiplomacy ? "Diplomacy" : (pirateFaction ? "Criminal Connections" : "Connections")
        let skillLevel = usedDiplomacy ? skills.diplomacy : (pirateFaction ? skills.criminalConnections : skills.connections)

        return AgentAccessResult(
            level: level,
            requiredStanding: requiredStanding(forLevel: level),
            effectiveStanding: bestEff,
            basis: bestBasis,
            baseStanding: bestBase,
            hasStandingData: hasData,
            skillName: skillName,
            skillLevel: skillLevel
        )
    }
}
