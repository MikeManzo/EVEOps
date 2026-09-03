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

// MARK:  Corp Holding Row (Left Panel)

struct CorpHoldingRow: View {
    let corp: ResolvedLoyaltyPoints
    let isEverMarks: Bool
    let isSelected: Bool

    @State private var showSpendPlan = false

    var body: some View {
        HStack(spacing: 10) {
            CorpLogoImage(corpId: corp.corporationId, size: 38)

            VStack(alignment: .leading, spacing: 3) {
                Text(corp.corporationName)
                    .font(.subheadline.bold())
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: 3) {
                    Image(systemName: lpCurrencyIcon(isEverMarks: isEverMarks))
                        .font(.system(size: 9))
                        .foregroundStyle(lpCurrencyColor(isEverMarks: isEverMarks))
                    Text(lpFormatLP(corp.loyaltyPoints) + " " + lpCurrencyLabel(isEverMarks: isEverMarks))
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }

            Spacer(minLength: 4)

            if corp.loyaltyPoints > 0 {
                Button {
                    showSpendPlan = true
                } label: {
                    Image(systemName: "wand.and.stars")
                        .font(.system(size: 12))
                        // accentColor washes out against the selection highlight,
                        // which is also blue — switch to white when the row is selected.
                        .foregroundStyle(isSelected ? .white : Color.accentColor)
                }
                .buttonStyle(.plain)
                .help("Optimize LP spend for maximum ISK")
                .popover(isPresented: $showSpendPlan, arrowEdge: .trailing) {
                    LPSpendPlanPopover(corp: corp)
                }
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK:  Offer Detail Popover

struct LPOfferDetailPopover: View {
    let resolved: ResolvedLPOffer
    let requiredItemNames: [Int: String]
    let isEverMarks: Bool
    let hubName: String
    let showPricing: Bool

    private var offer: ESILPStoreOffer { resolved.offer }

    @State private var typeInfo: ESIType?
    @State private var groupName: String?
    @State private var categoryName: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {

                // Header — large thumbnail + name + classification
                HStack(alignment: .top, spacing: 12) {
                    LPTypeImage(typeId: offer.typeId, size: 72)
                        .shadow(color: .black.opacity(0.2), radius: 4, x: 0, y: 2)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(resolved.typeName)
                            .font(.headline)
                            .fixedSize(horizontal: false, vertical: true)
                        if let cat = categoryName, let grp = groupName {
                            Text("\(cat) › \(grp)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        } else if let grp = groupName {
                            Text(grp)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        } else {
                            Text("Type #\(offer.typeId)")
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                        }
                        Text("Offer #\(offer.offerId)")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                    Spacer(minLength: 0)
                }
                .padding(16)

                // Physical properties row (volume / portion size)
                let hasVolume   = (typeInfo?.volume ?? 0) > 0
                let hasPortion  = (typeInfo?.portionSize ?? 1) > 1
                if hasVolume || hasPortion {
                    HStack(spacing: 12) {
                        if hasVolume, let vol = typeInfo?.volume {
                            Label(String(format: "%.2f m³", vol), systemImage: "cube")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        if hasPortion, let ps = typeInfo?.portionSize {
                            Label("Portion: \(ps)", systemImage: "square.stack.3d.up")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 10)
                }

                Divider()

                // Description
                if let desc = typeInfo?.description, !desc.isEmpty {
                    VStack(alignment: .leading, spacing: 2) {
                        sectionLabel("DESCRIPTION")
                        Text(desc.strippingEVEMarkup)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                            .textSelection(.enabled)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 4)
                    }
                    .padding(.bottom, 6)
                    Divider()
                } else if typeInfo == nil {
                    HStack {
                        ProgressView().scaleEffect(0.7)
                        Text("Loading item details…")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    Divider()
                }

                // Exchange Cost
                VStack(alignment: .leading, spacing: 2) {
                    sectionLabel("EXCHANGE COST")
                    detailRow(isEverMarks ? "EverMarks Cost" : "LP Cost") {
                        HStack(spacing: 4) {
                            Image(systemName: lpCurrencyIcon(isEverMarks: isEverMarks))
                                .font(.caption)
                                .foregroundStyle(lpCurrencyColor(isEverMarks: isEverMarks))
                            Text(lpFormatLP(offer.lpCost) + " " + lpCurrencyLabel(isEverMarks: isEverMarks))
                                .foregroundStyle(Color(hue: 0.13, saturation: 0.85, brightness: 0.9))
                                .fontWeight(.semibold)
                        }
                    }
                    if showPricing {
                        detailRow("ISK Cost") {
                            Text(offer.iskCost > 0
                                 ? EVEFormatters.formatISK(Double(offer.iskCost))
                                 : "—")
                                .foregroundStyle(.secondary)
                        }
                    }
                    if let ak = offer.akCost {
                        detailRow("AK Cost") {
                            Text("\(ak) AK").foregroundStyle(.secondary)
                        }
                    }
                    if !offer.requiredItems.isEmpty {
                        detailRow("Required Items") {
                            if let reqCost = resolved.requiredItemsCost {
                                Text(EVEFormatters.formatISK(reqCost)).foregroundStyle(.secondary)
                            } else {
                                Text("Loading…").foregroundStyle(.tertiary)
                            }
                        }
                    }
                }
                .padding(.bottom, 8)

                Divider()

                // Reward
                VStack(alignment: .leading, spacing: 2) {
                    sectionLabel("REWARD")
                    detailRow("Quantity") {
                        Text("×\(offer.quantity)").foregroundStyle(.primary)
                    }
                    if showPricing {
                        if let sell = resolved.marketSell {
                            detailRow("\(hubName) Sell") {
                                Text(EVEFormatters.formatISK(sell)).foregroundStyle(.green)
                            }
                            if offer.quantity > 1 {
                                detailRow("Total Value") {
                                    Text(EVEFormatters.formatISK(sell * Double(offer.quantity)))
                                        .foregroundStyle(.green)
                                }
                            }
                            if let net = resolved.netISK {
                                detailRow("Net ISK") {
                                    Text((net >= 0 ? "+" : "") + EVEFormatters.formatISK(net))
                                        .foregroundStyle(net >= 0 ? .green : .red)
                                        .fontWeight(.semibold)
                                }
                            }
                        } else {
                            detailRow("\(hubName) Sell") {
                                Text("No market data").foregroundStyle(.tertiary)
                            }
                        }
                    }
                }
                .padding(.bottom, 8)

                // ISK/LP badge
                if showPricing, let iskLP = resolved.iskPerLP {
                    let color = lpISKPerLPColor(iskLP)
                    HStack {
                        Spacer()
                        VStack(spacing: 2) {
                            Text(lpFormatISKPerLP(iskLP))
                                .font(.title2.bold().monospacedDigit())
                                .foregroundStyle(.white)
                            Text("ISK / LP")
                                .font(.caption2.bold())
                                .foregroundStyle(.white.opacity(0.75))
                        }
                        .padding(.horizontal, 20)
                        .padding(.vertical, 10)
                        .background(color, in: RoundedRectangle(cornerRadius: 12))
                        .shadow(color: color.opacity(0.45), radius: 6, x: 0, y: 2)
                        Spacer()
                    }
                    .padding(.vertical, 12)
                }

                // Required items
                if !offer.requiredItems.isEmpty {
                    Divider()
                    VStack(alignment: .leading, spacing: 2) {
                        sectionLabel("REQUIRED ITEMS (\(offer.requiredItems.count))")
                        ForEach(offer.requiredItems, id: \.typeId) { item in
                            HStack(spacing: 8) {
                                Text("×\(item.quantity)")
                                    .font(.caption.monospacedDigit())
                                    .foregroundStyle(.secondary)
                                    .frame(width: 44, alignment: .trailing)
                                Text(requiredItemNames[item.typeId] ?? "Item #\(item.typeId)")
                                    .font(.caption)
                                    .foregroundStyle(.primary)
                                Spacer(minLength: 0)
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 3)
                        }
                    }
                    .padding(.bottom, 10)
                }
            }
        }
        .frame(minWidth: 300, maxWidth: 360, minHeight: 200, maxHeight: 520)
        .task(id: offer.typeId) { await loadTypeInfo() }
    }

    private func sectionLabel(_ title: String) -> some View {
        Text(title)
            .font(.caption2.bold())
            .foregroundStyle(.tertiary)
            .padding(.horizontal, 16)
            .padding(.top, 10)
            .padding(.bottom, 2)
    }

    private func detailRow<Content: View>(
        _ label: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .frame(width: 100, alignment: .leading)
            content()
                .font(.subheadline)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 3)
    }

    private func loadTypeInfo() async {
        typeInfo = nil
        groupName = nil
        categoryName = nil
        guard let type = await UniverseCache.shared.type(id: offer.typeId) else { return }
        typeInfo = type
        guard let group = await UniverseCache.shared.group(id: type.groupId) else { return }
        groupName = group.name
        if let cat = await UniverseCache.shared.category(id: group.categoryId) {
            categoryName = cat.name
        }
    }
}

// MARK:  Spend Plan Popover (Holdings Optimizer)

struct LPSpendPlanEntry: Identifiable {
    let offer: ResolvedLPOffer
    let redemptions: Int
    var id: Int { offer.id }

    var lpUsed: Int { offer.offer.lpCost * redemptions }
    var iskGained: Double { (offer.netISK ?? 0) * Double(redemptions) }
}

/// Why the greedy planner couldn't build a spend plan — these are two distinct
/// situations that call for different next steps, so they're kept separate rather
/// than folded into one generic "no offers" message.
enum LPSpendPlanEmptyReason {
    /// None of this store's rewards have any market data at all (e.g. Paragon/EverMarks —
    /// mostly account-bound cosmetics). There's no ISK angle to optimize for here.
    case noMarketData
    /// Some offers are priced, but nothing clears break-even. `closest` are the
    /// least-unprofitable offers (may be ≤ 0 ISK/LP) shown for context.
    case noProfitableOffers(closest: [ResolvedLPOffer])
    /// At least one offer is profitable, but the corp's LP balance can't afford
    /// even one redemption of the cheapest of them.
    case lpTooLow(cheapest: ResolvedLPOffer, shortfall: Int)
}

/// Greedily fills the corp's LP balance with the highest ISK/LP offers it can afford,
/// in order, spilling leftover LP into the next-best affordable offer. This is an
/// approximation (not an exact knapsack solve) but matches the ranking already shown
/// in the offer list and needs no extra state to reason about.
struct LPSpendPlanPopover: View {
    let corp: ResolvedLoyaltyPoints

    @State private var isLoading = true
    @State private var loadError: String?
    @State private var plan: [LPSpendPlanEntry] = []
    @State private var emptyReason: LPSpendPlanEmptyReason?
    @State private var lpUsed = 0
    @State private var totalISK: Double = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            if isLoading {
                HStack(spacing: 8) {
                    ProgressView().scaleEffect(0.7)
                    Text("Calculating best value…")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(16)
            } else if let loadError {
                Text(loadError)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(16)
            } else if let emptyReason {
                emptyStateView(emptyReason)
            } else {
                Text(planSummarySentence)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                Divider()
                ScrollView {
                    planList
                }
                Divider()
                summary
            }
        }
        .frame(minWidth: 360, maxWidth: 440, minHeight: 160, maxHeight: 420)
        // List(.sidebar) — the ancestor presenting this popover — sets an implicit
        // .lineLimit(1) on its row content, which popovers inherit from their
        // presenting view's environment. Reset it here so multi-line text below
        // (e.g. the empty-state message) isn't silently truncated to one line.
        .lineLimit(nil)
        .task(id: corp.corporationId) { await buildPlan() }
    }

    @ViewBuilder
    private func emptyStateView(_ reason: LPSpendPlanEmptyReason) -> some View {
        switch reason {
        case .noMarketData:
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "xmark.seal")
                        .foregroundStyle(.tertiary)
                    Text("None of \(corp.corporationName)'s rewards are tradeable on the market — there's no ISK value to optimize for here.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(16)

        case .noProfitableOffers(let closest):
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "chart.line.downtrend.xyaxis")
                        .foregroundStyle(.tertiary)
                    Text("None of \(corp.corporationName)'s offers clear break-even at current prices, even checking every major hub.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if !closest.isEmpty {
                    Divider()
                    VStack(alignment: .leading, spacing: 4) {
                        Text("CLOSEST TO PROFITABLE")
                            .font(.caption2.bold())
                            .foregroundStyle(.tertiary)
                        ForEach(closest) { offer in
                            HStack(spacing: 8) {
                                Text(offer.typeName)
                                    .font(.caption)
                                    .lineLimit(1)
                                Spacer(minLength: 8)
                                if let ratio = offer.rawISKPerLP {
                                    Text(lpFormatISKPerLP(ratio) + " ISK/LP")
                                        .font(.caption.monospacedDigit().bold())
                                        .foregroundStyle(ratio > 0 ? .green : .red)
                                }
                            }
                        }
                    }
                    Text("Prices move — check back later, or redeem manually for an item's use value rather than resale profit.")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(16)

        case .lpTooLow(let cheapest, let shortfall):
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "medal")
                        .foregroundStyle(.tertiary)
                    Text("You don't have enough LP yet for a profitable redemption.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Divider()
                VStack(alignment: .leading, spacing: 4) {
                    Text("CHEAPEST PROFITABLE OFFER")
                        .font(.caption2.bold())
                        .foregroundStyle(.tertiary)
                    HStack(spacing: 8) {
                        Text(cheapest.typeName)
                            .font(.caption.bold())
                            .lineLimit(1)
                        Spacer(minLength: 8)
                        Text(lpFormatLP(cheapest.offer.lpCost) + " LP")
                            .font(.caption.monospacedDigit())
                    }
                    if let net = cheapest.netISK {
                        Text("+" + EVEFormatters.formatISK(net) + " net ISK")
                            .font(.caption2.monospacedDigit())
                            .foregroundStyle(.green)
                    }
                }
                Text("You need \(lpFormatLP(shortfall)) more LP to afford it.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(16)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Optimized LP Spend")
                .font(.headline)
            Text("\(corp.corporationName) · \(lpFormatLP(corp.loyaltyPoints)) LP available")
                .font(.caption)
                .foregroundStyle(.secondary)
            Text("Best price across Jita, Amarr, Dodixie, Rens & Hek")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .padding(16)
    }

    private var planList: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(plan) { entry in
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text("×\(entry.redemptions)")
                        .font(.caption.monospacedDigit().bold())
                        .foregroundStyle(.secondary)
                        .frame(minWidth: 28, alignment: .leading)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(entry.offer.typeName)
                            .font(.caption)
                            .lineLimit(2)
                            .fixedSize(horizontal: false, vertical: true)
                        if let hub = entry.offer.bestSellHub {
                            Text("sell at \(hub.displayName)")
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    VStack(alignment: .trailing, spacing: 1) {
                        Text("+" + EVEFormatters.formatISK(entry.iskGained))
                            .font(.caption.monospacedDigit().bold())
                            .foregroundStyle(.green)
                        Text(lpFormatLP(entry.lpUsed) + " LP")
                            .font(.caption2.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                    .fixedSize()
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 6)
            }
        }
        .padding(.vertical, 6)
    }

    /// Plain-English readout of the plan, generated by templating the numbers we
    /// already computed — no model call, so it's exact and always available.
    private var planSummarySentence: String {
        let lpText  = "\(lpFormatLP(lpUsed))/\(lpFormatLP(corp.loyaltyPoints)) LP"
        let iskText = "+" + EVEFormatters.formatISK(totalISK)

        if plan.count == 1, let only = plan.first {
            return "Redeem ×\(only.redemptions) \(only.offer.typeName) for \(lpText), netting \(iskText)."
        }
        let leader = plan.max { ($0.offer.iskPerLP ?? 0) < ($1.offer.iskPerLP ?? 0) }
        let ledBy = leader.map { " led by \($0.offer.typeName)" } ?? ""
        return "Redeem \(plan.count) offers\(ledBy) using \(lpText) for a projected \(iskText)."
    }

    private var summary: some View {
        VStack(spacing: 6) {
            HStack {
                Text("LP Used")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Text("\(lpFormatLP(lpUsed)) / \(lpFormatLP(corp.loyaltyPoints))")
                    .font(.caption.monospacedDigit())
            }
            HStack {
                Text("Projected ISK")
                    .font(.subheadline.bold())
                Spacer()
                Text("+" + EVEFormatters.formatISK(totalISK))
                    .font(.subheadline.bold().monospacedDigit())
                    .foregroundStyle(.green)
            }
        }
        .padding(16)
    }

    private func buildPlan() async {
        isLoading = true
        loadError = nil
        emptyReason = nil
        do {
            let bundle = try await fetchLPStoreOffersAcrossHubs(for: corp.corporationId)
            let candidates = bundle.offers
                .filter { ($0.iskPerLP ?? 0) > 0 && $0.offer.lpCost > 0 }
                .sorted { ($0.iskPerLP ?? 0) > ($1.iskPerLP ?? 0) }

            guard !candidates.isEmpty else {
                let priced = bundle.offers.filter { $0.rawISKPerLP != nil }
                plan = []
                if priced.isEmpty {
                    emptyReason = .noMarketData
                } else {
                    let closest = priced.sorted { $0.rawISKPerLP! > $1.rawISKPerLP! }.prefix(3)
                    emptyReason = .noProfitableOffers(closest: Array(closest))
                }
                isLoading = false
                return
            }

            var remainingLP = corp.loyaltyPoints
            var entries: [LPSpendPlanEntry] = []
            for offer in candidates {
                let count = remainingLP / offer.offer.lpCost
                guard count > 0 else { continue }
                entries.append(LPSpendPlanEntry(offer: offer, redemptions: count))
                remainingLP -= count * offer.offer.lpCost
            }

            if entries.isEmpty {
                let cheapest = candidates.min { $0.offer.lpCost < $1.offer.lpCost }!
                plan = []
                emptyReason = .lpTooLow(cheapest: cheapest, shortfall: cheapest.offer.lpCost - corp.loyaltyPoints)
            } else {
                plan = entries
                lpUsed = corp.loyaltyPoints - remainingLP
                totalISK = entries.reduce(0) { $0 + $1.iskGained }
            }
        } catch {
            loadError = "Could not load LP store offers."
        }
        isLoading = false
    }
}

// MARK:  Offer Row

struct LPOfferRow: View {
    let resolved: ResolvedLPOffer
    let isEven: Bool
    let requiredItemNames: [Int: String]
    let agentStations: [AgentStation]
    let isLoadingStations: Bool
    let isEverMarks: Bool
    let hubName: String
    let showPricing: Bool
    let onSetWaypoint: (Int) -> Void

    @State private var showPopover = false

    private var offer: ESILPStoreOffer { resolved.offer }

    var body: some View {
        HStack(spacing: 0) {

            // Icon (tappable for popover) + name
            HStack(spacing: 10) {
                LPTypeImage(typeId: offer.typeId, size: 44)
                    .shadow(color: .black.opacity(0.15), radius: 2, x: 0, y: 1)
                    .onTapGesture { showPopover = true }
                    .popover(isPresented: $showPopover, arrowEdge: .trailing) {
                        LPOfferDetailPopover(
                            resolved: resolved,
                            requiredItemNames: requiredItemNames,
                            isEverMarks: isEverMarks,
                            hubName: hubName,
                            showPricing: showPricing
                        )
                    }
                VStack(alignment: .leading, spacing: 2) {
                    Text(resolved.typeName)
                        .font(.subheadline.bold())
                        .lineLimit(1)
                    if !offer.requiredItems.isEmpty {
                        Label(
                            "\(offer.requiredItems.count) required item\(offer.requiredItems.count == 1 ? "" : "s")",
                            systemImage: "bag"
                        )
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.leading, 12)

            // LP / EverMarks cost
            HStack(spacing: 3) {
                Image(systemName: lpCurrencyIcon(isEverMarks: isEverMarks))
                    .font(.system(size: 9))
                    .foregroundStyle(lpCurrencyColor(isEverMarks: isEverMarks))
                Text(lpFormatLP(offer.lpCost))
                    .font(.caption.monospacedDigit().bold())
                    .foregroundStyle(Color(hue: 0.13, saturation: 0.85, brightness: 0.9))
            }
            .frame(width: 90, alignment: .trailing)

            if showPricing {
                // ISK cost
                Text(offer.iskCost > 0 ? EVEFormatters.formatISKShort(Double(offer.iskCost)) : "—")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .frame(width: 100, alignment: .trailing)
            }

            // Quantity
            Text("×\(offer.quantity)")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.tertiary)
                .frame(width: 44, alignment: .trailing)
                .padding(.trailing, showPricing ? 0 : 16)

            if showPricing {
                // Market sell price at the selected hub
                Group {
                    if let sell = resolved.marketSell {
                        Text(EVEFormatters.formatISKShort(sell))
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.green)
                    } else {
                        Text("—").foregroundStyle(.tertiary)
                    }
                }
                .frame(width: 110, alignment: .trailing)

                // ISK/LP badge
                iskPerLPBadge
                    .frame(width: 110, alignment: .trailing)
                    .padding(.trailing, 16)
            }
        }
        .padding(.vertical, 9)
        .background(isEven ? Color.clear : Color(NSColor.separatorColor).opacity(0.07))
        .contentShape(Rectangle())
        .contextMenu {
            if isLoadingStations {
                Label("Set Destination (loading stations…)", systemImage: "location")
                    .foregroundStyle(.secondary)
            } else if agentStations.isEmpty {
                Label("Set Destination (no stations found)", systemImage: "location.slash")
                    .foregroundStyle(.secondary)
            } else if agentStations.count == 1 {
                Button {
                    onSetWaypoint(agentStations[0].locationId)
                } label: {
                    Label("Set Destination: \(agentStations[0].stationName)", systemImage: "location.fill")
                }
            } else {
                Menu {
                    ForEach(agentStations) { station in
                        Button(station.stationName) {
                            onSetWaypoint(station.locationId)
                        }
                    }
                } label: {
                    Label("Set Destination", systemImage: "location.fill")
                }
            }
        }
    }

    @ViewBuilder
    private var iskPerLPBadge: some View {
        if let iskLP = resolved.iskPerLP {
            let color = lpISKPerLPColor(iskLP)
            Text(lpFormatISKPerLP(iskLP))
                .font(.caption.monospacedDigit().bold())
                .foregroundStyle(.white)
                .padding(.horizontal, 9)
                .padding(.vertical, 4)
                .background(color, in: Capsule())
                .shadow(color: color.opacity(0.4), radius: 3, x: 0, y: 1)
        } else if resolved.marketSell == nil {
            Text("—")
                .font(.caption)
                .foregroundStyle(.tertiary)
        } else {
            Text("≤0")
                .font(.caption.bold())
                .foregroundStyle(.white)
                .padding(.horizontal, 9)
                .padding(.vertical, 4)
                .background(Color.red.opacity(0.75), in: Capsule())
        }
    }
}
