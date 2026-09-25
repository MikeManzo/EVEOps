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
import AppKit

// MARK: - Presentation helpers

/// How a wallet journal entry is labelled and iconed. Categories (and their colors) come
/// from `WalletCategory`, the same grouping the Breakdown tab uses; the symbol is chosen
/// per ref type so a bounty, a mission reward and a donation look different at a glance.
nonisolated enum JournalEntryPresentation {
    static func title(_ refType: String) -> String {
        refType.replacingOccurrences(of: "_", with: " ").capitalized
    }

    static func symbol(_ refType: String) -> String {
        switch refType {
        case "bounty_prizes", "bounty_prize", "bounty_prizes_tax": return "scope"
        case let t where t.hasPrefix("agent_mission"):             return "person.text.rectangle"
        case "player_donation", "corporation_bonus":               return "gift"
        case "insurance":                                          return "checkmark.shield"
        case "market_escrow", "market_transaction":                return "cart"
        case "brokers_fee", "transaction_tax", "market_provider_tax": return "percent"
        case "daily_challenge_reward", "milestone_reward_payment",
             "corporate_reward_payout":                            return "rosette"
        case "project_discovery_reward":                           return "atom"
        default:
            switch WalletCategory.categorize(refType) {
            case .bountiesMissions: return "scope"
            case .market:           return "cart"
            case .industry:         return "hammer"
            case .contracts:        return "doc.text"
            case .planetary:        return "globe.americas"
            case .insurance:        return "checkmark.shield"
            case .corporation:      return "building.2"
            case .feesTaxes:        return "percent"
            case .transfers:        return "arrow.left.arrow.right"
            case .other:            return "circle.dotted"
            }
        }
    }

    /// Decodes a bounty entry's `reason` — ESI's raw "typeID: count,typeID: count" list of
    /// NPCs killed — into pairs. Nil when the reason isn't in that format.
    static func bountyKills(_ entry: ESIWalletJournalEntry) -> [(typeID: Int, count: Int)]? {
        guard entry.refType.hasPrefix("bounty_prize"),
              let reason = entry.reason, !reason.isEmpty else { return nil }
        var kills: [(typeID: Int, count: Int)] = []
        for pair in reason.split(separator: ",") {
            let parts = pair.split(separator: ":").map { $0.trimmingCharacters(in: .whitespaces) }
            guard parts.count == 2, let id = Int(parts[0]), let count = Int(parts[1]) else { return nil }
            kills.append((id, count))
        }
        return kills.isEmpty ? nil : kills
    }
}

// MARK: - Journal

/// The wallet journal, grouped by day under sticky headers that carry the day's net and
/// closing balance; each row shows its type's icon, a readable description (bounties
/// decoded from raw NPC type IDs into names), the amount and the time. Searchable and
/// filterable by category.
struct WalletJournalView: View {
    let journal: [ESIWalletJournalEntry]

    @Environment(\.eveRowDensity) private var density
    @State private var searchText = ""
    @State private var categoryFilter: WalletCategory?
    @State private var npcNames: [Int: String] = [:]

    private struct Day: Identifiable {
        let date: Date
        let entries: [ESIWalletJournalEntry]
        var id: Date { date }
        var net: Double { entries.compactMap(\.amount).reduce(0, +) }
        /// Balance after the day's last entry (entries arrive newest first).
        var closingBalance: Double? { entries.first?.balance }
    }

    private var filtered: [ESIWalletJournalEntry] {
        journal.filter { entry in
            if let categoryFilter, WalletCategory.categorize(entry.refType) != categoryFilter { return false }
            guard !searchText.isEmpty else { return true }
            if JournalEntryPresentation.title(entry.refType).localizedCaseInsensitiveContains(searchText) { return true }
            if entry.description.strippingEVEMarkup.localizedCaseInsensitiveContains(searchText) { return true }
            if let kills = JournalEntryPresentation.bountyKills(entry),
               kills.contains(where: { npcNames[$0.typeID]?.localizedCaseInsensitiveContains(searchText) == true }) {
                return true
            }
            return false
        }
    }

    private var days: [Day] {
        let cal = Calendar.current
        let grouped = Dictionary(grouping: filtered) { cal.startOfDay(for: $0.date) }
        return grouped
            .map { Day(date: $0.key, entries: $0.value.sorted { $0.date > $1.date }) }
            .sorted { $0.date > $1.date }
    }

