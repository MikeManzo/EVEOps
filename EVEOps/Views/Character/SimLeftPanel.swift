//
// SimLeftPanel.swift
// EVEOps
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

// MARK:  Left Panel

private enum LeftPanelMode { case ships, modules }

// Dogma effect IDs that identify which slot a module occupies
private enum SlotEffect {
    static let high: Int       = 12
    static let low: Int        = 11
    static let medium: Int     = 13
    static let rig: Int        = 2663
    static let subsystem: Int  = 3772

    static func category(from effects: [ESIDogmaEffect]) -> SimSlotCategory? {
        let ids = Set(effects.map(\.effectId))
        if ids.contains(high)      { return .high }
        if ids.contains(medium)    { return .medium }
        if ids.contains(low)       { return .low }
        if ids.contains(rig)       { return .rig }
        if ids.contains(subsystem) { return .subsystem }
        return nil
    }
}

struct SimLeftPanel: View {
    @Environment(SimulatorState.self) private var simState
    @Environment(AccountManager.self) private var accountManager

    // Ship browser
    @State private var allShipSections: [(className: String, ships: [ESIType])] = []
    @State private var isLoadingShips = false
    @State private var shipLoadIncomplete = false
    @State private var shipSearchText = ""
    @AppStorage("simulateCollapsedShipSections") private var collapsedSectionsRaw: String = ""

    // Module browser
    @State private var allModuleSections: [(category: SimSlotCategory, modules: [ESIType])] = []
    @State private var isLoadingModules = false
    @State private var moduleFilterText = ""
    @AppStorage("simulateCollapsedModuleSections") private var collapsedModuleSectionsRaw: String = ""
    @State private var noSlotMessage: String?

    @State private var leftMode: LeftPanelMode = .ships
    @State private var showLoadSheet = false

