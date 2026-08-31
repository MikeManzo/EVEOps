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

struct CharacterClonesView: View {
    @Environment(AccountManager.self) private var accountManager
    @Environment(DashboardPrefetcher.self) private var prefetcher
    @State private var clonesResponse: ESIClonesResponse?
    @State private var activeImplants: [ResolvedImplant] = []
    @State private var jumpClones: [ResolvedJumpClone] = []
    @State private var isLoading = true
    @State private var error: String?
    @State private var selectedImplant: ResolvedImplant?
    /// Implant shown in the detail pane when picked from a jump clone's icon strip
    /// (those rows aren't in the `List` selection model). Takes precedence when set.
    @State private var stripImplant: ResolvedImplant?
    @AppStorage("aiInsightsEnabled") private var aiInsightsEnabled = false
    @AppStorage("aiInsightClones") private var aiInsightClones = true

    var body: some View {
        LoadingStateView(isLoading: isLoading, error: error, isEmpty: clonesResponse == nil) {
            HStack(spacing: 0) {
                List(selection: $selectedImplant) {
                    jumpCooldownSection
                    if #available(macOS 26.0, *), IntelligenceService.isSupported, aiInsightsEnabled, aiInsightClones, !activeImplants.isEmpty {
                        Section {
                            CloneAIInsightCard(
                                characterName: accountManager.selectedAccount?.characterName ?? "",
                                activeImplantNames: activeImplants.map(\.name),
                                jumpCloneImplantNames: jumpClones.map(\.implantNames),
                                totalSP: prefetchedSP,
                                topSkillAreas: prefetchedTopSkillAreas
                            )
                            .listRowBackground(Color.clear)
                            .listRowInsets(EdgeInsets(top: 8, leading: 8, bottom: 8, trailing: 8))
                            .selectionDisabled()
                        }
                    }
                    activeImplantsSection
                    jumpClonesSection
                }
                .frame(maxWidth: .infinity)

                if let implant = stripImplant ?? selectedImplant {
                    Divider()
                    ImplantDetailView(implant: implant)
                        .frame(width: 320)
                }
            }
        }
        .onChange(of: selectedImplant) { _, newValue in
            // A row click in the List takes over the detail pane from the strip.
            if newValue != nil { stripImplant = nil }
        }
        .safeAreaInset(edge: .top, spacing: 0) {
            HStack {
                Text("Clones")
                    .font(.largeTitle.bold())
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(.background)
        }
        .navigationTitle("")
        .task(id: accountManager.selectedCharacterID) {
            clonesResponse = nil
            activeImplants = []
            jumpClones = []
            selectedImplant = nil
            stripImplant = nil
            isLoading = true
            await loadClones()
        }
    }

    // MARK:  Sections

    private var jumpCooldownSection: some View {
        Section("Jump Clone Cooldown") {
            HStack {
                Image(systemName: "clock.fill")
                    .foregroundStyle(.blue)
                Text("Clone Jump Timer")
                Spacer()
                if let lastJump = clonesResponse?.lastCloneJumpDate {
                    let cooldownEnd = lastJump.addingTimeInterval(36000)
                    if cooldownEnd > Date() {
                        Text(EVEFormatters.timeUntil(cooldownEnd))
                            .foregroundStyle(.orange)
                            .monospacedDigit()
                    } else {
                        Text("Ready")
                            .foregroundStyle(.green)
                    }
                } else {
                    Text("Ready")
                        .foregroundStyle(.green)
                }
            }
        }
    }

    private var activeImplantsSection: some View {
        Section("Active Implants") {
            if activeImplants.isEmpty {
                Text("No implants installed")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(activeImplants) { implant in
                    HStack {
                        AsyncImage(url: EVEImageURL.typeIcon(implant.typeId, size: 64)) { phase in
                            if let image = phase.image {
                                image.resizable()
                                    .frame(width: 28, height: 28)
                                    .clipShape(RoundedRectangle(cornerRadius: 4))
                            } else {
                                Image(systemName: "brain.head.profile")
                                    .foregroundStyle(.purple)
                                    .frame(width: 28, height: 28)
                            }
                        }
                        Text(implant.name)
                    }
                    .tag(implant)
                }
            }
        }
    }

    private var jumpClonesSection: some View {
        Section("Jump Clones (\(jumpClones.count))") {
            if jumpClones.isEmpty {
                Text("No jump clones")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(jumpClones, id: \.jumpCloneId) { clone in
                    jumpCloneRow(clone)
                }
            }
        }
    }

    private func jumpCloneRow(_ clone: ResolvedJumpClone) -> some View {
        HStack(alignment: .top, spacing: 10) {
            cloneLocationThumbnail(typeId: clone.locationTypeId)

            VStack(alignment: .leading, spacing: 3) {
                Text(clone.name ?? "Unnamed Clone")
                    .font(.body.weight(.medium))
                Text(clone.locationName)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                if clone.implants.isEmpty {
                    Text("No implants")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                } else {
                    implantStrip(clone.implants)
                        .padding(.top, 1)
                }
            }
        }
        .padding(.vertical, 2)
    }

