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
    @State private var route: [RouteSystem] = []
    @State private var isCalculating = false
    @State private var errorMessage: String?
    @State private var autopilotMessage: String?
    @State private var isSettingAutopilot = false

    private var canPlot: Bool {
        originSystem != nil && destinationSystem != nil && !isCalculating
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                inputPanel
                if isCalculating { calculatingView }
                if !route.isEmpty { routePanel }
            }
            .padding()
        }
        .navigationTitle("Route Planner")
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
                        Text("\(route.count - 1) jump\(route.count == 2 ? "" : "s")")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
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

    // MARK:  Route Calculation

    private func plotRoute() async {
        guard let origin = originSystem, let destination = destinationSystem else { return }

        isCalculating = true
        errorMessage = nil
        route = []

        do {
            // Fetch route directly using known system IDs — no name resolution needed
            let systemIds: [Int] = try await ESIClient.shared.fetch(
                "/route/\(origin.id)/\(destination.id)/",
                queryItems: [URLQueryItem(name: "flag", value: routeFlag)]
            )

            // Resolve all system details concurrently
            let resolvedSystems = await withTaskGroup(of: (Int, RouteSystem).self) { group -> [RouteSystem] in
                for (index, systemId) in systemIds.enumerated() {
                    group.addTask {
                        let solarSystem = await UniverseCache.shared.solarSystem(id: systemId)
                        return (index, RouteSystem(
                            id: systemId,
                            name: solarSystem?.name ?? "System #\(systemId)",
                            securityStatus: solarSystem?.securityStatus ?? 0.0
                        ))
                    }
                }
                var indexed: [(Int, RouteSystem)] = []
                for await result in group { indexed.append(result) }
                indexed.sort { $0.0 < $1.0 }
                return indexed.map(\.1)
            }
            route = resolvedSystems
        } catch {
            errorMessage = "No route found between these systems with the selected route type."
        }
        isCalculating = false
    }
}

// MARK:  Route System Model

struct RouteSystem {
    let id: Int
    let name: String
    let securityStatus: Double

    var displaySecurity: String {
        String(format: "%.1f", max(0.0, securityStatus))
    }

    var securityColor: Color { eveSecurityColor(securityStatus) }
}

// MARK:  System Search Field

struct SystemSearchField: View {
    let label: String
    let icon: String
    let iconColor: Color
    let placeholder: String
    @Binding var selectedSystem: SelectedSystem?

    @Environment(AccountManager.self) private var accountManager

    @State private var searchText = ""
    @State private var results: [SystemSearchResult] = []
    @State private var isSearching = false
    @State private var searchError: String?
    @State private var showPopover = false
    @State private var highlightedIndex: Int? = nil
    @State private var searchTask: Task<Void, Never>?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Label(label, systemImage: icon)
                .font(.caption.weight(.medium))
                .foregroundStyle(iconColor)

