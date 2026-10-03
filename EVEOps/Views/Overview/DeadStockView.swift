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

// MARK:  Row

/// A dead-stock line flattened for the table's sortable columns.
private struct DeadStockRow: Identifiable {
    let line: DeadStockLine
    let liquidity: DeadStockEngine.Liquidity?
    let place: String
    /// Days untouched; -1 without history, `.infinity` for "since before tracking".
    let untouchedDays: Double

    var id: Int { line.typeID }
    var name: String { line.name }
    var quantity: Int { line.quantity }
    var value: Double { line.value }
    var listValue: Double { line.listValue }
    var liquidityRank: Int { liquidity?.rawValue ?? 9 }

    var copyText: String { "\(line.name)\t\(line.quantity)" }
}

// MARK:  Main View

/// "What am I sitting on that I'll never use?" — every pilot's hangars, minus ships and
/// what's in them, blueprints, industry materials, and every part a saved fitting needs.
/// What's left is priced at Jita, with how fast it would sell and how long it's sat.
struct DeadStockView: View {
    @Environment(AccountManager.self) private var accountManager
    @Environment(DashboardPrefetcher.self) private var prefetcher
    @Environment(ThemeManager.self) private var themeManager

    @AppStorage("deadStock.minValue") private var minValue: Double = 1_000_000
    @AppStorage("deadStock.untouchedDays") private var untouchedFilter: Double = 0

    @State private var search = ""
    @State private var pilotFilter: Int = 0
    @State private var selection = Set<DeadStockRow.ID>()
    @State private var inspected: Int?
    @State private var sortOrder: [KeyPathComparator<DeadStockRow>] = [KeyPathComparator(\.value, order: .reverse)]

    private var service: DeadStockService { .shared }
    private var palette: EVEPalette { themeManager.palette }

    var body: some View {
        content
            .eveScreenHeader("Dead Stock", subtitle: subtitle, section: .deadStock) {
                if let progress = service.progress {
                    HStack(spacing: EVESpacing.xs) {
                        ProgressView().controlSize(.mini)
                        Text(verbatim: progress)
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
                FreshnessIndicator(isLoading: service.isLoading) { await load(force: true) }
            }
            .eveInspector(item: $inspected, minWidth: 320, idealWidth: 360, maxWidth: 420) { typeID in
                if let line = service.report?.lines.first(where: { $0.typeID == typeID }) {
                    DeadStockDetailPane(line: line, places: service.places, accounts: accountManager.accounts,
                                        dailyVolume: service.dailyVolume[typeID])
                }
            }
            .task(id: accountManager.accounts.map(\.characterID)) {
                if service.report == nil { await load() }
            }
            .onChange(of: AppRouter.shared.refreshTick) { _, _ in Task { await load(force: true) } }
            .onChange(of: selection) { _, new in
                if new.count == 1 { inspected = new.first }
            }
    }

    private func load(force: Bool = false) async {
        if prefetcher.characterData.isEmpty { await prefetcher.prefetchAll(accountManager: accountManager) }
        await service.refresh(accountManager: accountManager, prefetcher: prefetcher, force: force)
    }

    private var subtitle: Text? {
        guard let report = service.report, !report.lines.isEmpty else { return nil }
        return Text("\(EVEFormatters.formatISKShort(report.totalValue)) across \(report.lines.count) item types")
    }

    // MARK: Rows

    private func rows(now: Date) -> [DeadStockRow] {
        guard let report = service.report else { return [] }
        let needle = search.trimmingCharacters(in: .whitespacesAndNewlines)
        return report.lines.compactMap { line -> DeadStockRow? in
            guard line.value >= minValue || (minValue == 0) else { return nil }
            guard pilotFilter == 0 || line.characterIDs.contains(pilotFilter) else { return nil }
            guard needle.isEmpty || line.name.localizedCaseInsensitiveContains(needle) else { return nil }
            let days: Double
            if let since = line.untouchedSince {
                days = since == .distantPast ? .infinity : now.timeIntervalSince(since) / 86400
            } else {
                days = -1
            }
            if untouchedFilter > 0, days < untouchedFilter { return nil }
            let places = line.placeIDs
            var place = places.first.map { service.places[$0]?.name ?? String(localized: "Location #\($0)") } ?? "—"
            if places.count > 1 { place += String(localized: " +\(places.count - 1)") }
            return DeadStockRow(
                line: line,
                liquidity: DeadStockEngine.liquidity(quantity: line.quantity, averageDailyVolume: service.dailyVolume[line.typeID]),
                place: place,
                untouchedDays: days
            )
        }
        .sorted(using: sortOrder)
    }

    // MARK: Content

    @ViewBuilder
    private var content: some View {
        if let report = service.report {
            let shown = rows(now: .now)
            VStack(alignment: .leading, spacing: EVESpacing.lg) {
                if let error = service.error { banner(Text(error)) }
                if !service.skippedPilots.isEmpty {
                    banner(Text("Couldn’t read assets for \(service.skippedPilots.formatted(.list(type: .and))) — they aren’t counted."))
                }
                totals(report)
                trackingNote
                filterBar(shown)
                if shown.isEmpty {
                    EVEEmptyState("Nothing Matches", systemImage: "line.3.horizontal.decrease.circle",
                                  message: Text("Lower the minimum value or clear the filters.")) {
                        Button("Clear Filters") {
                            search = ""
                            pilotFilter = 0
                            minValue = 0
                            untouchedFilter = 0
                        }
                    }
                    .frame(maxHeight: .infinity)
                } else {
                    table(shown)
                        .clipShape(RoundedRectangle(cornerRadius: EVERadius.xl))
                }
            }
            .padding()
        } else if service.isLoading || service.error == nil {
            LoadingSkeleton()
        } else {
            EVEEmptyState(title: Text("Something Went Wrong"), systemImage: "exclamationmark.triangle",
                          message: Text(service.error ?? ""), tint: .orange) {
                Button("Try Again", systemImage: "arrow.clockwise") { Task { await load(force: true) } }
                    .buttonStyle(.borderedProminent)
                    .tint(palette.accent)
            }
        }
    }

    private func banner(_ text: Text) -> some View {
        Label { text } icon: { Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange) }
            .font(.caption)
            .padding(EVESpacing.md)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.orange.opacity(EVEOpacity.faint), in: RoundedRectangle(cornerRadius: EVERadius.md))
    }

