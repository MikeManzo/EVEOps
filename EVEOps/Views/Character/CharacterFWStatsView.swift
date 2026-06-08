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

    var body: some View {
        LoadingStateView(isLoading: isLoading, error: error,
                         isEmpty: entry == nil, emptyMessage: "No faction warfare data") {
            List {
                if let entry {
                    FWStatsCard(entry: entry)
                }
            }
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
