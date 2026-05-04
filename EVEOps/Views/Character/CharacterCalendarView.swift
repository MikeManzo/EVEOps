import SwiftUI

// MARK: - Main View

struct CharacterCalendarView: View {
    @Environment(AccountManager.self) private var accountManager
    @State private var events: [ESICalendarEvent] = []
    @State private var isLoading = false
    @State private var error: String?
    @State private var selectedEventID: ESICalendarEvent.ID? = nil
    @State private var responseFilter = "all"
    @State private var selectedDay: Date? = nil
    @State private var displayedMonth: Date = Calendar.current.date(
        from: Calendar.current.dateComponents([.year, .month], from: Date())
    ) ?? Date()

    var body: some View {
        VStack(spacing: 0) {
            filterBar
            if isLoading {
                ProgressView("Loading…").frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let msg = error {
                ContentUnavailableView(msg, systemImage: "calendar.badge.exclamationmark")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                CalendarGridView(
                    displayedMonth: $displayedMonth,
                    selectedDay: $selectedDay,
                    eventsByDay: eventsByDay
                )
                .padding(16)
                .onChange(of: selectedDay) { selectedEventID = nil }

                Divider()
                bottomSplit
            }
        }
        .navigationTitle("Calendar")
        .task(id: accountManager.selectedCharacterID) { await loadEvents() }
    }

    // MARK: - Filter Bar

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

    // MARK: - Bottom Split

    private var bottomSplit: some View {
        HSplitView {
            // Left: event list
            VStack(spacing: 0) {
                eventListHeader
                Divider()
                eventListBody
            }
            .frame(minWidth: 220)

            // Right: event detail
            Group {
                if let event = selectedEvent {
                    CalendarEventDetailPanel(event: event)
                        .id(event.eventId)
                } else {
                    emptyDetailState
                }
            }
            .frame(minWidth: 280)
        }
    }

    private var emptyDetailState: some View {
        VStack(spacing: 10) {
            Image(systemName: "calendar.badge.clock")
                .font(.system(size: 36))
                .foregroundStyle(.tertiary)
            Text("Select an event to view details")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Event List

    private var eventListHeader: some View {
        HStack(spacing: 8) {
            if let day = selectedDay {
                Image(systemName: "calendar")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Color.accentColor)
                Text(day, format: .dateTime.weekday(.abbreviated).month(.abbreviated).day())
                    .font(.subheadline.weight(.medium))
                Spacer()
                Button("Clear") {
                    withAnimation(.easeInOut(duration: 0.15)) { selectedDay = nil }
                }
                .buttonStyle(.borderless)
                .font(.caption)
                .foregroundStyle(.secondary)
            } else {
                Image(systemName: "list.bullet")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                Text("Upcoming Events")
                    .font(.subheadline.weight(.medium))
                Spacer()
            }
            Text("\(dayFilteredEvents.count)")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .monospacedDigit()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(.bar)
    }

    private var eventListBody: some View {
        Group {
            if dayFilteredEvents.isEmpty {
                Text(selectedDay != nil ? "No events on this day" : "No upcoming events")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(dayFilteredEvents, selection: $selectedEventID) { event in
                    CalendarEventRow(event: event)
                }
                .listStyle(.plain)
            }
        }
    }

    // MARK: - Helpers

    private var selectedEvent: ESICalendarEvent? {
        guard let id = selectedEventID else { return nil }
        return events.first { $0.id == id }
    }

    private var filteredEvents: [ESICalendarEvent] {
        responseFilter == "all" ? events : events.filter { $0.eventResponse == responseFilter }
    }

    private var dayFilteredEvents: [ESICalendarEvent] {
        guard let day = selectedDay else { return filteredEvents }
        let start = Calendar.current.startOfDay(for: day)
        return filteredEvents.filter {
            guard let d = $0.eventDate else { return false }
            return Calendar.current.startOfDay(for: d) == start
        }
    }

    private var eventsByDay: [Date: [ESICalendarEvent]] {
        var dict: [Date: [ESICalendarEvent]] = [:]
        for event in filteredEvents {
            guard let d = event.eventDate else { continue }
            dict[Calendar.current.startOfDay(for: d), default: []].append(event)
        }
        return dict
    }

    private func loadEvents() async {
        guard let account = accountManager.selectedAccount else { return }
        isLoading = true; error = nil
        do {
            let token = try await accountManager.validToken(for: account)
            let loaded: [ESICalendarEvent] = try await ESIClient.shared.fetch(
                "/characters/\(account.characterID)/calendar/", token: token
            )
            events = loaded.sorted { ($0.eventDate ?? .distantFuture) < ($1.eventDate ?? .distantFuture) }
        } catch { self.error = error.localizedDescription }
        isLoading = false
    }
}

// MARK: - Calendar Grid

private struct CalendarGridView: View {
    @Binding var displayedMonth: Date
    @Binding var selectedDay: Date?
    let eventsByDay: [Date: [ESICalendarEvent]]

    private let cal = Calendar.current
    private let columns = Array(repeating: GridItem(.flexible(), spacing: 2), count: 7)
    private let weekdayLabels = ["Mo", "Tu", "We", "Th", "Fr", "Sa", "Su"]

    var body: some View {
        VStack(spacing: 0) {
            monthHeader
            weekdayHeader
            Divider().opacity(0.4)
            dayGrid
        }
        .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.primary.opacity(0.1), lineWidth: 1))
    }

    private var monthHeader: some View {
        HStack(spacing: 0) {
            Button(action: prevMonth) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 13, weight: .semibold))
                    .frame(width: 36, height: 36)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)

