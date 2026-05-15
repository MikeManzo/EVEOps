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

// MARK:  Tab

private enum FittingsTab {
    case ships, savedFittings, community, simulate
}

// MARK:  Ship Data Models

struct ShipEntry: Identifiable, Hashable {
    let characterID: Int
    let characterName: String
    let itemId: Int
    let typeId: Int
    let typeName: String
    let customName: String?
    let locationName: String
    let isSingleton: Bool
    let shipClassName: String
    var id: Int { itemId }
    var displayName: String { customName ?? typeName }
}

struct CharacterShipGroup {
    let characterName: String
    let ships: [ShipEntry]
}

// MARK:  Saved Fitting Data Models

struct SavedFittingEntry: Identifiable, Hashable {
    let characterID: Int
    let characterName: String
    let fittingId: Int
    let name: String
    let fittingDescription: String
    let shipTypeId: Int
    let shipTypeName: String
    let shipClassName: String
    let items: [ESIFittingItem]
    var id: Int { fittingId }
}

struct CharacterFittingGroup {
    let characterName: String
    let fittings: [SavedFittingEntry]
}

// MARK:  Main View

struct CharacterFittingsView: View {
    @Environment(AccountManager.self) private var accountManager
    @Environment(DashboardPrefetcher.self) private var prefetcher
    @AppStorage("backgroundPollInterval") private var pollInterval: Double = 300

    // Ships tab
    @State private var shipSections: [(className: String, ships: [ShipEntry])] = []
    @State private var modulesByShip: [Int: [ESIAsset]] = [:]
    @State private var moduleTypeNames: [Int: String] = [:]
    @State private var isLoading = false
    @State private var error: String?
    @State private var selectedShip: ShipEntry?
    @State private var multiAccount = false

    // Saved fittings tab
    @State private var fittingSections: [(className: String, fittings: [SavedFittingEntry])] = []
    @State private var fittingTypeNames: [Int: String] = [:]
    @State private var isSavingsLoading = false
    @State private var savingsError: String?
    @State private var savedFittingsLoaded = false
    @State private var selectedFitting: SavedFittingEntry?

    @State private var activeTab: FittingsTab = .ships
    @State private var shipListID = UUID()
    @State private var fittingListID = UUID()
    @AppStorage("collapsedShipSections") private var collapsedShipRaw: String = ""
    @AppStorage("collapsedFittingSections") private var collapsedFittingRaw: String = ""

