import SwiftUI

struct CharacterKillmailsView: View {
    @Environment(AccountManager.self) private var accountManager
    @State private var groups: [KillmailGroup] = []
    @State private var isLoading = false
    @State private var error: String?
    @State private var selectedKillmail: ESIKillmail?
    @State private var filter = "all"

    var body: some View {
        LoadingStateView(isLoading: isLoading, error: error, isEmpty: groups.isEmpty, emptyMessage: "No kill/loss mails found") {
            VStack(spacing: 0) {
                filterBar
                killmailList
            }
        }
        .navigationTitle("Kill/Loss Mails")
        .sheet(item: $selectedKillmail) { km in
            KillmailDetailSheet(killmail: km)
        }
        .task { isLoading = true; await load() }
    }

    private var filterBar: some View {
        HStack(spacing: 12) {
            Picker("Type", selection: $filter) {
                Text("All").tag("all")
                Text("Kills").tag("kills")
                Text("Losses").tag("losses")
            }
            .pickerStyle(.segmented)
            .frame(maxWidth: 300)
            Spacer()
            let all = groups.flatMap(\.killmails)
            Label("\(all.filter(\.isKill).count) kills", systemImage: "flame.fill")
                .foregroundStyle(.green).font(.caption)
            Label("\(all.filter { !$0.isKill }.count) losses", systemImage: "xmark.circle.fill")
                .foregroundStyle(.red).font(.caption)
        }
        .padding(10)
        .background(.bar)
    }

    private var killmailList: some View {
        List {
            ForEach(groups, id: \.characterName) { group in
                let filtered = filter == "all" ? group.killmails
                    : group.killmails.filter { filter == "kills" ? $0.isKill : !$0.isKill }
                if !filtered.isEmpty {
                    Section(group.characterName) {
                        ForEach(filtered) { entry in
                            KillmailRow(entry: entry)
                                .contentShape(Rectangle())
                                .onTapGesture { selectedKillmail = entry.killmail }
                        }
                    }
                }
            }
        }
    }

    private func load() async {
        error = nil
        var result: [KillmailGroup] = []
        var lastError: Error?
        for account in accountManager.accounts {
            do {
                let token = try await accountManager.validToken(for: account)
                let refs: [ESIKillmailRef] = try await ESIClient.shared.fetch(
                    "/characters/\(account.characterID)/killmails/recent/", token: token
                )
                var entries: [KillmailEntry] = []
                await withTaskGroup(of: KillmailEntry?.self) { group in
                    for ref in refs.prefix(50) {
                        group.addTask {
                            guard let km: ESIKillmail = try? await ESIClient.shared.fetch(
                                "/killmails/\(ref.killmailId)/\(ref.killmailHash)/"
                            ) else { return nil }
                            return KillmailEntry(killmail: km, isKill: km.victim.characterId != account.characterID)
                        }
                    }
                    for await entry in group { if let e = entry { entries.append(e) } }
                }
                entries.sort { $0.killmail.killmailTime > $1.killmail.killmailTime }
                if !entries.isEmpty {
                    result.append(KillmailGroup(characterName: account.characterName, characterID: account.characterID, killmails: entries))
                }
            } catch { lastError = error }
        }
        groups = result
        if result.isEmpty, let e = lastError { self.error = e.localizedDescription }
        isLoading = false
    }
}

// MARK: - Shared Kill Mail types

struct KillmailEntry: Identifiable {
    let killmail: ESIKillmail
    let isKill: Bool
    var id: Int { killmail.killmailId }
}

struct KillmailGroup {
    let characterName: String
    let characterID: Int
    let killmails: [KillmailEntry]
}

// MARK: - Kill Mail Row

struct KillmailRow: View {
    let entry: KillmailEntry
    @State private var shipName = ""
    @State private var systemName = ""

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: entry.isKill ? "flame.fill" : "xmark.circle.fill")
                .foregroundStyle(entry.isKill ? .green : .red)
                .font(.title3)
                .frame(width: 20)
            AsyncImage(url: EVEImageURL.typeIcon(entry.killmail.victim.shipTypeId, size: 64)) { image in
                image.resizable()
            } placeholder: {
                RoundedRectangle(cornerRadius: 4).fill(.quaternary)
            }
            .frame(width: 36, height: 36)
            .clipShape(RoundedRectangle(cornerRadius: 4))

            VStack(alignment: .leading, spacing: 2) {
                Text(shipName.isEmpty ? "Ship #\(entry.killmail.victim.shipTypeId)" : shipName)
                    .font(.subheadline)
                Text(systemName.isEmpty ? "System #\(entry.killmail.solarSystemId)" : systemName)
                    .font(.caption).foregroundStyle(.secondary)
                Text("\(entry.killmail.attackers.count) attacker(s)")
                    .font(.caption2).foregroundStyle(.tertiary)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 2) {
                Text(entry.isKill ? "Kill" : "Loss")
                    .font(.caption.bold())
                    .foregroundStyle(entry.isKill ? .green : .red)
                Text(entry.killmail.killmailTime, style: .date)
                    .font(.caption2).foregroundStyle(.secondary)
                Text(entry.killmail.killmailTime, style: .time)
                    .font(.caption2).foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 2)
        .task {
            shipName = (await UniverseCache.shared.type(id: entry.killmail.victim.shipTypeId))?.name ?? ""
            systemName = await NameResolver.shared.resolve(id: entry.killmail.solarSystemId)
        }
    }
}

