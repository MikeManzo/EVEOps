import SwiftUI

struct StationDetailView: View {
    let entry: StationEntry

    @State private var stationType: ESIType?
    @State private var ownerName: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                // MARK: Header
                header

                Divider()

                VStack(alignment: .leading, spacing: 20) {
                    // Location
                    locationSection

                    // Services
                    if let services = entry.station.services, !services.isEmpty {
                        Divider()
                        servicesSection(services)
                    }

                    // Station details
                    Divider()
                    detailsSection
                }
                .padding(16)
            }
        }
        .background(.regularMaterial)
        .task(id: entry.station.stationId) { await loadDetails() }
    }

    // MARK: - Header

    private var header: some View {
        ZStack(alignment: .bottomLeading) {
            // Station type render as banner
            AsyncImage(url: EVEImageURL.typeRender(entry.station.typeId, size: 1024)) { phase in
                if let image = phase.image {
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(height: 120)
                        .clipped()
                } else {
                    Rectangle()
                        .fill(Color(white: 0.08))
                        .frame(height: 120)
                }
            }

            LinearGradient(
                colors: [.clear, .black.opacity(0.75)],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: 80)
            .frame(maxHeight: .infinity, alignment: .bottom)

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    // Station type icon
                    AsyncImage(url: EVEImageURL.typeIcon(entry.station.typeId, size: 256)) { phase in
                        if let image = phase.image {
                            image.resizable()
                                .frame(width: 36, height: 36)
                                .clipShape(RoundedRectangle(cornerRadius: 6))
                        } else {
                            RoundedRectangle(cornerRadius: 6)
                                .fill(.quaternary)
                                .frame(width: 36, height: 36)
                        }
                    }

                    VStack(alignment: .leading, spacing: 2) {
                        Text(entry.station.name)
                            .font(.headline)
                            .foregroundStyle(.white)
                            .lineLimit(2)
                        if let typeName = stationType?.name {
                            Text(typeName)
                                .font(.caption)
                                .foregroundStyle(.white.opacity(0.7))
                        }
                    }
                }
            }
            .padding(12)
        }
    }

    // MARK: - Location

    private var locationSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Location", systemImage: "location.fill")
                .font(.subheadline.bold())
                .foregroundStyle(.blue)

            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Circle()
                        .fill(securityColor(entry.securityStatus))
                        .frame(width: 8, height: 8)
                    Text(entry.systemName)
                        .font(.body.bold())
                    Text(String(format: "%.1f", entry.securityStatus))
                        .font(.caption.bold().monospacedDigit())
                        .foregroundStyle(securityColor(entry.securityStatus))
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(securityColor(entry.securityStatus).opacity(0.15), in: Capsule())
                }

                infoRow("Constellation", entry.constellationName)

                if let ownerName {
                    infoRow("Owner", ownerName)
                }
            }
        }
    }

    // MARK: - Services

    private func servicesSection(_ services: [String]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Services", systemImage: "building.2.fill")
                .font(.subheadline.bold())
                .foregroundStyle(.teal)

            let columns = [GridItem(.flexible()), GridItem(.flexible())]
            LazyVGrid(columns: columns, alignment: .leading, spacing: 8) {
                ForEach(services.sorted(), id: \.self) { service in
                    serviceBadge(service)
                }
            }
        }
    }

    private func serviceBadge(_ service: String) -> some View {
        let info = serviceInfo(service)
        return HStack(spacing: 6) {
            Image(systemName: info.icon)
                .font(.caption)
                .foregroundStyle(info.color)
                .frame(width: 16)
            Text(info.label)
                .font(.caption)
                .foregroundStyle(.primary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(info.color.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))
    }

    // MARK: - Details

    private var detailsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Station Details", systemImage: "info.circle.fill")
                .font(.subheadline.bold())
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 6) {
                if let efficiency = entry.station.reprocessingEfficiency,
                   entry.station.services?.contains("reprocessing-plant") == true {
                    statRow(
                        icon: "arrow.3.trianglepath",
                        color: .orange,
                        label: "Reprocessing",
                        value: String(format: "%.0f%%", efficiency * 100)
                    )
                }

                if let take = entry.station.reprocessingStationsTake,
                   entry.station.services?.contains("reprocessing-plant") == true {
                    statRow(
                        icon: "percent",
                        color: .orange,
                        label: "Station Take",
                        value: String(format: "%.1f%%", take * 100)
                    )
                }

                if let cost = entry.station.officeRentalCost, cost > 0 {
                    statRow(
                        icon: "building.fill",
                        color: .indigo,
                        label: "Office Rental",
                        value: formatISK(cost) + " /wk"
                    )
                }

                if let vol = entry.station.maxDockableShipVolume, vol > 0 {
                    statRow(
                        icon: "arrow.up.backward.and.arrow.down.forward",
                        color: .purple,
                        label: "Max Ship",
                        value: String(format: "%.0f m³", vol)
                    )
                }
            }
        }
    }

    // MARK: - Helpers

    private func infoRow(_ label: String, _ value: String) -> some View {
        HStack(spacing: 6) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.tertiary)
                .frame(width: 88, alignment: .trailing)
            Text(value)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func statRow(icon: String, color: Color, label: String, value: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.caption)
                .foregroundStyle(color)
                .frame(width: 16)
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .font(.caption.monospacedDigit())
                .foregroundStyle(.primary)
        }
    }

    private func securityColor(_ value: Double) -> Color {
        switch value {
        case 0.9...: return .cyan
        case 0.7..<0.9: return .green
        case 0.5..<0.7: return .yellow
        case 0.3..<0.5: return .orange
        case 0.1..<0.3: return Color(red: 1, green: 0.5, blue: 0)
        default: return .red
        }
    }

    private func formatISK(_ value: Double) -> String {
        if value >= 1_000_000_000 { return String(format: "%.1fB", value / 1_000_000_000) }
        if value >= 1_000_000     { return String(format: "%.1fM", value / 1_000_000) }
        if value >= 1_000         { return String(format: "%.1fK", value / 1_000) }
        return String(format: "%.0f", value)
    }

    private func serviceInfo(_ service: String) -> (label: String, icon: String, color: Color) {
        switch service {
        case "market":                return ("Market",         "cart.fill",                   .blue)
        case "reprocessing-plant":    return ("Reprocessing",   "arrow.3.trianglepath",        .orange)
        case "repair-facilities":     return ("Repair",         "wrench.and.screwdriver.fill", .green)
        case "fitting":               return ("Fitting",        "gearshape.2.fill",            .purple)
        case "cloning":               return ("Cloning",        "person.2.fill",               .pink)
        case "factory", "manufacturing": return ("Manufacturing","hammer.fill",                .yellow)
        case "labratory", "research": return ("Research",       "flask.fill",                  .cyan)
        case "insurance":             return ("Insurance",      "shield.fill",                 .mint)
        case "docking":               return ("Docking",        "arrow.down.to.line",          .teal)
        case "office-rental":         return ("Offices",        "building.fill",               .indigo)
        case "loyalty-point-store":   return ("LP Store",       "star.fill",                   Color(red: 0.9, green: 0.75, blue: 0.2))
        case "navy-offices":          return ("Navy",           "flag.fill",                   .red)
        case "security-offices":      return ("Security",       "lock.shield.fill",            .gray)
        case "bounty-missions":       return ("Bounties",       "target",                      .red)
        case "assay-office":          return ("Assay",          "scalemass.fill",              .brown)
        case "storage":               return ("Storage",        "archivebox.fill",             .gray)
        default:
            let label = service.split(separator: "-").map { $0.capitalized }.joined(separator: " ")
            return (label, "circle.fill", .gray)
        }
    }

    // MARK: - Data Loading

    private func loadDetails() async {
        async let typeTask = UniverseCache.shared.type(id: entry.station.typeId)
        async let ownerTask: String? = {
            guard let ownerId = entry.station.owner else { return nil }
            let names = await NameResolver.shared.resolve([ownerId])
            return names[ownerId]
        }()

        let (type, owner) = await (typeTask, ownerTask)
        stationType = type
        ownerName = owner
    }
}
