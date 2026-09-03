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

// Supporting types, formatters and row/popover views live in
// LoyaltyPointStoreSupport.swift.

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
    @AppStorage("lpStoreMarketHub") private var selectedHub: LPMarketHub = .jita

    // Required item names resolved alongside offer type names
    @State private var requiredItemNames: [Int: String] = [:]

    // Agent stations for the selected corp (for "Set Destination")
    @State private var agentStations: [AgentStation] = []
    @State private var isLoadingStations = false

    // Waypoint feedback toast
    @State private var waypointMessage: String?
    @State private var waypointIsSuccess = false

    private var selectedCorp: ResolvedLoyaltyPoints? {
        lpData.first { $0.corporationId == selectedCorpId }
    }

    private var isEverMarks: Bool { selectedCorpId == paragonCorporationId }

    /// Whether any currently-loaded offer actually has market pricing. Some NPC-corp
    /// reward stores (e.g. Paragon/EverMarks) turn out to be entirely non-tradeable
    /// items — detected from real fetch results rather than assumed from corp identity,
    /// so pricing UI hides itself for any store like that and reappears automatically
    /// if that ever changes, without hardcoding a corp ID.
    private var offersHaveMarketData: Bool {
        offers.contains { $0.marketSell != nil }
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
            if let id {
                sortByISKLP = true
                Task { await loadOffers(for: id) }
                Task { await loadAgentStations(for: id) }
            }
        }
        .onChange(of: selectedHub) { _, _ in
            if let id = selectedCorpId {
                Task { await loadOffers(for: id) }
            }
        }
    }

    // MARK:  Corp List (Left Panel)

    private var corpList: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Holdings")
                        .font(.subheadline.bold())
                    if !lpData.isEmpty {
                        HStack(spacing: 3) {
                            Image(systemName: "medal.fill")
                                .font(.system(size: 9))
                                .foregroundStyle(.yellow)
                            Text("\(lpFormatLP(totalLP)) total LP")
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
                    CorpHoldingRow(
                        corp: lp,
                        isEverMarks: lp.corporationId == paragonCorporationId,
                        isSelected: lp.corporationId == selectedCorpId
                    )
                    .tag(lp.corporationId)
                }
                .listStyle(.sidebar)
            }
        }
        .background(Color(NSColor.controlBackgroundColor))
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
                        .multilineTextAlignment(.center)
                        .lineLimit(nil)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: 280)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(Array(filteredOffers.enumerated()), id: \.element.id) { index, offer in
                            LPOfferRow(
                                resolved: offer,
                                isEven: index % 2 == 0,
                                requiredItemNames: requiredItemNames,
                                agentStations: agentStations,
                                isLoadingStations: isLoadingStations,
                                isEverMarks: isEverMarks,
                                hubName: selectedHub.displayName,
                                showPricing: offersHaveMarketData,
                                onSetWaypoint: { locationId in
                                    Task { await setWaypoint(locationId: locationId) }
                                }
                            )
                            Divider()
                                .padding(.leading, 64)
                                .opacity(0.5)
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
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

            // Waypoint feedback toast
            if let msg = waypointMessage {
                HStack(spacing: 4) {
                    Image(systemName: waypointIsSuccess
                          ? "checkmark.circle.fill"
                          : "exclamationmark.triangle.fill")
                        .foregroundStyle(waypointIsSuccess ? .green : .orange)
                        .font(.caption)
                    Text(msg)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .transition(.opacity)
            }

            // LP / EverMarks balance badge for selected corp
            if let corp = selectedCorp {
                HStack(spacing: 4) {
                    Image(systemName: lpCurrencyIcon(isEverMarks: isEverMarks))
                        .foregroundStyle(lpCurrencyColor(isEverMarks: isEverMarks))
                        .font(.caption)
                    Text(lpFormatLP(corp.loyaltyPoints) + " " + lpCurrencyLabel(isEverMarks: isEverMarks))
                        .font(.caption.bold().monospacedDigit())
                        .foregroundStyle(.primary)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(lpCurrencyColor(isEverMarks: isEverMarks).opacity(0.12), in: Capsule())
                .overlay(Capsule().strokeBorder(lpCurrencyColor(isEverMarks: isEverMarks).opacity(0.3), lineWidth: 1))
            }

            // Market hub / sort — hidden when this store's rewards have no market data at all
            // (e.g. Paragon/EverMarks — checked from the actual fetch, not assumed from corp ID).
            if offersHaveMarketData {
                HStack(spacing: 4) {
                    Image(systemName: "building.columns")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Picker("Market", selection: $selectedHub) {
                        ForEach(LPMarketHub.allCases) { hub in
                            Text(hub.displayName).tag(hub)
                        }
                    }
                    .pickerStyle(.menu)
                    .labelsHidden()
                    .frame(width: 80)
                }
                .help("Reference market for reward and required-item prices")

                Picker("Sort", selection: $sortByISKLP) {
                    Text("ISK/LP").tag(true)
                    Text("LP Cost").tag(false)
                }
                .pickerStyle(.segmented)
                .frame(width: 150)
                .labelsHidden()
                .help("Sort by estimated ISK per LP or by LP cost")
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .animation(.easeInOut(duration: 0.25), value: waypointMessage)
    }

    private var offerColumnHeader: some View {
        HStack(spacing: 0) {
            Text("Item")
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.leading, 64)

            HStack(spacing: 3) {
                Text(isEverMarks ? "EM Cost" : "LP Cost")
                if !sortByISKLP {
                    Image(systemName: "chevron.up")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(Color.accentColor)
                }
            }
            .frame(width: 90, alignment: .trailing)

            if offersHaveMarketData {
                Text("ISK Cost")
                    .frame(width: 100, alignment: .trailing)
            }

            Text("Qty")
                .frame(width: 44, alignment: .trailing)
                .padding(.trailing, offersHaveMarketData ? 0 : 16)

            if offersHaveMarketData {
                Text("\(selectedHub.displayName) Sell")
                    .frame(width: 110, alignment: .trailing)

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
        }
        .font(.caption.bold())
        .foregroundStyle(.secondary)
        .padding(.vertical, 6)
        .background(Color(NSColor.separatorColor).opacity(0.12))
    }

    // MARK:  Data Loading

    private func loadLP() async {
        isLoadingLP = true
        selectedCorpId = nil
        offers = []
        agentStations = []
        requiredItemNames = [:]

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
        requiredItemNames = [:]

        do {
            let bundle = try await fetchLPStoreOffers(for: corpId, regionId: selectedHub.regionId)
            offers = bundle.offers
            requiredItemNames = bundle.requiredItemNames
        } catch {
            offersError = "Could not load LP store. This corporation may not have a public LP store."
        }
        isLoadingOffers = false
    }

    private func loadAgentStations(for corpId: Int) async {
        isLoadingStations = true
        agentStations = []

        await AgentDataManager.shared.ensureLoaded()

        let allAgents = await AgentDataManager.shared.agents
        let locationIds = Array(Set(
            allAgents
                .filter { $0.corporationID == corpId && $0.agentTypeID != 1 }
                .map(\.locationID)
        ))

        guard !locationIds.isEmpty else {
            isLoadingStations = false
            return
        }

        let names = await NameResolver.shared.resolve(ids: locationIds)
        agentStations = locationIds
            .compactMap { id -> AgentStation? in
                guard let name = names[id] else { return nil }
                return AgentStation(locationId: id, stationName: name)
            }
            .sorted { $0.stationName < $1.stationName }

        isLoadingStations = false
    }

    // MARK:  Waypoint

    private func setWaypoint(locationId: Int) async {
        guard let account = accountManager.selectedAccount,
              let token = try? await accountManager.validToken(for: account) else {
            withAnimation { waypointMessage = "No character logged in." }
            waypointIsSuccess = false
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            withAnimation { waypointMessage = nil }
            return
        }
        do {
            try await ESIClient.shared.postAction(
                "/ui/autopilot/waypoint/",
                token: token,
                queryItems: [
                    URLQueryItem(name: "add_to_beginning",     value: "false"),
                    URLQueryItem(name: "clear_other_waypoints", value: "true"),
                    URLQueryItem(name: "destination_id",        value: "\(locationId)")
                ]
            )
            withAnimation { waypointMessage = "Destination set in EVE client." }
            waypointIsSuccess = true
        } catch {
            withAnimation { waypointMessage = "Requires esi-ui.write_waypoint.v1 scope." }
            waypointIsSuccess = false
        }
        try? await Task.sleep(nanoseconds: 3_000_000_000)
        withAnimation { waypointMessage = nil }
    }
}