            TextField(placeholder, text: $searchText)
                .textFieldStyle(.roundedBorder)
                .onChange(of: searchText) { _, newValue in
                    handleInput(newValue)
                }
                .onChange(of: selectedSystem) { _, newValue in
                    // Sync text when parent changes the selection (e.g., swap button)
                    if let system = newValue, searchText != system.name {
                        searchText = system.name
                    } else if newValue == nil && selectedSystem != nil {
                        searchText = ""
                    }
                }
                .onKeyPress(.downArrow) {
                    guard !results.isEmpty else { return .ignored }
                    highlightedIndex = min((highlightedIndex ?? -1) + 1, results.count - 1)
                    return .handled
                }
                .onKeyPress(.upArrow) {
                    guard !results.isEmpty else { return .ignored }
                    highlightedIndex = max((highlightedIndex ?? results.count) - 1, 0)
                    return .handled
                }
                .onKeyPress(.return) {
                    guard let idx = highlightedIndex, results.indices.contains(idx) else { return .ignored }
                    select(results[idx])
                    return .handled
                }
                .onKeyPress(.escape) {
                    showPopover = false
                    highlightedIndex = nil
                    return .handled
                }
                .onSubmit {
                    if let idx = highlightedIndex, results.indices.contains(idx) {
                        select(results[idx])
                    } else if let first = results.first {
                        select(first)
                    }
                }
                .popover(isPresented: $showPopover, arrowEdge: .bottom) {
                    searchResultsPopover
                }
        }
    }

    private var searchResultsPopover: some View {
        VStack(spacing: 0) {
            if isSearching {
                HStack(spacing: 8) {
                    ProgressView().scaleEffect(0.7)
                    Text("Searching…").font(.caption).foregroundStyle(.secondary)
                }
                .padding(12)
                .frame(minWidth: 260)
            } else if let err = searchError {
                HStack(alignment: .top, spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                    Text(err).font(.caption)
                }
                .padding(12)
                .frame(minWidth: 260)
            } else if results.isEmpty {
                Text("No systems found")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(12)
                    .frame(minWidth: 260)
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 0) {
                            ForEach(Array(results.enumerated()), id: \.element.id) { index, result in
                                Button { select(result) } label: {
                                    SystemResultRow(
                                        result: result,
                                        accentColor: iconColor,
                                        isHighlighted: highlightedIndex == index
                                    )
                                }
                                .buttonStyle(.plain)
                                .id(result.id)
                                if index < results.count - 1 {
                                    Divider().padding(.leading, 44)
                                }
                            }
                        }
                    }
                    .onChange(of: highlightedIndex) { _, newIndex in
                        if let idx = newIndex, results.indices.contains(idx) {
                            withAnimation(.easeInOut(duration: 0.15)) {
                                proxy.scrollTo(results[idx].id, anchor: .center)
                            }
                        }
                    }
                }
                .frame(minWidth: 260, maxHeight: 300)
                .onChange(of: results) { _, _ in highlightedIndex = nil }
            }
        }
    }

    private func handleInput(_ query: String) {
        let trimmed = query.trimmingCharacters(in: .whitespaces)

        // If the current text matches the confirmed selection, nothing to do
        if trimmed == selectedSystem?.name { return }

        // Text diverged from selection — clear it
        if selectedSystem != nil { selectedSystem = nil }

        searchTask?.cancel()
        guard trimmed.count >= 3 else {
            results = []
            showPopover = false
            return
        }

        searchTask = Task {
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled else { return }

            guard let account = accountManager.selectedAccount else {
                searchError = "Sign in to search for systems"
                showPopover = true
                return
            }

            isSearching = true
            searchError = nil
            showPopover = true
            do {
                let token = try await accountManager.validToken(for: account)
                let response: ESISearchResponse = try await ESIClient.shared.fetch(
                    "/characters/\(account.characterID)/search/",
                    token: token,
                    queryItems: [
                        URLQueryItem(name: "categories", value: "solar_system"),
                        URLQueryItem(name: "search", value: trimmed),
                        URLQueryItem(name: "strict", value: "false")
                    ]
                )
                guard !Task.isCancelled else { isSearching = false; return }
                let ids = Array((response.solarSystem ?? []).prefix(15))
                print("[SystemSearch] '\(trimmed)' → \(ids.count) IDs: \(ids)")

                // Resolve names concurrently via UniverseCache (persists between searches)
                let resolved = await withTaskGroup(of: SystemSearchResult?.self) { group -> [SystemSearchResult] in
                    for id in ids {
                        group.addTask {
                            guard let system = await UniverseCache.shared.solarSystem(id: id) else { return nil }
                            return SystemSearchResult(id: id, name: system.name, securityStatus: system.securityStatus)
                        }
                    }
                    var out: [SystemSearchResult] = []
                    for await result in group { if let r = result { out.append(r) } }
                    return out
                }
                guard !Task.isCancelled else { isSearching = false; return }
                results = resolved.sorted { $0.name < $1.name }
                print("[SystemSearch] resolved \(results.count) systems")
            } catch {
                if !Task.isCancelled {
                    searchError = error.localizedDescription
                    print("[SystemSearch] ERROR: \(error)")
                }
            }
            isSearching = false
        }
    }

    private func select(_ result: SystemSearchResult) {
        searchTask?.cancel()
        selectedSystem = SelectedSystem(id: result.id, name: result.name, securityStatus: result.securityStatus)
        searchText = result.name
        results = []
        showPopover = false
    }
}

// MARK:  System Search Result

struct SystemSearchResult: Identifiable, Equatable {
    let id: Int
    let name: String
    let securityStatus: Double

    var displaySecurity: String { String(format: "%.1f", max(0.0, securityStatus)) }
    var securityColor: Color { eveSecurityColor(securityStatus) }
}

struct SystemResultRow: View {
    let result: SystemSearchResult
    let accentColor: Color
    var isHighlighted: Bool = false