    /// Hi-res render of the station/structure the clone is parked in.
    private func cloneLocationThumbnail(typeId: Int?) -> some View {
        AsyncImage(url: typeId.flatMap { EVEImageURL.typeRender($0, size: 256) }) { phase in
            if let image = phase.image {
                image.resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fill)
            } else if typeId != nil, phase.error == nil {
                ProgressView().controlSize(.small)
            } else {
                Image(systemName: "building.2.fill")
                    .font(.system(size: 16))
                    .foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(width: 44, height: 44)
        .background(Color(white: 0.12))
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(.separator, lineWidth: 0.5))
    }

    /// Row of implant icons for a jump clone; each opens the implant detail pane.
    private func implantStrip(_ implants: [ResolvedImplant]) -> some View {
        let shown = implants.prefix(8)
        let overflow = implants.count - shown.count
        return HStack(spacing: 3) {
            ForEach(Array(shown)) { implant in
                Button {
                    stripImplant = implant
                } label: {
                    AsyncImage(url: EVEImageURL.typeIcon(implant.typeId, size: 64)) { phase in
                        if let image = phase.image {
                            image.resizable().interpolation(.high)
                        } else {
                            Image(systemName: "brain.head.profile")
                                .font(.system(size: 9))
                                .foregroundStyle(.purple)
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                        }
                    }
                    .frame(width: 20, height: 20)
                    .background(Color(white: 0.12))
                    .clipShape(RoundedRectangle(cornerRadius: 3))
                }
                .buttonStyle(.plain)
                .help(implant.name)
            }
            if overflow > 0 {
                Text("+\(overflow)")
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .padding(.leading, 1)
            }
        }
    }

    // MARK:  Prefetcher Helpers

    private var prefetchedSP: Int {
        guard let account = accountManager.selectedAccount,
              let data = prefetcher.data(for: account.characterID) else { return 0 }
        return data.skills.totalSp
    }

    private var prefetchedTopSkillAreas: [(name: String, spFormatted: String)] {
        guard let account = accountManager.selectedAccount,
              let data = prefetcher.data(for: account.characterID) else { return [] }
        var groupSP: [Int: Int] = [:]
        for skill in data.skills.skills {
            let gid = prefetcher.resolvedTypes[skill.skillId]?.groupId ?? 0
            groupSP[gid, default: 0] += skill.skillpointsInSkill
        }
        return groupSP
            .sorted { $0.value > $1.value }
            .prefix(5)
            .compactMap { gid, sp in
                guard let name = prefetcher.resolvedGroups[gid]?.name else { return nil }
                let formatted: String
                if sp >= 1_000_000 { formatted = String(format: "%.1fM SP", Double(sp) / 1_000_000) }
                else if sp >= 1_000 { formatted = String(format: "%.0fK SP", Double(sp) / 1_000) }
                else { formatted = "\(sp) SP" }
                return (name: name, spFormatted: formatted)
            }
    }

    // MARK:  Data Loading

    private func loadClones() async {
        guard let account = accountManager.selectedAccount else { return }
        isLoading = true
        do {
            let token = try await accountManager.validToken(for: account)
            let clones: ESIClonesResponse = try await ESIClient.shared.fetch(
                "/characters/\(account.characterID)/clones/", token: token
            )
            clonesResponse = clones

            let implantIDs: [Int] = try await ESIClient.shared.fetch(
                "/characters/\(account.characterID)/implants/", token: token
            )
            // Batch-resolve all implant type names via UniverseCache
            let allImplantIDs = implantIDs + clones.jumpClones.flatMap(\.implants)
            let resolvedTypes = await UniverseCache.shared.types(ids: allImplantIDs)

            var resolved: [ResolvedImplant] = []
            for implantID in implantIDs {
                let name = resolvedTypes[implantID]?.name ?? "Implant #\(implantID)"
                resolved.append(ResolvedImplant(typeId: implantID, name: name))
            }
            activeImplants = resolved
            if selectedImplant == nil { selectedImplant = resolved.first }

            var resolvedClones: [ResolvedJumpClone] = []
            for jc in clones.jumpClones {
                let locName = await NameResolver.shared.resolve(id: jc.locationId)
                let locTypeId = await cloneLocationTypeId(
                    locationId: jc.locationId, locationType: jc.locationType, token: token
                )
                let implants = jc.implants.map { impID in
                    ResolvedImplant(typeId: impID, name: resolvedTypes[impID]?.name ?? "Implant #\(impID)")
                }
                resolvedClones.append(ResolvedJumpClone(
                    jumpCloneId: jc.jumpCloneId,
                    name: jc.name,
                    locationId: jc.locationId,
                    locationName: locName,
                    locationTypeId: locTypeId,
                    implants: implants
                ))
            }
            jumpClones = resolvedClones
        } catch {
            self.error = error.localizedDescription
        }
        isLoading = false
    }

