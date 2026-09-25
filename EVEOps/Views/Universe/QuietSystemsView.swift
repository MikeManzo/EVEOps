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

// MARK:  Quiet Systems
//
// A signature-hunting aid: every k-space (+ Pochven) system ranked by how little
// traffic passed through it in the last hour (ESI `system_jumps`), cross-checked
// against `system_kills` so camped pockets drop out, and optionally limited to a
// jump radius of the signed-in character's current system. Rows hand off to the
// in-game autopilot ("Set Destination") or the Route Planner ("Plan Route").

struct QuietSystemsView: View {
    @Environment(AccountManager.self) private var accountManager
    @Environment(ThemeManager.self) private var themeManager
    private var palette: EVEPalette { themeManager.palette }

    // Universe + activity data
    @State private var systems: [TopoSystem] = []
    @State private var adjacency: [Int: [Int]] = [:]
    @State private var trafficPerHour: [Int: Int] = [:]   // ship jumps through the system
    @State private var killsPerHour: [Int: Int] = [:]     // ship + pod kills
    @State private var regionNames: [Int: String] = [:]
    @State private var distanceFromOrigin: [Int: Int] = [:]
    @State private var originSystemId: Int?
    @State private var originName: String?
    @State private var danger: SystemDangerService.Snapshot?
    @State private var dangerFetchedAt: Date?

    @State private var isLoading = false
    @State private var didLoad = false
    @State private var loadError: String?

    // Filters — persisted so they survive leaving/returning to the tab and app restarts.
    @AppStorage("quietSystems.bands") private var bandsRaw = "Low,Null"
    @AppStorage("quietSystems.maxKills") private var maxKills = 0
    @AppStorage("quietSystems.maxJumps") private var maxJumps = 10
    @AppStorage("quietSystems.limitToRange") private var limitToRange = true

    // Grouping — also persisted.
    @AppStorage("quietSystems.groupBy") private var groupBy: GroupMode = .region
    @AppStorage("quietSystems.collapsedGroups") private var collapsedGroupsRaw = ""

    private var bands: Set<SecBand> {
        get { Set(bandsRaw.split(separator: ",").compactMap { SecBand(rawValue: String($0)) }) }
        nonmutating set {
            bandsRaw = SecBand.allCases.filter(newValue.contains).map(\.rawValue).joined(separator: ",")
        }
    }

    private var collapsedGroups: Set<String> {
        get { Set(collapsedGroupsRaw.split(separator: ",").map(String.init)) }
        nonmutating set { collapsedGroupsRaw = newValue.sorted().joined(separator: ",") }
    }

    @State private var selectedId: Int?
    @State private var selectedConstellation: String?
    @State private var toast: String?

    private static let pochvenRegionID = 10_000_070
    private static let rowCap = 400

    enum SecBand: String, CaseIterable, Identifiable {
        case high = "High", low = "Low", null = "Null", pochven = "Pochven"
        var id: String { rawValue }
    }

    enum GroupMode: String, CaseIterable, Identifiable {
        case region = "Region", distance = "Distance", none = "None"
        var id: String { rawValue }
    }

    struct Row: Identifiable {
        let id: Int
        let name: String
        let security: Double
        let regionID: Int
        let region: String
        let constellationID: Int
        let traffic: Int
        let kills: Int
        let distance: Int?
    }

    struct SystemSection: Identifiable {
        let id: String       // namespaced key, e.g. "r10000042" or "d1"
        let title: String
        let order: Int        // for fixed-order (distance) grouping
        let rows: [Row]
    }

    /// Distance grouping only makes sense with a known origin; otherwise fall back to flat.
    private var effectiveGroupBy: GroupMode {
        (groupBy == .distance && originSystemId == nil) ? .none : groupBy
    }

    // MARK:  Body

