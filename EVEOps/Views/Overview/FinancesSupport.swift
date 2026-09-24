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
import Charts
import FoundationModels


// MARK:  Data Models

struct CharacterFinanceData {
    let characterID: Int
    let characterName: String
    let corporationName: String
    let balance: Double
    let journal: [ESIWalletJournalEntry]
    let transactions: [ESIWalletTransaction]
    let marketOrders: [ESIMarketOrder]
    let loyaltyPoints: [ResolvedLoyaltyPoints]
    /// Estimated total asset value using ESI market average prices. Populated after initial load.
    var assetValue: Double = 0
    /// Non-nil when one or more ESI fields failed to fetch; some displayed data may be missing.
    var partialLoadWarning: String? = nil

    var totalEscrow: Double {
        marketOrders.filter { $0.isBuyOrder ?? false }.compactMap(\.escrow).reduce(0, +)
    }

    var totalSellOrderValue: Double {
        marketOrders.filter { !($0.isBuyOrder ?? false) }.reduce(0) { $0 + $1.price * Double($1.volumeRemain) }
    }

    var totalBuyOrderValue: Double {
        marketOrders.filter { $0.isBuyOrder ?? false }.reduce(0) { $0 + $1.price * Double($1.volumeRemain) }
    }
}

struct ResolvedLoyaltyPoints {
    let corporationId: Int
    let corporationName: String
    let loyaltyPoints: Int
}

struct BalancePoint {
    let date: Date
    let balance: Double
}

struct WealthCategory: Identifiable {
    let id = UUID()
    let name: String
    let value: Double
    let color: Color
}

// Mark:  Finance AI Insight Card

@available(macOS 26.0, *)
struct FinanceAIInsightCard: View {
    let finance: CharacterFinanceData
    let netWorth: Double

    @AppStorage("aiInsightsEnabled") private var aiInsightsEnabled = false
    @AppStorage("aiInsightFinances") private var aiInsightFinances = true

    private var model: SystemLanguageModel { .default }

    var body: some View {
        if aiInsightsEnabled && aiInsightFinances, case .available = model.availability {
            AIInsightCard(
                loadingMessage: "Analyzing finances\u{2026}",
                taskID: finance.characterID,
                generate: generate
            ) { (insight: FinanceInsight) in
                StandardInsightBody(summary: insight.summary, suggestion: insight.suggestion)
            }
        }
    }

    private func generate() async throws -> FinanceInsight {
        // Sort by raw value on main actor, then format before crossing actor boundary
        let grouped = Dictionary(grouping: finance.journal) { $0.refType }
        let topRefs = grouped.map { refType, entries in
            (name: refType.replacingOccurrences(of: "_", with: " ").capitalized,
             total: entries.compactMap(\.amount).reduce(0, +))
        }
        .sorted { abs($0.total) > abs($1.total) }
        .prefix(5)
        .map { (name: $0.name, totalFormatted: EVEFormatters.formatISKShort($0.total)) }

        return try await IntelligenceService.shared.analyzeFinances(
            characterName: finance.characterName,
            balanceFormatted: EVEFormatters.formatISKShort(finance.balance),
            netWorthFormatted: EVEFormatters.formatISKShort(netWorth),
            sellOrderCount: finance.marketOrders.filter { !($0.isBuyOrder ?? false) }.count,
            buyOrderCount: finance.marketOrders.filter { $0.isBuyOrder ?? false }.count,
            topRefTypes: topRefs
        )
    }
}

// MARK:  Wallet Category Colours

extension WalletCategory {
    var color: Color {
        switch self {
        case .bountiesMissions: return .green
        case .market:           return .blue
        case .industry:         return .orange
        case .contracts:        return .purple
        case .planetary:        return .mint
        case .insurance:        return .teal
        case .corporation:      return .indigo
        case .feesTaxes:        return .red
        case .transfers:        return .cyan
        case .other:            return .gray
        }
    }
}

