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

struct CorporationMiningView: View {
    @Environment(AccountManager.self) private var accountManager
    @State private var observers: [MiningObserverData] = []
    @State private var isLoading = false
    @State private var error: String?
    @State private var expandedObserverId: Int?

    var body: some View {
        LoadingStateView(isLoading: isLoading, error: error, isEmpty: observers.isEmpty, emptyMessage: "No mining data found or insufficient roles") {
            List(observers) { observer in
                MiningObserverRow(data: observer, isExpanded: expandedObserverId == observer.id)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            expandedObserverId = expandedObserverId == observer.id ? nil : observer.id
                        }
                    }
            }
        }
        .safeAreaInset(edge: .top, spacing: 0) {
            HStack {
                Text("Corp Mining Ledger")
                    .font(.largeTitle.bold())
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(.background)
        }
        .navigationTitle("")
        .task(id: accountManager.selectedCharacterID) {
            guard let account = accountManager.selectedAccount else { return }
            isLoading = true
            error = nil
            do {
                let token = try await accountManager.validToken(for: account)
                let rawObservers: [ESIMiningObserver] = try await ESIClient.shared.fetchPages(
                    "/corporation/\(account.corporationID)/mining/observers/", token: token
                )
                var result: [MiningObserverData] = []
                await withTaskGroup(of: MiningObserverData?.self) { group in
                    for observer in rawObservers {
                        group.addTask {
                            let ledger: [ESIMiningLedgerEntry] = (try? await ESIClient.shared.fetch(
                                "/corporation/\(account.corporationID)/mining/observers/\(observer.observerId)/",
                                token: token
                            )) ?? []
                            let name = await NameResolver.shared.resolve(id: observer.observerId)
                            return MiningObserverData(
                                id: observer.observerId,
                                name: name,
                                type: observer.observerType,
                                lastUpdated: observer.lastUpdated,
                                ledger: ledger
                            )
                        }
                    }
                    for await data in group { if let d = data { result.append(d) } }
                }
                observers = result.sorted { $0.lastUpdated > $1.lastUpdated }
            } catch {
                self.error = error.localizedDescription
            }
            isLoading = false
        }
    }
}

struct MiningObserverData: Identifiable {
    let id: Int
    let name: String
    let type: String
    let lastUpdated: Date
    let ledger: [ESIMiningLedgerEntry]
    var totalQuantity: Int { ledger.reduce(0) { $0 + $1.quantity } }
}

struct MiningObserverRow: View {
    let data: MiningObserverData
    let isExpanded: Bool
    @State private var oreNames: [Int: String] = [:]

    // Ore totals grouped by typeId, sorted by quantity descending
    private var oreTotals: [(typeId: Int, quantity: Int)] {
        let grouped = Dictionary(grouping: data.ledger) { $0.typeId }
        return grouped.map { typeId, entries in
            (typeId: typeId, quantity: entries.reduce(0) { $0 + $1.quantity })
        }.sorted { $0.quantity > $1.quantity }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "building.2.fill").foregroundStyle(.blue)
                VStack(alignment: .leading, spacing: 2) {
                    Text(data.name.isEmpty ? "Structure #\(data.id)" : data.name)
                        .font(.subheadline.bold())
                    Text(data.type.replacingOccurrences(of: "_", with: " ").capitalized)
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text("\(data.totalQuantity.formatted()) m³")
                        .font(.caption.bold()).foregroundStyle(.blue)
                    Text(data.lastUpdated, style: .date)
                        .font(.caption2).foregroundStyle(.tertiary)
                }
                Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                    .foregroundStyle(.secondary).font(.caption)
            }

            if isExpanded {
                Divider()
                LazyVStack(spacing: 4) {
                    ForEach(oreTotals.prefix(20), id: \.typeId) { entry in
                        HStack(spacing: 8) {
                            AsyncImage(url: EVEImageURL.typeIcon(entry.typeId, size: 32)) { image in
                                image.resizable()
                            } placeholder: {
                                RoundedRectangle(cornerRadius: 3).fill(.quaternary)
                            }
                            .frame(width: 20, height: 20)
                            .clipShape(RoundedRectangle(cornerRadius: 3))

                            Text(oreNames[entry.typeId] ?? "Ore #\(entry.typeId)")
                                .font(.caption)
                            Spacer()
                            Text("\(entry.quantity.formatted()) m³")
                                .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                        }
                    }
                }
                .task(id: isExpanded) {
                    guard isExpanded, oreNames.isEmpty else { return }
                    let ids = Array(Set(data.ledger.map(\.typeId)))
                    let types = await UniverseCache.shared.types(ids: ids)
                    oreNames = types.mapValues(\.name)
                }
            }
        }
        .padding(.vertical, 4)
    }
}