    var body: some View {
        let rows = results
        let sections = groupedSections(rows)
        HStack(spacing: 0) {
            VStack(spacing: 0) {
                filterBar(rowCount: rows.count, sectionKeys: sections.map(\.id))
                Divider()

                if !didLoad {
                    loadingRow
                } else if let loadError {
                    errorRow(loadError)
                } else if rows.isEmpty {
                    emptyRow
                } else if effectiveGroupBy == .none {
                    List(rows) { row in
                        listRow(row)
                    }
                    .listStyle(.plain)
                } else {
                    List {
                        ForEach(sections) { section in
                            let collapsed = collapsedGroups.contains(section.id)
                            Section {
                                if !collapsed {
                                    ForEach(section.rows) { row in listRow(row) }
                                }
                            } header: {
                                sectionHeader(section, collapsed: collapsed)
                            }
                        }
                    }
                    .listStyle(.plain)
                }

                if let toast {
                    Text(toast)
                        .font(.caption)
                        .padding(.horizontal, 12).padding(.vertical, 6)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(.quaternary)
                        .transition(.opacity)
                }
            }

            if let selected = rows.first(where: { $0.id == selectedId }) {
                Divider()
                detailPane(selected)
                    .frame(width: 320)
                    .transition(.move(edge: .trailing).combined(with: .opacity))
            }
        }
        .animation(.easeInOut(duration: 0.15), value: selectedId)
        .task { await load() }
        .onChange(of: accountManager.selectedAccount?.characterID) { _, _ in
            Task { await resolveOrigin() }
        }
        .onChange(of: selectedId) { _, _ in
            selectedConstellation = nil
            Task { await resolveConstellation() }
        }
        .onChange(of: toast) { _, newValue in
            guard newValue != nil else { return }
            Task {
                try? await Task.sleep(for: .seconds(3))
                withAnimation { toast = nil }
            }
        }
    }

    // MARK:  Filter bar

    private func filterBar(rowCount: Int, sectionKeys: [String]) -> some View {
        HStack(spacing: 10) {
            ForEach(SecBand.allCases) { band in
                Toggle(band.rawValue, isOn: bandBinding(band))
                    .toggleStyle(.button)
                    .controlSize(.small)
            }

            Divider().frame(height: 16)

            Stepper(value: $maxKills, in: 0...50) {
                Text("≤ \(maxKills) kill\(maxKills == 1 ? "" : "s")/h")
                    .font(.caption.monospacedDigit())
            }
            .fixedSize()

            if originSystemId != nil {
                Divider().frame(height: 16)
                Toggle(isOn: $limitToRange) {
                    Text("Within").font(.caption)
                }
                .toggleStyle(.checkbox)
                Stepper(value: $maxJumps, in: 1...50) {
                    Text("\(maxJumps) jump\(maxJumps == 1 ? "" : "s") of \(originName ?? "me")")
                        .font(.caption.monospacedDigit())
                }
                .fixedSize()
                .disabled(!limitToRange)
            }

            Divider().frame(height: 16)

            Picker("Group", selection: $groupBy) {
                ForEach(GroupMode.allCases) { mode in
                    if mode != .distance || originSystemId != nil {
                        Text("Group: \(mode.rawValue)").tag(mode)
                    }
                }
            }
            .pickerStyle(.menu)
            .fixedSize()
            .labelsHidden()

            if effectiveGroupBy != .none, !sectionKeys.isEmpty {
                let allCollapsed = sectionKeys.allSatisfy { collapsedGroups.contains($0) }
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        setAllCollapsed(sectionKeys, collapsed: !allCollapsed)
                    }
                } label: {
                    Image(systemName: allCollapsed ? "chevron.down.circle" : "chevron.up.circle")
                }
                .accessibilityLabel("Expand or Collapse")
                .buttonStyle(.plain)
                .help(allCollapsed ? "Expand all sections" : "Collapse all sections")
            }

            Spacer()

            if let dangerFetchedAt {
                RelativeTimestamp(date: dangerFetchedAt, prefix: "Activity")
            }
            Text("\(rowCount) system\(rowCount == 1 ? "" : "s")")
                .font(.caption).foregroundStyle(.secondary)
            RefreshButton(isRefreshing: isLoading) {
                Task { await load(force: true) }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }

