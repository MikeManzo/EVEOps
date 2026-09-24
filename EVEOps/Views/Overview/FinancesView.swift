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
    @Environment(ThemeManager.self) var themeManager
    var palette: EVEPalette { themeManager.palette }
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
            emptyMessage: "No Financial Data",
            emptySystemImage: "chart.line.uptrend.xyaxis",
            onRetry: { Task { await refresh() } }
        ) {
            ScrollView {
                VStack(spacing: 20) {
                    summaryCards
                    todaySummary
                    wealthDistribution
                    if let finance = selectedFinance {
                        NetWorthHistoryCard(characterID: finance.characterID, tint: palette.accent)
                    }
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
                            .background(.yellow.opacity(0.08), in: RoundedRectangle(cornerRadius: EVERadius.md))
                            .overlay(RoundedRectangle(cornerRadius: EVERadius.md).strokeBorder(.yellow.opacity(0.2), lineWidth: 1))
                        }
                        characterDetail(finance)
                    }
                }
                .padding()
            }
        }
        .onChange(of: isLoadingAssets) { wasLoading, nowLoading in
            // Snapshot once valuation settles, so a half-valued net worth never becomes a
            // data point in the history.
            guard wasLoading, !nowLoading, let finance = selectedFinance else { return }
            NetWorthHistory.shared.record(characterID: finance.characterID, netWorth: netWorth, wallet: totalWealth)
        }
        .eveScreenHeader("Finances", section: .finances) {
            RelativeTimestamp(date: lastRefresh)
            RefreshButton(isRefreshing: isRefreshing) {
                Task { await refresh() }
            }
        }
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
