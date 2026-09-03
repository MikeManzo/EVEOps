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
                        CachedAsyncImage(url: EVEImageURL.typeRender(ship.typeId, size: 128)) { image in
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
            let items = modules.map { ESIFittingItemSave(flag: ESIFittingItemSave.postFlag($0.locationFlag), quantity: $0.quantity, typeId: $0.typeId) }
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
            CachedAsyncImage(url: EVEImageURL.typeRender(fitting.shipTypeId, size: 256)) { image in
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

    @Environment(AccountManager.self) private var accountManager
    @Environment(DashboardPrefetcher.self) private var prefetcher
    @State private var showExporter = false
    @State private var showModelViewer = false
    @State private var showShopView = false

    private var characterSkills: [Int: Int]? {
        guard let account = accountManager.selectedAccount else { return nil }
        return prefetcher.characterData[account.characterID]
            .map { Dictionary(uniqueKeysWithValues: $0.skills.skills.map { ($0.skillId, $0.activeSkillLevel) }) }
    }

    private var shopInput: FittingShopInput {
        var qtys: [Int: Int] = [:]
        for item in fitting.items { qtys[item.typeId, default: 0] += item.quantity }
        let hull = FittingShopItem(typeId: fitting.shipTypeId, quantity: 1, name: fitting.shipTypeName)
        let modules = qtys.sorted { $0.key < $1.key }.map { typeId, qty in
            FittingShopItem(typeId: typeId, quantity: qty, name: typeNames[typeId] ?? "Type #\(typeId)")
        }
        return FittingShopInput(fittingName: fitting.name, shipTypeId: fitting.shipTypeId, items: [hull] + modules)
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
                    SkillRequirementsView(typeId: fitting.shipTypeId, typeInfo: nil, characterSkills: characterSkills)
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
                    Button { showExporter = true } label: {
                        Label("Export…", systemImage: "arrow.down.doc")
                            .font(.caption.bold())
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 8))
                            .foregroundStyle(.white)
                    }
                    .buttonStyle(.plain)
                    if !fitting.items.isEmpty {
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
                    CachedAsyncImage(url: EVEImageURL.typeRender(fitting.shipTypeId, size: 512)) { image in
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
        .sheet(isPresented: $showModelViewer) {
            ShipModelSheet(shipName: fitting.shipTypeName, shipClass: fitting.shipClassName)
        }
        .sheet(isPresented: $showShopView) {
            FittingShopView(input: shopInput)
                .environment(accountManager)
        }
        .fileExporter(
            isPresented: $showExporter,
            document: EFTFittingDocument(text: EFTSerializer.export(fitting: fitting, typeNames: typeNames)),
            contentType: .eveFitting,
            defaultFilename: "\(fitting.name).eft"
        ) { _ in }
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
                if #available(macOS 26.0, *), IntelligenceService.isSupported {
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
    @Environment(AccountManager.self) private var accountManager
    @Environment(DashboardPrefetcher.self) private var prefetcher

    private var characterSkills: [Int: Int]? {
        guard let account = accountManager.selectedAccount else { return nil }
        return prefetcher.characterData[account.characterID]
            .map { Dictionary(uniqueKeysWithValues: $0.skills.skills.map { ($0.skillId, $0.activeSkillLevel) }) }
    }

    var body: some View {
        Button { showPopover = true } label: {
            HStack(spacing: 8) {
                CachedAsyncImage(url: EVEImageURL.typeIcon(item.typeId, size: 64)) { image in
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
        .overlay(alignment: .topTrailing) {
            SkillStatusDot(typeId: item.typeId, characterSkills: characterSkills)
                .padding(4)
        }
        .popover(isPresented: $showPopover, arrowEdge: .trailing) {
            ModuleDetailPopover(typeId: item.typeId, name: name, quantity: item.quantity)
        }
    }
}
