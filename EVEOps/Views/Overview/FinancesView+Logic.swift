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
    // MARK:  Loyalty Points

    func loyaltyPointsSection(_ lp: [ResolvedLoyaltyPoints]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            if lp.isEmpty {
                Text("No loyalty points")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 100)
            } else {
                let totalLP = lp.reduce(0) { $0 + $1.loyaltyPoints }
                HStack {
                    Text("Total LP")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text("\(totalLP.formatted()) LP")
                        .font(.title3.bold().monospacedDigit())
                        .foregroundStyle(.purple)
                }
                .padding()
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))

                LazyVStack(spacing: 1) {
                    ForEach(lp.sorted(by: { $0.loyaltyPoints > $1.loyaltyPoints }), id: \.corporationId) { entry in
                        HStack(spacing: 10) {
                            CachedAsyncImage(url: EVEImageURL.corporationLogo(entry.corporationId, size: 64)) { image in
                                image.resizable()
                            } placeholder: {
                                RoundedRectangle(cornerRadius: 4).fill(.quaternary)
                            }
                            .frame(width: 32, height: 32)
                            .clipShape(RoundedRectangle(cornerRadius: 4))

                            Text(entry.corporationName)
                                .font(.subheadline)

                            Spacer()

                            Text("\(entry.loyaltyPoints.formatted()) LP")
                                .font(.subheadline.bold().monospacedDigit())
                                .foregroundStyle(.purple)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                    }
                }
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
            }
        }
    }

    // MARK:  Asset Valuation

    /// Fetches all character assets and values them using /markets/prices/ (average market prices).
    /// Runs after finances are loaded; updates characterFinances in place as each character resolves.
    func loadAssetValues() async {
        isLoadingAssets = true
        defer { isLoadingAssets = false }

        // Fetch global market prices once (public endpoint, ESI-cached ~1 hour)
        let marketPrices: [ESIMarketPrice]
        do {
            marketPrices = try await ESIClient.shared.fetch("/markets/prices/")
        } catch {
            return
        }
        let priceMap = Dictionary(
            marketPrices.map { ($0.typeId, $0.averagePrice ?? $0.adjustedPrice ?? 0.0) },
            uniquingKeysWith: { first, _ in first }
        )

        for i in characterFinances.indices {
            let finance = characterFinances[i]
            guard let account = accountManager.accounts.first(where: { $0.characterID == finance.characterID }),
                  let token = try? await accountManager.validToken(for: account) else { continue }
            do {
                let assets: [ESIAsset] = try await ESIClient.shared.fetchPages(
                    "/characters/\(finance.characterID)/assets/", token: token
                )
                let value = assets
                    .filter { !($0.isBlueprintCopy ?? false) }
                    .reduce(0.0) { sum, asset in
                        sum + (priceMap[asset.typeId] ?? 0) * Double(asset.quantity)
                    }
                characterFinances[i].assetValue = value
            } catch {
                continue
            }
        }
    }

    // MARK:  Type Name Resolution

    func resolveTypeNames() async {
        var allTypeIDs = Set<Int>()
        for finance in characterFinances {
            finance.transactions.forEach { allTypeIDs.insert($0.typeId) }
            finance.marketOrders.forEach { allTypeIDs.insert($0.typeId) }
        }
        guard !allTypeIDs.isEmpty else { return }
        let types = await UniverseCache.shared.types(ids: Array(allTypeIDs))
        typeNames = types.mapValues { $0.name }
    }

    // MARK:  Helpers

    func formatRefType(_ refType: String) -> String {
        refType.replacingOccurrences(of: "_", with: " ").capitalized
    }

    // MARK:  Prefetcher Fast Path

    func buildFromPrefetcher() -> Bool {
        guard let account = accountManager.selectedAccount,
              let prefetched = prefetcher.data(for: account.characterID) else { return false }

        let resolvedLP = prefetched.loyaltyPoints.map { entry in
            ResolvedLoyaltyPoints(
                corporationId: entry.corporationId,
                corporationName: prefetcher.resolvedNames[entry.corporationId] ?? "Corporation #\(entry.corporationId)",
                loyaltyPoints: entry.loyaltyPoints
            )
        }

        characterFinances = [CharacterFinanceData(
            characterID: account.characterID,
            characterName: account.characterName,
            corporationName: account.corporationName,
            balance: prefetched.wallet,
            journal: prefetched.journal.sorted { $0.date > $1.date },
            transactions: prefetched.transactions.sorted { $0.date > $1.date },
            marketOrders: prefetched.marketOrders,
            loyaltyPoints: resolvedLP
        )]
        lastRefresh = prefetcher.lastRefresh ?? Date()
        return true
    }

    // MARK:  Data Loading

    func refresh() async {
        isRefreshing = true
        defer { isRefreshing = false }
        error = nil
        await loadAllFinances()
        await resolveTypeNames()
        await loadAssetValues()
    }

    func loadAllFinances() async {
        if characterFinances.isEmpty { isLoading = true }
        self.error = nil

        guard let account = accountManager.selectedAccount else {
            isLoading = false
            return
        }

        do {
            let data = try await loadFinance(for: account)
            characterFinances = [data]
        } catch {
            characterFinances = []
            self.error = error.localizedDescription
        }
        lastRefresh = Date()
        isLoading = false
    }

    func loadFinance(for account: StoredAccount) async throws -> CharacterFinanceData {
        let token = try await accountManager.validToken(for: account)
        let charID = account.characterID

        // Fetch each independently so one failure doesn't block others
        var balance: Double = 0
        var journal: [ESIWalletJournalEntry] = []
        var transactions: [ESIWalletTransaction] = []
        var orders: [ESIMarketOrder] = []
        var lp: [ESILoyaltyPoints] = []
        var firstFieldError: Error? = nil

        do { balance = try await ESIClient.shared.fetch("/characters/\(charID)/wallet/", token: token) } catch { if firstFieldError == nil { firstFieldError = error } }
        do { journal = try await ESIClient.shared.fetch("/characters/\(charID)/wallet/journal/", token: token) } catch { if firstFieldError == nil { firstFieldError = error } }
        do { transactions = try await ESIClient.shared.fetch("/characters/\(charID)/wallet/transactions/", token: token) } catch { if firstFieldError == nil { firstFieldError = error } }
        do { orders = try await ESIClient.shared.fetch("/characters/\(charID)/orders/", token: token) } catch { if firstFieldError == nil { firstFieldError = error } }
        do { lp = try await ESIClient.shared.fetch("/characters/\(charID)/loyalty/points/", token: token) } catch { if firstFieldError == nil { firstFieldError = error } }

        // Resolve LP corporation names
        let corpIDs = lp.map(\.corporationId)
        let names = await NameResolver.shared.resolve(ids: corpIDs)
        let resolvedLP = lp.map { entry in
            ResolvedLoyaltyPoints(
                corporationId: entry.corporationId,
                corporationName: names[entry.corporationId] ?? "Corporation #\(entry.corporationId)",
                loyaltyPoints: entry.loyaltyPoints
            )
        }

        return CharacterFinanceData(
            characterID: charID,
            characterName: account.characterName,
            corporationName: account.corporationName,
            balance: balance,
            journal: journal.sorted { $0.date > $1.date },
            transactions: transactions.sorted { $0.date > $1.date },
            marketOrders: orders,
            loyaltyPoints: resolvedLP,
            partialLoadWarning: firstFieldError?.localizedDescription
        )
    }
}
