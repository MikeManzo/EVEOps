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

// MARK:  Local Models

private struct ResolvedLPOffer: Identifiable {
    let offer: ESILPStoreOffer
    let typeName: String
    var jitaSell: Double?
    var id: Int { offer.offerId }

    /// Net ISK gained per exchange: (jitaSell × qty) − iskCost
    var netISK: Double? {
        guard let jitaSell else { return nil }
        return (jitaSell * Double(offer.quantity)) - Double(offer.iskCost)
    }

    /// ISK earned per LP spent
    var iskPerLP: Double? {
        guard let net = netISK, net > 0, offer.lpCost > 0 else { return nil }
        return net / Double(offer.lpCost)
    }
}

// MARK:  Image Views

private enum LPStoreImageCache {
    static let items = NSCache<NSNumber, NSImage>()
    static let corps = NSCache<NSNumber, NSImage>()
}

private struct LPTypeImage: View {
    let typeId: Int
    let size: CGFloat

    @State private var image: NSImage?
    @State private var failed = false

    var body: some View {
        Group {
            if let image {
                Image(nsImage: image).resizable().scaledToFit()
            } else if failed {
                Image(systemName: "cube.transparent")
                    .font(.system(size: size * 0.5))
                    .foregroundStyle(.tertiary)
            } else {
                RoundedRectangle(cornerRadius: size * 0.15).fill(.quaternary)
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: size * 0.15))
        .task(id: typeId) {
            if let cached = LPStoreImageCache.items.object(forKey: NSNumber(value: typeId)) {
                image = cached; return
            }
            image = nil; failed = false
            for urlOpt in [EVEImageURL.typeRender(typeId, size: 64), EVEImageURL.typeIcon(typeId, size: 64)] {
                guard let url = urlOpt,
                      let (data, resp) = try? await URLSession.shared.data(from: url),
                      (resp as? HTTPURLResponse)?.statusCode == 200,
                      let img = NSImage(data: data) else { continue }
                LPStoreImageCache.items.setObject(img, forKey: NSNumber(value: typeId))
                image = img
                return
            }
            failed = true
        }
    }
}

private struct CorpLogoImage: View {
    let corpId: Int
    let size: CGFloat

    @State private var image: NSImage?
    @State private var failed = false

    var body: some View {
        Group {
            if let image {
                Image(nsImage: image).resizable().scaledToFit()
            } else if failed {
                Image(systemName: "building.2")
                    .font(.system(size: size * 0.45))
                    .foregroundStyle(.tertiary)
            } else {
                RoundedRectangle(cornerRadius: size * 0.2).fill(.quaternary)
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: size * 0.2))
        .task(id: corpId) {
            if let cached = LPStoreImageCache.corps.object(forKey: NSNumber(value: corpId)) {
                image = cached; return
            }
            image = nil; failed = false
            guard let url = EVEImageURL.corporationLogo(corpId, size: 64),
                  let (data, resp) = try? await URLSession.shared.data(from: url),
                  (resp as? HTTPURLResponse)?.statusCode == 200,
                  let img = NSImage(data: data) else { failed = true; return }
            LPStoreImageCache.corps.setObject(img, forKey: NSNumber(value: corpId))
            image = img
        }
    }
}

// MARK:  LoyaltyPointStoreView

struct LoyaltyPointStoreView: View {
    @Environment(AccountManager.self) private var accountManager
    @Environment(DashboardPrefetcher.self) private var prefetcher

    @State private var lpData: [ResolvedLoyaltyPoints] = []
    @State private var selectedCorpId: Int?
    @State private var offers: [ResolvedLPOffer] = []
    @State private var isLoadingLP = false
    @State private var isLoadingOffers = false
    @State private var offersError: String?
    @State private var searchText = ""
    @State private var sortByISKLP = true

    private var selectedCorp: ResolvedLoyaltyPoints? {
        lpData.first { $0.corporationId == selectedCorpId }
    }

    private var filteredOffers: [ResolvedLPOffer] {
        var result = offers
        if !searchText.isEmpty {
            result = result.filter { $0.typeName.localizedCaseInsensitiveContains(searchText) }
        }
        if sortByISKLP {
            result = result.sorted { ($0.iskPerLP ?? -1) > ($1.iskPerLP ?? -1) }
        } else {
            result = result.sorted { $0.offer.lpCost < $1.offer.lpCost }
        }
        return result
    }

    private var totalLP: Int { lpData.reduce(0) { $0 + $1.loyaltyPoints } }

