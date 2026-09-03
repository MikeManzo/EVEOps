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

// MARK:  Sovereignty View

struct SovereigntyView: View {
    private enum Tab: String, CaseIterable, Identifiable {
        case campaigns = "Campaigns"
        case structures = "Structures"
        case holders = "Holders"
        var id: String { rawValue }
    }

    @State private var tab: Tab = .campaigns

    @State private var campaigns: [ResolvedCampaign] = []
    @State private var structures: [ESISovereigntyStructure] = []
    @State private var allianceNames: [Int: String] = [:]
    @State private var isLoading = true
    @State private var structuresLoading = true
    @State private var error: String?

    @State private var structureAllianceFilter: Int?
    @State private var showAllStructures = false

    @State private var holders: [AllianceHolding] = []
    @State private var holdersLoading = false
    @State private var holdersLoaded = false
    @State private var sovMap: [ESISovereigntyMapEntry] = []

    @State private var detail: SovDetail?

    var body: some View {
        HStack(spacing: 0) {
            VStack(spacing: 0) {
                Picker("View", selection: $tab) {
                    ForEach(Tab.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                Divider()

                if isLoading {
                    ProgressView("Loading sovereignty data…")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let error {
                    ContentUnavailableView("Couldn't load sovereignty", systemImage: "exclamationmark.triangle", description: Text(error))
                } else {
                    switch tab {
                    case .campaigns:  campaignsList
                    case .structures: structuresList
                    case .holders:    holdersList
                    }
                }
            }

            if let detail {
                Divider()
                SovDetailPane(
                    detail: detail,
                    campaignsBySystem: Dictionary(campaigns.map { ($0.campaign.solarSystemId, $0) }, uniquingKeysWith: { a, _ in a }),
                    structuresBySystem: Dictionary(grouping: structures, by: \.solarSystemId),
                    sovMap: sovMap,
                    allianceNames: allianceNames,
                    onClose: { self.detail = nil }
                )
                .frame(width: 340)
                .id(detail.id)
            }
        }
        .safeAreaInset(edge: .top, spacing: 0) {
            HStack {
                Text("Sovereignty").font(.largeTitle.bold())
                Spacer()
                if !isLoading && error == nil {
                    Text("\(campaigns.count) campaigns · \(structuresLoading ? "…" : "\(structures.count)") structures")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(.background)
        }
        .navigationTitle("")
        .task { await load() }
        .task(id: tab) { if tab == .holders { await loadHolders() } }
        .onChange(of: tab) { _, _ in detail = nil }
    }

    // MARK: Campaigns

    @ViewBuilder
    private var campaignsList: some View {
        if campaigns.isEmpty {
            ContentUnavailableView("No active campaigns", systemImage: "flag.slash",
                                   description: Text("There are no sovereignty campaigns running right now."))
        } else {
            List(campaigns) { camp in
                Button { detail = .campaign(camp) } label: { CampaignRow(item: camp) }
                    .buttonStyle(.plain)
                    .listRowBackground(rowBackground(selected: detail?.id == SovDetail.campaignID(camp.id)))
            }
        }
    }

    // MARK: Structures

    private var structureAlliances: [(id: Int, name: String)] {
        let ids = Set(structures.map(\.allianceId))
        return ids.map { ($0, allianceNames[$0] ?? "Alliance #\($0)") }
            .sorted { $0.1.localizedCaseInsensitiveCompare($1.1) == .orderedAscending }
    }

    private var visibleStructures: [ESISovereigntyStructure] {
        structures.filter { s in
            if let f = structureAllianceFilter, s.allianceId != f { return false }
            if !showAllStructures, (s.vulnerabilityOccupancyLevel ?? 6) >= 4.0 { return false }
            return true
        }
    }

    @ViewBuilder
    private var structuresList: some View {
        if structuresLoading && structures.isEmpty {
            ProgressView("Loading structures…")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Picker("Alliance", selection: $structureAllianceFilter) {
                    Text("All alliances").tag(Int?.none)
                    ForEach(structureAlliances, id: \.id) { Text($0.name).tag(Int?.some($0.id)) }
                }
                .pickerStyle(.menu)
                .labelsHidden()
                .frame(maxWidth: 260)

                Toggle("Include ADM ≥ 4", isOn: $showAllStructures)
                    .toggleStyle(.checkbox)
                    .font(.caption)

                Spacer()
                Text("\(visibleStructures.count) shown")
                    .font(.caption).foregroundStyle(.secondary)
            }
            .padding(.horizontal, 16).padding(.vertical, 8)
            Divider()

            if visibleStructures.isEmpty {
                ContentUnavailableView("Nothing to show", systemImage: "line.3.horizontal.decrease.circle",
                                       description: Text("No structures match the current filter."))
            } else {
                List(visibleStructures) { s in
                    Button { detail = .structure(s) } label: {
                        StructureRow(item: s, allianceName: allianceNames[s.allianceId])
                    }
                    .buttonStyle(.plain)
                    .listRowBackground(rowBackground(selected: detail?.id == SovDetail.structureID(s.id)))
                }
            }
        }
        }
    }

    // MARK: Holders

    @ViewBuilder
    private var holdersList: some View {
        if holdersLoading && holders.isEmpty {
            ProgressView("Loading the sovereignty map…")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if holders.isEmpty {
            ContentUnavailableView("No holdings data", systemImage: "globe",
                                   description: Text("The sovereignty map returned nothing."))
        } else {
            let maxCount = holders.first?.systemCount ?? 1
            List(Array(holders.enumerated()), id: \.element.id) { idx, h in
                Button { detail = .holder(h) } label: {
                    HolderRow(rank: idx + 1, holding: h, maxCount: maxCount)
                }
                .buttonStyle(.plain)
                .listRowBackground(rowBackground(selected: detail?.id == SovDetail.holderID(h.id)))
            }
        }
    }

    @ViewBuilder
    private func rowBackground(selected: Bool) -> some View {
        if selected { Color.accentColor.opacity(0.12) } else { Color.clear }
    }

    // MARK: Load

    private func load() async {
        // 1. Campaigns — the default tab. Fetch + resolve names, then show the view.
        //    Constellation/region/security fill in afterwards (see enrichCampaigns).
        do {
            let camps: [ESISovereigntyCampaign] = try await ESIClient.shared.fetch("/sovereignty/campaigns/")

            async let campNames = NameResolver.shared.resolve(ids: Array(Set(camps.compactMap(\.defenderId))))
            async let campSys = NameResolver.shared.resolve(ids: camps.map(\.solarSystemId))
            let (names, sysNames) = await (campNames, campSys)
            allianceNames.merge(names) { _, new in new }

            campaigns = camps
                .sorted { $0.startTime < $1.startTime }
                .map { c in
                    ResolvedCampaign(
                        campaign: c,
                        systemName: sysNames[c.solarSystemId] ?? "System #\(c.solarSystemId)",
                        securityStatus: nil,
                        constellationName: nil,
                        regionName: nil,
                        defenderName: c.defenderId.flatMap { names[$0] }
                    )
                }
            error = nil
        } catch {
            self.error = error.localizedDescription
        }
        isLoading = false

        // 2. Constellation / region / security for each campaign, in parallel.
        await enrichCampaigns()

        // 3. Structures — larger payload, not needed for the first paint.
        if let structs: [ESISovereigntyStructure] = try? await ESIClient.shared.fetch("/sovereignty/structures/") {
            let missing = Set(structs.map(\.allianceId)).subtracting(allianceNames.keys)
            if !missing.isEmpty {
                let more = await NameResolver.shared.resolve(ids: Array(missing))
                allianceNames.merge(more) { _, new in new }
            }
            structures = structs.sorted {
                ($0.vulnerabilityOccupancyLevel ?? 99) < ($1.vulnerabilityOccupancyLevel ?? 99)
            }
        }
        structuresLoading = false
    }

    /// Resolves constellation, region and security for every campaign concurrently
    /// and patches the rows in place as results arrive.
    private func enrichCampaigns() async {
        let ids = campaigns.map { ($0.campaign.campaignId, $0.campaign.constellationId, $0.campaign.solarSystemId) }
        guard !ids.isEmpty else { return }

        let enriched: [Int: (con: String?, region: String?, sec: Double?)] = await withTaskGroup(
            of: (Int, String?, String?, Double?).self
        ) { group in
            for (campaignId, constellationId, systemId) in ids {
                group.addTask {
                    let con = await UniverseCache.shared.constellation(id: constellationId)
                    var region: String?
                    if let con, let r = await UniverseCache.shared.region(id: con.regionId) { region = r.name }
                    let sys = await UniverseCache.shared.solarSystem(id: systemId)
                    return (campaignId, con?.name, region, sys?.securityStatus)
                }
            }
            var out: [Int: (con: String?, region: String?, sec: Double?)] = [:]
            for await (id, con, region, sec) in group { out[id] = (con, region, sec) }
            return out
        }

        for i in campaigns.indices {
            if let e = enriched[campaigns[i].campaign.campaignId] {
                campaigns[i].constellationName = e.con
                campaigns[i].regionName = e.region
                campaigns[i].securityStatus = e.sec
            }
        }
    }

    private func loadHolders() async {
        guard !holdersLoaded, !holdersLoading else { return }
        holdersLoading = true
        defer { holdersLoading = false }

        guard let map: [ESISovereigntyMapEntry] = try? await ESIClient.shared.fetch("/sovereignty/map/") else { return }
        sovMap = map
        var counts: [Int: Int] = [:]
        for entry in map { if let a = entry.allianceId { counts[a, default: 0] += 1 } }

        let top = counts.sorted { $0.value > $1.value }.prefix(20)
        let missing = top.map(\.key).filter { allianceNames[$0] == nil }
        if !missing.isEmpty {
            let more = await NameResolver.shared.resolve(ids: missing)
            allianceNames.merge(more) { _, new in new }
        }
        holders = top.map {
            AllianceHolding(allianceId: $0.key, systemCount: $0.value,
                            name: allianceNames[$0.key] ?? "Alliance #\($0.key)")
        }
        holdersLoaded = true
    }
}

// MARK:  Models

private struct ResolvedCampaign: Identifiable {
    let campaign: ESISovereigntyCampaign
    let systemName: String
    var securityStatus: Double?
    var constellationName: String?
    var regionName: String?
    let defenderName: String?
    var id: Int { campaign.id }
}

private struct AllianceHolding: Identifiable {
    let allianceId: Int
    let systemCount: Int
    let name: String
    var id: Int { allianceId }
}

// MARK:  Sovereignty Helpers

enum SovereigntyFormat {
    static func eventLabel(_ raw: String) -> String {
        switch raw {
        case "tcu_defense":      return "TCU Defense"
        case "ihub_defense":     return "IHub Defense"
        case "station_defense":  return "Station Defense"
        case "station_freeport": return "Station Freeport"
        default:                 return raw.replacingOccurrences(of: "_", with: " ").capitalized
        }
    }

    static func eventIcon(_ raw: String) -> String {
        switch raw {
        case "tcu_defense":      return "flag.fill"
        case "ihub_defense":     return "antenna.radiowaves.left.and.right"
        default:                 return "building.2.fill"
        }
    }

    static func structureName(_ typeId: Int) -> String {
        switch typeId {
        case 32226: return "Territorial Claim Unit"
        case 32458: return "Infrastructure Hub"
        default:    return "Sov Structure"
        }
    }

    static func structureIcon(_ typeId: Int) -> String {
        switch typeId {
        case 32226: return "flag.fill"
        case 32458: return "antenna.radiowaves.left.and.right"
        default:    return "building.2.fill"
        }
    }

    /// ADM colour — high = well defended (green), low = soft (red).
    static func admColor(_ adm: Double) -> Color {
        switch adm {
        case ..<2:   return .red
        case 2..<4:  return .orange
        case 4..<5:  return .yellow
        default:     return .green
        }
    }

    static func countdown(to date: Date) -> String {
        let delta = date.timeIntervalSinceNow
        let mag = abs(delta)
        let s: String
        if mag < 3600 { s = "\(Int(mag / 60))m" }
        else if mag < 86_400 { s = String(format: "%.0fh %.0fm", (mag / 3600).rounded(.down), (mag.truncatingRemainder(dividingBy: 3600) / 60).rounded(.down)) }
        else { s = String(format: "%.0fd %.0fh", (mag / 86_400).rounded(.down), (mag.truncatingRemainder(dividingBy: 86_400) / 3600).rounded(.down)) }
        return delta >= 0 ? "in \(s)" : "\(s) ago"
    }
}

func sovSecColor(_ status: Double) -> Color {
    switch status {
    case 0.5...:    return Color(red: 0.4, green: 0.8, blue: 0.3)
    case 0.1..<0.5: return .orange
    default:        return Color(red: 0.9, green: 0.2, blue: 0.2)
    }
}

// MARK:  Campaign Row

private struct CampaignRow: View {
    let item: ResolvedCampaign
    private var c: ESISovereigntyCampaign { item.campaign }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            if let defenderId = c.defenderId {
                CachedAsyncImage(url: EVEImageURL.allianceLogo(defenderId, size: 64)) { $0.resizable().scaledToFit() }
                placeholder: { RoundedRectangle(cornerRadius: 8).fill(.quaternary) }
                .frame(width: 44, height: 44)
                .clipShape(RoundedRectangle(cornerRadius: 8))
            } else {
                RoundedRectangle(cornerRadius: 8).fill(.quaternary).frame(width: 44, height: 44)
                    .overlay(Image(systemName: "flag").foregroundStyle(.secondary))
            }

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Label(SovereigntyFormat.eventLabel(c.eventType),
                          systemImage: SovereigntyFormat.eventIcon(c.eventType))
                        .font(.caption.bold())
                        .foregroundStyle(.orange)
                    Text(SovereigntyFormat.countdown(to: c.startTime))
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(c.startTime.timeIntervalSinceNow <= 0 ? .red : .secondary)
                    if c.startTime.timeIntervalSinceNow <= 0 {
                        Text("IN PROGRESS")
                            .font(.system(size: 9).bold())
                            .foregroundStyle(.red)
                            .padding(.horizontal, 4).padding(.vertical, 1)
                            .background(.red.opacity(0.15), in: Capsule())
                    }
                }

                HStack(spacing: 6) {
                    if let sec = item.securityStatus {
                        Text(String(format: "%.1f", sec))
                            .font(.caption2.bold().monospacedDigit())
                            .foregroundStyle(sovSecColor(sec))
                    }
                    Text(item.systemName).font(.subheadline.bold())
                    let geo = [item.constellationName, item.regionName].compactMap { $0 }.joined(separator: " · ")
                    if !geo.isEmpty {
                        Text("· \(geo)").font(.caption).foregroundStyle(.secondary)
                    }
                }

                Text(item.defenderName ?? "Defender unknown")
                    .font(.caption).foregroundStyle(.secondary)

                if let d = c.defenderScore, let a = c.attackersScore, d + a > 0 {
                    scoreBar(defender: d, attackers: a)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 4)
    }

    private func scoreBar(defender: Double, attackers: Double) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            GeometryReader { geo in
                let total = max(defender + attackers, 0.0001)
                HStack(spacing: 0) {
                    Rectangle().fill(.green).frame(width: geo.size.width * CGFloat(defender / total))
                    Rectangle().fill(.red).frame(width: geo.size.width * CGFloat(attackers / total))
                }
                .clipShape(Capsule())
            }
            .frame(height: 5)
            .accessibilityHidden(true)
            HStack {
                Text("Defender \(defender.formatted(.percent.precision(.fractionLength(0))))")
                    .foregroundStyle(.green)
                Spacer()
                Text("Attackers \(attackers.formatted(.percent.precision(.fractionLength(0))))")
                    .foregroundStyle(.red)
            }
            .font(.system(size: 9).monospacedDigit())
        }
        .frame(maxWidth: 260)
        .padding(.top, 2)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Contest score")
        .accessibilityValue("Defender \(defender.formatted(.percent.precision(.fractionLength(0)))), attackers \(attackers.formatted(.percent.precision(.fractionLength(0))))")
    }
}

