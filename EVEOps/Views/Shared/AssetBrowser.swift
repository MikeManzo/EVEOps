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

/// Shared asset browser for both personal and corporation assets. The two only differ
/// in their ESI endpoint, some labels, and whether the AI insight card is shown — all
/// captured by `Kind`. Filtering / grouping / sorting runs off the main thread
/// (`buildAssetSections` in `AssetSectioning.swift`) so "Group by" never blocks the UI.
struct AssetBrowser: View {
    enum Kind {
        case character
        case corporation

        var title: String {
            switch self {
            case .character:   return "Assets"
            case .corporation: return "Corp Assets"
            }
        }

        var emptyMessage: String {
            switch self {
            case .character:   return "No assets found"
            case .corporation: return "No corporation assets found or insufficient permissions"
            }
        }

        var searchPrompt: String {
            switch self {
            case .character:   return "Search assets..."
            case .corporation: return "Search corporation assets..."
            }
        }

        var collapsedDefaultsKey: String {
            switch self {
            case .character:   return "assetCollapsedSections"
            case .corporation: return "corpAssetCollapsedSections"
            }
        }

        var fallbackIcon: String {
            switch self {
            case .character:   return "cube.box.fill"
            case .corporation: return "shippingbox.fill"
            }
        }

        var fallbackIconTint: Color {
            switch self {
            case .character:   return .blue
            case .corporation: return .teal
            }
        }

        var showsAIInsight: Bool { self == .character }

        func endpoint(for account: StoredAccount) -> String {
            switch self {
            case .character:   return "/characters/\(account.characterID)/assets/"
            case .corporation: return "/corporations/\(account.corporationID)/assets/"
            }
        }

        func unknownLocationName(id: Int) -> String {
            switch self {
            case .character:   return "Unknown Location"
            case .corporation: return "Location #\(id)"
            }
        }
    }

    let kind: Kind

    @Environment(AccountManager.self) private var accountManager
    @State private var assets: [ResolvedAsset] = []
    @State private var assetByID: [Int: ResolvedAsset] = [:]
    @State private var sections: [AssetSection] = []
    @State private var isLoading = true
    @State private var error: String?
    @State private var searchText = ""
    @State private var groupMode: AssetGroupMode = .station
    @State private var selectedAssetID: Int?
    @State private var collapsedSections: Set<String>
    @State private var searchDebounce: Task<Void, Never>?
    @State private var saveDebounce: Task<Void, Never>?

    init(kind: Kind) {
        self.kind = kind
        _collapsedSections = State(initialValue: Self.loadCollapsedSections(key: kind.collapsedDefaultsKey))
    }

