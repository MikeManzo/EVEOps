//
// This file is part of EVEOps.
//
// EVEOps is free software: you can redistribute it and/or modify
// it under the terms of the GNU General Public License as published by
// the Free Software Foundation, version 3 or later.
//
// Copyright (c) 2026 CitizenCoder
//

import OSLog
import SwiftUI

struct CorporationHangarsView: View {
    @Environment(AccountManager.self) private var accountManager
    @State private var allHangarAssets: [ResolvedAsset] = []
    @State private var divisions: [HangarDivision] = HangarDivision.defaults
    @State private var locations: [HangarLocation] = []
    @State private var isLoading = true
    @State private var error: String?
    @State private var selectedLocationID: Int?
    @State private var selectedFlag = "CorpSAG1"
    @State private var selectedAsset: ResolvedAsset?
    @State private var searchText = ""
    @State private var needsDivisionsScope = false
    @State private var needsUniverseStructuresScope = false

    private static let hangarFlags = [
        "CorpSAG1", "CorpSAG2", "CorpSAG3",
        "CorpSAG4", "CorpSAG5", "CorpSAG6", "CorpSAG7",
        "CorpDeliveries"
    ]

    var body: some View {
        LoadingStateView(
            isLoading: isLoading,
            error: error,
            isEmpty: allHangarAssets.isEmpty,
            emptyMessage: "No corporation hangar contents found or insufficient permissions"
        ) {
            VStack(spacing: 0) {
                hangarHeader
                locationBar
                divisionBar
                if needsDivisionsScope {
                    scopeWarningBanner
                }
                if needsUniverseStructuresScope {
                    structureScopeWarningBanner
                }
                HStack(spacing: 0) {
                    itemPanel
                    if let asset = selectedAsset {
                        Divider()
                        AssetDetailView(asset: asset)
                            .frame(width: 320)
                    }
                }
            }
        }
        .navigationTitle("Corp Hangars")
        .task { await loadHangars() }
    }

    // MARK:  Header

