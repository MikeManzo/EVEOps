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
    @State private var members: [ESIFleetMember] = []
    @State private var isLoadingMembers = false
    @State private var membersError: String?
    @State private var resolvedNames: [Int: String] = [:]

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
                        membersSection
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
        .navigationTitle("")
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

    @ViewBuilder
    private var membersSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Fleet Members").font(.headline)
                if !members.isEmpty {
                    Text("\(members.count)")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if isLoadingMembers {
                    ProgressView().controlSize(.small)
                }
            }
            if let membersError {
                Text(membersError)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else if !isLoadingMembers && members.isEmpty {
                Text("No member details available.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                VStack(spacing: 8) {
                    ForEach(members.sorted(by: { $0.wingId == $1.wingId ? $0.squadId < $1.squadId : $0.wingId < $1.wingId })) { member in
                        FleetMemberRow(
                            member: member,
                            characterName: resolvedNames[member.characterId] ?? "Character #\(member.characterId)",
                            shipName: resolvedNames[member.shipTypeId] ?? "Ship #\(member.shipTypeId)",
                            systemName: resolvedNames[member.solarSystemId] ?? "System #\(member.solarSystemId)",
                            stationName: member.stationId.flatMap { resolvedNames[$0] },
                            roleLabel: fleetRoleLabel(member.role),
                            roleColor: roleColor(member.role)
                        )
                    }
                }
            }
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
        members = []
        membersError = nil
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
        if let info = fleetInfo {
            await loadMembers(fleetId: info.fleetId)
        }
    }

    private func loadMembers(fleetId: Int) async {
        guard let account = accountManager.selectedAccount else { return }
        isLoadingMembers = true
        membersError = nil
        do {
            let token = try await accountManager.validToken(for: account)
            let fetched: [ESIFleetMember] = try await ESIClient.shared.fetch(
                "/fleets/\(fleetId)/members/", token: token
            )
            members = fetched
            let ids = Set(fetched.map(\.characterId) + fetched.map(\.shipTypeId) + fetched.map(\.solarSystemId))
            var names = await NameResolver.shared.resolve(ids: Array(ids))
            for stationId in Set(fetched.compactMap(\.stationId)) {
                names[stationId] = await NameResolver.shared.resolveLocation(id: stationId, token: token)
            }
            resolvedNames = names
        } catch ESIError.forbidden {
            members = []
            membersError = "Only fleet, wing, or squad commanders can view the full member roster."
        } catch {
            members = []
            membersError = error.localizedDescription
        }
        isLoadingMembers = false
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

// MARK:  Member Row

/// A standalone view (not a func-based row) so each row owns its own presentation
/// state. Sharing one `@State` popover trigger across every row in the ForEach meant
/// only one row's popover ever actually presented, always showing the last member's data.
struct FleetMemberRow: View {
    let member: ESIFleetMember
    let characterName: String
    let shipName: String
    let systemName: String
    let stationName: String?
    let roleLabel: String
    let roleColor: Color

    @State private var isShowingDetail = false

    var body: some View {
        HStack(spacing: 10) {
            Button {
                isShowingDetail = true
            } label: {
                CachedAsyncImage(url: EVEImageURL.characterPortrait(member.characterId, size: 64)) { image in
                    image.resizable()
                } placeholder: {
                    Circle().fill(.quaternary)
                }
                .frame(width: 32, height: 32)
                .clipShape(Circle())
            }
            .buttonStyle(.plain)
            .popover(isPresented: $isShowingDetail) {
                FleetMemberDetailPopover(
                    member: member,
                    shipName: shipName,
                    systemName: systemName,
                    stationName: stationName
                )
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(characterName)
                    .font(.subheadline.bold())
                    .lineLimit(1)
                Text(systemName)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            CachedAsyncImage(url: EVEImageURL.typeIcon(member.shipTypeId, size: 64)) { image in
                image.resizable()
            } placeholder: {
                Color.clear
            }
            .frame(width: 22, height: 22)
            .clipShape(RoundedRectangle(cornerRadius: 4))
            Text(shipName)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .frame(width: 100, alignment: .leading)

            Text(roleLabel)
                .font(.caption2)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(roleColor.opacity(0.15), in: Capsule())
                .foregroundStyle(roleColor)
                .frame(width: 110, alignment: .center)
        }
        .padding(.vertical, 2)
    }
}

// MARK:  Member Detail Popover

/// Mirrors the character detail shown in Contacts (portrait, security status,
/// birthday/race/bloodline, corp/alliance, bio, corp history), plus the member's
/// current fleet position (ship, system, wing/squad, role).
struct FleetMemberDetailPopover: View {
    let member: ESIFleetMember
    let shipName: String
    let systemName: String
    let stationName: String?

    @State private var charInfo: ESICharacterPublic?
    @State private var corpName: String?
    @State private var allianceName: String?
    @State private var history: [ResolvedCorpHistory] = []
    @State private var isLoading = true

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header
                fleetPositionCard
                if isLoading {
                    HStack {
                        Spacer()
                        ProgressView().controlSize(.small)
                        Spacer()
                    }
                    .padding(.vertical, 12)
                } else if let charInfo {
                    characterInfoCard(charInfo)
                    if !history.isEmpty {
                        historySection
                    }
                }
            }
            .padding(16)
        }
        .frame(width: 340)
        .frame(maxHeight: 560)
        .task(id: member.characterId) { await load() }
    }

    private var header: some View {
        HStack(spacing: 12) {
            CachedAsyncImage(url: EVEImageURL.characterPortrait(member.characterId, size: 256)) { image in
                image.resizable()
            } placeholder: {
                Circle().fill(.quaternary)
            }
            .frame(width: 64, height: 64)
            .clipShape(Circle())

            VStack(alignment: .leading, spacing: 4) {
                Text(charInfo?.name ?? "Character #\(member.characterId)")
                    .font(.headline)
                    .fixedSize(horizontal: false, vertical: true)
                Text(Self.fleetRoleLabel(member.role))
                    .font(.caption)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Self.roleColor(member.role).opacity(0.15), in: Capsule())
                    .foregroundStyle(Self.roleColor(member.role))
                if let sec = charInfo?.securityStatus {
                    Label(String(format: "%.2f", sec), systemImage: "shield.fill")
                        .font(.caption)
                        .foregroundStyle(securityColor(sec))
                }
            }

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var fleetPositionCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Fleet Position")
                .font(.headline)
            detailRow(label: "Ship", value: shipName, icon: EVEImageURL.typeIcon(member.shipTypeId, size: 32))
            detailRow(label: "Solar System", value: systemName)
            if let stationName {
                detailRow(label: "Station", value: stationName)
            }
            detailRow(label: "Wing", value: member.wingId > 0 ? "\(member.wingId)" : "—")
            detailRow(label: "Squad", value: member.squadId > 0 ? "\(member.squadId)" : "—")
            detailRow(label: "Takes Fleet Warp", value: member.takesFleetWarp ? "Yes" : "No")
            detailRow(label: "Joined Fleet", value: member.joinTime.formatted(date: .abbreviated, time: .shortened))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
    }

    private func characterInfoCard(_ info: ESICharacterPublic) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Character Info")
                .font(.headline)

            detailRow(label: "Birthday", value: EVEFormatters.dateFormatter.string(from: info.birthday))
            detailRow(label: "Race", value: raceName(info.raceId))
            detailRow(label: "Bloodline", value: bloodlineName(info.bloodlineId))
            if let sec = info.securityStatus {
                detailRow(label: "Security Status", value: String(format: "%.4f", sec))
            }
            if let corpName {
                detailRow(label: "Corporation", value: corpName)
            }
            if let allianceName {
                detailRow(label: "Alliance", value: allianceName)
            }
            if let desc = info.description, !desc.isEmpty {
                Divider()
                Text("Bio")
                    .font(.headline)
                Text(desc.strippingEVEMarkup)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
    }

    private var historySection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Corporation History")
                .font(.headline)
            ForEach(history, id: \.recordId) { entry in
                HStack(spacing: 10) {
                    CachedAsyncImage(url: EVEImageURL.corporationLogo(entry.corporationId, size: 64)) { image in
                        image.resizable()
                    } placeholder: {
                        RoundedRectangle(cornerRadius: 4).fill(.quaternary)
                    }
                    .frame(width: 28, height: 28)
                    .clipShape(RoundedRectangle(cornerRadius: 4))

                    VStack(alignment: .leading, spacing: 2) {
                        Text(entry.corporationName)
                            .font(.subheadline)
                            .fixedSize(horizontal: false, vertical: true)
                        Text("Joined \(EVEFormatters.dateFormatter.string(from: entry.startDate))")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }

                    Spacer(minLength: 0)

                    if entry.isDeleted {
                        Text("Closed")
                            .font(.caption2)
                            .foregroundStyle(.red)
                    }
                }
                if entry.recordId != history.last?.recordId {
                    Divider()
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
    }

    private func detailRow(label: String, value: String, icon: URL? = nil) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label.uppercased())
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
            HStack(spacing: 6) {
                if let icon {
                    CachedAsyncImage(url: icon) { image in
                        image.resizable()
                    } placeholder: {
                        Color.clear
                    }
                    .frame(width: 18, height: 18)
                    .clipShape(RoundedRectangle(cornerRadius: 3))
                }
                Text(value)
                    .font(.subheadline)
                    .foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func load() async {
        isLoading = true
        charInfo = try? await ESIClient.shared.fetch("/characters/\(member.characterId)/")

        var corpHistory: [ESICorporationHistory] = []
        if let fetched: [ESICorporationHistory] = try? await ESIClient.shared.fetch("/characters/\(member.characterId)/corporationhistory/") {
            corpHistory = fetched
        }

        var idsToResolve: [Int] = []
        if let corpId = charInfo?.corporationId { idsToResolve.append(corpId) }
        if let allianceId = charInfo?.allianceId { idsToResolve.append(allianceId) }
        idsToResolve.append(contentsOf: corpHistory.map(\.corporationId))

        let resolved = await NameResolver.shared.resolve(ids: idsToResolve)
        if let corpId = charInfo?.corporationId { corpName = resolved[corpId] }
        if let allianceId = charInfo?.allianceId { allianceName = resolved[allianceId] }

        history = corpHistory
            .sorted { $0.startDate > $1.startDate }
            .map { entry in
                ResolvedCorpHistory(
                    recordId: entry.recordId,
                    corporationId: entry.corporationId,
                    corporationName: resolved[entry.corporationId] ?? "#\(entry.corporationId)",
                    startDate: entry.startDate,
                    isDeleted: entry.isDeleted ?? false
                )
            }
        isLoading = false
    }

    private func securityColor(_ sec: Double) -> Color {
        if sec >= 0.5 { return .green }
        if sec > 0.0 { return .yellow }
        return .red
    }

    private func raceName(_ id: Int) -> String {
        switch id {
        case 1: return "Caldari"
        case 2: return "Minmatar"
        case 4: return "Amarr"
        case 8: return "Gallente"
        default: return "Unknown"
        }
    }

    private func bloodlineName(_ id: Int) -> String {
        switch id {
        case 1: return "Deteis"
        case 2: return "Civire"
        case 3: return "Sebiestor"
        case 4: return "Brutor"
        case 5: return "Amarr"
        case 6: return "Ni-Kunni"
        case 7: return "Gallente"
        case 8: return "Intaki"
        case 9: return "Static"
        case 10: return "Modifier"
        case 11: return "Achura"
        case 12: return "Jin-Mei"
        case 13: return "Khanid"
        case 14: return "Vherokior"
        default: return "Unknown"
        }
    }

    fileprivate static func fleetRoleLabel(_ role: String) -> String {
        switch role {
        case "fleet_commander": return "Fleet Commander"
        case "wing_commander":  return "Wing Commander"
        case "squad_commander": return "Squad Commander"
        case "squad_member":    return "Squad Member"
        default: return role.replacingOccurrences(of: "_", with: " ").capitalized
        }
    }

    fileprivate static func roleColor(_ role: String) -> Color {
        switch role {
        case "fleet_commander": return .orange
        case "wing_commander":  return .yellow
        case "squad_commander": return .blue
        default: return .secondary
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
                            CachedAsyncImage(url: EVEImageURL.characterPortrait(result.id, size: 64)) { image in
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
