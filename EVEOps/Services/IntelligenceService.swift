
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

// MARK: Output Types
//
// FoundationModels' @Generable macro bakes a reference to
// `Generable.promptRepresentation` into the binary at compile time.
// That symbol was renamed between the macOS 26.0 SDK (used to build this
// binary) and macOS 26.5/26.6, causing a dyld abort on launch on all
// hardware. These types are kept as plain Swift structs so every caller
// continues to compile; the analyze* methods throw
// IntelligenceUnavailableError until the app is rebuilt against the
// current SDK.

struct FinanceInsight: Sendable {
    var summary: String
    var suggestion: String
}

struct SkillRecommendation: Sendable {
    var skillName: String
    var targetLevel: Int
    var rationale: String
}

struct SkillTrainingRecommendation: Sendable {
    var playstyleSummary: String
    var recommendations: [SkillRecommendation]
}

struct CombatInsight: Sendable {
    var summary: String
    var suggestion: String
}

struct IndustryInsight: Sendable {
    var summary: String
    var suggestion: String
}

struct AssetInsight: Sendable {
    var summary: String
    var suggestion: String
}

struct FittingInsight: Sendable {
    var roleAssessment: String
    var suggestion: String
}

struct MarketInsight: Sendable {
    var summary: String
    var suggestion: String
}

struct CloneInsight: Sendable {
    var setAssessment: String
    var recommendation: String
    var skillsNeeded: String
}

struct IntelligenceUnavailableError: LocalizedError {
    var errorDescription: String? {
        "Apple Intelligence insights are temporarily unavailable. A fix is in progress — please check for an app update."
    }
}

// MARK: Service

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
        throw IntelligenceUnavailableError()
    }

    // MARK: Trained Skills Analysis

    func analyzeTrainedSkills(
        characterName: String,
        totalSP: Int,
        topGroups: [(name: String, spFormatted: String, skillCount: Int, maxedCount: Int)],
        partialSkills: [(name: String, level: Int)],
        maxedSkills: [String]
    ) async throws -> SkillTrainingRecommendation {
        throw IntelligenceUnavailableError()
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
        throw IntelligenceUnavailableError()
    }

    // MARK: Industry Analysis

    func analyzeIndustry(
        characterName: String,
        totalJobs: Int,
        activeJobs: Int,
        activityBreakdown: [(activity: String, count: Int)],
        topBlueprints: [String]
    ) async throws -> IndustryInsight {
        throw IntelligenceUnavailableError()
    }

    // MARK: Asset Analysis

    func analyzeAssets(
        characterName: String,
        totalStacks: Int,
        locationCount: Int,
        topLocationsByCount: [(location: String, count: Int)],
        topItemsByQuantity: [(name: String, quantity: Int)]
    ) async throws -> AssetInsight {
        throw IntelligenceUnavailableError()
    }

    // MARK: Fitting Analysis

    func analyzeFitting(
        shipName: String,
        shipClass: String,
        slotModules: [(category: String, names: [String])]
    ) async throws -> FittingInsight {
        throw IntelligenceUnavailableError()
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
        throw IntelligenceUnavailableError()
    }

    // MARK: Clone / Implant Analysis

    func analyzeImplants(
        characterName: String,
        activeImplantNames: [String],
        jumpCloneImplantNames: [[String]],
        totalSP: Int,
        topSkillAreas: [(name: String, spFormatted: String)]
    ) async throws -> CloneInsight {
        throw IntelligenceUnavailableError()
    }
}
