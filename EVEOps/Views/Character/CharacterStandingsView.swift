import SwiftUI

struct CharacterStandingsView: View {
    @Environment(AccountManager.self) private var accountManager
    @State private var groups: [StandingsGroup] = []
    @State private var isLoading = false
    @State private var error: String?

    var body: some View {
        LoadingStateView(isLoading: isLoading, error: error, isEmpty: groups.isEmpty, emptyMessage: "No standings found") {
            List {
                ForEach(groups, id: \.characterName) { group in
                    Section(group.characterName) {
                        ForEach(["faction", "npc_corp", "agent"], id: \.self) { fromType in
                            let filtered = group.standings.filter { $0.fromType == fromType }
                            if !filtered.isEmpty {
                                StandingTypeSection(label: typeLabel(fromType), standings: filtered)
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle("Standings")
        .task { isLoading = true; await load() }
    }

    private func typeLabel(_ type: String) -> String {
        switch type {
        case "faction": return "Factions"
        case "npc_corp": return "NPC Corporations"
        case "agent": return "Agents"
        default: return type.capitalized
        }
    }

    private func load() async {
        error = nil
        var result: [StandingsGroup] = []
        var lastError: Error?
        for account in accountManager.accounts {
            do {
                let token = try await accountManager.validToken(for: account)
                let standings: [ESIStanding] = try await ESIClient.shared.fetch(
                    "/characters/\(account.characterID)/standings/", token: token
                )
                if !standings.isEmpty {
                    result.append(StandingsGroup(characterName: account.characterName, standings: standings))
                }
            } catch { lastError = error }
        }
        groups = result
        if result.isEmpty, let e = lastError { self.error = e.localizedDescription }
        isLoading = false
    }
}

struct StandingsGroup {
    let characterName: String
    let standings: [ESIStanding]
}

struct StandingTypeSection: View {
    let label: String
    let standings: [ESIStanding]

    var body: some View {
        DisclosureGroup(label) {
            ForEach(standings.sorted { abs($0.standing) > abs($1.standing) }) { standing in
                StandingRow(standing: standing)
            }
        }
    }
}

struct StandingRow: View {
    let standing: ESIStanding
    @State private var name = ""

    var body: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(name.isEmpty ? "ID #\(standing.fromId)" : name).font(.subheadline)
            }
            Spacer()
            HStack(spacing: 8) {
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 3).fill(.quaternary)
                        let fraction = (standing.standing + 10.0) / 20.0
                        let color: Color = standing.standing > 0 ? .green : standing.standing < 0 ? .red : .secondary
                        RoundedRectangle(cornerRadius: 3)
                            .fill(color)
                            .frame(width: geo.size.width * max(0, min(1, fraction)))
                    }
                }
                .frame(width: 100, height: 8)

                Text(String(format: "%+.1f", standing.standing))
                    .font(.subheadline.bold().monospacedDigit())
                    .foregroundStyle(standing.standing > 0 ? .green : standing.standing < 0 ? .red : .secondary)
                    .frame(width: 40, alignment: .trailing)
            }
        }
        .task { name = await NameResolver.shared.resolve(id: standing.fromId) }
    }
}
