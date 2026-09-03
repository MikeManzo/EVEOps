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
import AppKit

/// ⌘K quick switcher. Fuzzy-jumps between the ~50 navigation sections (which are
/// otherwise buried in seven collapsible sidebar groups), runs a few app actions,
/// and resolves EVE system / item / character names via ESI for a fast look-up.
struct CommandPaletteView: View {
    @Binding var selectedSection: NavigationSection?
    let onRun: (PaletteAction) -> Void
    let dismiss: () -> Void

    @Environment(AccountManager.self) private var accountManager

    @State private var query = ""
    @State private var highlighted = 0
    @State private var entityHits: [EntityHit] = []
    @State private var lookupInFlight = false
    @State private var lookupTask: Task<Void, Never>?
    @AppStorage("commandPalette.recentSections") private var recentsRaw = ""
    @FocusState private var fieldFocused: Bool

    private var recents: [NavigationSection] {
        recentsRaw.split(separator: ",").compactMap { NavigationSection(rawValue: String($0)) }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
                TextField("Jump to a section, action, or EVE name…", text: $query)
                    .textFieldStyle(.plain)
                    .font(.title3)
                    .focused($fieldFocused)
                    .onSubmit { runHighlighted() }
                    .onKeyPress(.downArrow) { move(1); return .handled }
                    .onKeyPress(.upArrow) { move(-1); return .handled }
                    .onKeyPress(.escape) { dismiss(); return .handled }
                    .accessibilityLabel("Search sections, actions, and EVE names")
                if lookupInFlight {
                    ProgressView().controlSize(.small)
                        .accessibilityLabel("Looking up names")
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)

            Divider()

            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 1) {
                        ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                            PaletteRowView(row: row, isHighlighted: index == highlighted)
                                .id(index)
                                .contentShape(Rectangle())
                                .onTapGesture { run(row) }
                                .onHover { if $0 { highlighted = index } }
                                .accessibilityElement(children: .combine)
                                .accessibilityAddTraits(.isButton)
                                .accessibilityAddTraits(index == highlighted ? .isSelected : [])
                        }
                    }
                    .padding(6)
                }
                .frame(maxHeight: 360)
                .onChange(of: highlighted) { _, new in
                    withAnimation(.easeOut(duration: 0.12)) { proxy.scrollTo(new, anchor: .center) }
                }
            }

            if rows.isEmpty {
                Text("No matches")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 24)
            }

            Divider()
            HStack(spacing: 14) {
                hint("up / down", "navigate")
                hint("return", "open")
                hint("esc", "close")
                Spacer()
            }
            .font(.caption2)
            .foregroundStyle(.tertiary)
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .accessibilityHidden(true)
        }
        .frame(width: 620)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .onAppear { fieldFocused = true }
        .onChange(of: query) { _, _ in
            highlighted = 0
            scheduleLookup()
        }
    }

    // MARK: Rows

    private var rows: [PaletteRow] {
        let trimmed = query.trimmingCharacters(in: .whitespaces)

        var result: [PaletteRow] = []

        if trimmed.isEmpty {
            result += recents.map { .section($0, subtitle: "Recent") }
            result += PaletteAction.always.map { .action($0) }
            return result
        }

        let sectionMatches = availableSections
            .compactMap { section -> (PaletteRow, Int)? in
                guard let score = Self.fuzzyScore(trimmed, section.rawValue) else { return nil }
                return (.section(section, subtitle: "Section"), score)
            }
            .sorted { $0.1 > $1.1 }
            .map(\.0)

        let actionMatches = PaletteAction.allCases.compactMap { action -> PaletteRow? in
            Self.fuzzyScore(trimmed, action.title) == nil ? nil : .action(action)
        }

        result += sectionMatches
        result += actionMatches
        result += entityHits.map { .entity($0) }
        return result
    }

    private var availableSections: [NavigationSection] {
        if accountManager.accounts.isEmpty {
            return [.dashboard, .diagnosticLogs]
        }
        return NavigationSection.allCases
    }

    // MARK: Actions

    private func move(_ delta: Int) {
        guard !rows.isEmpty else { return }
        highlighted = (highlighted + delta + rows.count) % rows.count
    }

    private func runHighlighted() {
        guard rows.indices.contains(highlighted) else { return }
        run(rows[highlighted])
    }

    private func run(_ row: PaletteRow) {
        switch row {
        case .section(let section, _):
            noteRecent(section)
            selectedSection = section
            dismiss()
        case .action(let action):
            onRun(action)
            dismiss()
        case .entity(let hit):
            hit.perform()
            dismiss()
        }
    }

    private func noteRecent(_ section: NavigationSection) {
        var list = [section.rawValue] + recents.map(\.rawValue).filter { $0 != section.rawValue }
        list = Array(list.prefix(6))
        recentsRaw = list.joined(separator: ",")
    }

    private func hint(_ key: String, _ label: String) -> some View {
        HStack(spacing: 4) {
            Text(key).monospaced()
            Text(label)
        }
    }

    // MARK: EVE name lookup

    private func scheduleLookup() {
        lookupTask?.cancel()
        let term = query.trimmingCharacters(in: .whitespaces)
        guard term.count >= 3 else {
            entityHits = []
            lookupInFlight = false
            return
        }
        lookupTask = Task {
            try? await Task.sleep(for: .milliseconds(280))
            guard !Task.isCancelled else { return }
            lookupInFlight = true
            defer { lookupInFlight = false }
            let hits = await EntityHit.resolve(term)
            guard !Task.isCancelled else { return }
            entityHits = hits
        }
    }

    // MARK: Fuzzy match

    /// Subsequence match with a bonus for contiguous runs and leading hits.
    /// Returns `nil` when `query` is not a subsequence of `target`.
    static func fuzzyScore(_ query: String, _ target: String) -> Int? {
        let q = Array(query.lowercased())
        guard !q.isEmpty else { return 0 }
        let t = Array(target.lowercased())
        var qi = 0, score = 0, streak = 0
        for (ti, ch) in t.enumerated() where qi < q.count {
            if q[qi] == ch {
                qi += 1
                streak += 1
                score += streak * 3 + (ti == 0 ? 12 : 0)
            } else {
                streak = 0
            }
        }
        return qi == q.count ? score : nil
    }
}

