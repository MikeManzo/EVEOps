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
        LoadingStateView(isLoading: isLoading, error: error, isEmpty: contacts.isEmpty, emptyMessage: "No contacts found") {
            VStack(spacing: 0) {
                filterBar
                List {
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
                .searchable(text: $searchFilter, prompt: "Filter contacts")
            }
        }
        .navigationTitle("Contacts")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    showingAddContact = true
                } label: {
                    Label("Add Contact", systemImage: "person.badge.plus")
                }
            }
        }
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
            await load()
        }
    }

    private var filterBar: some View {
        HStack {
            Picker("Type", selection: $typeFilter) {
                Text("All").tag("all")
                Text("Players").tag("player")
                Text("NPCs").tag("npc")
                Text("Corps").tag("corporation")
                Text("Alliances").tag("alliance")
            }
            .pickerStyle(.segmented)
            .frame(maxWidth: 520)
            Spacer()
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

// MARK: - Contact Row

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

// MARK: - Add Contact Sheet

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

// MARK: - Edit Standing Sheet

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

// MARK: - Standing Option Button

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