    @ViewBuilder
    private var trackingNote: some View {
        if let since = service.trackingSince, Date.now.timeIntervalSince(since) < 30 * 86400 {
            Label {
                Text("EVEOps started noting when items arrive on \(since.formatted(date: .abbreviated, time: .omitted)). “Untouched” ages build from there; anything older shows as “Before tracking”.")
            } icon: {
                Image(systemName: "clock.badge.questionmark").foregroundStyle(.secondary)
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
    }

    // MARK: Totals

    private func totals(_ report: DeadStockReport) -> some View {
        let places = report.valueByPlace
        let top = places.first
        return InsightStatRow {
            InsightStat(label: String(localized: "Sell Now"), value: EVEFormatters.formatISKShort(report.totalValue),
                        detail: String(localized: "to Jita buy orders"), tint: .green)
            InsightStat(label: String(localized: "If Listed"), value: EVEFormatters.formatISKShort(report.totalListValue),
                        detail: String(localized: "at the lowest Jita sell order"), tint: palette.accent)
            InsightStat(label: String(localized: "Item Types"), value: "\(report.lines.count)",
                        detail: String(localized: "in \(places.count) locations · \(report.fitCount) fits kept aside"))
            InsightStat(label: String(localized: "Biggest Pile"),
                        value: top.map { EVEFormatters.formatISKShort($0.value) } ?? "—",
                        detail: top.map { service.places[$0.placeID]?.name ?? String(localized: "Location #\($0.placeID)") }
                            ?? String(localized: "Nothing to sell"),
                        tint: .orange)
        }
    }

    // MARK: Filters

    private func filterBar(_ shown: [DeadStockRow]) -> some View {
        HStack(spacing: EVESpacing.md) {
            EVESearchField("Search items", text: $search)
                .frame(maxWidth: 260)
            EVEMenuPicker("Minimum value", selection: $minValue, options: [
                EVEMenuOption(0.0, "Any value"),
                EVEMenuOption(100_000.0, verbatim: String(localized: "≥ 100K")),
                EVEMenuOption(1_000_000.0, verbatim: String(localized: "≥ 1M")),
                EVEMenuOption(10_000_000.0, verbatim: String(localized: "≥ 10M")),
                EVEMenuOption(100_000_000.0, verbatim: String(localized: "≥ 100M")),
            ])
            EVEMenuPicker("Untouched", selection: $untouchedFilter, options: [
                EVEMenuOption(0.0, "Any age"),
                EVEMenuOption(7.0, "Untouched 7d+"),
                EVEMenuOption(30.0, "Untouched 30d+"),
                EVEMenuOption(90.0, "Untouched 90d+"),
            ])
            if accountManager.accounts.count > 1 {
                EVEMenuPicker("Pilot", selection: $pilotFilter, options:
                    [EVEMenuOption(0, "All pilots")] + accountManager.accounts.map {
                        EVEMenuOption($0.characterID, verbatim: $0.characterName, dividerBefore: $0.characterID == accountManager.accounts.first?.characterID)
                    })
            }
            Spacer()
            let picked = shown.filter { selection.contains($0.id) }
            let toCopy = picked.isEmpty ? shown : picked
            Button {
                InsightClipboard.copy(DeadStockEngine.clipboardText(toCopy.map(\.line)),
                                      toast: String(localized: "Copied \(toCopy.count) items for appraisal"))
            } label: {
                Label(picked.isEmpty ? "Copy All for Appraisal" : "Copy Selected", systemImage: "doc.on.clipboard")
            }
            .help("Copies “Name ⇥ Quantity” lines — paste into Janice, Evepraisal or EVE’s multi-sell.")
        }
    }

    // MARK: Table

    private func table(_ rows: [DeadStockRow]) -> some View {
        Table(rows, selection: $selection, sortOrder: $sortOrder) {
            TableColumn("Item", value: \.name) { row in
                HStack(spacing: EVESpacing.md) {
                    CachedAsyncImage(url: EVEImageURL.typeIcon(row.line.typeID, size: 64)) { image in
                        image.resizable()
                    } placeholder: {
                        RoundedRectangle(cornerRadius: EVERadius.xs).fill(.quaternary)
                    }
                    .frame(width: 20, height: 20)
                    .clipShape(RoundedRectangle(cornerRadius: EVERadius.xs))
                    Text(row.name).lineLimit(1).eveTruncationHelp(row.name)
                }
                .eveContextMenu(.item(typeID: row.line.typeID, name: row.name))
            }
            .width(min: 180, ideal: 260)

            TableColumn("Qty", value: \.quantity) { row in
                Text(row.quantity.formatted())
                    .monospacedDigit()
                    .frame(maxWidth: .infinity, alignment: .trailing)
                    .help(row.line.reserved > 0
                          ? Text("\(row.line.owned.formatted()) owned · \(row.line.reserved.formatted()) kept for fittings")
                          : Text("\(row.line.owned.formatted()) owned"))
            }
            .width(min: 50, ideal: 70)

            TableColumn("Sell Now", value: \.value) { row in
                Text(row.line.price == nil ? "—" : EVEFormatters.formatISKShort(row.value))
                    .fontWeight(.semibold)
                    .monospacedDigit()
                    .foregroundStyle(row.value > 0 ? Color.green : .secondary)
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
            .width(min: 70, ideal: 90)

            TableColumn("If Listed", value: \.listValue) { row in
                Text(row.line.price == nil ? "—" : EVEFormatters.formatISKShort(row.listValue))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
            .width(min: 70, ideal: 90)

            TableColumn("Liquidity", value: \.liquidityRank) { row in
                if let liquidity = row.liquidity {
                    EVEChip(Text(liquidity.title), tint: liquidity.color)
                        .help(liquidity.help)
                } else {
                    Text(verbatim: "—").foregroundStyle(.tertiary)
                }
            }
            .width(min: 70, ideal: 84)

            TableColumn("Untouched", value: \.untouchedDays) { row in
                Text(untouchedLabel(row.untouchedDays))
                    .monospacedDigit()
                    .foregroundStyle(row.untouchedDays >= 30 ? Color.orange : .secondary)
            }
            .width(min: 70, ideal: 100)

            TableColumn("Where", value: \.place) { row in
                Text(verbatim: row.place)
                    .lineLimit(1)
                    .foregroundStyle(.secondary)
                    .eveTruncationHelp(row.place)
            }
            .width(min: 140, ideal: 220)
        }
        .tableStyle(.inset(alternatesRowBackgrounds: true))
        .copyable(rows.filter { selection.contains($0.id) }.map(\.copyText))
    }

    private func untouchedLabel(_ days: Double) -> String {
        if days < 0 { return "—" }
        if days == .infinity { return String(localized: "Before tracking") }
        if days < 1 { return String(localized: "Today") }
        return String(localized: "\(Int(days))d")
    }
}

extension DeadStockEngine.Liquidity {
    var title: LocalizedStringKey {
        switch self {
        case .high:   "Liquid"
        case .medium: "Steady"
        case .low:    "Slow"
        case .none:   "No trades"
        }
    }

    var help: Text {
        switch self {
        case .high:   Text("Under a tenth of a day’s Jita volume — sells without moving the price.")
        case .medium: Text("Up to a day’s Jita volume.")
        case .low:    Text("More than a day’s Jita volume — dumping it all would push the price down.")
        case .none:   Text("Nothing traded in Jita over the last 30 days.")
        }
    }

    var color: Color {
        switch self {
        case .high:   .green
        case .medium: .teal
        case .low:    .orange
        case .none:   .red
        }
    }
}

// MARK:  Detail

private struct DeadStockDetailPane: View {
    let line: DeadStockLine
    let places: [Int: ReadyRoomPlace]
    let accounts: [StoredAccount]
    let dailyVolume: Double?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: EVESpacing.lg) {
                HStack(spacing: EVESpacing.md) {
                    CachedAsyncImage(url: EVEImageURL.typeIcon(line.typeID, size: 64)) { image in
                        image.resizable()
                    } placeholder: {
                        RoundedRectangle(cornerRadius: EVERadius.sm).fill(.quaternary)
                    }
                    .frame(width: 40, height: 40)
                    .clipShape(RoundedRectangle(cornerRadius: EVERadius.sm))
                    VStack(alignment: .leading, spacing: 2) {
                        Text(verbatim: line.name).font(.eveRowTitle)
                        Text("\(line.quantity.formatted()) dead of \(line.owned.formatted()) owned")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Grid(alignment: .leading, horizontalSpacing: EVESpacing.lg, verticalSpacing: EVESpacing.sm) {
                    row("Sell now", line.price.map { EVEFormatters.formatISK($0.buy * Double(line.quantity)) } ?? "—")
                    row("If listed", line.price.map { EVEFormatters.formatISK($0.sell * Double(line.quantity)) } ?? "—")
                    row("Kept for fittings", line.reserved.formatted())
                    if let volume = line.volume {
                        row("Volume", "\(volume.formatted(.number.precision(.fractionLength(0...1)))) m³")
                    }
                    if let dailyVolume {
                        row("Jita daily volume", dailyVolume.formatted(.number.precision(.fractionLength(0))))
                    }
                }
                .font(.caption)

                Text("Where it sits")
                    .font(.eveCaptionBold)
                    .foregroundStyle(.secondary)
                ForEach(grouped, id: \.key) { group in
                    VStack(alignment: .leading, spacing: EVESpacing.xs) {
                        Text(verbatim: places[group.key]?.name ?? String(localized: "Location #\(group.key)"))
                            .font(.eveCalloutSemibold)
                        if let system = places[group.key]?.systemName, let security = places[group.key]?.security {
                            Text(verbatim: "\(system) · \(security.formatted(.number.precision(.fractionLength(1))))")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        ForEach(group.value, id: \.itemID) { stack in
                            HStack {
                                PilotPortrait(characterID: stack.characterID, size: 16)
                                Text(verbatim: accounts.first { $0.characterID == stack.characterID }?.characterName ?? "")
                                    .font(.caption)
                                Spacer()
                                Text(stack.quantity.formatted())
                                    .font(.caption.monospacedDigit())
                            }
                        }
                    }
                    .padding(EVESpacing.md)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .eveCard(cornerRadius: EVERadius.md)
                }

                Button {
                    InsightClipboard.copy(DeadStockEngine.clipboardText([line]),
                                          toast: String(localized: "Copied \(line.name)"))
                } label: {
                    Label("Copy for Appraisal", systemImage: "doc.on.clipboard")
                }
            }
            .padding()
        }
    }

    private var grouped: [(key: Int, value: [DeadStockStack])] {
        Dictionary(grouping: line.stacks, by: \.placeID)
            .sorted { $0.value.reduce(0) { $0 + $1.quantity } > $1.value.reduce(0) { $0 + $1.quantity } }
    }

    private func row(_ label: LocalizedStringKey, _ value: String) -> some View {
        GridRow {
            Text(label).foregroundStyle(.secondary)
            Text(verbatim: value).monospacedDigit()
        }
    }
}