// MARK: - Rows

enum PaletteRow: Identifiable {
    case section(NavigationSection, subtitle: String)
    case action(PaletteAction)
    case entity(EntityHit)

    var id: String {
        switch self {
        case .section(let s, _): return "section.\(s.rawValue)"
        case .action(let a): return "action.\(a.rawValue)"
        case .entity(let e): return "entity.\(e.kind.rawValue).\(e.id)"
        }
    }
}

private struct PaletteRowView: View {
    let row: PaletteRow
    let isHighlighted: Bool

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .frame(width: 22)
                .foregroundStyle(isHighlighted ? Color.white : .secondary)
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .foregroundStyle(isHighlighted ? Color.white : .primary)
                if let subtitle {
                    Text(subtitle)
                        .font(.caption2)
                        .foregroundStyle(isHighlighted ? Color.white.opacity(0.8) : .secondary)
                }
            }
            Spacer()
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(isHighlighted ? Color.accentColor : Color.clear, in: RoundedRectangle(cornerRadius: 7))
    }

    private var icon: String {
        switch row {
        case .section(let s, _): return s.iconName
        case .action(let a): return a.icon
        case .entity(let e): return e.kind.icon
        }
    }
    private var title: String {
        switch row {
        case .section(let s, _): return s.rawValue
        case .action(let a): return a.title
        case .entity(let e): return e.name
        }
    }
    private var subtitle: String? {
        switch row {
        case .section(_, let sub): return sub
        case .action: return "Action"
        case .entity(let e): return e.kind.subtitle
        }
    }
}

// MARK: - Quick actions

enum PaletteAction: String, CaseIterable {
    case openSettings, addCharacter, refresh, diagnostics

    static var always: [PaletteAction] { [.openSettings, .addCharacter, .refresh] }

    var title: String {
        switch self {
        case .openSettings: return "Open Settings"
        case .addCharacter: return "Add Character…"
        case .refresh: return "Refresh Current View"
        case .diagnostics: return "Open Diagnostic Logs"
        }
    }
    var icon: String {
        switch self {
        case .openSettings: return "gearshape"
        case .addCharacter: return "person.badge.plus"
        case .refresh: return "arrow.clockwise"
        case .diagnostics: return "stethoscope"
        }
    }
}

// MARK: - Resolved EVE entities

struct EntityHit: Hashable {
    enum Kind: String {
        case system, type, character

        var icon: String {
            switch self {
            case .system: return "globe.europe.africa.fill"
            case .type: return "shippingbox.fill"
            case .character: return "person.fill"
            }
        }
        var subtitle: String {
            switch self {
            case .system: return "Solar system — open on Dotlan"
            case .type: return "Item — search the market"
            case .character: return "Character — open on zKillboard"
            }
        }
    }

    let kind: Kind
    let id: Int
    let name: String

    @MainActor
    func perform() {
        switch kind {
        case .type:
            WindowService.shared.showGalaxySearch(typeId: id, typeName: name)
        case .system:
            let slug = name.replacingOccurrences(of: " ", with: "_")
            open("https://evemaps.dotlan.net/system/\(slug)")
        case .character:
            open("https://zkillboard.com/character/\(id)/")
        }
    }

    private func open(_ string: String) {
        guard let url = URL(string: string.addingPercentEncoding(withAllowedCharacters: .urlFragmentAllowed) ?? string) else { return }
        NSWorkspace.shared.open(url)
    }

    /// Resolve a free-text term to systems / items / characters via `/universe/ids/`.
    static func resolve(_ term: String) async -> [EntityHit] {
        struct Response: Decodable {
            struct Entry: Decodable { let id: Int; let name: String }
            var characters: [Entry]?
            var systems: [Entry]?
            var inventoryTypes: [Entry]?
        }
        do {
            let response: Response = try await ESIClient.shared.post("/universe/ids/", body: [term])
            var hits: [EntityHit] = []
            hits += (response.systems ?? []).prefix(4).map { EntityHit(kind: .system, id: $0.id, name: $0.name) }
            hits += (response.inventoryTypes ?? []).prefix(5).map { EntityHit(kind: .type, id: $0.id, name: $0.name) }
            hits += (response.characters ?? []).prefix(3).map { EntityHit(kind: .character, id: $0.id, name: $0.name) }
            return hits
        } catch {
            return []
        }
    }
}
