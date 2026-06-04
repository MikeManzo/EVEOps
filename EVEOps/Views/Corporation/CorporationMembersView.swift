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

struct CorporationMembersView: View {
    @Environment(AccountManager.self) private var accountManager
    @State private var members: [ResolvedMember] = []
    @State private var tracking: [Int: ESIMemberTracking] = [:]
    @State private var memberTitles: [Int: [String]] = [:]
    @State private var memberRoles: [Int: [String]] = [:]
    @State private var isLoading = true
    @State private var error: String?
    @State private var searchText = ""
    @State private var selectedMemberID: Int?
    @State private var selectedDetail: MemberDetail?
    @State private var isLoadingDetail = false
    @State private var sortOrder: MemberSortOrder = .name

    enum MemberSortOrder: String, CaseIterable {
        case name = "Name"
        case lastSeen = "Last Seen"
        case joinDate = "Join Date"
    }

    var body: some View {
        LoadingStateView(isLoading: isLoading, error: error, isEmpty: members.isEmpty, emptyMessage: "No member data or insufficient permissions") {
            HStack(spacing: 0) {
                memberList
                    .frame(minWidth: 280, maxWidth: 350)
                Divider()
                detailPane
                    .frame(maxWidth: .infinity)
            }
        }
        .safeAreaInset(edge: .top, spacing: 0) {
            HStack {
                Text("Corp Members")
                    .font(.largeTitle.bold())
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(.background)
        }
        .navigationTitle("")
        .task(id: accountManager.selectedCharacterID) {
            members = []
            selectedMemberID = nil
            selectedDetail = nil
            isLoading = true
            await loadMembers()
        }
    }

    // MARK:  Member List

    private var memberList: some View {
        VStack(spacing: 0) {
            // Search and count
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("Search members...", text: $searchText)
                    .textFieldStyle(.plain)
                Spacer()
                Text("\(members.count)")
                    .font(.caption.bold())
                    .foregroundStyle(.secondary)
            }
            .padding(10)
            .background(.bar)

            // Sort picker
            Picker("Sort", selection: $sortOrder) {
                ForEach(MemberSortOrder.allCases, id: \.self) { order in
                    Text(order.rawValue).tag(order)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)

            List(sortedFilteredMembers, id: \.characterId, selection: $selectedMemberID) { member in
                memberRow(member)
                    .tag(member.characterId)
            }
            .listStyle(.plain)
        }
        .onChange(of: selectedMemberID) { _, newID in
            if let id = newID {
                Task { await loadDetail(for: id) }
            }
        }
    }

    private func memberRow(_ member: ResolvedMember) -> some View {
        HStack(spacing: 10) {
            AsyncImage(url: EVEImageURL.characterPortrait(member.characterId, size: 128)) { image in
                image.resizable()
            } placeholder: {
                RoundedRectangle(cornerRadius: 6).fill(.quaternary)
            }
            .frame(width: 36, height: 36)
            .clipShape(RoundedRectangle(cornerRadius: 6))

            VStack(alignment: .leading, spacing: 2) {
                Text(member.name)
                    .font(.body)
                    .lineLimit(1)

                HStack(spacing: 6) {
                    // Online status from tracking
                    if let track = tracking[member.characterId] {
                        if let logon = track.logonDate, let logoff = track.logoffDate {
                            if logon > logoff {
                                Image(systemName: "circle.fill")
                                    .font(.system(size: 6))
                                    .foregroundStyle(.green)
                                Text("Online")
                                    .font(.caption2)
                                    .foregroundStyle(.green)
                            } else {
                                Text(relativeTime(logoff))
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }

                    if let titles = memberTitles[member.characterId], !titles.isEmpty {
                        Text(titles.first ?? "")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                            .lineLimit(1)
                    }
                }
            }

            Spacer()

            // Ship icon from tracking
            if let track = tracking[member.characterId], let shipType = track.shipTypeId {
                AsyncImage(url: EVEImageURL.typeIcon(shipType, size: 64)) { image in
                    image.resizable()
                } placeholder: {
                    Color.clear
                }
                .frame(width: 24, height: 24)
                .clipShape(RoundedRectangle(cornerRadius: 4))
            }
        }
        .padding(.vertical, 2)
    }

    // MARK:  Detail Pane

    @ViewBuilder
    private var detailPane: some View {
        if isLoadingDetail {
            VStack(spacing: 12) {
                ProgressView()
                Text("Loading member details...")
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let detail = selectedDetail {
            ScrollView {
                VStack(spacing: 20) {
                    memberHeader(detail)
                    memberInfoCards(detail)
                    rolesSection(detail)
                    if !detail.titles.isEmpty {
                        titlesSection(detail.titles)
                    }
                    if !detail.corporationHistory.isEmpty {
                        historySection(detail.corporationHistory)
                    }
                }
                .padding()
            }
        } else {
            VStack(spacing: 12) {
                Image(systemName: "person.crop.circle")
                    .font(.system(size: 48))
                    .foregroundStyle(.tertiary)
                Text("Select a member to view details")
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func memberHeader(_ detail: MemberDetail) -> some View {
        HStack(spacing: 16) {
            AsyncImage(url: EVEImageURL.characterPortrait(detail.characterId, size: 512)) { image in
                image.resizable()
            } placeholder: {
                RoundedRectangle(cornerRadius: 12).fill(.quaternary)
            }
            .frame(width: 96, height: 96)
            .clipShape(RoundedRectangle(cornerRadius: 12))

            VStack(alignment: .leading, spacing: 6) {
                Text(detail.name)
                    .font(.title2.bold())

                if let title = detail.charInfo?.title, !title.isEmpty {
                    Text(title)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                HStack(spacing: 12) {
                    if let info = detail.charInfo {
                        Label(info.gender.capitalized, systemImage: "person.fill")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        if let sec = info.securityStatus {
                            Label(String(format: "%.2f", sec), systemImage: "shield.fill")
                                .font(.caption)
                                .foregroundStyle(securityColor(sec))
                        }
                    }
                    if let track = detail.tracking {
                        if let logon = track.logonDate, let logoff = track.logoffDate, logon > logoff {
                            Label("Online", systemImage: "circle.fill")
                                .font(.caption)
                                .foregroundStyle(.green)
                        } else if let logoff = track.logoffDate {
                            Label("Last seen \(relativeTime(logoff))", systemImage: "clock")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }

            Spacer()

            // Ship render if available
            if let track = detail.tracking, let shipType = track.shipTypeId {
                VStack(spacing: 4) {
                    AsyncImage(url: EVEImageURL.typeRender(shipType, size: 256)) { phase in
                        if case .success(let image) = phase {
                            image.resizable().aspectRatio(contentMode: .fit)
                        } else {
                            AsyncImage(url: EVEImageURL.typeIcon(shipType, size: 64)) { image in
                                image.resizable()
                            } placeholder: {
                                Color.clear
                            }
                        }
                    }
                    .frame(width: 80, height: 80)

                    if let shipName = detail.shipTypeName {
                        Text(shipName)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .padding()
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
    }

    private func memberInfoCards(_ detail: MemberDetail) -> some View {
        HStack(spacing: 16) {
            // Character info
            VStack(alignment: .leading, spacing: 10) {
                Text("Character Info")
                    .font(.headline)

                if let info = detail.charInfo {
                    infoRow("Birthday", value: EVEFormatters.dateFormatter.string(from: info.birthday))
                    infoRow("Race", value: raceName(info.raceId))
                    infoRow("Bloodline", value: bloodlineName(info.bloodlineId))
                    if let sec = info.securityStatus {
                        infoRow("Security Status", value: String(format: "%.4f", sec))
                    }
                    if let desc = info.description, !desc.isEmpty {
                        Text("Bio")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(stripHTML(desc))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(4)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding()
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))

            // Tracking info
            VStack(alignment: .leading, spacing: 10) {
                Text("Activity")
                    .font(.headline)

                if let track = detail.tracking {
                    if let logon = track.logonDate {
                        infoRow("Last Login", value: EVEFormatters.dateFormatter.string(from: logon))
                    }
                    if let logoff = track.logoffDate {
                        infoRow("Last Logout", value: EVEFormatters.dateFormatter.string(from: logoff))
                    }
                    if let joinDate = track.startDate {
                        infoRow("Corp Join Date", value: EVEFormatters.dateFormatter.string(from: joinDate))
                    }
                    if let systemId = track.systemId {
                        infoRow("System", value: detail.systemName ?? "#\(systemId)")
                    }
                    if let locId = track.locationId {
                        infoRow("Location", value: detail.locationName ?? "#\(locId)")
                    }
                } else {
                    Text("No tracking data available")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding()
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
        }
    }

    private func rolesSection(_ detail: MemberDetail) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Roles").font(.headline)
            if detail.roles.isEmpty {
                Text("No roles assigned")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                FlowLayout(spacing: 6) {
                    ForEach(detail.roles, id: \.self) { role in
                        Text(formatRole(role))
                            .font(.caption)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(.blue.opacity(0.15), in: Capsule())
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
    }

    private func titlesSection(_ titles: [String]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Titles")
                .font(.headline)
            FlowLayout(spacing: 6) {
                ForEach(titles, id: \.self) { title in
                    Text(title)
                        .font(.caption)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(.purple.opacity(0.15), in: Capsule())
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
    }

    private func historySection(_ history: [ResolvedCorpHistory]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Corporation History")
                .font(.headline)
            ForEach(history, id: \.recordId) { entry in
                HStack(spacing: 10) {
                    AsyncImage(url: EVEImageURL.corporationLogo(entry.corporationId, size: 64)) { image in
                        image.resizable()
                    } placeholder: {
                        RoundedRectangle(cornerRadius: 4).fill(.quaternary)
                    }
                    .frame(width: 28, height: 28)
                    .clipShape(RoundedRectangle(cornerRadius: 4))

                    VStack(alignment: .leading, spacing: 2) {
                        Text(entry.corporationName)
                            .font(.subheadline)
                        Text("Joined \(EVEFormatters.dateFormatter.string(from: entry.startDate))")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

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

    // MARK:  Helpers

    private func infoRow(_ label: String, value: String) -> some View {
        HStack {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .font(.caption.monospacedDigit())
        }
    }

    private func formatRole(_ role: String) -> String {
        role.replacingOccurrences(of: "_", with: " ")
            .split(separator: " ")
            .map { $0.prefix(1).uppercased() + $0.dropFirst().lowercased() }
            .joined(separator: " ")
    }

    private func securityColor(_ sec: Double) -> Color {
        if sec >= 0.5 { return .green }
        if sec > 0.0 { return .yellow }
        return .red
    }

    private func relativeTime(_ date: Date) -> String {
        let interval = Date().timeIntervalSince(date)
        if interval < 60 { return "just now" }
        if interval < 3600 { return "\(Int(interval / 60))m ago" }
        if interval < 86400 { return "\(Int(interval / 3600))h ago" }
        return "\(Int(interval / 86400))d ago"
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

    private func stripHTML(_ html: String) -> String {
        html.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&#39;", with: "'")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var sortedFilteredMembers: [ResolvedMember] {
        let filtered: [ResolvedMember]
        if searchText.isEmpty {
            filtered = members
        } else {
            filtered = members.filter { $0.name.localizedCaseInsensitiveContains(searchText) }
        }

        switch sortOrder {
        case .name:
            return filtered.sorted { $0.name < $1.name }
        case .lastSeen:
            return filtered.sorted { a, b in
                let aDate = tracking[a.characterId]?.logoffDate ?? .distantPast
                let bDate = tracking[b.characterId]?.logoffDate ?? .distantPast
                return aDate > bDate
            }
        case .joinDate:
            return filtered.sorted { a, b in
                let aDate = tracking[a.characterId]?.startDate ?? .distantPast
                let bDate = tracking[b.characterId]?.startDate ?? .distantPast
                return aDate > bDate
            }
        }
    }

    // MARK:  Data Loading

    private func loadMembers() async {
        guard let account = accountManager.selectedAccount else { return }
        isLoading = true
        do {
            let token = try await accountManager.validToken(for: account)
            let corpID = account.corporationID

            let memberIDs: [Int] = try await ESIClient.shared.fetch(
                "/corporations/\(corpID)/members/", token: token
            )

            let names = await NameResolver.shared.resolve(ids: memberIDs)
            members = memberIDs.map { id in
                ResolvedMember(characterId: id, name: names[id] ?? "#\(id)")
            }.sorted { $0.name < $1.name }

            // Load tracking, titles, and roles in parallel
            do {
                let trackingData: [ESIMemberTracking] = try await ESIClient.shared.fetch(
                    "/corporations/\(corpID)/membertracking/", token: token
                )
                for entry in trackingData {
                    tracking[entry.characterId] = entry
                }
            } catch {}

            do {
                let titlesData: [ESIMemberTitle] = try await ESIClient.shared.fetch(
                    "/corporations/\(corpID)/members/titles/", token: token
                )
                for entry in titlesData {
                    memberTitles[entry.characterId] = entry.titles.compactMap(\.name)
                }
            } catch {}

            do {
                let rolesData: [ESIMemberRoles] = try await ESIClient.shared.fetch(
                    "/corporations/\(corpID)/roles/", token: token
                )
                for entry in rolesData {
                    memberRoles[entry.characterId] = entry.roles ?? []
                }
            } catch {}

        } catch {
            self.error = error.localizedDescription
        }
        isLoading = false
    }

    private func loadDetail(for characterId: Int) async {
        isLoadingDetail = true
        selectedDetail = nil

        let memberName = members.first { $0.characterId == characterId }?.name ?? "#\(characterId)"
        let track = tracking[characterId]
        let titles = memberTitles[characterId] ?? []
        let roles = memberRoles[characterId] ?? []

        // Fetch public character info and corp history
        var charInfo: ESICharacterPublic?
        var corpHistory: [ESICorporationHistory] = []

        do { charInfo = try await ESIClient.shared.fetch("/characters/\(characterId)/") } catch {}
        do { corpHistory = try await ESIClient.shared.fetch("/characters/\(characterId)/corporationhistory/") } catch {}

        // Resolve names for location, system, ship, and corp history
        var idsToResolve: [Int] = []
        if let sysId = track?.systemId { idsToResolve.append(sysId) }
        if let locId = track?.locationId { idsToResolve.append(locId) }
        if let shipType = track?.shipTypeId { idsToResolve.append(shipType) }
        idsToResolve.append(contentsOf: corpHistory.map(\.corporationId))

        let resolvedNames = await NameResolver.shared.resolve(ids: idsToResolve)

        let resolvedHistory = corpHistory
            .sorted { $0.startDate > $1.startDate }
            .map { entry in
                ResolvedCorpHistory(
                    recordId: entry.recordId,
                    corporationId: entry.corporationId,
                    corporationName: resolvedNames[entry.corporationId] ?? "#\(entry.corporationId)",
                    startDate: entry.startDate,
                    isDeleted: entry.isDeleted ?? false
                )
            }

        selectedDetail = MemberDetail(
            characterId: characterId,
            name: memberName,
            charInfo: charInfo,
            tracking: track,
            titles: titles,
            roles: roles,
            corporationHistory: resolvedHistory,
            systemName: track?.systemId.flatMap { resolvedNames[$0] },
            locationName: track?.locationId.flatMap { resolvedNames[$0] },
            shipTypeName: track?.shipTypeId.flatMap { resolvedNames[$0] }
        )

        isLoadingDetail = false
    }
}

// MARK:  Data Models

struct ResolvedMember {
    let characterId: Int
    let name: String
}

struct MemberDetail {
    let characterId: Int
    let name: String
    let charInfo: ESICharacterPublic?
    let tracking: ESIMemberTracking?
    let titles: [String]
    let roles: [String]
    let corporationHistory: [ResolvedCorpHistory]
    let systemName: String?
    let locationName: String?
    let shipTypeName: String?
}

struct ResolvedCorpHistory {
    let recordId: Int
    let corporationId: Int
    let corporationName: String
    let startDate: Date
    let isDeleted: Bool
}

// MARK:  Flow Layout

struct FlowLayout: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let result = layout(proposal: proposal, subviews: subviews)
        return result.size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = layout(proposal: proposal, subviews: subviews)
        for (index, position) in result.positions.enumerated() {
            subviews[index].place(at: CGPoint(x: bounds.minX + position.x, y: bounds.minY + position.y), proposal: .unspecified)
        }
    }

    private func layout(proposal: ProposedViewSize, subviews: Subviews) -> (size: CGSize, positions: [CGPoint]) {
        let maxWidth = proposal.width ?? .infinity
        var positions: [CGPoint] = []
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        var maxX: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > maxWidth && x > 0 {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            positions.append(CGPoint(x: x, y: y))
            rowHeight = max(rowHeight, size.height)
            x += size.width + spacing
            maxX = max(maxX, x)
        }

        return (CGSize(width: maxX, height: y + rowHeight), positions)
    }
}
