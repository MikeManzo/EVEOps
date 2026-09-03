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

struct LocationOverviewView: View {
    @Environment(AccountManager.self) var accountManager
    @Environment(DashboardPrefetcher.self) var prefetcher
    @AppStorage("backgroundPollInterval") var pollInterval: Double = 300
    @State var locations: [CharacterLocationInfo] = []
    @State var isLoading = false
    @State var isRefreshing = false
    @State var error: String?
    @State var lastRefresh: Date?
    @State var refreshTick = 0
    @State var stationsExpanded: [Int: Bool] = [:]
    @State var systemActivity: [Int: SystemActivityData] = [:]
    @State var fwSystems: [Int: ESIFWSystem] = [:]
    @State var incursions: [ESIIncursion] = []
    @State var situationalFactionNames: [Int: String] = [:]
    @State var showCargoValueInfo = false
    @State var cargoValues: [Int: CargoValueSummary] = [:]
    @State var cargoLoading: Set<Int> = []
    @State var cargoErrors: [Int: String] = [:]

    var body: some View {
        LoadingStateView(
            isLoading: isLoading,
            error: error,
            isEmpty: locations.isEmpty,
            hasContent: !locations.isEmpty,
            emptyMessage: "No location data",
            onRetry: { Task { await refreshAll() } }
        ) {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    HStack(alignment: .firstTextBaseline) {
                        Text("Location Overview")
                            .font(.largeTitle.bold())
                        Spacer()
                        RelativeTimestamp(date: lastRefresh)
                        RefreshButton(isRefreshing: isRefreshing) {
                            Task { await refreshAll() }
                        }
                    }
                    .padding(.horizontal)

                    ForEach(locations, id: \.characterID) { info in
                        locationCard(info)
                    }
                }
                .padding()
            }
        }
        .navigationTitle("")
        .task(id: accountManager.selectedCharacterID) {
            locations = []
            if buildFromPrefetcher() {
                Task { await loadSystemActivity() }
                return
            }
            isLoading = true
            async let loc: Void = loadLocations()
            async let act: Void = loadSystemActivity()
            _ = await (loc, act)
        }
        .autoRefresh(every: pollInterval) { await refreshAll() }
        .onChange(of: AppRouter.shared.refreshTick) { _, _ in
            Task { await refreshAll() }
        }
    }

}
