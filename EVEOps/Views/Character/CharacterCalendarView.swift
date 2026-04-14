import SwiftUI

struct CharacterCalendarView: View {
    @Environment(AccountManager.self) private var accountManager
    @State private var events: [ESICalendarEvent] = []
    @State private var isLoading = false
    @State private var error: String?
    @State private var selectedEvent: ESICalendarEvent?
    @State private var responseFilter = "all"

    var body: some View {
        LoadingStateView(isLoading: isLoading, error: error, isEmpty: events.isEmpty, emptyMessage: "No upcoming events") {
            VStack(spacing: 0) {
                filterBar
                eventList
            }
        }
        .navigationTitle("Calendar")
        .sheet(item: $selectedEvent) { event in
            CalendarEventDetailSheet(event: event)
        }
        .task(id: accountManager.selectedCharacterID) {
            guard let account = accountManager.selectedAccount else { return }
            isLoading = true
            error = nil
            do {
                let token = try await accountManager.validToken(for: account)
                let loaded: [ESICalendarEvent] = try await ESIClient.shared.fetch(
                    "/characters/\(account.characterID)/calendar/", token: token
                )
                events = loaded.sorted { ($0.eventDate ?? .distantFuture) < ($1.eventDate ?? .distantFuture) }
            } catch {
                self.error = error.localizedDescription
            }
            isLoading = false
        }
    }

    private var filterBar: some View {
        HStack {
            Picker("Response", selection: $responseFilter) {
                Text("All").tag("all")
                Text("Accepted").tag("accepted")
                Text("Tentative").tag("tentative")
                Text("Not Responded").tag("not_responded")
                Text("Declined").tag("declined")
            }
            .pickerStyle(.segmented)
            .frame(maxWidth: 500)
            Spacer()
        }
        .padding(10)
        .background(.bar)
    }

    private var filteredEvents: [ESICalendarEvent] {
        responseFilter == "all" ? events : events.filter { $0.eventResponse == responseFilter }
    }

    private var eventList: some View {
        List(filteredEvents) { event in
            CalendarEventRow(event: event)
                .contentShape(Rectangle())
                .onTapGesture { selectedEvent = event }
        }
    }
}

struct CalendarEventRow: View {
    let event: ESICalendarEvent

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: responseIcon(event.eventResponse ?? "not_responded"))
                .foregroundStyle(responseColor(event.eventResponse ?? "not_responded"))
                .font(.title3)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(event.title ?? "Untitled Event").font(.subheadline)
                    if (event.importance ?? 0) > 0 {
                        Image(systemName: "exclamationmark.circle.fill")
                            .foregroundStyle(.orange).font(.caption)
                    }
                }
                if let date = event.eventDate {
                    Text(date, style: .relative).font(.caption).foregroundStyle(.secondary)
                }
                Text(responseLabel(event.eventResponse ?? "not_responded"))
                    .font(.caption2)
                    .foregroundStyle(responseColor(event.eventResponse ?? "not_responded"))
            }

            Spacer()

            if let date = event.eventDate {
                VStack(alignment: .trailing, spacing: 2) {
                    Text(date, style: .date).font(.caption2).foregroundStyle(.secondary)
                    Text(date, style: .time).font(.caption2).foregroundStyle(.tertiary)
                }
            }
        }
        .padding(.vertical, 2)
    }

    private func responseIcon(_ response: String) -> String {
        switch response {
        case "accepted": return "checkmark.circle.fill"
        case "declined": return "xmark.circle.fill"
        case "tentative": return "questionmark.circle.fill"
        default: return "circle"
        }
    }

    private func responseColor(_ response: String) -> Color {
        switch response {
        case "accepted": return .green
        case "declined": return .red
        case "tentative": return .orange
        default: return .secondary
        }
    }

    private func responseLabel(_ response: String) -> String {
        response.replacingOccurrences(of: "_", with: " ").capitalized
    }
}

