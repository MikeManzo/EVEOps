//
// This file is part of EVEOps.
//
// EVEOps is free software: you can redistribute it and/or modify
// it under the terms of the GNU General Public License as published by
// the Free Software Foundation, version 3 or later.
//
// Copyright (c) 2026 CitizenCoder
//

import SwiftUI

struct CorporationKillmailsView: View {
    @Environment(AccountManager.self) private var accountManager
    @State private var groups: [KillmailGroup] = []
    @State private var isLoading = false
    @State private var error: String?
    @State private var selectedEntry: KillmailEntry?
    @State private var filter = "all"

    // Comma-separated character IDs whose sections are collapsed — persisted across launches.
    @AppStorage("corpKillmails.collapsedCharacters") private var collapsedRaw = ""

    private var collapsedIDs: Set<Int> {
        Set(collapsedRaw.split(separator: ",").compactMap { Int($0) })
    }

    private func toggleCollapsed(_ characterID: Int) {
        var ids = collapsedIDs
        if ids.contains(characterID) { ids.remove(characterID) } else { ids.insert(characterID) }
        collapsedRaw = ids.map(String.init).joined(separator: ",")
    }

    private var allKillmails: [KillmailEntry] { groups.flatMap(\.killmails) }

    var body: some View {
        LoadingStateView(isLoading: isLoading, error: error, isEmpty: groups.isEmpty, emptyMessage: "No killmails found or insufficient roles") {
            VStack(spacing: 0) {
                filterBar
                killmailList
            }
        }
        .safeAreaInset(edge: .top, spacing: 0) {
            HStack {
                Text("Corp Kill/Loss Mails")
                    .font(.largeTitle.bold())
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(.background)
        }
        .navigationTitle("")
        .sheet(item: $selectedEntry) { entry in
            KillmailDetailSheet(entry: entry)
        }
        .task(id: accountManager.selectedCharacterID) {
            groups = []
            selectedEntry = nil
            isLoading = true
            await loadGroups()
        }
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
            Label("\(allKillmails.filter(\.isKill).count) kills", systemImage: "flame.fill")
                .foregroundStyle(.green).font(.caption)
            Label("\(allKillmails.filter { !$0.isKill }.count) losses", systemImage: "xmark.circle.fill")
                .foregroundStyle(.red).font(.caption)
        }
        .padding(10)
        .background(.bar)
    }

    private var killmailList: some View {
        List {
            ForEach(groups, id: \.characterID) { group in
                let filtered = filter == "all" ? group.killmails
                    : group.killmails.filter { filter == "kills" ? $0.isKill : !$0.isKill }
                if !filtered.isEmpty {
                    Section {
                        if !collapsedIDs.contains(group.characterID) {
                            ForEach(filtered) { entry in
                                KillmailRow(entry: entry)
                                    .contentShape(Rectangle())
                                    .onTapGesture { selectedEntry = entry }
                            }
                        }
                    } header: {
                        CorpKillmailSectionHeader(
                            group: group,
                            filtered: filtered,
                            isCollapsed: collapsedIDs.contains(group.characterID),
                            onToggle: { toggleCollapsed(group.characterID) }
                        )
                    }
                }
            }
        }
    }

    private func loadGroups() async {
        guard let account = accountManager.selectedAccount else {
            isLoading = false
            return
        }
        error = nil
        do {
            let token = try await accountManager.validToken(for: account)
            let refs: [ESIKillmailRef] = try await ESIClient.shared.fetchPages(
                "/corporations/\(account.corporationID)/killmails/recent/", token: token
            )

            // Fetch all killmail details concurrently, tagging each with the responsible corp member.
            var charEntries: [Int: [KillmailEntry]] = [:]
            await withTaskGroup(of: (Int, KillmailEntry)?.self) { group in
                for ref in refs {
                    group.addTask {
                        guard let km: ESIKillmail = try? await ESIClient.shared.fetch(
                            "/killmails/\(ref.killmailId)/\(ref.killmailHash)/"
                        ) else { return nil }
                        let isKill = km.victim.corporationId != account.corporationID
                        let charID: Int
                        if isKill {
                            // Find the corp member who landed the kill.
                            charID = km.attackers.first(where: { $0.corporationId == account.corporationID })?.characterId ?? 0
                        } else {
                            charID = km.victim.characterId ?? 0
                        }
                        return (charID, KillmailEntry(killmail: km, isKill: isKill))
                    }
                }
                for await result in group {
                    guard let (charID, entry) = result else { continue }
                    charEntries[charID, default: []].append(entry)
                }
            }

            // Resolve character names and assemble groups sorted by most recent activity.
            var resolved: [KillmailGroup] = []
            for (charID, entries) in charEntries {
                let name = charID > 0 ? await NameResolver.shared.resolve(id: charID) : "Unknown"
                let sorted = entries.sorted { $0.killmail.killmailTime > $1.killmail.killmailTime }
                resolved.append(KillmailGroup(characterName: name, characterID: charID, killmails: sorted))
            }
            groups = resolved.sorted {
                ($0.killmails.first?.killmail.killmailTime ?? .distantPast) >
                ($1.killmails.first?.killmail.killmailTime ?? .distantPast)
            }
        } catch {
            self.error = error.localizedDescription
        }
        isLoading = false
    }
}

// MARK: - Section Header

private struct CorpKillmailSectionHeader: View {
    let group: KillmailGroup
    let filtered: [KillmailEntry]
    let isCollapsed: Bool
    let onToggle: () -> Void

    var body: some View {
        Button(action: onToggle) {
            HStack(spacing: 8) {
                AsyncImage(url: EVEImageURL.characterPortrait(group.characterID, size: 64)) { image in
                    image.resizable()
                } placeholder: {
                    RoundedRectangle(cornerRadius: 6).fill(.quaternary)
                }
                .frame(width: 48, height: 48)
                .clipShape(RoundedRectangle(cornerRadius: 6))

                Text(group.characterName)
                    .font(.title3.bold())
                    .foregroundStyle(.primary)

                Spacer()

                let kills = filtered.filter(\.isKill).count
                let losses = filtered.filter { !$0.isKill }.count

                if kills > 0 {
                    Label("\(kills)", systemImage: "flame.fill")
                        .font(.caption2.bold())
                        .foregroundStyle(.green)
                }
                if losses > 0 {
                    Label("\(losses)", systemImage: "xmark.circle.fill")
                        .font(.caption2.bold())
                        .foregroundStyle(.red)
                }

                Image(systemName: isCollapsed ? "chevron.right" : "chevron.down")
                    .font(.caption2.bold())
                    .foregroundStyle(.secondary)
                    .frame(width: 12)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
