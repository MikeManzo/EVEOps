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

struct CharacterMailsView: View {
    @Environment(AccountManager.self) private var accountManager
    @State private var mails: [ESIMailHeader] = []
    @State private var selectedMail: ESIMailHeader?
    @State private var mailBody: String?
    @State private var isLoading = true
    @State private var error: String?
    @State private var senderNames: [Int: String] = [:]
    @State private var showingCompose = false
    @State private var deleteError: String?

    var body: some View {
        LoadingStateView(isLoading: isLoading, error: error, isEmpty: mails.isEmpty, emptyMessage: "No mails found") {
            VStack(spacing: 0) {
                HStack {
                    Spacer()
                    Button {
                        showingCompose = true
                    } label: {
                        Label("Compose", systemImage: "square.and.pencil")
                    }
                    .buttonStyle(.borderless)
                    Button(role: .destructive) {
                        Task {
                            if let mail = selectedMail { await deleteMail(mail) }
                        }
                    } label: {
                        Label("Delete Mail", systemImage: "trash")
                    }
                    .buttonStyle(.borderless)
                    .disabled(selectedMail == nil)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(.bar)
                Divider()
                HSplitView {
                    mailList
                        .frame(minWidth: 300, idealWidth: 350)
                    mailDetail
                        .frame(minWidth: 300)
                }
            }
        }
        .navigationTitle("Mails")
        .sheet(isPresented: $showingCompose) {
            ComposeMailSheet { subject, recipients, body in
                await sendMail(subject: subject, recipients: recipients, body: body)
            }
        }
        .task(id: accountManager.selectedCharacterID) {
            mails = []
            selectedMail = nil
            mailBody = nil
            isLoading = true
            await loadMails()
        }
    }

    private var mailList: some View {
        List(selection: $selectedMail) {
            ForEach(mails) { mail in
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        if mail.isRead != true {
                            Circle()
                                .fill(.blue)
                                .frame(width: 8, height: 8)
                        }
                        Text(mail.subject ?? "(No Subject)")
                            .font(.subheadline)
                            .fontWeight(mail.isRead == true ? .regular : .bold)
                            .lineLimit(1)
                    }
                    HStack {
                        if let fromID = mail.from {
                            Text(senderNames[fromID] ?? "#\(fromID)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        if let timestamp = mail.timestamp {
                            Text(timestamp, style: .date)
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                        }
                    }
                }
                .padding(.vertical, 2)
                .tag(mail)
                .swipeActions(edge: .trailing) {
                    Button(role: .destructive) {
                        Task { await deleteMail(mail) }
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var mailDetail: some View {
        if let mail = selectedMail {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    Text(mail.subject ?? "(No Subject)")
                        .font(.title2.bold())

                    HStack {
                        if let fromID = mail.from {
                            Text("From: \(senderNames[fromID] ?? "#\(fromID)")")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        if let timestamp = mail.timestamp {
                            Text(timestamp, format: .dateTime)
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                        }
                    }

                    Divider()

                    if let body = mailBody {
                        Text(stripHTMLTags(body))
                            .font(.body)
                            .textSelection(.enabled)
                    } else {
                        ProgressView()
                    }
                }
                .padding()
            }
            .onChange(of: selectedMail) { _, newValue in
                if let mail = newValue {
                    Task { await loadMailBody(mail) }
                }
            }
            .task {
                if let mail = selectedMail {
                    await loadMailBody(mail)
                }
            }
        } else {
            Text("Select a mail to read")
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func stripHTMLTags(_ html: String) -> String {
        var result = html
        result = result.replacingOccurrences(of: "<br>", with: "\n", options: .caseInsensitive)
        result = result.replacingOccurrences(of: "<br/>", with: "\n", options: .caseInsensitive)
        result = result.replacingOccurrences(of: "<br />", with: "\n", options: .caseInsensitive)
        result = result.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
        return result
    }

    private func loadMails() async {
        guard let account = accountManager.selectedAccount else { return }
        isLoading = true
        do {
            let token = try await accountManager.validToken(for: account)
            mails = try await ESIClient.shared.fetch(
                "/characters/\(account.characterID)/mail/", token: token
            )
            mails.sort { ($0.timestamp ?? .distantPast) > ($1.timestamp ?? .distantPast) }
            if selectedMail == nil { selectedMail = mails.first }

            let senderIDs = Set(mails.compactMap(\.from))
            senderNames = await NameResolver.shared.resolve(ids: Array(senderIDs))
        } catch {
            self.error = error.localizedDescription
        }
        isLoading = false
    }

    private func loadMailBody(_ mail: ESIMailHeader) async {
        guard let account = accountManager.selectedAccount, let mailId = mail.mailId else { return }
        mailBody = nil
        do {
            let token = try await accountManager.validToken(for: account)
            let body: ESIMailBody = try await ESIClient.shared.fetch(
                "/characters/\(account.characterID)/mail/\(mailId)/", token: token
            )
            mailBody = body.body ?? "(Empty)"
        } catch {
            mailBody = "Failed to load mail body."
        }
    }

    private func deleteMail(_ mail: ESIMailHeader) async {
        guard let account = accountManager.selectedAccount, let mailId = mail.mailId else { return }
        do {
            let token = try await accountManager.validToken(for: account)
            try await ESIClient.shared.delete(
                "/characters/\(account.characterID)/mail/\(mailId)/",
                token: token
            )
            mails.removeAll { $0.mailId == mail.mailId }
            if selectedMail?.mailId == mail.mailId {
                selectedMail = mails.first
            }
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func sendMail(subject: String, recipients: [ESIMailRecipient], body: String) async {
        guard let account = accountManager.selectedAccount else { return }
        do {
            let token = try await accountManager.validToken(for: account)
            let request = ESIMailSendRequest(body: body, recipients: recipients, subject: subject)
            let _: Int = try await ESIClient.shared.post(
                "/characters/\(account.characterID)/mail/", body: request, token: token
            )
            await loadMails()
        } catch {
            self.error = error.localizedDescription
        }
    }
}

// MARK:  Compose Mail Sheet

struct ComposeMailSheet: View {
    let onSend: (String, [ESIMailRecipient], String) async -> Void
    @Environment(\.dismiss) private var dismiss

    @State private var toInput = ""
    @State private var subject = ""
    @State private var messageBody = ""
    @State private var recipients: [ResolvedRecipient] = []
    @State private var isSearching = false
    @State private var searchError: String?
    @State private var isSending = false
    @State private var sendError: String?

    struct ResolvedRecipient: Identifiable {
        let id: Int
        let name: String
        let type: String // "character", "corporation", "alliance"
    }

    private var canSend: Bool {
        !recipients.isEmpty && !subject.trimmingCharacters(in: .whitespaces).isEmpty &&
        !messageBody.trimmingCharacters(in: .whitespaces).isEmpty && !isSending
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("New Message").font(.headline)
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.escape)
            }
            .padding()
            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    // Recipients
                    VStack(alignment: .leading, spacing: 6) {
                        Text("To").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                        if !recipients.isEmpty {
                            RecipientPillGrid(recipients) { recipient in
                                HStack(spacing: 4) {
                                    Text(recipient.name).font(.caption)
                                    Button {
                                        recipients.removeAll { $0.id == recipient.id }
                                    } label: {
                                        Image(systemName: "xmark").font(.caption2)
                                    }
                                    .buttonStyle(.plain)
                                }
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(.blue.opacity(0.15), in: Capsule())
                            }
                        }
                        HStack {
                            TextField("Search character or corporation name…", text: $toInput)
                                .textFieldStyle(.roundedBorder)
                                .onSubmit { Task { await searchRecipient() } }
                            Button("Add") { Task { await searchRecipient() } }
                                .disabled(toInput.trimmingCharacters(in: .whitespaces).isEmpty || isSearching)
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
                    }

                    Divider()

                    // Subject
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Subject").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                        TextField("Subject", text: $subject)
                            .textFieldStyle(.roundedBorder)
                    }

                    Divider()

                    // Body
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Message").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                        TextEditor(text: $messageBody)
                            .font(.body)
                            .frame(minHeight: 200)
                            .overlay(
                                RoundedRectangle(cornerRadius: 6)
                                    .stroke(.quaternary, lineWidth: 1)
                            )
                    }

                    if let sendError {
                        HStack(spacing: 6) {
                            Image(systemName: "exclamationmark.triangle.fill")
                            Text(sendError)
                        }
                        .foregroundStyle(.red)
                        .font(.caption)
                        .padding(8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(.red.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
                    }
                }
                .padding()
            }

            Divider()

            // Footer
            HStack {
                Spacer()
                Button("Send") {
                    Task { await send() }
                }
                .buttonStyle(.borderedProminent)
                .disabled(!canSend)
                .overlay(alignment: .leading) {
                    if isSending { ProgressView().controlSize(.small).padding(.leading, 8) }
                }
            }
            .padding()
        }
        .frame(minWidth: 540, minHeight: 480)
    }

    private func searchRecipient() async {
        let name = toInput.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }
        isSearching = true
        searchError = nil
        defer { isSearching = false }
        do {
            let result: ESIIDsResponse = try await ESIClient.shared.post("/universe/ids/", body: [name])
            if let chars = result.characters, let match = chars.first(where: { $0.name.lowercased() == name.lowercased() }) {
                if !recipients.contains(where: { $0.id == match.id }) {
                    recipients.append(ResolvedRecipient(id: match.id, name: match.name, type: "character"))
                }
                toInput = ""
            } else if let corps = result.corporations, let match = corps.first(where: { $0.name.lowercased() == name.lowercased() }) {
                if !recipients.contains(where: { $0.id == match.id }) {
                    recipients.append(ResolvedRecipient(id: match.id, name: match.name, type: "corporation"))
                }
                toInput = ""
            } else if let alliances = result.alliances, let match = alliances.first(where: { $0.name.lowercased() == name.lowercased() }) {
                if !recipients.contains(where: { $0.id == match.id }) {
                    recipients.append(ResolvedRecipient(id: match.id, name: match.name, type: "alliance"))
                }
                toInput = ""
            } else {
                searchError = "No exact match found for \"\(name)\". Check the spelling."
            }
        } catch {
            searchError = error.localizedDescription
        }
    }

    private func send() async {
        isSending = true
        sendError = nil
        let mailRecipients = recipients.map { ESIMailRecipient(recipientId: $0.id, recipientType: $0.type) }
        await onSend(subject, mailRecipients, messageBody)
        isSending = false
        dismiss()
    }
}

// MARK:  Recipient pill grid

struct RecipientPillGrid<Data: RandomAccessCollection, Content: View>: View where Data.Element: Identifiable {
    let data: Data
    let content: (Data.Element) -> Content

    init(_ data: Data, @ViewBuilder content: @escaping (Data.Element) -> Content) {
        self.data = data
        self.content = content
    }

    var body: some View {
        LazyVGrid(
            columns: [GridItem(.adaptive(minimum: 100, maximum: 200), alignment: .leading)],
            alignment: .leading,
            spacing: 6
        ) {
            ForEach(data) { item in
                content(item)
            }
        }
    }
}
