
//
// This file is part of EVEOps.
//
// EVEOps is free software: you can redistribute it and/or modify
// it under the terms of the GNU General Public License as published by
// the Free Software Foundation, version 3 or later.
//
// Copyright (c) 2026 CitizenCoder
//

@preconcurrency import Foundation
import FoundationModels

// MARK: Output Types
//
// Plain Codable structs — no @Generable, no @Guide.
// @Generable bakes a reference to FoundationModels.Generable.promptRepresentation
// into the binary at compile time. That symbol exists in the SDK the binary was
// built with but is absent from the FoundationModels.framework shipped with other
// OS versions, causing a dyld abort at launch. Using plain Codable structs with
// JSON-prompted free-form generation avoids all macro-generated symbol references
// and works on every FoundationModels version.

struct FinanceInsight: Codable, Sendable {
    var summary: String
    var suggestion: String
    private enum CodingKeys: String, CodingKey { case summary, suggestion }
    nonisolated init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        summary    = try c.decode(String.self, forKey: .summary)
        suggestion = try c.decode(String.self, forKey: .suggestion)
    }
}

struct SkillRecommendation: Codable, Sendable {
    var skillName: String
    var targetLevel: Int
    var rationale: String
    private enum CodingKeys: String, CodingKey { case skillName, targetLevel, rationale }
    nonisolated init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        skillName   = try c.decode(String.self, forKey: .skillName)
        targetLevel = try c.decode(Int.self,    forKey: .targetLevel)
        rationale   = try c.decode(String.self, forKey: .rationale)
    }
}

struct SkillTrainingRecommendation: Codable, Sendable {
    var playstyleSummary: String
    var recommendations: [SkillRecommendation]
    private enum CodingKeys: String, CodingKey { case playstyleSummary, recommendations }
    nonisolated init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        playstyleSummary = try c.decode(String.self,               forKey: .playstyleSummary)
        recommendations  = try c.decode([SkillRecommendation].self, forKey: .recommendations)
    }
}

struct CombatInsight: Codable, Sendable {
    var summary: String
    var suggestion: String
    private enum CodingKeys: String, CodingKey { case summary, suggestion }
    nonisolated init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        summary    = try c.decode(String.self, forKey: .summary)
        suggestion = try c.decode(String.self, forKey: .suggestion)
    }
}

struct IndustryInsight: Codable, Sendable {
    var summary: String
    var suggestion: String
    private enum CodingKeys: String, CodingKey { case summary, suggestion }
    nonisolated init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        summary    = try c.decode(String.self, forKey: .summary)
        suggestion = try c.decode(String.self, forKey: .suggestion)
    }
}

struct AssetInsight: Codable, Sendable {
    var summary: String
    var suggestion: String
    private enum CodingKeys: String, CodingKey { case summary, suggestion }
    nonisolated init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        summary    = try c.decode(String.self, forKey: .summary)
        suggestion = try c.decode(String.self, forKey: .suggestion)
    }
}

struct FittingInsight: Codable, Sendable {
    var roleAssessment: String
    var suggestion: String
    private enum CodingKeys: String, CodingKey { case roleAssessment, suggestion }
    nonisolated init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        roleAssessment = try c.decode(String.self, forKey: .roleAssessment)
        suggestion     = try c.decode(String.self, forKey: .suggestion)
    }
}

struct MarketInsight: Codable, Sendable {
    var summary: String
    var suggestion: String
    private enum CodingKeys: String, CodingKey { case summary, suggestion }
    nonisolated init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        summary    = try c.decode(String.self, forKey: .summary)
        suggestion = try c.decode(String.self, forKey: .suggestion)
    }
}

struct CloneInsight: Codable, Sendable {
    var setAssessment: String
    var recommendation: String
    var skillsNeeded: String
    private enum CodingKeys: String, CodingKey { case setAssessment, recommendation, skillsNeeded }
    nonisolated init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        setAssessment  = try c.decode(String.self, forKey: .setAssessment)
        recommendation = try c.decode(String.self, forKey: .recommendation)
        skillsNeeded   = try c.decode(String.self, forKey: .skillsNeeded)
    }
}