// MARK:  Structure Row

private struct StructureRow: View {
    let item: ESISovereigntyStructure
    let allianceName: String?

    @State private var systemName: String?
    @State private var regionName: String?
    @State private var securityStatus: Double?

    var body: some View {
        HStack(spacing: 12) {
            CachedAsyncImage(url: EVEImageURL.allianceLogo(item.allianceId, size: 64)) { $0.resizable().scaledToFit() }
            placeholder: { RoundedRectangle(cornerRadius: 6).fill(.quaternary) }
            .frame(width: 36, height: 36)
            .clipShape(RoundedRectangle(cornerRadius: 6))

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Label(SovereigntyFormat.structureName(item.structureTypeId),
                          systemImage: SovereigntyFormat.structureIcon(item.structureTypeId))
                        .font(.caption.bold())
                    if let sec = securityStatus {
                        Text(String(format: "%.1f", sec))
                            .font(.caption2.bold().monospacedDigit())
                            .foregroundStyle(sovSecColor(sec))
                    }
                    Text(systemName ?? "System #\(item.solarSystemId)")
                        .font(.subheadline)
                    if let regionName {
                        Text("· \(regionName)").font(.caption).foregroundStyle(.secondary)
                    }
                }
                Text(allianceName ?? "Alliance #\(item.allianceId)")
                    .font(.caption2).foregroundStyle(.tertiary)
                if let start = item.vulnerableStartTime, let end = item.vulnerableEndTime {
                    vulnerabilityLabel(start: start, end: end)
                }
            }

