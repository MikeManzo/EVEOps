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
    @State private var fwSystems: [ESIFWSystem] = []
    @State private var fwWars: [ESIFWWar] = []
    @State private var fwLeaderboard: ESIFWLeaderboards?
    @State private var fwFactionNames: [Int: String] = [:]
    @State private var fwSystemNames: [Int: String] = [:]

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
                    WarzoneRow(
                        stat: stat,
                        isYourFaction: entry?.stats.factionId == stat.factionId,
                        allSystems: fwSystems,
                        wars: fwWars,
                        leaderboard: fwLeaderboard,
                        factionNames: fwFactionNames,
                        systemNames: fwSystemNames
                    )
                }
            }
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

    private func loadWarzoneControl() async {
        isLoadingWarzone = true
        defer { isLoadingWarzone = false }

        async let systemsResult: [ESIFWSystem]? = try? await ESIClient.shared.fetch("/fw/systems/")
        async let warsResult: [ESIFWWar]? = try? await ESIClient.shared.fetch("/fw/wars/")
        async let leaderboardResult: ESIFWLeaderboards? = try? await ESIClient.shared.fetch("/fw/leaderboards/")

        let (systemsOpt, warsOpt, leaderboardOpt) = await (systemsResult, warsResult, leaderboardResult)
        guard let systems = systemsOpt else { return }

        fwSystems = systems
        fwWars = warsOpt ?? []
        fwLeaderboard = leaderboardOpt

        var counts: [Int: (owned: Int, contested: Int, occupied: Int)] = [:]
        for sys in systems {
            var current = counts[sys.ownerFactionId] ?? (owned: 0, contested: 0, occupied: 0)
            current.owned += 1
            if sys.contested != "uncontested" { current.contested += 1 }
            if sys.occupierFactionId != sys.ownerFactionId { current.occupied += 1 }
            counts[sys.ownerFactionId] = current
        }

        // Resolve every faction that appears anywhere (owner, occupier, or a war party) in one batch.
        let allFactionIds = Set(counts.keys)
            .union(systems.map(\.occupierFactionId))
            .union(fwWars.flatMap { [$0.factionId, $0.againstId] })
        fwFactionNames = await NameResolver.shared.resolve(ids: Array(allFactionIds))

        fwSystemNames = await NameResolver.shared.resolve(ids: systems.map(\.solarSystemId))

        warzoneStats = counts
            .map { factionId, count in
                WarzoneFactionStat(
                    factionId: factionId,
                    factionName: fwFactionNames[factionId] ?? "Faction #\(factionId)",
                    systemsOwned: count.owned,
                    systemsContested: count.contested,
                    systemsOccupied: count.occupied
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
    let systemsOccupied: Int
    var id: Int { factionId }
}

// MARK:  Warzone Row + Popover

private struct WarzoneRow: View {
    let stat: WarzoneFactionStat
    let isYourFaction: Bool
    let allSystems: [ESIFWSystem]
    let wars: [ESIFWWar]
    let leaderboard: ESIFWLeaderboards?
    let factionNames: [Int: String]
    let systemNames: [Int: String]

    @State private var showPopover = false

    var body: some View {
        HStack(spacing: 10) {
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
                if stat.systemsContested > 0 || stat.systemsOccupied > 0 {
                    HStack(spacing: 6) {
                        if stat.systemsContested > 0 {
                            Text("\(stat.systemsContested) contested")
                                .font(.caption2)
                                .foregroundStyle(.orange)
                        }
                        if stat.systemsOccupied > 0 {
                            Text("\(stat.systemsOccupied) occupied")
                                .font(.caption2)
                                .foregroundStyle(.red)
                        }
                    }
                }
            }

            Spacer()

            Text("\(stat.systemsOwned)")
                .font(.subheadline.bold().monospacedDigit())
                .foregroundStyle(.primary)
            Text("systems")
                .font(.caption2)
                .foregroundStyle(.secondary)

            Image(systemName: "info.circle")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, isYourFaction ? 4 : 0)
        .listRowBackground(isYourFaction ? Color.blue.opacity(0.08) : Color.clear)
        .contentShape(Rectangle())
        .onTapGesture { showPopover = true }
        .popover(isPresented: $showPopover, arrowEdge: .trailing) {
            WarzoneFactionPopover(
                stat: stat,
                isYourFaction: isYourFaction,
                allSystems: allSystems,
                wars: wars,
                leaderboard: leaderboard,
                factionNames: factionNames,
                systemNames: systemNames
            )
        }
    }
}

private struct WarzoneFactionPopover: View {
    let stat: WarzoneFactionStat
    let isYourFaction: Bool
    let allSystems: [ESIFWSystem]
    let wars: [ESIFWWar]
    let leaderboard: ESIFWLeaderboards?
    let factionNames: [Int: String]
    let systemNames: [Int: String]

    private var ownedSystems: [ESIFWSystem] {
        allSystems
            .filter { $0.ownerFactionId == stat.factionId }
            .sorted { lhs, rhs in
                let lhsOccupied = lhs.occupierFactionId != lhs.ownerFactionId
                let rhsOccupied = rhs.occupierFactionId != rhs.ownerFactionId
                if lhsOccupied != rhsOccupied { return lhsOccupied }
                if (lhs.contested != "uncontested") != (rhs.contested != "uncontested") {
                    return lhs.contested != "uncontested"
                }
                return vpFraction(lhs) > vpFraction(rhs)
            }
    }

    private var opponentFactionIds: [Int] {
        Array(Set(wars.filter { $0.factionId == stat.factionId }.map(\.againstId)))
            .sorted { (factionNames[$0] ?? "") < (factionNames[$1] ?? "") }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                header
                Divider()

                if !opponentFactionIds.isEmpty {
                    warSection
                    Divider()
                }

                if let leaderboard {
                    statsSection(leaderboard)
                    Divider()
                }

                systemsSection
            }
        }
        .frame(minWidth: 320, maxWidth: 360, maxHeight: 480)
    }

    // MARK:  Header

    private var header: some View {
        HStack(spacing: 12) {
            AsyncImage(url: EVEImageURL.corporationLogo(stat.factionId, size: 64)) { image in
                image.resizable().scaledToFit()
            } placeholder: {
                RoundedRectangle(cornerRadius: 8).fill(.quaternary)
            }
            .frame(width: 44, height: 44)
            .clipShape(RoundedRectangle(cornerRadius: 8))

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(stat.factionName).font(.headline)
                    if isYourFaction {
                        Label("You", systemImage: "star.fill")
                            .font(.caption2.bold())
                            .foregroundStyle(.blue)
                    }
                }
                Text("\(stat.systemsOwned) systems · \(stat.systemsContested) contested · \(stat.systemsOccupied) occupied")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(12)
    }

    // MARK:  War Opponents

    private var warSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            sectionLabel("AT WAR WITH")
            FlowChips(items: opponentFactionIds.map { factionNames[$0] ?? "Faction #\($0)" })
                .padding(.horizontal, 12)
        }
        .padding(.vertical, 8)
    }

    // MARK:  Combat Stats

    private func statsSection(_ leaderboard: ESIFWLeaderboards) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionLabel("FACTION COMBAT STATS")
            periodRow(label: "Kills", color: .red,
                      yesterday: amount(for: leaderboard.kills.yesterday),
                      lastWeek: amount(for: leaderboard.kills.lastWeek),
                      total: amount(for: leaderboard.kills.activeTotal))
            periodRow(label: "Victory Points", color: .blue,
                      yesterday: amount(for: leaderboard.victoryPoints.yesterday),
                      lastWeek: amount(for: leaderboard.victoryPoints.lastWeek),
                      total: amount(for: leaderboard.victoryPoints.activeTotal))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private func periodRow(label: String, color: Color, yesterday: Int, lastWeek: Int, total: Int) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).font(.caption.bold()).foregroundStyle(.secondary)
            HStack {
                statPill("Yesterday", yesterday, color)
                statPill("Last Week", lastWeek, color)
                statPill("Total", total, color)
            }
        }
    }

    private func statPill(_ label: String, _ value: Int, _ color: Color) -> some View {
        VStack(spacing: 1) {
            Text(value.formatted())
                .font(.caption.bold().monospacedDigit())
                .foregroundStyle(value > 0 ? color : .secondary)
            Text(label)
                .font(.system(size: 9))
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity)
    }

    private func amount(for entries: [ESIFWLeaderboardEntry]) -> Int {
        entries.first { $0.factionId == stat.factionId }?.amount ?? 0
    }

    // MARK:  Systems

    private var systemsSection: some View {
        VStack(alignment: .leading, spacing: 2) {
            sectionLabel("SYSTEMS (\(ownedSystems.count))")
            ForEach(ownedSystems, id: \.solarSystemId) { sys in
                systemRow(sys)
            }
        }
        .padding(.bottom, 8)
    }

    private func systemRow(_ sys: ESIFWSystem) -> some View {
        let isOccupied = sys.occupierFactionId != sys.ownerFactionId
        let fraction = vpFraction(sys)
        return VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 6) {
                Text(systemNames[sys.solarSystemId] ?? "System #\(sys.solarSystemId)")
                    .font(.caption.bold())
                if sys.contested != "uncontested" {
                    Text("Contested")
                        .font(.system(size: 9).bold())
                        .foregroundStyle(.orange)
                        .padding(.horizontal, 5).padding(.vertical, 1)
                        .background(Color.orange.opacity(0.15), in: Capsule())
                }
                Spacer(minLength: 0)
                Text(fraction.formatted(.percent.precision(.fractionLength(0))))
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            if isOccupied {
                Label(
                    "Occupied by \(factionNames[sys.occupierFactionId] ?? "Faction #\(sys.occupierFactionId)")",
                    systemImage: "exclamationmark.triangle.fill"
                )
                .font(.caption2)
                .foregroundStyle(.red)
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.secondary.opacity(0.15))
                    Capsule().fill(isOccupied ? .red : .orange)
                        .frame(width: geo.size.width * CGFloat(fraction))
                }
            }
            .frame(height: 4)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 5)
    }

    private func vpFraction(_ sys: ESIFWSystem) -> Double {
        guard sys.victoryPointsThreshold > 0 else { return 0 }
        return min(1, Double(sys.victoryPoints) / Double(sys.victoryPointsThreshold))
    }

    private func sectionLabel(_ title: String) -> some View {
        Text(title)
            .font(.caption2.bold())
            .foregroundStyle(.tertiary)
            .padding(.horizontal, 12)
            .padding(.top, 10)
            .padding(.bottom, 2)
    }
}

// MARK:  Flow Layout for war-opponent chips

private struct FlowChips: View {
    let items: [String]

    var body: some View {
        // Simple wrapping flow using a Layout so an arbitrary number of opponent
        // chips can wrap onto multiple lines within the popover's fixed width.
        FlowLayout(spacing: 6) {
            ForEach(items, id: \.self) { name in
                Text(name)
                    .font(.caption2.bold())
                    .foregroundStyle(.red)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Color.red.opacity(0.12), in: Capsule())
            }
        }
    }
}

