import SwiftUI

// MARK:  Career Agent Type

enum CareerAgentType: String, CaseIterable {
    case industry = "Industry"
    case business = "Business"
    case military = "Military"
    case advancedMilitary = "Soldier of Fortune"
    case exploration = "Exploration"

    var iconName: String {
        switch self {
        case .industry: return "hammer.fill"
        case .business: return "banknote.fill"
        case .military: return "shield.lefthalf.filled"
        case .advancedMilitary: return "flame.fill"
        case .exploration: return "safari.fill"
        }
    }

    var color: Color {
        switch self {
        case .industry: return .orange
        case .business: return .green
        case .military: return .blue
        case .advancedMilitary: return .red
        case .exploration: return .purple
        }
    }

    var description: String {
        switch self {
        case .industry:
            return "Learn the foundations of manufacturing and mining. These agents teach ore refining, blueprint usage, and basic ship production — the backbone of the EVE economy."
        case .business:
            return "Master market trading and hauling. Missions cover reading market orders, running courier contracts, and building wealth through commerce."
        case .military:
            return "Develop combat fundamentals through structured PvE missions. Learn module fitting, engagement ranges, and how to tackle NPC enemies efficiently."
        case .advancedMilitary:
            return "Advanced combat covering fleet tactics, electronic warfare, and specialized roles. Harder missions with better rewards for pilots ready to fight seriously."
        case .exploration:
            return "Discover the universe through probe scanning, hacking, and archaeology. Agents teach data and relic site mechanics, covert navigation, and the secrets of unknown space."
        }
    }
}

// MARK:  Career Faction Data

struct CareerFactionData: Identifiable {
    let id: String
    let name: String
    let factionColor: Color
    /// NPC corporation ID used for the faction logo on the image server
    let factionCorpID: Int
    /// (agent type, system name) pairs — one system per career type
    let systems: [(type: CareerAgentType, systemName: String)]

    static let all: [CareerFactionData] = [
        CareerFactionData(
            id: "caldari",
            name: "Caldari State",
            factionColor: .cyan,
            factionCorpID: 1000035,   // Caldari Navy
            systems: [
                (.industry, "Uitra"),
                (.business, "Kisogo"),
                (.military, "Jouvulen"),
                (.advancedMilitary, "Haajinen"),
                (.exploration, "Akiainavas")
            ]
        ),
        CareerFactionData(
            id: "gallente",
            name: "Gallente Federation",
            factionColor: .teal,
            factionCorpID: 1000046,   // Federation Navy
            systems: [
                (.industry, "Clellinon"),
                (.business, "Trossere"),
                (.military, "Couster"),
                (.advancedMilitary, "Aunia"),
                (.exploration, "Duripant")
            ]
        ),
        CareerFactionData(
            id: "amarr",
            name: "Amarr Empire",
            factionColor: .yellow,
            factionCorpID: 1000096,   // Imperial Navy
            systems: [
                (.industry, "Deepari"),
                (.business, "Conoban"),
                (.military, "Pasha"),
                (.advancedMilitary, "Ardishapur Prime"),
                (.exploration, "Arzad")
            ]
        ),
        CareerFactionData(
            id: "minmatar",
            name: "Minmatar Republic",
            factionColor: .orange,
            factionCorpID: 1000060,   // Republic Fleet
            systems: [
                (.industry, "Embod"),
                (.business, "Hadaugago"),
                (.military, "Malukker"),
                (.advancedMilitary, "Ryddinjorn"),
                (.exploration, "Emolgranlan")
            ]
        )
    ]
}

// MARK:  Resolved System

struct ResolvedCareerSystem {
    let systemID: Int
    let securityStatus: Double
    let securityClass: String?
}

// MARK:  Selected Career Entry

struct SelectedCareerEntry: Equatable {
    let factionID: String
    let agentType: CareerAgentType
    let systemName: String

    static func == (lhs: SelectedCareerEntry, rhs: SelectedCareerEntry) -> Bool {
        lhs.factionID == rhs.factionID && lhs.agentType == rhs.agentType
    }
}

// MARK:  Career Agents View

struct CareerAgentsView: View {
    @Environment(AccountManager.self) private var accountManager

    @State private var resolvedSystems: [String: ResolvedCareerSystem] = [:]
    @State private var isLoading = false
    @State private var loadError: String?
    @State private var selectedEntry: SelectedCareerEntry?