            Spacer(minLength: 0)

            if let adm = item.vulnerabilityOccupancyLevel {
                Text(String(format: "ADM %.1f", adm))
                    .font(.caption.bold().monospacedDigit())
                    .foregroundStyle(SovereigntyFormat.admColor(adm))
                    .padding(.horizontal, 7).padding(.vertical, 3)
                    .background(SovereigntyFormat.admColor(adm).opacity(0.15), in: Capsule())
            }
        }
        .padding(.vertical, 3)
        .task(id: item.solarSystemId) {
            guard systemName == nil else { return }
            if let sys = await UniverseCache.shared.solarSystem(id: item.solarSystemId) {
                systemName = sys.name
                securityStatus = sys.securityStatus
                if let con = await UniverseCache.shared.constellation(id: sys.constellationId),
                   let reg = await UniverseCache.shared.region(id: con.regionId) {
                    regionName = reg.name
                }
            }
        }
    }

    @ViewBuilder
    private func vulnerabilityLabel(start: Date, end: Date) -> some View {
        let now = Date()
        if now >= start && now < end {
            Text("Vulnerable now — ends \(SovereigntyFormat.countdown(to: end))")
                .font(.caption2).foregroundStyle(.red)
        } else if start > now && start.timeIntervalSinceNow < 48 * 3600 {
            Text("Vulnerable \(SovereigntyFormat.countdown(to: start))")
                .font(.caption2).foregroundStyle(.orange)
        }
    }
}

