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

// MARK:  Models

struct CommunityFitModule: Identifiable {
    let typeId: Int
    let slotCategory: String
    let frequency: Int  // 0–100 percentage of sampled kills featuring this module
    var id: Int { typeId }
}

struct CommunityAttackerShip: Identifiable {
    let typeId: Int
    let frequency: Int  // 0–100 percentage of sampled kills where this hull appeared
    var id: Int { typeId }
}

struct CommunityMetaFit {
    let shipTypeId: Int
    let shipTypeName: String
    let shipClassName: String
    let killCount: Int
    let modules: [CommunityFitModule]
    let attackerShips: [CommunityAttackerShip]
}

struct RecentlyDestroyedEntry: Identifiable {
    let typeId: Int
    let name: String
    let killCount: Int
    var id: Int { typeId }
}

// MARK:  Main View

struct CommunityFittingsView: View {
    @Environment(AccountManager.self) private var accountManager
    @State private var searchText = ""
    @State private var searchResults: [ESIType] = []
    @State private var selectedTypeId: Int?
    @State private var isSearching = false
    @State private var metaFit: CommunityMetaFit?
    @State private var typeNames: [Int: String] = [:]
    @State private var isLoadingFit = false
    @State private var fitError: String?
    @State private var fitCache: [Int: (fit: CommunityMetaFit, names: [Int: String])] = [:]
    @State private var searchTask: Task<Void, Never>?
    @State private var recentlyDestroyed: [RecentlyDestroyedEntry] = []
    @State private var isLoadingRecent = false
    @State private var recentError: String?

    var body: some View {
        HStack(spacing: 0) {
            shipSearchPanel
            Divider()
            detailPanel
                .frame(width: 360)
        }
        .task {
            guard recentlyDestroyed.isEmpty && !isLoadingRecent else { return }
            await loadRecentlyDestroyed()
        }
        .task(id: selectedTypeId) {
            guard let id = selectedTypeId else { return }
            if let cached = fitCache[id] {
                metaFit = cached.fit
                typeNames = cached.names
                return
            }
            await loadMetaFit(for: id)
        }
    }

    // MARK:  Left Panel