    private func bandBinding(_ band: SecBand) -> Binding<Bool> {
        Binding(
            get: { bands.contains(band) },
            set: { on in
                var next = bands
                if on { next.insert(band) } else { next.remove(band) }
                bands = next
            }
        )
    }

    // MARK:  Rows

    /// A system row wired for selection, shared by the flat and grouped lists.
    private func listRow(_ row: Row) -> some View {
        systemRow(row)
            .listRowInsets(.init(top: 6, leading: 12, bottom: 6, trailing: 12))
            .listRowBackground(selectedId == row.id ? palette.accent.opacity(0.12) : Color.clear)
            .contentShape(Rectangle())
            .onTapGesture { selectedId = (selectedId == row.id) ? nil : row.id }
    }

    private func systemRow(_ row: Row) -> some View {
        HStack(spacing: 10) {
            Text(String(format: "%.1f", max(0, row.security)))
                .font(.caption.bold().monospacedDigit())
                .foregroundStyle(eveSecurityColor(row.security))
                .frame(width: 30, alignment: .center)
                .padding(.vertical, 2)
                .background(eveSecurityColor(row.security).opacity(0.15), in: RoundedRectangle(cornerRadius: EVERadius.sm))

            VStack(alignment: .leading, spacing: 1) {
                Text(row.name).font(.callout.weight(.medium))
                Text(row.region).font(.caption2).foregroundStyle(.secondary)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 1) {
                Text("\(row.traffic) traffic/h")
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(row.traffic == 0 ? Color.green : .secondary)
                HStack(spacing: 6) {
                    if row.kills > 0 {
                        Text("\(row.kills) kill\(row.kills == 1 ? "" : "s")/h")
                            .foregroundStyle(.orange)
                    }
                    if let d = row.distance {
                        Text("\(d) jump\(d == 1 ? "" : "s") away")
                            .foregroundStyle(.tertiary)
                    }
                }
                .font(.caption2.monospacedDigit())
            }
        }
    }