// MARK:  Detail Pane

private enum SovDetail: Identifiable {
    case campaign(ResolvedCampaign)
    case structure(ESISovereigntyStructure)
    case holder(AllianceHolding)

    static func campaignID(_ id: Int) -> String { "c\(id)" }
    static func structureID(_ id: Int) -> String { "s\(id)" }
    static func holderID(_ id: Int) -> String { "h\(id)" }

    var id: String {
        switch self {
        case .campaign(let c):  return Self.campaignID(c.id)
        case .structure(let s): return Self.structureID(s.id)
        case .holder(let h):    return Self.holderID(h.id)
        }
    }
}

private struct SovDetailPane: View {
    let detail: SovDetail
    let campaignsBySystem: [Int: ResolvedCampaign]
    let structuresBySystem: [Int: [ESISovereigntyStructure]]
    let sovMap: [ESISovereigntyMapEntry]
    let allianceNames: [Int: String]
    var onClose: () -> Void = {}

    @Environment(AccountManager.self) private var accountManager
    @State private var destMessage: String?

    private var title: String {
        switch detail {
        case .campaign:  return "Campaign"
        case .structure: return "Sovereignty Structure"
        case .holder:    return "Alliance Holdings"
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(title).font(.headline)
                Spacer()
                Button { onClose() } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .keyboardShortcut(.escape)
            }
            .padding(.horizontal, 14).padding(.vertical, 10)
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    switch detail {
                    case .campaign(let c):  campaignBody(c)
                    case .structure(let s): structureBody(s)
                    case .holder(let h):    holderBody(h)
                    }
                    if let destMessage {
                        Label(destMessage, systemImage: "paperplane.fill")
                            .font(.caption).foregroundStyle(.green)
                    }
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .frame(maxHeight: .infinity)
        .background(.regularMaterial)
    }