    private var shipSearchPanel: some View {
        VStack(spacing: 0) {
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                    .font(.subheadline)
                TextField("Search ship type\u{2026}", text: $searchText)
                    .textFieldStyle(.plain)
                    .onChange(of: searchText) { _, query in
                        searchTask?.cancel()
                        searchTask = Task {
                            try? await Task.sleep(for: .milliseconds(300))
                            guard !Task.isCancelled else { return }
                            await performSearch(query)
                        }
                    }
                if !searchText.isEmpty {
                    Button { searchText = "" } label: {
                        Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 8))
            .padding(10)

            Divider()

            if searchText.isEmpty {
                if isLoadingRecent {
                    VStack(spacing: 8) {
                        ProgressView()
                        Text("Loading recent kills\u{2026}")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if recentlyDestroyed.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "helm")
                            .font(.system(size: 36))
                            .foregroundStyle(.tertiary)
                        Text("Search for a ship type")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        Text("e.g. \u{201C}Ferox\u{201D}, \u{201C}Ishtar\u{201D}, \u{201C}Muninn\u{201D}")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                        if let err = recentError {
                            Text(err)
                                .font(.caption2)
                                .foregroundStyle(.red.opacity(0.7))
                                .multilineTextAlignment(.center)
                                .padding(.horizontal, 12)
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    VStack(spacing: 0) {
                        HStack {
                            Label("Recently Destroyed", systemImage: "flame.fill")
                                .font(.caption.bold())
                                .foregroundStyle(.orange)
                            Spacer()
                            Text("Forge \u{00B7} Domain")
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(.quaternary.opacity(0.25))

                        List(recentlyDestroyed, selection: $selectedTypeId) { entry in
                            RecentlyDestroyedRow(entry: entry)
                                .tag(entry.typeId)
                        }
                        .listStyle(.inset)
                    }
                }
            } else if isSearching {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if searchResults.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "questionmark.circle")
                        .font(.largeTitle).foregroundStyle(.tertiary)
                    Text("No ships found")
                        .font(.subheadline).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(searchResults, id: \.typeId, selection: $selectedTypeId) { type in
                    CommunityShipRow(type: type)
                        .tag(type.typeId)
                }
                .listStyle(.inset)
            }
        }
        .frame(maxWidth: .infinity)
    }

    // MARK:  Right Panel

    @ViewBuilder
    private var detailPanel: some View {
        if let id = selectedTypeId {
            if isLoadingFit {
                VStack(spacing: 12) {
                    ProgressView()
                    Text("Analyzing recent losses\u{2026}")
                        .font(.caption).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let error = fitError {
                VStack(spacing: 10) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.largeTitle).foregroundStyle(.orange)
                    Text(error)
                        .font(.caption).foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let fit = metaFit {
                CommunityFitDetailPane(fit: fit, typeNames: typeNames)
            } else {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            let _ = id  // suppress unused warning
        } else {
            VStack(spacing: 12) {
                Image(systemName: "chart.bar.doc.horizontal")
                    .font(.system(size: 36)).foregroundStyle(.tertiary)
                Text("Select a ship to view\ncommunity meta fits")
                    .font(.subheadline).foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    // MARK:  Search

    private func performSearch(_ query: String) async {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else {
            searchResults = []
            return
        }
        isSearching = true

        struct SearchResp: Decodable { let inventoryType: [Int]? }

        guard let account = accountManager.selectedAccount,
              let token = try? await accountManager.validToken(for: account) else {
            isSearching = false
            return
        }

        let resp: SearchResp? = try? await ESIClient.shared.fetch(
            "/characters/\(account.characterID)/search/",
            token: token,
            queryItems: [
                URLQueryItem(name: "categories", value: "inventory_type"),
                URLQueryItem(name: "search", value: trimmed),
                URLQueryItem(name: "strict", value: "false")
            ]
        )
        let ids = Array((resp?.inventoryType ?? []).prefix(100))
        guard !ids.isEmpty else {
            searchResults = []
            isSearching = false
            return
        }
        let types = await UniverseCache.shared.types(ids: ids)
        searchResults = types.values
            .filter { CharacterFittingsView.eveShipGroupIds.contains($0.groupId) }
            .sorted { $0.name < $1.name }
        isSearching = false
    }

    // MARK:  Recently Destroyed

    private func loadRecentlyDestroyed() async {
        isLoadingRecent = true
        recentError = nil
        do {
            let refs = try await ZKillboardClient.shared.fetchRecentKillRefs()
            guard !refs.isEmpty else {
                recentError = "zKillboard returned no recent kills."
                isLoadingRecent = false
                return
            }

            let killmails: [ESIKillmail] = await withTaskGroup(of: ESIKillmail?.self) { group in
                for ref in refs.prefix(50) {
                    group.addTask {
                        try? await ESIClient.shared.fetch("/killmails/\(ref.killmailId)/\(ref.zkb.hash)/")
                    }
                }
                var results: [ESIKillmail] = []
                for await km in group { if let km { results.append(km) } }
                return results
            }

            guard !killmails.isEmpty else {
                recentError = "Could not retrieve killmail details from ESI."
                isLoadingRecent = false
                return
            }

            var counts: [Int: Int] = [:]
            for km in killmails {
                counts[km.victim.shipTypeId, default: 0] += 1
            }

            let typeIds = Array(counts.keys)
            let types = await UniverseCache.shared.types(ids: typeIds)

            recentlyDestroyed = counts.compactMap { typeId, count -> RecentlyDestroyedEntry? in
                guard let t = types[typeId],
                      CharacterFittingsView.eveShipGroupIds.contains(t.groupId) else { return nil }
                return RecentlyDestroyedEntry(typeId: typeId, name: t.name, killCount: count)
            }
            .sorted { $0.killCount > $1.killCount }

            if recentlyDestroyed.isEmpty {
                recentError = "No player ship kills found in latest batch."
            }
        } catch {
            recentError = "zKillboard: \(error.localizedDescription)"
        }
        isLoadingRecent = false
    }

    // MARK:  Meta Fit Loading

    private func loadMetaFit(for shipTypeId: Int) async {
        isLoadingFit = true
        metaFit = nil
        fitError = nil

        do {
            let refs = try await ZKillboardClient.shared.fetchLossRefs(shipTypeID: shipTypeId)
            guard !refs.isEmpty else {
                fitError = "No recent losses found for this ship type on zKillboard."
                isLoadingFit = false
                return
            }

            let killmails: [ESIKillmail] = await withTaskGroup(of: ESIKillmail?.self) { group in
                for ref in refs.prefix(25) {
                    group.addTask {
                        try? await ESIClient.shared.fetch("/killmails/\(ref.killmailId)/\(ref.zkb.hash)/")
                    }
                }
                var results: [ESIKillmail] = []
                for await km in group { if let km { results.append(km) } }
                return results
            }

            guard !killmails.isEmpty else {
                fitError = "Could not retrieve killmail details from ESI."
                isLoadingFit = false
                return
            }

            let shipTypes = await UniverseCache.shared.types(ids: [shipTypeId])
            let shipType = shipTypes[shipTypeId]
            let shipTypeName = shipType?.name ?? "Unknown Ship"
            let shipClassName = CharacterFittingsView.eveShipGroups[shipType?.groupId ?? 0] ?? "Unknown"

            let modules = buildMetaModules(from: killmails)
            let attackerShips = buildAttackerShips(from: killmails)

            let allTypeIds = Array(Set(modules.map(\.typeId) + attackerShips.map(\.typeId)))
            let resolved = await UniverseCache.shared.types(ids: allTypeIds)
            let names = resolved.mapValues(\.name)

            let fit = CommunityMetaFit(
                shipTypeId: shipTypeId,
                shipTypeName: shipTypeName,
                shipClassName: shipClassName,
                killCount: killmails.count,
                modules: modules,
                attackerShips: attackerShips
            )

            fitCache[shipTypeId] = (fit: fit, names: names)
            metaFit = fit
            typeNames = names
        } catch {
            fitError = error.localizedDescription
        }
        isLoadingFit = false
    }

    // MARK:  Aggregation

    private func buildMetaModules(from killmails: [ESIKillmail]) -> [CommunityFitModule] {
        let validKills = killmails.filter { !($0.victim.items?.isEmpty ?? true) }
        let total = max(1, validKills.count)
        var counts: [String: Int] = [:]

        for km in validKills {
            var seen = Set<String>()
            for item in km.victim.items ?? [] {
                let slot = slotCategory(flag: item.flag)
                guard slot != "Cargo" else { continue }
                let key = "\(slot)|\(item.itemTypeId)"
                if seen.insert(key).inserted {
                    counts[key, default: 0] += 1
                }
            }
        }

        let slotOrder = ["High Slots", "Med Slots", "Low Slots", "Rig Slots", "Subsystems", "Drone Bay", "Fighter Bay"]

        return counts.compactMap { key, count -> CommunityFitModule? in
            let parts = key.split(separator: "|").map(String.init)
            guard parts.count == 2, let typeId = Int(parts[1]) else { return nil }
            let freq = count * 100 / total
            return freq >= 20 ? CommunityFitModule(typeId: typeId, slotCategory: parts[0], frequency: freq) : nil
        }
        .sorted { lhs, rhs in
            let li = slotOrder.firstIndex(of: lhs.slotCategory) ?? 99
            let ri = slotOrder.firstIndex(of: rhs.slotCategory) ?? 99
            return li != ri ? li < ri : lhs.frequency > rhs.frequency
        }
    }

    private func buildAttackerShips(from killmails: [ESIKillmail]) -> [CommunityAttackerShip] {
        let total = max(1, killmails.count)
        var counts: [Int: Int] = [:]
        for km in killmails {
            var seen = Set<Int>()
            for attacker in km.attackers {
                guard let typeId = attacker.shipTypeId, typeId > 0 else { continue }
                if seen.insert(typeId).inserted {
                    counts[typeId, default: 0] += 1
                }
            }
        }
        return counts.compactMap { typeId, count -> CommunityAttackerShip? in
            let freq = count * 100 / total
            return freq >= 10 ? CommunityAttackerShip(typeId: typeId, frequency: freq) : nil
        }
        .sorted { $0.frequency > $1.frequency }
        .prefix(10)
        .map { $0 }
    }

    private func slotCategory(flag: Int) -> String {
        switch flag {
        case 11...18: return "Low Slots"
        case 19...26: return "Med Slots"
        case 27...34: return "High Slots"
        case 87:      return "Drone Bay"
        case 92...99: return "Rig Slots"
        case 125...132: return "Subsystems"
        case 158:     return "Fighter Bay"
        default:      return "Cargo"
        }
    }
}

// MARK:  Ship Search Row

struct CommunityShipRow: View {
    let type: ESIType

    var body: some View {
        HStack(spacing: 12) {
            AsyncImage(url: EVEImageURL.typeRender(type.typeId, size: 256)) { img in
                img.resizable().aspectRatio(contentMode: .fill)
            } placeholder: {
                RoundedRectangle(cornerRadius: 10).fill(.quaternary)
            }
            .frame(width: 72, height: 72)
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(.white.opacity(0.08), lineWidth: 0.5))

            Text(type.name)
                .font(.title3)

            Spacer()
        }
        .padding(.vertical, 6)
    }
}

// MARK:  Recently Destroyed Row

struct RecentlyDestroyedRow: View {
    let entry: RecentlyDestroyedEntry

    var body: some View {
        HStack(spacing: 12) {
            AsyncImage(url: EVEImageURL.typeRender(entry.typeId, size: 256)) { img in
                img.resizable().aspectRatio(contentMode: .fill)
            } placeholder: {
                RoundedRectangle(cornerRadius: 10).fill(.quaternary)
            }
            .frame(width: 72, height: 72)
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(.white.opacity(0.08), lineWidth: 0.5))

            Text(entry.name)
                .font(.title3)

            Spacer()

            Label("\(entry.killCount)", systemImage: "heart.badge.bolt.slash")
                .font(.headline.monospacedDigit())
                .foregroundStyle(.red.opacity(0.75))
        }
        .padding(.vertical, 6)
    }
}

// MARK:  Detail Pane

struct CommunityFitDetailPane: View {
    let fit: CommunityMetaFit
    let typeNames: [Int: String]

    private let slotOrder = ["High Slots", "Med Slots", "Low Slots", "Rig Slots", "Subsystems", "Drone Bay", "Fighter Bay"]

    var body: some View {
        VStack(spacing: 0) {
            // Hero header
            ZStack(alignment: .bottomLeading) {
                AsyncImage(url: EVEImageURL.typeRender(fit.shipTypeId, size: 512)) { img in
                    img.resizable().aspectRatio(contentMode: .fill)
                } placeholder: {
                    Rectangle().fill(LinearGradient(
                        colors: [Color(.darkGray).opacity(0.4), .black.opacity(0.6)],
                        startPoint: .topLeading, endPoint: .bottomTrailing
                    ))
                }
                .frame(height: 160)
                .clipped()

                LinearGradient(
                    stops: [.init(color: .clear, location: 0), .init(color: .black.opacity(0.75), location: 1)],
                    startPoint: .top, endPoint: .bottom
                )

                VStack(alignment: .leading, spacing: 3) {
                    Text(fit.shipTypeName)
                        .font(.headline).foregroundStyle(.white)
                    Text(fit.shipClassName)
                        .font(.caption).foregroundStyle(.white.opacity(0.7))
                    Label("Based on \(fit.killCount) recent losses", systemImage: "chart.bar.fill")
                        .font(.caption2).foregroundStyle(.white.opacity(0.55))
                }
                .padding(12)
            }
            .frame(height: 160)

            // Attribution bar
            HStack(spacing: 5) {
                Image(systemName: "info.circle").font(.caption2).foregroundStyle(.secondary)
                Text("Kill data sourced from zKillboard")
                    .font(.caption2).foregroundStyle(.tertiary)
                Spacer()
                Button("zkillboard.com") {
                    if let url = URL(string: "https://zkillboard.com") {
                        NSWorkspace.shared.open(url)
                    }
                }
                .buttonStyle(.link)
                .font(.caption2)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(.quaternary.opacity(0.3))

            Divider()

            if fit.modules.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "chart.bar")
                        .font(.largeTitle).foregroundStyle(.tertiary)
                    Text("Insufficient fitting data")
                        .font(.subheadline).foregroundStyle(.secondary)
                    Text("Not enough kills with recorded fitting information.")
                        .font(.caption).foregroundStyle(.tertiary).multilineTextAlignment(.center)
                }
                .padding()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 10) {
                        if #available(macOS 26.0, *) {
                            FittingAIInsightCard(
                                shipName: fit.shipTypeName,
                                shipClass: fit.shipClassName,
                                slotModules: communitySlotSummary()
                            )
                        }

                        if !fit.attackerShips.isEmpty {
                            GroupBox {
                                VStack(spacing: 4) {
                                    ForEach(fit.attackerShips) { attacker in
                                        AttackerShipRow(
                                            typeId: attacker.typeId,
                                            name: typeNames[attacker.typeId],
                                            frequency: attacker.frequency
                                        )
                                    }
                                }
                            } label: {
                                Label("Common Attackers", systemImage: "scope")
                                    .font(.caption.bold())
                                    .foregroundStyle(.red)
                            }
                        }

                        let grouped = Dictionary(grouping: fit.modules, by: \.slotCategory)
                        ForEach(slotOrder.filter { grouped[$0] != nil }, id: \.self) { slot in
                            GroupBox {
                                VStack(spacing: 4) {
                                    ForEach(grouped[slot]!.sorted { $0.frequency > $1.frequency }) { mod in
                                        CommunityModuleRow(module: mod, name: typeNames[mod.typeId])
                                    }
                                }
                            } label: {
                                Label(slot, systemImage: slotIcon(slot))
                                    .font(.caption.bold())
                                    .foregroundStyle(slotColor(slot))
                            }
                        }
                    }
                    .padding(12)
                }
            }
        }
    }

