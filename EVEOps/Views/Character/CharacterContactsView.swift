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

struct CharacterContactsView: View {
    @Environment(AccountManager.self) private var accountManager
    @Environment(PresenceTracker.self) private var presenceTracker
    @State private var contacts: [ESIContact] = []
    @State private var isLoading = false
    @State private var error: String?
    @State private var contactNames: [Int: String] = [:]
    @State private var searchFilter = ""
    @State private var showingAddContact = false
    @AppStorage("contacts.typeFilter") private var typeFilter = "all"
    @State private var contactToEdit: ESIContact?
    @State private var selectedContactID: Int?
    @State private var selectedDetail: ContactDetail?
    @State private var isLoadingDetail = false

    private var filteredContacts: [ESIContact] {
        var result = contacts
        switch typeFilter {
        case "player":      result = result.filter { $0.isPlayerCharacter }
        case "npc":         result = result.filter { $0.contactType == "character" && !$0.isPlayerCharacter }
        case "corporation": result = result.filter { $0.contactType == "corporation" }
        case "alliance":    result = result.filter { $0.contactType == "alliance" }
        default: break
        }
        if !searchFilter.isEmpty {
            result = result.filter {
                (contactNames[$0.contactId] ?? "").localizedCaseInsensitiveContains(searchFilter)
            }
        }
        return result.sorted { abs($0.standing) > abs($1.standing) }
    }

    private var groupedContacts: [(String, [ESIContact])] {
        if typeFilter != "all" {
            return filteredContacts.isEmpty ? [] : [(typeFilter, filteredContacts)]
        }
        let all = filteredContacts
        var groups: [(String, [ESIContact])] = []
        let players   = all.filter { $0.isPlayerCharacter }
        let npcs      = all.filter { $0.contactType == "character" && !$0.isPlayerCharacter }
        let corps     = all.filter { $0.contactType == "corporation" }
        let alliances = all.filter { $0.contactType == "alliance" }
        let factions  = all.filter { $0.contactType == "faction" }
        if !players.isEmpty   { groups.append(("player", players)) }
        if !npcs.isEmpty      { groups.append(("npc", npcs)) }
        if !corps.isEmpty     { groups.append(("corporation", corps)) }
        if !alliances.isEmpty { groups.append(("alliance", alliances)) }
        if !factions.isEmpty  { groups.append(("faction", factions)) }
        return groups
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Spacer()
                Button {
                    showingAddContact = true
                } label: {
                    Label("Add Contact", systemImage: "person.badge.plus")
                }
                .buttonStyle(.borderless)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(.bar)
            Divider()
            LoadingStateView(isLoading: isLoading, error: error, isEmpty: contacts.isEmpty, emptyMessage: "No contacts found") {
                HStack(spacing: 0) {
                    contactList
                        .frame(minWidth: 300, maxWidth: 400)
                    Divider()
                    detailPane
                        .frame(maxWidth: .infinity)
                }
            }
        }
        .safeAreaInset(edge: .top, spacing: 0) {
            HStack {
                Text("Contacts")
                    .font(.largeTitle.bold())
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(.background)
        }
        .navigationTitle("")
        .sheet(isPresented: $showingAddContact) {
            AddContactSheet { contactId, contactType, standing in
                await addContact(contactId: contactId, contactType: contactType, standing: standing)
            }
        }
        .sheet(item: $contactToEdit) { contact in
            EditStandingSheet(
                contactName: contactNames[contact.contactId] ?? "ID #\(contact.contactId)",
                currentStanding: contact.standing
            ) { newStanding in
                await updateStanding(contact: contact, standing: newStanding)
            }
        }
        .task(id: accountManager.selectedCharacterID) {
            selectedContactID = nil
            selectedDetail = nil
            await load()
        }
    }

    // MARK: Contact List

