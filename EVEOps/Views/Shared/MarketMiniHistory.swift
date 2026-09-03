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

/// Compact price-trend card backed by `MarketHistoryService`. Drop it anywhere a
/// single item's recent market behaviour adds context — asset detail, fitting
/// shop, loyalty store. Collapses to nothing when the item has no market history.
struct MarketMiniHistory: View {
    let typeId: Int
    var regionId: Int = MarketHistoryService.jitaRegionId
    /// Optional "now" price used for the vs-median badge (e.g. Jita sell).
    var currentPrice: Double? = nil
    var regionLabel: String = "Jita"

    @State private var series: MarketHistoryService.Series?
    @State private var days = 90
    @State private var isLoading = true
    @State private var failed = false

    private let lineColor = Color(red: 0.2, green: 0.75, blue: 0.8)

    private var visible: [MarketHistoryService.Point] {
        guard let series else { return [] }
        guard let cutoff = Calendar.current.date(byAdding: .day, value: -days, to: Date()) else { return series.points }
        return series.points.filter { $0.date >= cutoff }
    }

    var body: some View {
        Group {
            if failed || (!isLoading && (series?.points.isEmpty ?? true)) {
                EmptyView()
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    header
                    if isLoading {
                        ProgressView()
                            .controlSize(.small)
                            .frame(maxWidth: .infinity, minHeight: 96)
                    } else if visible.count < 2 {
                        Text("Not enough recent history")
                            .font(.caption).foregroundStyle(.tertiary)
                            .frame(maxWidth: .infinity, minHeight: 60, alignment: .center)
                    } else {
                        chart
                        statsRow
                    }
                }
            }
        }
        .task(id: "\(typeId)-\(regionId)") { await load() }
    }

    // MARK: Header

    private var header: some View {
        HStack(spacing: 8) {
            Label("Price Trend (\(regionLabel))", systemImage: "chart.xyaxis.line")
                .font(.subheadline.bold())
                .foregroundStyle(.secondary)

            Spacer()

            medianBadge

            Picker("", selection: $days) {
                Text("30d").tag(30)
                Text("90d").tag(90)
                Text("1y").tag(365)
            }
            .labelsHidden()
            .pickerStyle(.segmented)
            .controlSize(.mini)
            .frame(width: 118)
        }
    }

    @ViewBuilder
    private var medianBadge: some View {
        if let cur = currentPrice, cur > 0, let med = series?.median(days: 30), med > 0 {
            let delta = (cur - med) / med
            let pct = String(format: "%+.1f%%", delta * 100)
            let color: Color = delta > 0.02 ? .red : (delta < -0.02 ? .green : .secondary)
            Text("\(pct) vs 30d")
                .font(.caption2.monospacedDigit())
                .foregroundStyle(color)
                .help("Current price vs the 30-day median (\(EVEFormatters.formatISKShort(med))). Above the norm shows red, below shows green.")
        }
    }

    // MARK: Chart

    private var chart: some View {
        let med = series?.median(days: days)
        return Chart {
            ForEach(visible) { p in
                AreaMark(x: .value("Date", p.date), y: .value("Price", p.average))
                    .foregroundStyle(.linearGradient(
                        colors: [lineColor.opacity(0.22), lineColor.opacity(0.02)],
                        startPoint: .top, endPoint: .bottom))
                LineMark(x: .value("Date", p.date), y: .value("Price", p.average))
                    .foregroundStyle(lineColor)
                    .interpolationMethod(.catmullRom)
            }
            if let med {
                RuleMark(y: .value("30d median", med))
                    .foregroundStyle(.secondary.opacity(0.5))
                    .lineStyle(StrokeStyle(lineWidth: 0.5, dash: [3, 2]))
            }
        }
        .chartYAxis {
            AxisMarks { value in
                AxisGridLine()
                AxisValueLabel {
                    if let d = value.as(Double.self) {
                        Text(d.formatted(.number.notation(.compactName)))
                            .font(.system(size: 9))
                    }
                }
            }
        }
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: 3)) { _ in
                AxisGridLine()
                AxisValueLabel(format: .dateTime.month(.abbreviated).day())
            }
        }
        .frame(height: 96)
    }

    // MARK: Stats

    @ViewBuilder
    private var statsRow: some View {
        let lows = visible.map(\.lowest)
        let highs = visible.map(\.highest)
        HStack(spacing: 0) {
            stat("30d median", series?.median(days: 30).map { EVEFormatters.formatISKShort($0) } ?? "—")
            Divider().frame(height: 26)
            stat("Vol/day", series?.averageVolume(days: 30).map { $0.formatted(.number.notation(.compactName)) } ?? "—")
            Divider().frame(height: 26)
            stat("\(days)d range",
                 (lows.min().map { EVEFormatters.formatISKShort($0) } ?? "—")
                 + " – "
                 + (highs.max().map { EVEFormatters.formatISKShort($0) } ?? "—"))
        }
    }

    private func stat(_ label: String, _ value: String) -> some View {
        VStack(spacing: 2) {
            Text(label).font(.caption2).foregroundStyle(.tertiary)
            Text(value).font(.caption.monospacedDigit())
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: Load

    private func load() async {
        isLoading = true
        failed = false
        do {
            series = try await MarketHistoryService.shared.series(typeId: typeId, regionId: regionId)
        } catch {
            failed = true
        }
        isLoading = false
    }
}
