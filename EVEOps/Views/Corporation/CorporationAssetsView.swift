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

struct CorporationAssetsView: View {
    @Environment(AccountManager.self) private var accountManager
    @State private var assets: [ResolvedAsset] = []
    @State private var isLoading = true
    @State private var error: String?
    @State private var searchText = ""
    @State private var groupMode: AssetGroupMode = .station
    @State private var selectedAsset: ResolvedAsset?

    var body: some View {
        LoadingStateView(isLoading: isLoading, error: error, isEmpty: assets.isEmpty, emptyMessage: "No corporation assets found or insufficient permissions") {
            HStack(spacing: 0) {
                VStack(spacing: 0) {
                    HStack {
                        Image(systemName: "magnifyingglass")
                            .foregroundStyle(.secondary)
                        TextField("Search corporation assets...", text: $searchText)
                            .textFieldStyle(.plain)
                        Spacer()
                        Picker("Group by", selection: $groupMode) {
                            ForEach(AssetGroupMode.allCases, id: \.self) { mode in
                                Text(mode.label).tag(mode)
                            }
                        }
                        .pickerStyle(.segmented)
                        .fixedSize()
                    }
                    .padding(10)
                    .background(.bar)

                    List(selection: $selectedAsset) {
                        let keyPath: (ResolvedAsset) -> String = groupMode == .station ? \.locationName : \.typeName
                        let grouped = Dictionary(grouping: filteredAssets, by: keyPath)
                        ForEach(grouped.keys.sorted(), id: \.self) { sectionKey in
                            Section(sectionKey) {
                                ForEach(grouped[sectionKey] ?? []) { asset in
                                    HStack(spacing: 8) {
                                        AsyncImage(url: EVEImageURL.typeIcon(asset.typeId, size: 256)) { phase in
                                            if let image = phase.image {
                                                image.resizable()
                                                    .frame(width: 28, height: 28)
                                                    .clipShape(RoundedRectangle(cornerRadius: 4))
                                            } else {
                                                Image(systemName: "shippingbox.fill")
                                                    .foregroundStyle(.teal)
                                                    .frame(width: 28, height: 28)
                                            }
                                        }
                                        switch groupMode {
                                        case .station:
                                            HStack(spacing: 4) {
                                                Text(asset.typeName)
                                                if asset.isBlueprintCopy {
                                                    Text("(BPC)")
                                                        .font(.caption2)
                                                        .foregroundStyle(.orange)
                                                }
                                            }
                                        case .type:
                                            VStack(alignment: .leading) {
                                                Text(asset.locationName)
                                                if asset.isBlueprintCopy {
                                                    Text("(BPC)")
                                                        .font(.caption2)
                                                        .foregroundStyle(.orange)
                                                }
                                            }
                                        }
                                        Spacer()
                                        Text("x\(asset.quantity)")
                                            .font(.caption.monospacedDigit())
                                            .foregroundStyle(.secondary)
                                    }
                                    .tag(asset)
                                }
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity)

                if selectedAsset != nil {
                    Divider()
                    AssetDetailView(asset: selectedAsset!)
                        .frame(width: 320)
                }
            }
        }
        .safeAreaInset(edge: .top, spacing: 0) {
            HStack {
                Text("Corp Assets")
                    .font(.largeTitle.bold())
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(.background)
        }
        .navigationTitle("Corp Assets")
        .task(id: accountManager.selectedCharacterID) {
            assets = []
            selectedAsset = nil
            isLoading = true
            await loadAssets()
        }
    }

    private var filteredAssets: [ResolvedAsset] {
        if searchText.isEmpty { return assets }
        return assets.filter {
            $0.typeName.localizedCaseInsensitiveContains(searchText) ||
            $0.locationName.localizedCaseInsensitiveContains(searchText)
        }
    }

    private func loadAssets() async {
        guard let account = accountManager.selectedAccount else { return }
        isLoading = true
        do {
            let token = try await accountManager.validToken(for: account)
            let rawAssets: [ESIAsset] = try await ESIClient.shared.fetchPages(
                "/corporations/\(account.corporationID)/assets/", token: token
            )

            let typeIDs = Array(Set(rawAssets.map(\.typeId)))
            let typeNames = await NameResolver.shared.resolve(ids: typeIDs)

            let itemIdToType: [Int: String] = Dictionary(
                rawAssets.map { ($0.itemId, typeNames[$0.typeId] ?? "Container") },
                uniquingKeysWith: { first, _ in first }
            )

            let locationIDs = Array(Set(rawAssets.map(\.locationId)))
            var locationNames: [Int: String] = [:]
            for locID in locationIDs {
                if let containerName = itemIdToType[locID] {
                    locationNames[locID] = containerName
                } else {
                    locationNames[locID] = await NameResolver.shared.resolveLocation(id: locID, token: token)
                }
            }

            assets = rawAssets.map { asset in
                ResolvedAsset(
                    itemId: asset.itemId,
                    typeId: asset.typeId,
                    typeName: typeNames[asset.typeId] ?? "Unknown Type",
                    quantity: asset.quantity,
                    locationId: asset.locationId,
                    locationName: locationNames[asset.locationId] ?? "Location #\(asset.locationId)",
                    locationFlag: asset.locationFlag,
                    isBlueprintCopy: asset.isBlueprintCopy ?? false,
                    isSingleton: asset.isSingleton
                )
            }
            if selectedAsset == nil { selectedAsset = assets.first }
        } catch {
            self.error = error.localizedDescription
        }
        isLoading = false
    }
}