    private var contactList: some View {
        VStack(spacing: 0) {
            filterBar
            List(selection: $selectedContactID) {
                ForEach(groupedContacts, id: \.0) { type, group in
                    Section(typeLabel(type)) {
                        ForEach(group) { contact in
                            ContactRow(
                                contact: contact,
                                name: contactNames[contact.contactId],
                                presence: contact.isPlayerCharacter
                                    ? presenceTracker.score(for: contact.contactId)
                                    : nil
                            )
                            .tag(contact.contactId)
                            .swipeActions(edge: .leading) {
                                Button {
                                    contactToEdit = contact
                                } label: {
                                    Label("Edit Standing", systemImage: "pencil")
                                }
                                .tint(.blue)
                            }
                            .swipeActions(edge: .trailing) {
                                Button(role: .destructive) {
                                    Task { await deleteContact(contact) }
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                            }
                            .contextMenu {
                                Button {
                                    contactToEdit = contact
                                } label: {
                                    Label("Edit Standing", systemImage: "pencil")
                                }
                                Divider()
                                Button(role: .destructive) {
                                    Task { await deleteContact(contact) }
                                } label: {
                                    Label("Remove Contact", systemImage: "person.badge.minus")
                                }
                            }
                        }
                    }
                }
            }
            .onChange(of: selectedContactID) { _, newID in
                if let id = newID {
                    Task { await loadDetail(for: id) }
                } else {
                    selectedDetail = nil
                }
            }
        }
    }

    // MARK: Detail Pane

    @ViewBuilder
    private var detailPane: some View {
        if isLoadingDetail {
            VStack(spacing: 12) {
                ProgressView()
                Text("Loading contact details...")
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let detail = selectedDetail {
            ScrollView {
                VStack(spacing: 20) {
                    contactHeader(detail)
                    standingCard(detail)
                    if detail.contact.contactType == "character", let info = detail.charInfo {
                        characterInfoCard(info, corpName: detail.corpName, allianceName: detail.allianceName)
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
                Text("Select a contact to view details")
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func contactHeader(_ detail: ContactDetail) -> some View {
        HStack(spacing: 16) {
            let imageURL: URL? = {
                switch detail.contact.contactType {
                case "character":   return EVEImageURL.characterPortrait(detail.contact.contactId, size: 512)
                case "corporation": return EVEImageURL.corporationLogo(detail.contact.contactId, size: 256)
                case "alliance":    return EVEImageURL.allianceLogo(detail.contact.contactId, size: 256)
                default:            return EVEImageURL.corporationLogo(detail.contact.contactId, size: 256)
                }
            }()
            let isCharacter = detail.contact.contactType == "character"

            AsyncImage(url: imageURL) { image in
                image.resizable().aspectRatio(contentMode: .fill)
            } placeholder: {
                RoundedRectangle(cornerRadius: isCharacter ? 48 : 12).fill(.quaternary)
            }
            .frame(width: 96, height: 96)
            .clipShape(isCharacter ? AnyShape(Circle()) : AnyShape(RoundedRectangle(cornerRadius: 12)))

            VStack(alignment: .leading, spacing: 6) {
                Text(detail.name)
                    .font(.title2.bold())

                Text(detail.contact.displayTypeLabel)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                if let info = detail.charInfo, let sec = info.securityStatus {
                    Label(String(format: "%.2f", sec), systemImage: "shield.fill")
                        .font(.caption)
                        .foregroundStyle(securityColor(sec))
                }
            }

            Spacer()
        }
        .padding()
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
    }

    private func standingCard(_ detail: ContactDetail) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Standing")
                .font(.headline)

            HStack(spacing: 12) {
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 4).fill(.quaternary)
                        let fraction = (detail.contact.standing + 10.0) / 20.0
                        let color: Color = detail.contact.standing > 0 ? .green : detail.contact.standing < 0 ? .red : .secondary
                        RoundedRectangle(cornerRadius: 4)
                            .fill(color)
                            .frame(width: geo.size.width * max(0, min(1, fraction)))
                    }
                }
                .frame(height: 12)

                Text(String(format: "%+.1f", detail.contact.standing))
                    .font(.title3.bold().monospacedDigit())
                    .foregroundStyle(detail.contact.standing > 0 ? .green : detail.contact.standing < 0 ? .red : .secondary)
                    .frame(width: 50, alignment: .trailing)
            }

            HStack(spacing: 16) {
                if detail.contact.isWatched == true {
                    Label("Watched", systemImage: "eye.fill")
                        .font(.caption)
                        .foregroundStyle(.blue)
                }
                if detail.contact.isBlocked == true {
                    Label("Blocked", systemImage: "nosign")
                        .font(.caption)
                        .foregroundStyle(.red)
                }
                if detail.contact.isWatched != true && detail.contact.isBlocked != true {
                    Text("No flags")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
    }

    private func characterInfoCard(_ info: ESICharacterPublic, corpName: String?, allianceName: String?) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Character Info")
                .font(.headline)

            infoRow("Birthday", value: EVEFormatters.dateFormatter.string(from: info.birthday))
            infoRow("Race", value: raceName(info.raceId))
            infoRow("Bloodline", value: bloodlineName(info.bloodlineId))
            if let sec = info.securityStatus {
                infoRow("Security Status", value: String(format: "%.4f", sec))
            }
            if let corp = corpName {
                infoRow("Corporation", value: corp)
            }
            if let alliance = allianceName {
                infoRow("Alliance", value: alliance)
            }
            if let desc = info.description, !desc.isEmpty {
                Divider()
                Text("Bio")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(stripHTML(desc))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(5)
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

    // MARK: Helpers

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

    private var filterBar: some View {
        VStack(spacing: 6) {
            Picker("Type", selection: $typeFilter) {
                Text("All").tag("all")
                Text("Players").tag("player")
                Text("NPCs").tag("npc")
                Text("Corps").tag("corporation")
                Text("Alliances").tag("alliance")
            }
            .pickerStyle(.segmented)
            TextField("Filter contacts", text: $searchFilter)
                .textFieldStyle(.roundedBorder)
        }
        .padding(10)
        .background(.bar)
    }

    private func typeLabel(_ type: String) -> String {
        switch type {
        case "player":      return "Players"
        case "npc":         return "NPCs"
        case "corporation": return "Corporations"
        case "alliance":    return "Alliances"
        case "faction":     return "Factions"
        default:            return type.capitalized
        }
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

    private func stripHTML(_ html: String) -> String {
        html.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&#39;", with: "'")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: Data Loading

    private func load() async {
        guard let account = accountManager.selectedAccount else { return }
        isLoading = true
        error = nil
        do {
            let token = try await accountManager.validToken(for: account)
            let loaded: [ESIContact] = try await ESIClient.shared.fetchPages(
                "/characters/\(account.characterID)/contacts/", token: token
            )
            contacts = loaded
            let ids = loaded.map(\.contactId)
            contactNames = await NameResolver.shared.resolve(ids: ids)

            // Register player character contacts with the presence tracker (excludes NPC agents).
            let characterIDs = loaded.filter { $0.isPlayerCharacter }.map(\.contactId)
            presenceTracker.updateContactIDs(characterIDs)
        } catch {
            self.error = error.localizedDescription
        }
        isLoading = false
    }

    private func loadDetail(for contactId: Int) async {
        guard let contact = contacts.first(where: { $0.contactId == contactId }) else { return }
        isLoadingDetail = true
        selectedDetail = nil

        let name = contactNames[contactId] ?? "ID #\(contactId)"
        var charInfo: ESICharacterPublic? = nil
        var resolvedHistory: [ResolvedCorpHistory] = []
        var corpName: String? = nil
        var allianceName: String? = nil

        if contact.contactType == "character" {
            do { charInfo = try await ESIClient.shared.fetch("/characters/\(contactId)/") } catch {}

            if contact.isPlayerCharacter {
                var corpHistory: [ESICorporationHistory] = []
                do { corpHistory = try await ESIClient.shared.fetch("/characters/\(contactId)/corporationhistory/") } catch {}

                var idsToResolve: [Int] = []
                if let corpId = charInfo?.corporationId { idsToResolve.append(corpId) }
                if let allianceId = charInfo?.allianceId { idsToResolve.append(allianceId) }
                idsToResolve.append(contentsOf: corpHistory.map(\.corporationId))

                let resolved = await NameResolver.shared.resolve(ids: idsToResolve)
                if let corpId = charInfo?.corporationId { corpName = resolved[corpId] }
                if let allianceId = charInfo?.allianceId { allianceName = resolved[allianceId] }

                resolvedHistory = corpHistory
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
            } else if let corpId = charInfo?.corporationId {
                let resolved = await NameResolver.shared.resolve(ids: [corpId])
                corpName = resolved[corpId]
            }
        }

        selectedDetail = ContactDetail(
            contact: contact,
            name: name,
            charInfo: charInfo,
            corporationHistory: resolvedHistory,
            corpName: corpName,
            allianceName: allianceName
        )
        isLoadingDetail = false
    }

    private func deleteContact(_ contact: ESIContact) async {
        guard let account = accountManager.selectedAccount else { return }
        do {
            let token = try await accountManager.validToken(for: account)
            try await ESIClient.shared.delete(
                "/characters/\(account.characterID)/contacts/",
                token: token,
                queryItems: [URLQueryItem(name: "contact_ids", value: "\(contact.contactId)")]
            )
            contacts.removeAll { $0.contactId == contact.contactId }
            if selectedContactID == contact.contactId {
                selectedContactID = nil
                selectedDetail = nil
            }
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func updateStanding(contact: ESIContact, standing: Double) async {
        guard let account = accountManager.selectedAccount else { return }
        do {
            let token = try await accountManager.validToken(for: account)
            try await ESIClient.shared.put(
                "/characters/\(account.characterID)/contacts/",
                body: [contact.contactId],
                token: token,
                queryItems: [URLQueryItem(name: "standing", value: "\(standing)")]
            )
            if let idx = contacts.firstIndex(where: { $0.contactId == contact.contactId }) {
                contacts[idx] = ESIContact(
                    contactId: contact.contactId,
                    contactType: contact.contactType,
                    isBlocked: contact.isBlocked,
                    isWatched: contact.isWatched,
                    labelIds: contact.labelIds,
                    standing: standing
                )
            }
            if selectedContactID == contact.contactId {
                Task { await loadDetail(for: contact.contactId) }
            }
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func addContact(contactId: Int, contactType: String, standing: Double) async {
        guard let account = accountManager.selectedAccount else { return }
        do {
            let token = try await accountManager.validToken(for: account)
            let _: [Int] = try await ESIClient.shared.post(
                "/characters/\(account.characterID)/contacts/",
                body: [contactId],
                token: token,
                queryItems: [URLQueryItem(name: "standing", value: "\(standing)")]
            )
            await load()
        } catch {
            self.error = error.localizedDescription
        }
    }
}

// MARK: Contact Detail Model

struct ContactDetail {
    let contact: ESIContact
    let name: String
    var charInfo: ESICharacterPublic?
    var corporationHistory: [ResolvedCorpHistory]
    var corpName: String?
    var allianceName: String?
}

// Mark:  Contact Row

struct ContactRow: View {
    let contact: ESIContact
    let name: String?
    var presence: PresenceScore?

    var body: some View {
        HStack(spacing: 12) {
            // Portrait with optional presence badge overlay
            ZStack(alignment: .bottomTrailing) {
                AsyncImage(url: contact.imageURL) { image in
                    image.resizable().aspectRatio(contentMode: .fill)
                } placeholder: {
                    RoundedRectangle(cornerRadius: contact.contactType == "character" ? 20 : 6)
                        .fill(.quaternary)
                }
                .frame(width: 40, height: 40)
                .clipShape(contact.contactType == "character" ? AnyShape(Circle()) : AnyShape(RoundedRectangle(cornerRadius: 6)))

                if contact.isPlayerCharacter {
                    if let presence {
                        PresenceBadge(score: presence, size: 11)
                            .offset(x: 3, y: 3)
                    } else {
                        PresencePlaceholder(size: 11)
                            .offset(x: 3, y: 3)
                    }
                }
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(name ?? "ID #\(contact.contactId)")
                    .font(.subheadline)
                Text(contact.displayTypeLabel)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            // Standing bar + value
            HStack(spacing: 8) {
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 3).fill(.quaternary)
                        let fraction = (contact.standing + 10.0) / 20.0
                        let color: Color = contact.standing > 0 ? .green : contact.standing < 0 ? .red : .secondary
                        RoundedRectangle(cornerRadius: 3)
                            .fill(color)
                            .frame(width: geo.size.width * max(0, min(1, fraction)))
                    }
                }
                .frame(width: 80, height: 8)

                Text(String(format: "%+.1f", contact.standing))
                    .font(.subheadline.bold().monospacedDigit())
                    .foregroundStyle(contact.standing > 0 ? .green : contact.standing < 0 ? .red : .secondary)
                    .frame(width: 40, alignment: .trailing)
            }

            if contact.isWatched == true {
                Image(systemName: "eye.fill")
                    .font(.caption)
                    .foregroundStyle(.blue)
            }
            if contact.isBlocked == true {
                Image(systemName: "nosign")
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
        .padding(.vertical, 2)
    }
}

// Mark:  Add Contact Sheet

struct AddContactSheet: View {
    let onAdd: (Int, String, Double) async -> Void
    @Environment(\.dismiss) private var dismiss

    @State private var nameInput = ""
    @State private var standing: Double = 0
    @State private var isSearching = false
    @State private var searchResult: SearchResult?
    @State private var searchError: String?
    @State private var isAdding = false

    struct SearchResult {
        let id: Int
        let name: String
        let type: String
    }

    private let standingOptions: [(Double, String, Color)] = [
        (-10, "Terrible", .red),
        (-5,  "Bad",      .orange),
        (0,   "Neutral",  .secondary),
        (5,   "Good",     .mint),
        (10,  "Excellent",.green)
    ]

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Add Contact").font(.headline)
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.escape)
            }
            .padding()
            Divider()

            VStack(alignment: .leading, spacing: 20) {
                // Search
                VStack(alignment: .leading, spacing: 8) {
                    Text("Character / Corporation / Alliance").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                    HStack {
                        TextField("Exact name…", text: $nameInput)
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
                    if let searchError {
                        Text(searchError).font(.caption).foregroundStyle(.red)
                    }
                    if let result = searchResult {
                        HStack(spacing: 10) {
                            Image(systemName: result.type == "character" ? "person.fill" : result.type == "corporation" ? "building.2.fill" : "link")
                                .foregroundStyle(.blue)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(result.name).font(.subheadline.bold())
                                Text(result.type.capitalized).font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                        }
                        .padding(10)
                        .background(.green.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
                    }
                }

                // Standing picker
                VStack(alignment: .leading, spacing: 10) {
                    Text("Standing").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                    HStack(spacing: 8) {
                        ForEach(standingOptions, id: \.0) { value, label, color in
                            StandingOptionButton(
                                value: value, label: label, color: color,
                                isSelected: standing == value
                            ) { standing = value }
                        }
                    }
                }
            }
            .padding()

            Divider()

            HStack {
                Spacer()
                Button("Add Contact") {
                    Task { await addContact() }
                }
                .buttonStyle(.borderedProminent)
                .disabled(searchResult == nil || isAdding)
            }
            .padding()
        }
        .frame(minWidth: 460, minHeight: 320)
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
                searchResult = SearchResult(id: match.id, name: match.name, type: "character")
            } else if let match = result.corporations?.first(where: { $0.name.lowercased() == name.lowercased() }) {
                searchResult = SearchResult(id: match.id, name: match.name, type: "corporation")
            } else if let match = result.alliances?.first(where: { $0.name.lowercased() == name.lowercased() }) {
                searchResult = SearchResult(id: match.id, name: match.name, type: "alliance")
            } else {
                searchError = "No exact match found for \"\(name)\". Check the spelling."
            }
        } catch {
            searchError = error.localizedDescription
        }
    }

    private func addContact() async {
        guard let result = searchResult else { return }
        isAdding = true
        await onAdd(result.id, result.type, standing)
        isAdding = false
        dismiss()
    }
}

// Mark:  Edit Standing Sheet

struct EditStandingSheet: View {
    let contactName: String
    let currentStanding: Double
    let onUpdate: (Double) async -> Void
    @Environment(\.dismiss) private var dismiss

    @State private var standing: Double
    @State private var isUpdating = false

    private let standingOptions: [(Double, String, Color)] = [
        (-10, "Terrible", .red),
        (-5,  "Bad",      .orange),
        (0,   "Neutral",  .secondary),
        (5,   "Good",     .mint),
        (10,  "Excellent", .green)
    ]

    init(contactName: String, currentStanding: Double, onUpdate: @escaping (Double) async -> Void) {
        self.contactName = contactName
        self.currentStanding = currentStanding
        self.onUpdate = onUpdate
        _standing = State(initialValue: currentStanding)
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Edit Standing").font(.headline)
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.escape)
            }
            .padding()
            Divider()

            VStack(alignment: .leading, spacing: 20) {
                Text(contactName).font(.title3.bold())

                VStack(alignment: .leading, spacing: 10) {
                    Text("Standing").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                    HStack(spacing: 8) {
                        ForEach(standingOptions, id: \.0) { value, label, color in
                            StandingOptionButton(
                                value: value, label: label, color: color,
                                isSelected: standing == value
                            ) { standing = value }
                        }
                    }
                }
            }
            .padding()

            Divider()

            HStack {
                Spacer()
                Button("Update Standing") {
                    Task {
                        isUpdating = true
                        await onUpdate(standing)
                        isUpdating = false
                        dismiss()
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(standing == currentStanding || isUpdating)
                .overlay(alignment: .leading) {
                    if isUpdating { ProgressView().controlSize(.small).padding(.leading, 8) }
                }
            }
            .padding()
        }
        .frame(minWidth: 420, minHeight: 260)
    }
}

// Mark:  Standing Option Button

struct StandingOptionButton: View {
    let value: Double
    let label: String
    let color: Color
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 3) {
                Text(value >= 0 ? "+\(Int(value))" : "\(Int(value))")
                    .font(.caption.bold().monospacedDigit())
                    .foregroundStyle(isSelected ? color : .secondary)
                Text(label)
                    .font(.caption2)
                    .foregroundStyle(isSelected ? color : Color.secondary.opacity(0.6))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .background(isSelected ? color.opacity(0.15) : Color.secondary.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(isSelected ? color.opacity(0.4) : Color.clear, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}