    /// Resolves a jump clone's parked location to its station/structure type ID so the
    /// row can show a hi-res `typeRender`. Returns `nil` for structures we can't read.
    private func cloneLocationTypeId(locationId: Int, locationType: String, token: String) async -> Int? {
        switch locationType {
        case "station":
            return await UniverseCache.shared.station(id: locationId)?.typeId
        case "structure":
            let structure: ESIStructure? = try? await ESIClient.shared.fetch(
                "/universe/structures/\(locationId)/", token: token
            )
            return structure?.typeId
        default:
            return nil
        }
    }
}

// MARK:  Supporting Types

struct ResolvedImplant: Identifiable, Hashable {
    let typeId: Int
    let name: String

    var id: Int { typeId }
}

struct ResolvedJumpClone {
    let jumpCloneId: Int
    let name: String?
    let locationId: Int
    let locationName: String
    /// Station/structure type of the clone's parked location, for the header render.
    /// `nil` when unresolvable (e.g. a structure whose ACL denies docking access).
    let locationTypeId: Int?
    let implants: [ResolvedImplant]

    var implantNames: [String] { implants.map(\.name) }
}

// MARK:  Clone AI Insight Card

@available(macOS 26.0, *)
struct CloneAIInsightCard: View {
    let characterName: String
    let activeImplantNames: [String]
    let jumpCloneImplantNames: [[String]]
    let totalSP: Int
    let topSkillAreas: [(name: String, spFormatted: String)]

    @AppStorage("aiInsightsEnabled") private var aiInsightsEnabled = false
    @AppStorage("aiInsightClones") private var aiInsightClones = true
    @State private var insight: CloneInsight?
    @State private var isGenerating = false
    @State private var generationError: String?
    @State private var hasAutoGenerated = false

    private var model: SystemLanguageModel { .default }

    var body: some View {
        if aiInsightsEnabled && aiInsightClones, case .available = model.availability {
            VStack(alignment: .leading, spacing: 10) {
                headerRow

                if isGenerating {
                    HStack(spacing: 6) {
                        ProgressView().controlSize(.mini)
                        Text("Analyzing implants\u{2026}")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                } else if let ins = insight {
                    insightContent(ins)
                } else if let err = generationError {
                    Text(err)
                        .font(.caption2)
                        .foregroundStyle(.red.opacity(0.8))
                } else {
                    Button("Generate Insight") {
                        Task { await generate() }
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.mini)
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(.purple.opacity(0.25)))
            .task(id: activeImplantNames.joined()) {
                guard !hasAutoGenerated else { return }
                hasAutoGenerated = true
                await generate()
            }
        }
    }

    private var headerRow: some View {
        HStack {
            Label("AI Implant Insight", systemImage: "sparkles")
                .font(.caption.bold())
                .foregroundStyle(.purple)
            Spacer()
            if insight != nil, !isGenerating {
                Button {
                    Task { await generate() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("Regenerate insight")
            }
        }
    }

    @ViewBuilder
    private func insightContent(_ ins: CloneInsight) -> some View {
        // Set assessment
        Text(ins.setAssessment)
            .font(.caption)
            .fixedSize(horizontal: false, vertical: true)

        Divider()

        // Recommendation
        VStack(alignment: .leading, spacing: 4) {
            Label("Recommendation", systemImage: "arrow.up.circle.fill")
                .font(.caption2.bold())
                .foregroundStyle(.blue)
            Text(ins.recommendation)
                .font(.caption)
                .fixedSize(horizontal: false, vertical: true)
        }

        // Skills needed (only show when training is actually required)
        let skillsText = ins.skillsNeeded.trimmingCharacters(in: .whitespaces)
        if !skillsText.isEmpty, !skillsText.localizedCaseInsensitiveContains("none") {
            Divider()
            VStack(alignment: .leading, spacing: 4) {
                Label("Training Required", systemImage: "book.fill")
                    .font(.caption2.bold())
                    .foregroundStyle(.orange)
                Text(skillsText)
                    .font(.caption)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func generate() async {
        isGenerating = true
        generationError = nil
        defer { isGenerating = false }
        do {
            insight = try await IntelligenceService.shared.analyzeImplants(
                characterName: characterName,
                activeImplantNames: activeImplantNames,
                jumpCloneImplantNames: jumpCloneImplantNames,
                totalSP: totalSP,
                topSkillAreas: topSkillAreas
            )
        } catch {
            generationError = "Unable to generate insight. Try again later."
        }
    }
}
