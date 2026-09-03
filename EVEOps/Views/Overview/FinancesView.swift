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

struct FinancesView: View {
    @Environment(AccountManager.self) var accountManager
    @Environment(DashboardPrefetcher.self) var prefetcher
    @State var characterFinances: [CharacterFinanceData] = []
    @State var isLoading = false
    @State var isRefreshing = false
    @State var lastRefresh: Date?
    @State var error: String?
    @State var selectedTab = 0
    @State var typeNames: [Int: String] = [:]
    @State var isLoadingAssets = false

    var totalWealth: Double {
        characterFinances.reduce(0) { $0 + $1.balance }
    }

    var totalEscrow: Double {
        characterFinances.reduce(0) { $0 + $1.totalEscrow }
    }

    var totalSellOrderValue: Double {
        characterFinances.reduce(0) { $0 + $1.totalSellOrderValue }
    }

    var totalBuyOrderValue: Double {
        characterFinances.reduce(0) { $0 + $1.totalBuyOrderValue }
    }

    var totalAssetValue: Double {
        characterFinances.reduce(0) { $0 + $1.assetValue }
    }

    var netWorth: Double {
        totalWealth + totalEscrow + totalSellOrderValue + totalAssetValue
    }

    var selectedFinance: CharacterFinanceData? {
        characterFinances.first
    }

    var body: some View {
        LoadingStateView(
            isLoading: isLoading,
            error: error,
            isEmpty: characterFinances.isEmpty,
            hasContent: !characterFinances.isEmpty,
            emptyMessage: "No financial data",
            onRetry: { Task { await refresh() } }
        ) {
            ScrollView {
                VStack(spacing: 20) {
                    summaryCards
                    todaySummary
                    wealthDistribution
                    if let finance = selectedFinance {
                        if let warning = finance.partialLoadWarning {
                            HStack(spacing: 6) {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .foregroundStyle(.yellow)
                                    .font(.caption)
                                Text(warning)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Spacer()
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(.yellow.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
                            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(.yellow.opacity(0.2), lineWidth: 1))
                        }
                        characterDetail(finance)
                    }
                }
                .padding()
            }
        }
        .safeAreaInset(edge: .top, spacing: 0) {
            HStack(spacing: 12) {
                Text("Finances")
                    .font(.largeTitle.bold())
                Spacer()
                RelativeTimestamp(date: lastRefresh)
                RefreshButton(isRefreshing: isRefreshing) {
                    Task { await refresh() }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(.background)
        }
        .navigationTitle("")
        .onChange(of: AppRouter.shared.refreshTick) { _, _ in
            Task { await refresh() }
        }
        .task(id: accountManager.selectedCharacterID) {
            if buildFromPrefetcher() {
                await resolveTypeNames()
                await loadAssetValues()
                return
            }
            isLoading = true
            await loadAllFinances()
            await resolveTypeNames()
            await loadAssetValues()
        }
        .onChange(of: prefetcher.lastRefresh) { _, _ in
            // Prefetcher refreshed on its background poll interval (Settings) — sync immediately
            Task {
                if buildFromPrefetcher() {
                    await resolveTypeNames()
                    await loadAssetValues()
                }
            }
        }
    }

}