// MARK: - Kill Mail Detail Sheet

struct KillmailDetailSheet: View {
    let killmail: ESIKillmail
    @State private var victimShipName = ""
    @State private var systemName = ""
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Killmail #\(killmail.killmailId)")
                    .font(.headline)
                Spacer()
                Button("Close") { dismiss() }
                    .keyboardShortcut(.escape)
            }
            .padding()
            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    GroupBox {
                        HStack(spacing: 12) {
                            AsyncImage(url: EVEImageURL.typeIcon(killmail.victim.shipTypeId, size: 64)) { image in
                                image.resizable()
                            } placeholder: {
                                RoundedRectangle(cornerRadius: 4).fill(.quaternary)
                            }
                            .frame(width: 48, height: 48)
                            .clipShape(RoundedRectangle(cornerRadius: 4))

                            VStack(alignment: .leading, spacing: 4) {
                                if let charId = killmail.victim.characterId {
                                    KillmailCharacterLabel(id: charId)
                                }
                                Text(victimShipName.isEmpty ? "Ship #\(killmail.victim.shipTypeId)" : victimShipName)
                                    .font(.subheadline).foregroundStyle(.secondary)
                                Text(systemName.isEmpty ? "System #\(killmail.solarSystemId)" : systemName)
                                    .font(.caption).foregroundStyle(.secondary)
                                Text(killmail.killmailTime.formatted(.dateTime))
                                    .font(.caption2).foregroundStyle(.tertiary)
                            }
                            Spacer()
                            VStack(alignment: .trailing, spacing: 2) {
                                Text("\(killmail.victim.damageTaken)")
                                    .font(.title3.bold()).foregroundStyle(.red)
                                Text("damage taken").font(.caption2).foregroundStyle(.secondary)
                            }
                        }
                    } label: {
                        Label("Victim", systemImage: "xmark.circle.fill").foregroundStyle(.red)
                    }

                    GroupBox {
                        LazyVStack(spacing: 8) {
                            ForEach(Array(killmail.attackers.sorted { $0.finalBlow && !$1.finalBlow }.enumerated()), id: \.offset) { _, attacker in
                                KillmailAttackerRow(attacker: attacker)
                            }
                        }
                    } label: {
                        Label("Attackers (\(killmail.attackers.count))", systemImage: "flame.fill")
                            .foregroundStyle(.orange)
                    }
                }
                .padding()
            }
        }
        .frame(minWidth: 520, minHeight: 420)
        .task {
            victimShipName = (await UniverseCache.shared.type(id: killmail.victim.shipTypeId))?.name ?? ""
            systemName = await NameResolver.shared.resolve(id: killmail.solarSystemId)
        }
    }
}

struct KillmailCharacterLabel: View {
    let id: Int
    @State private var name = ""
    var body: some View {
        HStack(spacing: 6) {
            AsyncImage(url: EVEImageURL.characterPortrait(id, size: 64)) { image in
                image.resizable()
            } placeholder: { Circle().fill(.quaternary) }
            .frame(width: 22, height: 22).clipShape(Circle())
            Text(name.isEmpty ? "Character #\(id)" : name).font(.subheadline.bold())
        }
        .task { name = await NameResolver.shared.resolve(id: id) }
    }
}

struct KillmailAttackerRow: View {
    let attacker: ESIKillmailAttacker
    @State private var shipName = ""
    @State private var name = ""

    var body: some View {
        HStack(spacing: 8) {
            if let charId = attacker.characterId {
                AsyncImage(url: EVEImageURL.characterPortrait(charId, size: 64)) { image in
                    image.resizable()
                } placeholder: { Circle().fill(.quaternary) }
                .frame(width: 28, height: 28).clipShape(Circle())
            } else {
                Circle().fill(.quaternary).frame(width: 28, height: 28)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(name.isEmpty ? (attacker.characterId.map { "Character #\($0)" } ?? "NPC") : name)
                    .font(.subheadline)
                Text(shipName.isEmpty ? (attacker.shipTypeId.map { "Ship #\($0)" } ?? "Unknown") : shipName)
                    .font(.caption).foregroundStyle(.secondary)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 2) {
                if attacker.finalBlow {
                    Text("Final Blow").font(.caption2.bold())
                        .padding(.horizontal, 5).padding(.vertical, 2)
                        .background(.red.opacity(0.15), in: Capsule())
                        .foregroundStyle(.red)
                }
                Text("\(attacker.damageDone) dmg")
                    .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
            }
        }
        .task {
            if let charId = attacker.characterId { name = await NameResolver.shared.resolve(id: charId) }
            if let shipId = attacker.shipTypeId { shipName = (await UniverseCache.shared.type(id: shipId))?.name ?? "" }
        }
    }
}
