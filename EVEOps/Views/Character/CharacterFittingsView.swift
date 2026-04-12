import SwiftUI

struct ShipEntry: Identifiable, Hashable {
    let itemId: Int
    let typeId: Int
    let typeName: String
    let locationName: String
    let isSingleton: Bool
    var id: Int { itemId }
}

struct CharacterShipGroup {
    let characterName: String
    let ships: [ShipEntry]
}

struct CharacterFittingsView: View {
    @Environment(AccountManager.self) private var accountManager
    @State private var groups: [CharacterShipGroup] = []
    @State private var modulesByShip: [Int: [ESIAsset]] = [:]
    @State private var moduleTypeNames: [Int: String] = [:]
    @State private var isLoading = false
    @State private var error: String?
    @State private var selectedShip: ShipEntry?

    private var isEmpty: Bool { groups.allSatisfy { $0.ships.isEmpty } }

    var body: some View {
        LoadingStateView(isLoading: isLoading, error: error, isEmpty: isEmpty, emptyMessage: "No ships found") {
            HStack(spacing: 0) {
                List(selection: $selectedShip) {
                    ForEach(groups, id: \.characterName) { group in
                        Section(group.characterName) {
                            ForEach(group.ships) { ship in
                                ShipRow(ship: ship)
                                    .tag(ship)
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity)

                if let ship = selectedShip {
                    Divider()
                    ShipDetailPane(
                        ship: ship,
                        modules: modulesByShip[ship.itemId] ?? [],
                        typeNames: moduleTypeNames
                    )
                    .frame(width: 340)
                }
            }
        }
        .navigationTitle("Ships & Fittings")
        .task { isLoading = true; await load() }
    }

    private func load() async {
        error = nil
        var result: [CharacterShipGroup] = []
        var allModulesByShip: [Int: [ESIAsset]] = [:]
        var allModuleTypeIds: Set<Int> = []
        var lastError: Error?

        for account in accountManager.accounts {
            do {
                let token = try await accountManager.validToken(for: account)
                let assets: [ESIAsset] = try await ESIClient.shared.fetchPages(
                    "/characters/\(account.characterID)/assets/", token: token
                )

                let typeIds = Array(Set(assets.map(\.typeId)))
                let types = await UniverseCache.shared.types(ids: typeIds)
                let groupIds = Set(types.values.map(\.groupId))
                let groups = await UniverseCache.shared.groups(ids: groupIds)

                let shipTypeIds = Set(
                    types.values
                        .filter { groups[$0.groupId]?.categoryId == 6 }
                        .map(\.typeId)
                )
                let shipAssets = assets.filter { shipTypeIds.contains($0.typeId) }

                let assetsByLocation = Dictionary(grouping: assets, by: \.locationId)
                for ship in shipAssets where ship.isSingleton {
                    let modules = (assetsByLocation[ship.itemId] ?? []).filter { isSlotModule($0.locationFlag) }
                    if !modules.isEmpty {
                        allModulesByShip[ship.itemId] = modules
                        allModuleTypeIds.formUnion(modules.map(\.typeId))
                    }
                }

                let locationIds = Array(Set(shipAssets.map(\.locationId)))
                var locationNames: [Int: String] = [:]
                await withTaskGroup(of: (Int, String).self) { group in
                    for locId in locationIds {
                        group.addTask {
                            (locId, await NameResolver.shared.resolveLocation(id: locId, token: token))
                        }
                    }
                    for await (locId, name) in group {
                        locationNames[locId] = name
                    }
                }

                let ships = shipAssets.map { asset in
                    ShipEntry(
                        itemId: asset.itemId,
                        typeId: asset.typeId,
                        typeName: types[asset.typeId]?.name ?? "Ship #\(asset.typeId)",
                        locationName: locationNames[asset.locationId] ?? "#\(asset.locationId)",
                        isSingleton: asset.isSingleton
                    )
                }.sorted { $0.typeName < $1.typeName }

                if !ships.isEmpty {
                    result.append(CharacterShipGroup(characterName: account.characterName, ships: ships))
                }
            } catch { lastError = error }
        }

        let moduleTypes = await UniverseCache.shared.types(ids: Array(allModuleTypeIds))
        moduleTypeNames = moduleTypes.mapValues(\.name)
        modulesByShip = allModulesByShip
        groups = result
        if selectedShip == nil { selectedShip = groups.first?.ships.first }
        if result.isEmpty, let e = lastError { self.error = e.localizedDescription }
        isLoading = false
    }

    private func isSlotModule(_ flag: String) -> Bool {
        flag.hasPrefix("HiSlot") || flag.hasPrefix("MedSlot") || flag.hasPrefix("LoSlot") ||
        flag.hasPrefix("RigSlot") || flag.hasPrefix("SubSystem") ||
        flag == "DroneBay" || flag == "FighterBay" || flag == "Cargo"
    }
}

// MARK: - Ship List Row

struct ShipRow: View {
    let ship: ShipEntry

    var body: some View {
        HStack(spacing: 12) {
            AsyncImage(url: EVEImageURL.typeRender(ship.typeId, size: 256)) { image in
                image.resizable().aspectRatio(contentMode: .fill)
            } placeholder: {
                RoundedRectangle(cornerRadius: 6).fill(.quaternary)
            }
            .frame(width: 52, height: 52)
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .strokeBorder(.white.opacity(0.08), lineWidth: 0.5)
            )

            VStack(alignment: .leading, spacing: 3) {
                Text(ship.typeName).font(.subheadline.bold())
                Text(ship.locationName)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                HStack(spacing: 4) {
                    if ship.isSingleton {
                        Label("Assembled", systemImage: "checkmark.circle.fill")
                            .font(.caption2)
                            .foregroundStyle(.green)
                            .labelStyle(.titleAndIcon)
                    } else {
                        Label("Packaged", systemImage: "shippingbox")
                            .font(.caption2)
                            .foregroundStyle(.orange)
                            .labelStyle(.titleAndIcon)
                    }
                }
            }
        }
        .padding(.vertical, 3)
    }
}

// MARK: - Ship Detail Pane

struct ShipDetailPane: View {
    let ship: ShipEntry
    let modules: [ESIAsset]
    let typeNames: [Int: String]

    var body: some View {
        VStack(spacing: 0) {
            // Hero ship render
            ZStack(alignment: .bottomLeading) {
                AsyncImage(url: EVEImageURL.typeRender(ship.typeId, size: 512)) { image in
                    image.resizable().aspectRatio(contentMode: .fill)
                } placeholder: {
                    Rectangle().fill(
                        LinearGradient(
                            colors: [Color(.darkGray).opacity(0.4), .black.opacity(0.6)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                }
                .frame(height: 160)
                .clipped()

                // Gradient overlay for readability
                LinearGradient(
                    stops: [
                        .init(color: .clear, location: 0.0),
                        .init(color: .black.opacity(0.75), location: 1.0)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )

                VStack(alignment: .leading, spacing: 3) {
                    Text(ship.typeName)
                        .font(.headline)
                        .foregroundStyle(.white)
                    Label(ship.locationName, systemImage: "mappin.circle.fill")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.75))
                        .lineLimit(1)
                }
                .padding(12)
            }
            .frame(height: 160)

            Divider()

            if !ship.isSingleton {
                VStack(spacing: 10) {
                    Image(systemName: "shippingbox")
                        .font(.largeTitle)
                        .foregroundStyle(.tertiary)
                    Text("Ship is packaged")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Text("Unpackage the ship in-game to view its fitting.")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .multilineTextAlignment(.center)
                }
                .padding()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if modules.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "wrench.and.screwdriver")
                        .font(.largeTitle)
                        .foregroundStyle(.tertiary)
                    Text("No modules fitted")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Text("This ship has no modules in its fitting slots.")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .multilineTextAlignment(.center)
                }
                .padding()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                CurrentFittingPane(modules: modules, typeNames: typeNames)
            }
        }
    }
}

// MARK: - Fitting Slots Pane

struct CurrentFittingPane: View {
    let modules: [ESIAsset]
    let typeNames: [Int: String]

    private let slotOrder = ["High Slots", "Med Slots", "Low Slots", "Rig Slots", "Subsystems", "Drone Bay", "Fighter Bay", "Cargo"]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                let grouped = Dictionary(grouping: modules) { slotCategory($0.locationFlag) }
                ForEach(slotOrder.filter { grouped[$0] != nil }, id: \.self) { category in
                    GroupBox {
                        LazyVGrid(
                            columns: [GridItem(.flexible()), GridItem(.flexible())],
                            spacing: 6
                        ) {
                            ForEach(grouped[category]!, id: \.itemId) { module in
                                ModuleCell(module: module, name: typeNames[module.typeId])
                            }
                        }
                    } label: {
                        Label(category, systemImage: slotIcon(category))
                            .font(.caption.bold())
                            .foregroundStyle(slotColor(category))
                    }
                }
            }
            .padding(12)
        }
    }

    private func slotCategory(_ flag: String) -> String {
        if flag.hasPrefix("HiSlot") { return "High Slots" }
        if flag.hasPrefix("MedSlot") { return "Med Slots" }
        if flag.hasPrefix("LoSlot") { return "Low Slots" }
        if flag.hasPrefix("RigSlot") { return "Rig Slots" }
        if flag.hasPrefix("SubSystem") { return "Subsystems" }
        if flag == "DroneBay" { return "Drone Bay" }
        if flag == "FighterBay" { return "Fighter Bay" }
        return "Cargo"
    }

    private func slotColor(_ category: String) -> Color {
        switch category {
        case "High Slots":  return .orange
        case "Med Slots":   return .cyan
        case "Low Slots":   return .yellow
        case "Rig Slots":   return .green
        case "Subsystems":  return .purple
        case "Drone Bay":   return .teal
        case "Fighter Bay": return .indigo
        default:            return .secondary
        }
    }

    private func slotIcon(_ category: String) -> String {
        switch category {
        case "High Slots":  return "bolt.fill"
        case "Med Slots":   return "antenna.radiowaves.left.and.right"
        case "Low Slots":   return "shield.lefthalf.filled"
        case "Rig Slots":   return "gearshape.2.fill"
        case "Subsystems":  return "cpu.fill"
        case "Drone Bay":   return "dot.radiowaves.up.forward"
        case "Fighter Bay": return "airplane"
        default:            return "shippingbox.fill"
        }
    }
}

// MARK: - Module Grid Cell

struct ModuleCell: View {
    let module: ESIAsset
    let name: String?

    var body: some View {
        HStack(spacing: 8) {
            AsyncImage(url: EVEImageURL.typeIcon(module.typeId, size: 64)) { image in
                image.resizable()
            } placeholder: {
                RoundedRectangle(cornerRadius: 4).fill(.quaternary)
            }
            .frame(width: 32, height: 32)
            .clipShape(RoundedRectangle(cornerRadius: 4))
            .overlay(
                RoundedRectangle(cornerRadius: 4)
                    .strokeBorder(.white.opacity(0.1), lineWidth: 0.5)
            )

            VStack(alignment: .leading, spacing: 1) {
                Text(name ?? "Type #\(module.typeId)")
                    .font(.caption)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                if module.quantity > 1 {
                    Text("x\(module.quantity)")
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(7)
        .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 7))
    }
}
