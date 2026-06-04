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

struct CharacterStandingsView: View {
    @Environment(AccountManager.self) private var accountManager
    @State private var groups: [StandingsGroup] = []
    @State private var isLoading = false
    @State private var error: String?

    var body: some View {
        LoadingStateView(isLoading: isLoading, error: error, isEmpty: groups.isEmpty, emptyMessage: "No standings found") {
            List {
                ForEach(groups, id: \.characterName) { group in
                    Section(header: Text(group.characterName).font(.title3).bold()) {
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
        .safeAreaInset(edge: .top, spacing: 0) {
            HStack {
                Text("Standings")
                    .font(.largeTitle.bold())
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(.background)
        }
        .navigationTitle("Standings")
        .task(id: accountManager.selectedCharacterID) {
            groups = []
            isLoading = true
            await load()
        }
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
    @AppStorage private var isExpanded: Bool

    init(label: String, standings: [ESIStanding]) {
        self.label = label
        self.standings = standings
        self._isExpanded = AppStorage(wrappedValue: true, "standings.section.\(label)")
    }

    var body: some View {
        DisclosureGroup(isExpanded: $isExpanded) {
            ForEach(standings.sorted { abs($0.standing) > abs($1.standing) }) { standing in
                StandingRow(standing: standing)
            }
        } label: {
            Text(label).font(.headline)
        }
    }
}

struct StandingRow: View {
    let standing: ESIStanding
    @State private var name = ""
    @State private var showPopover = false

    private var iconURL: URL? {
        switch standing.fromType {
        case "faction", "npc_corp": return EVEImageURL.corporationLogo(standing.fromId, size: 64)
        case "agent": return EVEImageURL.characterPortrait(standing.fromId, size: 64)
        default: return nil
        }
    }

    var body: some View {
        HStack(spacing: 10) {
            AsyncImage(url: iconURL) { image in
                image.resizable().scaledToFit()
            } placeholder: {
                RoundedRectangle(cornerRadius: 6).fill(.quaternary)
            }
            .frame(width: 32, height: 32)
            .clipShape(RoundedRectangle(cornerRadius: 6))

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
        .contentShape(Rectangle())
        .onTapGesture { showPopover = true }
        .popover(isPresented: $showPopover) {
            if standing.fromType == "faction" {
                FactionPopoverView(standing: standing).frame(width: 320)
            } else if standing.fromType == "npc_corp" {
                NpcCorpPopoverView(standing: standing).frame(width: 320)
            } else if standing.fromType == "agent" {
                AgentPopoverView(standing: standing).frame(width: 300)
            }
        }
        .task { name = await NameResolver.shared.resolve(id: standing.fromId) }
    }
}

struct FactionPopoverView: View {
    let standing: ESIStanding
    @State private var faction: ESIFaction?
    @State private var homeSystemName: String?

    private var standingColor: Color {
        standing.standing > 0 ? .green : standing.standing < 0 ? .red : .secondary
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header: logo + name + standing
            HStack(spacing: 12) {
                AsyncImage(url: EVEImageURL.corporationLogo(standing.fromId, size: 64)) { image in
                    image.resizable().scaledToFit()
                } placeholder: {
                    RoundedRectangle(cornerRadius: 6).fill(.quaternary)
                }
                .frame(width: 64, height: 64)
                .clipShape(RoundedRectangle(cornerRadius: 6))

                VStack(alignment: .leading, spacing: 4) {
                    if let faction {
                        Text(faction.name).font(.headline)
                    } else {
                        ProgressView().controlSize(.small)
                    }
                    Text(String(format: "%+.1f standing", standing.standing))
                        .font(.subheadline.bold().monospacedDigit())
                        .foregroundStyle(standingColor)
                }
            }

            if let faction {
                Divider()

                // Description
                if !faction.description.isEmpty {
                    Text(faction.description)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        //.lineLimit(6)
                        .fixedSize(horizontal: false, vertical: true)
                }

                // Stats grid
                Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 6) {
                    if let sysName = homeSystemName {
                        GridRow {
                            Text("Home System").font(.caption).foregroundStyle(.secondary)
                            Text(sysName).font(.caption.bold())
                        }
                    }
                    if let count = faction.stationCount {
                        GridRow {
                            Text("Stations").font(.caption).foregroundStyle(.secondary)
                            Text("\(count)").font(.caption.bold())
                        }
                    }
                    if let sysCount = faction.stationSystemCount {
                        GridRow {
                            Text("Systems w/ Stations").font(.caption).foregroundStyle(.secondary)
                            Text("\(sysCount)").font(.caption.bold())
                        }
                    }
                }
            }
        }
        .padding()
        .task {
            faction = await UniverseCache.shared.faction(id: standing.fromId)
            if let sysId = faction?.solarSystemId {
                homeSystemName = await NameResolver.shared.resolve(id: sysId)
            }
        }
    }
}

struct NpcCorpPopoverView: View {
    let standing: ESIStanding
    @State private var corp: ESICorporationPublic?
    @State private var ceoName: String?

    private var standingColor: Color {
        standing.standing > 0 ? .green : standing.standing < 0 ? .red : .secondary
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                AsyncImage(url: EVEImageURL.corporationLogo(standing.fromId, size: 64)) { image in
                    image.resizable().scaledToFit()
                } placeholder: {
                    RoundedRectangle(cornerRadius: 6).fill(.quaternary)
                }
                .frame(width: 64, height: 64)
                .clipShape(RoundedRectangle(cornerRadius: 6))

                VStack(alignment: .leading, spacing: 4) {
                    if let corp {
                        Text(corp.name).font(.headline)
                        Text("[\(corp.ticker)]").font(.subheadline).foregroundStyle(.secondary)
                    } else {
                        ProgressView().controlSize(.small)
                    }
                    Text(String(format: "%+.1f standing", standing.standing))
                        .font(.subheadline.bold().monospacedDigit())
                        .foregroundStyle(standingColor)
                }
            }

            if let corp {
                Divider()

                if let desc = corp.description, !desc.isEmpty {
                    Text(desc)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 6) {
                    GridRow {
                        Text("Members").font(.caption).foregroundStyle(.secondary)
                        Text("\(corp.memberCount)").font(.caption.bold())
                    }
                    GridRow {
                        Text("Tax Rate").font(.caption).foregroundStyle(.secondary)
                        Text(String(format: "%.1f%%", corp.taxRate * 100)).font(.caption.bold())
                    }
                    if let ceoName {
                        GridRow {
                            Text("CEO").font(.caption).foregroundStyle(.secondary)
                            Text(ceoName).font(.caption.bold())
                        }
                    }
                }
            }
        }
        .padding()
        .task {
            corp = try? await ESIClient.shared.fetch("/corporations/\(standing.fromId)/")
            if let ceoId = corp?.ceoId {
                ceoName = await NameResolver.shared.resolve(id: ceoId)
            }
        }
    }
}

struct AgentPopoverView: View {
    let standing: ESIStanding
    @State private var agentInfo: ESICharacterPublic?
    @State private var corpName: String?

    private var standingColor: Color {
        standing.standing > 0 ? .green : standing.standing < 0 ? .red : .secondary
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                AsyncImage(url: EVEImageURL.characterPortrait(standing.fromId, size: 64)) { image in
                    image.resizable().scaledToFit()
                } placeholder: {
                    RoundedRectangle(cornerRadius: 6).fill(.quaternary)
                }
                .frame(width: 64, height: 64)
                .clipShape(RoundedRectangle(cornerRadius: 6))

                VStack(alignment: .leading, spacing: 4) {
                    if let agentInfo {
                        Text(agentInfo.name).font(.headline)
                    } else {
                        ProgressView().controlSize(.small)
                    }
                    Text(String(format: "%+.1f standing", standing.standing))
                        .font(.subheadline.bold().monospacedDigit())
                        .foregroundStyle(standingColor)
                }
            }

            if agentInfo != nil {
                Divider()

                Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 6) {
                    if let corpName {
                        GridRow {
                            Text("Corporation").font(.caption).foregroundStyle(.secondary)
                            Text(corpName).font(.caption.bold())
                        }
                    }
                    if let sec = agentInfo?.securityStatus {
                        GridRow {
                            Text("Security Status").font(.caption).foregroundStyle(.secondary)
                            Text(String(format: "%.2f", sec)).font(.caption.bold())
                        }
                    }
                }
            }
        }
        .padding()
        .task {
            agentInfo = try? await ESIClient.shared.fetch("/characters/\(standing.fromId)/")
            if let corpId = agentInfo?.corporationId {
                corpName = await NameResolver.shared.resolve(id: corpId)
            }
        }
    }
}
