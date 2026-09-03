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

// MARK:  Ship List Row

struct ShipRow: View {
    let ship: ShipEntry
    var showCharacterName: Bool = false

    var body: some View {
        HStack(spacing: 12) {
            CachedAsyncImage(url: EVEImageURL.typeRender(ship.typeId, size: 256)) { image in
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
    @Environment(DashboardPrefetcher.self) private var prefetcher
    @State private var showSaveSheet = false
    @State private var showModelViewer = false
    @State private var showShopView = false

    private var characterSkills: [Int: Int]? {
        guard let account = accountManager.selectedAccount else { return nil }
        return prefetcher.characterData[account.characterID]
            .map { Dictionary(uniqueKeysWithValues: $0.skills.skills.map { ($0.skillId, $0.activeSkillLevel) }) }
    }

    private var shopInput: FittingShopInput {
        var qtys: [Int: Int] = [:]
        for module in modules { qtys[module.typeId, default: 0] += module.quantity }
        let hull = FittingShopItem(typeId: ship.typeId, quantity: 1, name: ship.typeName)
        let items = qtys.sorted { $0.key < $1.key }.map { typeId, qty in
            FittingShopItem(typeId: typeId, quantity: qty, name: typeNames[typeId] ?? "Type #\(typeId)")
        }
        return FittingShopInput(fittingName: ship.displayName, shipTypeId: ship.typeId, items: [hull] + items)
    }

    var body: some View {
        VStack(spacing: 0) {
            // Title/skills stack above its own button row (rather than sharing one
            // horizontal line via a Spacer) so neither gets squeezed for width — the
            // skill pills need real room to wrap onto their own line(s), not just show
            // their icon. The ship render and gradient are `.background`s of this
            // content rather than ZStack siblings with their own fixed height, so they
            // always exactly fill however tall the content needs to be (at least 190),
            // instead of a fixed-height image leaving a blank gap when text wraps.
            VStack(alignment: .leading, spacing: 8) {
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
                    SkillRequirementsView(typeId: ship.typeId, typeInfo: nil, characterSkills: characterSkills)
                }
                HStack(spacing: 8) {
                    Button { showModelViewer = true } label: {
                        Label("View 3D", systemImage: "cube.transparent")
                            .font(.caption.bold())
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 8))
                            .foregroundStyle(.white)
                    }
                    .buttonStyle(.plain)
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
                        Button { showShopView = true } label: {
                            Label("Shop Fit", systemImage: "cart.fill")
                                .font(.caption.bold())
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 8))
                                .foregroundStyle(.white)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, minHeight: 190, alignment: .bottomLeading)
            .background {
                LinearGradient(
                    stops: [
                        .init(color: .clear, location: 0.0),
                        .init(color: .black.opacity(0.75), location: 1.0)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            }
            .background {
                // GeometryReader pins the image to exactly this box's size before
                // clipping. `.aspectRatio(contentMode: .fill)` is free to compute a
                // size larger than what `.background` proposes — .clipped() alone only
                // clips drawing, not that oversized layout footprint — so without this
                // the image's box can bleed past its intended bounds.
                GeometryReader { geo in
                    CachedAsyncImage(url: EVEImageURL.typeRender(ship.typeId, size: 512)) { image in
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
                    .frame(width: geo.size.width, height: geo.size.height)
                    .clipped()
                }
            }

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
        .sheet(isPresented: $showModelViewer) {
            ShipModelSheet(shipName: ship.typeName, shipClass: ship.shipClassName)
        }
        .sheet(isPresented: $showSaveSheet) {
            SaveFittingSheet(ship: ship, modules: modules, onSaved: onFittingSaved)
                .environment(accountManager)
        }
        .sheet(isPresented: $showShopView) {
            FittingShopView(input: shopInput)
                .environment(accountManager)
        }
    }
}