    // MARK: Campaign

    @ViewBuilder
    private func campaignBody(_ item: ResolvedCampaign) -> some View {
        let c = item.campaign
        let local = structuresBySystem[c.solarSystemId] ?? []
        let holder = local.first?.allianceId

        VStack(alignment: .leading, spacing: 6) {
            Label(SovereigntyFormat.eventLabel(c.eventType), systemImage: SovereigntyFormat.eventIcon(c.eventType))
                .font(.headline).foregroundStyle(.orange)
            Text(c.startTime.timeIntervalSinceNow <= 0
                 ? "In progress — started \(SovereigntyFormat.countdown(to: c.startTime))"
                 : "Starts \(SovereigntyFormat.countdown(to: c.startTime))")
                .font(.subheadline)
            Text(c.startTime.formatted(.dateTime.weekday().month().day().hour().minute()) + " local")
                .font(.caption).foregroundStyle(.secondary)
        }

        ResolvedSystemLine(systemId: c.solarSystemId, fallbackName: item.systemName)

        if let d = c.defenderScore, let a = c.attackersScore, d + a > 0 {
            scoreBar(defender: d, attackers: a)
        }

        AllianceInfoCard(allianceId: c.defenderId, role: "Defender", allianceNames: allianceNames)

        if let participants = c.participants, !participants.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                Text("ATTACKERS").font(.caption2.bold()).foregroundStyle(.tertiary)
                ForEach(participants.filter { $0.allianceId != c.defenderId }) { p in
                    HStack(spacing: 8) {
                        CachedAsyncImage(url: EVEImageURL.allianceLogo(p.allianceId, size: 32)) { $0.resizable().scaledToFit() }
                        placeholder: { RoundedRectangle(cornerRadius: 4).fill(.quaternary) }
                        .frame(width: 22, height: 22).clipShape(RoundedRectangle(cornerRadius: 4))
                        Text(allianceNames[p.allianceId] ?? "Alliance #\(p.allianceId)").font(.caption)
                        Spacer()
                        Text(p.score.formatted(.percent.precision(.fractionLength(0))))
                            .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                    }
                }
            }
        } else {
            Text("Attacker details not published for this campaign.")
                .font(.caption).foregroundStyle(.tertiary)
        }

        if let holder, holder != c.defenderId {
            metaRow("Current sov holder", allianceNames[holder] ?? "Alliance #\(holder)")
        }
        if let adm = local.compactMap(\.vulnerabilityOccupancyLevel).max() {
            metaRow("System ADM", String(format: "%.1f", adm))
        }

        systemActions(systemId: c.solarSystemId, systemName: item.systemName)
    }

    // MARK: Structure

    @ViewBuilder
    private func structureBody(_ s: ESISovereigntyStructure) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(SovereigntyFormat.structureName(s.structureTypeId),
                  systemImage: SovereigntyFormat.structureIcon(s.structureTypeId))
                .font(.headline)
            if let adm = s.vulnerabilityOccupancyLevel {
                Text(String(format: "Activity Defense Multiplier %.2f", adm))
                    .font(.subheadline)
                    .foregroundStyle(SovereigntyFormat.admColor(adm))
            }
        }

        ResolvedSystemLine(systemId: s.solarSystemId, fallbackName: "System #\(s.solarSystemId)")

        AllianceInfoCard(allianceId: s.allianceId, role: "Holder", allianceNames: allianceNames)

        if let start = s.vulnerableStartTime, let end = s.vulnerableEndTime {
            VStack(alignment: .leading, spacing: 2) {
                Text("VULNERABILITY WINDOW").font(.caption2.bold()).foregroundStyle(.tertiary)
                Text("\(start.formatted(.dateTime.weekday().hour().minute())) – \(end.formatted(.dateTime.weekday().hour().minute()))")
                    .font(.caption)
                let now = Date()
                if now >= start && now < end {
                    Text("Vulnerable now — ends \(SovereigntyFormat.countdown(to: end))")
                        .font(.caption2).foregroundStyle(.red)
                } else {
                    Text("Next window \(SovereigntyFormat.countdown(to: start))")
                        .font(.caption2).foregroundStyle(.orange)
                }
            }
        }

        let siblings = (structuresBySystem[s.solarSystemId] ?? []).filter { $0.id != s.id }
        if !siblings.isEmpty {
            VStack(alignment: .leading, spacing: 4) {
                Text("OTHER STRUCTURES HERE").font(.caption2.bold()).foregroundStyle(.tertiary)
                ForEach(siblings) { sib in
                    HStack(spacing: 6) {
                        Image(systemName: SovereigntyFormat.structureIcon(sib.structureTypeId)).font(.caption2)
                        Text(SovereigntyFormat.structureName(sib.structureTypeId)).font(.caption)
                        if let adm = sib.vulnerabilityOccupancyLevel {
                            Text(String(format: "ADM %.1f", adm)).font(.caption2)
                                .foregroundStyle(SovereigntyFormat.admColor(adm))
                        }
                    }
                }
            }
        }

        if let camp = campaignsBySystem[s.solarSystemId] {
            metaRow("Active campaign", "\(SovereigntyFormat.eventLabel(camp.campaign.eventType)) — \(SovereigntyFormat.countdown(to: camp.campaign.startTime))")
        }

        systemActions(systemId: s.solarSystemId, systemName: allianceNames[s.allianceId] ?? "system")
    }

    // MARK: Holder

    @ViewBuilder
    private func holderBody(_ h: AllianceHolding) -> some View {
        AllianceInfoCard(allianceId: h.allianceId, role: "Alliance", allianceNames: allianceNames)

        let allStructs = structuresBySystem.values.flatMap { $0 }.filter { $0.allianceId == h.allianceId }
        let tcus = allStructs.filter { $0.structureTypeId == 32226 }.count
        let ihubs = allStructs.filter { $0.structureTypeId == 32458 }.count
        let defending = campaignsBySystem.values.filter { $0.campaign.defenderId == h.allianceId }.count
        let attacking = campaignsBySystem.values.filter { c in
            (c.campaign.participants ?? []).contains { $0.allianceId == h.allianceId } && c.campaign.defenderId != h.allianceId
        }.count

        VStack(alignment: .leading, spacing: 8) {
            metaRow("Systems held", "\(h.systemCount)")
            metaRow("Territorial Claim Units", "\(tcus)")
            metaRow("Infrastructure Hubs", "\(ihubs)")
            metaRow("Defending campaigns", "\(defending)")
            metaRow("Attacking campaigns", "\(attacking)")
        }

        HStack(spacing: 8) {
            externalLink("zKillboard", "https://zkillboard.com/alliance/\(h.allianceId)/")
            if let name = allianceNames[h.allianceId] {
                externalLink("Dotlan", "https://evemaps.dotlan.net/alliance/\(name.replacingOccurrences(of: " ", with: "_"))")
            }
        }
    }

    // MARK: Shared pieces

    private func metaRow(_ label: String, _ value: String) -> some View {
        HStack(spacing: 6) {
            Text(label).font(.caption).foregroundStyle(.secondary)
            Spacer()
            Text(value).font(.caption.monospacedDigit())
        }
    }

    private func scoreBar(defender: Double, attackers: Double) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            GeometryReader { geo in
                let total = max(defender + attackers, 0.0001)
                HStack(spacing: 0) {
                    Rectangle().fill(.green).frame(width: geo.size.width * CGFloat(defender / total))
                    Rectangle().fill(.red).frame(width: geo.size.width * CGFloat(attackers / total))
                }
                .clipShape(Capsule())
            }
            .frame(height: 6)
            .accessibilityHidden(true)
            HStack {
                Text("Defender \(defender.formatted(.percent.precision(.fractionLength(0))))").foregroundStyle(.green)
                Spacer()
                Text("Attackers \(attackers.formatted(.percent.precision(.fractionLength(0))))").foregroundStyle(.red)
            }
            .font(.system(size: 10).monospacedDigit())
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Contest score")
        .accessibilityValue("Defender \(defender.formatted(.percent.precision(.fractionLength(0)))), attackers \(attackers.formatted(.percent.precision(.fractionLength(0))))")
    }

    @ViewBuilder
    private func systemActions(systemId: Int, systemName: String) -> some View {
        HStack(spacing: 8) {
            if accountManager.selectedAccount != nil {
                Button {
                    Task { await setDestination(systemId: systemId) }
                } label: {
                    Label("Set Destination", systemImage: "paperplane.fill").font(.caption.weight(.semibold))
                }
                .buttonStyle(.borderedProminent).controlSize(.small)
            }
            externalLink("zKillboard", "https://zkillboard.com/system/\(systemId)/")
        }
    }

    private func externalLink(_ label: String, _ urlString: String) -> some View {
        Group {
            if let url = URL(string: urlString) {
                Link(destination: url) {
                    Label(label, systemImage: "arrow.up.right.square").font(.caption)
                }
                .buttonStyle(.bordered).controlSize(.small)
            }
        }
    }

    private func setDestination(systemId: Int) async {
        guard let account = accountManager.selectedAccount,
              let token = try? await accountManager.validToken(for: account) else {
            destMessage = "Sign in to set a destination."
            return
        }
        do {
            try await ESIClient.shared.postAction("/ui/autopilot/waypoint/", token: token, queryItems: [
                URLQueryItem(name: "add_to_beginning", value: "false"),
                URLQueryItem(name: "clear_other_waypoints", value: "true"),
                URLQueryItem(name: "destination_id", value: "\(systemId)")
            ])
            destMessage = "Destination set in the EVE client."
        } catch {
            destMessage = "Couldn't set destination (needs esi-ui.write_waypoint.v1)."
        }
    }
}

