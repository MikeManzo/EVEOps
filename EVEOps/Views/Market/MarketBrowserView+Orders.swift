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

extension MarketBrowserView {
    // MARK:  Orders Table

    @ViewBuilder
    func ordersTable(orders: [ResolvedOrder], isBuy: Bool) -> some View {
        let sortOrder = isBuy ? $buySortOrder : $sellSortOrder
        let sorted = orders.sorted(using: sortOrder.wrappedValue)

        if sorted.isEmpty {
            EVEEmptyState(isBuy ? "No Buy Orders" : "No Sell Orders", systemImage: "cart",
                          message: Text("There are no \(isBuy ? "buy" : "sell") orders for this item in this region."))
                .frame(minHeight: 160)
                .eveCard()
        } else {
            let priceColor: Color = isBuy ? .orange : .green
            Table(sorted, selection: $selectedOrderIDs, sortOrder: sortOrder) {
                TableColumn("Price", value: \.price) { row in
                    Text(EVEFormatters.formatISK(row.price))
                        .monospacedDigit()
                        .fontWeight(.semibold)
                        .foregroundStyle(priceColor)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                }
                .width(min: 100, ideal: 130)

                TableColumn("Qty", value: \.quantity) { row in
                    quantityCell(row.order, tint: priceColor)
                }
                .width(min: 70, ideal: 90)

                TableColumn("Min", value: \.minVolume) { row in
                    Text(formatCount(row.minVolume))
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                }
                .width(min: 40, ideal: 56)

                TableColumn("Location", value: \.locationName) { row in
                    VStack(alignment: .leading, spacing: 1) {
                        Text(row.locationName)
                            .lineLimit(1)
                            .eveTruncationHelp(row.locationName)
                        Text(row.systemName)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .width(min: 180, ideal: 300)

                TableColumn("Sec", value: \.securityStatus) { row in
                    EVESecurityBadge(status: row.securityStatus, compact: true)
                        .frame(maxWidth: .infinity)
                }
                .width(48)

                TableColumn("Jumps", value: \.jumpsSortKey) { row in
                    jumpsCell(row.jumps)
                        .frame(maxWidth: .infinity)
                }
                .width(60)

                if isBuy {
                    TableColumn("Range", value: \.rangeRank) { row in
                        Text(formatRange(row.order.range))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    .width(min: 60, ideal: 80)
                }
            }
            .tableStyle(.inset(alternatesRowBackgrounds: true))
            // The order book lives inside the detail pane's scroll view, so the table
            // gets a height that fits its rows (capped) instead of scrolling a page
            // inside a page for a handful of orders.
            .frame(height: min(CGFloat(sorted.count) * 40 + 30, 520))
            .clipShape(RoundedRectangle(cornerRadius: EVERadius.xl))
            .contextMenu(forSelectionType: ResolvedOrder.ID.self) { ids in
                if let id = ids.first, let row = sorted.first(where: { $0.id == id }) {
                    let destId = row.order.locationId
                    Button("Set Destination: \(row.locationName)", systemImage: "location.fill") {
                        Task { await setWaypoint(destinationId: destId, clear: true) }
                    }
                    Button("Add Waypoint: \(row.locationName)", systemImage: "plus.circle") {
                        Task { await setWaypoint(destinationId: destId, clear: false) }
                    }
                    Divider()
                    Button("Copy", systemImage: "doc.on.doc") {
                        let text = sorted.filter { ids.contains($0.id) }.map(\.copyText).joined(separator: "\n")
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(text, forType: .string)
                    }
                }
            } primaryAction: { ids in
                guard ids.count == 1, let id = ids.first,
                      let row = sorted.first(where: { $0.id == id }) else { return }
                Task { await setWaypoint(destinationId: row.order.locationId, clear: true) }
            }
            .copyable(sorted.filter { selectedOrderIDs.contains($0.id) }.map(\.copyText))
        }
    }

    /// Remaining quantity over total, with a thin fill bar showing how much of the
    /// order is left.
    private func quantityCell(_ order: ESIRegionMarketOrder, tint: Color) -> some View {
        let fill = CGFloat(order.volumeRemain) / CGFloat(max(1, order.volumeTotal))
        return VStack(alignment: .trailing, spacing: EVESpacing.xxs) {
            Text(formatCount(order.volumeRemain))
                .monospacedDigit()
            Capsule()
                .fill(EVEFill.track)
                .overlay(alignment: .trailing) {
                    GeometryReader { geo in
                        Capsule()
                            .fill(tint.opacity(0.55))
                            .frame(width: geo.size.width * fill)
                            .frame(maxWidth: .infinity, alignment: .trailing)
                    }
                }
                .frame(height: 2)
        }
        .frame(maxWidth: .infinity, alignment: .trailing)
        .help("\(formatCount(order.volumeRemain)) of \(formatCount(order.volumeTotal)) remaining")
    }

    @ViewBuilder
    private func jumpsCell(_ jumps: Int?) -> some View {
        if let jumps {
            HStack(spacing: 3) {
                Circle()
                    .fill(jumps == 0 ? Color.green : jumps < 5 ? Color.yellow : Color.orange)
                    .frame(width: 5, height: 5)
                Text(jumps == 0 ? "Here" : "\(jumps)")
                    .monospacedDigit()
                    .foregroundStyle(jumps == 0 ? .green : jumps < 5 ? .primary : .secondary)
            }
        } else {
            Text("—").foregroundStyle(.tertiary)
        }
    }

    // MARK:  Price History

    @ViewBuilder
    var priceHistoryView: some View {
        let history = filteredHistory
        let eveTeal = palette.accent
        let volumeColor = Color(red: 0.15, green: 0.55, blue: 0.4)
        let hoveredEntry = hoveredHistoryDate.flatMap { closestHistoryEntry(to: $0) }

        VStack(alignment: .leading, spacing: EVESpacing.xl) {
            HStack(spacing: EVESpacing.lg) {
                Text("Price History")
                    .font(.headline)

                // Legend
                HStack(spacing: 10) {
                    legendItem(color: eveTeal, symbol: "line.diagonal", label: "Avg")
                    legendItem(color: eveTeal.opacity(0.5), symbol: "rectangle.fill", label: "Hi/Lo")
                    legendItem(color: volumeColor, symbol: "chart.bar.fill", label: "Vol")
                }
                .font(.caption2)
                .foregroundStyle(.secondary)

                Spacer()

                Picker(selection: $historyDays) {
                    Text("30d").tag(30)
                    Text("90d").tag(90)
                    Text("1y").tag(365)
                } label: {
                    EmptyView()
                }
                .labelsHidden()
                .eveSegmentedPicker()
                .frame(width: 130)
            }

            if history.isEmpty {
                Text("No price history available")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 200)
            } else {
                // ── Single unified chart (price + volume) ─────────────
                // Volume bars are plotted in a "virtual zone" below the price
                // data using the same ISK coordinate space. One x-axis means
                // the crosshair is always pixel-perfect across both datasets.
                let allPrices = history.flatMap { [$0.lowest, $0.highest] }
                let rawPMin   = allPrices.min() ?? 0
                let rawPMax   = allPrices.max() ?? 1
                let pSpan     = max(rawPMax - rawPMin, 1)
                let pMax      = rawPMax + pSpan * 0.04
                let pMin      = rawPMin - pSpan * 0.02
                // Volume zone: 28% of price span, placed below price data with a gap
                let volZone   = pSpan * 0.28
                let volBase   = pMin - volZone * 1.22   // gap = 22% of volZone
                let yMin      = volBase - volZone * 0.08
                let maxVol    = Double(history.map(\.volume).max() ?? 1)

                Chart {
                    // ── Volume bars (lower zone) ──────────────────────
                    ForEach(history) { entry in
                        if let date = parseHistoryDate(entry.date) {
                            let barTop = volBase + Double(entry.volume) / maxVol * volZone
                            BarMark(
                                x: .value("Date", date),
                                yStart: .value("VolBase", volBase),
                                yEnd: .value("VolTop", barTop)
                            )
                            .foregroundStyle(
                                hoveredEntry?.date == entry.date
                                    ? volumeColor
                                    : volumeColor.opacity(0.5)
                            )
                        }
                    }

                    // ── Thin separator between the two zones ──────────
                    RuleMark(y: .value("Sep", pMin - pSpan * 0.01))
                        .foregroundStyle(Color.secondary.opacity(0.18))
                        .lineStyle(StrokeStyle(lineWidth: 0.5))

                    // ── Price high/low range bands ─────────────────────
                    ForEach(history) { entry in
                        if let date = parseHistoryDate(entry.date) {
                            RectangleMark(
                                x: .value("Date", date),
                                yStart: .value("Low", entry.lowest),
                                yEnd: .value("High", entry.highest),
                                width: 4
                            )
                            .foregroundStyle(eveTeal.opacity(0.4))
                        }
                    }

                    // ── Average price: area fill then line on top ──────
                    ForEach(history) { entry in
                        if let date = parseHistoryDate(entry.date) {
                            AreaMark(
                                x: .value("Date", date),
                                yStart: .value("AreaFloor", pMin),
                                yEnd: .value("Average", entry.average)
                            )
                            .foregroundStyle(eveTeal.opacity(0.10))

                            LineMark(
                                x: .value("Date", date),
                                y: .value("Average", entry.average)
                            )
                            .foregroundStyle(eveTeal)
                            .lineStyle(StrokeStyle(lineWidth: 1.5))
                        }
                    }

                    // ── Hover crosshair + tooltip ─────────────────────
                    if let entry = hoveredEntry, let date = parseHistoryDate(entry.date) {
                        RuleMark(x: .value("Hover", date))
                            .foregroundStyle(Color.secondary.opacity(0.45))
                            .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 2]))
                            .annotation(
                                position: .top, spacing: 4,
                                overflowResolution: .init(x: .fit(to: .chart), y: .disabled)
                            ) {
                                historyTooltip(entry: entry, eveTeal: eveTeal)
                            }

                        PointMark(
                            x: .value("Date", date),
                            y: .value("Average", entry.average)
                        )
                        .foregroundStyle(eveTeal)
                        .symbolSize(36)
                    }
                }
                .chartYScale(domain: yMin...pMax)
                .chartYAxis {
                    // Only show grid lines + labels for the price zone
                    AxisMarks { value in
                        if let v = value.as(Double.self), v >= pMin {
                            AxisGridLine()
                            AxisValueLabel {
                                Text(EVEFormatters.formatISKShort(v)).font(.caption2)
                            }
                        }
                    }
                }
                .chartXSelection(value: $hoveredHistoryDate)
                .eveChartAccessibility(String(localized: "Average price"),
                                       points: history.compactMap { entry in
                                           parseHistoryDate(entry.date).map { ($0, entry.average) }
                                       })
                .frame(height: 270)
                .padding(EVESpacing.lg)
                .eveCard()

                // History summary stats
                if let last = history.last {
                    HStack(spacing: 0) {
                        statCard("5d Avg Vol", value: fiveDayAvgVolume(history), color: .primary)
                        Divider()
                        statCard("Last High", value: EVEFormatters.formatISKShort(last.highest), color: .green)
                        Divider()
                        statCard("Last Low", value: EVEFormatters.formatISKShort(last.lowest), color: .red)
                        Divider()
                        statCard("Last Avg", value: EVEFormatters.formatISKShort(last.average), color: .blue)
                        Divider()
                        statCard("Orders", value: "\(last.orderCount)", color: .secondary)
                    }
                    .eveCard()
                }
            }
        }
    }

    @ViewBuilder
    func historyTooltip(entry: ESIMarketHistory, eveTeal: Color) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(entry.date)
                .font(.caption2.bold())
                .foregroundStyle(.secondary)
            HStack(alignment: .top, spacing: EVESpacing.lg) {
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: EVESpacing.xs) {
                        Image(systemName: "arrow.up").font(.eveMicro).foregroundStyle(.green)
                        Text(EVEFormatters.formatISKShort(entry.highest)).font(.caption2)
                    }
                    HStack(spacing: EVESpacing.xs) {
                        Image(systemName: "arrow.down").font(.eveMicro).foregroundStyle(.red)
                        Text(EVEFormatters.formatISKShort(entry.lowest)).font(.caption2)
                    }
                    HStack(spacing: EVESpacing.xs) {
                        Image(systemName: "minus").font(.eveMicro).foregroundStyle(eveTeal)
                        Text(EVEFormatters.formatISKShort(entry.average)).font(.caption2).foregroundStyle(eveTeal)
                    }
                }
                Divider()
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: EVESpacing.xs) {
                        Image(systemName: "shippingbox").font(.eveMicro).foregroundStyle(.secondary)
                        Text(formatCount(entry.volume)).font(.caption2)
                    }
                    HStack(spacing: EVESpacing.xs) {
                        Image(systemName: "list.bullet").font(.eveMicro).foregroundStyle(.secondary)
                        Text("\(entry.orderCount) orders").font(.caption2)
                    }
                }
            }
        }
        .padding(EVESpacing.md)
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: EVERadius.md))
        .shadow(color: .black.opacity(0.2), radius: 4, x: 0, y: 2)
    }

}
