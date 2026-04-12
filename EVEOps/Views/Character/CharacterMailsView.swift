import SwiftUI

struct CharacterMailsView: View {
    @Environment(AccountManager.self) private var accountManager
    @State private var mails: [ESIMailHeader] = []
    @State private var selectedMail: ESIMailHeader?
    @State private var mailBody: String?
    @State private var isLoading = true
    @State private var error: String?
    @State private var senderNames: [Int: String] = [:]

    var body: some View {
        LoadingStateView(isLoading: isLoading, error: error, isEmpty: mails.isEmpty, emptyMessage: "No mails found") {
            HSplitView {
                mailList
                    .frame(minWidth: 300, idealWidth: 350)
                mailDetail
                    .frame(minWidth: 300)
            }
        }
        .navigationTitle("Mails")
        .task { await loadMails() }
    }

    private var mailList: some View {
        List(mails, selection: $selectedMail) { mail in
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
}