    private var loadingRow: some View {
        HStack(spacing: 8) {
            ProgressView().controlSize(.small)
            Text("Loading galaxy activity…").font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func errorRow(_ message: String) -> some View {
        ContentUnavailableView("Couldn't load", systemImage: "exclamationmark.triangle", description: Text(message))
    }

    private var emptyRow: some View {
        ContentUnavailableView(
            "No systems match",
            systemImage: "sparkle.magnifyingglass",
            description: Text("Loosen the filters — raise the kill limit, widen the jump radius, or add a security band.")
        )
    }

    // MARK:  Grouping

    /// Splits the already-sorted rows into sections. Rows keep their global
    /// traffic→distance order within each section; sections are ordered so the
    /// one containing the single quietest system comes first (distance mode uses
    /// its natural bucket order instead).
    private func groupedSections(_ rows: [Row]) -> [SystemSection] {
        switch effectiveGroupBy {
        case .none:
            return [SystemSection(id: "all", title: "", order: 0, rows: rows)]

        case .region:
            var byKey: [String: [Row]] = [:]
            for r in rows { byKey["r\(r.regionID)", default: []].append(r) }
            return byKey.map { key, rs in
                SystemSection(id: key, title: rs.first?.region ?? "—", order: 0, rows: rs)
            }
            .sorted { a, b in
                let at = a.rows.map(\.traffic).min() ?? .max
                let bt = b.rows.map(\.traffic).min() ?? .max
                if at != bt { return at < bt }
                let ad = a.rows.compactMap(\.distance).min() ?? .max
                let bd = b.rows.compactMap(\.distance).min() ?? .max
                if ad != bd { return ad < bd }
                return a.title < b.title
            }

        case .distance:
            var byKey: [String: (title: String, order: Int, rows: [Row])] = [:]
            for r in rows {
                let bucket = distanceBucket(r.distance)
                byKey[bucket.key, default: (bucket.title, bucket.order, [])].rows.append(r)
            }
            return byKey
                .map { key, v in SystemSection(id: key, title: v.title, order: v.order, rows: v.rows) }
                .sorted { $0.order < $1.order }
        }
    }

    private func distanceBucket(_ distance: Int?) -> (key: String, title: String, order: Int) {
        guard let d = distance else { return ("d9", "Unreachable", 9) }
        switch d {
        case 0:      return ("d0", "Current system", 0)
        case 1...3:  return ("d1", "1–3 jumps", 1)
        case 4...6:  return ("d2", "4–6 jumps", 2)
        case 7...10: return ("d3", "7–10 jumps", 3)
        default:     return ("d4", "11+ jumps", 4)
        }
    }

    private func sectionHeader(_ section: SystemSection, collapsed: Bool) -> some View {
        let quietest = section.rows.map(\.traffic).min() ?? 0
        let nearest = section.rows.compactMap(\.distance).min()
        return Button {
            withAnimation(.easeInOut(duration: 0.2)) { toggleCollapsed(section.id) }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: collapsed ? "chevron.right" : "chevron.down")
                    .font(.caption2).foregroundStyle(.secondary).frame(width: 12)
                Text(section.title).font(.caption.bold()).foregroundStyle(.primary)
                Text("\(section.rows.count)").font(.caption2).foregroundStyle(.tertiary)
                Spacer()
                Text("quietest \(quietest)/h")
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(quietest == 0 ? Color.green : .secondary)
                if let nearest {
                    Text("· \(nearest)j").font(.caption2.monospacedDigit()).foregroundStyle(.tertiary)
                }
            }
            .padding(.vertical, 4)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .textCase(nil)
    }

    private func toggleCollapsed(_ key: String) {
        var set = collapsedGroups
        if set.contains(key) { set.remove(key) } else { set.insert(key) }
        collapsedGroups = set
    }

    private func setAllCollapsed(_ keys: [String], collapsed: Bool) {
        var set = collapsedGroups
        if collapsed { set.formUnion(keys) } else { set.subtract(keys) }
        collapsedGroups = set
    }

    // MARK:  Results

    private func band(for s: TopoSystem) -> SecBand {
        if s.regionID == Self.pochvenRegionID { return .pochven }
        if s.security >= 0.45 { return .high }
        if s.security > 0.0 { return .low }
        return .null
    }

    private var results: [Row] {
        guard !systems.isEmpty else { return [] }
        let proximity = limitToRange && originSystemId != nil

        var rows: [Row] = []
        rows.reserveCapacity(256)
        for s in systems {
            guard bands.contains(band(for: s)) else { continue }
            let kills = killsPerHour[s.id] ?? 0
            guard kills <= maxKills else { continue }

            let dist = distanceFromOrigin[s.id]
            if proximity, s.id != originSystemId {
                guard let dist, dist <= maxJumps else { continue }
            }

            rows.append(Row(
                id: s.id,
                name: s.name,
                security: s.security,
                regionID: s.regionID,
                region: regionNames[s.regionID] ?? "—",
                constellationID: s.constellationID,
                traffic: trafficPerHour[s.id] ?? 0,
                kills: kills,
                distance: dist
            ))
        }

        rows.sort {
            if $0.traffic != $1.traffic { return $0.traffic < $1.traffic }
            return ($0.distance ?? .max) < ($1.distance ?? .max)
        }
        return Array(rows.prefix(Self.rowCap))
    }

    // MARK:  Loading

    private func load(force: Bool = false) async {
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false; didLoad = true }
        loadError = nil

        async let topoTask = UniverseTopology.shared.load()
        async let snapTask: SystemDangerService.Snapshot? = {
            try? await SystemDangerService.shared.snapshot(forceRefresh: force)
        }()
        async let regionsTask = UniverseCache.shared.knownSpaceRegions()

        guard let topo = await topoTask else {
            loadError = "Couldn't load the galaxy map data. Check your connection and try again."
            return
        }

        systems = topo.systems

        var adj: [Int: [Int]] = [:]
        adj.reserveCapacity(topo.systems.count)
        for (a, b) in topo.jumps {
            adj[a, default: []].append(b)
            adj[b, default: []].append(a)
        }
        adjacency = adj

        if let snap = await snapTask {
            danger = snap
            dangerFetchedAt = snap.fetchedAt
            var traffic: [Int: Int] = [:]
            var kills: [Int: Int] = [:]
            for s in topo.systems {
                let d = snap.danger(for: s.id)
                if d.shipJumps > 0 { traffic[s.id] = d.shipJumps }
                let combat = d.shipKills + d.podKills
                if combat > 0 { kills[s.id] = combat }
            }
            trafficPerHour = traffic
            killsPerHour = kills
        }

        let regions = await regionsTask
        regionNames = Dictionary(regions.map { ($0.id, $0.name) }, uniquingKeysWith: { a, _ in a })

        await resolveOrigin()
    }