            Spacer()

            VStack(spacing: 2) {
                Text(displayedMonth, format: .dateTime.month(.wide).year())
                    .font(.system(size: 15, weight: .semibold))
                    .monospacedDigit()
                if !isCurrentMonth {
                    Button("Today") { jumpToToday() }
                        .buttonStyle(.borderless)
                        .font(.system(size: 11))
                        .foregroundStyle(Color.accentColor)
                }
            }

            Spacer()

            Button(action: nextMonth) {
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .frame(width: 36, height: 36)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 8)
        .padding(.top, 10)
        .padding(.bottom, 6)
    }

    private var weekdayHeader: some View {
        LazyVGrid(columns: columns, spacing: 2) {
            ForEach(weekdayLabels, id: \.self) { label in
                Text(label)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
            }
        }
        .padding(.horizontal, 8)
    }

    private var dayGrid: some View {
        LazyVGrid(columns: columns, spacing: 2) {
            ForEach(calendarDays, id: \.self) { date in
                CalendarDayCell(
                    date: date,
                    isCurrentMonth: cal.isDate(date, equalTo: displayedMonth, toGranularity: .month),
                    isSelected: selectedDay.map { cal.isDate(date, inSameDayAs: $0) } ?? false,
                    isToday: cal.isDateInToday(date),
                    events: eventsByDay[cal.startOfDay(for: date)] ?? []
                )
                .onTapGesture { handleDayTap(date) }
            }
        }
        .padding(.horizontal, 8)
        .padding(.bottom, 10)
        .padding(.top, 4)
        .id(displayedMonth)
        .transition(.opacity)
        .animation(.easeInOut(duration: 0.15), value: displayedMonth)
    }

    private var calendarDays: [Date] {
        guard let interval = cal.dateInterval(of: .month, for: displayedMonth),
              let count = cal.range(of: .day, in: .month, for: displayedMonth)?.count else { return [] }
        let firstDay = interval.start
        let offset = (cal.component(.weekday, from: firstDay) + 5) % 7
        let total = ((offset + count + 6) / 7) * 7
        let start = cal.date(byAdding: .day, value: -offset, to: firstDay) ?? firstDay
        return (0..<total).compactMap { cal.date(byAdding: .day, value: $0, to: start) }
    }

    private var isCurrentMonth: Bool {
        cal.isDate(displayedMonth, equalTo: Date(), toGranularity: .month)
    }

    private func handleDayTap(_ date: Date) {
        let alreadySelected = selectedDay.map { cal.isDate(date, inSameDayAs: $0) } ?? false
        withAnimation(.easeInOut(duration: 0.12)) {
            selectedDay = alreadySelected ? nil : date
        }
        if !cal.isDate(date, equalTo: displayedMonth, toGranularity: .month) {
            let components = cal.dateComponents([.year, .month], from: date)
            withAnimation(.easeInOut(duration: 0.2)) {
                displayedMonth = cal.date(from: components) ?? date
            }
        }
    }

    private func prevMonth() {
        withAnimation(.easeInOut(duration: 0.2)) {
            displayedMonth = cal.date(byAdding: .month, value: -1, to: displayedMonth) ?? displayedMonth
        }
    }

    private func nextMonth() {
        withAnimation(.easeInOut(duration: 0.2)) {
            displayedMonth = cal.date(byAdding: .month, value: 1, to: displayedMonth) ?? displayedMonth
        }
    }

    private func jumpToToday() {
        withAnimation(.easeInOut(duration: 0.2)) {
            displayedMonth = cal.date(from: cal.dateComponents([.year, .month], from: Date())) ?? Date()
            selectedDay = nil
        }
    }
}

// MARK: - Day Cell

private struct CalendarDayCell: View {
    let date: Date
    let isCurrentMonth: Bool
    let isSelected: Bool
    let isToday: Bool
    let events: [ESICalendarEvent]

    private let cal = Calendar.current