/// Wallet-balance sparkline with a hover crosshair: move the pointer across it to read the
/// balance at any journal entry.
struct BalanceSparkline: View {
    let points: [BalancePoint]
    let tint: Color

    @State private var hoveredDate: Date?

    private var hoveredPoint: BalancePoint? {
        guard let hoveredDate else { return nil }
        return points.min { abs($0.date.timeIntervalSince(hoveredDate)) < abs($1.date.timeIntervalSince(hoveredDate)) }
    }

    var body: some View {
        Chart {
            ForEach(points, id: \.date) { point in
                AreaMark(x: .value("Date", point.date), y: .value("Balance", point.balance))
                    .foregroundStyle(.eveAreaFill(tint))
                    .interpolationMethod(.monotone)
                LineMark(x: .value("Date", point.date), y: .value("Balance", point.balance))
                    .foregroundStyle(tint)
                    .lineStyle(StrokeStyle(lineWidth: 1.5, lineCap: .round))
                    .interpolationMethod(.monotone)
            }
            if let hovered = hoveredPoint {
                RuleMark(x: .value("Date", hovered.date))
                    .foregroundStyle(.secondary.opacity(0.5))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 2]))
                    .annotation(position: .top, spacing: 2, overflowResolution: .init(x: .fit(to: .chart), y: .fit(to: .chart))) {
                        EVEChartCallout(
                            title: hovered.date.formatted(date: .abbreviated, time: .shortened),
                            value: EVEFormatters.formatISKShort(hovered.balance),
                            tint: tint
                        )
                    }
                PointMark(x: .value("Date", hovered.date), y: .value("Balance", hovered.balance))
                    .foregroundStyle(tint)
                    .symbolSize(28)
            }
        }
        .chartXAxis(.hidden)
        .chartYAxis(.hidden)
        .chartXSelection(value: $hoveredDate)
        .accessibilityLabel("Wallet balance history")
    }
}

/// One day's ISK flow as a diverging bar: spending grows left (red) from a center line,
/// income grows right (green), both on the week's shared scale — so the rows read as a
/// small chart of the week rather than a column of numbers.
struct DayFlowBar: View {
    let made: Double
    let spent: Double
    let scale: Double

    var body: some View {
        GeometryReader { geo in
            let half = geo.size.width / 2
            let madeWidth = half * min(made / scale, 1)
            let spentWidth = half * min(spent / scale, 1)
            ZStack {
                Capsule().fill(Color.primary.opacity(0.05))
                HStack(spacing: 0) {
                    ZStack(alignment: .trailing) {
                        Color.clear
                        if spentWidth > 0 {
                            Capsule().fill(.red.opacity(0.75)).frame(width: max(spentWidth, 2))
                        }
                    }
                    ZStack(alignment: .leading) {
                        Color.clear
                        if madeWidth > 0 {
                            Capsule().fill(.green.opacity(0.75)).frame(width: max(madeWidth, 2))
                        }
                    }
                }
                Rectangle().fill(.secondary.opacity(0.4)).frame(width: 1)
            }
        }
        .frame(height: 6)
        .frame(minWidth: 60)
        .accessibilityHidden(true)
    }
}

/// Background trend line for the Net Worth summary card.
struct NetWorthSparkline: View {
    let points: [NetWorthHistory.Point]
    let tint: Color

    var body: some View {
        let low = points.map(\.netWorth).min() ?? 0
        let high = points.map(\.netWorth).max() ?? 1
        Chart(points) { point in
            AreaMark(x: .value("Day", point.date), y: .value("Net Worth", point.netWorth))
                .foregroundStyle(.eveAreaFill(tint))
                .interpolationMethod(.monotone)
            LineMark(x: .value("Day", point.date), y: .value("Net Worth", point.netWorth))
                .foregroundStyle(tint.opacity(0.7))
                .lineStyle(StrokeStyle(lineWidth: 1.2))
                .interpolationMethod(.monotone)
        }
        // Scale to the range, not from zero — a flat-looking line hides real movement.
        .chartYScale(domain: (low * 0.995)...(max(high, low + 1) * 1.005))
        .chartXAxis(.hidden)
        .chartYAxis(.hidden)
        .accessibilityHidden(true)
    }
}

