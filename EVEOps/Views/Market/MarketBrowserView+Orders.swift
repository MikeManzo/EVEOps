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

    func ordersTable(orders: [ResolvedOrder], isBuy: Bool) -> some View {
        let sortKey = isBuy ? buySortKey : sellSortKey
        let ascending = isBuy ? buySortAsc : sellSortAsc
        let sorted = sortedOrders(orders, key: sortKey, ascending: ascending)

        return VStack(alignment: .leading, spacing: 0) {
            // Sortable column headers
            HStack(spacing: 0) {
                sortableColumn("Price",    key: .price,     isBuy: isBuy, width: 120, alignment: .trailing)
                sortableColumn("Qty",      key: .quantity,  isBuy: isBuy, width: 80,  alignment: .trailing, leadingPad: 12)
                sortableColumn("Min",      key: .minVolume, isBuy: isBuy, width: 60,  alignment: .trailing, leadingPad: 12)
                sortableColumn("Location", key: .location,  isBuy: isBuy, width: nil, alignment: .leading,  leadingPad: 12)
                sortableColumn("Sec",      key: .security,  isBuy: isBuy, width: 36,  alignment: .center)
                sortableColumn("Jumps",    key: .jumps,     isBuy: isBuy, width: 48,  alignment: .center)
                if isBuy {
                    sortableColumn("Range", key: .range, isBuy: isBuy, width: 80, alignment: .leading, leadingPad: 8)
                }
            }
            .font(.caption.bold())
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(Color(NSColor.separatorColor).opacity(0.15))

            if sorted.isEmpty {
                Text("No \(isBuy ? "buy" : "sell") orders in this region")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 80)
                    .multilineTextAlignment(.center)
                    .padding()
            } else {
                LazyVStack(spacing: 0) {
                    ForEach(Array(sorted.enumerated()), id: \.element.id) { index, resolved in
                        orderRow(resolved, isBuy: isBuy, isEven: index % 2 == 0)
                            .contextMenu {
                                let destId = resolved.order.locationId
                                let name = resolved.locationName
                                Button {
                                    Task { await setWaypoint(destinationId: destId, clear: true) }
                                } label: {
                                    Label("Set Destination: \(name)", systemImage: "location.fill")
                                }
                                Button {
                                    Task { await setWaypoint(destinationId: destId, clear: false) }
                                } label: {
                                    Label("Add Waypoint: \(name)", systemImage: "plus.circle")
                                }
                            }
                        Divider()
                            .padding(.leading, 15)
                    }
                }
            }
        }
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    func sortableColumn(_ title: String, key: OrderSortKey, isBuy: Bool,
                                 width: CGFloat?, alignment: Alignment,
                                 leadingPad: CGFloat = 0) -> some View {
        let isActive = (isBuy ? buySortKey : sellSortKey) == key
        let asc      = isBuy ? buySortAsc : sellSortAsc
        return Button {
            if isBuy {
                if buySortKey == key { buySortAsc.toggle() } else { buySortKey = key; buySortAsc = true }
            } else {
                if sellSortKey == key { sellSortAsc.toggle() } else { sellSortKey = key; sellSortAsc = true }
            }
        } label: {
            HStack(spacing: 2) {
                Text(title)
                if isActive {
                    Image(systemName: asc ? "chevron.up" : "chevron.down")
                        .font(.system(size: 7, weight: .bold))
                }
            }
            .frame(minWidth: width, idealWidth: width, maxWidth: width ?? .infinity, alignment: alignment)
        }
        .buttonStyle(.plain)
        .foregroundStyle(isActive ? .primary : .secondary)
        .padding(.leading, leadingPad)
    }

    func sortedOrders(_ orders: [ResolvedOrder], key: OrderSortKey, ascending: Bool) -> [ResolvedOrder] {
        orders.sorted { a, b in
            let less: Bool
            switch key {
            case .price:     less = a.order.price < b.order.price
            case .quantity:  less = a.order.volumeRemain < b.order.volumeRemain
            case .minVolume: less = a.order.minVolume < b.order.minVolume
            case .location:  less = a.locationName.localizedCompare(b.locationName) == .orderedAscending
            case .security:  less = a.securityStatus < b.securityStatus
            case .jumps:
                switch (a.jumps, b.jumps) {
                case (.some(let aj), .some(let bj)): less = aj < bj
                case (.some, .none):                 less = true
                case (.none, .some):                 less = false
                case (.none, .none):                 less = false
                }
            case .range: less = rangeOrder(a.order.range) < rangeOrder(b.order.range)
            }
            return ascending ? less : !less
        }
    }

    func rangeOrder(_ range: String) -> Int {
        switch range {
        case "station":     return 0
        case "solarsystem": return 1
        case "1":           return 2
        case "2":           return 3
        case "3":           return 4
        case "4":           return 5
        case "5":           return 6
        case "10":          return 7
        case "20":          return 8
        case "30":          return 9
        case "40":          return 10
        case "region":      return 11
        default:            return 12
        }
    }

    func orderRow(_ resolved: ResolvedOrder, isBuy: Bool, isEven: Bool) -> some View {
        let order = resolved.order
        let priceColor: Color = isBuy ? .orange : .green
        let sec = resolved.securityStatus
        let fillRatio = CGFloat(order.volumeRemain) / CGFloat(max(1, order.volumeTotal))

        return HStack(spacing: 0) {
            // Left accent bar — green for sell, orange for buy
            Rectangle()
                .fill(priceColor.opacity(0.75))
                .frame(width: 3)

            HStack(spacing: 0) {
                Text(EVEFormatters.formatISK(order.price))
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(priceColor)
                    .frame(width: 120, alignment: .trailing)

                // Qty with volume fill bar
                VStack(alignment: .trailing, spacing: 2) {
                    Text(formatCount(order.volumeRemain))
                        .font(.subheadline.monospacedDigit())
                    Text("/ \(formatCount(order.volumeTotal))")
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.tertiary)
                    ZStack(alignment: .trailing) {
                        RoundedRectangle(cornerRadius: 1)
                            .fill(Color.primary.opacity(0.08))
                        RoundedRectangle(cornerRadius: 1)
                            .fill(priceColor.opacity(0.55))
                            .frame(width: 80 * fillRatio)
                    }
                    .frame(width: 80, height: 2)
                }
                .frame(width: 80, alignment: .trailing)
                .padding(.leading, 12)

                Text(formatCount(order.minVolume))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .frame(width: 60, alignment: .trailing)
                    .padding(.leading, 12)

                VStack(alignment: .leading, spacing: 1) {
                    Text(resolved.locationName)
                        .font(.subheadline)
                        .lineLimit(1)
                    Text(resolved.systemName)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.leading, 12)

                // Security status pill badge
                Text(String(format: "%.1f", max(0, sec)))
                    .font(.system(size: 9, weight: .bold).monospacedDigit())
                    .foregroundStyle(.white)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(securityColor(sec), in: Capsule())
                    .frame(width: 36, alignment: .center)

                // Jumps with colored proximity dot
                Group {
                    if let jumps = resolved.jumps {
                        HStack(spacing: 3) {
                            Circle()
                                .fill(jumps == 0 ? Color.green : jumps < 5 ? Color.yellow : Color.orange)
                                .frame(width: 5, height: 5)
                            Text(jumps == 0 ? "Here" : "\(jumps)")
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(jumps == 0 ? .green : jumps < 5 ? .primary : .secondary)
                        }
                    } else {
                        Text("—")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                }
                .frame(width: 48, alignment: .center)

                if isBuy {
                    Text(formatRange(order.range))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .frame(width: 80, alignment: .leading)
                        .padding(.leading, 8)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
        }
        .background(isEven ? Color.primary.opacity(0.03) : Color.clear)
    }

    // MARK:  Price History

    @ViewBuilder
    var priceHistoryView: some View {
        let history = filteredHistory
        let eveTeal = Color(red: 0.2, green: 0.75, blue: 0.8)
        let volumeColor = Color(red: 0.15, green: 0.55, blue: 0.4)
        let hoveredEntry = hoveredHistoryDate.flatMap { closestHistoryEntry(to: $0) }

        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 12) {
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
                .pickerStyle(.segmented)
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
                .frame(height: 270)
                .padding(12)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))

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
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
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
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.up").font(.system(size: 9)).foregroundStyle(.green)
                        Text(EVEFormatters.formatISKShort(entry.highest)).font(.caption2)
                    }
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.down").font(.system(size: 9)).foregroundStyle(.red)
                        Text(EVEFormatters.formatISKShort(entry.lowest)).font(.caption2)
                    }
                    HStack(spacing: 4) {
                        Image(systemName: "minus").font(.system(size: 9)).foregroundStyle(eveTeal)
                        Text(EVEFormatters.formatISKShort(entry.average)).font(.caption2).foregroundStyle(eveTeal)
                    }
                }
                Divider()
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 4) {
                        Image(systemName: "shippingbox").font(.system(size: 9)).foregroundStyle(.secondary)
                        Text(formatCount(entry.volume)).font(.caption2)
                    }
                    HStack(spacing: 4) {
                        Image(systemName: "list.bullet").font(.system(size: 9)).foregroundStyle(.secondary)
                        Text("\(entry.orderCount) orders").font(.caption2)
                    }
                }
            }
        }
        .padding(8)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 8))
        .shadow(color: .black.opacity(0.2), radius: 4, x: 0, y: 2)
    }

}