struct IntelligenceUnavailableError: LocalizedError {
    var errorDescription: String? {
        "Apple Intelligence insights are temporarily unavailable. Please check for an app update."
    }
}

struct IntelligenceParseError: LocalizedError {
    var errorDescription: String? {
        "Apple Intelligence returned an unexpected response. Please try again."
    }
}

// MARK: Service

@available(macOS 26.0, *)
actor IntelligenceService {
    static let shared = IntelligenceService()

    private static let generationOptions = GenerationOptions(temperature: 0.2)

    private var financeCache:  [String: FinanceInsight]               = [:]
    private var skillCache:    [String: SkillTrainingRecommendation]  = [:]
    private var combatCache:   [String: CombatInsight]                = [:]
    private var industryCache: [String: IndustryInsight]              = [:]
    private var assetCache:    [String: AssetInsight]                 = [:]
    private var fittingCache:  [String: FittingInsight]               = [:]
    private var marketCache:   [String: MarketInsight]                = [:]
    private var cloneCache:    [String: CloneInsight]                 = [:]

    // MARK: Generic JSON helper

    // Prompts the model with free-form text and decodes the JSON response.
    // The caller includes the exact JSON schema in the prompt so the model
    // knows what structure to produce.
    private nonisolated func generate<T: Decodable>(instructions: String, prompt: String) async throws -> T {
        let session = LanguageModelSession(instructions: instructions)
        let response = try await session.respond(to: prompt, options: Self.generationOptions)
        var raw = response.content.trimmingCharacters(in: .whitespacesAndNewlines)

        // Strip markdown code-block wrapper that some model versions add
        if raw.hasPrefix("```") {
            let lines = raw.components(separatedBy: "\n")
            raw = lines.dropFirst().dropLast()
                .joined(separator: "\n")
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }
        // Extract the first {...} block in case the model added surrounding text
        if let start = raw.firstIndex(of: "{"), let end = raw.lastIndex(of: "}") {
            raw = String(raw[start...end])
        }

        guard let data = raw.data(using: .utf8) else { throw IntelligenceParseError() }
        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            throw IntelligenceParseError()
        }
    }

    // MARK: Finance Analysis

    func analyzeFinances(
        characterName: String,
        balanceFormatted: String,
        netWorthFormatted: String,
        sellOrderCount: Int,
        buyOrderCount: Int,
        topRefTypes: [(name: String, totalFormatted: String)]
    ) async throws -> FinanceInsight {
        let activitySummary = topRefTypes.prefix(5)
            .map { "\($0.name): \($0.totalFormatted)" }
            .joined(separator: "; ")

        let prompt = """
        EVE Online character: \(characterName)
        Wallet balance: \(balanceFormatted)
        Net worth: \(netWorthFormatted)
        Market activity: \(sellOrderCount) sell orders, \(buyOrderCount) buy orders
        Recent financial activity: \(activitySummary.isEmpty ? "no recent activity recorded" : activitySummary)

        Respond ONLY with a JSON object in this exact structure, no other text:
        {"summary": "<2-3 sentence financial assessment>", "suggestion": "<1 actionable ISK-making suggestion>"}
        """

        if let cached = financeCache[prompt] { return cached }

        let result: FinanceInsight = try await generate(
            instructions: "You are a concise EVE Online financial advisor. Provide practical ISK-making analysis using correct EVE Online terminology. Respond only with the JSON object requested — no preamble, no explanation.",
            prompt: prompt
        )
        financeCache[prompt] = result
        return result
    }

    // MARK: Trained Skills Analysis

    func analyzeTrainedSkills(
        characterName: String,
        totalSP: Int,
        topGroups: [(name: String, spFormatted: String, skillCount: Int, maxedCount: Int)],
        partialSkills: [(name: String, level: Int)],
        maxedSkills: [String]
    ) async throws -> SkillTrainingRecommendation {
        let groupLines = topGroups
            .map { g -> String in
                let maxedNote = g.maxedCount > 0 ? ", \(g.maxedCount) at L5" : ""
                return "  \(g.name): \(g.spFormatted), \(g.skillCount) skills\(maxedNote)"
            }
            .joined(separator: "\n")

        let partialList = partialSkills.isEmpty ? "none"
            : partialSkills.map { "\($0.name) (L\($0.level))" }.joined(separator: ", ")

        let maxedList = maxedSkills.isEmpty ? "none" : maxedSkills.joined(separator: ", ")

        let prompt = """
        EVE Online character: \(characterName)
        Total Skill Points: \(formatSP(totalSP))
        Top skill areas by SP:
        \(groupLines)
        Partially trained skills with current level — eligible to train higher:
        \(partialList)
        Maxed skills (L5) — DO NOT recommend any of these:
        \(maxedList)

        Respond ONLY with a JSON object in this exact structure, no other text:
        {"playstyleSummary": "<2-3 sentence playstyle description>", "recommendations": [{"skillName": "<bare EVE skill name>", "targetLevel": <integer 1-5>, "rationale": "<1 sentence reason>"}, ... exactly 7 items]}

        Rules: skillName must be the bare skill name only (e.g. "Caldari Cruiser"). targetLevel must be strictly greater than the skill's current level shown in parentheses, or 1 if the skill is not listed. Never recommend maxed (L5) skills.
        """

        if let cached = skillCache[prompt] { return cached }

        let result: SkillTrainingRecommendation = try await generate(
            instructions: "You are an EVE Online skill advisor. Recommend exactly 7 skills to train next in priority order. Respond only with the JSON object requested — no preamble, no explanation.",
            prompt: prompt
        )
        skillCache[prompt] = result
        return result
    }

    // MARK: Combat Analysis

    func analyzeCombat(
        characterName: String,
        killCount: Int,
        lossCount: Int,
        topLostShips: [(name: String, count: Int)],
        activeSystemNames: [String],
        avgAttackersOnLoss: Double,
        commonThreatShips: [String]
    ) async throws -> CombatInsight {
        let lostShipSummary = topLostShips.prefix(4)
            .map { "\($0.name) x\($0.count)" }
            .joined(separator: ", ")
        let systemSummary = activeSystemNames.prefix(4).joined(separator: ", ")
        let threatSummary = commonThreatShips.prefix(4).joined(separator: ", ")

        let prompt = """
        EVE Online character: \(characterName)
        Recent combat (up to 50 killmails): \(killCount) kills, \(lossCount) losses
        Most frequently lost ships: \(lostShipSummary.isEmpty ? "none" : lostShipSummary)
        Average number of attackers on losses: \(String(format: "%.1f", avgAttackersOnLoss)) (1-2 = solo/small gang; 5+ = large fleet)
        Most active systems: \(systemSummary.isEmpty ? "unknown" : systemSummary)
        Common ships attacking this character: \(threatSummary.isEmpty ? "unknown" : threatSummary)

        Respond ONLY with a JSON object in this exact structure, no other text:
        {"summary": "<2-3 sentence combat assessment>", "suggestion": "<1 actionable suggestion to improve combat performance or survivability>"}
        """

        if let cached = combatCache[prompt] { return cached }

        let result: CombatInsight = try await generate(
            instructions: "You are a concise EVE Online PvP analyst. Assess combat style and efficiency based on kill/loss data. Respond only with the JSON object requested — no preamble, no explanation.",
            prompt: prompt
        )
        combatCache[prompt] = result
        return result
    }

    // MARK: Industry Analysis

    func analyzeIndustry(
        characterName: String,
        totalJobs: Int,
        activeJobs: Int,
        activityBreakdown: [(activity: String, count: Int)],
        topBlueprints: [String]
    ) async throws -> IndustryInsight {
        let activityLines = activityBreakdown
            .map { "\($0.activity): \($0.count) jobs" }
            .joined(separator: "; ")
        let blueprintList = topBlueprints.prefix(8).joined(separator: ", ")

        let prompt = """
        EVE Online character: \(characterName)
        Industry job history: \(totalJobs) total jobs (\(activeJobs) currently active)
        Activity breakdown: \(activityLines.isEmpty ? "none recorded" : activityLines)
        Most used blueprints: \(blueprintList.isEmpty ? "none" : blueprintList)

        Respond ONLY with a JSON object in this exact structure, no other text:
        {"summary": "<2-3 sentence industry assessment>", "suggestion": "<1 actionable suggestion to improve output, profit, or production chain value>"}
        """

        if let cached = industryCache[prompt] { return cached }

        let result: IndustryInsight = try await generate(
            instructions: "You are a concise EVE Online industrial advisor. Use correct EVE Online industry terminology. Respond only with the JSON object requested — no preamble, no explanation.",
            prompt: prompt
        )
        industryCache[prompt] = result
        return result
    }

    // MARK: Asset Analysis

    func analyzeAssets(
        characterName: String,
        totalStacks: Int,
        locationCount: Int,
        topLocationsByCount: [(location: String, count: Int)],
        topItemsByQuantity: [(name: String, quantity: Int)]
    ) async throws -> AssetInsight {
        let locationLines = topLocationsByCount.prefix(5)
            .map { "\($0.location): \($0.count) stacks" }
            .joined(separator: "; ")
        let itemLines = topItemsByQuantity.prefix(5)
            .map { "\($0.name): x\($0.quantity)" }
            .joined(separator: "; ")

        let prompt = """
        EVE Online character: \(characterName)
        Total assets: \(totalStacks) stacks across \(locationCount) locations
        Top locations by asset count: \(locationLines.isEmpty ? "none" : locationLines)
        Most-held items by quantity: \(itemLines.isEmpty ? "none" : itemLines)

        Respond ONLY with a JSON object in this exact structure, no other text:
        {"summary": "<2-3 sentence assessment of asset spread across New Eden>", "suggestion": "<1 actionable suggestion to consolidate, liquidate, or better deploy assets>"}
        """

        if let cached = assetCache[prompt] { return cached }

        let result: AssetInsight = try await generate(
            instructions: "You are a concise EVE Online logistics advisor. Respond only with the JSON object requested — no preamble, no explanation.",
            prompt: prompt
        )
        assetCache[prompt] = result
        return result
    }

    // MARK: Fitting Analysis

    func analyzeFitting(
        shipName: String,
        shipClass: String,
        slotModules: [(category: String, names: [String])]
    ) async throws -> FittingInsight {
        let slotLines = slotModules
            .filter { !$0.names.isEmpty }
            .map { "  \($0.category): \($0.names.joined(separator: ", "))" }
            .joined(separator: "\n")

        let prompt = """
        EVE Online ship fitting:
        Ship: \(shipName) (\(shipClass))
        Fitted modules:
        \(slotLines.isEmpty ? "  No modules" : slotLines)

        Respond ONLY with a JSON object in this exact structure, no other text:
        {"roleAssessment": "<2-3 sentence assessment of this fitting's role, tank type, and overall purpose>", "suggestion": "<1 specific module swap or addition to improve the fitting>"}
        """

        if let cached = fittingCache[prompt] { return cached }

        let result: FittingInsight = try await generate(
            instructions: "You are a concise EVE Online fitting advisor. Use correct EVE Online module names and fitting terminology. Respond only with the JSON object requested — no preamble, no explanation.",
            prompt: prompt
        )
        fittingCache[prompt] = result
        return result
    }

    // MARK: Market Analysis

    func analyzeMarket(
        itemName: String,
        regionName: String,
        bestSell: String,
        bestBuy: String,
        spreadPercent: Double,
        sellOrderCount: Int,
        buyOrderCount: Int,
        avgDailyVolume: Int,
        priceChange30dPercent: Double,
        adjustedPrice: String?,
        globalAveragePrice: String?
    ) async throws -> MarketInsight {
        let trend: String
        if priceChange30dPercent > 5 {
            let pct = (priceChange30dPercent / 100).formatted(.percent.precision(.fractionLength(1)))
            trend = "rising (+\(pct) over 30 days)"
        } else if priceChange30dPercent < -5 {
            let pct = (priceChange30dPercent / 100).formatted(.percent.precision(.fractionLength(1)))
            trend = "falling (\(pct) over 30 days)"
        } else {
            let pct = (priceChange30dPercent / 100).formatted(.percent.precision(.fractionLength(1)))
            trend = "stable (\(pct) over 30 days)"
        }

        var priceLine = ""
        if let adj = adjustedPrice { priceLine += "ESI adjusted price: \(adj). " }
        if let avg = globalAveragePrice { priceLine += "Global average price: \(avg). " }

        let prompt = """
        EVE Online market analysis:
        Item: \(itemName)
        Region: \(regionName)
        Best sell price: \(bestSell)
        Best buy price: \(bestBuy)
        Spread: \((spreadPercent / 100).formatted(.percent.precision(.fractionLength(1))))
        Active orders: \(sellOrderCount) sell, \(buyOrderCount) buy
        5-day average daily volume: \(avgDailyVolume > 0 ? "\(avgDailyVolume) units" : "unknown")
        30-day price trend: \(trend)
        \(priceLine)

        Respond ONLY with a JSON object in this exact structure, no other text:
        {"summary": "<2-3 sentence assessment of price trend, liquidity, and spread>", "suggestion": "<1 actionable trading suggestion: buy, sell, station trade, arbitrage, or wait>"}
        """

        if let cached = marketCache[prompt] { return cached }

        let result: MarketInsight = try await generate(
            instructions: "You are a concise EVE Online market analyst. Use correct EVE Online market terminology. Respond only with the JSON object requested — no preamble, no explanation.",
            prompt: prompt
        )
        marketCache[prompt] = result
        return result
    }

    // MARK: Clone / Implant Analysis

    func analyzeImplants(
        characterName: String,
        activeImplantNames: [String],
        jumpCloneImplantNames: [[String]],
        totalSP: Int,
        topSkillAreas: [(name: String, spFormatted: String)]
    ) async throws -> CloneInsight {
        let implantList = activeImplantNames.isEmpty
            ? "  none installed"
            : activeImplantNames.enumerated()
                .map { "  \($0.offset + 1). \($0.element)" }
                .joined(separator: "\n")

        let jumpCloneLines: String
        if jumpCloneImplantNames.isEmpty {
            jumpCloneLines = "  no jump clones"
        } else {
            jumpCloneLines = jumpCloneImplantNames.enumerated()
                .map { idx, implants in
                    let names = implants.isEmpty ? "empty clone" : implants.joined(separator: ", ")
                    return "  Clone \(idx + 1): \(names)"
                }
                .joined(separator: "\n")
        }

        let skillAreaLines = topSkillAreas.prefix(5)
            .map { "  \($0.name): \($0.spFormatted)" }
            .joined(separator: "\n")

        let prompt = """
        EVE Online character: \(characterName)
        Total Skill Points: \(formatSP(totalSP))
        Top skill areas (indicates playstyle):
        \(skillAreaLines.isEmpty ? "  not available" : skillAreaLines)
        Active implants currently installed:
        \(implantList)
        Jump clone implants in storage:
        \(jumpCloneLines)

        Respond ONLY with a JSON object in this exact structure, no other text:
        {"setAssessment": "<3+ sentence assessment: identify implant grade and slot coverage, evaluate playstyle alignment, comment on set completeness>", "recommendation": "<1 specific implant upgrade using exact EVE item name, slot number, and reason>", "skillsNeeded": "<exact EVE skill name and minimum level required, or 'None required'>"}

        Slot reference: slots 1-5 are attribute implants (1=Perception, 2=Memory, 3=Willpower, 4=Intelligence, 5=Charisma); slots 6-10 are hardwirings. Cybernetics I-V gates implant grades.
        """

        if let cached = cloneCache[prompt] { return cached }

        let result: CloneInsight = try await generate(
            instructions: "You are a knowledgeable EVE Online implant advisor. Write thorough, specific implant set assessments using exact EVE Online item names. Respond only with the JSON object requested — no preamble, no explanation.",
            prompt: prompt
        )
        cloneCache[prompt] = result
        return result
    }

    // MARK: Helpers

    private func formatSP(_ sp: Int) -> String {
        if sp >= 1_000_000 { return String(format: "%.1fM SP", Double(sp) / 1_000_000) }
        if sp >= 1_000    { return String(format: "%.0fK SP", Double(sp) / 1_000) }
        return "\(sp) SP"
    }
}