    var body: some View {
        VStack(spacing: 3) {
            ZStack {
                if isSelected {
                    Circle().fill(Color.accentColor).frame(width: 28, height: 28)
                } else if isToday {
                    Circle().strokeBorder(Color.accentColor, lineWidth: 1.5).frame(width: 28, height: 28)
                }
                Text("\(cal.component(.day, from: date))")
                    .font(.system(size: 12, weight: isSelected || isToday ? .semibold : .regular))
                    .foregroundStyle(isSelected ? Color.white : (isToday ? Color.accentColor : Color.primary))
                    .monospacedDigit()
            }
            HStack(spacing: 3) {
                if events.isEmpty {
                    Color.clear.frame(width: 5, height: 5)
                } else {
                    ForEach(Array(events.prefix(3).enumerated()), id: \.offset) { _, event in
                        Circle()
                            .fill(dotColor(event.eventResponse ?? "not_responded"))
                            .frame(width: 5, height: 5)
                    }
                    if events.count > 3 {
                        Text("+").font(.system(size: 7, weight: .bold)).foregroundStyle(.secondary)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 3)
        .opacity(isCurrentMonth ? 1.0 : 0.28)
    }

    private func dotColor(_ response: String) -> Color {
        if isSelected { return .white.opacity(0.8) }
        switch response {
        case "accepted": return .green
        case "declined": return .red
        case "tentative": return .orange
        default: return Color.accentColor.opacity(0.8)
        }
    }
}

// MARK: - Event Row

struct CalendarEventRow: View {
    let event: ESICalendarEvent

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: responseIcon(event.eventResponse ?? "not_responded"))
                .foregroundStyle(responseColor(event.eventResponse ?? "not_responded"))
                .font(.body)
                .frame(width: 20)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 5) {
                    Text(event.title ?? "Untitled Event")
                        .font(.subheadline)
                        .lineLimit(1)
                    if (event.importance ?? 0) > 0 {
                        Image(systemName: "exclamationmark.circle.fill")
                            .foregroundStyle(.orange).font(.caption2)
                    }
                }
                if let date = event.eventDate {
                    Text(date, style: .date)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.vertical, 1)
    }

    private func responseIcon(_ r: String) -> String {
        switch r {
        case "accepted": return "checkmark.circle.fill"
        case "declined": return "xmark.circle.fill"
        case "tentative": return "questionmark.circle.fill"
        default: return "circle"
        }
    }

    private func responseColor(_ r: String) -> Color {
        switch r {
        case "accepted": return .green
        case "declined": return .red
        case "tentative": return .orange
        default: return .secondary
        }
    }
}

// MARK: - Event Detail Panel

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
            } catch {}
            isLoading = false
        }
    }

    // MARK: Header

    private var detailHeader: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(event.title ?? "Untitled Event")
                        .font(.headline)
                    if (event.importance ?? 0) > 0 {
                        Image(systemName: "exclamationmark.circle.fill")
                            .foregroundStyle(.orange)
                            .font(.subheadline)
                    }
                }
                if let date = event.eventDate {
                    Text(date, format: .dateTime.weekday(.wide).month(.wide).day().hour().minute())
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            // Response badge
            Label(responseLabel(currentResponse), systemImage: responseIcon(currentResponse))
                .font(.caption.weight(.medium))
                .foregroundStyle(responseColor(currentResponse))
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(responseColor(currentResponse).opacity(0.12), in: Capsule())
        }
        .padding(16)
        .background(.bar)
    }

    // MARK: Body

    private func detailBody(_ detail: ESICalendarEventDetail) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {

                // Info
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
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                }

                // Description
                if !detail.text.isEmpty {
                    GroupBox {
                        Text(detail.text)
                            .font(.subheadline)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    } label: {
                        Label("Description", systemImage: "text.alignleft")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                }

                // RSVP
                GroupBox {
                    VStack(spacing: 8) {
                        HStack(spacing: 8) {
                            RSVPButton(label: "Accept", icon: "checkmark.circle.fill", color: .green,
                                       isSelected: currentResponse == "accepted", isLoading: isResponding)
                            { await respond("accepted") }
                            RSVPButton(label: "Tentative", icon: "questionmark.circle.fill", color: .orange,
                                       isSelected: currentResponse == "tentative", isLoading: isResponding)
                            { await respond("tentative") }
                            RSVPButton(label: "Decline", icon: "xmark.circle.fill", color: .red,
                                       isSelected: currentResponse == "declined", isLoading: isResponding)
                            { await respond("declined") }
                        }
                        if let responseError {
                            Text(responseError).font(.caption).foregroundStyle(.red)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                } label: {
                    Label("Your Response", systemImage: "hand.raised")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
            }
            .padding(16)
        }
    }

    // MARK: Helpers

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
        case "accepted": return "checkmark.circle.fill"
        case "declined": return "xmark.circle.fill"
        case "tentative": return "questionmark.circle.fill"
        default: return "circle"
        }
    }

    private func responseColor(_ r: String) -> Color {
        switch r {
        case "accepted": return .green
        case "declined": return .red
        case "tentative": return .orange
        default: return .secondary
        }
    }

    private func responseLabel(_ r: String) -> String {
        r.replacingOccurrences(of: "_", with: " ").capitalized
    }
}

// MARK: - RSVP Button

struct RSVPButton: View {
    let label: String
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
