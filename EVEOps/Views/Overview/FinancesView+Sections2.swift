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
    // MARK:  Journal

    func journalSection(_ journal: [ESIWalletJournalEntry]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            if journal.isEmpty {
                Text("No journal entries")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 100)
            } else {
                // Summary by ref type
                let grouped = Dictionary(grouping: journal) { $0.refType }
                let topTypes = grouped.sorted { a, b in
                    let aTotal = a.value.compactMap(\.amount).map(abs).reduce(0, +)
                    let bTotal = b.value.compactMap(\.amount).map(abs).reduce(0, +)
                    return aTotal > bTotal
                }.prefix(5)

                if !topTypes.isEmpty {
                    HStack(spacing: 12) {
                        ForEach(Array(topTypes), id: \.key) { refType, entries in
                            let total = entries.compactMap(\.amount).reduce(0, +)
                            VStack(spacing: 2) {
                                Text(formatRefType(refType))
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                                Text(EVEFormatters.formatISKShort(total))
                                    .font(.caption.bold().monospacedDigit())
                                    .foregroundStyle(total >= 0 ? .green : .red)
                                Text("\(entries.count)x")
                                    .font(.caption2)
                                    .foregroundStyle(.tertiary)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(8)
                            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
                        }
                    }
                }

                // Journal entries list
                LazyVStack(spacing: 1) {
                    ForEach(journal) { entry in
                        journalRow(entry)
                    }
                }
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
            }
        }
    }

    func journalRow(_ entry: ESIWalletJournalEntry) -> some View {
        HStack(spacing: 10) {
            Image(systemName: (entry.amount ?? 0) >= 0 ? "arrow.down.circle.fill" : "arrow.up.circle.fill")
                .foregroundStyle((entry.amount ?? 0) >= 0 ? .green : .red)
                .font(.title3)

            VStack(alignment: .leading, spacing: 2) {
                Text(formatRefType(entry.refType))
                    .font(.subheadline)
                if !entry.description.isEmpty {
                    Text(entry.description.strippingEVEMarkup)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                if let reason = entry.reason, !reason.isEmpty {
                    Text(reason)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 2) {
                if let amount = entry.amount {
                    Text((amount >= 0 ? "+" : "") + EVEFormatters.formatISKShort(amount))
                        .font(.subheadline.bold().monospacedDigit())
                        .foregroundStyle(amount >= 0 ? .green : .red)
                }
                if let balance = entry.balance {
                    Text(EVEFormatters.formatISKShort(balance))
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                Text(EVEFormatters.dateFormatter.string(from: entry.date))
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    // MARK:  Breakdown

    struct WalletFlowDatum: Identifiable {
        let flow: String          // "Income" or "Expenses"
        let categoryLabel: String
        let amount: Double
        var id: String { flow + "·" + categoryLabel }
    }

    @ViewBuilder
    func breakdownSection(_ journal: [ESIWalletJournalEntry]) -> some View {
        if journal.isEmpty {
            Text("No journal entries")
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, minHeight: 100)
        } else {
            let bd = WalletBreakdown(journal: journal)
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 12) {
                    breakdownStat("Income", bd.totalIncome, .green)
                    breakdownStat("Expenses", -bd.totalExpense, .red)
                    breakdownStat("Net", bd.net, bd.net >= 0 ? .green : .red)
                }

                if let earliest = bd.earliest, let latest = bd.latest {
                    Text("\(bd.entryCount) entries · \(EVEFormatters.dateFormatter.string(from: earliest)) – \(EVEFormatters.dateFormatter.string(from: latest))")
                        .font(.caption2).foregroundStyle(.tertiary)
                }

                let cats = bd.categories.map(\.category)
                Chart(flowData(bd)) { row in
                    BarMark(
                        x: .value("Flow", row.flow),
                        y: .value("ISK", row.amount)
                    )
                    .foregroundStyle(by: .value("Category", row.categoryLabel))
                }
                .chartForegroundStyleScale(domain: cats.map(\.label), range: cats.map(\.color))
                .chartYAxis {
                    AxisMarks { value in
                        AxisGridLine()
                        AxisValueLabel {
                            if let d = value.as(Double.self) {
                                Text(d.formatted(.number.notation(.compactName))).font(.caption2)
                            }
                        }
                    }
                }
                .chartLegend(position: .bottom, spacing: 8)
                .frame(height: 240)
                .padding(12)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))

                VStack(spacing: 1) {
                    ForEach(bd.categories) { summary in
                        breakdownRow(summary, maxGross: bd.categories.first?.gross ?? 1)
                    }
                }
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
            }
        }
    }

    func flowData(_ bd: WalletBreakdown) -> [WalletFlowDatum] {
        var rows: [WalletFlowDatum] = []
        for summary in bd.categories {
            if summary.income > 0 {
                rows.append(WalletFlowDatum(flow: "Income", categoryLabel: summary.category.label, amount: summary.income))
            }
            if summary.expense > 0 {
                rows.append(WalletFlowDatum(flow: "Expenses", categoryLabel: summary.category.label, amount: summary.expense))
            }
        }
        return rows
    }

    func breakdownStat(_ title: String, _ value: Double, _ color: Color) -> some View {
        VStack(spacing: 4) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Text(EVEFormatters.formatISKShort(value))
                .font(.title3.bold().monospacedDigit())
                .foregroundStyle(color)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
    }

    func breakdownRow(_ summary: WalletCategorySummary, maxGross: Double) -> some View {
        VStack(spacing: 4) {
            HStack(spacing: 8) {
                Circle().fill(summary.category.color).frame(width: 8, height: 8)
                Text(summary.category.label).font(.subheadline)
                Text("\(summary.count)x").font(.caption2).foregroundStyle(.tertiary)
                Spacer()
                Text((summary.net >= 0 ? "+" : "") + EVEFormatters.formatISKShort(summary.net))
                    .font(.subheadline.bold().monospacedDigit())
                    .foregroundStyle(summary.net >= 0 ? .green : .red)
            }
            HStack(spacing: 6) {
                GeometryReader { geo in
                    let frac = maxGross > 0 ? summary.gross / maxGross : 0
                    ZStack(alignment: .leading) {
                        Capsule().fill(.quaternary).frame(height: 4)
                        Capsule().fill(summary.category.color.opacity(0.8))
                            .frame(width: max(2, geo.size.width * frac), height: 4)
                    }
                }
                .frame(height: 4)
                Text("in \(EVEFormatters.formatISKShort(summary.income)) · out \(EVEFormatters.formatISKShort(summary.expense))")
                    .font(.caption2).foregroundStyle(.tertiary)
                    .fixedSize()
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    // MARK:  Transactions

    func transactionSection(_ transactions: [ESIWalletTransaction]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            if transactions.isEmpty {
                Text("No transactions")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 100)
            } else {
                // Summary
                let buyTotal = transactions.filter(\.isBuy).reduce(0.0) { $0 + $1.unitPrice * Double($1.quantity) }
                let sellTotal = transactions.filter { !$0.isBuy }.reduce(0.0) { $0 + $1.unitPrice * Double($1.quantity) }

                HStack(spacing: 16) {
                    VStack(spacing: 2) {
                        Text("Bought")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(EVEFormatters.formatISKShort(buyTotal))
                            .font(.subheadline.bold().monospacedDigit())
                            .foregroundStyle(.orange)
                        Text("\(transactions.filter(\.isBuy).count) orders")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(10)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))

                    VStack(spacing: 2) {
                        Text("Sold")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(EVEFormatters.formatISKShort(sellTotal))
                            .font(.subheadline.bold().monospacedDigit())
                            .foregroundStyle(.green)
                        Text("\(transactions.filter { !$0.isBuy }.count) orders")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(10)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))

                    VStack(spacing: 2) {
                        Text("Net")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        let net = sellTotal - buyTotal
                        Text(EVEFormatters.formatISKShort(net))
                            .font(.subheadline.bold().monospacedDigit())
                            .foregroundStyle(net >= 0 ? .green : .red)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(10)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
                }

                LazyVStack(spacing: 1) {
                    ForEach(transactions) { tx in
                        transactionRow(tx)
                    }
                }
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
            }
        }
    }

    func transactionRow(_ tx: ESIWalletTransaction) -> some View {
        HStack(spacing: 10) {
            CachedAsyncImage(url: EVEImageURL.typeIcon(tx.typeId, size: 64)) { image in
                image.resizable()
            } placeholder: {
                RoundedRectangle(cornerRadius: 4).fill(.quaternary)
            }
            .frame(width: 32, height: 32)
            .clipShape(RoundedRectangle(cornerRadius: 4))

            VStack(alignment: .leading, spacing: 2) {
                Text(typeNames[tx.typeId] ?? "Type #\(tx.typeId)")
                    .font(.subheadline)
                Text("\(tx.quantity)x @ \(EVEFormatters.formatISK(tx.unitPrice))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 2) {
                let total = tx.unitPrice * Double(tx.quantity)
                Text(EVEFormatters.formatISKShort(total))
                    .font(.subheadline.bold().monospacedDigit())
                    .foregroundStyle(tx.isBuy ? .red : .green)
                Text(tx.isBuy ? "Buy" : "Sell")
                    .font(.caption2)
                    .foregroundStyle(tx.isBuy ? .orange : .green)
                Text(EVEFormatters.dateFormatter.string(from: tx.date))
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    // MARK:  Market Orders

    func marketOrdersSection(_ orders: [ESIMarketOrder]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            if orders.isEmpty {
                Text("No active market orders")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 100)
            } else {
                let sellOrders = orders.filter { !($0.isBuyOrder ?? false) }
                let buyOrders = orders.filter { $0.isBuyOrder ?? false }

                // Summary
                HStack(spacing: 16) {
                    VStack(spacing: 2) {
                        Text("Sell Orders")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text("\(sellOrders.count)")
                            .font(.title3.bold())
                            .foregroundStyle(.green)
                        Text(EVEFormatters.formatISKShort(sellOrders.reduce(0) { $0 + $1.price * Double($1.volumeRemain) }))
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(10)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))

                    VStack(spacing: 2) {
                        Text("Buy Orders")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text("\(buyOrders.count)")
                            .font(.title3.bold())
                            .foregroundStyle(.orange)
                        Text(EVEFormatters.formatISKShort(buyOrders.reduce(0) { $0 + $1.price * Double($1.volumeRemain) }))
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(10)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))

                    VStack(spacing: 2) {
                        Text("In Escrow")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(EVEFormatters.formatISKShort(buyOrders.compactMap(\.escrow).reduce(0, +)))
                            .font(.title3.bold().monospacedDigit())
                            .foregroundStyle(.orange)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(10)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
                }

                // Order list
                if !sellOrders.isEmpty {
                    Text("Sell Orders")
                        .font(.subheadline.bold())
                        .padding(.top, 4)
                    LazyVStack(spacing: 1) {
                        ForEach(sellOrders) { order in
                            marketOrderRow(order)
                        }
                    }
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
                }

                if !buyOrders.isEmpty {
                    Text("Buy Orders")
                        .font(.subheadline.bold())
                        .padding(.top, 4)
                    LazyVStack(spacing: 1) {
                        ForEach(buyOrders) { order in
                            marketOrderRow(order)
                        }
                    }
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
                }
            }
        }
    }

    func marketOrderRow(_ order: ESIMarketOrder) -> some View {
        let isBuy = order.isBuyOrder ?? false
        return HStack(spacing: 10) {
            CachedAsyncImage(url: EVEImageURL.typeIcon(order.typeId, size: 64)) { image in
                image.resizable()
            } placeholder: {
                RoundedRectangle(cornerRadius: 4).fill(.quaternary)
            }
            .frame(width: 32, height: 32)
            .clipShape(RoundedRectangle(cornerRadius: 4))

            VStack(alignment: .leading, spacing: 2) {
                Text(typeNames[order.typeId] ?? "Type #\(order.typeId)")
                    .font(.subheadline)
                Text("\(order.volumeRemain)/\(order.volumeTotal) remaining")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                // Progress bar
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 2)
                            .fill(.quaternary)
                        RoundedRectangle(cornerRadius: 2)
                            .fill(isBuy ? .orange : .green)
                            .frame(width: geo.size.width * Double(order.volumeTotal - order.volumeRemain) / max(Double(order.volumeTotal), 1))
                    }
                }
                .frame(height: 4)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 2) {
                Text(EVEFormatters.formatISK(order.price))
                    .font(.subheadline.monospacedDigit())
                Text(EVEFormatters.formatISKShort(order.price * Double(order.volumeRemain)))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                Text("\(order.duration)d \u{2022} \(order.range)")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                Text("Issued: \(EVEFormatters.dateFormatter.string(from: order.issued))")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

}
