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
    @AppStorage("aiInsightsEnabled") private var aiInsightsEnabled = false
    @AppStorage("aiInsightClones") private var aiInsightClones = true

    var body: some View {
        LoadingStateView(isLoading: isLoading, error: error, isEmpty: clonesResponse == nil) {
            HStack(spacing: 0) {
                List(selection: $selectedImplant) {
                    jumpCooldownSection
                    if #available(macOS 26.0, *), aiInsightsEnabled, aiInsightClones, !activeImplants.isEmpty {
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

                if let implant = selectedImplant {
                    Divider()
                    ImplantDetailView(implant: implant)
                        .frame(width: 320)
                }
            }
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
            ForEach(jumpClones, id: \.jumpCloneId) { clone in
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Image(systemName: "person.2.fill")
                            .foregroundStyle(.teal)
                        Text(clone.name ?? "Unnamed Clone")
                            .font(.body)
                    }
                    Text(clone.locationName)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.leading, 28)
                    if !clone.implantNames.isEmpty {
                        Text("Implants: \(clone.implantNames.joined(separator: ", "))")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                            .padding(.leading, 28)
                            .lineLimit(2)
                    }
                }
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
                let implantNames = jc.implants.prefix(10).map { impID in
                    resolvedTypes[impID]?.name ?? "Implant #\(impID)"
                }
                resolvedClones.append(ResolvedJumpClone(
                    jumpCloneId: jc.jumpCloneId,
                    name: jc.name,
                    locationId: jc.locationId,
                    locationName: locName,
                    implantNames: implantNames
                ))
            }
            jumpClones = resolvedClones
        } catch {
            self.error = error.localizedDescription
        }
        isLoading = false
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
    let implantNames: [String]
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
