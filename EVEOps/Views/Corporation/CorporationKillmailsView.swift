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

struct CorporationKillmailsView: View {
    @Environment(AccountManager.self) private var accountManager
    @State private var killmails: [KillmailEntry] = []
    @State private var isLoading = false
    @State private var error: String?
    @State private var selectedEntry: KillmailEntry?
    @State private var filter = "all"

    var body: some View {
        LoadingStateView(isLoading: isLoading, error: error, isEmpty: killmails.isEmpty, emptyMessage: "No killmails found or insufficient roles") {
            VStack(spacing: 0) {
                filterBar
                List {
                    let filtered = filter == "all" ? killmails
                        : killmails.filter { filter == "kills" ? $0.isKill : !$0.isKill }
                    ForEach(filtered) { entry in
                        KillmailRow(entry: entry)
                            .contentShape(Rectangle())
                            .onTapGesture { selectedEntry = entry }
                    }
                }
            }
        }
        .safeAreaInset(edge: .top, spacing: 0) {
            HStack {
                Text("Corp Kill/Loss Mails")
                    .font(.largeTitle.bold())
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(.background)
        }
        .navigationTitle("Corp Kill/Loss Mails")
        .sheet(item: $selectedEntry) { entry in
            KillmailDetailSheet(entry: entry)
        }
        .task(id: accountManager.selectedCharacterID) {
            guard let account = accountManager.selectedAccount else { return }
            isLoading = true
            error = nil
            do {
                let token = try await accountManager.validToken(for: account)
                let refs: [ESIKillmailRef] = try await ESIClient.shared.fetchPages(
                    "/corporations/\(account.corporationID)/killmails/recent/", token: token
                )
                var entries: [KillmailEntry] = []
                await withTaskGroup(of: KillmailEntry?.self) { group in
                    for ref in refs {
                        group.addTask {
                            guard let km: ESIKillmail = try? await ESIClient.shared.fetch(
                                "/killmails/\(ref.killmailId)/\(ref.killmailHash)/"
                            ) else { return nil }
                            // Kill = victim is NOT from our corp; Loss = victim IS from our corp
                            let isKill = km.victim.corporationId != account.corporationID
                            return KillmailEntry(killmail: km, isKill: isKill)
                        }
                    }
                    for await entry in group { if let e = entry { entries.append(e) } }
                }
                killmails = entries.sorted { $0.killmail.killmailTime > $1.killmail.killmailTime }
            } catch {
                self.error = error.localizedDescription
            }
            isLoading = false
        }
    }

    private var filterBar: some View {
        HStack(spacing: 12) {
            Picker("Type", selection: $filter) {
                Text("All").tag("all")
                Text("Kills").tag("kills")
                Text("Losses").tag("losses")
            }
            .pickerStyle(.segmented)
            .frame(maxWidth: 300)
            Spacer()
            Label("\(killmails.filter(\.isKill).count) kills", systemImage: "flame.fill")
                .foregroundStyle(.green).font(.caption)
            Label("\(killmails.filter { !$0.isKill }.count) losses", systemImage: "xmark.circle.fill")
                .foregroundStyle(.red).font(.caption)
        }
        .padding(10)
        .background(.bar)
    }
}
