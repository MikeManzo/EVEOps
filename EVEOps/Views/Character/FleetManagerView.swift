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

struct FleetManagerView: View {
    @Environment(AccountManager.self) private var accountManager
    @State private var fleetInfo: ESIFleetInfo?
    @State private var isLoading = true
    @State private var error: String?
    @State private var showingInvite = false
    @State private var inviteConfirmation: String?
    @State private var missingScope = false

    private static let requiredScope = "esi-fleets.read_fleet.v1"

    var body: some View {
        if missingScope {
            scopeMissingView
        } else {
        LoadingStateView(isLoading: isLoading, error: error, isEmpty: fleetInfo == nil, emptyMessage: "You are not currently in a fleet") {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    HStack {
                        Spacer()
                        Button { Task { await loadFleet() } } label: {
                            Label("Refresh", systemImage: "arrow.clockwise")
                        }
                        .buttonStyle(.borderless)
                    }
                    if let info = fleetInfo {
                        fleetStatusCard(info)
                        if canInvite(info) {
                            inviteCard(info)
                        }
                        if let confirmation = inviteConfirmation {
                            HStack(spacing: 8) {
                                Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                                Text(confirmation).font(.subheadline)
                            }
                            .padding()
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(.green.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
                        }
                    }
                }
                .padding()
            }
        }
        .safeAreaInset(edge: .top, spacing: 0) {
            HStack {
                Text("Fleet Manager")
                    .font(.largeTitle.bold())
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(.background)
        }
        .navigationTitle("Fleet Manager")
        .sheet(isPresented: $showingInvite) {
            InviteFleetMemberSheet { characterId, role in
                await sendInvite(characterId: characterId, role: role)
            }
        }
        .task(id: accountManager.selectedCharacterID) { await loadFleet() }
        } // end missingScope else
    }

    private var scopeMissingView: some View {
        VStack(spacing: 16) {
            Image(systemName: "lock.shield")
                .font(.system(size: 48))
                .foregroundStyle(.orange)
            Text("Fleet Access Required")
                .font(.title2.bold())
            Text("Fleet Manager requires the **esi-fleets.read_fleet.v1** scope.\n\nPlease remove and re-add your character to grant the updated permissions.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .frame(maxWidth: 420)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func canInvite(_ info: ESIFleetInfo) -> Bool {
        info.role == "fleet_commander" || info.role == "wing_commander" || info.role == "squad_commander"
    }

    private func fleetStatusCard(_ info: ESIFleetInfo) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Fleet Status").font(.headline)
            HStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 4) {
                    Label("In Fleet", systemImage: "dot.radiowaves.left.and.right")
                        .foregroundStyle(.green)
                        .font(.subheadline.bold())
                    Text("Fleet ID: \(info.fleetId)")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 6) {
                    Text(fleetRoleLabel(info.role))
                        .font(.subheadline)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(roleColor(info.role).opacity(0.15), in: Capsule())
                        .foregroundStyle(roleColor(info.role))
                    if info.wingId > 0 {
                        Text("Wing \(info.wingId)")
                            .font(.caption2).foregroundStyle(.secondary)
                    }
                    if info.squadId > 0 {
                        Text("Squad \(info.squadId)")
                            .font(.caption2).foregroundStyle(.secondary)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
    }

    private func inviteCard(_ info: ESIFleetInfo) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Invite Members").font(.headline)
                Spacer()
                Button("Invite Pilot") { showingInvite = true }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
            }
            Text("As \(fleetRoleLabel(info.role)), you can invite pilots and assign their fleet role.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
    }

    private func fleetRoleLabel(_ role: String) -> String {
        switch role {
        case "fleet_commander": return "Fleet Commander"
        case "wing_commander":  return "Wing Commander"
        case "squad_commander": return "Squad Commander"
        case "squad_member":    return "Squad Member"
        default: return role.replacingOccurrences(of: "_", with: " ").capitalized
        }
    }

    private func roleColor(_ role: String) -> Color {
        switch role {
        case "fleet_commander": return .orange
        case "wing_commander":  return .yellow
        case "squad_commander": return .blue
        default: return .secondary
        }
    }

    private func loadFleet() async {
        guard let account = accountManager.selectedAccount else {
            isLoading = false
            return
        }
        guard account.scopes.contains(Self.requiredScope) else {
            missingScope = true
            isLoading = false
            return
        }
        missingScope = false
        isLoading = true
        error = nil
        fleetInfo = nil
        do {
            let token = try await accountManager.validToken(for: account)
            fleetInfo = try await ESIClient.shared.fetch(
                "/characters/\(account.characterID)/fleet/", token: token
            )
        } catch ESIError.serverError(let code, _) where code == 404 {
            fleetInfo = nil
        } catch {
            self.error = error.localizedDescription
        }
        isLoading = false
    }

    private func sendInvite(characterId: Int, role: String) async {
        guard let account = accountManager.selectedAccount, let info = fleetInfo else { return }
        do {
            let token = try await accountManager.validToken(for: account)
            let invite = ESIFleetInvite(characterId: characterId, role: role)
            try await ESIClient.shared.postVoid(
                "/fleets/\(info.fleetId)/members/",
                body: invite,
                token: token
            )
            inviteConfirmation = "Invite sent successfully."
        } catch ESIError.forbidden {
            self.error = "Access denied. Ensure your character has fleet command and the esi-fleets.write_fleet.v1 scope."
        } catch {
            self.error = error.localizedDescription
        }
    }
}

// MARK:  Invite Sheet

struct InviteFleetMemberSheet: View {
    let onInvite: (Int, String) async -> Void
    @Environment(\.dismiss) private var dismiss