struct CalendarEventDetailSheet: View {
    let event: ESICalendarEvent
    @Environment(AccountManager.self) private var accountManager
    @State private var detail: ESICalendarEventDetail?
    @State private var isLoading = true
    @State private var currentResponse: String
    @State private var isResponding = false
    @State private var responseError: String?
    @Environment(\.dismiss) private var dismiss

    init(event: ESICalendarEvent) {
        self.event = event
        _currentResponse = State(initialValue: event.eventResponse ?? "not_responded")
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(event.title ?? "Event Detail").font(.headline)
                Spacer()
                Button("Close") { dismiss() }.keyboardShortcut(.escape)
            }
            .padding()
            Divider()

            if isLoading {
                ProgressView("Loading...").padding().frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let detail {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        GroupBox("Event Info") {
                            VStack(alignment: .leading, spacing: 8) {
                                if let ownerName = detail.ownerName {
                                    LabeledContent("Organizer", value: ownerName)
                                }
                                LabeledContent("Date", value: detail.date.formatted(.dateTime))
                                LabeledContent("Duration", value: "\(detail.duration) minutes")
                            }
                        }
                        GroupBox("Description") {
                            Text(detail.text.isEmpty ? "No description provided." : detail.text)
                                .font(.body)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }

                        // RSVP Controls
                        GroupBox("Your Response") {
                            VStack(spacing: 10) {
                                HStack(spacing: 12) {
                                    RSVPButton(
                                        label: "Accept",
                                        icon: "checkmark.circle.fill",
                                        color: .green,
                                        isSelected: currentResponse == "accepted",
                                        isLoading: isResponding
                                    ) { await respond("accepted") }

                                    RSVPButton(
                                        label: "Tentative",
                                        icon: "questionmark.circle.fill",
                                        color: .orange,
                                        isSelected: currentResponse == "tentative",
                                        isLoading: isResponding
                                    ) { await respond("tentative") }

                                    RSVPButton(
                                        label: "Decline",
                                        icon: "xmark.circle.fill",
                                        color: .red,
                                        isSelected: currentResponse == "declined",
                                        isLoading: isResponding
                                    ) { await respond("declined") }
                                }
                                if let responseError {
                                    Text(responseError)
                                        .font(.caption)
                                        .foregroundStyle(.red)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                }
                            }
                            .padding(.top, 4)
                        }
                    }
                    .padding()
                }
            } else {
                Text("Failed to load event details").foregroundStyle(.secondary).padding()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(minWidth: 480, minHeight: 360)
        .task {
            guard let account = accountManager.selectedAccount else { isLoading = false; return }
            do {
                let token = try await accountManager.validToken(for: account)
                detail = try await ESIClient.shared.fetch(
                    "/characters/\(account.characterID)/calendar/\(event.eventId)/", token: token
                )
                currentResponse = detail?.response ?? currentResponse
            } catch {}
            isLoading = false
        }
    }

    private func respond(_ response: String) async {
        guard let account = accountManager.selectedAccount else { return }
        isResponding = true
        responseError = nil
        do {
            let token = try await accountManager.validToken(for: account)
            try await ESIClient.shared.put(
                "/characters/\(account.characterID)/calendar/\(event.eventId)/",
                body: ESICalendarResponseRequest(response: response),
                token: token
            )
            currentResponse = response
        } catch {
            responseError = error.localizedDescription
        }
        isResponding = false
    }
}

struct RSVPButton: View {
    let label: String
    let icon: String
    let color: Color
    let isSelected: Bool
    let isLoading: Bool
    let action: () async -> Void

    var body: some View {
        Button {
            Task { await action() }
        } label: {
            Label(label, systemImage: icon)
                .font(.subheadline.weight(isSelected ? .bold : .regular))
                .foregroundStyle(isSelected ? color : .secondary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                .background(isSelected ? color.opacity(0.15) : Color.clear, in: RoundedRectangle(cornerRadius: 8))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(isSelected ? color.opacity(0.4) : Color.secondary.opacity(0.2), lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
        .disabled(isLoading || isSelected)
    }
}
