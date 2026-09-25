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
            // #7: Net Worth is the headline figure of this screen — elevated so it reads
            // as primary next to the three secondary stat tiles beside it.
            netWorthCard
        }
    }

    /// The screen's headline figure, with its recorded trend: a 30-day sparkline and the
    /// week-over-week change once enough daily snapshots exist.
    var netWorthCard: some View {
        let characterID = selectedFinance?.characterID
        let history = characterID.map { NetWorthHistory.shared.points(characterID: $0, days: 30) } ?? []
        let weekChange = characterID.flatMap { NetWorthHistory.shared.change(characterID: $0, overDays: 7) }
        return VStack(spacing: 6) {
            Text("Net Worth")
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(EVEFormatters.formatISKShort(netWorth))
                .font(.eveStatCompact)
                .foregroundStyle(eveAmountStyle(netWorth, palette.accent))
                .eveNumeric(netWorth)
            if let weekChange {
                Text("\(weekChange >= 0 ? "▲" : "▼") \(abs(weekChange).formatted(.percent.precision(.fractionLength(1)))) this week")
                    .font(.eveMicro.monospacedDigit())
                    .foregroundStyle(weekChange >= 0 ? .green : .red)
            }
        }
        .frame(maxWidth: .infinity)
        .padding()
        .background(alignment: .bottom) {
            if history.count > 1 {
                NetWorthSparkline(points: history, tint: palette.accent)
                    .frame(height: 30)
                    .padding(.horizontal, EVESpacing.md)
                    .padding(.bottom, EVESpacing.xs)
                    .opacity(0.8)
                    .allowsHitTesting(false)
            }
        }
        .eveElevatedCard()
    }

    func summaryCard(_ title: String, value: Double, color: Color, isPrimary: Bool = false) -> some View {
        let card = VStack(spacing: 6) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(EVEFormatters.formatISKShort(value))
                .font(.eveStatCompact)
                .foregroundStyle(eveAmountStyle(value, color))
                .eveNumeric(value)
        }
        .frame(maxWidth: .infinity)
        .padding()

        return Group {
            if isPrimary {
                card.eveElevatedCard()
            } else {
                card.eveCard()
            }
        }
    }

    // MARK:  Today Summary

    var todayISK: (made: Double, spent: Double) {
        characterFinances.flatMap(\.journal).todayISKSummary
    }

    var last7DaysISK: [(date: Date, made: Double, spent: Double)] {
        characterFinances.flatMap(\.journal).dailyISKSummaries(precedingDays: 7)
    }

    /// Every wallet-journal entry dated since local midnight, across all loaded characters.
    var todaysJournalEntries: [ESIWalletJournalEntry] {
        let start = Calendar.current.startOfDay(for: Date())
        return characterFinances.flatMap(\.journal).filter { $0.date >= start }
    }

    var todaySummary: some View {
        HStack(alignment: .top, spacing: 16) {
            todayColumn
                .frame(maxWidth: .infinity, alignment: .topLeading)
            last7DaysColumn
                .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .padding(10)
        .eveCard()
    }

    // MARK:  Today column

    private var todayColumn: some View {
        let daily = todayISK
        let net = daily.made - daily.spent
        let sevenDay = last7DaysISK
        let avgNet = sevenDay.isEmpty
            ? 0
            : sevenDay.reduce(0.0) { $0 + ($1.made - $1.spent) } / Double(sevenDay.count)
        return VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text("Today")
                    .font(.subheadline.bold())
                Spacer()
                Text("Resets at local midnight")
                    .font(.eveMicro)
                    .foregroundStyle(.tertiary)
            }
            iskStatCard("Made", value: daily.made, color: .green)
            iskStatCard("Spent", value: daily.spent, color: .red)
            iskStatCard("Net", value: net, color: net >= 0 ? .green : .red, signed: true,
                        footnote: sevenDayComparison(today: net, average: avgNet))
            todayBalanceCard(net: net)
            if !todayCategoryRows.isEmpty {
                todayCategoryBreakdown
            }
            todayActivityCard
        }
    }

    private func iskStatCard(_ title: String, value: Double, color: Color,
                             signed: Bool = false, footnote: String? = nil) -> some View {
        VStack(spacing: 3) {
            HStack {
                Text(title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Text((signed && !EVEFormatters.isZeroISK(value) && value > 0 ? "+" : "") + EVEFormatters.formatISKShort(value))
                    .font(.eveStatCompact)
                    .foregroundStyle(eveAmountStyle(value, color))
            }
            if let footnote {
                Text(footnote)
                    .font(.eveMicro)
                    .foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity)
        .eveCard(cornerRadius: EVERadius.md)
    }

    /// "▲ 34% vs 7-day avg (…)" — nil when there is no meaningful 7-day baseline.
    private func sevenDayComparison(today: Double, average: Double) -> String? {
        guard abs(average) > 1 else { return nil }
        let delta = (today - average) / abs(average)
        let arrow = delta >= 0 ? "▲" : "▼"
        let pct = abs(delta).formatted(.percent.precision(.fractionLength(0)))
        return "\(arrow) \(pct) vs 7-day avg (\(EVEFormatters.formatISKShort(average)))"
    }

    // MARK:  Today column — wallet movement

    private func todayBalanceCard(net: Double) -> some View {
        let current = totalWealth
        let opening = current - net
        let up = net >= 0
        let fraction = opening > 1 ? min(abs(net) / opening, 1) : (net == 0 ? 0 : 1)
        return VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("Wallet Today")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Text(opening > 1
                     ? (up ? "▲ " : "▼ ") + (abs(net) / opening).formatted(.percent.precision(.fractionLength(2)))
                     : "—")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(net == 0 ? Color.secondary : (up ? .green : .red))
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(.quaternary)
                    Capsule()
                        .fill(up ? Color.green : Color.red)
                        .frame(width: max(2, geo.size.width * fraction))
                }
            }
            .frame(height: 5)
            HStack {
                Text("Open " + EVEFormatters.formatISKShort(opening))
                Spacer()
                Text("Now " + EVEFormatters.formatISKShort(current))
            }
            .font(.eveMicro.monospacedDigit())
            .foregroundStyle(.tertiary)
        }
        .padding(10)
        .frame(maxWidth: .infinity)
        .eveCard(cornerRadius: EVERadius.md)
    }

    // MARK:  Today column — category breakdown

    private var todayCategoryRows: [WalletCategorySummary] {
        Array(WalletBreakdown(journal: todaysJournalEntries).categories.prefix(4))
    }

    private var todayCategoryBreakdown: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text("By Category")
                .font(.caption)
                .foregroundStyle(.secondary)
            ForEach(todayCategoryRows) { row in
                HStack(spacing: 6) {
                    Text(row.category.label)
                        .font(.caption2)
                        .lineLimit(1)
                    Spacer(minLength: 4)
                    if row.income > 0 {
                        Text("+" + EVEFormatters.formatISKShort(row.income))
                            .foregroundStyle(.green)
                    }
                    if row.expense > 0 {
                        Text("-" + EVEFormatters.formatISKShort(row.expense))
                            .foregroundStyle(.red)
                    }
                }
                .font(.caption2.monospacedDigit())
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity)
        .eveCard(cornerRadius: EVERadius.md)
    }

    // MARK:  Today column — activity

    private var todayActivityCard: some View {
        let entries = todaysJournalEntries
        let count = entries.count
        let topIncome = entries.filter { ($0.amount ?? 0) > 0 }
            .max { ($0.amount ?? 0) < ($1.amount ?? 0) }
        let topExpense = entries.filter { ($0.amount ?? 0) < 0 }
            .min { ($0.amount ?? 0) < ($1.amount ?? 0) }
        return VStack(alignment: .leading, spacing: 5) {
            HStack {
                Text("Activity")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Text("\(count) \(count == 1 ? "entry" : "entries")")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            if let topIncome {
                activityLine(label: "Top in", entry: topIncome, color: .green)
            }
            if let topExpense {
                activityLine(label: "Top out", entry: topExpense, color: .red)
            }
            if count == 0 {
                Text("No wallet activity yet today")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity)
        .eveCard(cornerRadius: EVERadius.md)
    }

    private func activityLine(label: String, entry: ESIWalletJournalEntry, color: Color) -> some View {
        let amount = entry.amount ?? 0
        return HStack(spacing: 6) {
            VStack(alignment: .leading, spacing: 0) {
                Text(label)
                    .font(.eveMicro)
                    .foregroundStyle(.tertiary)
                Text(formatRefType(entry.refType))
                    .font(.caption2)
                    .lineLimit(1)
            }
            Spacer(minLength: 4)
            Text((amount >= 0 ? "+" : "-") + EVEFormatters.formatISKShort(abs(amount)))
                .font(.caption2.bold().monospacedDigit())
                .foregroundStyle(color)
        }
    }

    // MARK:  Last 7 days column

    private var last7DaysColumn: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text("Last 7 Days")
                    .font(.subheadline.bold())
                Spacer()
                HStack(spacing: 0) {
                    Text("Made")
                        .frame(width: 64, alignment: .trailing)
                    Text("Spent")
                        .frame(width: 64, alignment: .trailing)
                    Text("Net")
                        .frame(width: 64, alignment: .trailing)
                }
                .font(.eveMicro)
                .foregroundStyle(.tertiary)
            }
            let days = last7DaysISK
            let scale = max(days.map { max($0.made, $0.spent) }.max() ?? 0, 1)
            VStack(spacing: 0) {
                ForEach(Array(days.enumerated()), id: \.offset) { index, day in
                    if index > 0 { Divider() }
                    daySummaryRow(day, scale: scale)
                }
            }
            .padding(.vertical, 4)
            .padding(.horizontal, 10)
            .eveCard(cornerRadius: EVERadius.md)
        }
    }

    private func daySummaryRow(_ day: (date: Date, made: Double, spent: Double), scale: Double) -> some View {
        let net = day.made - day.spent
        return HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 0) {
                Text(day.date, format: .dateTime.weekday(.abbreviated))
                    .font(.caption.bold())
                Text(day.date, format: .dateTime.month(.abbreviated).day())
                    .font(.eveMicro)
                    .foregroundStyle(.secondary)
            }
            .frame(width: 44, alignment: .leading)
            DayFlowBar(made: day.made, spent: day.spent, scale: scale)
                .padding(.horizontal, EVESpacing.md)
            Text(EVEFormatters.formatISKShort(day.made))
                .foregroundStyle(day.made > 0 ? .green : .secondary)
                .frame(width: 64, alignment: .trailing)
            Text(EVEFormatters.formatISKShort(day.spent))
                .foregroundStyle(day.spent > 0 ? .red : .secondary)
                .frame(width: 64, alignment: .trailing)
            Text((net > 0 && !EVEFormatters.isZeroISK(net) ? "+" : "") + EVEFormatters.formatISKShort(net))
                .foregroundStyle(net > 0 ? .green : (net < 0 ? .red : .secondary))
                .frame(width: 64, alignment: .trailing)
        }
        .font(.caption.monospacedDigit())
        .padding(.vertical, 6)
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
                HStack(alignment: .center, spacing: EVESpacing.xxl) {
                    Chart(categories) { cat in
                        SectorMark(
                            angle: .value("ISK", cat.value),
                            innerRadius: .ratio(0.62),
                            angularInset: 1.5
                        )
                        .foregroundStyle(cat.color)
                        .cornerRadius(EVERadius.xs)
                    }
                    .chartLegend(.hidden)
                    .chartBackground { _ in
                        VStack(spacing: 0) {
                            Text("Total")
                                .font(.eveMicro)
                                .foregroundStyle(.secondary)
                            Text(EVEFormatters.formatISKShort(netWorth).replacingOccurrences(of: " ISK", with: ""))
                                .font(.eveRowTitle.monospacedDigit())
                        }
                    }
                    .frame(width: 112, height: 112)

                    VStack(alignment: .leading, spacing: EVESpacing.md) {
                        Grid(alignment: .leading, horizontalSpacing: EVESpacing.lg, verticalSpacing: EVESpacing.sm) {
                            ForEach(categories) { cat in
                                GridRow {
                                    HStack(spacing: EVESpacing.sm) {
                                        Circle().fill(cat.color).frame(width: 8, height: 8)
                                        Text(cat.name).font(.callout)
                                        if cat.name == "Assets" && isLoadingAssets {
                                            ProgressView().controlSize(.mini)
                                        }
                                    }
                                    Text(EVEFormatters.formatISKShort(cat.value))
                                        .font(.callout.weight(.semibold).monospacedDigit())
                                        .gridColumnAlignment(.trailing)
                                    Text(netWorth > 0 ? (cat.value / netWorth).formatted(.percent.precision(.fractionLength(1))) : "—")
                                        .font(.caption.monospacedDigit())
                                        .foregroundStyle(.secondary)
                                        .gridColumnAlignment(.trailing)
                                    EVEProgressBar(value: netWorth > 0 ? cat.value / netWorth : 0, tint: cat.color, height: 4)
                                        .frame(width: 120)
                                }
                            }
                        }

                        if isLoadingAssets && totalAssetValue == 0 {
                            HStack(spacing: 4) {
                                ProgressView().controlSize(.mini)
                                Text("Valuing assets...")
                                    .font(.eveMicro)
                                    .foregroundStyle(.tertiary)
                            }
                        }

                        Text("Asset values estimated using current market average prices")
                            .font(.eveMicro)
                            .foregroundStyle(.tertiary)
                    }
                    .fixedSize(horizontal: true, vertical: false)

                    Spacer(minLength: 0)
                }
                .padding(.vertical, EVESpacing.xs)
            }
        }
        .padding(10)
        .eveCard()
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
        .eveSegmentedPicker()
        .frame(maxWidth: 640)

        switch selectedTab {
        case 0: WalletJournalView(journal: finance.journal)
        case 4: breakdownSection(finance.journal)
        case 1: WalletTransactionsTable(transactions: finance.transactions, typeNames: typeNames)
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
                RoundedRectangle(cornerRadius: EVERadius.md).fill(.quaternary)
            }
            .frame(width: 64, height: 64)
            .clipShape(RoundedRectangle(cornerRadius: EVERadius.md))

            VStack(alignment: .leading, spacing: 4) {
                Text(finance.characterName)
                    .font(.title3.bold())
                Text(EVEFormatters.formatISK(finance.balance))
                    .font(.eveHeroStat)
                    .foregroundStyle(.blue)
                    .eveNumeric(finance.balance)
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
        .eveCard()
    }

    @ViewBuilder
    func balanceSparkline(_ journal: [ESIWalletJournalEntry]) -> some View {
        let points = journal.prefix(50).reversed().compactMap { entry -> BalancePoint? in
            guard let bal = entry.balance else { return nil }
            return BalancePoint(date: entry.date, balance: bal)
        }
        if points.count > 1 {
            BalanceSparkline(points: Array(points), tint: palette.accent)
                .frame(width: 220, height: 60)
        }
    }

}