    private var presentCategories: [WalletCategory] {
        let present = Set(journal.map { WalletCategory.categorize($0.refType) })
        return WalletCategory.allCases.filter(present.contains)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: EVESpacing.md) {
            if journal.isEmpty {
                EVEEmptyState("No Journal Entries", systemImage: "list.bullet.rectangle")
                    .frame(height: 160)
            } else {
                summaryTiles
                filterBar
                if days.isEmpty {
                    ContentUnavailableView.search(text: searchText)
                        .frame(height: 160)
                } else {
                    LazyVStack(alignment: .leading, spacing: EVESpacing.md, pinnedViews: .sectionHeaders) {
                        ForEach(days) { day in
                            Section {
                                VStack(spacing: 0) {
                                    ForEach(Array(day.entries.enumerated()), id: \.element.id) { index, entry in
                                        if index > 0 { Divider().padding(.leading, 52) }
                                        row(entry)
                                    }
                                }
                                .eveCard()
                            } header: {
                                dayHeader(day)
                            }
                        }
                    }
                }
            }
        }
        .task(id: journal.first?.id) { await resolveNPCNames() }
    }

    // MARK: Summary tiles

    private var summaryTiles: some View {
        let grouped = Dictionary(grouping: journal) { $0.refType }
        let top = grouped.sorted { a, b in
            a.value.compactMap(\.amount).map(abs).reduce(0, +) > b.value.compactMap(\.amount).map(abs).reduce(0, +)
        }.prefix(5)
        return HStack(spacing: EVESpacing.lg) {
            ForEach(Array(top), id: \.key) { refType, entries in
                let total = entries.compactMap(\.amount).reduce(0, +)
                VStack(spacing: 2) {
                    Label(JournalEntryPresentation.title(refType), systemImage: JournalEntryPresentation.symbol(refType))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    Text(EVEFormatters.formatISKShort(total))
                        .font(.caption.bold().monospacedDigit())
                        .foregroundStyle(eveAmountStyle(total, total >= 0 ? .green : .red))
                    Text("\(entries.count)×")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
                .frame(maxWidth: .infinity)
                .padding(EVESpacing.md)
                .eveCard(cornerRadius: EVERadius.md)
            }
        }
    }

    // MARK: Filter bar

    private var filterBar: some View {
        HStack(spacing: EVESpacing.md) {
            HStack(spacing: EVESpacing.sm) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("Search journal", text: $searchText)
                    .textFieldStyle(.plain)
                if !searchText.isEmpty {
                    Button { searchText = "" } label: {
                        Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Clear")
                }
            }
            .padding(.horizontal, EVESpacing.md)
            .padding(.vertical, 5)
            .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: EVERadius.sm))
            .frame(maxWidth: 280)

            EVEMenuPicker("Category", selection: $categoryFilter, options:
                [EVEMenuOption(WalletCategory?.none, "All Categories")] +
                presentCategories.enumerated().map { index, category in
                    EVEMenuOption(Optional(category), verbatim: category.label,
                                  systemImage: JournalEntryPresentation.symbol(Self.representativeRefType(category)),
                                  dividerBefore: index == 0)
                })

            Spacer()

            Text("\(filtered.count) of \(journal.count)")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
        }
    }

    /// A ref type whose symbol stands for the whole category in the filter menu.
    private static func representativeRefType(_ category: WalletCategory) -> String {
        switch category {
        case .bountiesMissions: return "bounty_prizes"
        case .market:           return "market_transaction"
        case .industry:         return "manufacturing"
        case .contracts:        return "contract_price"
        case .planetary:        return "planetary_import_tax"
        case .insurance:        return "insurance"
        case .corporation:      return "corporation_payment"
        case .feesTaxes:        return "brokers_fee"
        case .transfers:        return "player_donation"
        case .other:            return "unknown_type"
        }
    }

    // MARK: Day header

    private func dayHeader(_ day: Day) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: EVESpacing.md) {
            Text(EVEDates.dayHeader(day.date))
                .font(.subheadline.weight(.semibold))
            Text("\(day.entries.count) \(day.entries.count == 1 ? "entry" : "entries")")
                .font(.caption)
                .foregroundStyle(.tertiary)
            Spacer()
            Text((day.net > 0 && !EVEFormatters.isZeroISK(day.net) ? "+" : "") + EVEFormatters.formatISKShort(day.net))
                .font(.caption.weight(.semibold).monospacedDigit())
                .foregroundStyle(eveAmountStyle(day.net, day.net >= 0 ? .green : .red))
                .help("Net for the day")
            if let closing = day.closingBalance {
                Text("Balance \(EVEFormatters.formatISKShort(closing))")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .help("Wallet balance at the end of the day")
            }
        }
        .padding(.horizontal, EVESpacing.xs)
        .padding(.vertical, EVESpacing.sm)
        .frame(maxWidth: .infinity)
        .background(EVESurface.panel)
    }

    // MARK: Row

    private func row(_ entry: ESIWalletJournalEntry) -> some View {
        let category = WalletCategory.categorize(entry.refType)
        let amount = entry.amount ?? 0
        let description = entry.description.strippingEVEMarkup
        let kills = JournalEntryPresentation.bountyKills(entry)

        return HStack(alignment: .top, spacing: EVESpacing.md + 2) {
            Image(systemName: JournalEntryPresentation.symbol(entry.refType))
                .font(.callout.weight(.medium))
                .foregroundStyle(category.color)
                .frame(width: 30, height: 30)
                .background(category.color.opacity(0.14), in: RoundedRectangle(cornerRadius: EVERadius.md))
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text(JournalEntryPresentation.title(entry.refType))
                    .font(.subheadline.weight(.medium))
                if !description.isEmpty {
                    Text(description)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .eveTruncationHelp(description)
                }
                if let kills {
                    bountyLine(kills)
                } else if let reason = entry.reason, !reason.isEmpty {
                    Text(reason)
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                        .eveTruncationHelp(reason)
                }
            }

            Spacer(minLength: EVESpacing.md)

            VStack(alignment: .trailing, spacing: 2) {
                Text((amount > 0 && !EVEFormatters.isZeroISK(amount) ? "+" : "") + EVEFormatters.formatISKShort(amount))
                    .font(.subheadline.weight(.semibold).monospacedDigit())
                    .foregroundStyle(eveAmountStyle(amount, amount >= 0 ? .green : .red))
                    .help(entry.balance.map { "Balance after: \(EVEFormatters.formatISK($0))" } ?? "")
                Text(EVEDates.time(entry.date))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.tertiary)
                    .help(EVEDates.full(entry.date))
            }
        }
        .padding(.horizontal, EVESpacing.lg)
        .eveRowPadding()
        .padding(.vertical, 2)
        .contentShape(Rectangle())
        .contextMenu {
            Button("Copy Entry", systemImage: "doc.on.doc") { copy(entry) }
        }
    }

    /// "14 NPCs · 3× Guristas Despoiler, 2× Pithi Arrogator +9 more", full list on hover.
    private func bountyLine(_ kills: [(typeID: Int, count: Int)]) -> some View {
        let total = kills.reduce(0) { $0 + $1.count }
        let ranked = kills.sorted { $0.count > $1.count }
        let named = ranked.map { kill in "\(kill.count)× \(npcNames[kill.typeID] ?? "NPC #\(kill.typeID)")" }
        let preview = named.prefix(2).joined(separator: ", ")
        let more = named.count > 2 ? " +\(named.count - 2) more" : ""
        return HStack(spacing: EVESpacing.xs) {
            Text("\(total) NPC\(total == 1 ? "" : "s")")
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
            Text("·").foregroundStyle(.tertiary)
            Text(preview + more)
                .font(.caption)
                .foregroundStyle(.tertiary)
                .lineLimit(1)
        }
        .help(named.joined(separator: "\n"))
    }

    // MARK: Actions & data

    private func copy(_ entry: ESIWalletJournalEntry) {
        let line = [
            entry.date.formatted(.iso8601),
            JournalEntryPresentation.title(entry.refType),
            entry.amount.map { String($0) } ?? "",
            entry.balance.map { String($0) } ?? "",
            entry.description.strippingEVEMarkup
        ].joined(separator: "\t")
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(line, forType: .string)
    }

    /// Resolves the NPC type names inside bounty entries in one batch.
    private func resolveNPCNames() async {
        let ids = Set(journal.compactMap(JournalEntryPresentation.bountyKills).flatMap { $0.map(\.typeID) })
            .subtracting(npcNames.keys)
        guard !ids.isEmpty else { return }
        let types = await UniverseCache.shared.types(ids: Array(ids))
        for (id, type) in types { npcNames[id] = type.name }
    }
}
