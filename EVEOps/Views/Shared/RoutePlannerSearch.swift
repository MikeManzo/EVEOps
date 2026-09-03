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

struct RouteSystem {
    let id: Int
    let name: String
    let securityStatus: Double
    var danger: SystemDanger = .none

    var displaySecurity: String {
        String(format: "%.1f", max(0.0, securityStatus))
    }

    var securityColor: Color { eveSecurityColor(securityStatus) }
    var dangerLevel: DangerLevel { DangerLevel(combatKills: danger.combatKills) }
}

// MARK:  System Search Field

struct SystemSearchField: View {
    let label: LocalizedStringKey
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
                Logger.systemSearch.info("[SystemSearch] '\(trimmed)' → \(ids.count) IDs: \(ids)")

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
                Logger.systemSearch.info("[SystemSearch] resolved \(results.count) systems")
            } catch {
                if !Task.isCancelled {
                    searchError = error.localizedDescription
                    Logger.systemSearch.error("[SystemSearch] ERROR: \(error)")
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

