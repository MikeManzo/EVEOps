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
import FoundationModels

struct CharacterKillmailsView: View {
    @Environment(AccountManager.self) private var accountManager
    @State private var groups: [KillmailGroup] = []
    @State private var isLoading = false
    @State private var error: String?
    @State private var selectedEntry: KillmailEntry?
    @State private var loadingDetail: String?
    @State private var filter = "all"

    var body: some View {
        LoadingStateView(
            isLoading: isLoading,
            error: error,
            isEmpty: groups.isEmpty,
            emptyMessage: "No kill/loss mails found",
            loadingMessage: loadingDetail ?? "Loading..."
        ) {
            VStack(spacing: 0) {
                filterBar
                if #available(macOS 26.0, *) {
                    CombatAIInsightCard(groups: groups)
                        .padding(10)
                }
                killmailList
            }
        }
        .navigationTitle("Kill/Loss Mails")
        .sheet(item: $selectedEntry) { entry in
            KillmailDetailSheet(entry: entry)
        }
        .task(id: accountManager.selectedCharacterID) {
            groups = []
            selectedEntry = nil
            isLoading = true
            await load()
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
                                .onTapGesture { selectedEntry = entry }
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

                // Try zKillboard first — covers complete lifetime history
                var killRefs: [(killmailId: Int, hash: String, zkb: ZKBMeta?)] = []
                do {
                    loadingDetail = "Fetching history from zKillboard..."
                    let zkbRefs = try await ZKillboardClient.shared.fetchKillRefs(characterID: account.characterID)
                    killRefs = zkbRefs.map { ($0.killmailId, $0.zkb.hash, $0.zkb) }
                } catch {
                    // Fall back to ESI recent killmails
                    loadingDetail = "Fetching kill history..."
                    let esiRefs: [ESIKillmailRef] = try await ESIClient.shared.fetchPages(
                        "/characters/\(account.characterID)/killmails/recent/", token: token
                    )
                    killRefs = esiRefs.map { ($0.killmailId, $0.killmailHash, nil) }
                }

                if killRefs.isEmpty {
                    continue
                }

                loadingDetail = "Loading \(killRefs.count) killmail details..."

                var entries: [KillmailEntry] = []
                await withTaskGroup(of: KillmailEntry?.self) { group in
                    for ref in killRefs {
                        group.addTask {
                            guard let km: ESIKillmail = try? await ESIClient.shared.fetch(
                                "/killmails/\(ref.killmailId)/\(ref.hash)/"
                            ) else { return nil }
                            return KillmailEntry(
                                killmail: km,
                                isKill: km.victim.characterId != account.characterID,
                                zkb: ref.zkb
                            )
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
        loadingDetail = nil
        if result.isEmpty, let e = lastError { self.error = e.localizedDescription }
        isLoading = false
    }
}

// MARK:  Shared Kill Mail types

struct KillmailEntry: Identifiable {
    let killmail: ESIKillmail
    let isKill: Bool
    let zkb: ZKBMeta?
    var id: Int { killmail.killmailId }

    nonisolated init(killmail: ESIKillmail, isKill: Bool, zkb: ZKBMeta? = nil) {
        self.killmail = killmail
        self.isKill = isKill
        self.zkb = zkb
    }
}

struct KillmailGroup {
    let characterName: String
    let characterID: Int
    let killmails: [KillmailEntry]
}

// MARK:  Kill Mail Row

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
                if let totalValue = entry.zkb?.totalValue, totalValue > 0 {
                    Text(EVEFormatters.formatISKShort(totalValue))
                        .font(.caption2.monospacedDigit()).foregroundStyle(.secondary)
                }
                Text(entry.killmail.killmailTime, style: .date)
                    .font(.caption2).foregroundStyle(.secondary)
                HStack(spacing: 4) {
                    if entry.zkb?.isSolo == true {
                        Text("Solo")
                            .font(.caption2.bold())
                            .padding(.horizontal, 4).padding(.vertical, 1)
                            .background(.blue.opacity(0.15), in: Capsule())
                            .foregroundStyle(.blue)
                    }
                    if entry.zkb?.isNPC == true {
                        Text("NPC")
                            .font(.caption2.bold())
                            .padding(.horizontal, 4).padding(.vertical, 1)
                            .background(.secondary.opacity(0.15), in: Capsule())
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .padding(.vertical, 2)
        .task {
            shipName = (await UniverseCache.shared.type(id: entry.killmail.victim.shipTypeId))?.name ?? ""
            systemName = await NameResolver.shared.resolve(id: entry.killmail.solarSystemId)
        }
    }
}

// MARK:  Kill Mail Detail Sheet

struct KillmailDetailSheet: View {
    let entry: KillmailEntry
    var killmail: ESIKillmail { entry.killmail }
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

                    if let zkb = entry.zkb {
                        iskBreakdownBox(zkb: zkb)
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

                    if let items = killmail.victim.items, !items.isEmpty {
                        let sorted = items.sorted {
                            (($0.quantityDestroyed ?? 0) + ($0.quantityDropped ?? 0)) >
                            (($1.quantityDestroyed ?? 0) + ($1.quantityDropped ?? 0))
                        }
                        GroupBox {
                            LazyVStack(spacing: 6) {
                                ForEach(Array(sorted.enumerated()), id: \.offset) { _, item in
                                    KillmailItemRow(item: item)
                                }
                            }
                        } label: {
                            Label("Items Lost (\(items.count))", systemImage: "shippingbox.fill")
                                .foregroundStyle(.secondary)
                        }
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

    @ViewBuilder
    private func iskBreakdownBox(zkb: ZKBMeta) -> some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 16) {
                    if let total = zkb.totalValue, total > 0 {
                        iskStat("Total", value: total, color: .primary)
                    }
                    if let fitted = zkb.fittedValue, fitted > 0 {
                        iskStat("Fitted", value: fitted, color: .secondary)
                    }
                    if let destroyed = zkb.destroyedValue, destroyed > 0 {
                        iskStat("Destroyed", value: destroyed, color: .red)
                    }
                    if let dropped = zkb.droppedValue, dropped > 0 {
                        iskStat("Dropped", value: dropped, color: .green)
                    }
                }
                if zkb.isSolo || zkb.isNPC || zkb.isAWOX || (zkb.points ?? 0) > 0 {
                    HStack(spacing: 6) {
                        if zkb.isSolo {
                            badge("Solo", color: .blue)
                        }
                        if zkb.isNPC {
                            badge("NPC", color: .secondary)
                        }
                        if zkb.isAWOX {
                            badge("AWOX", color: .orange)
                        }
                        if let pts = zkb.points, pts > 0 {
                            Text("\(pts) pts")
                                .font(.caption2.monospacedDigit())
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        } label: {
            Label("Combat Value", systemImage: "banknote.fill").foregroundStyle(.yellow)
        }
    }

    private func iskStat(_ label: String, value: Double, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(.caption2).foregroundStyle(.secondary)
            Text(EVEFormatters.formatISKShort(value))
                .font(.caption.monospacedDigit().bold())
                .foregroundStyle(color)
        }
    }

    private func badge(_ text: String, color: Color) -> some View {
        Text(text)
            .font(.caption2.bold())
            .padding(.horizontal, 5).padding(.vertical, 2)
            .background(color.opacity(0.15), in: Capsule())
            .foregroundStyle(color)
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

// MARK: Killmail Item Row

struct KillmailItemRow: View {
    let item: ESIKillmailItem
    @State private var typeName = ""

    var body: some View {
        HStack(spacing: 8) {
            AsyncImage(url: EVEImageURL.typeIcon(item.itemTypeId, size: 32)) { image in
                image.resizable()
            } placeholder: {
                RoundedRectangle(cornerRadius: 3).fill(.quaternary)
            }
            .frame(width: 24, height: 24)
            .clipShape(RoundedRectangle(cornerRadius: 3))

            Text(typeName.isEmpty ? "Item #\(item.itemTypeId)" : typeName)
                .font(.caption)

            Spacer()

            HStack(spacing: 6) {
                let destroyed = item.quantityDestroyed ?? 0
                let dropped = item.quantityDropped ?? 0
                if destroyed > 0 || (destroyed == 0 && dropped == 0) {
                    HStack(spacing: 3) {
                        Image(systemName: "xmark.circle.fill").foregroundStyle(.red)
                        Text("\(max(1, destroyed))").foregroundStyle(.red)
                    }
                    .font(.caption2.monospacedDigit())
                }
                if dropped > 0 {
                    HStack(spacing: 3) {
                        Image(systemName: "arrow.down.circle.fill").foregroundStyle(.green)
                        Text("\(dropped)").foregroundStyle(.green)
                    }
                    .font(.caption2.monospacedDigit())
                }
            }
        }
        .task { typeName = (await UniverseCache.shared.type(id: item.itemTypeId))?.name ?? "" }
    }
}

// MARK: Combat AI Insight Card

@available(macOS 26.0, *)
struct CombatAIInsightCard: View {
    let groups: [KillmailGroup]

    @AppStorage("aiInsightsEnabled")  private var aiInsightsEnabled  = false
    @AppStorage("aiInsightKillmails") private var aiInsightKillmails = true
    @State private var insight: CombatInsight?
    @State private var isGenerating = false
    @State private var generationError: String?
    @State private var hasAutoGenerated = false

    private var model: SystemLanguageModel { .default }

    var body: some View {
        if aiInsightsEnabled && aiInsightKillmails, case .available = model.availability {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Label("AI Insight", systemImage: "sparkles")
                        .font(.subheadline.bold())
                        .foregroundStyle(.purple)
                    Spacer()
                    if insight != nil, !isGenerating {
                        Button {
                            Task { await generate() }
                        } label: {
                            Image(systemName: "arrow.clockwise")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                        .help("Regenerate insight")
                    }
                }

                if isGenerating {
                    HStack(spacing: 8) {
                        ProgressView().controlSize(.small)
                        Text("Analyzing combat record\u{2026}")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                } else if let insight {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(insight.summary)
                            .font(.subheadline)
                            .fixedSize(horizontal: false, vertical: true)
                        HStack(alignment: .top, spacing: 6) {
                            Image(systemName: "lightbulb.fill")
                                .font(.caption).foregroundStyle(.yellow).padding(.top, 1)
                            Text(insight.suggestion)
                                .font(.caption).foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                } else if let error = generationError {
                    Text(error).font(.caption).foregroundStyle(.red.opacity(0.8))
                } else {
                    Button("Generate Insight") { Task { await generate() } }
                        .buttonStyle(.bordered).controlSize(.small)
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(.purple.opacity(0.2)))
            .task(id: groups.first?.characterID ?? 0) {
                guard !hasAutoGenerated else { return }
                hasAutoGenerated = true
                await generate()
            }
        }
    }

    private func generate() async {
        isGenerating = true
        generationError = nil

        let allEntries = groups.flatMap(\.killmails)
        let kills = allEntries.filter(\.isKill)
        let losses = allEntries.filter { !$0.isKill }

        // Top lost ships
        let lostShipCounts = Dictionary(grouping: losses, by: { $0.killmail.victim.shipTypeId })
            .map { typeId, entries in (typeId: typeId, count: entries.count) }
            .sorted { $0.count > $1.count }
            .prefix(4)
        var topLostShips: [(name: String, count: Int)] = []
        for item in lostShipCounts {
            let name = (await UniverseCache.shared.type(id: item.typeId))?.name ?? "Ship #\(item.typeId)"
            topLostShips.append((name: name, count: item.count))
        }

        // Average attackers on losses
        let avgAttackers = losses.isEmpty ? 0.0
            : Double(losses.reduce(0) { $0 + $1.killmail.attackers.count }) / Double(losses.count)

        // Most active systems
        let systemCounts = Dictionary(grouping: allEntries, by: { $0.killmail.solarSystemId })
            .map { systemId, entries in (systemId: systemId, count: entries.count) }
            .sorted { $0.count > $1.count }
            .prefix(4)
        var activeSystemNames: [String] = []
        for item in systemCounts {
            let name = await NameResolver.shared.resolve(id: item.systemId)
            activeSystemNames.append(name)
        }

        // Most common ships fielded against this character
        let threatShipIds = losses.flatMap { $0.killmail.attackers.compactMap(\.shipTypeId) }
        let threatCounts = Dictionary(grouping: threatShipIds, by: { $0 })
            .map { typeId, arr in (typeId: typeId, count: arr.count) }
            .sorted { $0.count > $1.count }
            .prefix(4)
        var commonThreatShips: [String] = []
        for item in threatCounts {
            let name = (await UniverseCache.shared.type(id: item.typeId))?.name ?? "Ship #\(item.typeId)"
            commonThreatShips.append(name)
        }

        let characterName = groups.count == 1
            ? groups[0].characterName
            : groups.map(\.characterName).joined(separator: ", ")

        do {
            insight = try await IntelligenceService.shared.analyzeCombat(
                characterName: characterName,
                killCount: kills.count,
                lossCount: losses.count,
                topLostShips: topLostShips,
                activeSystemNames: activeSystemNames,
                avgAttackersOnLoss: avgAttackers,
                commonThreatShips: commonThreatShips
            )
        } catch {
            generationError = "Unable to generate insight. Try again later."
        }
        isGenerating = false
    }
}
