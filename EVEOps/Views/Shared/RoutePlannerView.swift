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
import OSLog

// MARK:  Selected System

struct SelectedSystem: Equatable {
    let id: Int
    let name: String
    let securityStatus: Double
}

// MARK:  Route Planner View

struct RoutePlannerView: View {
    @Environment(AccountManager.self) private var accountManager
    @State private var originSystem: SelectedSystem?
    @State private var destinationSystem: SelectedSystem?
    @State private var routeFlag = "shortest"
    @State private var avoidSystems: [SelectedSystem] = []
    @State private var avoidSystemPicker: SelectedSystem?
    @State private var route: [RouteSystem] = []
    @State private var isCalculating = false
    @State private var errorMessage: String?

    // Route-danger overlay (ESI system_kills / system_jumps, refreshed hourly by CCP)
    @State private var avoidDanger = false
    @State private var dangerThreshold = 5
    @State private var dangerSnapshotAt: Date?
    @State private var autoAvoidedCount = 0
    @State private var autopilotMessage: String?
    @State private var isSettingAutopilot = false
    @State private var theraConnections: [EVEScoutConnection] = []
    @State private var isLoadingThera = false
    @State private var theraError: String?
    @State private var showTheraInfo = false
    @State private var theraExpanded = true
    @State private var selectedTheraId: String?