    /// Resolves the signed-in character's current system and rebuilds the jump-distance map.
    private func resolveOrigin() async {
        guard let account = accountManager.selectedAccount,
              let token = try? await accountManager.validToken(for: account),
              let loc: ESICharacterLocation = try? await ESIClient.shared.fetch(
                  "/characters/\(account.characterID)/location/", token: token, bypassCache: true)
        else {
            // No character / location — proximity is meaningless. The filter bar
            // hides the "Within N jumps" controls while `originSystemId` is nil, and
            // `results` ignores `limitToRange` in that case, so leave the user's
            // saved preference untouched.
            originSystemId = nil
            originName = nil
            distanceFromOrigin = [:]
            return
        }
        originSystemId = loc.solarSystemId
        originName = await UniverseCache.shared.solarSystem(id: loc.solarSystemId)?.name
        recomputeDistances()
    }

    /// Breadth-first jump distance from the origin over the stargate graph.
    private func recomputeDistances() {
        guard let origin = originSystemId, !adjacency.isEmpty else {
            distanceFromOrigin = [:]
            return
        }
        var dist: [Int: Int] = [origin: 0]
        var queue = [origin]
        var head = 0
        while head < queue.count {
            let current = queue[head]
            head += 1
            let next = dist[current]! + 1
            for neighbour in adjacency[current] ?? [] where dist[neighbour] == nil {
                dist[neighbour] = next
                queue.append(neighbour)
            }
        }
        distanceFromOrigin = dist
    }

    // MARK:  Actions

    private func setDestination(_ row: Row) async {
        switch await AutopilotService.setDestination(systemId: row.id, accountManager: accountManager) {
        case .ok:
            withAnimation { toast = "Destination set: \(row.name)" }
        case .notSignedIn:
            withAnimation { toast = "Sign in to set a destination." }
        case .missingScope:
            withAnimation { toast = "Requires esi-ui.write_waypoint.v1 scope — re-add your character with updated permissions." }
        case .failed(let message):
            withAnimation { toast = message }
        }
    }

    private func planRoute(_ row: Row) {
        AppRouter.shared.pendingRoute = .init(originId: originSystemId, destinationId: row.id)
        AppRouter.shared.pendingSection = .routePlanner
    }

    private func resolveConstellation() async {
        guard let id = selectedId,
              let system = systems.first(where: { $0.id == id }) else { return }
        let name = await UniverseCache.shared.constellation(id: system.constellationID)?.name
        // Guard against a late result for a row the user already moved off.
        if selectedId == id { selectedConstellation = name }
    }

    // MARK:  Detail pane

    private func secClassLabel(_ row: Row) -> String {
        if row.regionID == Self.pochvenRegionID { return "Pochven" }
        if row.security >= 0.45 { return "Highsec" }
        if row.security > 0.0 { return "Lowsec" }
        return "Nullsec" + (row.security <= -0.99 ? " (unrated)" : "")
    }

