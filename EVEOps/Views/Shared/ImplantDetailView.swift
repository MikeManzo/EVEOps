import SwiftUI

struct ImplantDetailView: View {
    let implant: ResolvedImplant
    @State private var typeInfo: ESIType?
    @State private var groupName: String?
    @State private var categoryName: String?

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                headerSection

                VStack(alignment: .leading, spacing: 16) {
                    typeInfoSection

                    if let desc = typeInfo?.description, !desc.isEmpty {
                        Divider()
                        descriptionSection(desc)
                    }
                }
                .padding()
            }
        }
        .frame(minWidth: 280, idealWidth: 320)
        .task(id: implant.typeId) { await loadTypeInfo() }
    }

    // MARK:  Header

    private var headerSection: some View {
        ZStack(alignment: .bottom) {
            Rectangle()
                .fill(Color(white: 0.1))
                .frame(height: 200)
                .overlay {
                    AsyncImage(url: EVEImageURL.typeIcon(implant.typeId, size: 256)) { phase in
                        if let image = phase.image {
                            image.resizable()
                                .interpolation(.high)
                                .frame(width: 128, height: 128)
                        } else if phase.error != nil {
                            Image(systemName: "brain.head.profile")
                                .font(.system(size: 48))
                                .foregroundStyle(.quaternary)
                        } else {
                            ProgressView().scaleEffect(0.8)
                        }
                    }
                }

            VStack(alignment: .leading, spacing: 2) {
                Text(implant.name)
                    .font(.headline)
                    .foregroundStyle(.white)
                if let groupName {
                    Text(groupName)
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.7))
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .background(.ultraThinMaterial.opacity(0.8))
        }
    }

    // MARK:  Type Info

    private var typeInfoSection: some View {
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
            if let volume = typeInfo?.volume, volume > 0 {
                infoRow(label: "Volume", value: String(format: "%.2f m\u{00B3}", volume))
            }
            if let mass = typeInfo?.mass, mass > 0 {
                infoRow(label: "Mass", value: formatLargeNumber(mass) + " kg")
            }
            infoRow(label: "Type ID", value: "\(implant.typeId)")
        }
    }

    // MARK:  Description

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

    // MARK:  Helpers

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
        text = text.replacingOccurrences(of: "<br>", with: "\n", options: .caseInsensitive)
        text = text.replacingOccurrences(of: "<br/>", with: "\n", options: .caseInsensitive)
        text = text.replacingOccurrences(of: "<br />", with: "\n", options: .caseInsensitive)
        while let start = text.range(of: "<"), let end = text.range(of: ">", range: start.upperBound..<text.endIndex) {
            text.removeSubrange(start.lowerBound...end.lowerBound)
        }
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK:  Data Loading

    private func loadTypeInfo() async {
        guard let type = await UniverseCache.shared.type(id: implant.typeId) else { return }
        typeInfo = type

        if let group = await UniverseCache.shared.group(id: type.groupId) {
            groupName = group.name
            let category: ESICategory? = try? await ESIClient.shared.fetch("/universe/categories/\(group.categoryId)/")
            categoryName = category?.name
        }
    }
}
