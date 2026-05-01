import Foundation
import FoundationModels

// Mark:  Generable Output Types

@available(macOS 26.0, *)
@Generable(description: "Financial health analysis for an EVE Online character")
struct FinanceInsight: Sendable {
    @Guide(description: "Two to three sentence assessment of this character's financial situation, main income sources, and market activity")
    var summary: String

    @Guide(description: "One specific, actionable suggestion to grow ISK or improve market efficiency in EVE Online")
    var suggestion: String
}

@available(macOS 26.0, *)
@Generable(description: "A single EVE Online skill training recommendation")
struct SkillRecommendation: Sendable {
    @Guide(description: "The exact EVE Online skill name only — no prefixes, no level info. Examples: 'Caldari Cruiser', 'Shield Operation', 'Heavy Missiles'")
    var skillName: String

    @Guide(description: "The numeric level to train this skill to", .range(1...5))
    var targetLevel: Int

    @Guide(description: "One sentence explaining why this skill is valuable for this character")
    var rationale: String
}

@available(macOS 26.0, *)
@Generable(description: "Skill training recommendations for an EVE Online character based on their existing trained skills")
struct SkillTrainingRecommendation: Sendable {
    @Guide(description: "Two to three sentence description of this character's evident EVE Online playstyle and strengths based on their trained skills")
    var playstyleSummary: String

    @Guide(description: "Seven skill recommendations in priority order, from most to least impactful for this character's development", .count(7))
    var recommendations: [SkillRecommendation]
}

// MARK: Combat Analysis Insight

@available(macOS 26.0, *)
@Generable(description: "Combat performance analysis for an EVE Online character")
struct CombatInsight: Sendable {
    @Guide(description: "Two to three sentence assessment of this character's combat style, preferred ships or roles, and overall kill/loss performance based on recent killmail history")
    var summary: String

    @Guide(description: "One specific, actionable suggestion to improve combat performance, survivability, or ISK efficiency in EVE Online")
    var suggestion: String
}

// MARK: Industry Analysis Insight

@available(macOS 26.0, *)
@Generable(description: "Industry and manufacturing efficiency analysis for an EVE Online character")
struct IndustryInsight: Sendable {
    @Guide(description: "Two to three sentence assessment of this character's industrial activity, production focus, and slot utilization based on their job history")
    var summary: String

    @Guide(description: "One specific, actionable suggestion to improve manufacturing output, profit margin, or expand into higher-value production chains in EVE Online")
    var suggestion: String
}

// MARK: Asset Distribution Insight

@available(macOS 26.0, *)
@Generable(description: "Asset distribution and management analysis for an EVE Online character")
struct AssetInsight: Sendable {
    @Guide(description: "Two to three sentence assessment of this character's asset spread across the galaxy, notable holdings, and potential inefficiencies in asset management")
    var summary: String

    @Guide(description: "One specific, actionable suggestion to consolidate, liquidate, or better deploy underused or stranded assets in EVE Online")
    var suggestion: String
}

// MARK: Fitting Analysis Insight

@available(macOS 26.0, *)
@Generable(description: "Ship fitting role and optimization analysis for EVE Online")
struct FittingInsight: Sendable {
    @Guide(description: "Two to three sentence assessment of this fitting's intended role, tank type, and overall purpose based on the modules (e.g., active armor PvE Dominix, passive shield Raven for Level 4 missions)")
    var roleAssessment: String

    @Guide(description: "One specific, actionable module swap or addition to improve this fitting's performance, survivability, or ISK efficiency in EVE Online")
    var suggestion: String
}

// MARK: Market Analysis Insight

@available(macOS 26.0, *)
@Generable(description: "Market price and liquidity analysis for an EVE Online tradeable item")
struct MarketInsight: Sendable {
    @Guide(description: "Two to three sentence assessment of this item's current price trend, market liquidity, and buy/sell spread in the selected region based on order count, daily volume, and recent price movement")
    var summary: String

    @Guide(description: "One specific, actionable suggestion — whether to buy, sell, station trade, arbitrage between regions, or wait for a better price — based on current market conditions in EVE Online")
    var suggestion: String
}

// Mark:  Service

