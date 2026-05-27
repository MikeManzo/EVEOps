//
// SimLoadFittingSheet.swift
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
import UniformTypeIdentifiers

// MARK:  Load Fitting Sheet

struct SimLoadFittingSheet: View {
    @Environment(SimulatorState.self) private var simState
    @Environment(AccountManager.self) private var accountManager
    @Environment(\.dismiss) private var dismiss

    enum LoadMode { case saved, current, eft }
    @State private var mode: LoadMode = .saved
    @State private var savedFittings: [SavedFittingEntry] = []
    @State private var ships: [ShipEntry] = []
    @State private var shipModules: [Int: [ESIAsset]] = [:]
    @State private var isLoading = false

    // From File import state
    @State private var showFileImporter = false
    @State private var isResolvingEFT = false
    @State private var eftError: String?

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Load Fitting").font(.headline)
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
            }
            .padding()

            Picker("Mode", selection: $mode) {
                Text("Saved Fittings").tag(LoadMode.saved)
                Text("Current Ships").tag(LoadMode.current)
                Text("From File").tag(LoadMode.eft)
            }
            .pickerStyle(.segmented)
            .padding(.horizontal)
            .padding(.bottom, 8)

            Divider()

            if isLoading {
                VStack(spacing: 8) {
                    ProgressView()
                    Text("Loading…").font(.caption).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if mode == .saved {
                savedFittingsList
            } else if mode == .current {
                currentShipsList
            } else {
                eftImportView
            }
        }
        .frame(width: 380, height: 480)
        .task { await loadData() }
        .fileImporter(
            isPresented: $showFileImporter,
            allowedContentTypes: [.eveFitting, .plainText],
            allowsMultipleSelection: false
        ) { result in
            Task { await handleFileImport(result) }
        }
    }

    private var savedFittingsList: some View {
        Group {
            if savedFittings.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "bookmark.slash").font(.largeTitle).foregroundStyle(.tertiary)
                    Text("No saved fittings found").font(.subheadline).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(savedFittings) { fitting in
                    loadRow(
                        imageURL: EVEImageURL.typeRender(fitting.shipTypeId, size: 128),
                        title: fitting.name,
                        subtitle: fitting.shipTypeName,
                        detail: "\(fitting.items.count) modules"
                    ) {
                        Task { await simState.loadFromSavedFitting(fitting); dismiss() }
                    }
                }
                .listStyle(.inset)
            }
        }
    }

    private var currentShipsList: some View {
        Group {
            if ships.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "helm").font(.largeTitle).foregroundStyle(.tertiary)
                    Text("No assembled ships found").font(.subheadline).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(ships) { ship in
                    loadRow(
                        imageURL: EVEImageURL.typeRender(ship.typeId, size: 128),
                        title: ship.displayName,
                        subtitle: ship.typeName,
                        detail: ship.locationName
                    ) {
                        Task {
                            await simState.loadFromShipModules(ship, modules: shipModules[ship.itemId] ?? [])
                            dismiss()
                        }
                    }
                }
                .listStyle(.inset)
            }
        }
    }

    private func loadRow(
        imageURL: URL?,
        title: String,
        subtitle: String,
        detail: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                AsyncImage(url: imageURL) { img in
                    img.resizable().aspectRatio(contentMode: .fill)
                } placeholder: {
                    RoundedRectangle(cornerRadius: 6).fill(.quaternary)
                }
                .frame(width: 44, height: 44)
                .clipShape(RoundedRectangle(cornerRadius: 6))

                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.subheadline.bold())
                    Text(subtitle).font(.caption).foregroundStyle(.secondary)
                    Text(detail).font(.caption2).foregroundStyle(.tertiary)
                }
                Spacer()
                Image(systemName: "chevron.right").font(.caption2).foregroundStyle(.tertiary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: From File

    private var eftImportView: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "doc.badge.arrow.up")
                .font(.system(size: 44))
                .foregroundStyle(.secondary)
            Text("Import a .eft fitting file")
                .font(.subheadline)
            Text("Compatible with Pyfa, EFT, and the EVE Online fitting window")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)

            if isResolvingEFT {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("Resolving modules…").font(.caption).foregroundStyle(.secondary)
                }
            } else if let eftError {
                Text(eftError)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
            }

            Button("Choose .eft File…") { showFileImporter = true }
                .buttonStyle(.borderedProminent)
                .disabled(isResolvingEFT)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func handleFileImport(_ result: Result<[URL], Error>) async {
        guard case .success(let urls) = result, let url = urls.first else {
            if case .failure(let error) = result { eftError = error.localizedDescription }
            return
        }

        let accessed = url.startAccessingSecurityScopedResource()
        defer { if accessed { url.stopAccessingSecurityScopedResource() } }

        isResolvingEFT = true
        eftError = nil

        do {
            let text = try String(contentsOf: url, encoding: .utf8)
            let parsed = try EFTSerializer.parse(eftText: text)

            guard let account = accountManager.selectedAccount,
                  let token = try? await accountManager.validToken(for: account) else {
                eftError = "No active account — sign in to resolve module names"
                isResolvingEFT = false
                return
            }

            let (shipTypeId, name, items) = try await EFTSerializer.resolve(
                parsed: parsed, account: account, token: token
            )
            let entry = SavedFittingEntry(
                characterID: 0, characterName: "",
                fittingId: 0, name: name, fittingDescription: "",
                shipTypeId: shipTypeId, shipTypeName: parsed.shipTypeName,
                shipClassName: "", items: items
            )
            await simState.loadFromSavedFitting(entry)
            dismiss()
        } catch {
            eftError = error.localizedDescription
        }
        isResolvingEFT = false
    }

    private func loadData() async {
        isLoading = true
        var fittings: [SavedFittingEntry] = []
        var loadedShips: [ShipEntry] = []
        var loadedModules: [Int: [ESIAsset]] = [:]

        for account in accountManager.accounts {
            guard let token = try? await accountManager.validToken(for: account) else { continue }

            if let raw: [ESIFitting] = try? await ESIClient.shared.fetch(
                "/characters/\(account.characterID)/fittings/", token: token
            ) {
                let tids = Array(Set(raw.map(\.shipTypeId)))
                let types = await UniverseCache.shared.types(ids: tids)
                let fittingGroupIds = Set(types.values.map(\.groupId))
                let fittingGroups = await UniverseCache.shared.groups(ids: fittingGroupIds)
                for f in raw {
                    let gid = types[f.shipTypeId]?.groupId ?? 0
                    fittings.append(SavedFittingEntry(
                        characterID: account.characterID,
                        characterName: account.characterName,
                        fittingId: f.fittingId,
                        name: f.name,
                        fittingDescription: f.description,
                        shipTypeId: f.shipTypeId,
                        shipTypeName: types[f.shipTypeId]?.name ?? "Unknown",
                        shipClassName: fittingGroups[gid]?.name ?? "Unknown",
                        items: f.items
                    ))
                }
            }

            if let rawAssets: [ESIAsset] = try? await ESIClient.shared.fetchPages(
                "/characters/\(account.characterID)/assets/", token: token
            ) {
                var seen = Set<Int>()
                let assets = rawAssets.filter { seen.insert($0.itemId).inserted }
                let tids = Array(Set(assets.map(\.typeId)))
                let types = await UniverseCache.shared.types(ids: tids)
                let assetGroupIds = Set(types.values.map(\.groupId))
                let assetGroups = await UniverseCache.shared.groups(ids: assetGroupIds)
                let shipGroupIds = Set(assetGroups.values.filter { $0.categoryId == 6 }.map(\.groupId))
                let shipTids = Set(types.filter { shipGroupIds.contains($0.value.groupId) }.keys)
                let byLoc = Dictionary(grouping: assets, by: \.locationId)
                let shipAssets = assets.filter { shipTids.contains($0.typeId) && $0.isSingleton }

                // Fetch custom names (pilot-assigned ship nicknames)
                let shipItemIds = shipAssets.map(\.itemId)
                var customNames: [Int: String] = [:]
                if !shipItemIds.isEmpty,
                   let nameResults: [ESIAssetName] = try? await ESIClient.shared.post(
                       "/characters/\(account.characterID)/assets/names/",
                       body: shipItemIds, token: token
                   ) {
                    for entry in nameResults where entry.name != "None" {
                        customNames[entry.itemId] = entry.name
                    }
                }

                // Resolve location names concurrently
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

                for a in shipAssets {
                    let gid = types[a.typeId]?.groupId ?? 0
                    loadedShips.append(ShipEntry(
                        characterID: account.characterID,
                        characterName: account.characterName,
                        itemId: a.itemId,
                        typeId: a.typeId,
                        typeName: types[a.typeId]?.name ?? "Unknown",
                        customName: customNames[a.itemId],
                        locationName: locationNames[a.locationId] ?? "#\(a.locationId)",
                        isSingleton: true,
                        shipClassName: assetGroups[gid]?.name ?? "Unknown"
                    ))
                    let mods = (byLoc[a.itemId] ?? []).filter { f in
                        f.locationFlag.hasPrefix("HiSlot") || f.locationFlag.hasPrefix("MedSlot") ||
                        f.locationFlag.hasPrefix("LoSlot") || f.locationFlag.hasPrefix("RigSlot") ||
                        f.locationFlag.hasPrefix("SubSystem")
                    }
                    if !mods.isEmpty { loadedModules[a.itemId] = mods }
                }
            }
        }

        savedFittings = fittings.sorted { $0.name < $1.name }
        ships = loadedShips.sorted { $0.displayName < $1.displayName }
        shipModules = loadedModules
        isLoading = false
    }
}