    var body: some View {
        HStack(spacing: 0) {
            // Left: faction list
            ScrollView {
                VStack(spacing: 16) {
                    ForEach(CareerFactionData.all) { faction in
                        factionSection(faction)
                    }

                    if let err = loadError {
                        HStack(spacing: 6) {
                            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                            Text(err)
                        }
                        .font(.caption)
                        .padding(10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(.orange.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
                    }
                }
                .padding()
            }

            // Right: detail pane
            if let entry = selectedEntry,
               let faction = CareerFactionData.all.first(where: { $0.id == entry.factionID }) {
                Divider()
                CareerAgentDetailView(
                    faction: faction,
                    agentType: entry.agentType,
                    systemName: entry.systemName,
                    resolved: resolvedSystems[entry.systemName]
                )
                .frame(width: 300)
            }
        }
        .navigationTitle("Career Agents")
        .task {
            await resolveAllSystems()
        }
    }

    // MARK:  Faction Section

    private func factionSection(_ faction: CareerFactionData) -> some View {
        GroupBox {
            VStack(spacing: 0) {
                ForEach(Array(faction.systems.enumerated()), id: \.offset) { index, entry in
                    agentRow(faction: faction, entry: entry)
                    if index < faction.systems.count - 1 {
                        Divider().padding(.leading, 44)
                    }
                }
            }
        } label: {
            HStack(spacing: 8) {
                AsyncImage(url: EVEImageURL.corporationLogo(faction.factionCorpID, size: 32)) { phase in
                    if let image = phase.image {
                        image.resizable()
                            .frame(width: 20, height: 20)
                            .clipShape(RoundedRectangle(cornerRadius: 4))
                    } else {
                        RoundedRectangle(cornerRadius: 4)
                            .fill(faction.factionColor.opacity(0.3))
                            .frame(width: 20, height: 20)
                    }
                }
                Text(faction.name)
                    .foregroundStyle(faction.factionColor)
                    .font(.headline)
            }
        }
    }

    // MARK:  Agent Row

    @ViewBuilder
    private func agentRow(faction: CareerFactionData, entry: (type: CareerAgentType, systemName: String)) -> some View {
        let resolved = resolvedSystems[entry.systemName]
        let isSelected = selectedEntry?.factionID == faction.id && selectedEntry?.agentType == entry.type

        Button {
            selectedEntry = SelectedCareerEntry(
                factionID: faction.id,
                agentType: entry.type,
                systemName: entry.systemName
            )
        } label: {
            HStack(spacing: 10) {
                Image(systemName: entry.type.iconName)
                    .foregroundStyle(entry.type.color)
                    .frame(width: 22, alignment: .center)

                VStack(alignment: .leading, spacing: 2) {
                    Text(entry.type.rawValue)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.primary)
                    Text(entry.systemName)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                if let resolved {
                    securityBadge(resolved.securityStatus)
                } else if isLoading {
                    ProgressView().scaleEffect(0.6)
                }

                Image(systemName: "chevron.right")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            .padding(.vertical, 8)
            .padding(.horizontal, 4)
            .background(isSelected ? entry.type.color.opacity(0.1) : Color.clear, in: RoundedRectangle(cornerRadius: 6))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK:  Security Badge

    private func securityBadge(_ sec: Double) -> some View {
        Text(String(format: "%.1f", max(0.0, sec)))
            .font(.caption.bold().monospacedDigit())
            .foregroundStyle(careerSecColor(sec))
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(careerSecColor(sec).opacity(0.15), in: Capsule())
    }

    // MARK:  Data Loading

    private func resolveAllSystems() async {
        guard resolvedSystems.isEmpty else { return }
        isLoading = true
        defer { isLoading = false }

        let allNames = CareerFactionData.all.flatMap { $0.systems.map(\.systemName) }

        do {
            let response: ESIIDsResponse = try await ESIClient.shared.post(
                "/universe/ids/",
                body: allNames
            )
            let esiSystems = response.solarSystems ?? []

            await withTaskGroup(of: (String, ResolvedCareerSystem)?.self) { group in
                for esiSystem in esiSystems {
                    group.addTask {
                        guard let details = await UniverseCache.shared.solarSystem(id: esiSystem.id) else { return nil }
                        return (esiSystem.name, ResolvedCareerSystem(
                            systemID: esiSystem.id,
                            securityStatus: details.securityStatus,
                            securityClass: details.securityClass
                        ))
                    }
                }
                for await result in group {
                    if let (name, resolved) = result {
                        resolvedSystems[name] = resolved
                    }
                }
            }
        } catch {
            loadError = "Could not resolve system locations: \(error.localizedDescription)"
        }
    }
}

// MARK:  Career Agent Detail View

struct CareerAgentDetailView: View {
    let faction: CareerFactionData
    let agentType: CareerAgentType
    let systemName: String
    let resolved: ResolvedCareerSystem?

    @Environment(AccountManager.self) private var accountManager

    @State private var constellationName: String?
    @State private var regionName: String?
    @State private var jumpCount: Int?
    @State private var autopilotMessage: String?
    @State private var isSetting = false
    @State private var lpBalance: Int?
    @State private var lpOffers: [ESILPStoreOffer] = []
    @State private var offerTypeNames: [Int: String] = [:]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                header
                Divider()
                actionBar
                Divider()
                VStack(alignment: .leading, spacing: 20) {
                    descriptionSection
                    Divider()
                    locationSection
                    if !lpOffers.isEmpty || lpBalance != nil {
                        Divider()
                        lpStoreSection
                    }
                }
                .padding(16)
            }
        }
        .background(.regularMaterial)
        .task(id: systemName) {
            constellationName = nil
            regionName = nil
            jumpCount = nil
            autopilotMessage = nil
            lpBalance = nil
            lpOffers = []
            offerTypeNames = [:]
            await withTaskGroup(of: Void.self) { group in
                group.addTask { await loadLocationDetails() }
                group.addTask { await loadLPStore() }
            }
        }
    }

    // MARK:  Header

    private var header: some View {
        ZStack(alignment: .bottomLeading) {
            // Faction-colored gradient banner
            LinearGradient(
                colors: [faction.factionColor.opacity(0.5), faction.factionColor.opacity(0.15)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .frame(height: 100)

            // Faction logo watermark
            AsyncImage(url: EVEImageURL.corporationLogo(faction.factionCorpID, size: 256)) { phase in
                if let image = phase.image {
                    image.resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 80, height: 80)
                        .opacity(0.15)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                        .padding(.trailing, 12)
                } else {
                    EmptyView()
                }
            }

            // Title overlay
            HStack(spacing: 10) {
                AsyncImage(url: EVEImageURL.corporationLogo(faction.factionCorpID, size: 64)) { phase in
                    if let image = phase.image {
                        image.resizable()
                            .frame(width: 40, height: 40)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                    } else {
                        RoundedRectangle(cornerRadius: 8)
                            .fill(faction.factionColor.opacity(0.4))
                            .frame(width: 40, height: 40)
                            .overlay {
                                Image(systemName: agentType.iconName)
                                    .foregroundStyle(faction.factionColor)
                            }
                    }
                }

                VStack(alignment: .leading, spacing: 3) {
                    Text(agentType.rawValue)
                        .font(.headline)
                        .foregroundStyle(.primary)
                    Text(faction.name)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(12)
        }
    }

    // MARK:  Action Bar

    private var actionBar: some View {
        HStack(spacing: 8) {
            if accountManager.selectedAccount != nil {
                Button {
                    Task { await setDestination() }
                } label: {
                    Label(isSetting ? "Setting…" : "Set Destination", systemImage: "paperplane.fill")
                        .font(.caption.weight(.semibold))
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .disabled(resolved == nil || isSetting)
            }

            Spacer()

            if let msg = autopilotMessage {
                Label(
                    msg,
                    systemImage: msg.hasPrefix("Destination") ? "checkmark.circle.fill" : "exclamationmark.triangle.fill"
                )
                .font(.caption)
                .foregroundStyle(msg.hasPrefix("Destination") ? .green : .orange)
                .lineLimit(1)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.bar)
    }

    // MARK:  Description

    private var descriptionSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(agentType.rawValue, systemImage: agentType.iconName)
                .font(.subheadline.bold())
                .foregroundStyle(agentType.color)

            Text(agentType.description)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK:  Location

    private var locationSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Location", systemImage: "location.fill")
                .font(.subheadline.bold())
                .foregroundStyle(.blue)

            VStack(alignment: .leading, spacing: 6) {
                // System + security
                HStack(spacing: 6) {
                    if let resolved {
                        Circle()
                            .fill(careerSecColor(resolved.securityStatus))
                            .frame(width: 8, height: 8)
                    }
                    Text(systemName)
                        .font(.body.bold())

                    if let resolved {
                        Text(String(format: "%.1f", max(0.0, resolved.securityStatus)))
                            .font(.caption.bold().monospacedDigit())
                            .foregroundStyle(careerSecColor(resolved.securityStatus))
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(careerSecColor(resolved.securityStatus).opacity(0.15), in: Capsule())

                        if let cls = resolved.securityClass {
                            Text(cls)
                                .font(.caption2.bold())
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, 5)
                                .padding(.vertical, 2)
                                .background(.secondary.opacity(0.1), in: Capsule())
                        }
                    }

                    if let jumps = jumpCount {
                        jumpBadge(jumps)
                    }
                }

                if let constellation = constellationName {
                    infoRow("Constellation", constellation)
                }
                if let region = regionName {
                    infoRow("Region", region)
                }

                if resolved == nil {
                    HStack(spacing: 6) {
                        ProgressView().scaleEffect(0.7)
                        Text("Resolving…").font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    private func jumpBadge(_ jumps: Int) -> some View {
        Group {
            if jumps == 0 {
                Text("current system")
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

    private func infoRow(_ label: String, _ value: String) -> some View {
        HStack(spacing: 6) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.tertiary)
                .frame(width: 80, alignment: .trailing)
            Text(value)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    // MARK:  LP Store Section

    private var lpStoreSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label("Loyalty Store", systemImage: "star.fill")
                    .font(.subheadline.bold())
                    .foregroundStyle(.yellow)
                Spacer()
                if let lp = lpBalance {
                    HStack(spacing: 4) {
                        Image(systemName: "star.circle.fill")
                            .foregroundStyle(.yellow)
                            .font(.caption)
                        Text("\(lp.formatted()) LP")
                            .font(.caption.bold().monospacedDigit())
                            .foregroundStyle(.yellow)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(.yellow.opacity(0.12), in: Capsule())
                }
            }

            if lpOffers.isEmpty {
                HStack(spacing: 6) {
                    ProgressView().scaleEffect(0.7)
                    Text("Loading offers…").font(.caption).foregroundStyle(.secondary)
                }
            } else {
                VStack(spacing: 4) {
                    ForEach(lpOffers.prefix(10)) { offer in
                        lpOfferRow(offer)
                    }
                    if lpOffers.count > 10 {
                        Text("…and \(lpOffers.count - 10) more offers")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                            .padding(.top, 2)
                    }
                }
            }
        }
    }

    private func lpOfferRow(_ offer: ESILPStoreOffer) -> some View {
        let name = offerTypeNames[offer.typeId] ?? "Type \(offer.typeId)"
        let canAfford = lpBalance.map { $0 >= offer.lpCost } ?? false

        return HStack(spacing: 8) {
            AsyncImage(url: EVEImageURL.typeIcon(offer.typeId, size: 64)) { phase in
                if let image = phase.image {
                    image.resizable()
                        .frame(width: 28, height: 28)
                        .clipShape(RoundedRectangle(cornerRadius: 5))
                } else {
                    RoundedRectangle(cornerRadius: 5)
                        .fill(.quaternary)
                        .frame(width: 28, height: 28)
                }
            }

            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 4) {
                    Text(name)
                        .font(.caption)
                        .lineLimit(1)
                    if offer.quantity > 1 {
                        Text("×\(offer.quantity)")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                HStack(spacing: 6) {
                    Text("\(offer.lpCost.formatted()) LP")
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(canAfford ? .yellow : .secondary)
                    if offer.iskCost > 0 {
                        Text("+ \(formatISK(Double(offer.iskCost))) ISK")
                            .font(.caption2.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Spacer()
        }
        .padding(.vertical, 3)
        .padding(.horizontal, 4)
        .background(canAfford ? Color.yellow.opacity(0.04) : Color.clear, in: RoundedRectangle(cornerRadius: 6))
    }

    private func formatISK(_ value: Double) -> String {
        if value >= 1_000_000_000 { return String(format: "%.1fB", value / 1_000_000_000) }
        if value >= 1_000_000     { return String(format: "%.1fM", value / 1_000_000) }
        if value >= 1_000         { return String(format: "%.0fK", value / 1_000) }
        return String(format: "%.0f", value)
    }

    // MARK:  Data Loading

    private func loadLocationDetails() async {
        guard let resolved else { return }

        async let systemTask = UniverseCache.shared.solarSystem(id: resolved.systemID)

        if let system = await systemTask {
            async let constellationTask = UniverseCache.shared.constellation(id: system.constellationId)

            if let constellation = await constellationTask {
                constellationName = constellation.name
                async let regionTask = UniverseCache.shared.region(id: constellation.regionId)
                if let region = await regionTask {
                    regionName = region.name
                }
            }
        }

        await loadJumpCount(to: resolved.systemID)
    }

    private func loadLPStore() async {
        // Fetch LP store offers (public endpoint — no auth required)
        let offers: [ESILPStoreOffer] = (try? await ESIClient.shared.fetch(
            "/loyalty/stores/\(faction.factionCorpID)/offers/"
        )) ?? []

        // Sort by LP cost ascending so cheapest (most accessible) appear first
        let sorted = offers.sorted { $0.lpCost < $1.lpCost }
        lpOffers = sorted

        // Resolve type names for top 10 displayed offers
        let topIDs = sorted.prefix(10).map(\.typeId)
        let resolved = await NameResolver.shared.resolve(ids: Array(topIDs))
        offerTypeNames = resolved

        // Fetch character's LP balance with this corp (requires auth)
        guard let account = accountManager.selectedAccount else { return }
        if let token = try? await accountManager.validToken(for: account) {
            let allLP: [ESILoyaltyPoints] = (try? await ESIClient.shared.fetch(
                "/characters/\(account.characterID)/loyalty/points/",
                token: token
            )) ?? []
            lpBalance = allLP.first(where: { $0.corporationId == faction.factionCorpID })?.loyaltyPoints
        }
    }

    private func loadJumpCount(to destinationSystemID: Int) async {
        guard let account = accountManager.selectedAccount else { return }
        do {
            let token = try await accountManager.validToken(for: account)
            let location: ESICharacterLocation = try await ESIClient.shared.fetch(
                "/characters/\(account.characterID)/location/",
                token: token
            )
            if location.solarSystemId == destinationSystemID {
                jumpCount = 0
            } else {
                let route: [Int] = try await ESIClient.shared.fetch(
                    "/route/\(location.solarSystemId)/\(destinationSystemID)/",
                    queryItems: [URLQueryItem(name: "flag", value: "shortest")]
                )
                jumpCount = max(0, route.count - 1)
            }
        } catch {
            // Jump count is optional context — silently skip
        }
    }

    // MARK:  Autopilot

    private func setDestination() async {
        guard let account = accountManager.selectedAccount,
              let resolved else { return }
        isSetting = true
        autopilotMessage = nil
        do {
            let token = try await accountManager.validToken(for: account)
            try await ESIClient.shared.postAction(
                "/ui/autopilot/waypoint/",
                token: token,
                queryItems: [
                    URLQueryItem(name: "add_to_beginning", value: "false"),
                    URLQueryItem(name: "clear_other_waypoints", value: "true"),
                    URLQueryItem(name: "destination_id", value: "\(resolved.systemID)")
                ]
            )
            autopilotMessage = "Destination set to \(systemName)."
        } catch ESIError.unauthorized {
            autopilotMessage = "Needs esi-ui.write_waypoint.v1 scope."
        } catch {
            autopilotMessage = error.localizedDescription
        }
        isSetting = false
    }
}

// MARK:  Security Color

private func careerSecColor(_ status: Double) -> Color {
    switch status {
    case 0.9...: return Color(red: 0.3, green: 0.9, blue: 1.0)
    case 0.8..<0.9: return Color(red: 0.0, green: 0.9, blue: 0.8)
    case 0.7..<0.8: return Color(red: 0.0, green: 0.9, blue: 0.4)
    case 0.6..<0.7: return Color(red: 0.4, green: 0.9, blue: 0.0)
    case 0.5..<0.6: return Color(red: 0.9, green: 0.9, blue: 0.0)
    case 0.4..<0.5: return Color(red: 1.0, green: 0.6, blue: 0.0)
    case 0.3..<0.4: return Color(red: 1.0, green: 0.4, blue: 0.0)
    case 0.2..<0.3: return Color(red: 1.0, green: 0.2, blue: 0.0)
    case 0.1..<0.2: return Color(red: 0.9, green: 0.0, blue: 0.0)
    default: return Color(red: 0.6, green: 0.0, blue: 0.0)
    }
}