    var body: some View {
        HStack(spacing: 0) {
            corpList
                .frame(width: 240)
            Divider()
            offerPanel
        }
        .safeAreaInset(edge: .top, spacing: 0) {
            HStack {
                Text("LP Store")
                    .font(.largeTitle.bold())
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(.background)
        }
        .navigationTitle("")
        .task(id: accountManager.selectedCharacterID) {
            await loadLP()
        }
        .onChange(of: selectedCorpId) { _, id in
            if let id { Task { await loadOffers(for: id) } }
        }
    }

    // MARK:  Corp List (Left Panel)

    private var corpList: some View {
        VStack(spacing: 0) {
            // Panel header
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Holdings")
                        .font(.subheadline.bold())
                    if !lpData.isEmpty {
                        HStack(spacing: 3) {
                            Image(systemName: "medal.fill")
                                .font(.system(size: 9))
                                .foregroundStyle(.yellow)
                            Text("\(formatLP(totalLP)) total LP")
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.top, 10)
            .padding(.bottom, 8)
            .background(.bar)

            Divider()

            if isLoadingLP {
                VStack(spacing: 10) {
                    ProgressView()
                    Text("Loading LP…")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if lpData.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "medal")
                        .font(.system(size: 36))
                        .foregroundStyle(.tertiary)
                    Text("No Loyalty Points")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Text("Earn LP by running missions for NPC corporations.")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 12)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(lpData, id: \.corporationId, selection: Binding(
                    get: { selectedCorpId },
                    set: { selectedCorpId = $0 }
                )) { lp in
                    corpRow(lp)
                        .tag(lp.corporationId)
                }
                .listStyle(.sidebar)
            }
        }
        .background(Color(NSColor.controlBackgroundColor))
    }

    private func corpRow(_ lp: ResolvedLoyaltyPoints) -> some View {
        HStack(spacing: 10) {
            CorpLogoImage(corpId: lp.corporationId, size: 38)

            VStack(alignment: .leading, spacing: 3) {
                Text(lp.corporationName)
                    .font(.subheadline.bold())
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: 3) {
                    Image(systemName: "medal.fill")
                        .font(.system(size: 9))
                        .foregroundStyle(.yellow)
                    Text(formatLP(lp.loyaltyPoints) + " LP")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.vertical, 4)
    }

    // MARK:  Offer Panel (Right Panel)

    @ViewBuilder
    private var offerPanel: some View {
        if selectedCorpId == nil {
            VStack(spacing: 14) {
                Image(systemName: "storefront.fill")
                    .font(.system(size: 52))
                    .foregroundStyle(.tertiary)
                Text("Select a Corporation")
                    .font(.headline)
                    .foregroundStyle(.secondary)
                Text("Choose a corporation on the left to browse their LP store offers.")
                    .font(.subheadline)
                    .foregroundStyle(.tertiary)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if isLoadingOffers {
            VStack(spacing: 14) {
                ProgressView()
                Text("Loading LP store offers…")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let err = offersError {
            VStack(spacing: 14) {
                Image(systemName: "exclamationmark.triangle")
                    .font(.system(size: 38))
                    .foregroundStyle(.orange)
                Text(err)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                Button("Retry") {
                    if let id = selectedCorpId { Task { await loadOffers(for: id) } }
                }
                .buttonStyle(.bordered)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            offerList
        }
    }

    private var offerList: some View {
        VStack(spacing: 0) {
            offerToolbar
            Divider()
            offerColumnHeader
            Divider()
            if filteredOffers.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 32))
                        .foregroundStyle(.tertiary)
                    Text(searchText.isEmpty ? "No offers available" : "No results for \"\(searchText)\"")
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(Array(filteredOffers.enumerated()), id: \.element.id) { index, offer in
                            offerRow(offer, isEven: index % 2 == 0)
                            Divider()
                                .padding(.leading, 64)
                                .opacity(0.5)
                        }
                    }
                }
            }
        }
    }

    private var offerToolbar: some View {
        HStack(spacing: 10) {
            // Search field
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                    .font(.subheadline)
                TextField("Search offers…", text: $searchText)
                    .textFieldStyle(.plain)
                if !searchText.isEmpty {
                    Button { searchText = "" } label: {
                        Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(7)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
            .frame(maxWidth: 260)

            // Result count
            if !offers.isEmpty {
                Text("\(filteredOffers.count) offer\(filteredOffers.count == 1 ? "" : "s")")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .monospacedDigit()
            }

            Spacer()

            // LP balance badge for selected corp
            if let corp = selectedCorp {
                HStack(spacing: 4) {
                    Image(systemName: "medal.fill")
                        .foregroundStyle(.yellow)
                        .font(.caption)
                    Text(formatLP(corp.loyaltyPoints) + " LP")
                        .font(.caption.bold().monospacedDigit())
                        .foregroundStyle(.primary)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(.yellow.opacity(0.12), in: Capsule())
                .overlay(Capsule().strokeBorder(.yellow.opacity(0.3), lineWidth: 1))
            }

            // Sort picker
            Picker("Sort", selection: $sortByISKLP) {
                Text("ISK/LP").tag(true)
                Text("LP Cost").tag(false)
            }
            .pickerStyle(.segmented)
            .frame(width: 150)
            .labelsHidden()
            .help("Sort by estimated ISK per LP or by LP cost")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
    }

    private var offerColumnHeader: some View {
        HStack(spacing: 0) {
            Text("Item")
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.leading, 64)

            // LP — sort indicator when active
            HStack(spacing: 3) {
                Text("LP Cost")
                if !sortByISKLP {
                    Image(systemName: "chevron.up")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(Color.accentColor)
                }
            }
            .frame(width: 90, alignment: .trailing)

            Text("ISK Cost")
                .frame(width: 100, alignment: .trailing)

            Text("Qty")
                .frame(width: 44, alignment: .trailing)

            Text("Jita Sell")
                .frame(width: 110, alignment: .trailing)

            // ISK/LP — sort indicator when active
            HStack(spacing: 3) {
                Text("ISK/LP")
                if sortByISKLP {
                    Image(systemName: "chevron.down")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(Color.accentColor)
                }
            }
            .frame(width: 110, alignment: .trailing)
            .padding(.trailing, 16)
        }
        .font(.caption.bold())
        .foregroundStyle(.secondary)
        .padding(.vertical, 6)
        .background(Color(NSColor.separatorColor).opacity(0.12))
    }

    private func offerRow(_ resolved: ResolvedLPOffer, isEven: Bool) -> some View {
        let offer = resolved.offer
        return HStack(spacing: 0) {
            // Icon + name
            HStack(spacing: 10) {
                LPTypeImage(typeId: offer.typeId, size: 44)
                    .shadow(color: .black.opacity(0.15), radius: 2, x: 0, y: 1)
                VStack(alignment: .leading, spacing: 2) {
                    Text(resolved.typeName)
                        .font(.subheadline.bold())
                        .lineLimit(1)
                    if !offer.requiredItems.isEmpty {
                        Label("\(offer.requiredItems.count) required item\(offer.requiredItems.count == 1 ? "" : "s")", systemImage: "bag")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.leading, 12)

            // LP cost
            HStack(spacing: 3) {
                Image(systemName: "medal.fill")
                    .font(.system(size: 9))
                    .foregroundStyle(.yellow)
                Text(formatLP(offer.lpCost))
                    .font(.caption.monospacedDigit().bold())
                    .foregroundStyle(Color(hue: 0.13, saturation: 0.85, brightness: 0.9))
            }
            .frame(width: 90, alignment: .trailing)

            // ISK cost
            Text(offer.iskCost > 0 ? EVEFormatters.formatISKShort(Double(offer.iskCost)) : "—")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: 100, alignment: .trailing)

            // Quantity
            Text("×\(offer.quantity)")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.tertiary)
                .frame(width: 44, alignment: .trailing)

            // Jita sell price
            Group {
                if let sell = resolved.jitaSell {
                    Text(EVEFormatters.formatISKShort(sell))
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.green)
                } else {
                    Text("—")
                        .foregroundStyle(.tertiary)
                }
            }
            .frame(width: 110, alignment: .trailing)

            // ISK/LP — pill badge
            iskPerLPBadge(resolved)
                .frame(width: 110, alignment: .trailing)
                .padding(.trailing, 16)
        }
        .padding(.vertical, 9)
        .background(isEven ? Color.clear : Color(NSColor.separatorColor).opacity(0.07))
    }

    @ViewBuilder
    private func iskPerLPBadge(_ resolved: ResolvedLPOffer) -> some View {
        if let iskLP = resolved.iskPerLP {
            let color = iskPerLPColor(iskLP)
            Text(formatISKperLP(iskLP))
                .font(.caption.monospacedDigit().bold())
                .foregroundStyle(.white)
                .padding(.horizontal, 9)
                .padding(.vertical, 4)
                .background(color, in: Capsule())
                .shadow(color: color.opacity(0.4), radius: 3, x: 0, y: 1)
        } else if resolved.jitaSell == nil {
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

    private func iskPerLPColor(_ value: Double) -> Color {
        if value >= 1500 { return .green }
        if value >= 800  { return Color(hue: 0.25, saturation: 0.8, brightness: 0.75) }
        if value >= 400  { return .orange }
        return .red
    }

    // MARK:  Data Loading

    private func loadLP() async {
        isLoadingLP = true
        selectedCorpId = nil
        offers = []

        // Try prefetcher first
        if let account = accountManager.selectedAccount,
           let prefetched = prefetcher.data(for: account.characterID) {
            let corpIDs = prefetched.loyaltyPoints.map(\.corporationId)
            let names = await NameResolver.shared.resolve(ids: corpIDs)
            lpData = prefetched.loyaltyPoints
                .map { lp in
                    ResolvedLoyaltyPoints(
                        corporationId: lp.corporationId,
                        corporationName: names[lp.corporationId] ?? "Corp #\(lp.corporationId)",
                        loyaltyPoints: lp.loyaltyPoints
                    )
                }
                .sorted { $0.loyaltyPoints > $1.loyaltyPoints }
            isLoadingLP = false
            if let first = lpData.first { selectedCorpId = first.corporationId }
            return
        }

        // Live fetch fallback
        guard let account = accountManager.selectedAccount,
              let token = try? await accountManager.validToken(for: account) else {
            isLoadingLP = false
            return
        }
        do {
            let raw: [ESILoyaltyPoints] = try await ESIClient.shared.fetch(
                "/characters/\(account.characterID)/loyalty/points/", token: token
            )
            let corpIDs = raw.map(\.corporationId)
            let names = await NameResolver.shared.resolve(ids: corpIDs)
            lpData = raw
                .map { lp in
                    ResolvedLoyaltyPoints(
                        corporationId: lp.corporationId,
                        corporationName: names[lp.corporationId] ?? "Corp #\(lp.corporationId)",
                        loyaltyPoints: lp.loyaltyPoints
                    )
                }
                .sorted { $0.loyaltyPoints > $1.loyaltyPoints }
        } catch {
            lpData = []
        }
        isLoadingLP = false
        if let first = lpData.first { selectedCorpId = first.corporationId }
    }

    private func loadOffers(for corpId: Int) async {
        isLoadingOffers = true
        offersError = nil
        offers = []

        do {
            // LP store offers are public — no auth needed
            let raw: [ESILPStoreOffer] = try await ESIClient.shared.fetch(
                "/loyalty/stores/\(corpId)/offers/"
            )

            // Resolve item names for all unique typeIds
            let typeIds = Array(Set(raw.map(\.typeId)))
            let names = await NameResolver.shared.resolve(ids: typeIds)

            var resolved = raw.map { offer in
                ResolvedLPOffer(
                    offer: offer,
                    typeName: names[offer.typeId] ?? "Item #\(offer.typeId)"
                )
            }

            isLoadingOffers = false
            offers = resolved.sorted { ($0.iskPerLP ?? -1) > ($1.iskPerLP ?? -1) }

            // Fetch Jita prices in background and update rows as they arrive
            if !typeIds.isEmpty {
                if let prices = try? await FuzzworkClient.shared.prices(typeIds: typeIds) {
                    for i in resolved.indices {
                        let tid = resolved[i].offer.typeId
                        resolved[i].jitaSell = prices[tid]?.sellPercentile
                    }
                    offers = resolved.sorted { ($0.iskPerLP ?? -1) > ($1.iskPerLP ?? -1) }
                }
            }
        } catch {
            isLoadingOffers = false
            offersError = "Could not load LP store. This corporation may not have a public LP store."
        }
    }

    // MARK:  Formatting

    private func formatLP(_ value: Int) -> String {
        if value >= 1_000_000 { return String(format: "%.1fM", Double(value) / 1_000_000) }
        if value >= 1_000 { return String(format: "%.0fK", Double(value) / 1_000) }
        return "\(value)"
    }

    private func formatISKperLP(_ value: Double) -> String {
        if value >= 1_000_000 { return String(format: "%.1fM", value / 1_000_000) }
        if value >= 1_000 { return String(format: "%.0fK", value / 1_000) }
        return String(format: "%.0f", value)
    }
}
