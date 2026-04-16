import SwiftUI

struct StationDetailView: View {
    let entry: StationEntry
    var onNavigateToMarket: (() -> Void)? = nil

    @Environment(AccountManager.self) private var accountManager
    @Environment(DashboardPrefetcher.self) private var prefetcher

    @State private var stationType: ESIType?
    @State private var ownerName: String?
    @State private var jumpCount: Int?
    @State private var assetsAtStation: [StationAsset] = []
    @State private var autopilotMessage: String?
    @State private var isSettingAutopilot = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                // MARK: Header
                header

                Divider()

                // MARK: Action Bar
                actionBar

                Divider()

                VStack(alignment: .leading, spacing: 20) {
                    // Location
                    locationSection

                    // Services
                    if let services = entry.station.services, !services.isEmpty {
                        Divider()
                        servicesSection(services)
                    }

                    // Assets at this station
                    if !assetsAtStation.isEmpty {
                        Divider()
                        assetsSection
                    }

                    // Station details
                    Divider()
                    detailsSection
                }
                .padding(16)
            }
        }
        .background(.regularMaterial)
        .task(id: entry.station.stationId) {
            // Reset state for new station
            autopilotMessage = nil
            jumpCount = nil
            assetsAtStation = []
            stationType = nil
            ownerName = nil

            await withTaskGroup(of: Void.self) { group in
                group.addTask { await loadDetails() }
                group.addTask { await loadJumpCount() }
                group.addTask { await loadAssetsAtStation() }
            }
        }
    }

    // MARK: - Action Bar

    private var actionBar: some View {
        HStack(spacing: 8) {
            if let account = accountManager.selectedAccount, !account.isTokenExpired {
                Button {
                    Task { await setAutopilot(clear: true) }
                } label: {
                    Label(isSettingAutopilot ? "Setting…" : "Set Destination", systemImage: "paperplane.fill")
                        .font(.caption.weight(.semibold))
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .disabled(isSettingAutopilot)

                Button {
                    Task { await setAutopilot(clear: false) }
                } label: {
                    Label("Add Waypoint", systemImage: "plus.circle")
                        .font(.caption.weight(.semibold))
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(isSettingAutopilot)
            }

            if let onNavigateToMarket,
               entry.station.services?.contains("market") == true {
                Button(action: onNavigateToMarket) {
                    Label("Market Browser", systemImage: "cart.fill")
                        .font(.caption.weight(.semibold))
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }

            Spacer()

            if let msg = autopilotMessage {
                Label(msg,
                      systemImage: msg.hasPrefix("Destination") || msg.hasPrefix("Waypoint")
                        ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(msg.hasPrefix("Destination") || msg.hasPrefix("Waypoint") ? .green : .orange)
                    .lineLimit(1)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.bar)
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

                    // Jump count badge
                    if let jumps = jumpCount {
                        if jumps == 0 {
                            Text("current")
                                .font(.caption.bold())
                                .foregroundStyle(.green)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(.green.opacity(0.12), in: Capsule())
                        } else {
                            Text("\(jumps) jump\(jumps == 1 ? "" : "s")")
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(.secondary.opacity(0.1), in: Capsule())
                        }
                    }
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

    // MARK: - Assets At Station

    private var assetsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(
                "Your Assets Here (\(assetsAtStation.count) type\(assetsAtStation.count == 1 ? "" : "s"))",
                systemImage: "shippingbox.fill"
            )
            .font(.subheadline.bold())
            .foregroundStyle(.indigo)

            VStack(alignment: .leading, spacing: 4) {
                ForEach(assetsAtStation.prefix(6)) { asset in
                    HStack(spacing: 8) {
                        AsyncImage(url: EVEImageURL.typeIcon(asset.typeId, size: 64)) { phase in
                            if let image = phase.image {
                                image.resizable()
                                    .frame(width: 20, height: 20)
                                    .clipShape(RoundedRectangle(cornerRadius: 3))
                            } else {
                                RoundedRectangle(cornerRadius: 3)
                                    .fill(.quaternary)
                                    .frame(width: 20, height: 20)
                            }
                        }
                        Text(asset.typeName)
                            .font(.caption)
                            .lineLimit(1)
                        if asset.isBlueprintCopy {
                            Text("BPC")
                                .font(.caption2)
                                .foregroundStyle(.orange)
                        }
                        Spacer()
                        Text("×\(asset.quantity)")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                }
                if assetsAtStation.count > 6 {
                    Text("…and \(assetsAtStation.count - 6) more")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .padding(.top, 2)
                }
            }
        }
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
        case "market":                   return ("Market",         "cart.fill",                   .blue)
        case "reprocessing-plant":       return ("Reprocessing",   "arrow.3.trianglepath",        .orange)
        case "repair-facilities":        return ("Repair",         "wrench.and.screwdriver.fill", .green)
        case "fitting":                  return ("Fitting",        "gearshape.2.fill",            .purple)
        case "cloning":                  return ("Cloning",        "person.2.fill",               .pink)
        case "factory", "manufacturing": return ("Manufacturing",  "hammer.fill",                 .yellow)
        case "labratory", "research":    return ("Research",       "flask.fill",                  .cyan)
        case "insurance":                return ("Insurance",      "shield.fill",                 .mint)
        case "docking":                  return ("Docking",        "arrow.down.to.line",          .teal)
        case "office-rental":            return ("Offices",        "building.fill",               .indigo)
        case "loyalty-point-store":      return ("LP Store",       "star.fill",                   Color(red: 0.9, green: 0.75, blue: 0.2))
        case "navy-offices":             return ("Navy",           "flag.fill",                   .red)
        case "security-offices":         return ("Security",       "lock.shield.fill",            .gray)
        case "bounty-missions":          return ("Bounties",       "target",                      .red)
        case "assay-office":             return ("Assay",          "scalemass.fill",              .brown)
        case "storage":                  return ("Storage",        "archivebox.fill",             .gray)
        default:
            let label = service.split(separator: "-").map { $0.capitalized }.joined(separator: " ")
            return (label, "circle.fill", .gray)
        }
    }

    // MARK: - Autopilot

    private func setAutopilot(clear: Bool) async {
        guard let account = accountManager.selectedAccount else { return }
        isSettingAutopilot = true
        autopilotMessage = nil
        do {
            let token = try await accountManager.validToken(for: account)
            try await ESIClient.shared.postAction(
                "/ui/autopilot/waypoint/",
                token: token,
                queryItems: [
                    URLQueryItem(name: "add_to_beginning", value: "false"),
                    URLQueryItem(name: "clear_other_waypoints", value: clear ? "true" : "false"),
                    URLQueryItem(name: "destination_id", value: "\(entry.station.stationId)")
                ]
            )
            autopilotMessage = clear ? "Destination set in EVE client." : "Waypoint added in EVE client."
        } catch ESIError.unauthorized {
            autopilotMessage = "Needs esi-ui.write_waypoint.v1 scope."
        } catch {
            autopilotMessage = error.localizedDescription
        }
        isSettingAutopilot = false
    }

    // MARK: - Data Loading

    private func loadDetails() async {
        async let typeTask = UniverseCache.shared.type(id: entry.station.typeId)
        async let ownerTask: String? = {
            guard let ownerId = entry.station.owner else { return nil }
            let names = await NameResolver.shared.resolve(ids: [ownerId])
            return names[ownerId]
        }()

        let (type, owner) = await (typeTask, ownerTask)
        stationType = type
        ownerName = owner
    }

    private func loadJumpCount() async {
        guard let account = accountManager.selectedAccount,
              let data = prefetcher.data(for: account.characterID) else { return }
        let originSystemId = data.location.solarSystemId
        if originSystemId == entry.systemId {
            jumpCount = 0
            return
        }
        do {
            let route: [Int] = try await ESIClient.shared.fetch(
                "/route/\(originSystemId)/\(entry.systemId)/",
                queryItems: [URLQueryItem(name: "flag", value: "shortest")]
            )
            jumpCount = max(0, route.count - 1)
        } catch {
            // No route or unreachable — leave nil
        }
    }

    private func loadAssetsAtStation() async {
        guard let account = accountManager.selectedAccount, !account.isTokenExpired else { return }
        do {
            let token = try await accountManager.validToken(for: account)
            let rawAssets: [ESIAsset] = try await ESIClient.shared.fetchPages(
                "/characters/\(account.characterID)/assets/", token: token
            )
            let atStation = rawAssets.filter {
                $0.locationId == entry.station.stationId && $0.locationType == "station"
            }
            guard !atStation.isEmpty else { return }

            let typeIds = Array(Set(atStation.map(\.typeId)))
            let typeNames = await NameResolver.shared.resolve(ids: typeIds)

            // Aggregate quantity by typeId
            var byType: [Int: (name: String, qty: Int, isBPC: Bool)] = [:]
            for asset in atStation {
                let name = typeNames[asset.typeId] ?? "Unknown Type"
                let isBPC = asset.isBlueprintCopy ?? false
                if let existing = byType[asset.typeId] {
                    byType[asset.typeId] = (existing.name, existing.qty + asset.quantity, existing.isBPC || isBPC)
                } else {
                    byType[asset.typeId] = (name, asset.quantity, isBPC)
                }
            }
            assetsAtStation = byType.map { typeId, info in
                StationAsset(typeId: typeId, typeName: info.name, quantity: info.qty, isBlueprintCopy: info.isBPC)
            }.sorted { $0.typeName < $1.typeName }
        } catch {
            // Silently fail — assets are optional context
        }
    }
}

// MARK: - Supporting Types

private struct StationAsset: Identifiable {
    let typeId: Int
    let typeName: String
    let quantity: Int
    let isBlueprintCopy: Bool
    var id: Int { typeId }
}