    private var hangarHeader: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("Corporation Hangars")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("\(visibleItems.count) items in \(divisionDisplayName(for: selectedFlag))")
                    .font(.title2.bold())
            }
            Spacer()
            Text("\(allHangarAssets.count) total")
                .font(.caption.monospacedDigit())
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(.quaternary, in: Capsule())
        }
        .padding()
        .background(.regularMaterial)
    }

    // MARK:  Scope warning banner

    private var scopeWarningBanner: some View {
        HStack(spacing: 8) {
            Image(systemName: "lock.shield")
                .foregroundStyle(.blue)
            VStack(alignment: .leading, spacing: 1) {
                Text("Custom hangar names unavailable")
                    .font(.caption.bold())
                Text("Re-authenticate to grant the \u{201C}esi-corporations.read_divisions.v1\u{201D} scope and see your corporation\u{2019}s custom division names.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button {
                needsDivisionsScope = false
            } label: {
                Image(systemName: "xmark")
                    .font(.caption2.bold())
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(.blue.opacity(0.08))
        .overlay(alignment: .bottom) { Divider() }
        .transition(.move(edge: .top).combined(with: .opacity))
    }

    // MARK:  Structure scope warning banner

    private var structureScopeWarningBanner: some View {
        HStack(spacing: 8) {
            Image(systemName: "building.2.crop.circle.badge.xmark")
                .foregroundStyle(.orange)
            VStack(alignment: .leading, spacing: 1) {
                Text("Structure names unavailable")
                    .font(.caption.bold())
                Text("Re-authenticate to grant the \u{201C}esi-universe.read_structures.v1\u{201D} scope. Your token was issued before this scope was required.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button {
                needsUniverseStructuresScope = false
            } label: {
                Image(systemName: "xmark")
                    .font(.caption2.bold())
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(.orange.opacity(0.08))
        .overlay(alignment: .bottom) { Divider() }
        .transition(.move(edge: .top).combined(with: .opacity))
    }

    // MARK:  Location bar

    private var locationBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                locationPill(id: nil, name: "All Locations")
                ForEach(locations) { loc in
                    locationPill(id: loc.id, name: loc.name)
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
        }
        .background(.bar)
        .overlay(alignment: .bottom) { Divider() }
    }

    private func locationPill(id: Int?, name: String) -> some View {
        let isSelected = selectedLocationID == id
        let count = allHangarAssets.filter { id == nil || $0.locationId == id }.count
        return Button {
            selectedLocationID = id
            selectedAsset = nil
        } label: {
            VStack(spacing: 2) {
                Text(name)
                    .font(.caption)
                    .lineLimit(1)
                Text("\(count) items")
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(isSelected ? Color.accentColor : .secondary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(
                isSelected ? Color.accentColor.opacity(0.2) : Color.clear,
                in: RoundedRectangle(cornerRadius: 8)
            )
        }
        .buttonStyle(.plain)
    }

    // MARK:  Division bar

    private var divisionBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(divisions) { div in
                    divisionPill(div)
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
        }
        .background(.regularMaterial)
        .overlay(alignment: .bottom) { Divider() }
    }

    private func divisionPill(_ div: HangarDivision) -> some View {
        let isSelected = selectedFlag == div.flag
        let base = selectedLocationID == nil
            ? allHangarAssets
            : allHangarAssets.filter { $0.locationId == selectedLocationID }
        let count = base.filter { $0.locationFlag == div.flag }.count
        return Button {
            selectedFlag = div.flag
            selectedAsset = nil
        } label: {
            VStack(spacing: 2) {
                Text(div.name)
                    .font(.caption)
                    .lineLimit(1)
                Text("\(count) items")
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(isSelected ? Color.accentColor : .secondary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(
                isSelected ? Color.accentColor.opacity(0.2) : Color.clear,
                in: RoundedRectangle(cornerRadius: 8)
            )
        }
        .buttonStyle(.plain)
    }

    // MARK:  Item panel

    private var itemPanel: some View {
        VStack(spacing: 0) {
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("Search \(divisionDisplayName(for: selectedFlag))...", text: $searchText)
                    .textFieldStyle(.plain)
            }
            .padding(10)
            .background(.bar)

            if visibleItems.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "archivebox")
                        .font(.largeTitle)
                        .foregroundStyle(.secondary)
                    Text(searchText.isEmpty ? "Hangar is empty" : "No matching items")
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(selection: $selectedAsset) {
                    ForEach(visibleItems) { asset in
                        HStack(spacing: 8) {
                            AsyncImage(url: EVEImageURL.typeIcon(asset.typeId, size: 256)) { phase in
                                if let image = phase.image {
                                    image.resizable()
                                        .frame(width: 28, height: 28)
                                        .clipShape(RoundedRectangle(cornerRadius: 4))
                                } else {
                                    Image(systemName: "shippingbox.fill")
                                        .foregroundStyle(.teal)
                                        .frame(width: 28, height: 28)
                                }
                            }
                            VStack(alignment: .leading, spacing: 2) {
                                HStack(spacing: 4) {
                                    Text(asset.typeName)
                                    if asset.isBlueprintCopy {
                                        Text("BPC")
                                            .font(.caption2)
                                            .padding(.horizontal, 4)
                                            .padding(.vertical, 1)
                                            .background(.orange.opacity(0.2), in: Capsule())
                                            .foregroundStyle(.orange)
                                    }
                                }
                                if locations.count > 1 || selectedLocationID == nil {
                                    Text(asset.locationName)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            Spacer()
                            Text("×\(asset.quantity)")
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(.secondary)
                        }
                        .tag(asset)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity)
    }

    // MARK:  Computed

    private var visibleItems: [ResolvedAsset] {
        var base = allHangarAssets.filter { $0.locationFlag == selectedFlag }
        if let locID = selectedLocationID {
            base = base.filter { $0.locationId == locID }
        }
        if !searchText.isEmpty {
            base = base.filter {
                $0.typeName.localizedCaseInsensitiveContains(searchText) ||
                $0.locationName.localizedCaseInsensitiveContains(searchText)
            }
        }
        return base
    }

    private func divisionDisplayName(for flag: String) -> String {
        divisions.first(where: { $0.flag == flag })?.name ?? flag
    }

    // MARK:  Data loading

    private func loadHangars() async {
        guard let account = accountManager.selectedAccount else { return }
        isLoading = true
        do {
            let token = try await accountManager.validToken(for: account)

            let rawAssets: [ESIAsset] = try await ESIClient.shared.fetchPages(
                "/corporations/\(account.corporationID)/assets/", token: token, bypassCache: true
            )

            let hangarRaw = rawAssets.filter { Self.hangarFlags.contains($0.locationFlag) }

            let typeIDs = Array(Set(hangarRaw.map(\.typeId)))
            let typeNames = await NameResolver.shared.resolve(ids: typeIDs)

            // Pre-seed structure names from the corp structures endpoint so player-owned
            // structures resolve without needing esi-universe.read_structures.v1.
            do {
                let corpStructures: [ESICorporationStructure] = try await ESIClient.shared.fetchPages(
                    "/corporations/\(account.corporationID)/structures/", token: token
                )
                let structureNames = Dictionary(
                    uniqueKeysWithValues: corpStructures.map { ($0.structureId, $0.name) }
                )
                await NameResolver.shared.seed(structureNames)
            } catch {
                Logger.network.warning("Corp structures pre-seed failed: \(error.localizedDescription)")
            }

            // Corp hangar items at NPC stations have locationType="item" because they sit
            // inside the corp's rented office (itself an "item" in the asset tree). The
            // office has locationType="station" pointing to the real station ID. Walk up
            // the parent chain using ALL raw assets to find the real station or structure.
            var itemParent: [Int: (locationId: Int, locationType: String)] = [:]
            for asset in rawAssets {
                itemParent[asset.itemId] = (locationId: asset.locationId, locationType: asset.locationType)
            }

            var effectiveLocIdMap: [Int: Int] = [:]
            for rawLocId in Set(hangarRaw.map(\.locationId)) {
                var current = rawLocId
                var resolved = false
                for _ in 0..<10 {
                    guard let parent = itemParent[current] else { break }
                    if parent.locationType == "station" || parent.locationType == "solar_system" {
                        effectiveLocIdMap[rawLocId] = parent.locationId
                        resolved = true
                        break
                    }
                    current = parent.locationId
                }
                if !resolved { effectiveLocIdMap[rawLocId] = rawLocId }
            }

            let effectiveLocIds = Set(effectiveLocIdMap.values)
            let hasPlayerStructures = effectiveLocIds.contains { $0 > 1_000_000_000 }
            needsUniverseStructuresScope = hasPlayerStructures &&
                !jwtContainsScope(token, "esi-universe.read_structures.v1")

            var locNames: [Int: String] = [:]
            for locID in effectiveLocIds {
                let resolved = await NameResolver.shared.resolveLocation(id: locID, token: token)
                if resolved.hasPrefix("#") {
                    locNames[locID] = locID > 1_000_000_000 ? "Unknown Structure" : "Unknown Location"
                } else {
                    locNames[locID] = resolved
                }
            }

            allHangarAssets = hangarRaw.map { asset in
                let effId = effectiveLocIdMap[asset.locationId] ?? asset.locationId
                return ResolvedAsset(
                    itemId: asset.itemId,
                    typeId: asset.typeId,
                    typeName: typeNames[asset.typeId] ?? "Unknown",
                    quantity: asset.quantity,
                    locationId: effId,
                    locationName: locNames[effId] ?? "Unknown Location",
                    locationFlag: asset.locationFlag,
                    isBlueprintCopy: asset.isBlueprintCopy ?? false,
                    isSingleton: asset.isSingleton
                )
            }.sorted { $0.typeName < $1.typeName }

            locations = Array(effectiveLocIds)
                .map { HangarLocation(id: $0, name: locNames[$0] ?? "Unknown Location") }
                .sorted { $0.name < $1.name }

            // Fetch custom division names — requires esi-corporations.read_divisions.v1.
            // A 403 means the scope was never granted; warn the user. Other errors are ignored silently.
            do {
                let divData: ESICorporationDivisions = try await ESIClient.shared.fetch(
                    "/corporations/\(account.corporationID)/divisions/", token: token
                )
                var updated = HangarDivision.defaults
                for entry in divData.hangar ?? [] {
                    guard let name = entry.name, !name.isEmpty,
                          entry.division >= 1, entry.division <= 7 else { continue }
                    let flag = "CorpSAG\(entry.division)"
                    if let idx = updated.firstIndex(where: { $0.flag == flag }) {
                        updated[idx].name = name
                    }
                }
                divisions = updated
                needsDivisionsScope = false
            } catch ESIError.forbidden, ESIError.unauthorized {
                needsDivisionsScope = true
            } catch {
                Logger.network.warning("Corp divisions fetch failed (using defaults): \(error.localizedDescription)")
            }

            // Auto-select the first division that actually contains items
            if let first = divisions.first(where: { div in
                allHangarAssets.contains { $0.locationFlag == div.flag }
            }) {
                selectedFlag = first.flag
            }

        } catch {
            self.error = error.localizedDescription
        }
        isLoading = false
    }

    // MARK:  JWT helpers

    private func jwtContainsScope(_ token: String, _ scope: String) -> Bool {
        let parts = token.components(separatedBy: ".")
        guard parts.count >= 2 else { return false }
        var base64 = parts[1]
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        let remainder = base64.count % 4
        if remainder != 0 { base64 += String(repeating: "=", count: 4 - remainder) }
        guard let data = Data(base64Encoded: base64),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return false }
        if let scopes = json["scp"] as? [String] { return scopes.contains(scope) }
        if let single = json["scp"] as? String { return single == scope }
        return false
    }
}

// MARK:  Supporting models

struct HangarLocation: Identifiable {
    let id: Int
    let name: String
}

struct HangarDivision: Identifiable {
    let division: Int
    let flag: String
    var name: String

    var id: String { flag }

    static let defaults: [HangarDivision] =
        (1...7).map { HangarDivision(division: $0, flag: "CorpSAG\($0)", name: "Division \($0)") }
        + [HangarDivision(division: 0, flag: "CorpDeliveries", name: "Deliveries")]
}