@available(macOS 26.0, *)
actor IntelligenceService {
    static let shared = IntelligenceService()

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
        """

        let session = LanguageModelSession(
            instructions: "You are a concise EVE Online financial advisor. Provide practical ISK-making analysis using correct EVE Online terminology."
        )
        let response = try await session.respond(to: prompt, generating: FinanceInsight.self)
        return response.content
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

        // e.g. "Caldari Cruiser (L3), Shield Operation (L4), Heavy Missiles (L2)"
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
        """

        let session = LanguageModelSession(
            instructions: "You are an EVE Online skill advisor. Based on the character's skill areas, recommend 7 skills to train next. You may suggest training a partially-trained skill to a higher level, or suggest a brand-new skill (not yet trained) that suits the character. For skillName give ONLY the bare EVE skill name — no level info, no prefixes (e.g. 'Caldari Cruiser', not 'Caldari Cruiser to Level V'). For targetLevel give the integer level to train TO; it must be strictly greater than the skill's current level shown in parentheses, or 1 if the skill is not listed. Never recommend maxed (L5) skills."
        )
        let response = try await session.respond(to: prompt, generating: SkillTrainingRecommendation.self)
        return response.content
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
            .map { "\($0.name) ×\($0.count)" }
            .joined(separator: ", ")
        let systemSummary = activeSystemNames.prefix(4).joined(separator: ", ")
        let threatSummary = commonThreatShips.prefix(4).joined(separator: ", ")

        let prompt = """
        EVE Online character: \(characterName)
        Recent combat (up to 50 killmails): \(killCount) kills, \(lossCount) losses
        Most frequently lost ships: \(lostShipSummary.isEmpty ? "none" : lostShipSummary)
        Average number of attackers on losses: \(String(format: "%.1f", avgAttackersOnLoss)) (1–2 = solo/small gang; 5+ = large fleet)
        Most active systems: \(systemSummary.isEmpty ? "unknown" : systemSummary)
        Common ships attacking this character: \(threatSummary.isEmpty ? "unknown" : threatSummary)
        """

        let session = LanguageModelSession(
            instructions: "You are a concise EVE Online PvP analyst. Assess this character's combat style and efficiency based on their kill/loss data, then give one practical suggestion to improve their combat performance or survivability."
        )
        let response = try await session.respond(to: prompt, generating: CombatInsight.self)
        return response.content
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
        """

        let session = LanguageModelSession(
            instructions: "You are a concise EVE Online industrial advisor. Analyze this character's manufacturing and industry activity, then give one practical suggestion to improve efficiency, profitability, or production chain value. Use correct EVE Online industry terminology."
        )
        let response = try await session.respond(to: prompt, generating: IndustryInsight.self)
        return response.content
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
            .map { "\($0.name): ×\($0.quantity)" }
            .joined(separator: "; ")

        let prompt = """
        EVE Online character: \(characterName)
        Total assets: \(totalStacks) stacks across \(locationCount) locations
        Top locations by asset count: \(locationLines.isEmpty ? "none" : locationLines)
        Most-held items by quantity: \(itemLines.isEmpty ? "none" : itemLines)
        """

        let session = LanguageModelSession(
            instructions: "You are a concise EVE Online logistics advisor. Analyze how this character's assets are distributed across New Eden and give one actionable suggestion to consolidate, liquidate, or better utilize their holdings."
        )
        let response = try await session.respond(to: prompt, generating: AssetInsight.self)
        return response.content
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
        """

        let session = LanguageModelSession(
            instructions: "You are a concise EVE Online fitting advisor. Based on the module loadout, identify the fitting's role and tank type, then give one specific, practical module swap or addition to improve it. Use correct EVE Online module names and fitting terminology."
        )
        let response = try await session.respond(to: prompt, generating: FittingInsight.self)
        return response.content
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
            trend = "rising (\(String(format: "+%.1f%%", priceChange30dPercent)) over 30 days)"
        } else if priceChange30dPercent < -5 {
            trend = "falling (\(String(format: "%.1f%%", priceChange30dPercent)) over 30 days)"
        } else {
            trend = "stable (\(String(format: "%.1f%%", priceChange30dPercent)) over 30 days)"
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
        Spread: \(String(format: "%.1f%%", spreadPercent))
        Active orders: \(sellOrderCount) sell, \(buyOrderCount) buy
        5-day average daily volume: \(avgDailyVolume > 0 ? "\(avgDailyVolume) units" : "unknown")
        30-day price trend: \(trend)
        \(priceLine)
        """

        let session = LanguageModelSession(
            instructions: "You are a concise EVE Online market analyst. Assess this item's price trend, liquidity, and spread, then give one actionable trading suggestion. Use correct EVE Online market terminology (station trading, arbitrage, margin, buy/sell wall, etc.)."
        )
        let response = try await session.respond(to: prompt, generating: MarketInsight.self)
        return response.content
    }

    // MARK: Helpers

    private func formatSP(_ sp: Int) -> String {
        if sp >= 1_000_000 { return String(format: "%.1fM SP", Double(sp) / 1_000_000) }
        if sp >= 1_000 { return String(format: "%.0fK SP", Double(sp) / 1_000) }
        return "\(sp) SP"
    }
}
