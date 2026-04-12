import SwiftUI

struct CharacterAssetsView: View {
    @Environment(AccountManager.self) private var accountManager
    @State private var assets: [ResolvedAsset] = []
    @State private var isLoading = true
    @State private var error: String?
    @State private var searchText = ""
    @State private var groupMode: AssetGroupMode = .station
    @State private var selectedAsset: ResolvedAsset?

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
                .frame(maxWidth: .infinity)

                if selectedAsset != nil {
                    Divider()
                    AssetDetailView(asset: selectedAsset!)
                        .frame(width: 320)
                }
            }
        }
        .navigationTitle("Assets")
        .task { await loadAssets() }
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
        return List(selection: $selectedAsset) {
            ForEach(grouped.keys.sorted(), id: \.self) { sectionKey in
                Section(sectionKey) {
                    ForEach(grouped[sectionKey] ?? []) { asset in
                        assetRow(asset)
                            .tag(asset)
                    }
                }
            }
        }
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
