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

extension FinancesView {
    // MARK:  Summary Cards

    var summaryCards: some View {
        HStack(spacing: 16) {
            summaryCard("Wallet Balance", value: totalWealth, color: .blue)
            summaryCard("Sell Orders", value: totalSellOrderValue, color: .green)
            summaryCard("Buy Orders (Escrow)", value: totalEscrow, color: .orange)
            summaryCard("Net Worth", value: netWorth, color: .purple)
        }
    }

    func summaryCard(_ title: String, value: Double, color: Color) -> some View {
        VStack(spacing: 6) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(EVEFormatters.formatISKShort(value))
                .font(.title3.bold().monospacedDigit())
                .foregroundStyle(color)
        }
        .frame(maxWidth: .infinity)
        .padding()
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
    }

    // MARK:  Today Summary

    var todayISK: (made: Double, spent: Double) {
        characterFinances.flatMap(\.journal).todayISKSummary
    }

    var todaySummary: some View {
        let daily = todayISK
        let net = daily.made - daily.spent
        return VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text("Today")
                    .font(.subheadline.bold())
                Spacer()
                Text("Resets at local midnight")
                    .font(.system(size: 9))
                    .foregroundStyle(.tertiary)
            }
            HStack(spacing: 16) {
                VStack(spacing: 2) {
                    Text("Made")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(EVEFormatters.formatISKShort(daily.made))
                        .font(.title3.bold().monospacedDigit())
                        .foregroundStyle(.green)
                }
                .frame(maxWidth: .infinity)
                .padding(10)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))

                VStack(spacing: 2) {
                    Text("Spent")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(EVEFormatters.formatISKShort(daily.spent))
                        .font(.title3.bold().monospacedDigit())
                        .foregroundStyle(.red)
                }
                .frame(maxWidth: .infinity)
                .padding(10)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))

                VStack(spacing: 2) {
                    Text("Net")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text((net >= 0 ? "+" : "") + EVEFormatters.formatISKShort(net))
                        .font(.title3.bold().monospacedDigit())
                        .foregroundStyle(net >= 0 ? .green : .red)
                }
                .frame(maxWidth: .infinity)
                .padding(10)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
            }
        }
        .padding(10)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
    }

    // MARK:  Wealth Distribution

    var wealthCategoryData: [WealthCategory] {
        [
            WealthCategory(name: "Assets", value: totalAssetValue, color: .purple),
            WealthCategory(name: "Sell Orders", value: totalSellOrderValue, color: .green),
            WealthCategory(name: "Escrow", value: totalEscrow, color: .orange),
            WealthCategory(name: "Wallet", value: totalWealth, color: .blue),
        ].filter { $0.value > 0 }
    }

    var wealthDistribution: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Wealth Distribution")
                .font(.subheadline.bold())

            let categories = wealthCategoryData
            if categories.isEmpty {
                Text("No wealth data")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 60, alignment: .center)
            } else {
                HStack(alignment: .top, spacing: 16) {
                    Chart(categories) { cat in
                        SectorMark(
                            angle: .value("ISK", cat.value),
                            innerRadius: .ratio(0.55),
                            angularInset: 2
                        )
                        .foregroundStyle(cat.color)
                        .cornerRadius(4)
                    }
                    .chartLegend(.hidden)
                    .frame(width: 100, height: 100)

                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(categories) { cat in
                            HStack(spacing: 6) {
                                Circle()
                                    .fill(cat.color)
                                    .frame(width: 7, height: 7)
                                Text(cat.name)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                if cat.name == "Assets" && isLoadingAssets {
                                    ProgressView()
                                        .scaleEffect(0.4)
                                        .frame(width: 10, height: 10)
                                }
                                Spacer()
                                VStack(alignment: .trailing, spacing: 0) {
                                    Text(EVEFormatters.formatISKShort(cat.value))
                                        .font(.caption2.bold().monospacedDigit())
                                        .foregroundStyle(cat.color)
                                    if netWorth > 0 {
                                        Text((cat.value / netWorth).formatted(.percent.precision(.fractionLength(1))))
                                            .font(.system(size: 9))
                                            .foregroundStyle(.secondary)
                                    }
                                }
                            }
                        }

                        if isLoadingAssets && totalAssetValue == 0 {
                            HStack(spacing: 4) {
                                ProgressView().scaleEffect(0.5)
                                Text("Valuing assets...")
                                    .font(.system(size: 9))
                                    .foregroundStyle(.tertiary)
                            }
                        }

                        Text("Asset values estimated using current market average prices")
                            .font(.system(size: 9))
                            .foregroundStyle(.tertiary)
                            .padding(.top, 1)
                    }
                }
            }
        }
        .padding(10)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
    }

    // MARK:  Character Detail

    @ViewBuilder
    func characterDetail(_ finance: CharacterFinanceData) -> some View {
        // Balance header with sparkline
        balanceHeader(finance)

        // AI Insight card (macOS 26+, when enabled in Settings)
        if #available(macOS 26.0, *), IntelligenceService.isSupported {
            FinanceAIInsightCard(finance: finance, netWorth: netWorth)
        }

        // Tab content
        Picker("View", selection: $selectedTab) {
            Text("Journal (\(finance.journal.count))").tag(0)
            Text("Breakdown").tag(4)
            Text("Transactions (\(finance.transactions.count))").tag(1)
            Text("Market Orders (\(finance.marketOrders.count))").tag(2)
            Text("Loyalty Points (\(finance.loyaltyPoints.count))").tag(3)
        }
        .pickerStyle(.segmented)
        .frame(maxWidth: 640)

        switch selectedTab {
        case 0: journalSection(finance.journal)
        case 4: breakdownSection(finance.journal)
        case 1: transactionSection(finance.transactions)
        case 2: marketOrdersSection(finance.marketOrders)
        case 3: loyaltyPointsSection(finance.loyaltyPoints)
        default: EmptyView()
        }
    }

    func balanceHeader(_ finance: CharacterFinanceData) -> some View {
        HStack(spacing: 20) {
            CachedAsyncImage(url: EVEImageURL.characterPortrait(finance.characterID, size: 256)) { image in
                image.resizable()
            } placeholder: {
                RoundedRectangle(cornerRadius: 8).fill(.quaternary)
            }
            .frame(width: 64, height: 64)
            .clipShape(RoundedRectangle(cornerRadius: 8))

            VStack(alignment: .leading, spacing: 4) {
                Text(finance.characterName)
                    .font(.title3.bold())
                Text(EVEFormatters.formatISK(finance.balance))
                    .font(.title.bold().monospacedDigit())
                    .foregroundStyle(.blue)
            }

            Spacer()

            // Balance sparkline from journal
            if !finance.journal.isEmpty {
                balanceSparkline(finance.journal)
            }

            VStack(alignment: .trailing, spacing: 6) {
                Label("\(finance.marketOrders.filter { !($0.isBuyOrder ?? false) }.count) sell", systemImage: "arrow.up.circle.fill")
                    .font(.caption)
                    .foregroundStyle(.green)
                Label("\(finance.marketOrders.filter { $0.isBuyOrder ?? false }.count) buy", systemImage: "arrow.down.circle.fill")
                    .font(.caption)
                    .foregroundStyle(.orange)
                Label(EVEFormatters.formatISKShort(finance.totalEscrow), systemImage: "lock.fill")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
    }

    @ViewBuilder
    func balanceSparkline(_ journal: [ESIWalletJournalEntry]) -> some View {
        let points = journal.prefix(50).reversed().compactMap { entry -> BalancePoint? in
            guard let bal = entry.balance else { return nil }
            return BalancePoint(date: entry.date, balance: bal)
        }
        if points.count > 1 {
            Chart(points, id: \.date) { point in
                LineMark(x: .value("Date", point.date), y: .value("Balance", point.balance))
                    .foregroundStyle(.blue)
                AreaMark(x: .value("Date", point.date), y: .value("Balance", point.balance))
                    .foregroundStyle(.blue.opacity(0.1))
            }
            .chartXAxis(.hidden)
            .chartYAxis(.hidden)
            .frame(width: 220, height: 60)
        }
    }

}
