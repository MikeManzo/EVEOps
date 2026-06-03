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

struct CorporationStructuresView: View {
    @Environment(AccountManager.self) private var accountManager
    @State private var structures: [ResolvedStructure] = []
    @State private var isLoading = true
    @State private var error: String?

    var body: some View {
        LoadingStateView(isLoading: isLoading, error: error, isEmpty: structures.isEmpty, emptyMessage: "No structures found or insufficient permissions") {
            List(structures, id: \.structureId) { structure in
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Image(systemName: "building.2.fill")
                            .foregroundStyle(stateColor(structure.state))
                        VStack(alignment: .leading, spacing: 2) {
                            Text(structure.name)
                                .font(.headline)
                            Text(structure.typeName)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        VStack(alignment: .trailing, spacing: 2) {
                            Text(structure.systemName)
                                .font(.subheadline)
                            stateLabel(structure.state)
                        }
                    }

                    HStack {
                        if let fuelExpires = structure.fuelExpires {
                            Label {
                                VStack(alignment: .leading) {
                                    Text("Fuel expires")
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                    Text(EVEFormatters.timeUntil(fuelExpires))
                                        .font(.caption.monospacedDigit())
                                        .foregroundStyle(fuelExpires.timeIntervalSinceNow < 86400 ? .red : .primary)
                                }
                            } icon: {
                                Image(systemName: "fuelpump.fill")
                                    .foregroundStyle(fuelExpires.timeIntervalSinceNow < 86400 ? .red : .orange)
                            }
                        }

                        Spacer()

                        if let timerEnd = structure.stateTimerEnd {
                            Label {
                                VStack(alignment: .leading) {
                                    Text("Timer")
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                    Text(EVEFormatters.timeUntil(timerEnd))
                                        .font(.caption.monospacedDigit())
                                        .foregroundStyle(.red)
                                }
                            } icon: {
                                Image(systemName: "clock.badge.exclamationmark.fill")
                                    .foregroundStyle(.red)
                            }
                        }
                    }

                    if !structure.services.isEmpty {
                        HStack(spacing: 8) {
                            ForEach(structure.services, id: \.name) { service in
                                HStack(spacing: 4) {
                                    Circle()
                                        .fill(service.state == "online" ? .green : .red)
                                        .frame(width: 6, height: 6)
                                    Text(service.name)
                                        .font(.caption2)
                                }
                            }
                        }
                    }
                }
                .padding(.vertical, 4)
            }
        }
        .navigationTitle("Corp Structures")
        .task(id: accountManager.selectedCharacterID) {
            structures = []
            isLoading = true
            await loadStructures()
        }
    }

    private func stateColor(_ state: String) -> Color {
        switch state {
        case "shield_vulnerable", "online": return .green
        case "armor_reinforce", "hull_reinforce": return .red
        case "armor_vulnerable", "hull_vulnerable": return .orange
        case "anchoring", "unanchoring": return .yellow
        default: return .secondary
        }
    }

    private func stateLabel(_ state: String) -> some View {
        Text(state.replacingOccurrences(of: "_", with: " ").capitalized)
            .font(.caption)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(stateColor(state).opacity(0.2), in: Capsule())
            .foregroundStyle(stateColor(state))
    }

    private func loadStructures() async {
        guard let account = accountManager.selectedAccount else { return }
        isLoading = true
        do {
            let token = try await accountManager.validToken(for: account)
            let rawStructures: [ESICorporationStructure] = try await ESIClient.shared.fetch(
                "/corporations/\(account.corporationID)/structures/", token: token
            )

            var resolved: [ResolvedStructure] = []
            for structure in rawStructures {
                let systemName = await NameResolver.shared.resolve(id: structure.systemId)
                var typeName = "Structure #\(structure.typeId)"
                if let typeInfo = await UniverseCache.shared.type(id: structure.typeId) {
                    typeName = typeInfo.name
                }

                resolved.append(ResolvedStructure(
                    structureId: structure.structureId,
                    name: structure.name,
                    typeName: typeName,
                    systemName: systemName,
                    state: structure.state,
                    fuelExpires: structure.fuelExpires,
                    stateTimerEnd: structure.stateTimerEnd,
                    services: structure.services ?? []
                ))
            }
            structures = resolved
        } catch {
            self.error = error.localizedDescription
        }
        isLoading = false
    }
}

struct ResolvedStructure {
    let structureId: Int
    let name: String
    let typeName: String
    let systemName: String
    let state: String
    let fuelExpires: Date?
    let stateTimerEnd: Date?
    let services: [ESIStructureService]
}
