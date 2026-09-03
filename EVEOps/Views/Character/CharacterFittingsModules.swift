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
                if #available(macOS 26.0, *), IntelligenceService.isSupported {
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
                CachedAsyncImage(url: EVEImageURL.typeIcon(module.typeId, size: 64)) { image in
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
        .overlay(alignment: .topTrailing) {
            SkillStatusDot(typeId: module.typeId, characterSkills: characterSkills)
                .padding(4)
        }
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

    @Environment(AccountManager.self) private var accountManager
    @Environment(DashboardPrefetcher.self) private var prefetcher
    @State private var esiType: ESIType?
    @State private var groupName: String?

    private var characterSkills: [Int: Int]? {
        guard let account = accountManager.selectedAccount else { return nil }
        return prefetcher.characterData[account.characterID]
            .map { Dictionary(uniqueKeysWithValues: $0.skills.skills.map { ($0.skillId, $0.activeSkillLevel) }) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 12) {
                CachedAsyncImage(url: EVEImageURL.typeIcon(typeId, size: 128)) { image in
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
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
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
                        Text(desc.strippingEVEMarkup)
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

        SkillRequirementsView(typeId: typeId, typeInfo: esiType, characterSkills: characterSkills)
            .padding(.horizontal, 16)
            .padding(.vertical, 8)

        Divider()

        HStack(spacing: 0) {
            Button {
                WindowService.shared.showGalaxySearch(typeId: typeId, typeName: name ?? "Type #\(typeId)")
            } label: {
                Label("Find in Galaxy", systemImage: "globe.europe.africa.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderless)
            .foregroundStyle(.blue)

            Divider().frame(height: 20)

            Button {
                WindowService.shared.showItemSkillTree(typeId: typeId, typeName: name ?? "Type #\(typeId)")
            } label: {
                Label("Skill Tree", systemImage: "network")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderless)
            .foregroundStyle(.blue)
        }
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
