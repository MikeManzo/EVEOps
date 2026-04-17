import SwiftUI

struct ColoniesOverviewView: View {
    @Environment(AccountManager.self) private var accountManager
    @Environment(DashboardPrefetcher.self) private var prefetcher
    @State private var colonies: [CharacterColonyGroup] = []
    @State private var isLoading = false
    @State private var error: String?
    @State private var selectedEntry: ColonyDetailEntry?

    var body: some View {
        LoadingStateView(isLoading: isLoading, error: error, isEmpty: colonies.isEmpty, emptyMessage: "No PI colonies found") {
            List {
                ForEach(colonies, id: \.characterName) { group in
                    Section(group.characterName) {
                        ForEach(group.colonies, id: \.planetId) { colony in
                            Button {
                                selectedEntry = ColonyDetailEntry(characterID: group.characterID, colony: colony)
                            } label: {
                                ColonyRowView(colony: colony)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
        }
        .navigationTitle("Colonies Overview")
        .sheet(item: $selectedEntry) { entry in
            ColonyDetailView(characterID: entry.characterID, colony: entry.colony)
        }
        .task {
            if buildFromPrefetcher() { return }
            isLoading = true
            await loadColonies()
        }
    }

    private func buildFromPrefetcher() -> Bool {
        var groups: [CharacterColonyGroup] = []
        for account in accountManager.accounts {
            guard let prefetched = prefetcher.data(for: account.characterID) else { return false }
            var resolved: [ResolvedColony] = []
            for colony in prefetched.colonies {
                let systemName = prefetcher.resolvedNames[colony.solarSystemId]
                    ?? prefetcher.resolvedSystems[colony.solarSystemId]?.name
                    ?? "System #\(colony.solarSystemId)"
                resolved.append(ResolvedColony(
                    planetId: colony.planetId,
                    planetType: colony.planetType,
                    systemName: systemName,
                    numPins: colony.numPins,
                    upgradeLevel: colony.upgradeLevel,
                    lastUpdate: colony.lastUpdate
                ))
            }
            if !resolved.isEmpty {
                groups.append(CharacterColonyGroup(
                    characterID: account.characterID,
                    characterName: account.characterName,
                    colonies: resolved
                ))
            }
        }
        colonies = groups
        return true
    }

    private func loadColonies() async {
        if colonies.isEmpty { isLoading = true }
        error = nil
        var groups: [CharacterColonyGroup] = []
        var lastError: Error?
        for account in accountManager.accounts {
            do {
                let token = try await accountManager.validToken(for: account)
                let rawColonies: [ESIColony] = try await ESIClient.shared.fetch(
                    "/characters/\(account.characterID)/planets/", token: token
                )

                var resolved: [ResolvedColony] = []
                for colony in rawColonies {
                    let systemName = await NameResolver.shared.resolve(id: colony.solarSystemId)
                    resolved.append(ResolvedColony(
                        planetId: colony.planetId,
                        planetType: colony.planetType,
                        systemName: systemName,
                        numPins: colony.numPins,
                        upgradeLevel: colony.upgradeLevel,
                        lastUpdate: colony.lastUpdate
                    ))
                }

                if !resolved.isEmpty {
                    groups.append(CharacterColonyGroup(
                        characterID: account.characterID,
                        characterName: account.characterName,
                        colonies: resolved
                    ))
                }
            } catch {
                lastError = error
            }
        }
        colonies = groups
        if groups.isEmpty, let lastError {
            self.error = lastError.localizedDescription
        }
        isLoading = false
    }
}

struct ColonyDetailEntry: Identifiable {
    let characterID: Int
    let colony: ResolvedColony
    var id: Int { colony.planetId }
}

struct CharacterColonyGroup {
    let characterID: Int
    let characterName: String
    let colonies: [ResolvedColony]
}

struct ResolvedColony {
    let planetId: Int
    let planetType: String
    let systemName: String
    let numPins: Int
    let upgradeLevel: Int
    let lastUpdate: Date

    var isStale: Bool {
        Date().timeIntervalSince(lastUpdate) > 86400
    }
}

struct ColonyRowView: View {
    let colony: ResolvedColony

    var body: some View {
        HStack {
            Image(systemName: "globe.americas.fill")
                .foregroundStyle(planetColor)
            VStack(alignment: .leading, spacing: 2) {
                Text("\(colony.systemName) - \(colony.planetType.capitalized)")
                    .font(.body)
                Text("\(colony.numPins) pins - Level \(colony.upgradeLevel)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text("Updated \(colony.lastUpdate, style: .relative) ago")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                if colony.isStale {
                    Text("Extraction may be offline")
                        .font(.caption2)
                        .foregroundStyle(.orange)
                }
            }
        }
    }

    private var planetColor: Color {
        switch colony.planetType.lowercased() {
        case "temperate": return .green
        case "barren": return .brown
        case "oceanic": return .blue
        case "ice": return .cyan
        case "gas": return .orange
        case "lava": return .red
        case "storm": return .purple
        case "plasma": return .pink
        default: return .gray
        }
    }
}
