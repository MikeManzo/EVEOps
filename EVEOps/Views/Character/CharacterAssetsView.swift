import SwiftUI

struct CharacterAssetsView: View {
    @Environment(AccountManager.self) private var accountManager
    @State private var assets: [ResolvedAsset] = []
    @State private var isLoading = true
    @State private var error: String?
    @State private var searchText = ""
    @State private var groupByLocation = true
    @State private var selectedAsset: ResolvedAsset?

    var body: some View {
        LoadingStateView(isLoading: isLoading, error: error, isEmpty: assets.isEmpty, emptyMessage: "No assets found") {
            HSplitView {
                VStack(spacing: 0) {
                    HStack {
                        Image(systemName: "magnifyingglass")
                            .foregroundStyle(.secondary)
                        TextField("Search assets...", text: $searchText)
                            .textFieldStyle(.plain)
                        Spacer()
                        Toggle("Group by location", isOn: $groupByLocation)
                    }
                    .padding(10)
                    .background(.bar)

                    if groupByLocation {
                        groupedList
                    } else {
                        flatList
                    }
                }
                .frame(minWidth: 300)

                if let selected = selectedAsset {
                    AssetDetailView(asset: selected)
                } else {
                    VStack {
                        Image(systemName: "cube.box")
                            .font(.largeTitle)
                            .foregroundStyle(.quaternary)
                        Text("Select an asset to view details")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .frame(minWidth: 280, idealWidth: 320)
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
        let grouped = Dictionary(grouping: filteredAssets, by: \.locationName)
        return List(selection: $selectedAsset) {
            ForEach(grouped.keys.sorted(), id: \.self) { location in
                Section(location) {
                    ForEach(grouped[location] ?? []) { asset in
                        assetRow(asset)
                            .tag(asset)
                    }
                }
            }
        }
    }

    private var flatList: some View {
        List(filteredAssets, selection: $selectedAsset) { asset in
            assetRow(asset)
                .tag(asset)
        }
    }

    private func assetRow(_ asset: ResolvedAsset) -> some View {
        HStack(spacing: 8) {
            AsyncImage(url: EVEImageURL.typeIcon(asset.typeId, size: 64)) { phase in
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
                HStack(spacing: 4) {
                    Text(asset.typeName)
                    if asset.isBlueprintCopy {
                        Text("(BPC)")
                            .font(.caption2)
                            .foregroundStyle(.orange)
                    }
                }
                if !groupByLocation {
                    Text(asset.locationName)
                        .font(.caption)
                        .foregroundStyle(.secondary)
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
        } catch {
            self.error = error.localizedDescription
        }
        isLoading = false
    }
}