    private var shipsEmpty: Bool { shipSections.isEmpty }
    private var savedEmpty: Bool { fittingSections.isEmpty }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 2) {
                fittingsTabButton("Ships", icon: "ferry.fill", tab: .ships)
                fittingsTabButton("Saved Fittings", icon: "bookmark.fill", tab: .savedFittings)
                fittingsTabButton("Community", icon: "globe", tab: .community)
                fittingsTabButton("Simulate", icon: "slider.horizontal.3", tab: .simulate)
            }
            .padding(3)
            .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .zIndex(1)

            Divider()

            if activeTab == .ships {
                LoadingStateView(isLoading: isLoading, error: error, isEmpty: shipsEmpty, emptyMessage: "No ships found") {
                    shipsContent
                }
            } else if activeTab == .savedFittings {
                LoadingStateView(
                    isLoading: isSavingsLoading || !savedFittingsLoaded,
                    error: savingsError,
                    isEmpty: savedEmpty,
                    emptyMessage: "No saved fittings — select a ship and use 'Save Fitting'"
                ) {
                    savedFittingsContent
                }
            } else if activeTab == .community {
                CommunityFittingsView()
            } else {
                SimulateFittingView()
            }
        }
        .navigationTitle("Ships & Fittings")
        .toolbar {
            ToolbarItem(placement: .automatic) {
                Button {
                    Task {
                        await ESIClient.shared.clearCache()
                        await UniverseCache.shared.clearDiskCache()
                        if activeTab == .ships {
                            await load()
                        } else {
                            await loadSavedFittings()
                        }
                    }
                } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
            }
        }
        .task { await load() }
        .task(id: pollInterval) {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(pollInterval))
                await load()
            }
        }
        .onChange(of: prefetcher.lastRefresh) { _, _ in
            Task { await load() }
        }
        .onChange(of: activeTab) { _, newTab in
            if newTab == .savedFittings && !savedFittingsLoaded && !isSavingsLoading {
                Task { await loadSavedFittings() }
            }
        }
    }

    private var shipsContent: some View {
        HStack(spacing: 0) {
            List(selection: $selectedShip) {
                ForEach(shipSections, id: \.className) { section in
                    Section(isExpanded: Binding(
                        get: { !collapsedShipRaw.components(separatedBy: "\n").contains(section.className) },
                        set: { expanded in
                            var set = Set(collapsedShipRaw.components(separatedBy: "\n").filter { !$0.isEmpty })
                            if expanded { set.remove(section.className) } else { set.insert(section.className) }
                            collapsedShipRaw = set.joined(separator: "\n")
                        }
                    )) {
                        ForEach(section.ships) { ship in
                            ShipRow(ship: ship, showCharacterName: multiAccount).tag(ship)
                        }
                    } header: {
                        HStack(spacing: 8) {
                            Image(systemName: Self.shipClassIcon(section.className)).font(.body)
                            Text(section.className).font(.title2.bold())
                            Spacer()
                            Text("\(section.ships.count)")
                                .font(.subheadline.monospacedDigit())
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .id(shipListID)
            .frame(maxWidth: .infinity)

            if let ship = selectedShip {
                Divider()
                ShipDetailPane(
                    ship: ship,
                    modules: modulesByShip[ship.itemId] ?? [],
                    typeNames: moduleTypeNames,
                    onFittingSaved: {
                        Task { await loadSavedFittings() }
                    }
                )
                .frame(width: 340)
            }
        }
    }

    private var savedFittingsContent: some View {
        HStack(spacing: 0) {
            List(selection: $selectedFitting) {
                ForEach(fittingSections, id: \.className) { section in
                    Section(isExpanded: Binding(
                        get: { !collapsedFittingRaw.components(separatedBy: "\n").contains(section.className) },
                        set: { expanded in
                            var set = Set(collapsedFittingRaw.components(separatedBy: "\n").filter { !$0.isEmpty })
                            if expanded { set.remove(section.className) } else { set.insert(section.className) }
                            collapsedFittingRaw = set.joined(separator: "\n")
                        }
                    )) {
                        ForEach(section.fittings) { fitting in
                            SavedFittingRow(fitting: fitting, showCharacterName: multiAccount) {
                                Task { await deleteFitting(fitting) }
                            }
                            .tag(fitting)
                        }
                    } header: {
                        HStack(spacing: 8) {
                            Image(systemName: Self.shipClassIcon(section.className)).font(.body)
                            Text(section.className).font(.title2.bold())
                            Spacer()
                            Text("\(section.fittings.count)")
                                .font(.subheadline.monospacedDigit())
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .id(fittingListID)
            .frame(maxWidth: .infinity)

            if let fitting = selectedFitting {
                Divider()
                SavedFittingDetailPane(fitting: fitting, typeNames: fittingTypeNames)
                    .frame(width: 340)
            }
        }
    }

    // MARK:  EVE Ship Group Table (Static SDE data — immune to API cache corruption)

    static let eveShipGroups: [Int: String] = [
        29: "Capsule", 31: "Shuttle", 237: "Corvette",
        25: "Frigate", 358: "Assault Frigate", 541: "Interceptor",
        543: "Covert Ops", 831: "Electronic Attack Ship", 1022: "Expedition Frigate",
        420: "Destroyer", 833: "Interdictor", 902: "Tactical Destroyer", 1202: "Command Destroyer",
        26: "Cruiser", 359: "Heavy Assault Cruiser", 832: "Heavy Interdiction Cruiser",
        834: "Logistics", 906: "Recon Ship", 963: "Strategic Cruiser",
        419: "Battlecruiser", 1201: "Attack Battlecruiser", 540: "Command Ship",
        27: "Battleship", 381: "Black Ops", 659: "Marauder",
        485: "Dreadnought", 547: "Carrier", 893: "Force Auxiliary",
        30: "Titan", 548: "Supercarrier",
        28: "Industrial", 380: "Deep Space Transport", 894: "Blockade Runner",
        441: "Freighter", 898: "Jump Freighter",
        463: "Mining Barge", 900: "Exhumer", 1305: "Mining Frigate",
    ]
    static let eveShipGroupIds: Set<Int> = Set(eveShipGroups.keys)

    // MARK:  Load Ships

    private func load() async {
        guard !isLoading else { return }
        isLoading = true
        shipSections = []
        error = nil
        var allShips: [ShipEntry] = []
        var allModulesByShip: [Int: [ESIAsset]] = [:]
        var allModuleTypeIds: Set<Int> = []
        var lastError: Error?

        for account in accountManager.accounts {
            do {
                let token = try await accountManager.validToken(for: account)
                let rawAssets: [ESIAsset] = try await ESIClient.shared.fetchPages(
                    "/characters/\(account.characterID)/assets/", token: token
                )
                // Deduplicate itemIds — ESI may return duplicates across pages when items move
                var seenItemIds = Set<Int>()
                let assets = rawAssets.filter { seenItemIds.insert($0.itemId).inserted }

                let typeIds = Array(Set(assets.map(\.typeId)))
                let types = await UniverseCache.shared.types(ids: typeIds)

                let shipTypeIds = Set(
                    types.filter { Self.eveShipGroupIds.contains($0.value.groupId) }.keys
                )
                let shipAssets = assets.filter { shipTypeIds.contains($0.typeId) }

                let assetsByLocation = Dictionary(grouping: assets, by: \.locationId)
                for ship in shipAssets where ship.isSingleton {
                    let modules = (assetsByLocation[ship.itemId] ?? []).filter { isSlotModule($0.locationFlag) }
                    if !modules.isEmpty {
                        allModulesByShip[ship.itemId] = modules
                        allModuleTypeIds.formUnion(modules.map(\.typeId))
                    }
                }

                let assembledIds = shipAssets.filter(\.isSingleton).map(\.itemId)
                var customNames: [Int: String] = [:]
                if !assembledIds.isEmpty,
                   let nameResults: [ESIAssetName] = try? await ESIClient.shared.post(
                       "/characters/\(account.characterID)/assets/names/",
                       body: assembledIds, token: token
                   ) {
                    for entry in nameResults where entry.name != "None" {
                        customNames[entry.itemId] = entry.name
                    }
                }

                let locationIds = Array(Set(shipAssets.map(\.locationId)))
                var locationNames: [Int: String] = [:]
                await withTaskGroup(of: (Int, String).self) { group in
                    for locId in locationIds {
                        group.addTask {
                            (locId, await NameResolver.shared.resolveLocation(id: locId, token: token))
                        }
                    }
                    for await (locId, name) in group {
                        locationNames[locId] = name
                    }
                }

                let ships = shipAssets.map { asset in
                    let groupId = types[asset.typeId]?.groupId ?? 0
                    return ShipEntry(
                        characterID: account.characterID,
                        characterName: account.characterName,
                        itemId: asset.itemId,
                        typeId: asset.typeId,
                        typeName: types[asset.typeId]?.name ?? "Ship #\(asset.typeId)",
                        customName: customNames[asset.itemId],
                        locationName: locationNames[asset.locationId] ?? "#\(asset.locationId)",
                        isSingleton: asset.isSingleton,
                        shipClassName: Self.eveShipGroups[groupId] ?? "Unknown"
                    )
                }
                allShips.append(contentsOf: ships)
            } catch { lastError = error }
        }

        let moduleTypes = await UniverseCache.shared.types(ids: Array(allModuleTypeIds))
        moduleTypeNames = moduleTypes.mapValues(\.name)
        modulesByShip = allModulesByShip
        multiAccount = accountManager.accounts.count > 1

        let byClass = Dictionary(grouping: allShips, by: \.shipClassName)
        shipSections = byClass.keys
            .sorted()
            .map { className in
                (className: className, ships: byClass[className]!.sorted { $0.displayName < $1.displayName })
            }

        if selectedShip == nil { selectedShip = shipSections.first?.ships.first }
        if allShips.isEmpty, let e = lastError { self.error = e.localizedDescription }
        shipListID = UUID()
        isLoading = false
    }

    // MARK:  Load Saved Fittings

    private func loadSavedFittings() async {
        isSavingsLoading = true
        fittingSections = []
        savingsError = nil

        var rawByAccount: [(characterName: String, characterID: Int, fittings: [ESIFitting])] = []
        for account in accountManager.accounts {
            guard let token = try? await accountManager.validToken(for: account) else { continue }
            if let fittings: [ESIFitting] = try? await ESIClient.shared.fetch(
                "/characters/\(account.characterID)/fittings/",
                token: token,
                bypassCache: true
            ) {
                rawByAccount.append((account.characterName, account.characterID, fittings))
            }
        }

        let allTypeIds = Array(Set(rawByAccount.flatMap { item in
            item.fittings.map(\.shipTypeId) + item.fittings.flatMap { $0.items.map(\.typeId) }
        }))
        let types = await UniverseCache.shared.types(ids: allTypeIds)

        var allFittings: [SavedFittingEntry] = []
        for item in rawByAccount {
            let entries = item.fittings.map { fitting -> SavedFittingEntry in
                let groupId = types[fitting.shipTypeId]?.groupId ?? 0
                return SavedFittingEntry(
                    characterID: item.characterID,
                    characterName: item.characterName,
                    fittingId: fitting.fittingId,
                    name: fitting.name,
                    fittingDescription: fitting.description,
                    shipTypeId: fitting.shipTypeId,
                    shipTypeName: types[fitting.shipTypeId]?.name ?? "Unknown Ship",
                    shipClassName: Self.eveShipGroups[groupId] ?? "Unknown",
                    items: fitting.items
                )
            }
            allFittings.append(contentsOf: entries)
        }

        fittingTypeNames = types.mapValues(\.name)
        let byClass = Dictionary(grouping: allFittings, by: \.shipClassName)
        fittingSections = byClass.keys
            .sorted()
            .map { className in
                (className: className, fittings: byClass[className]!.sorted { $0.name < $1.name })
            }
        if selectedFitting == nil { selectedFitting = fittingSections.first?.fittings.first }
        fittingListID = UUID()
        isSavingsLoading = false
        savedFittingsLoaded = true
    }

    // MARK:  Delete Fitting

    private func deleteFitting(_ entry: SavedFittingEntry) async {
        guard let account = accountManager.accounts.first(where: { $0.characterID == entry.characterID }) else { return }
        do {
            let token = try await accountManager.validToken(for: account)
            try await ESIClient.shared.delete(
                "/characters/\(entry.characterID)/fittings/\(entry.fittingId)/",
                token: token
            )
            fittingSections = fittingSections.compactMap { section in
                let remaining = section.fittings.filter { $0.id != entry.fittingId }
                return remaining.isEmpty ? nil : (className: section.className, fittings: remaining)
            }
            if selectedFitting?.id == entry.fittingId {
                selectedFitting = fittingSections.first?.fittings.first
            }
        } catch {
            savingsError = error.localizedDescription
        }
    }

    // MARK:  Helpers

    @ViewBuilder
    private func fittingsTabButton(_ title: String, icon: String, tab: FittingsTab) -> some View {
        Label(title, systemImage: icon)
            .font(.subheadline)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(activeTab == tab ? Color.accentColor : Color.clear,
                        in: RoundedRectangle(cornerRadius: 6))
            .foregroundStyle(activeTab == tab ? .white : .primary)
            .contentShape(Rectangle())
            .onTapGesture { activeTab = tab }
    }

    private func isSlotModule(_ flag: String) -> Bool {
        flag.hasPrefix("HiSlot") || flag.hasPrefix("MedSlot") || flag.hasPrefix("LoSlot") ||
        flag.hasPrefix("RigSlot") || flag.hasPrefix("SubSystem") ||
        flag == "DroneBay" || flag == "FighterBay" || flag == "Cargo"
    }

    static func shipClassIcon(_ name: String) -> String {
        switch name {
        case "Capsule":                         return "dot.circle.fill"
        case "Shuttle":                         return "paperplane.fill"
        case "Corvette":                        return "scope"
        case "Frigate", "Assault Frigate",
             "Interceptor", "Covert Ops",
             "Electronic Attack Ship",
             "Expedition Frigate":              return "arrowtriangle.up.fill"
        case "Destroyer", "Interdictor",
             "Command Destroyer",
             "Tactical Destroyer":              return "bolt.fill"
        case "Cruiser", "Heavy Assault Cruiser",
             "Heavy Interdiction Cruiser",
             "Logistics", "Recon Ship",
             "Strategic Cruiser":               return "shield.fill"
        case "Battlecruiser", "Attack Battlecruiser",
             "Command Ship":                    return "shield.lefthalf.filled"
        case "Battleship", "Black Ops",
             "Marauder":                        return "star.fill"
        case "Carrier", "Force Auxiliary":      return "building.2.fill"
        case "Dreadnought":                     return "scope"
        case "Supercarrier", "Titan":           return "crown.fill"
        case "Freighter", "Jump Freighter":     return "shippingbox.fill"
        case "Industrial", "Deep Space Transport",
             "Blockade Runner":                 return "cube.box.fill"
        case "Industrial Command Ship",
             "Mining Barge", "Exhumer",
             "Mining Frigate":                  return "cube.fill"
        default:                                return "questionmark.circle.fill"
        }
    }
}

// MARK:  Ship List Row

struct ShipRow: View {
    let ship: ShipEntry
    var showCharacterName: Bool = false

    var body: some View {
        HStack(spacing: 12) {
            AsyncImage(url: EVEImageURL.typeRender(ship.typeId, size: 256)) { image in
                image.resizable().aspectRatio(contentMode: .fill)
            } placeholder: {
                RoundedRectangle(cornerRadius: 6).fill(.quaternary)
            }
            .frame(width: 52, height: 52)
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .strokeBorder(.white.opacity(0.08), lineWidth: 0.5)
            )

            VStack(alignment: .leading, spacing: 3) {
                Text(ship.displayName).font(.subheadline.bold())
                if ship.customName != nil {
                    Text(ship.typeName)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                if showCharacterName {
                    Text(ship.characterName)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Text(ship.locationName)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                HStack(spacing: 4) {
                    if ship.isSingleton {
                        Label("Assembled", systemImage: "checkmark.circle.fill")
                            .font(.caption2)
                            .foregroundStyle(.green)
                            .labelStyle(.titleAndIcon)
                    } else {
                        Label("Packaged", systemImage: "shippingbox")
                            .font(.caption2)
                            .foregroundStyle(.orange)
                            .labelStyle(.titleAndIcon)
                    }
                }
            }
        }
        .padding(.vertical, 3)
    }
}

// MARK:  Ship Detail Pane

struct ShipDetailPane: View {
    let ship: ShipEntry
    let modules: [ESIAsset]
    let typeNames: [Int: String]
    var onFittingSaved: (() -> Void)? = nil

    @Environment(AccountManager.self) private var accountManager
    @State private var showSaveSheet = false

    var body: some View {
        VStack(spacing: 0) {
            ZStack(alignment: .bottomLeading) {
                AsyncImage(url: EVEImageURL.typeRender(ship.typeId, size: 512)) { image in
                    image.resizable().aspectRatio(contentMode: .fill)
                } placeholder: {
                    Rectangle().fill(
                        LinearGradient(
                            colors: [Color(.darkGray).opacity(0.4), .black.opacity(0.6)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                }
                .frame(height: 160)
                .clipped()

                LinearGradient(
                    stops: [
                        .init(color: .clear, location: 0.0),
                        .init(color: .black.opacity(0.75), location: 1.0)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )

                HStack(alignment: .bottom) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(ship.displayName)
                            .font(.headline)
                            .foregroundStyle(.white)
                        if ship.customName != nil {
                            Text(ship.typeName)
                                .font(.caption)
                                .foregroundStyle(.white.opacity(0.6))
                        }
                        Label(ship.locationName, systemImage: "mappin.circle.fill")
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.75))
                            .lineLimit(1)
                    }
                    Spacer()
                    if ship.isSingleton && !modules.isEmpty {
                        Button { showSaveSheet = true } label: {
                            Label("Save Fitting", systemImage: "bookmark.fill")
                                .font(.caption.bold())
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 8))
                                .foregroundStyle(.white)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(12)
            }
            .frame(height: 160)

            Divider()

            if !ship.isSingleton {
                VStack(spacing: 10) {
                    Image(systemName: "shippingbox")
                        .font(.largeTitle)
                        .foregroundStyle(.tertiary)
                    Text("Ship is packaged")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Text("Unpackage the ship in-game to view its fitting.")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .multilineTextAlignment(.center)
                }
                .padding()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if modules.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "wrench.and.screwdriver")
                        .font(.largeTitle)
                        .foregroundStyle(.tertiary)
                    Text("No modules fitted")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Text("This ship has no modules in its fitting slots.")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .multilineTextAlignment(.center)
                }
                .padding()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                CurrentFittingPane(modules: modules, typeNames: typeNames, shipName: ship.typeName, shipClass: ship.shipClassName)
            }
        }
        .sheet(isPresented: $showSaveSheet) {
            SaveFittingSheet(ship: ship, modules: modules, onSaved: onFittingSaved)
                .environment(accountManager)
        }
    }
}

// MARK:  Save Fitting Sheet

struct SaveFittingSheet: View {
    let ship: ShipEntry
    let modules: [ESIAsset]
    var onSaved: (() -> Void)? = nil

    @Environment(AccountManager.self) private var accountManager
    @Environment(\.dismiss) private var dismiss

    @State private var name: String
    @State private var fittingDescription = ""
    @State private var isSaving = false
    @State private var saveError: String?

    init(ship: ShipEntry, modules: [ESIAsset], onSaved: (() -> Void)? = nil) {
        self.ship = ship
        self.modules = modules
        self.onSaved = onSaved
        _name = State(initialValue: ship.displayName)
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Save Fitting").font(.headline)
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
            }
            .padding()

            Divider()

            Form {
                Section("Ship") {
                    HStack(spacing: 12) {
                        AsyncImage(url: EVEImageURL.typeRender(ship.typeId, size: 128)) { image in
                            image.resizable().aspectRatio(contentMode: .fill)
                        } placeholder: {
                            RoundedRectangle(cornerRadius: 6).fill(.quaternary)
                        }
                        .frame(width: 44, height: 44)
                        .clipShape(RoundedRectangle(cornerRadius: 6))

                        VStack(alignment: .leading, spacing: 2) {
                            Text(ship.typeName).font(.subheadline.bold())
                            Text(ship.shipClassName).font(.caption).foregroundStyle(.secondary)
                            Text("\(modules.count) modules").font(.caption2).foregroundStyle(.tertiary)
                        }
                    }
                    .padding(.vertical, 2)
                }

                Section("Name") {
                    TextField("Fitting name", text: $name)
                }

                Section("Description") {
                    TextField("Optional description", text: $fittingDescription, axis: .vertical)
                        .lineLimit(2...4)
                }
            }
            .formStyle(.grouped)

            Divider()

            HStack {
                if let saveError {
                    Label(saveError, systemImage: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(.red)
                        .lineLimit(2)
                }
                Spacer()
                if isSaving { ProgressView().controlSize(.small) }
                Button("Save") { Task { await save() } }
                    .keyboardShortcut(.defaultAction)
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty || isSaving)
                    .buttonStyle(.borderedProminent)
            }
            .padding()
        }
        .frame(width: 400)
        .fixedSize(horizontal: false, vertical: true)
    }

    private func save() async {
        isSaving = true
        saveError = nil
        guard let account = accountManager.accounts.first(where: { $0.characterID == ship.characterID }) else {
            saveError = "Account not found"
            isSaving = false
            return
        }
        do {
            let token = try await accountManager.validToken(for: account)
            let items = modules.map { ESIFittingItemSave(flag: $0.locationFlag, quantity: $0.quantity, typeId: $0.typeId) }
            let body = ESIFittingSaveRequest(
                description: fittingDescription,
                items: items,
                name: name.trimmingCharacters(in: .whitespaces),
                shipTypeId: ship.typeId
            )
            let _: ESIFittingCreatedResponse = try await ESIClient.shared.post(
                "/characters/\(ship.characterID)/fittings/",
                body: body,
                token: token
            )
            onSaved?()
            dismiss()
        } catch ESIError.unauthorized {
            saveError = "Missing permission — please re-authenticate to enable saving fittings."
        } catch {
            saveError = error.localizedDescription
        }
        isSaving = false
    }
}

// MARK:  Saved Fitting Row

struct SavedFittingRow: View {
    let fitting: SavedFittingEntry
    var showCharacterName: Bool = false
    let onDelete: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            AsyncImage(url: EVEImageURL.typeRender(fitting.shipTypeId, size: 256)) { image in
                image.resizable().aspectRatio(contentMode: .fill)
            } placeholder: {
                RoundedRectangle(cornerRadius: 6).fill(.quaternary)
            }
            .frame(width: 52, height: 52)
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .strokeBorder(.white.opacity(0.08), lineWidth: 0.5)
            )

            VStack(alignment: .leading, spacing: 3) {
                Text(fitting.name).font(.subheadline.bold())
                Text(fitting.shipTypeName)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                if showCharacterName {
                    Text(fitting.characterName)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Text("\(fitting.items.count) modules")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 3)
        .contextMenu {
            Button(role: .destructive, action: onDelete) {
                Label("Delete Fitting", systemImage: "trash")
            }
        }
        .swipeActions(edge: .trailing) {
            Button(role: .destructive, action: onDelete) {
                Label("Delete", systemImage: "trash")
            }
        }
    }
}

// MARK:  Saved Fitting Detail Pane

struct SavedFittingDetailPane: View {
    let fitting: SavedFittingEntry
    let typeNames: [Int: String]

    var body: some View {
        VStack(spacing: 0) {
            ZStack(alignment: .bottomLeading) {
                AsyncImage(url: EVEImageURL.typeRender(fitting.shipTypeId, size: 512)) { image in
                    image.resizable().aspectRatio(contentMode: .fill)
                } placeholder: {
                    Rectangle().fill(
                        LinearGradient(
                            colors: [Color(.darkGray).opacity(0.4), .black.opacity(0.6)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                }
                .frame(height: 160)
                .clipped()

                LinearGradient(
                    stops: [
                        .init(color: .clear, location: 0.0),
                        .init(color: .black.opacity(0.75), location: 1.0)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )

                VStack(alignment: .leading, spacing: 3) {
                    Text(fitting.name)
                        .font(.headline)
                        .foregroundStyle(.white)
                    Text(fitting.shipTypeName)
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.7))
                    if !fitting.fittingDescription.isEmpty {
                        Text(fitting.fittingDescription)
                            .font(.caption2)
                            .foregroundStyle(.white.opacity(0.5))
                            .lineLimit(1)
                    }
                }
                .padding(12)
            }
            .frame(height: 160)

            Divider()

            if fitting.items.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "wrench.and.screwdriver")
                        .font(.largeTitle)
                        .foregroundStyle(.tertiary)
                    Text("No modules in this fitting")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .padding()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                SavedFittingSlotPane(items: fitting.items, typeNames: typeNames, shipName: fitting.shipTypeName, shipClass: fitting.shipClassName)
            }
        }
    }
}

// MARK:  Saved Fitting Slot Pane

struct SavedFittingSlotPane: View {
    let items: [ESIFittingItem]
    let typeNames: [Int: String]
    let shipName: String
    let shipClass: String

    @AppStorage("aiInsightFittings") private var aiInsightFittings = true
    private let slotOrder = ["High Slots", "Med Slots", "Low Slots", "Rig Slots", "Subsystems", "Drone Bay", "Fighter Bay", "Cargo"]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                if #available(macOS 26.0, *) {
                    FittingAIInsightCard(
                        shipName: shipName,
                        shipClass: shipClass,
                        slotModules: slotSummary(),
                        featureEnabled: aiInsightFittings
                    )
                }
                let grouped = Dictionary(grouping: items) { slotCategory($0.flag) }
                ForEach(slotOrder.filter { grouped[$0] != nil }, id: \.self) { category in
                    GroupBox {
                        LazyVGrid(
                            columns: [GridItem(.flexible()), GridItem(.flexible())],
                            spacing: 6
                        ) {
                            ForEach(grouped[category]!) { item in
                                SavedModuleCell(item: item, name: typeNames[item.typeId])
                            }
                        }
                    } label: {
                        Label(category, systemImage: slotIcon(category))
                            .font(.caption.bold())
                            .foregroundStyle(slotColor(category))
                    }
                }
            }
            .padding(12)
        }
    }

    private func slotSummary() -> [(category: String, names: [String])] {
        let grouped = Dictionary(grouping: items) { slotCategory($0.flag) }
        return slotOrder.compactMap { cat in
            guard let catItems = grouped[cat], !catItems.isEmpty else { return nil }
            return (category: cat, names: catItems.map { typeNames[$0.typeId] ?? "Unknown" })
        }
    }

    private func slotCategory(_ flag: String) -> String {
        if flag.hasPrefix("HiSlot") { return "High Slots" }
        if flag.hasPrefix("MedSlot") { return "Med Slots" }
        if flag.hasPrefix("LoSlot") { return "Low Slots" }
        if flag.hasPrefix("RigSlot") { return "Rig Slots" }
        if flag.hasPrefix("SubSystem") { return "Subsystems" }
        if flag == "DroneBay" { return "Drone Bay" }
        if flag == "FighterBay" { return "Fighter Bay" }
        return "Cargo"
    }

    private func slotColor(_ category: String) -> Color {
        switch category {
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

    private func slotIcon(_ category: String) -> String {
        switch category {
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

// MARK:  Saved Module Cell

struct SavedModuleCell: View {
    let item: ESIFittingItem
    let name: String?
    @State private var showPopover = false

    var body: some View {
        Button { showPopover = true } label: {
            HStack(spacing: 8) {
                AsyncImage(url: EVEImageURL.typeIcon(item.typeId, size: 64)) { image in
                    image.resizable()
                } placeholder: {
                    RoundedRectangle(cornerRadius: 4).fill(.quaternary)
                }
                .frame(width: 32, height: 32)
                .clipShape(RoundedRectangle(cornerRadius: 4))
                .overlay(
                    RoundedRectangle(cornerRadius: 4)
                        .strokeBorder(.white.opacity(0.1), lineWidth: 0.5)
                )

                VStack(alignment: .leading, spacing: 1) {
                    Text(name ?? "Type #\(item.typeId)")
                        .font(.caption)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                    if item.quantity > 1 {
                        Text("x\(item.quantity)")
                            .font(.caption2.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(7)
            .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 7))
            .contentShape(RoundedRectangle(cornerRadius: 7))
        }
        .buttonStyle(.plain)
        .popover(isPresented: $showPopover, arrowEdge: .trailing) {
            ModuleDetailPopover(typeId: item.typeId, name: name, quantity: item.quantity)
        }
    }
}

// MARK:  Fitting Slots Pane

struct CurrentFittingPane: View {
    let modules: [ESIAsset]
    let typeNames: [Int: String]
    let shipName: String
    let shipClass: String

    @AppStorage("aiInsightFittings") private var aiInsightFittings = true
    private let slotOrder = ["High Slots", "Med Slots", "Low Slots", "Rig Slots", "Subsystems", "Drone Bay", "Fighter Bay", "Cargo"]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                if #available(macOS 26.0, *) {
                    FittingAIInsightCard(
                        shipName: shipName,
                        shipClass: shipClass,
                        slotModules: slotSummary(),
                        featureEnabled: aiInsightFittings
                    )
                }
                let grouped = Dictionary(grouping: modules) { slotCategory($0.locationFlag) }
                ForEach(slotOrder.filter { grouped[$0] != nil }, id: \.self) { category in
                    GroupBox {
                        LazyVGrid(
                            columns: [GridItem(.flexible()), GridItem(.flexible())],
                            spacing: 6
                        ) {
                            ForEach(grouped[category]!, id: \.itemId) { module in
                                ModuleCell(module: module, name: typeNames[module.typeId])
                            }
                        }
                    } label: {
                        Label(category, systemImage: slotIcon(category))
                            .font(.caption.bold())
                            .foregroundStyle(slotColor(category))
                    }
                }
            }
            .padding(12)
        }
    }

    private func slotSummary() -> [(category: String, names: [String])] {
        let grouped = Dictionary(grouping: modules) { slotCategory($0.locationFlag) }
        return slotOrder.compactMap { cat in
            guard let catModules = grouped[cat], !catModules.isEmpty else { return nil }
            return (category: cat, names: catModules.map { typeNames[$0.typeId] ?? "Unknown" })
        }
    }

    private func slotCategory(_ flag: String) -> String {
        if flag.hasPrefix("HiSlot") { return "High Slots" }
        if flag.hasPrefix("MedSlot") { return "Med Slots" }
        if flag.hasPrefix("LoSlot") { return "Low Slots" }
        if flag.hasPrefix("RigSlot") { return "Rig Slots" }
        if flag.hasPrefix("SubSystem") { return "Subsystems" }
        if flag == "DroneBay" { return "Drone Bay" }
        if flag == "FighterBay" { return "Fighter Bay" }
        return "Cargo"
    }

    private func slotColor(_ category: String) -> Color {
        switch category {
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

    private func slotIcon(_ category: String) -> String {
        switch category {
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

// MARK:  Module Grid Cell

struct ModuleCell: View {
    let module: ESIAsset
    let name: String?
    @State private var showPopover = false

    var body: some View {
        Button { showPopover = true } label: {
            HStack(spacing: 8) {
                AsyncImage(url: EVEImageURL.typeIcon(module.typeId, size: 64)) { image in
                    image.resizable()
                } placeholder: {
                    RoundedRectangle(cornerRadius: 4).fill(.quaternary)
                }
                .frame(width: 32, height: 32)
                .clipShape(RoundedRectangle(cornerRadius: 4))
                .overlay(
                    RoundedRectangle(cornerRadius: 4)
                        .strokeBorder(.white.opacity(0.1), lineWidth: 0.5)
                )

                VStack(alignment: .leading, spacing: 1) {
                    Text(name ?? "Type #\(module.typeId)")
                        .font(.caption)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                    if module.quantity > 1 {
                        Text("x\(module.quantity)")
                            .font(.caption2.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(7)
            .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 7))
            .contentShape(RoundedRectangle(cornerRadius: 7))
        }
        .buttonStyle(.plain)
        .popover(isPresented: $showPopover, arrowEdge: .trailing) {
            ModuleDetailPopover(typeId: module.typeId, name: name, quantity: module.quantity)
        }
    }
}

// MARK:  Fitting AI Insight Card

@available(macOS 26.0, *)
struct FittingAIInsightCard: View {
    let shipName: String
    let shipClass: String
    let slotModules: [(category: String, names: [String])]
    var featureEnabled: Bool = true

    @AppStorage("aiInsightsEnabled") private var aiInsightsEnabled = false
    @State private var insight: FittingInsight?
    @State private var isGenerating = false
    @State private var generationError: String?
    @State private var hasAutoGenerated = false

    private var model: SystemLanguageModel { .default }

    var body: some View {
        if aiInsightsEnabled && featureEnabled, case .available = model.availability {
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
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                        .help("Regenerate insight")
                    }
                }

                if isGenerating {
                    HStack(spacing: 8) {
                        ProgressView().controlSize(.small)
                        Text("Analyzing fitting\u{2026}")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                } else if let insight {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(insight.roleAssessment)
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
            .task(id: shipName) {
                guard !hasAutoGenerated else { return }
                hasAutoGenerated = true
                await generate()
            }
        }
    }

    private func generate() async {
        isGenerating = true
        generationError = nil
        do {
            insight = try await IntelligenceService.shared.analyzeFitting(
                shipName: shipName,
                shipClass: shipClass,
                slotModules: slotModules
            )
        } catch {
            generationError = "Unable to generate insight. Try again later."
        }
        isGenerating = false
    }
}

// MARK:  Module Detail Popover

struct ModuleDetailPopover: View {
    let typeId: Int
    let name: String?
    let quantity: Int

    @Environment(\.openWindow) private var openWindow
    @State private var esiType: ESIType?
    @State private var groupName: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 12) {
                AsyncImage(url: EVEImageURL.typeIcon(typeId, size: 128)) { image in
                    image.resizable()
                } placeholder: {
                    RoundedRectangle(cornerRadius: 8).fill(.quaternary)
                }
                .frame(width: 64, height: 64)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .strokeBorder(.white.opacity(0.1), lineWidth: 0.5)
                )

                VStack(alignment: .leading, spacing: 4) {
                    Text(name ?? "Type #\(typeId)")
                        .font(.headline)
                    if let groupName {
                        Text(groupName)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    } else {
                        Text("Loading…")
                            .font(.subheadline)
                            .foregroundStyle(.tertiary)
                    }
                    if quantity > 1 {
                        Text("Quantity: \(quantity)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
            }
            .padding(16)

            if let type = esiType {
                Divider()

                let stats: [(String, String, String)] = [
                    type.volume.map { ("cube.fill", "Volume", volumeString($0)) },
                    type.mass.map { ("scalemass.fill", "Mass", massString($0)) },
                    type.capacity.map { ("archivebox.fill", "Capacity", volumeString($0)) },
                ].compactMap { $0 }

                if !stats.isEmpty {
                    HStack(spacing: 0) {
                        ForEach(Array(stats.enumerated()), id: \.offset) { _, stat in
                            VStack(spacing: 3) {
                                Image(systemName: stat.0)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Text(stat.2)
                                    .font(.caption.monospacedDigit())
                                Text(stat.1)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                            .frame(maxWidth: .infinity)
                        }
                    }
                    .padding(.vertical, 10)
                    .background(.quaternary.opacity(0.3))

                    Divider()
                }

                if let desc = type.description, !desc.isEmpty {
                    ScrollView {
                        Text(desc)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(14)
                    }
                    .frame(maxHeight: 180)
                }
            } else {
                HStack {
                    ProgressView().controlSize(.small)
                    Text("Loading details…").font(.caption).foregroundStyle(.secondary)
                }
                .padding(16)
            }
        }

        Divider()

        Button {
            openWindow(value: GalaxyMarketSearchInput(typeId: typeId, typeName: name ?? "Type #\(typeId)"))
        } label: {
            Label("Find in Galaxy", systemImage: "globe.europe.africa.fill")
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderless)
        .foregroundStyle(.blue)
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .frame(width: 300)
        .task { await fetchDetails() }
    }

    private func fetchDetails() async {
        let types = await UniverseCache.shared.types(ids: [typeId])
        guard let t = types[typeId] else { return }
        esiType = t
        let groups = await UniverseCache.shared.groups(ids: Set([t.groupId]))
        groupName = groups[t.groupId]?.name
    }

    private func volumeString(_ v: Double) -> String {
        v >= 1000 ? String(format: "%.0f m³", v) : String(format: "%.2f m³", v)
    }

    private func massString(_ m: Double) -> String {
        m >= 1_000_000 ? String(format: "%.0f t", m / 1_000_000) : String(format: "%.0f kg", m)
    }
}
