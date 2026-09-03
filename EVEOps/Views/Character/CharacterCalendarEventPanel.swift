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

// MARK:  EVE Calendar Event Detail

struct CalendarEventDetailPanel: View {
    let event: ESICalendarEvent
    @Environment(AccountManager.self) private var accountManager
    @State private var detail: ESICalendarEventDetail?
    @State private var isLoading = true
    @State private var currentResponse: String
    @State private var isResponding = false
    @State private var responseError: String?

    init(event: ESICalendarEvent) {
        self.event = event
        _currentResponse = State(initialValue: event.eventResponse ?? "not_responded")
    }

    var body: some View {
        VStack(spacing: 0) {
            detailHeader
            Divider()
            if isLoading {
                ProgressView("Loading…").frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let detail {
                detailBody(detail)
            } else {
                Text("Failed to load event details")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .task {
            guard let account = accountManager.selectedAccount else { isLoading = false; return }
            do {
                let token = try await accountManager.validToken(for: account)
                detail = try await ESIClient.shared.fetch(
                    "/characters/\(account.characterID)/calendar/\(event.eventId)/", token: token
                )
                currentResponse = detail?.response ?? currentResponse
            } catch {
                logSuppressed(error, "Calendar: event \(event.eventId) detail")
            }
            isLoading = false
        }
    }

    private var detailHeader: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(event.title ?? "Untitled Event").font(.headline)
                    if (event.importance ?? 0) > 0 {
                        Image(systemName: "exclamationmark.circle.fill")
                            .foregroundStyle(.orange).font(.subheadline)
                    }
                }
                if let date = event.eventDate {
                    Text(date, format: .dateTime.weekday(.wide).month(.wide).day().hour().minute())
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            Spacer()
            Label(responseLabel(currentResponse), systemImage: responseIcon(currentResponse))
                .font(.caption.weight(.medium))
                .foregroundStyle(responseColor(currentResponse))
                .padding(.horizontal, 8).padding(.vertical, 4)
                .background(responseColor(currentResponse).opacity(0.12), in: Capsule())
        }
        .padding(16)
        .background(.bar)
    }

    private func detailBody(_ detail: ESICalendarEventDetail) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                GroupBox {
                    Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 6) {
                        if let ownerName = detail.ownerName {
                            GridRow {
                                Text("Organizer").foregroundStyle(.secondary)
                                Text(ownerName)
                            }
                        }
                        GridRow {
                            Text("Date").foregroundStyle(.secondary)
                            Text(detail.date.formatted(.dateTime))
                        }
                        GridRow {
                            Text("Duration").foregroundStyle(.secondary)
                            Text("\(detail.duration) minutes")
                        }
                    }
                    .font(.subheadline)
                } label: {
                    Label("Event Info", systemImage: "info.circle")
                        .font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                }

                if !detail.text.isEmpty {
                    GroupBox {
                        Text(detail.text.strippingEVEMarkup)
                            .font(.subheadline)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    } label: {
                        Label("Description", systemImage: "text.alignleft")
                            .font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                    }
                }

                GroupBox {
                    VStack(spacing: 8) {
                        HStack(spacing: 8) {
                            RSVPButton(label: "Accept",    icon: "checkmark.circle.fill",   color: .green,
                                       isSelected: currentResponse == "accepted",  isLoading: isResponding)
                            { await respond("accepted") }
                            RSVPButton(label: "Tentative", icon: "questionmark.circle.fill", color: .orange,
                                       isSelected: currentResponse == "tentative", isLoading: isResponding)
                            { await respond("tentative") }
                            RSVPButton(label: "Decline",   icon: "xmark.circle.fill",        color: .red,
                                       isSelected: currentResponse == "declined",  isLoading: isResponding)
                            { await respond("declined") }
                        }
                        if let responseError {
                            Text(responseError).font(.caption).foregroundStyle(.red)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                } label: {
                    Label("Your Response", systemImage: "hand.raised")
                        .font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                }
            }
            .padding(16)
        }
    }

    private func respond(_ response: String) async {
        guard let account = accountManager.selectedAccount else { return }
        isResponding = true; responseError = nil
        do {
            let token = try await accountManager.validToken(for: account)
            try await ESIClient.shared.put(
                "/characters/\(account.characterID)/calendar/\(event.eventId)/",
                body: ESICalendarResponseRequest(response: response), token: token
            )
            currentResponse = response
        } catch { responseError = error.localizedDescription }
        isResponding = false
    }

    private func responseIcon(_ r: String) -> String {
        switch r {
        case "accepted":  return "checkmark.circle.fill"
        case "declined":  return "xmark.circle.fill"
        case "tentative": return "questionmark.circle.fill"
        default:          return "circle"
        }
    }

    private func responseColor(_ r: String) -> Color {
        switch r {
        case "accepted":  return .green
        case "declined":  return .red
        case "tentative": return .orange
        default:          return .secondary
        }
    }

    private func responseLabel(_ r: String) -> String {
        r.replacingOccurrences(of: "_", with: " ").capitalized
    }
}

// MARK:  RSVP Button

struct RSVPButton: View {
    let label: LocalizedStringKey
    let icon: String
    let color: Color
    let isSelected: Bool
    let isLoading: Bool
    let action: () async -> Void

    var body: some View {
        Button { Task { await action() } } label: {
            Label(label, systemImage: icon)
                .font(.subheadline.weight(isSelected ? .bold : .regular))
                .foregroundStyle(isSelected ? color : .secondary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                .background(isSelected ? color.opacity(0.15) : Color.clear, in: RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8)
                    .stroke(isSelected ? color.opacity(0.4) : Color.secondary.opacity(0.2), lineWidth: 1))
        }
        .buttonStyle(.plain)
        .disabled(isLoading || isSelected)
    }
}
