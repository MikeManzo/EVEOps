import SwiftUI

struct AssetDetailView: View {
    let asset: ResolvedAsset
    @State private var typeInfo: ESIType?
    @State private var groupName: String?
    @State private var categoryName: String?
    @State private var marketGroupName: String?
    @State private var isLoading = true

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                // Header: render + icon + name
                headerSection

                VStack(alignment: .leading, spacing: 16) {
                    // Asset-specific info
                    assetInfoSection

                    Divider()

                    // Type attributes
                    if let typeInfo {
                        typeAttributesSection(typeInfo)

                        if let desc = typeInfo.description, !desc.isEmpty {
                            Divider()
                            descriptionSection(desc)
                        }
                    }
                }
                .padding()
            }
        }
        .frame(minWidth: 280, idealWidth: 320)
        .task(id: asset.typeId) { await loadTypeInfo() }
    }

    // MARK: - Header

    private var headerSection: some View {
        ZStack(alignment: .bottom) {
            AsyncImage(url: EVEImageURL.typeRender(asset.typeId, size: 512)) { phase in
                switch phase {
                case .success(let image):
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(maxHeight: 200)
                default:
                    Rectangle()
                        .fill(Color(white: 0.1))
                        .frame(height: 200)
                        .overlay {
                            if isLoading {
                                ProgressView().scaleEffect(0.8)
                            } else {
                                Image(systemName: "cube.box.fill")
                                    .font(.largeTitle)
                                    .foregroundStyle(.quaternary)
                            }
                        }
                }
            }

            // Name overlay at bottom
            HStack(spacing: 10) {
                AsyncImage(url: EVEImageURL.typeIcon(asset.typeId, size: 64)) { phase in
                    if let image = phase.image {
                        image.resizable()
                            .frame(width: 40, height: 40)
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                    }
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(asset.typeName)
                        .font(.headline)
                        .foregroundStyle(.white)
                    if let groupName {
                        Text(groupName)
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.7))
                    }
                }
                Spacer()
            }
            .padding(12)
            .background(.ultraThinMaterial.opacity(0.8))
        }
    }

    // MARK: - Asset Info

    private var assetInfoSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Asset Details")
                .font(.subheadline.bold())
                .foregroundStyle(.secondary)

            infoRow(label: "Quantity", value: "\(asset.quantity)")
            infoRow(label: "Location", value: asset.locationName)
            infoRow(label: "Location Flag", value: formatLocationFlag(asset.locationFlag))

            if asset.isBlueprintCopy {
                infoRow(label: "Blueprint", value: "Copy (BPC)")
            }
            if asset.isSingleton {
                infoRow(label: "Assembled", value: "Yes")
            }

            infoRow(label: "Type ID", value: "\(asset.typeId)")
            infoRow(label: "Item ID", value: "\(asset.itemId)")
        }
    }

    // MARK: - Type Attributes

    private func typeAttributesSection(_ type: ESIType) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Type Information")
                .font(.subheadline.bold())
                .foregroundStyle(.secondary)

            if let categoryName {
                infoRow(label: "Category", value: categoryName)
            }
            if let groupName {
                infoRow(label: "Group", value: groupName)
            }
            if let marketGroupName {
                infoRow(label: "Market Group", value: marketGroupName)
            }
            if let volume = type.volume, volume > 0 {
                infoRow(label: "Volume", value: String(format: "%.2f m\u{00B3}", volume))
            }
            if let packagedVolume = type.packagedVolume, packagedVolume > 0, packagedVolume != type.volume {
                infoRow(label: "Packaged Volume", value: String(format: "%.2f m\u{00B3}", packagedVolume))
            }
            if let mass = type.mass, mass > 0 {
                infoRow(label: "Mass", value: formatLargeNumber(mass) + " kg")
            }
            if let capacity = type.capacity, capacity > 0 {
                infoRow(label: "Capacity", value: String(format: "%.0f m\u{00B3}", capacity))
            }
            if let radius = type.radius, radius > 0 {
                infoRow(label: "Radius", value: formatLargeNumber(radius) + " m")
            }
            if let portionSize = type.portionSize, portionSize > 1 {
                infoRow(label: "Portion Size", value: "\(portionSize)")
            }

            // Total volume for stacked items
            if asset.quantity > 1, let vol = type.packagedVolume ?? type.volume, vol > 0 {
                let total = vol * Double(asset.quantity)
                infoRow(label: "Total Volume", value: String(format: "%.2f m\u{00B3}", total))
            }
        }
    }

    // MARK: - Description

    private func descriptionSection(_ description: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Description")
                .font(.subheadline.bold())
                .foregroundStyle(.secondary)

            Text(stripHTML(description))
                .font(.caption)
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
        }
    }

    // MARK: - Helpers

    private func infoRow(label: String, value: String) -> some View {
        HStack(alignment: .top) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 110, alignment: .trailing)
            Text(value)
                .font(.caption)
                .textSelection(.enabled)
            Spacer()
        }
    }

    private func formatLocationFlag(_ flag: String) -> String {
        // Convert camelCase ESI flags to readable text
        switch flag {
        case "Hangar": return "Hangar"
        case "AssetSafety": return "Asset Safety"
        case "Deliveries": return "Deliveries"
        case "HangarAll": return "Hangar (All)"
        case "Cargo": return "Cargo Hold"
        case "DroneBay": return "Drone Bay"
        case "FighterBay": return "Fighter Bay"
        case "FleetHangar": return "Fleet Hangar"
        case "ShipHangar": return "Ship Hangar"
        case "SpecializedOreHold": return "Ore Hold"
        case "SpecializedFuelBay": return "Fuel Bay"
        case "SpecializedAmmoHold": return "Ammo Hold"
        case "SpecializedMineralHold": return "Mineral Hold"
        case "SpecializedSalvageHold": return "Salvage Hold"
        case "SpecializedShipHold": return "Ship Hold"
        case "SpecializedSmallShipHold": return "Small Ship Hold"
        case "SpecializedMediumShipHold": return "Medium Ship Hold"
        case "SpecializedLargeShipHold": return "Large Ship Hold"
        case "SpecializedIndustrialShipHold": return "Industrial Ship Hold"
        case "SpecializedCommandCenterHold": return "Command Center Hold"
        case "SpecializedPlanetaryCommoditiesHold": return "Planetary Commodities Hold"
        case "SpecializedMaterialBay": return "Material Bay"
        case "CorpSAG1": return "Corp Hangar 1"
        case "CorpSAG2": return "Corp Hangar 2"
        case "CorpSAG3": return "Corp Hangar 3"
        case "CorpSAG4": return "Corp Hangar 4"
        case "CorpSAG5": return "Corp Hangar 5"
        case "CorpSAG6": return "Corp Hangar 6"
        case "CorpSAG7": return "Corp Hangar 7"
        case "CorpDeliveries": return "Corp Deliveries"
        case "Implant": return "Implant"
        case "BoosterBay": return "Booster Bay"
        case "SubSystemSlot0": return "Subsystem Slot 1"
        case "SubSystemSlot1": return "Subsystem Slot 2"
        case "SubSystemSlot2": return "Subsystem Slot 3"
        case "SubSystemSlot3": return "Subsystem Slot 4"
        case "LoSlot0", "LoSlot1", "LoSlot2", "LoSlot3", "LoSlot4", "LoSlot5", "LoSlot6", "LoSlot7":
            let slot = flag.last.map(String.init) ?? "?"
            return "Low Slot \(Int(slot)! + 1)"
        case "MedSlot0", "MedSlot1", "MedSlot2", "MedSlot3", "MedSlot4", "MedSlot5", "MedSlot6", "MedSlot7":
            let slot = flag.last.map(String.init) ?? "?"
            return "Mid Slot \(Int(slot)! + 1)"
        case "HiSlot0", "HiSlot1", "HiSlot2", "HiSlot3", "HiSlot4", "HiSlot5", "HiSlot6", "HiSlot7":
            let slot = flag.last.map(String.init) ?? "?"
            return "High Slot \(Int(slot)! + 1)"
        case "RigSlot0", "RigSlot1", "RigSlot2":
            let slot = flag.last.map(String.init) ?? "?"
            return "Rig Slot \(Int(slot)! + 1)"
        default:
            return flag
        }
    }

    private func formatLargeNumber(_ value: Double) -> String {
        if value >= 1_000_000_000 {
            return String(format: "%.2fB", value / 1_000_000_000)
        } else if value >= 1_000_000 {
            return String(format: "%.2fM", value / 1_000_000)
        } else if value >= 1_000 {
            return String(format: "%.1fK", value / 1_000)
        }
        return String(format: "%.0f", value)
    }

    private func stripHTML(_ html: String) -> String {
        var text = html
        // Replace <br> and <br/> with newlines
        text = text.replacingOccurrences(of: "<br>", with: "\n", options: .caseInsensitive)
        text = text.replacingOccurrences(of: "<br/>", with: "\n", options: .caseInsensitive)
        text = text.replacingOccurrences(of: "<br />", with: "\n", options: .caseInsensitive)
        // Strip remaining tags
        while let start = text.range(of: "<"), let end = text.range(of: ">", range: start.upperBound..<text.endIndex) {
            text.removeSubrange(start.lowerBound...end.lowerBound)
        }
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - Data Loading

    private func loadTypeInfo() async {
        isLoading = true
        do {
            let type: ESIType = try await ESIClient.shared.fetch("/universe/types/\(asset.typeId)/")
            typeInfo = type

            // Load group info
            let group: ESIGroup = try await ESIClient.shared.fetch("/universe/groups/\(type.groupId)/")
            groupName = group.name

            // Load category info
            let category: ESICategory = try await ESIClient.shared.fetch("/universe/categories/\(group.categoryId)/")
            categoryName = category.name

            // Load market group if available
            if let mgID = type.marketGroupId {
                let mg: ESIMarketGroup = try await ESIClient.shared.fetch("/universe/market_groups/\(mgID)/")
                marketGroupName = mg.name
            }
        } catch {
            // Partial info is fine
        }
        isLoading = false
    }
}
