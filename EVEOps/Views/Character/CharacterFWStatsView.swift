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

struct CharacterFWStatsView: View {
    @Environment(AccountManager.self) private var accountManager
    @State private var entry: FWStatsEntry?
    @State private var isLoading = false
    @State private var error: String?

    @State private var warzoneStats: [WarzoneFactionStat] = []
    @State private var isLoadingWarzone = false

    var body: some View {
        // Warzone control is public, galaxy-wide data — shown regardless of whether the
        // selected character has personal FW stats, so it isn't hidden behind a per-character
        // error/empty state (e.g. a character with no FW activity).
        List {
            Section("Your Stats") {
                if isLoading {
                    HStack {
                        ProgressView().controlSize(.small)
                        Text("Loading…").font(.caption).foregroundStyle(.secondary)
                    }
                } else if let error {
                    Text(error).font(.caption).foregroundStyle(.secondary)
                } else if let entry {
                    FWStatsCard(entry: entry)
                }
            }
            warzoneControlSection
        }
        .safeAreaInset(edge: .top, spacing: 0) {
            HStack {
                Text("Faction Warfare")
                    .font(.largeTitle.bold())
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(.background)
        }
        .navigationTitle("")
        .task(id: accountManager.selectedCharacterID) {
            entry = nil
            await load()
        }
        .task {
            // Warzone control is public data — independent of the selected character.
            await loadWarzoneControl()
        }
    }

    // MARK:  Warzone Control

    private var warzoneControlSection: some View {
        Section("Warzone Control") {
            if isLoadingWarzone && warzoneStats.isEmpty {
                HStack {
                    ProgressView().controlSize(.small)
                    Text("Loading warzone control…")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } else if warzoneStats.isEmpty {
                Text("Warzone control unavailable")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(warzoneStats) { stat in
                    warzoneRow(stat)
                }
            }
        }
    }

    private func warzoneRow(_ stat: WarzoneFactionStat) -> some View {
        let isYourFaction = entry?.stats.factionId == stat.factionId
        return HStack(spacing: 10) {
            AsyncImage(url: EVEImageURL.corporationLogo(stat.factionId, size: 64)) { image in
                image.resizable().scaledToFit()
            } placeholder: {
                RoundedRectangle(cornerRadius: 6).fill(.quaternary)
            }
            .frame(width: 32, height: 32)
            .clipShape(RoundedRectangle(cornerRadius: 6))

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(stat.factionName)
                        .font(.subheadline.bold())
                    if isYourFaction {
                        Label("You", systemImage: "star.fill")
                            .font(.caption2.bold())
                            .foregroundStyle(.blue)
                    }
                }
                if stat.systemsContested > 0 {
                    Text("\(stat.systemsContested) contested")
                        .font(.caption2)
                        .foregroundStyle(.orange)
                }
            }

            Spacer()

            Text("\(stat.systemsOwned)")
                .font(.subheadline.bold().monospacedDigit())
                .foregroundStyle(.primary)
            Text("systems")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, isYourFaction ? 4 : 0)
        .listRowBackground(isYourFaction ? Color.blue.opacity(0.08) : Color.clear)
    }

    private func load() async {
        guard let account = accountManager.selectedAccount else { return }

        isLoading = true
        error = nil

        guard account.scopes.contains("esi-characters.read_fw_stats.v1") else {
            self.error = "Missing scope: esi-characters.read_fw_stats.v1\n\nRemove and re-add your account to grant this permission."
            isLoading = false
            return
        }

        do {
            let token = try await accountManager.validToken(for: account)
            let stats: ESIFWCharacterStats = try await ESIClient.shared.fetch(
                "/characters/\(account.characterID)/fw/stats/", token: token
            )
            var factionName: String?
            if let factionId = stats.factionId {
                factionName = await NameResolver.shared.resolve(id: factionId)
            }
            entry = FWStatsEntry(stats: stats, factionName: factionName)
        } catch ESIError.forbidden {
            self.error = "No faction warfare activity found for \(account.characterName)."
        } catch {
            self.error = error.localizedDescription
        }

        isLoading = false
    }