    @State private var nameInput = ""
    @State private var selectedRole = "squad_member"
    @State private var isSearching = false
    @State private var searchResult: InviteSearchResult?
    @State private var searchError: String?
    @State private var isInviting = false

    struct InviteSearchResult {
        let id: Int
        let name: String
    }

    private let roleOptions: [(String, String)] = [
        ("squad_member",    "Squad Member"),
        ("squad_commander", "Squad Commander"),
        ("wing_commander",  "Wing Commander"),
        ("fleet_commander", "Fleet Commander"),
    ]

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Invite to Fleet").font(.headline)
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.escape)
            }
            .padding()
            Divider()

            VStack(alignment: .leading, spacing: 20) {
                // Pilot search
                VStack(alignment: .leading, spacing: 8) {
                    Text("Pilot Name").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                    HStack {
                        TextField("Exact character name…", text: $nameInput)
                            .textFieldStyle(.roundedBorder)
                            .onSubmit { Task { await search() } }
                        Button("Search") { Task { await search() } }
                            .disabled(nameInput.trimmingCharacters(in: .whitespaces).isEmpty || isSearching)
                    }
                    if isSearching {
                        HStack(spacing: 6) {
                            ProgressView().controlSize(.small)
                            Text("Searching…").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    if let err = searchError {
                        Text(err).font(.caption).foregroundStyle(.red)
                    }
                    if let result = searchResult {
                        HStack(spacing: 10) {
                            AsyncImage(url: EVEImageURL.characterPortrait(result.id, size: 64)) { image in
                                image.resizable()
                            } placeholder: {
                                Circle().fill(.quaternary)
                            }
                            .frame(width: 32, height: 32)
                            .clipShape(Circle())
                            Text(result.name).font(.subheadline.bold())
                            Spacer()
                            Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                        }
                        .padding(10)
                        .background(.green.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
                    }
                }

                // Role picker
                VStack(alignment: .leading, spacing: 8) {
                    Text("Fleet Role").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                    Picker("Role", selection: $selectedRole) {
                        ForEach(roleOptions, id: \.0) { apiRole, label in
                            Text(label).tag(apiRole)
                        }
                    }
                    .pickerStyle(.segmented)
                }
            }
            .padding()

            Divider()

            HStack {
                Spacer()
                Button("Send Invite") {
                    Task { await sendInvite() }
                }
                .buttonStyle(.borderedProminent)
                .disabled(searchResult == nil || isInviting)
                .overlay(alignment: .leading) {
                    if isInviting { ProgressView().controlSize(.small).padding(.leading, 8) }
                }
            }
            .padding()
        }
        .frame(minWidth: 460, minHeight: 340)
    }

    private func search() async {
        let name = nameInput.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }
        isSearching = true
        searchError = nil
        searchResult = nil
        defer { isSearching = false }
        do {
            let result: ESIIDsResponse = try await ESIClient.shared.post("/universe/ids/", body: [name])
            if let match = result.characters?.first(where: { $0.name.lowercased() == name.lowercased() }) {
                searchResult = InviteSearchResult(id: match.id, name: match.name)
                nameInput = ""
            } else {
                searchError = "No character found for \"\(name)\". Check the spelling."
            }
        } catch {
            searchError = error.localizedDescription
        }
    }

    private func sendInvite() async {
        guard let result = searchResult else { return }
        isInviting = true
        await onInvite(result.id, selectedRole)
        isInviting = false
        dismiss()
    }
}