    private func communitySlotSummary() -> [(category: String, names: [String])] {
        let grouped = Dictionary(grouping: fit.modules, by: \.slotCategory)
        return slotOrder.compactMap { slot -> (category: String, names: [String])? in
            guard let mods = grouped[slot], !mods.isEmpty else { return nil }
            let names = mods.sorted { $0.frequency > $1.frequency }
                .map { typeNames[$0.typeId] ?? "Type #\($0.typeId)" }
            return (category: slot, names: names)
        }
    }

    private func slotColor(_ slot: String) -> Color {
        switch slot {
        case "High Slots":  return .orange
        case "Med Slots":   return .cyan
        case "Low Slots":   return .yellow
        case "Rig Slots":   return .green
        case "Subsystems":  return .purple
        case "Drone Bay":   return .teal
        case "Fighter Bay": return .indigo
        default:            return .secondary
        }
    }

    private func slotIcon(_ slot: String) -> String {
        switch slot {
        case "High Slots":  return "bolt.fill"
        case "Med Slots":   return "antenna.radiowaves.left.and.right"
        case "Low Slots":   return "shield.lefthalf.filled"
        case "Rig Slots":   return "gearshape.2.fill"
        case "Subsystems":  return "cpu.fill"
        case "Drone Bay":   return "dot.radiowaves.up.forward"
        case "Fighter Bay": return "airplane"
        default:            return "shippingbox.fill"
        }
    }
}