    private func loadWarzoneControl() async {
        isLoadingWarzone = true
        defer { isLoadingWarzone = false }

        guard let systems: [ESIFWSystem] = try? await ESIClient.shared.fetch("/fw/systems/") else { return }

        var counts: [Int: (owned: Int, contested: Int)] = [:]
        for sys in systems {
            var current = counts[sys.ownerFactionId] ?? (owned: 0, contested: 0)
            current.owned += 1
            if sys.contested != "uncontested" { current.contested += 1 }
            counts[sys.ownerFactionId] = current
        }

        let factionIds = Array(counts.keys)
        let names = await NameResolver.shared.resolve(ids: factionIds)

        warzoneStats = counts
            .map { factionId, count in
                WarzoneFactionStat(
                    factionId: factionId,
                    factionName: names[factionId] ?? "Faction #\(factionId)",
                    systemsOwned: count.owned,
                    systemsContested: count.contested
                )
            }
            .sorted { $0.systemsOwned > $1.systemsOwned }
    }
}

// Mark:  Card

private struct FWStatsCard: View {
    let entry: FWStatsEntry

    private var stats: ESIFWCharacterStats { entry.stats }
    private var isEnlisted: Bool { stats.factionId != nil }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            enrollmentHeader
            Divider()
            rankRow
            Divider()
            periodTable(label: "Kills",
                        yesterday: stats.kills.yesterday,
                        lastWeek: stats.kills.lastWeek,
                        total: stats.kills.total,
                        color: .red)
            Divider()
            periodTable(label: "Victory Points",
                        yesterday: stats.victoryPoints.yesterday,
                        lastWeek: stats.victoryPoints.lastWeek,
                        total: stats.victoryPoints.total,
                        color: .blue)
        }
        .padding(.vertical, 8)
    }

    private var enrollmentHeader: some View {
        HStack(spacing: 12) {
            if let factionId = stats.factionId {
                AsyncImage(url: EVEImageURL.corporationLogo(factionId, size: 64)) { image in
                    image.resizable().scaledToFit()
                } placeholder: {
                    RoundedRectangle(cornerRadius: 8).fill(.quaternary)
                }
                .frame(width: 48, height: 48)
                .clipShape(RoundedRectangle(cornerRadius: 8))
            } else {
                Image(systemName: "shield.slash.fill")
                    .font(.title)
                    .foregroundStyle(.secondary)
                    .frame(width: 48, height: 48)
            }

            VStack(alignment: .leading, spacing: 4) {
                if let name = entry.factionName {
                    Text(name).font(.headline)
                } else {
                    Text("Not Currently Enlisted").font(.headline).foregroundStyle(.secondary)
                }
                if let date = stats.enlistedOn {
                    Text("Enlisted \(date, style: .date)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            if isEnlisted {
                Label("Active", systemImage: "checkmark.circle.fill")
                    .font(.caption.bold())
                    .foregroundStyle(.green)
            }
        }
    }

    private var rankRow: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("Current Rank").font(.caption).foregroundStyle(.secondary)
                Text(rankLabel(stats.currentRank)).font(.subheadline.bold())
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 4) {
                Text("Highest Rank").font(.caption).foregroundStyle(.secondary)
                Text(rankLabel(stats.highestRank)).font(.subheadline.bold())
            }
        }
    }

    private func periodTable(label: String, yesterday: Int, lastWeek: Int, total: Int, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(label).font(.caption.bold()).foregroundStyle(.secondary)
            Grid(alignment: .leading, horizontalSpacing: 0, verticalSpacing: 4) {
                GridRow {
                    Text("Yesterday").font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Text("\(yesterday)")
                        .font(.caption.bold().monospacedDigit())
                        .foregroundStyle(yesterday > 0 ? color : .secondary)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                }
                GridRow {
                    Text("Last Week").font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Text("\(lastWeek)")
                        .font(.caption.bold().monospacedDigit())
                        .foregroundStyle(lastWeek > 0 ? color : .secondary)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                }
                GridRow {
                    Text("All Time").font(.caption.bold())
                    Spacer()
                    Text("\(total)")
                        .font(.caption.bold().monospacedDigit())
                        .foregroundStyle(total > 0 ? color : .secondary)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                }
            }
        }
    }

    private func rankLabel(_ rank: Int?) -> String {
        guard let rank else { return "—" }
        return "Rank \(rank) / 20"
    }
}

// Mark:  Model

private struct FWStatsEntry {
    let stats: ESIFWCharacterStats
    let factionName: String?
}

private struct WarzoneFactionStat: Identifiable {
    let factionId: Int
    let factionName: String
    let systemsOwned: Int
    let systemsContested: Int
    var id: Int { factionId }
}