// MARK:  Resolved System Line

private struct ResolvedSystemLine: View {
    let systemId: Int
    let fallbackName: String

    @State private var name: String?
    @State private var sec: Double?
    @State private var constellation: String?
    @State private var region: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("SYSTEM").font(.caption2.bold()).foregroundStyle(.tertiary)
            HStack(spacing: 6) {
                if let sec {
                    Text(String(format: "%.1f", sec))
                        .font(.caption.bold().monospacedDigit())
                        .foregroundStyle(sovSecColor(sec))
                }
                Text(name ?? fallbackName).font(.subheadline.bold())
            }
            let geo = [constellation, region].compactMap { $0 }.joined(separator: " · ")
            if !geo.isEmpty {
                Text(geo).font(.caption).foregroundStyle(.secondary)
            }
        }
        .task(id: systemId) {
            guard name == nil else { return }
            if let sys = await UniverseCache.shared.solarSystem(id: systemId) {
                name = sys.name
                sec = sys.securityStatus
                if let con = await UniverseCache.shared.constellation(id: sys.constellationId) {
                    constellation = con.name
                    if let reg = await UniverseCache.shared.region(id: con.regionId) { region = reg.name }
                }
            }
        }
    }
}

// MARK:  Alliance Info Card

private struct AllianceInfoCard: View {
    let allianceId: Int?
    var role: String = "Alliance"
    let allianceNames: [Int: String]

