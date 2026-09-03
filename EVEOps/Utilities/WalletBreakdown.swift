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

/// Buckets ESI wallet-journal `ref_type` values into a handful of human categories
/// so a character's income and spending can be summarised without a per-ref-type wall.
enum WalletCategory: String, CaseIterable, Sendable {
    case bountiesMissions
    case market
    case industry
    case contracts
    case planetary
    case insurance
    case corporation
    case feesTaxes
    case transfers
    case other

    var label: String {
        switch self {
        case .bountiesMissions: return "Bounties & Missions"
        case .market:           return "Market"
        case .industry:         return "Industry"
        case .contracts:        return "Contracts"
        case .planetary:        return "Planetary"
        case .insurance:        return "Insurance"
        case .corporation:      return "Corporation"
        case .feesTaxes:        return "Fees & Taxes"
        case .transfers:        return "Transfers"
        case .other:            return "Other"
        }
    }

    static func categorize(_ refType: String) -> WalletCategory {
        switch refType {
        case "bounty_prizes", "bounty_prize", "bounty_prizes_tax",
             "agent_mission_reward", "agent_mission_time_bonus_reward",
             "agent_mission_reward_corporation_tax", "agent_mission_time_bonus_reward_corporation_tax",
             "agent_mission_collateral_paid", "agent_mission_collateral_refunded",
             "corporate_reward_payout", "project_discovery_reward", "project_discovery_tax",
             "milestone_reward_payment", "daily_challenge_reward":
            return .bountiesMissions

        case "market_transaction", "market_escrow", "market_fine_paid",
             "transaction_tax", "brokers_fee", "market_provider_tax",
             "acceleration_gate_fee":
            return .market

        case "industry_job_tax", "manufacturing", "researching_technology",
             "researching_time_productivity", "researching_material_productivity",
             "copying", "reaction", "reprocessing_tax", "jump_clone_activation_fee",
             "jump_clone_installation_fee":
            return .industry

        case "contract_price", "contract_reward", "contract_collateral",
             "contract_collateral_refund", "contract_collateral_payment",
             "contract_collateral_deposited_corp", "contract_brokers_fee",
             "contract_brokers_fee_corp", "contract_sales_tax", "contract_deposit",
             "contract_deposit_refund", "contract_deposit_corp", "contract_deposit_sales_tax",
             "contract_reward_deposited", "contract_reward_deposited_corp",
             "contract_reward_refund", "contract_price_payment_corp":
            return .contracts

        case "planetary_import_tax", "planetary_export_tax", "planetary_construction":
            return .planetary

        case "insurance":
            return .insurance

        case "corporation_account_withdrawal", "corporation_dividend_payment",
             "corporation_payment", "corporation_registration_fee", "corporation_logo_change_cost",
             "office_rental_fee", "office_fee_refund", "war_fee", "war_fee_surrender",
             "alliance_maintainance_fee", "alliance_registration_fee", "sovereignty_bill",
             "infrastructure_hub_maintenance", "structure_gate_jump":
            return .corporation

        case "player_donation", "player_trading", "corporation_bonus", "gm_cash_transfer",
             "external_trade_freeze", "external_trade_thaw", "external_trade_delivery":
            return .transfers

        case "skill_purchase", "asset_safety_recovery_tax", "clone_activation",
             "clone_transfer", "docking_fee", "cspa", "cspaofflinerefund",
             "contraband_fine", "unknown", "reaction_bill", "resource_wars_reward",
             "opportunity_reward", "ess_escrow_transfer", "kill_right_fee",
             "medal_creation", "medal_issued", "bureau_import", "bureau_export",
             "release_of_impounded_property", "flux_ticket_sale", "flux_payout",
             "flux_tax", "flux_ticket_repayment", "datacore_fee", "redeemable_skill",
             "expert_system_activation_fee":
            return .feesTaxes

        default:
            return .other
        }
    }
}

struct WalletCategorySummary: Identifiable, Sendable {
    let category: WalletCategory
    /// Sum of positive amounts.
    let income: Double
    /// Magnitude of negative amounts (always >= 0).
    let expense: Double
    let count: Int

    var net: Double { income - expense }
    var gross: Double { income + expense }
    var id: String { category.rawValue }
}

/// Aggregated income/expense picture derived from a wallet journal slice.
struct WalletBreakdown: Sendable {
    let totalIncome: Double
    let totalExpense: Double
    /// Non-empty categories, sorted by gross activity descending.
    let categories: [WalletCategorySummary]
    let entryCount: Int
    let earliest: Date?
    let latest: Date?

    var net: Double { totalIncome - totalExpense }

    init(journal: [ESIWalletJournalEntry]) {
        var income = [WalletCategory: Double]()
        var expense = [WalletCategory: Double]()
        var counts = [WalletCategory: Int]()
        var totalIn = 0.0
        var totalOut = 0.0
        var minDate: Date?
        var maxDate: Date?

        for entry in journal {
            if minDate == nil || entry.date < minDate! { minDate = entry.date }
            if maxDate == nil || entry.date > maxDate! { maxDate = entry.date }

            guard let amount = entry.amount, amount != 0 else { continue }
            let cat = WalletCategory.categorize(entry.refType)
            counts[cat, default: 0] += 1
            if amount > 0 {
                income[cat, default: 0] += amount
                totalIn += amount
            } else {
                expense[cat, default: 0] += -amount
                totalOut += -amount
            }
        }

        totalIncome = totalIn
        totalExpense = totalOut
        entryCount = journal.count
        earliest = minDate
        latest = maxDate

        categories = WalletCategory.allCases.compactMap { cat -> WalletCategorySummary? in
            let inc = income[cat] ?? 0
            let exp = expense[cat] ?? 0
            guard inc != 0 || exp != 0 else { return nil }
            return WalletCategorySummary(category: cat, income: inc, expense: exp, count: counts[cat] ?? 0)
        }
        .sorted { $0.gross > $1.gross }
    }
}
