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

struct CharacterResearchAgentsView: View {
    @Environment(AccountManager.self) private var accountManager

    @State private var groups: [ResearchGroup] = []
    @State private var isLoading = false
    @State private var error: String?
    @State private var now = Date()

    var body: some View {
        LoadingStateView(isLoading: isLoading, error: error,
                         isEmpty: groups.isEmpty, emptyMessage: "No active research agents") {
            List {
                ForEach(groups, id: \.characterID) { group in
                    Section(groups.count > 1 ? group.characterName : "") {
                        ForEach(group.agents) { agent in
                            agentRow(agent)
                        }
                    }
                }
            }
        }
        .safeAreaInset(edge: .top, spacing: 0) {
            HStack {
                Text("Research Agents")
                    .font(.largeTitle.bold())
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(.background)
        }
        .navigationTitle("Research Agents")
        .task(id: accountManager.selectedCharacterID) { await load() }
        .task(id: "timer") {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(60))
                now = Date()
            }
        }
    }

    // MARK:  Row

    private func agentRow(_ agent: ResolvedResearchAgent) -> some View {
        let elapsed = now.timeIntervalSince(agent.startedAt)
        let accumulated = agent.remainderPoints + agent.pointsPerDay * elapsed / 86400

        return HStack(spacing: 12) {
            AsyncImage(url: EVEImageURL.characterPortrait(agent.agentId, size: 64)) { img in
                img.resizable()
            } placeholder: {
                Circle().fill(.quaternary)
            }
            .frame(width: 40, height: 40)
            .clipShape(Circle())

            VStack(alignment: .leading, spacing: 3) {
                Text(agent.agentName).font(.subheadline.bold())
                Text(agent.skillName).font(.caption).foregroundStyle(.secondary)
                Text("Started \(agent.startedAt, style: .date)")
                    .font(.caption2).foregroundStyle(.tertiary)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 3) {
                Text(String(format: "%.0f RP", accumulated))
                    .font(.subheadline.bold().monospacedDigit())
                    .foregroundStyle(.green)
                Text(String(format: "+%.1f/day", agent.pointsPerDay))
                    .font(.caption2.monospacedDigit()).foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }

    // MARK:  Load

    private func load() async {
        isLoading = true
        error = nil
        var loaded: [ResearchGroup] = []
        var lastError: Error?
        var missingScope = false

        for account in accountManager.accounts {
            guard account.scopes.contains("esi-characters.read_agents_research.v1") else {
                missingScope = true
                continue
            }
            do {
                let token = try await accountManager.validToken(for: account)
                let agents: [ESIResearchAgent] = try await ESIClient.shared.fetch(
                    "/characters/\(account.characterID)/agents_research/", token: token
                )
                guard !agents.isEmpty else { continue }

                // Resolve agent names (NPC characters) and skill type names in parallel
                async let agentNames = resolveNames(ids: agents.map(\.agentId))
                async let skillTypes = UniverseCache.shared.types(ids: agents.map(\.skillTypeId))
                let (nameMap, typeMap) = await (agentNames, skillTypes)

                let resolved = agents.map { agent in
                    ResolvedResearchAgent(
                        agentId: agent.agentId,
                        agentName: nameMap[agent.agentId] ?? "Agent #\(agent.agentId)",
                        skillName: typeMap[agent.skillTypeId]?.name ?? "Skill #\(agent.skillTypeId)",
                        pointsPerDay: agent.pointsPerDay,
                        remainderPoints: agent.remainderPoints,
                        startedAt: agent.startedAt
                    )
                }.sorted { $0.agentName < $1.agentName }

                loaded.append(ResearchGroup(
                    characterID: account.characterID,
                    characterName: account.characterName,
                    agents: resolved
                ))
            } catch {
                lastError = error
            }
        }

        groups = loaded
        if loaded.isEmpty {
            if missingScope {
                self.error = "Missing scope: esi-characters.read_agents_research.v1\n\nRemove and re-add your account to grant this permission."
            } else if let lastError {
                self.error = lastError.localizedDescription
            }
        }
        isLoading = false
    }

    private func resolveNames(ids: [Int]) async -> [Int: String] {
        await withTaskGroup(of: (Int, String).self) { group in
            for id in ids {
                group.addTask {
                    let name = await NameResolver.shared.resolve(id: id)
                    return (id, name)
                }
            }
            var result: [Int: String] = [:]
            for await (id, name) in group { result[id] = name }
            return result
        }
    }
}

// MARK:  Models

private struct ResolvedResearchAgent: Identifiable {
    let agentId: Int
    let agentName: String
    let skillName: String
    let pointsPerDay: Double
    let remainderPoints: Double
    let startedAt: Date
    var id: Int { agentId }
}

private struct ResearchGroup {
    let characterID: Int
    let characterName: String
    let agents: [ResolvedResearchAgent]
}