    var body: some View {
        HStack(spacing: 10) {
            Text(result.displaySecurity)
                .font(.caption.bold().monospacedDigit())
                .foregroundStyle(result.securityColor)
                .frame(width: 28, alignment: .center)
                .padding(.vertical, 2)
                .background(result.securityColor.opacity(0.15), in: RoundedRectangle(cornerRadius: 5))

            Text(result.name)
                .font(.subheadline)
                .foregroundStyle(isHighlighted ? accentColor : .primary)
                .fontWeight(isHighlighted ? .semibold : .regular)

            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(isHighlighted ? accentColor.opacity(0.12) : Color.clear)
        .frame(maxWidth: .infinity)
        .contentShape(Rectangle())
        .background(Color.clear)
    }
}

// MARK:  Route System Row

struct RouteSystemRow: View {
    let system: RouteSystem
    let jumpNumber: Int
    let isLast: Bool
    let isFirst: Bool
    var showWaypointButton: Bool = false
    var onSetDestination: (() async -> Void)? = nil
    var onAddWaypoint: (() async -> Void)? = nil

    @State private var showWaypointMenu = false

    var body: some View {
        HStack(spacing: 0) {
            // Vertical connector track
            VStack(spacing: 0) {
                Rectangle()
                    .fill(isFirst ? Color.clear : Color.secondary.opacity(0.25))
                    .frame(width: 2)
                    .frame(maxHeight: .infinity)
                Circle()
                    .fill(isFirst ? Color.blue : isLast ? Color.green : system.securityColor)
                    .frame(width: 8, height: 8)
                Rectangle()
                    .fill(isLast ? Color.clear : Color.secondary.opacity(0.25))
                    .frame(width: 2)
                    .frame(maxHeight: .infinity)
            }
            .frame(width: 20)
            .padding(.leading, 8)

            HStack(spacing: 10) {
                // Jump number
                Text("\(jumpNumber)")
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.tertiary)
                    .frame(width: 24, alignment: .trailing)

                // Security badge
                Text(system.displaySecurity)
                    .font(.caption.bold().monospacedDigit())
                    .foregroundStyle(system.securityColor)
                    .frame(width: 30, alignment: .center)
                    .padding(.vertical, 2)
                    .background(system.securityColor.opacity(0.15), in: RoundedRectangle(cornerRadius: 5))

                // System name
                Text(system.name)
                    .font(.subheadline)
                    .fontWeight(isFirst || isLast ? .semibold : .regular)

                Spacer()

                if isFirst {
                    Text("ORIGIN").font(.caption2.bold()).foregroundStyle(.blue)
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(.blue.opacity(0.15), in: Capsule())
                } else if isLast {
                    Text("DEST").font(.caption2.bold()).foregroundStyle(.green)
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(.green.opacity(0.15), in: Capsule())
                }

                if showWaypointButton {
                    Menu {
                        Button("Set Destination") { Task { await onSetDestination?() } }
                        Button("Add Waypoint") { Task { await onAddWaypoint?() } }
                    } label: {
                        Image(systemName: "paperplane")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .padding(5)
                            .background(.quaternary.opacity(0.6), in: RoundedRectangle(cornerRadius: 5))
                    }
                    .menuStyle(.button)
                    .buttonStyle(.plain)
                    .help("Send to autopilot")
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
        }
        .frame(minHeight: 36)
        .background(isFirst ? Color.blue.opacity(0.05) : isLast ? Color.green.opacity(0.05) : Color.clear)
    }
}

// MARK:  Helpers

private func eveSecurityColor(_ status: Double) -> Color {
    switch status {
    case 0.9...: return Color(red: 0.3, green: 0.9, blue: 1.0)
    case 0.8..<0.9: return Color(red: 0.0, green: 0.9, blue: 0.8)
    case 0.7..<0.8: return Color(red: 0.0, green: 0.9, blue: 0.4)
    case 0.6..<0.7: return Color(red: 0.4, green: 0.9, blue: 0.0)
    case 0.5..<0.6: return Color(red: 0.9, green: 0.9, blue: 0.0)
    case 0.4..<0.5: return Color(red: 1.0, green: 0.6, blue: 0.0)
    case 0.3..<0.4: return Color(red: 1.0, green: 0.4, blue: 0.0)
    case 0.2..<0.3: return Color(red: 1.0, green: 0.2, blue: 0.0)
    case 0.1..<0.2: return Color(red: 0.9, green: 0.0, blue: 0.0)
    default: return Color(red: 0.6, green: 0.0, blue: 0.0)
    }
}