    private var canPlot: Bool {
        originSystem != nil && destinationSystem != nil && !isCalculating
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                inputPanel
                if isCalculating { calculatingView }
                if !route.isEmpty { routePanel }
                theraConnectionsPanel
            }
            .padding()
        }
        .safeAreaInset(edge: .top, spacing: 0) {
            HStack {
                Text("Route Planner")
                    .font(.largeTitle.bold())
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(.background)
        }
        .navigationTitle("")
        .task { await loadTheraConnections() }
    }

    // MARK:  Input Panel

    private var inputPanel: some View {
        GroupBox {
            VStack(spacing: 14) {
                // Origin / Destination row
                HStack(alignment: .bottom, spacing: 8) {
                    SystemSearchField(
                        label: "Origin",
                        icon: "location.fill",
                        iconColor: .blue,
                        placeholder: "e.g. Jita",
                        selectedSystem: $originSystem
                    )

                    // Swap button
                    Button {
                        let temp = originSystem
                        originSystem = destinationSystem
                        destinationSystem = temp
                    } label: {
                        Image(systemName: "arrow.left.arrow.right")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(.secondary)
                            .frame(width: 28, height: 28)
                            .background(.quaternary, in: RoundedRectangle(cornerRadius: 6))
                    }
                    .buttonStyle(.plain)
                    .padding(.bottom, 1)

                    SystemSearchField(
                        label: "Destination",
                        icon: "mappin.circle.fill",
                        iconColor: .green,
                        placeholder: "e.g. Amarr",
                        selectedSystem: $destinationSystem
                    )
                }

                Divider()

                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Route Type").font(.caption).foregroundStyle(.secondary)
                        Picker("Route Type", selection: $routeFlag) {
                            Text("Shortest").tag("shortest")
                            Text("Secure (0.5+)").tag("secure")
                            Text("Insecure (<0.5)").tag("insecure")
                        }
                        .pickerStyle(.segmented)
                        .frame(maxWidth: 360)
                    }

                    Spacer()

                    Button {
                        Task { await plotRoute() }
                    } label: {
                        Label("Plot Route", systemImage: "arrow.triangle.turn.up.right.circle.fill")
                            .frame(minWidth: 110)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(!canPlot)
                }

                Divider()

                VStack(alignment: .leading, spacing: 8) {
                    SystemSearchField(
                        label: "Avoid Systems",
                        icon: "xmark.octagon.fill",
                        iconColor: .red,
                        placeholder: "e.g. Rancer",
                        selectedSystem: $avoidSystemPicker
                    )
                    .onChange(of: avoidSystemPicker) { _, newValue in
                        guard let picked = newValue else { return }
                        let isEndpoint = picked.id == originSystem?.id || picked.id == destinationSystem?.id
                        let alreadyAvoided = avoidSystems.contains { $0.id == picked.id }
                        if !isEndpoint && !alreadyAvoided {
                            avoidSystems.append(picked)
                        }
                        avoidSystemPicker = nil
                    }

                    if !avoidSystems.isEmpty {
                        FlowLayout(spacing: 6) {
                            ForEach(avoidSystems, id: \.id) { system in
                                HStack(spacing: 4) {
                                    Text(system.name)
                                        .font(.caption)
                                    Button {
                                        avoidSystems.removeAll { $0.id == system.id }
                                    } label: {
                                        Image(systemName: "xmark.circle.fill")
                                            .font(.caption2)
                                    }
                                    .buttonStyle(.plain)
                                }
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(.red.opacity(0.12), in: Capsule())
                                .foregroundStyle(.red)
                            }
                        }
                    }
                }

                Divider()

                dangerAvoidanceControls

                if let errorMessage {
                    HStack(spacing: 6) {
                        Image(systemName: "exclamationmark.triangle.fill")
                        Text(errorMessage)
                    }
                    .foregroundStyle(.red)
                    .font(.caption)
                    .padding(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(.red.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
                }
            }
        } label: {
            Label("Route Planner", systemImage: "map.fill")
        }
    }

    // MARK:  Danger Avoidance

    private var dangerAvoidanceControls: some View {
        VStack(alignment: .leading, spacing: 8) {
            Toggle(isOn: $avoidDanger) {
                Label("Route around recent kills", systemImage: "flame.fill")
                    .font(.caption.weight(.medium))
            }
            .toggleStyle(.checkbox)

            if avoidDanger {
                HStack(spacing: 6) {
                    Text("Avoid systems with more than")
                        .font(.caption).foregroundStyle(.secondary)
                    Stepper(value: $dangerThreshold, in: 0...50) {
                        Text("\(dangerThreshold)")
                            .font(.caption.bold().monospacedDigit())
                            .frame(minWidth: 18)
                    }
                    .fixedSize()
                    Text("ship + pod kills in the last hour")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Text("Uses EVE's hourly kill map. Origin and destination are never skipped, even if hot.")
                    .font(.caption2).foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var calculatingView: some View {
        HStack(spacing: 10) {
            ProgressView()
            Text("Calculating route…")
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding()
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 10))
    }

    // MARK:  Route Panel

    private var routePanel: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 0) {
                // Header
                HStack(alignment: .center) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("\(originSystem?.name ?? "") → \(destinationSystem?.name ?? "")")
                            .font(.headline)
                        HStack(spacing: 6) {
                            Text("\(route.count - 1) jump\(route.count == 2 ? "" : "s")")
                            if autoAvoidedCount > 0 {
                                Text("· routed around \(autoAvoidedCount) hot system\(autoAvoidedCount == 1 ? "" : "s")")
                                    .foregroundStyle(dangerColor(.high))
                            }
                            if let dangerSnapshotAt {
                                Text("· kills as of \(dangerSnapshotAt, format: .relative(presentation: .named))")
                            }
                        }
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }
                    Spacer()
                    routeRiskSummary
                    securitySummary

                    if accountManager.selectedAccount != nil {
                        Button {
                            Task { await setFullAutopilotRoute() }
                        } label: {
                            Label(isSettingAutopilot ? "Setting…" : "Set Autopilot", systemImage: "paperplane.fill")
                                .font(.caption.weight(.semibold))
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .disabled(isSettingAutopilot)
                        .padding(.leading, 8)
                    }
                }
                .padding(.bottom, 8)

                if let autopilotMessage {
                    HStack(spacing: 6) {
                        Image(systemName: autopilotMessage.hasPrefix("Route set") ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                            .foregroundStyle(autopilotMessage.hasPrefix("Route set") ? .green : .orange)
                        Text(autopilotMessage)
                    }
                    .font(.caption)
                    .padding(.bottom, 8)
                }

                Divider()

                LazyVStack(spacing: 0) {
                    ForEach(Array(route.enumerated()), id: \.offset) { index, system in
                        RouteSystemRow(
                            system: system,
                            jumpNumber: index + 1,
                            isLast: index == route.count - 1,
                            isFirst: index == 0,
                            showWaypointButton: accountManager.selectedAccount != nil,
                            onSetDestination: { await setWaypoint(systemId: system.id, clear: true) },
                            onAddWaypoint: { await setWaypoint(systemId: system.id, clear: false) }
                        )
                    }
                }
            }
        } label: {
            Label("Route", systemImage: "arrow.triangle.turn.up.right.circle.fill")
        }
    }

    private var securitySummary: some View {
        HStack(spacing: 6) {
            let highSec = route.filter { $0.securityStatus >= 0.5 }.count
            let lowSec = route.filter { $0.securityStatus > 0.0 && $0.securityStatus < 0.5 }.count
            let nullSec = route.filter { $0.securityStatus <= 0.0 }.count
            if highSec > 0 { secPill("\(highSec)H", color: .blue) }
            if lowSec > 0 { secPill("\(lowSec)L", color: .orange) }
            if nullSec > 0 { secPill("\(nullSec)N", color: .red) }
        }
    }

    private func secPill(_ label: String, color: Color) -> some View {
        Text(label)
            .font(.caption2.bold().monospacedDigit())
            .foregroundStyle(color)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(color.opacity(0.15), in: Capsule())
    }

    // MARK:  Route Risk

    @ViewBuilder
    private var routeRiskSummary: some View {
        let totalKills = route.reduce(0) { $0 + $1.danger.combatKills }
        let peak = route.max { $0.danger.combatKills < $1.danger.combatKills }
        let level = DangerLevel(combatKills: peak?.danger.combatKills ?? 0)
        let color = dangerColor(level)

        HStack(spacing: 5) {
            Image(systemName: totalKills == 0 ? "checkmark.shield.fill" : "flame.fill")
                .font(.caption2)
                .accessibilityHidden(true)
            Text(totalKills == 0 ? "Clear" : "\(totalKills) kill\(totalKills == 1 ? "" : "s")/h")
                .font(.caption2.bold().monospacedDigit())
        }
        .foregroundStyle(totalKills == 0 ? Color.green : color)
        .padding(.horizontal, 7)
        .padding(.vertical, 3)
        .background((totalKills == 0 ? Color.green : color).opacity(0.15), in: Capsule())
        .help(riskTooltip(totalKills: totalKills, peak: peak))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Route risk")
        .accessibilityValue(totalKills == 0
            ? "Clear, no kills reported in the last hour"
            : "\(totalKills) ship and pod kills per hour across the route")
    }

    private func riskTooltip(totalKills: Int, peak: RouteSystem?) -> String {
        guard totalKills > 0, let peak, peak.danger.combatKills > 0 else {
            return "No ship or pod kills reported on this route in the last hour."
        }
        return "\(totalKills) ship + pod kills across the route in the last hour. "
             + "Busiest: \(peak.name) (\(peak.danger.shipKills) ship, \(peak.danger.podKills) pod)."
    }

    // MARK:  Autopilot

    private func setWaypoint(systemId: Int, clear: Bool) async {
        guard let account = accountManager.selectedAccount else { return }
        autopilotMessage = nil
        do {
            let token = try await accountManager.validToken(for: account)
            try await ESIClient.shared.postAction(
                "/ui/autopilot/waypoint/",
                token: token,
                queryItems: [
                    URLQueryItem(name: "add_to_beginning", value: "false"),
                    URLQueryItem(name: "clear_other_waypoints", value: clear ? "true" : "false"),
                    URLQueryItem(name: "destination_id", value: "\(systemId)")
                ]
            )
            autopilotMessage = clear ? "Destination set in EVE client." : "Waypoint added in EVE client."
        } catch ESIError.unauthorized {
            autopilotMessage = "Requires esi-ui.write_waypoint.v1 scope — re-add your character with updated permissions."
        } catch {
            autopilotMessage = error.localizedDescription
        }
    }

    /// Sends the entire route to the EVE client autopilot, clearing existing waypoints.
    private func setFullAutopilotRoute() async {
        guard !route.isEmpty, let account = accountManager.selectedAccount else { return }
        isSettingAutopilot = true
        autopilotMessage = nil
        do {
            let token = try await accountManager.validToken(for: account)
            try await ESIClient.shared.postAction(
                "/ui/autopilot/waypoint/",
                token: token,
                queryItems: [
                    URLQueryItem(name: "add_to_beginning", value: "false"),
                    URLQueryItem(name: "clear_other_waypoints", value: "true"),
                    URLQueryItem(name: "destination_id", value: "\(route.last!.id)")
                ]
            )
            if route.count > 2 {
                for system in route.dropFirst().dropLast().reversed() {
                    try await ESIClient.shared.postAction(
                        "/ui/autopilot/waypoint/",
                        token: token,
                        queryItems: [
                            URLQueryItem(name: "add_to_beginning", value: "true"),
                            URLQueryItem(name: "clear_other_waypoints", value: "false"),
                            URLQueryItem(name: "destination_id", value: "\(system.id)")
                        ]
                    )
                }
            }
            autopilotMessage = "Route set in EVE client (\(route.count - 1) jump\(route.count == 2 ? "" : "s"))."
        } catch ESIError.unauthorized {
            autopilotMessage = "Requires esi-ui.write_waypoint.v1 scope — re-add your character with updated permissions."
        } catch {
            autopilotMessage = error.localizedDescription
        }
        isSettingAutopilot = false
    }

    // MARK:  Thera / EVE Scout

    private var theraConnectionsPanel: some View {
        let routeIds = Set(route.map(\.id))
        return GroupBox {
            if theraExpanded {
                VStack(alignment: .leading, spacing: 6) {
                    if isLoadingThera {
                        HStack(spacing: 8) {
                            ProgressView().controlSize(.small)
                            Text("Loading connections…")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    } else if let err = theraError {
                        HStack(spacing: 6) {
                            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                            Text(err).font(.caption).foregroundStyle(.secondary)
                        }
                    } else if theraConnections.isEmpty {
                        Text("No active Thera or Pochven connections found.")
                            .font(.caption).foregroundStyle(.secondary)
                    } else {
                        let sorted = theraConnections.sorted { a, b in
                            let aOnRoute = routeIds.contains(a.destinationSystemId)
                            let bOnRoute = routeIds.contains(b.destinationSystemId)
                            if aOnRoute != bOnRoute { return aOnRoute }
                            return a.destinationSecurity < b.destinationSecurity
                        }
                        LazyVStack(spacing: 2) {
                            ForEach(sorted) { conn in
                                TheraConnectionRow(
                                    connection: conn,
                                    isOnRoute: routeIds.contains(conn.destinationSystemId),
                                    isSelected: selectedTheraId == conn.id,
                                    onTap: {
                                        withAnimation(.easeInOut(duration: 0.15)) {
                                            selectedTheraId = selectedTheraId == conn.id ? nil : conn.id
                                        }
                                    },
                                    onSetAsOrigin: {
                                        originSystem = theraSelectedSystem(conn)
                                        selectedTheraId = nil
                                    },
                                    onSetAsDestination: {
                                        destinationSystem = theraSelectedSystem(conn)
                                        selectedTheraId = nil
                                    }
                                )
                            }
                        }
                    }
                }
            }
        } label: {
            HStack {
                Label("Thera & Pochven Connections", systemImage: "waveform.path.ecg.rectangle")
                Button {
                    showTheraInfo.toggle()
                } label: {
                    Image(systemName: "info.circle")
                        .font(.caption).foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .popover(isPresented: $showTheraInfo, arrowEdge: .top) {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Thera & Pochven Connections")
                            .font(.headline)
                        Text("Thera is a wormhole system with dozens of daily connections to K-space. Pochven is Triglavian-controlled space with its own wormhole network. Both offer shortcuts across the galaxy — but wormholes are unstable and expire.")
                            .font(.callout)
                            .fixedSize(horizontal: false, vertical: true)
                        Divider()
                        VStack(alignment: .leading, spacing: 6) {
                            infoRow(icon: "circle.fill", color: eveSecurityColor(0.9), text: "Highsec destination")
                            infoRow(icon: "circle.fill", color: eveSecurityColor(0.3), text: "Lowsec destination")
                            infoRow(icon: "circle.fill", color: eveSecurityColor(-0.1), text: "Nullsec destination")
                            infoRow(icon: "circle.fill", color: .purple, text: "Pochven destination")
                            infoRow(icon: "checkmark.seal.fill", color: .green, text: "ON ROUTE — K-space end is on your plotted route")
                            infoRow(icon: "exclamationmark.circle.fill", color: .red, text: "Near end of life (< 2 hours remaining)")
                        }
                        .font(.caption)
                        Divider()
                        HStack(spacing: 4) {
                            Image(systemName: "antenna.radiowaves.left.and.right")
                                .foregroundStyle(.secondary)
                            Text("Connection data provided by [EVE Scout](https://www.eve-scout.com)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(16)
                    .frame(width: 320)
                }
                Spacer()
                if !theraConnections.isEmpty {
                    Text("\(theraConnections.count) active")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Button {
                    Task { await loadTheraConnections(forceRefresh: true) }
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.caption2).foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("Refresh connections")
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) { theraExpanded.toggle() }
                } label: {
                    Image(systemName: theraExpanded ? "chevron.down" : "chevron.right")
                        .font(.caption2).foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help(theraExpanded ? "Collapse" : "Expand")
            }
        }
    }

    private func loadTheraConnections(forceRefresh: Bool = false) async {
        guard !isLoadingThera else { return }
        isLoadingThera = true
        theraError = nil
        do {
            theraConnections = try await EVEScoutClient.shared.fetchConnections(forceRefresh: forceRefresh)
        } catch {
            theraError = "Could not load: \(error.localizedDescription)"
        }
        isLoadingThera = false
    }

    private func infoRow(icon: String, color: Color, text: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .foregroundStyle(color)
                .frame(width: 14)
            Text(text).foregroundStyle(.primary)
        }
    }

    private func theraSelectedSystem(_ conn: EVEScoutConnection) -> SelectedSystem {
        let sec: Double
        switch conn.destinationSecurity.lowercased() {
        case "highsec": sec = 0.9
        case "lowsec":  sec = 0.3
        default:        sec = -0.1
        }
        return SelectedSystem(id: conn.destinationSystemId, name: conn.destinationSystemName, securityStatus: sec)
    }

    // MARK:  Route Calculation

    private func plotRoute() async {
        guard let origin = originSystem, let destination = destinationSystem else { return }

        isCalculating = true
        errorMessage = nil
        route = []
        autoAvoidedCount = 0

        // Pull the hourly kill/jump map first — used to annotate every hop and,
        // optionally, to steer the route away from hot systems. Best-effort: a
        // failure here just means the route has no danger overlay.
        let danger = try? await SystemDangerService.shared.snapshot()
        dangerSnapshotAt = danger?.fetchedAt

        var avoidIds = Set(avoidSystems.map(\.id))
        if avoidDanger, let danger {
            let hot = danger.hostileSystems(threshold: dangerThreshold)
                .subtracting([origin.id, destination.id])
            autoAvoidedCount = hot.subtracting(avoidIds).count
            avoidIds.formUnion(hot)
        }

        do {
            let systemIds: [Int]
            if avoidIds.isEmpty {
                // Fast path — ESI's own routing endpoint, unchanged from before.
                systemIds = try await ESIClient.shared.fetch(
                    "/route/\(origin.id)/\(destination.id)/",
                    queryItems: [URLQueryItem(name: "flag", value: routeFlag)]
                )
            } else {
                // ESI has no avoidance parameter — fall back to a local pathfinder.
                let flag = RoutePathfinder.RouteFlag(rawValue: routeFlag) ?? .shortest
                systemIds = try await RoutePathfinder.findRoute(
                    from: origin.id,
                    to: destination.id,
                    avoiding: avoidIds,
                    flag: flag
                )
            }

            // Resolve all system details concurrently
            let resolvedSystems = await withTaskGroup(of: (Int, RouteSystem).self) { group -> [RouteSystem] in
                for (index, systemId) in systemIds.enumerated() {
                    group.addTask {
                        let solarSystem = await UniverseCache.shared.solarSystem(id: systemId)
                        return (index, RouteSystem(
                            id: systemId,
                            name: solarSystem?.name ?? "System #\(systemId)",
                            securityStatus: solarSystem?.securityStatus ?? 0.0,
                            danger: danger?.danger(for: systemId) ?? .none
                        ))
                    }
                }
                var indexed: [(Int, RouteSystem)] = []
                for await result in group { indexed.append(result) }
                indexed.sort { $0.0 < $1.0 }
                return indexed.map(\.1)
            }
            route = resolvedSystems
        } catch let error as RoutePathfinder.NoRouteError {
            errorMessage = error.localizedDescription
        } catch {
            errorMessage = "No route found between these systems with the selected route type."
        }
        isCalculating = false
    }
}

// MARK:  Route System Model

