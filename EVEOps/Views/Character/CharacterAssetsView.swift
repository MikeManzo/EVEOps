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
import FoundationModels

struct CharacterAssetsView: View {
    @Environment(AccountManager.self) private var accountManager
    @State private var assets: [ResolvedAsset] = []
    @State private var isLoading = true
    @State private var error: String?
    @State private var searchText = ""
    @State private var groupMode: AssetGroupMode = .station
    @State private var selectedAsset: ResolvedAsset?
    @State private var collapsedSections: Set<String> = Self.loadCollapsedSections()

    var body: some View {
        LoadingStateView(isLoading: isLoading, error: error, isEmpty: assets.isEmpty, emptyMessage: "No assets found") {
            HStack(spacing: 0) {
                VStack(spacing: 0) {
                    HStack {
                        Image(systemName: "magnifyingglass")
                            .foregroundStyle(.secondary)
                        TextField("Search assets...", text: $searchText)
                            .textFieldStyle(.plain)
                        Spacer()
                        Button(collapsedSections.isEmpty ? "Collapse All" : "Expand All") {
                            if collapsedSections.isEmpty {
                                let keyPath: (ResolvedAsset) -> String = groupMode == .station ? \.locationName : \.typeName
                                collapsedSections = Set(filteredAssets.map(keyPath))
                            } else {
                                collapsedSections = []
                            }
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(.secondary)
                        .font(.caption)
                        Divider().frame(height: 14)
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

                    groupedList
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)

                Divider()
                detailPanel
                    .frame(width: 320)
            }
        }
        .navigationTitle("Assets")
        .task { await loadAssets() }
        .onChange(of: collapsedSections) { saveCollapsedSections() }
        .onChange(of: groupMode) { collapsedSections = [] }
    }

    private static func loadCollapsedSections() -> Set<String> {
        guard let data = UserDefaults.standard.data(forKey: "assetCollapsedSections"),
              let decoded = try? JSONDecoder().decode(Set<String>.self, from: data)
        else { return [] }
        return decoded
    }

    @ViewBuilder
    private var detailPanel: some View {
        if let asset = selectedAsset {
            AssetDetailView(asset: asset)
        } else {
            Spacer()
        }
    }

    private func saveCollapsedSections() {
        if let data = try? JSONEncoder().encode(collapsedSections) {
            UserDefaults.standard.set(data, forKey: "assetCollapsedSections")
        }
    }

    private var filteredAssets: [ResolvedAsset] {
        if searchText.isEmpty { return assets }
        return assets.filter {
            $0.typeName.localizedCaseInsensitiveContains(searchText) ||
            $0.locationName.localizedCaseInsensitiveContains(searchText)
        }
    }

    private var groupedList: some View {
        let keyPath: (ResolvedAsset) -> String = groupMode == .station ? \.locationName : \.typeName
        let grouped = Dictionary(grouping: filteredAssets, by: keyPath)
        let sortedKeys = grouped.keys.sorted()
        return List(selection: $selectedAsset) {
            if #available(macOS 26.0, *) {
                AssetAIInsightCard(
                    assets: assets,
                    characterName: accountManager.selectedAccount?.characterName ?? "Character"
                )
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
                .listRowInsets(EdgeInsets(top: 8, leading: 8, bottom: 8, trailing: 8))
                .selectionDisabled()
            }
            ForEach(sortedKeys, id: \.self) { sectionKey in
                let items = grouped[sectionKey] ?? []
                let isExpanded = Binding<Bool>(
                    get: { !collapsedSections.contains(sectionKey) },
                    set: { expanded in
                        if expanded {
                            collapsedSections.remove(sectionKey)
                        } else {
                            collapsedSections.insert(sectionKey)
                        }
                    }
                )
                Section(isExpanded: isExpanded) {
                    ForEach(items) { asset in
                        assetRow(asset)
                            .tag(asset)
                    }
                } header: {
                    HStack {
                        Text(sectionKey)
                            .font(.title3.bold())
                        Spacer()
                        Text("\(items.count)")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .frame(maxHeight: .infinity)
    }

    private func assetRow(_ asset: ResolvedAsset) -> some View {
        HStack(spacing: 8) {
            AsyncImage(url: EVEImageURL.typeIcon(asset.typeId, size: 256)) { phase in
                if let image = phase.image {
                    image.resizable()
                        .frame(width: 28, height: 28)
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                } else {
                    Image(systemName: "cube.box.fill")
                        .foregroundStyle(.blue)
                        .frame(width: 28, height: 28)
                }
            }
            VStack(alignment: .leading) {
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
                    Text(asset.locationName)
                        .font(.callout)
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
    }

    private func loadAssets() async {
        guard let account = accountManager.selectedAccount else { return }
        isLoading = true
        do {
            let token = try await accountManager.validToken(for: account)
            let rawAssets: [ESIAsset] = try await ESIClient.shared.fetchPages(
                "/characters/\(account.characterID)/assets/", token: token
            )

            let typeIDs = Array(Set(rawAssets.map(\.typeId)))
            let typeNames = await NameResolver.shared.resolve(ids: typeIDs)

            // Build a map of itemId -> typeName for containers (ships, etc.)
            let itemIdToType: [Int: String] = Dictionary(
                rawAssets.map { ($0.itemId, typeNames[$0.typeId] ?? "Container") },
                uniquingKeysWith: { first, _ in first }
            )

            // Resolve location names: stations, structures, or parent containers
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
                    locationName: locationNames[asset.locationId] ?? "Unknown Location",
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

enum AssetGroupMode: CaseIterable {
    case station, type

    var label: String {
        switch self {
        case .station: return "By Station"
        case .type: return "By Type"
        }
    }
}

struct ResolvedAsset: Identifiable, Hashable {
    let itemId: Int
    let typeId: Int
    let typeName: String
    let quantity: Int
    let locationId: Int
    let locationName: String
    var locationFlag: String = ""
    var isBlueprintCopy: Bool = false
    var isSingleton: Bool = false

    var id: Int { itemId }
}

// MARK: Asset AI Insight Card

@available(macOS 26.0, *)
struct AssetAIInsightCard: View {
    let assets: [ResolvedAsset]
    let characterName: String

    @AppStorage("aiInsightsEnabled") private var aiInsightsEnabled = false
    @AppStorage("aiInsightAssets")   private var aiInsightAssets   = true
    @State private var insight: AssetInsight?
    @State private var isGenerating = false
    @State private var generationError: String?
    @State private var hasAutoGenerated = false

    private var model: SystemLanguageModel { .default }

    var body: some View {
        if aiInsightsEnabled && aiInsightAssets, case .available = model.availability {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Label("AI Insight", systemImage: "sparkles")
                        .font(.subheadline.bold())
                        .foregroundStyle(.purple)
                    Spacer()
                    if insight != nil, !isGenerating {
                        Button {
                            Task { await generate() }
                        } label: {
                            Image(systemName: "arrow.clockwise")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                        .help("Regenerate insight")
                    }
                }

                if isGenerating {
                    HStack(spacing: 8) {
                        ProgressView().controlSize(.small)
                        Text("Analyzing asset spread\u{2026}")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                } else if let insight {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(insight.summary)
                            .font(.subheadline)
                            .fixedSize(horizontal: false, vertical: true)
                        HStack(alignment: .top, spacing: 6) {
                            Image(systemName: "lightbulb.fill")
                                .font(.caption).foregroundStyle(.yellow).padding(.top, 1)
                            Text(insight.suggestion)
                                .font(.caption).foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                } else if let error = generationError {
                    Text(error).font(.caption).foregroundStyle(.red.opacity(0.8))
                } else {
                    Button("Generate Insight") { Task { await generate() } }
                        .buttonStyle(.bordered).controlSize(.small)
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(.purple.opacity(0.2)))
            .task(id: assets.first?.itemId ?? 0) {
                guard !hasAutoGenerated else { return }
                hasAutoGenerated = true
                await generate()
            }
        }
    }

    private func generate() async {
        isGenerating = true
        generationError = nil

        let byLocation = Dictionary(grouping: assets, by: { $0.locationName })
        let topLocations = byLocation
            .map { (location: $0.key, count: $0.value.count) }
            .sorted { $0.count > $1.count }
            .prefix(5)
            .map { (location: $0.location, count: $0.count) }

        let byType = Dictionary(grouping: assets, by: { $0.typeName })
        let topItems = byType
            .map { (name: $0.key, quantity: $0.value.reduce(0) { $0 + $1.quantity }) }
            .sorted { $0.quantity > $1.quantity }
            .prefix(5)
            .map { (name: $0.name, quantity: $0.quantity) }

        do {
            insight = try await IntelligenceService.shared.analyzeAssets(
                characterName: characterName,
                totalStacks: assets.count,
                locationCount: byLocation.keys.count,
                topLocationsByCount: topLocations,
                topItemsByQuantity: topItems
            )
        } catch {
            generationError = "Unable to generate insight. Try again later."
        }
        isGenerating = false
    }
}
