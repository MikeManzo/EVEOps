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

struct CharacterCommunicationsView: View {
    @Environment(AccountManager.self) private var accountManager
    @State private var notifications: [ESINotification] = []
    @State private var isLoading = true
    @State private var error: String?
    @State private var filterType = "all"
    @State private var selectedNotification: ESINotification?

    var body: some View {
        LoadingStateView(isLoading: isLoading, error: error, isEmpty: notifications.isEmpty, emptyMessage: "No notifications") {
            HStack(spacing: 0) {
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

                    List(filteredNotifications, selection: $selectedNotification) { notification in
                        notificationRow(notification)
                            .tag(notification)
                    }
                }
                .frame(maxWidth: .infinity)

                if let selected = selectedNotification {
                    Divider()
                    NotificationDetailView(notification: selected)
                        .frame(width: 320)
                }
            }
        }
        .safeAreaInset(edge: .top, spacing: 0) {
            HStack {
                Text("Communications")
                    .font(.largeTitle.bold())
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(.background)
        }
        .navigationTitle("")
        .task(id: accountManager.selectedCharacterID) {
            notifications = []
            selectedNotification = nil
            isLoading = true
            await loadNotifications()
        }
    }

    private func notificationRow(_ notification: ESINotification) -> some View {
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
                    Text(text.strippingEVEMarkup.prefix(200))
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

    private var filteredNotifications: [ESINotification] {
        switch filterType {
        case "unread": return notifications.filter { $0.isRead != true }
        case "structure": return notifications.filter { $0.type.lowercased().contains("structure") || $0.type.lowercased().contains("tower") }
        case "war": return notifications.filter { $0.type.lowercased().contains("war") || $0.type.lowercased().contains("ally") }
        default: return notifications
        }
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

// MARK:  Detail Pane

struct NotificationDetailView: View {
    let notification: ESINotification
    @State private var senderName: String?

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                // Header
                HStack(spacing: 12) {
                    Image(systemName: notificationIcon(notification.type))
                        .font(.title2)
                        .foregroundStyle(notificationColor(notification.type))
                        .frame(width: 32)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(formatNotificationType(notification.type))
                            .font(.headline)
                        if notification.isRead != true {
                            Label("Unread", systemImage: "circle.fill")
                                .font(.caption)
                                .foregroundStyle(.blue)
                        }
                    }
                    Spacer()
                }
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.bar)

                VStack(alignment: .leading, spacing: 16) {
                    // Details
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Details")
                            .font(.subheadline.bold())
                            .foregroundStyle(.secondary)

                        infoRow(label: "Time", value: notification.timestamp.formatted(date: .long, time: .shortened))
                        infoRow(label: "Type", value: notification.type)
                        infoRow(label: "Sender", value: senderName ?? "ID: \(notification.senderId)")
                        infoRow(label: "Sender Type", value: formatSenderType(notification.senderType))
                        infoRow(label: "Status", value: notification.isRead == true ? "Read" : "Unread")
                        infoRow(label: "ID", value: "\(notification.notificationId)")
                    }

                    // Raw text payload
                    if let text = notification.text, !text.isEmpty {
                        Divider()
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Notification Data")
                                .font(.subheadline.bold())
                                .foregroundStyle(.secondary)

                            Text(text.strippingEVEMarkup)
                                .font(.caption.monospaced())
                                .foregroundStyle(.primary)
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(8)
                                .background(.quaternary.opacity(0.4))
                                .clipShape(RoundedRectangle(cornerRadius: 6))
                        }
                    }
                }
                .padding()
            }
        }
        .frame(minWidth: 280, idealWidth: 320)
        .task(id: notification.notificationId) { await resolveSender() }
    }

    private func infoRow(label: String, value: String) -> some View {
        HStack(alignment: .top) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 90, alignment: .trailing)
            Text(value)
                .font(.caption)
                .textSelection(.enabled)
            Spacer()
        }
    }

    private func resolveSender() async {
        let names = await NameResolver.shared.resolve(ids: [notification.senderId])
        senderName = names[notification.senderId]
    }

    private func formatSenderType(_ type: String) -> String {
        switch type {
        case "character": return "Character"
        case "corporation": return "Corporation"
        case "alliance": return "Alliance"
        case "faction": return "Faction"
        default: return type
        }
    }
}

// MARK:  Shared helpers (used by both views)

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
    type.replacingOccurrences(of: "([a-z])([A-Z])", with: "$1 $2", options: .regularExpression)
}
