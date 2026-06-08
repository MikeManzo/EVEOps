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

struct CharacterMedalsView: View {
    @Environment(AccountManager.self) private var accountManager
    @State private var groups: [MedalGroup] = []
    @State private var isLoading = false
    @State private var error: String?

    var body: some View {
        LoadingStateView(isLoading: isLoading, error: error,
                         isEmpty: groups.isEmpty, emptyMessage: "No medals awarded") {
            List {
                ForEach(groups, id: \.characterID) { group in
                    Section(groups.count > 1 ? group.characterName : "") {
                        ForEach(group.medals) { medal in
                            MedalRow(medal: medal)
                        }
                    }
                }
            }
        }
        .safeAreaInset(edge: .top, spacing: 0) {
            HStack {
                Text("Medals")
                    .font(.largeTitle.bold())
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(.background)
        }
        .navigationTitle("")
        .task(id: accountManager.selectedCharacterID) { await load() }
    }

    private func load() async {
        isLoading = true
        error = nil
        var result: [MedalGroup] = []
        var lastError: Error?
        var missingScope = false

        for account in accountManager.accounts {
            guard account.scopes.contains("esi-characters.read_medals.v1") else {
                missingScope = true
                continue
            }
            do {
                let token = try await accountManager.validToken(for: account)
                let medals: [ESIMedal] = try await ESIClient.shared.fetch(
                    "/characters/\(account.characterID)/medals/", token: token
                )
                if !medals.isEmpty {
                    let sorted = medals.sorted { $0.date > $1.date }
                    result.append(MedalGroup(
                        characterID: account.characterID,
                        characterName: account.characterName,
                        medals: sorted
                    ))
                }
            } catch { lastError = error }
        }

        groups = result
        if result.isEmpty {
            if missingScope {
                self.error = "Missing scope: esi-characters.read_medals.v1\n\nRemove and re-add your account to grant this permission."
            } else if let e = lastError {
                self.error = e.localizedDescription
            }
        }
        isLoading = false
    }
}

// Mark:  Row

private struct MedalRow: View {
    let medal: ESIMedal
    @State private var corpName = ""
    @State private var issuerName = ""
    @State private var showDetail = false

    var body: some View {
        HStack(spacing: 12) {
            AsyncImage(url: EVEImageURL.corporationLogo(medal.corporationId, size: 64)) { image in
                image.resizable().scaledToFit()
            } placeholder: {
                RoundedRectangle(cornerRadius: 6).fill(.quaternary)
            }
            .frame(width: 40, height: 40)
            .clipShape(RoundedRectangle(cornerRadius: 6))

            VStack(alignment: .leading, spacing: 3) {
                Text(medal.title)
                    .font(.subheadline.bold())
                    .lineLimit(1)
                Text(corpName.isEmpty ? "Corp #\(medal.corporationId)" : corpName)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(medal.date, style: .date)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }

            Spacer()

            if medal.status == "public" {
                Image(systemName: "eye.fill")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            } else {
                Image(systemName: "eye.slash.fill")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        .onTapGesture { showDetail = true }
        .popover(isPresented: $showDetail) {
            medalDetail.frame(width: 320)
        }
        .task {
            async let corp = NameResolver.shared.resolve(id: medal.corporationId)
            async let issuer = NameResolver.shared.resolve(id: medal.issuerId)
            (corpName, issuerName) = await (corp, issuer)
        }
    }

    private var medalDetail: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                AsyncImage(url: EVEImageURL.corporationLogo(medal.corporationId, size: 64)) { image in
                    image.resizable().scaledToFit()
                } placeholder: {
                    RoundedRectangle(cornerRadius: 6).fill(.quaternary)
                }
                .frame(width: 64, height: 64)
                .clipShape(RoundedRectangle(cornerRadius: 6))

                VStack(alignment: .leading, spacing: 4) {
                    Text(medal.title).font(.headline)
                    Text(corpName.isEmpty ? "Corp #\(medal.corporationId)" : corpName)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }

            Divider()

            if !medal.description.isEmpty {
                Text(medal.description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 6) {
                GridRow {
                    Text("Awarded").font(.caption).foregroundStyle(.secondary)
                    Text(medal.date, style: .date).font(.caption.bold())
                }
                GridRow {
                    Text("Issued By").font(.caption).foregroundStyle(.secondary)
                    Text(issuerName.isEmpty ? "ID #\(medal.issuerId)" : issuerName)
                        .font(.caption.bold())
                }
                if !medal.reason.isEmpty {
                    GridRow {
                        Text("Reason").font(.caption).foregroundStyle(.secondary)
                        Text(medal.reason).font(.caption.bold())
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                GridRow {
                    Text("Visibility").font(.caption).foregroundStyle(.secondary)
                    Text(medal.status.capitalized).font(.caption.bold())
                }
            }
        }
        .padding()
    }
}

// Mark:  Models

private struct MedalGroup {
    let characterID: Int
    let characterName: String
    let medals: [ESIMedal]
}