    private var filteredShipSections: [(className: String, ships: [ESIType])] {
        let q = shipSearchText.lowercased().trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return allShipSections }
        return allShipSections.compactMap { section in
            let filtered = section.ships.filter { $0.name.lowercased().contains(q) }
            return filtered.isEmpty ? nil : (className: section.className, ships: filtered)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            if leftMode == .modules {
                allModulesBrowser
            } else {
                shipBrowser
            }
        }
        .sheet(isPresented: $showLoadSheet) {
            SimLoadFittingSheet()
                .environment(simState)
                .environment(accountManager)
        }
        .task {
            await loadAllShips()
            if simState.shipTypeId != nil {
                leftMode = .modules
                await loadAllModules()
            }
        }
        .onChange(of: simState.shipTypeId) { _, newId in
            withAnimation(.easeInOut(duration: 0.15)) {
                leftMode = newId != nil ? .modules : .ships
            }
            if newId != nil { Task { await loadAllModules() } }
        }
        .onChange(of: simState.activeSlotId) { _, newId in
            if newId != nil && simState.shipTypeId != nil {
                withAnimation(.easeInOut(duration: 0.15)) { leftMode = .modules }
            }
        }
    }

    // MARK: Ship Browser

    private var shipBrowser: some View {
        VStack(spacing: 0) {
            searchBar(text: $shipSearchText, placeholder: "Filter ships…") { _ in }

            Button { showLoadSheet = true } label: {
                Label("Load Saved Fitting or Ship", systemImage: "square.and.arrow.down")
                    .font(.caption).frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderless)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 10)
            .padding(.bottom, 8)

            Divider()

            if isLoadingShips {
                VStack(spacing: 8) {
                    ProgressView()
                    Text("Loading ship database…").font(.caption).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if filteredShipSections.isEmpty {
                emptyState(shipSearchText.isEmpty ? "No ships" : "No ships match \"\(shipSearchText)\"")
            } else {
                List {
                    ForEach(filteredShipSections, id: \.className) { section in
                        Section(isExpanded: Binding(
                            get: { !collapsedSectionsRaw.components(separatedBy: "\n").contains(section.className) },
                            set: { expanded in
                                var set = Set(collapsedSectionsRaw.components(separatedBy: "\n").filter { !$0.isEmpty })
                                if expanded { set.remove(section.className) } else { set.insert(section.className) }
                                collapsedSectionsRaw = set.joined(separator: "\n")
                            }
                        )) {
                            ForEach(section.ships, id: \.typeId) { type in
                                SimShipRow(type: type, className: section.className)
                                    .contentShape(Rectangle())
                                    .onTapGesture {
                                        Task { await simState.selectShip(typeId: type.typeId) }
                                    }
                            }
                        } header: {
                            HStack(spacing: 6) {
                                Image(systemName: CharacterFittingsView.shipClassIcon(section.className))
                                    .font(.caption2).foregroundStyle(.secondary)
                                Text(section.className).font(.subheadline.bold())
                                Spacer()
                                Text("\(section.ships.count)")
                                    .font(.caption.monospacedDigit()).foregroundStyle(.tertiary)
                            }
                        }
                    }
                }
                .listStyle(.sidebar)
            }

            if shipLoadIncomplete {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                    Text("Some ships failed to load")
                        .font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Button("Retry") { Task { await retryLoadShips() } }
                        .font(.caption).buttonStyle(.borderless)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(.background.secondary)
            }
        }
    }

    // MARK: All-Modules Browser

    private var allModulesBrowser: some View {
        VStack(spacing: 0) {
            // Header
            HStack(spacing: 8) {
                Button {
                    simState.activeSlotId = nil
                    withAnimation(.easeInOut(duration: 0.15)) { leftMode = .ships }
                } label: {
                    Label("Ships", systemImage: "chevron.left").font(.caption.bold())
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)

                Spacer()

                if !simState.shipName.isEmpty {
                    VStack(alignment: .trailing, spacing: 1) {
                        Text(simState.shipName).font(.caption.bold()).lineLimit(1)
                        if !simState.shipClassName.isEmpty {
                            Text(simState.shipClassName).font(.caption2).foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .padding(.horizontal, 10).padding(.vertical, 8)

            // Slot targeting indicator
            if let active = simState.activeSlot {
                HStack(spacing: 6) {
                    Image(systemName: active.category.icon)
                        .font(.caption2).foregroundStyle(active.category.color)
                    Text("Targeting \(active.category.displayName) · slot \(active.index + 1)")
                        .font(.caption2).foregroundStyle(active.category.color)
                    Spacer()
                    Button {
                        simState.activeSlotId = nil
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.caption2).foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 10).padding(.vertical, 5)
                .background(active.category.color.opacity(0.08))
            }

            Divider()
            searchBar(text: $moduleFilterText, placeholder: "Filter modules…") { _ in }
            Divider()

            if isLoadingModules {
                VStack(spacing: 8) {
                    ProgressView()
                    Text("Loading module database…").font(.caption).foregroundStyle(.secondary)
                    Text("First launch only — cached for 7 days")
                        .font(.caption2).foregroundStyle(.tertiary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if allModuleSections.isEmpty {
                emptyState("No modules available")
            } else {
                ZStack(alignment: .bottom) {
                    List {
                        ForEach(allModuleSections, id: \.category) { section in
                            let filtered = filterModules(section.modules)
                            let totalSlots = simState.slots.filter { $0.category == section.category }.count
                            let usedSlots  = simState.slots.filter { $0.category == section.category && !$0.isEmpty }.count
                            if !filtered.isEmpty || moduleFilterText.isEmpty {
                                Section(isExpanded: Binding(
                                    get: { !collapsedModuleSectionsRaw.components(separatedBy: "\n").contains(section.category.displayName) },
                                    set: { expanded in
                                        var set = Set(collapsedModuleSectionsRaw.components(separatedBy: "\n").filter { !$0.isEmpty })
                                        if expanded { set.remove(section.category.displayName) } else { set.insert(section.category.displayName) }
                                        collapsedModuleSectionsRaw = set.joined(separator: "\n")
                                    }
                                )) {
                                    ForEach(filtered, id: \.typeId) { type in
                                        let drag = SimModuleDrag(typeId: type.typeId, category: section.category)
                                        SimModuleRow(type: type)
                                            .contentShape(Rectangle())
                                            .opacity(totalSlots == 0 || usedSlots >= totalSlots ? 0.4 : 1.0)
                                            .onDrag({
                                                simState.draggingCategory = drag.category
                                                simState.pendingDropPayload = drag
                                                return drag.makeItemProvider()
                                            }, preview: {
                                                SimModuleDragPreview(type: type, category: section.category)
                                            })
                                            .onTapGesture {
                                                Task { await selectModule(type: type, category: section.category) }
                                            }
                                    }
                                } header: {
                                    HStack(spacing: 6) {
                                        Image(systemName: section.category.icon)
                                            .font(.caption2).foregroundStyle(section.category.color)
                                        Text(section.category.displayName).font(.subheadline.bold())
                                        Spacer()
                                        if totalSlots > 0 {
                                            Text("\(usedSlots)/\(totalSlots)")
                                                .font(.caption.monospacedDigit())
                                                .foregroundStyle(usedSlots >= totalSlots
                                                    ? Color.secondary
                                                    : section.category.color.opacity(0.85))
                                        }
                                    }
                                }
                            }
                        }
                    }
                    .listStyle(.sidebar)

                    if let msg = noSlotMessage {
                        Text(msg)
                            .font(.caption.bold())
                            .padding(.horizontal, 12).padding(.vertical, 7)
                            .background(.ultraThinMaterial, in: Capsule())
                            .padding(.bottom, 10)
                            .transition(.move(edge: .bottom).combined(with: .opacity))
                    }
                }
                .animation(.easeInOut(duration: 0.2), value: noSlotMessage != nil)
            }
        }
        .task { await loadAllModules() }
    }

    // MARK: Module Selection

    private func selectModule(type: ESIType, category: SimSlotCategory) async {
        // If user tapped a specific slot of the right category, fill it directly
        if let active = simState.activeSlot, active.category == category {
            await simState.fillSlot(id: active.id, with: type.typeId)
            simState.activeSlotId = nil
            return
        }
        // Otherwise fill next available slot of this category
        let filled = await simState.fillNextAvailableSlot(category: category, typeId: type.typeId)
        if !filled {
            withAnimation { noSlotMessage = "No open \(category.displayName) on this ship" }
            Task {
                try? await Task.sleep(for: .seconds(2))
                withAnimation { noSlotMessage = nil }
            }
        }
    }

    // MARK: Data Loading

    private func loadAllShips() async {
        guard allShipSections.isEmpty else { return }
        isLoadingShips = true
        shipLoadIncomplete = false
        guard let shipCategory = await UniverseCache.shared.category(id: 6) else {
            isLoadingShips = false; return
        }
        let groups = await UniverseCache.shared.groups(ids: Set(shipCategory.groups))
        let publishedGroups = groups.values.filter(\.published)
        let publishedGroupIds = Set(publishedGroups.map(\.groupId))
        let allTypeIds = Array(Set(publishedGroups.flatMap(\.types)))
        let types = await UniverseCache.shared.types(ids: allTypeIds)
        let missingCount = allTypeIds.filter { types[$0] == nil }.count
        let shipTypes = types.values.filter { publishedGroupIds.contains($0.groupId) && $0.published }
        let byClass = Dictionary(grouping: Array(shipTypes)) { type -> String in
            groups[type.groupId]?.name ?? "Unknown"
        }
        allShipSections = byClass.keys.sorted().map { cls in
            (className: cls, ships: byClass[cls]!.sorted { $0.name < $1.name })
        }
        if missingCount > 0 { shipLoadIncomplete = true }
        isLoadingShips = false
    }

    private func retryLoadShips() async {
        allShipSections = []
        await loadAllShips()
    }

    private func loadAllModules() async {
        guard allModuleSections.isEmpty else { return }
        isLoadingModules = true
        defer { isLoadingModules = false }

        guard let modCategory = await UniverseCache.shared.category(id: 7) else { return }
        let groups = await UniverseCache.shared.groups(ids: Set(modCategory.groups))
        let publishedTypeIds = Array(Set(
            groups.values.filter(\.published).flatMap(\.types)
        ))
        guard !publishedTypeIds.isEmpty else { return }
        let types = await UniverseCache.shared.types(ids: publishedTypeIds)

        var bySlot: [SimSlotCategory: [ESIType]] = [:]
        for t in types.values where t.published {
            guard let effects = t.dogmaEffects,
                  let cat = SlotEffect.category(from: effects) else { continue }
            bySlot[cat, default: []].append(t)
        }

        allModuleSections = SimSlotCategory.allCases.compactMap { cat in
            guard let mods = bySlot[cat], !mods.isEmpty else { return nil }
            return (category: cat, modules: mods.sorted { $0.name < $1.name })
        }
    }

    // MARK: Helpers

    private func filterModules(_ modules: [ESIType]) -> [ESIType] {
        let q = moduleFilterText.lowercased().trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return modules }
        return modules.filter { $0.name.lowercased().contains(q) }
    }

    @ViewBuilder
    private func searchBar(
        text: Binding<String>,
        placeholder: String,
        onChange: @escaping (String) -> Void
    ) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass").foregroundStyle(.secondary).font(.subheadline)
            TextField(placeholder, text: text)
                .textFieldStyle(.plain)
                .onChange(of: text.wrappedValue) { _, q in onChange(q) }
            if !text.wrappedValue.isEmpty {
                Button { text.wrappedValue = "" } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 10).padding(.vertical, 7)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 8))
        .padding(10)
    }

    private func emptyState(_ msg: String) -> some View {
        VStack(spacing: 8) {
            Image(systemName: "questionmark.circle").font(.largeTitle).foregroundStyle(.tertiary)
            Text(msg).font(.subheadline).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK:  Ship Search Row

struct SimShipRow: View {
    let type: ESIType
    var className: String = ""

    var body: some View {
        HStack(spacing: 10) {
            AsyncImage(url: EVEImageURL.typeRender(type.typeId, size: 128)) { img in
                img.resizable().aspectRatio(contentMode: .fill)
            } placeholder: {
                RoundedRectangle(cornerRadius: 8).fill(.quaternary)
            }
            .frame(width: 48, height: 48)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(.white.opacity(0.08), lineWidth: 0.5))

            VStack(alignment: .leading, spacing: 2) {
                Text(type.name).font(.subheadline.bold())
                Text(className.isEmpty ? "Ship" : className)
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(.vertical, 4)
    }
}

// MARK:  Module Search Row

struct SimModuleRow: View {
    let type: ESIType

    var body: some View {
        HStack(spacing: 10) {
            AsyncImage(url: EVEImageURL.typeIcon(type.typeId, size: 64)) { img in
                img.resizable().aspectRatio(contentMode: .fit)
            } placeholder: {
                RoundedRectangle(cornerRadius: 6).fill(.quaternary)
            }
            .frame(width: 34, height: 34)
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(.white.opacity(0.08), lineWidth: 0.5))

            Text(type.name).font(.subheadline).lineLimit(2)
            Spacer()
        }
        .padding(.vertical, 2)
    }
}
