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
    @Guide(description: "A specific EVE Online skill to train, formatted as 'Skill Name to Level X' (e.g. 'Caldari Cruiser to Level V')")
    var skill: String

    @Guide(description: "One sentence explaining why this skill is valuable for this character")
    var rationale: String
}

@available(macOS 26.0, *)
@Generable(description: "Skill training recommendations for an EVE Online character based on their existing trained skills")
struct SkillTrainingRecommendation: Sendable {
    @Guide(description: "Two to three sentence description of this character's evident EVE Online playstyle and strengths based on their trained skills")
    var playstyleSummary: String

    @Guide(description: "Five skill recommendations in priority order, from most to least impactful for this character's development", .count(5))
    var recommendations: [SkillRecommendation]
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
        notableSkills: [String]
    ) async throws -> SkillTrainingRecommendation {
        let groupLines = topGroups
            .map { g -> String in
                let maxedNote = g.maxedCount > 0 ? ", \(g.maxedCount) at L5" : ""
                return "  \(g.name): \(g.spFormatted), \(g.skillCount) skills\(maxedNote)"
            }
            .joined(separator: "\n")

        let skillList = notableSkills.isEmpty ? "none" : notableSkills.joined(separator: ", ")

        let prompt = """
        EVE Online character: \(characterName)
        Total Skill Points: \(formatSP(totalSP))
        Top skill areas by SP:
        \(groupLines)
        High-trained skills (L4 and L5): \(skillList)
        """

        let session = LanguageModelSession(
            instructions: "You are a concise EVE Online skill advisor. Analyze this character's training history to identify their playstyle, then recommend the 5 most impactful skills they should train next, in priority order. Be specific and practical."
        )
        let response = try await session.respond(to: prompt, generating: SkillTrainingRecommendation.self)
        return response.content
    }

    // MARK: Helpers

    private func formatSP(_ sp: Int) -> String {
        if sp >= 1_000_000 { return String(format: "%.1fM SP", Double(sp) / 1_000_000) }
        if sp >= 1_000 { return String(format: "%.0fK SP", Double(sp) / 1_000) }
        return "\(sp) SP"
    }
}
