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

struct CorporationWarsView: View {
    @Environment(AccountManager.self) private var accountManager

    @State private var wars: [ESIWar] = []
    @State private var names: [Int: String] = [:]
    @State private var isLoading = false
    @State private var error: String?

    private var activeWars: [ESIWar] { wars.filter(\.isActive) }
    private var historicalWars: [ESIWar] { wars.filter { !$0.isActive } }

    var body: some View {
        LoadingStateView(isLoading: isLoading, error: error,
                         isEmpty: wars.isEmpty, emptyMessage: "No wars found for this corporation") {
            List {
                if !activeWars.isEmpty {
                    Section("Active (\(activeWars.count))") {
                        ForEach(activeWars) { war in warRow(war) }
                    }
                }
                if !historicalWars.isEmpty {
                    Section("History (\(historicalWars.count))") {
                        ForEach(historicalWars) { war in warRow(war) }
                    }
                }
            }
        }
        .navigationTitle("Corp Wars")
        .task(id: accountManager.selectedCharacterID) { await load() }
    }

    // MARK:  Row

    private func warRow(_ war: ESIWar) -> some View {
        let account = accountManager.accounts.first
        let corpID = account?.corporationID ?? 0
        let allianceID = account?.allianceID

        let isAggressor = war.aggressor.corporationId == corpID
            || (allianceID != nil && war.aggressor.allianceId == allianceID)
        let opponent = isAggressor ? war.defender : war.aggressor
        let opponentID = opponent.corporationId ?? opponent.allianceId ?? 0
        let opponentName = names[opponentID] ?? "Entity #\(opponentID)"

        return HStack(spacing: 12) {
            Image(systemName: isAggressor ? "bolt.fill" : "shield.fill")
                .foregroundStyle(isAggressor ? .red : .blue)
                .frame(width: 20)

            VStack(alignment: .leading, spacing: 4) {
                Text(opponentName).font(.subheadline.bold())
                HStack(spacing: 6) {
                    statusBadge(isAggressor ? "Aggressor" : "Defender",
                                color: isAggressor ? .red : .blue)
                    if war.mutual { statusBadge("Mutual", color: .orange) }
                    if war.openForAllies { statusBadge("Open", color: .green) }
                    if !war.isActive {
                        statusBadge("Finished", color: .secondary)
                    }
                }
                Text("Declared \(war.declared, style: .date)")
                    .font(.caption2).foregroundStyle(.tertiary)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 4) {
                HStack(spacing: 4) {
                    Image(systemName: "flame.fill").foregroundStyle(.red).font(.caption2)
                    Text(EVEFormatters.formatISKShort(opponent.iskDestroyed))
                        .font(.caption.bold().monospacedDigit())
                }
                Text("\(opponent.shipsKilled) ships killed")
                    .font(.caption2).foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }

    private func statusBadge(_ text: String, color: Color) -> some View {
        Text(text)
            .font(.caption2)
            .padding(.horizontal, 6).padding(.vertical, 2)
            .background(color.opacity(0.15))
            .foregroundStyle(color)
            .clipShape(Capsule())
    }

    // MARK:  Load

    private func load() async {
        guard let account = accountManager.accounts.first else { return }
        isLoading = true
        error = nil

        do {
            let token = try await accountManager.validToken(for: account)
            let warIDs: [Int] = try await ESIClient.shared.fetch(
                "/corporations/\(account.corporationID)/wars/", token: token
            )
            guard !warIDs.isEmpty else {
                wars = []
                isLoading = false
                return
            }

            // Fetch individual war details in parallel (cap at 100 most recent)
            var fetched: [ESIWar] = []
            await withTaskGroup(of: ESIWar?.self) { group in
                for id in warIDs.prefix(100) {
                    group.addTask {
                        try? await ESIClient.shared.fetch("/wars/\(id)/")
                    }
                }
                for await war in group {
                    if let war { fetched.append(war) }
                }
            }
            wars = fetched.sorted { $0.declared > $1.declared }

            // Resolve all entity names
            var entityIDs: Set<Int> = []
            for war in fetched {
                if let id = war.aggressor.corporationId { entityIDs.insert(id) }
                if let id = war.aggressor.allianceId { entityIDs.insert(id) }
                if let id = war.defender.corporationId { entityIDs.insert(id) }
                if let id = war.defender.allianceId { entityIDs.insert(id) }
            }
            names = await withTaskGroup(of: (Int, String).self) { group in
                for id in entityIDs {
                    group.addTask {
                        let name = await NameResolver.shared.resolve(id: id)
                        return (id, name)
                    }
                }
                var result: [Int: String] = [:]
                for await (id, name) in group { result[id] = name }
                return result
            }
        } catch ESIError.serverError(let statusCode, _) where statusCode == 404 {
            wars = []
        } catch {
            self.error = error.localizedDescription
        }
        isLoading = false
    }
}