    @State private var info: ESIAlliancePublic?
    @State private var corpCount: Int?
    @State private var executorName: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(role.uppercased()).font(.caption2.bold()).foregroundStyle(.tertiary)
            if let allianceId {
                HStack(spacing: 12) {
                    CachedAsyncImage(url: EVEImageURL.allianceLogo(allianceId, size: 128)) { $0.resizable().scaledToFit() }
                    placeholder: { RoundedRectangle(cornerRadius: 8).fill(.quaternary) }
                    .frame(width: 52, height: 52).clipShape(RoundedRectangle(cornerRadius: 8))

                    VStack(alignment: .leading, spacing: 3) {
                        HStack(spacing: 6) {
                            Text(info?.name ?? allianceNames[allianceId] ?? "Alliance #\(allianceId)")
                                .font(.headline)
                            if let t = info?.ticker { Text("[\(t)]").font(.caption).foregroundStyle(.secondary) }
                        }
                        HStack(spacing: 12) {
                            if let corpCount {
                                Label("\(corpCount) corps", systemImage: "person.3.fill").font(.caption2)
                            }
                            if let d = info?.dateFounded {
                                Label(d.formatted(.dateTime.year().month().day()), systemImage: "calendar").font(.caption2)
                            }
                        }
                        .foregroundStyle(.secondary)
                        if let executorName {
                            Text("Executor: \(executorName)").font(.caption2).foregroundStyle(.tertiary)
                        }
                    }
                    Spacer()
                }
            } else {
                Text("Not published for this campaign.").font(.callout).foregroundStyle(.secondary)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 10))
        .task(id: allianceId) {
            guard let allianceId else { return }
            info = try? await ESIClient.shared.fetch("/alliances/\(allianceId)/")
            if let corps: [Int] = try? await ESIClient.shared.fetch("/alliances/\(allianceId)/corporations/") {
                corpCount = corps.count
            }
            if let exec = info?.executorCorporationId {
                executorName = await NameResolver.shared.resolve(id: exec)
            }
        }
    }
}

