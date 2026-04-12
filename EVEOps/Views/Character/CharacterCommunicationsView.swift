import SwiftUI

struct CharacterCommunicationsView: View {
    @Environment(AccountManager.self) private var accountManager
    @State private var notifications: [ESINotification] = []
    @State private var isLoading = true
    @State private var error: String?
    @State private var filterType = "all"

    var body: some View {
        LoadingStateView(isLoading: isLoading, error: error, isEmpty: notifications.isEmpty, emptyMessage: "No notifications") {
            VStack(spacing: 0) {
                HStack {
                    Picker("Type", selection: $filterType) {
                        Text("All").tag("all")
                        Text("Unread").tag("unread")
                        Text("Structure").tag("structure")
                        Text("War").tag("war")
                    }
                    .pickerStyle(.segmented)
                    .frame(maxWidth: 400)
                    Spacer()
                    Text("\(filteredNotifications.count) notifications")
                        .foregroundStyle(.secondary)
                }
                .padding(10)
                .background(.bar)

                List(filteredNotifications) { notification in
                    HStack(alignment: .top, spacing: 12) {
                        Image(systemName: notificationIcon(notification.type))
                            .foregroundStyle(notificationColor(notification.type))
                            .frame(width: 20)

                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text(formatNotificationType(notification.type))
                                    .font(.subheadline.bold())
                                if notification.isRead != true {
                                    Circle()
                                        .fill(.blue)
                                        .frame(width: 6, height: 6)
                                }
                            }
                            if let text = notification.text {
                                Text(text.prefix(200))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(3)
                            }
                            Text(notification.timestamp, style: .relative)
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                        }
                    }
                    .padding(.vertical, 2)
                }
            }
        }
        .navigationTitle("Communications")
        .task { await loadNotifications() }
    }

    private var filteredNotifications: [ESINotification] {
        switch filterType {
        case "unread": return notifications.filter { $0.isRead != true }
        case "structure": return notifications.filter { $0.type.lowercased().contains("structure") || $0.type.lowercased().contains("tower") }
        case "war": return notifications.filter { $0.type.lowercased().contains("war") || $0.type.lowercased().contains("ally") }
        default: return notifications
        }
    }

    private func notificationIcon(_ type: String) -> String {
        let lower = type.lowercased()
        if lower.contains("structure") || lower.contains("tower") { return "building.2.fill" }
        if lower.contains("war") { return "shield.fill" }
        if lower.contains("kill") { return "xmark.circle.fill" }
        if lower.contains("contract") { return "doc.text.fill" }
        if lower.contains("corp") { return "person.3.fill" }
        return "bell.fill"
    }

    private func notificationColor(_ type: String) -> Color {
        let lower = type.lowercased()
        if lower.contains("attack") || lower.contains("kill") { return .red }
        if lower.contains("structure") || lower.contains("tower") { return .orange }
        if lower.contains("war") { return .purple }
        return .blue
    }

    private func formatNotificationType(_ type: String) -> String {
        var result = type
        // Convert camelCase to spaces
        result = result.replacingOccurrences(of: "([a-z])([A-Z])", with: "$1 $2", options: .regularExpression)
        return result
    }

    private func loadNotifications() async {
        guard let account = accountManager.selectedAccount else { return }
        isLoading = true
        do {
            let token = try await accountManager.validToken(for: account)
            notifications = try await ESIClient.shared.fetch(
                "/characters/\(account.characterID)/notifications/", token: token
            )
            notifications.sort { $0.timestamp > $1.timestamp }
        } catch {
            self.error = error.localizedDescription
        }
        isLoading = false
    }
}