/// Net worth over time from locally recorded daily snapshots, with a range picker and a
/// hover crosshair. Explains itself while history is still accumulating.
struct NetWorthHistoryCard: View {
    let characterID: Int
    let tint: Color

    private enum Range: Int, CaseIterable, Identifiable {
        case month = 30, quarter = 90, year = 365, all = 0
        var id: Int { rawValue }
        var title: LocalizedStringKey {
            switch self {
            case .month: "30D"
            case .quarter: "90D"
            case .year: "1Y"
            case .all: "All"
            }
        }
    }

    @AppStorage("finances.historyRange") private var rangeRaw = Range.quarter.rawValue
    @State private var hoveredDate: Date?

    private var range: Range { Range(rawValue: rangeRaw) ?? .quarter }

    private var points: [NetWorthHistory.Point] {
        NetWorthHistory.shared.points(characterID: characterID, days: range == .all ? nil : range.rawValue)
    }

    private var hoveredPoint: NetWorthHistory.Point? {
        guard let hoveredDate else { return nil }
        return points.min { abs($0.date.timeIntervalSince(hoveredDate)) < abs($1.date.timeIntervalSince(hoveredDate)) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: EVESpacing.md) {
            HStack {
                Text("Net Worth History")
                    .font(.subheadline.bold())
                Spacer()
                Picker("Range", selection: $rangeRaw) {
                    ForEach(Range.allCases) { Text($0.title).tag($0.rawValue) }
                }
                .labelsHidden()
                .eveSegmentedPicker()
                .fixedSize()
            }

            if points.count < 2 {
                Label("History builds up from one snapshot a day while you use Finances — check back tomorrow for a trend.",
                      systemImage: "chart.line.uptrend.xyaxis")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 80)
            } else {
                chart.frame(height: 160)
            }
        }
        .padding(EVESpacing.md + 2)
        .eveCard()
    }

    private var chart: some View {
        let low = points.map(\.netWorth).min() ?? 0
        let high = points.map(\.netWorth).max() ?? 1
        return Chart {
            ForEach(points) { point in
                AreaMark(x: .value("Day", point.date), y: .value("Net Worth", point.netWorth))
                    .foregroundStyle(.eveAreaFill(tint))
                    .interpolationMethod(.monotone)
                LineMark(x: .value("Day", point.date), y: .value("Net Worth", point.netWorth))
                    .foregroundStyle(tint)
                    .lineStyle(StrokeStyle(lineWidth: 1.8, lineCap: .round))
                    .interpolationMethod(.monotone)
            }
            if let hovered = hoveredPoint {
                RuleMark(x: .value("Day", hovered.date))
                    .foregroundStyle(.secondary.opacity(0.5))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 2]))
                    .annotation(position: .top, spacing: 2, overflowResolution: .init(x: .fit(to: .chart), y: .fit(to: .chart))) {
                        EVEChartCallout(
                            title: hovered.date.formatted(date: .abbreviated, time: .omitted),
                            value: EVEFormatters.formatISKShort(hovered.netWorth),
                            tint: tint
                        )
                    }
                PointMark(x: .value("Day", hovered.date), y: .value("Net Worth", hovered.netWorth))
                    .foregroundStyle(tint)
                    .symbolSize(30)
            }
        }
        .chartYScale(domain: (low * 0.98)...(max(high, low + 1) * 1.02))
        .eveISKYAxis()
        .eveDateXAxis()
        .chartXSelection(value: $hoveredDate)
        .accessibilityLabel("Net worth history")
    }
}