// MARK:  Holder Row

private struct HolderRow: View {
    let rank: Int
    let holding: AllianceHolding
    let maxCount: Int

    var body: some View {
        HStack(spacing: 12) {
            Text("\(rank)")
                .font(.caption.bold().monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: 22, alignment: .trailing)

            CachedAsyncImage(url: EVEImageURL.allianceLogo(holding.allianceId, size: 64)) { $0.resizable().scaledToFit() }
            placeholder: { RoundedRectangle(cornerRadius: 6).fill(.quaternary) }
            .frame(width: 32, height: 32)
            .clipShape(RoundedRectangle(cornerRadius: 6))

            VStack(alignment: .leading, spacing: 3) {
                Text(holding.name).font(.subheadline)
                GeometryReader { geo in
                    let frac = maxCount > 0 ? CGFloat(holding.systemCount) / CGFloat(maxCount) : 0
                    ZStack(alignment: .leading) {
                        Capsule().fill(.quaternary).frame(height: 5)
                        Capsule().fill(.blue.opacity(0.7)).frame(width: max(2, geo.size.width * frac), height: 5)
                    }
                }
                .frame(height: 5)
            }

            Text("\(holding.systemCount)")
                .font(.subheadline.bold().monospacedDigit())
                .frame(width: 44, alignment: .trailing)
        }
        .padding(.vertical, 4)
    }
}