    @ViewBuilder
    private func detailPane(_ row: Row) -> some View {
        let activity = danger?.danger(for: row.id) ?? SystemDanger.none
        let level = DangerLevel(combatKills: activity.combatKills)

        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Text(row.name).font(.headline)
                Spacer()
                Button { selectedId = nil } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                }
                .accessibilityLabel("Clear")
                .buttonStyle(.plain)
                .keyboardShortcut(.escape)
            }
            .padding(.horizontal, 14).padding(.vertical, 10)
            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    // Location
                    VStack(alignment: .leading, spacing: 6) {
                        detailRow("Security") {
                            HStack(spacing: 6) {
                                Text(String(format: "%.2f", row.security))
                                    .foregroundStyle(eveSecurityColor(row.security))
                                    .monospacedDigit()
                                Text(secClassLabel(row)).foregroundStyle(.secondary)
                            }
                            .font(.caption)
                        }
                        detailRow("Region") { Text(row.region).font(.caption) }
                        detailRow("Constellation") {
                            Text(selectedConstellation ?? "…")
                                .font(.caption)
                                .foregroundStyle(selectedConstellation == nil ? .tertiary : .primary)
                        }
                        if let d = row.distance {
                            detailRow("Distance") {
                                Text("\(d) jump\(d == 1 ? "" : "s") from \(originName ?? "you")").font(.caption)
                            }
                        }
                    }
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: EVERadius.lg))

                    // Activity (last hour)
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text("ACTIVITY").font(.caption2.bold()).foregroundStyle(.tertiary)
                            Spacer()
                            if let dangerFetchedAt {
                                Text(dangerFetchedAt, format: .relative(presentation: .named))
                                    .font(.caption2).foregroundStyle(.tertiary)
                            }
                        }
                        detailRow("Traffic") {
                            Text("\(activity.shipJumps) ship jump\(activity.shipJumps == 1 ? "" : "s")/h")
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(activity.shipJumps == 0 ? Color.green : .primary)
                        }
                        detailRow("Ship kills") {
                            Text("\(activity.shipKills)").font(.caption.monospacedDigit())
                                .foregroundStyle(activity.shipKills == 0 ? Color.secondary : Color.orange)
                        }
                        detailRow("Pod kills") {
                            Text("\(activity.podKills)").font(.caption.monospacedDigit())
                                .foregroundStyle(activity.podKills == 0 ? Color.secondary : Color.orange)
                        }
                        detailRow("NPC kills") {
                            Text("\(activity.npcKills)").font(.caption.monospacedDigit())
                                .foregroundStyle(.secondary)
                        }
                        detailRow("Assessment") {
                            Text(activity.combatKills == 0 ? "Quiet — no PvP in the last hour" : "\(level.label) · \(activity.combatKills) kills/h")
                                .font(.caption)
                                .foregroundStyle(activity.combatKills == 0 ? Color.green : dangerColor(level))
                        }
                    }
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: EVERadius.lg))

                    // Actions
                    VStack(spacing: 8) {
                        if accountManager.selectedAccount != nil {
                            Button {
                                Task { await setDestination(row) }
                            } label: {
                                Label("Set Destination", systemImage: "paperplane.fill")
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.borderedProminent)
                        }
                        Button {
                            planRoute(row)
                        } label: {
                            Label("Plan Route", systemImage: "point.3.connected.trianglepath.dotted")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                        Button {
                            AppRouter.shared.pendingSection = .galaxyMap
                        } label: {
                            Label("Open Galaxy Map", systemImage: "globe")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                    }
                    .controlSize(.small)

                    Text("Traffic and kill figures come from EVE's hourly aggregates — a low count means quiet in the last ~60 minutes, not a guarantee.")
                        .font(.caption2).foregroundStyle(.tertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .frame(maxHeight: .infinity)
        .background(EVESurface.panel)
    }

    private func detailRow(_ label: String, @ViewBuilder value: () -> some View) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label)
                .font(.caption).foregroundStyle(.secondary)
                .frame(width: 92, alignment: .leading)
            value()
            Spacer(minLength: 0)
        }
    }
}