    var body: some View {
        LoadingStateView(isLoading: isLoading, error: error, isEmpty: assets.isEmpty, emptyMessage: kind.emptyMessage) {
            HStack(spacing: 0) {
                VStack(spacing: 0) {
                    toolbar
                    groupedList
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)

                Divider()
                detailPanel
                    .frame(width: 320)
            }
        }
        .safeAreaInset(edge: .top, spacing: 0) {
            HStack {
                Text(kind.title)
                    .font(.largeTitle.bold())
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(.background)
        }
        .navigationTitle("")
        .task(id: accountManager.selectedCharacterID) {
            assets = []
            assetByID = [:]
            sections = []
            selectedAssetID = nil
            isLoading = true
            await loadAssets()
        }
        .onChange(of: collapsedSections) { saveCollapsedSections() }
        .onChange(of: groupMode) {
            Task { await recomputeSections(regroup: true) }
        }
        .onChange(of: searchText) {
            searchDebounce?.cancel()
            guard !searchText.isEmpty else {
                Task { await recomputeSections() }
                return
            }
            searchDebounce = Task {
                try? await Task.sleep(nanoseconds: 250_000_000)
                guard !Task.isCancelled else { return }
                await recomputeSections()
            }
        }
    }

    // MARK:  Sub-views

    private var toolbar: some View {
        HStack {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField(kind.searchPrompt, text: $searchText)
                .textFieldStyle(.plain)
            Spacer()
            Button(collapsedSections.isEmpty ? "Collapse All" : "Expand All") {
                if collapsedSections.isEmpty {
                    collapsedSections = Set(sections.map(\.key))
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
    }

    private var groupedList: some View {
        List(selection: $selectedAssetID) {
            if kind.showsAIInsight, #available(macOS 26.0, *), IntelligenceService.isSupported {
                AssetAIInsightCard(
                    assets: assets,
                    characterName: accountManager.selectedAccount?.characterName ?? "Character"
                )
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
                .listRowInsets(EdgeInsets(top: 8, leading: 8, bottom: 8, trailing: 8))
                .selectionDisabled()
            }
            ForEach(sections) { section in
                Section {
                    if !collapsedSections.contains(section.key) {
                        ForEach(section.items) { asset in
                            assetRow(asset)
                                .tag(asset.id)
                        }
                    }
                } header: {
                    sectionHeader(section)
                }
            }
        }
        .listStyle(.sidebar)
        .frame(maxHeight: .infinity)
    }

    private func sectionHeader(_ section: AssetSection) -> some View {
        let collapsed = collapsedSections.contains(section.key)
        return Button {
            if collapsed {
                collapsedSections.remove(section.key)
            } else {
                collapsedSections.insert(section.key)
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: collapsed ? "chevron.right" : "chevron.down")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .frame(width: 10)
                Text(section.key)
                    .font(.title3.bold())
                Spacer()
                Text("\(section.count)")
                    .font(.title3.bold())
                    .foregroundStyle(.secondary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func assetRow(_ asset: ResolvedAsset) -> some View {
        HStack(spacing: 8) {
            AsyncImage(url: EVEImageURL.typeIcon(asset.typeId, size: 64)) { phase in
                if let image = phase.image {
                    image.resizable()
                        .frame(width: 28, height: 28)
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                } else {
                    Image(systemName: kind.fallbackIcon)
                        .foregroundStyle(kind.fallbackIconTint)
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

    @ViewBuilder
    private var detailPanel: some View {
        if let id = selectedAssetID, let asset = assetByID[id] {
            AssetDetailView(asset: asset)
        } else {
            Spacer()
        }
    }

    // MARK:  Sectioning

    /// Number of sections past which a fresh grouping opens collapsed. Rendering a
    /// `List` of thousands of expanded sections (every row realized at once) is what
    /// beachballs "By Type"; collapsed headers alone stay cheap.
    private static let autoCollapseThreshold = 40

    /// Rebuilds `sections` off the main thread so "Group by" and search never block the UI.
    /// `regroup` marks a change of grouping key (the picker), which resets collapse state.
    private func recomputeSections(regroup: Bool = false) async {
        let snapshot = assets
        let search = searchText
        let mode = groupMode
        let built = await Task.detached(priority: .userInitiated) {
            buildAssetSections(from: snapshot, search: search, groupMode: mode)
        }.value
        // Drop stale results if inputs changed while we were working.
        guard search == searchText, mode == groupMode else { return }
        if regroup {
            collapsedSections = built.count > Self.autoCollapseThreshold
                ? Set(built.map(\.key))
                : []
        }
        sections = built
    }

    private static func loadCollapsedSections(key: String) -> Set<String> {
        guard let data = UserDefaults.standard.data(forKey: key),
              let decoded = try? JSONDecoder().decode(Set<String>.self, from: data)
        else { return [] }
        return decoded
    }

    /// Debounced so a "By Type" regroup (which can flip thousands of keys at once)
    /// doesn't encode + write on the main thread mid-interaction.
    private func saveCollapsedSections() {
        let snapshot = collapsedSections
        let key = kind.collapsedDefaultsKey
        saveDebounce?.cancel()
        saveDebounce = Task {
            try? await Task.sleep(nanoseconds: 400_000_000)
            guard !Task.isCancelled else { return }
            let data = await Task.detached(priority: .utility) {
                try? JSONEncoder().encode(snapshot)
            }.value
            if let data { UserDefaults.standard.set(data, forKey: key) }
        }
    }

    // MARK:  Data loading

    private func loadAssets() async {
        guard let account = accountManager.selectedAccount else { return }
        isLoading = true
        do {
            let token = try await accountManager.validToken(for: account)
            let rawAssets: [ESIAsset] = try await ESIClient.shared.fetchPages(
                kind.endpoint(for: account), token: token
            )

            let typeIDs = Array(Set(rawAssets.map(\.typeId)))
            let typeNames = await NameResolver.shared.resolve(ids: typeIDs)

            // Map itemId -> typeName so nested containers (ships, cans) resolve to a readable name.
            let itemIdToType: [Int: String] = Dictionary(
                rawAssets.map { ($0.itemId, typeNames[$0.typeId] ?? "Container") },
                uniquingKeysWith: { first, _ in first }
            )

            // Resolve location names: stations, structures, or parent containers.
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
                    locationName: locationNames[asset.locationId] ?? kind.unknownLocationName(id: asset.locationId),
                    locationFlag: asset.locationFlag,
                    isBlueprintCopy: asset.isBlueprintCopy ?? false,
                    isSingleton: asset.isSingleton
                )
            }
            assetByID = Dictionary(assets.map { ($0.itemId, $0) }, uniquingKeysWith: { first, _ in first })
            if selectedAssetID == nil { selectedAssetID = assets.first?.itemId }
            await recomputeSections()
        } catch {
            self.error = error.localizedDescription
        }
        isLoading = false
    }
}

// MARK:  Supporting types

nonisolated enum AssetGroupMode: CaseIterable, Sendable {
    case station, type

    var label: String {
        switch self {
        case .station: return "By Station"
        case .type:    return "By Type"
        }
    }
}

nonisolated struct ResolvedAsset: Identifiable, Hashable, Sendable {
    let itemId: Int
    let typeId: Int
    let typeName: String
    let quantity: Int
    let locationId: Int
    let locationName: String
    var locationFlag: String = ""
    var isBlueprintCopy: Bool = false
    var isSingleton: Bool = false
    var customName: String? = nil

    var id: Int { itemId }
}

// MARK:  Asset AI Insight Card

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