// MARK:  Module Row

struct CommunityModuleRow: View {
    let module: CommunityFitModule
    let name: String?
    @State private var showPopover = false

    var body: some View {
        Button { showPopover = true } label: {
            HStack(spacing: 8) {
                AsyncImage(url: EVEImageURL.typeIcon(module.typeId, size: 64)) { img in
                    img.resizable()
                } placeholder: {
                    RoundedRectangle(cornerRadius: 4).fill(.quaternary)
                }
                .frame(width: 28, height: 28)
                .clipShape(RoundedRectangle(cornerRadius: 4))
                .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(.white.opacity(0.1), lineWidth: 0.5))

                Text(name ?? "Type #\(module.typeId)")
                    .font(.caption)
                    .lineLimit(1)

                Spacer(minLength: 0)

                Text("\(module.frequency)%")
                    .font(.caption2.monospacedDigit())
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(frequencyColor(module.frequency).opacity(0.15), in: Capsule())
                    .foregroundStyle(frequencyColor(module.frequency))
            }
            .padding(.vertical, 2)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .popover(isPresented: $showPopover, arrowEdge: .trailing) {
            ModuleDetailPopover(typeId: module.typeId, name: name, quantity: 1)
        }
    }

    private func frequencyColor(_ freq: Int) -> Color {
        if freq >= 75 { return .green }
        if freq >= 50 { return .yellow }
        return .orange
    }
}

// MARK:  Attacker Ship Row

struct AttackerShipRow: View {
    let typeId: Int
    let name: String?
    let frequency: Int
    @State private var showPopover = false

    var body: some View {
        Button { showPopover = true } label: {
            HStack(spacing: 8) {
                AsyncImage(url: EVEImageURL.typeRender(typeId, size: 64)) { img in
                    img.resizable()
                } placeholder: {
                    RoundedRectangle(cornerRadius: 4).fill(.quaternary)
                }
                .frame(width: 28, height: 28)
                .clipShape(RoundedRectangle(cornerRadius: 4))
                .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(.white.opacity(0.1), lineWidth: 0.5))

                Text(name ?? "Type #\(typeId)")
                    .font(.caption)
                    .lineLimit(1)

                Spacer(minLength: 0)

                Text("\(frequency)%")
                    .font(.caption2.monospacedDigit())
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(Color.red.opacity(0.15), in: Capsule())
                    .foregroundStyle(.red)
            }
            .padding(.vertical, 2)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .popover(isPresented: $showPopover, arrowEdge: .trailing) {
            ModuleDetailPopover(typeId: typeId, name: name, quantity: 1)
        }
    }
}
