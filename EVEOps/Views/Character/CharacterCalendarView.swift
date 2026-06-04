import SwiftUI

// MARK:  Item Source

enum CalendarItemSource: String, CaseIterable, Hashable {
    case eveEvent       = "Events"
    case skill          = "Skills"
    case industryJob    = "Industry"
    case piExpiry       = "PI"
    case moonExtract    = "Moon"
    case contractExpiry = "Contracts"
    case marketOrder    = "Market"
    case attributeRemap = "Remap"

    var color: Color {
        switch self {
        case .eveEvent:       return .accentColor
        case .skill:          return .purple
        case .industryJob:    return .orange
        case .piExpiry:       return .green
        case .moonExtract:    return Color(hue: 0.12, saturation: 0.85, brightness: 0.95)
        case .contractExpiry: return .red
        case .marketOrder:    return .cyan
        case .attributeRemap: return .pink
        }
    }

    var icon: String {
        switch self {
        case .eveEvent:       return "calendar"
        case .skill:          return "brain"
        case .industryJob:    return "hammer"
        case .piExpiry:       return "globe.europe.africa"
        case .moonExtract:    return "moon.fill"
        case .contractExpiry: return "doc.text"
        case .marketOrder:    return "cart"
        case .attributeRemap: return "slider.horizontal.3"
        }
    }
}

// MARK:  Calendar Item

enum CalendarItem: Identifiable {
    case eveEvent(ESICalendarEvent)
    case skillCompletion(ESISkillQueue, String)            // queue entry, skill name
    case industryJob(ESIIndustryJob, String?)              // job, product/blueprint name
    case piExpiry(ESIColony, [ESIPlanetPin], String)       // colony, expiring pins, system name
    case moonExtract(ESIMoonExtraction, String?)           // extraction, moon name
    case contractExpiry(ESIContract)
    case marketOrderExpiry(ESIMarketOrder, Date, String?)  // order, computed expiry, type name
    case attributeRemap(Date)

    var id: String {
        switch self {
        case .eveEvent(let e):                return "evt-\(e.eventId)"
        case .skillCompletion(let q, _):      return "skill-\(q.skillId)-\(q.finishedLevel)"
        case .industryJob(let j, _):          return "job-\(j.jobId)"
        case .piExpiry(let c, _, _):          return "pi-\(c.planetId)"
        case .moonExtract(let m, _):          return "moon-\(m.structureId)"
        case .contractExpiry(let c):          return "cont-\(c.contractId)"
        case .marketOrderExpiry(let o, _, _): return "ord-\(o.orderId)"
        case .attributeRemap(let d):          return "remap-\(Int(d.timeIntervalSince1970))"
        }
    }

    var date: Date? {
        switch self {
        case .eveEvent(let e):                return e.eventDate
        case .skillCompletion(let q, _):      return q.finishDate
        case .industryJob(let j, _):          return j.endDate
        case .piExpiry(_, let pins, _):       return pins.compactMap(\.expiryTime).min()
        case .moonExtract(let m, _):          return m.chunkArrivalTime
        case .contractExpiry(let c):          return c.dateExpired
        case .marketOrderExpiry(_, let d, _): return d
        case .attributeRemap(let d):          return d
        }
    }

    var source: CalendarItemSource {
        switch self {
        case .eveEvent:          return .eveEvent
        case .skillCompletion:   return .skill
        case .industryJob:       return .industryJob
        case .piExpiry:          return .piExpiry
        case .moonExtract:       return .moonExtract
        case .contractExpiry:    return .contractExpiry
        case .marketOrderExpiry: return .marketOrder
        case .attributeRemap:    return .attributeRemap
        }
    }

    var title: String {
        switch self {
        case .eveEvent(let e):
            return e.title ?? "Untitled Event"
        case .skillCompletion(let q, let name):
            return "\(name) \(skillRoman(q.finishedLevel))"
        case .industryJob(_, let name):
            return name ?? "Industry Job"
        case .piExpiry(let c, _, let sysName):
            return "\(sysName) · \(c.planetType.capitalized)"
        case .moonExtract(_, let name):
            return name ?? "Moon Chunk Ready"
        case .contractExpiry(let c):
            let t = c.title ?? ""; return t.isEmpty ? "Contract Expires" : t
        case .marketOrderExpiry(let o, _, let name):
            let dir = (o.isBuyOrder == true) ? "Buy" : "Sell"
            return name.map { "\($0) \(dir)" } ?? "\(dir) Order"
        case .attributeRemap:
            return "Attribute Remap Available"
        }
    }

    var color: Color { source.color }
    var icon: String  { source.icon }
}

private func skillRoman(_ level: Int) -> String {
    ["I", "II", "III", "IV", "V"][max(0, min(4, level - 1))]
}

// MARK:  Main View

struct CharacterCalendarView: View {
    @Environment(AccountManager.self) private var accountManager
    @State private var allItems: [CalendarItem] = []
    @State private var isLoading = false
    @State private var error: String?
    @State private var selectedItemID: String?
    @State private var activeFilters: Set<CalendarItemSource> = Set(CalendarItemSource.allCases)
    @State private var eventResponseFilter = "all"
    @State private var selectedDay: Date?
    @State private var displayedMonth: Date = Calendar.current.date(
        from: Calendar.current.dateComponents([.year, .month], from: Date())
    ) ?? Date()

    var body: some View {
        VStack(spacing: 0) {
            filterBar
            if isLoading && allItems.isEmpty {
                ProgressView("Loading…").frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let msg = error, allItems.isEmpty {
                ContentUnavailableView(msg, systemImage: "calendar.badge.exclamationmark")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                CalendarGridView(
                    displayedMonth: $displayedMonth,
                    selectedDay: $selectedDay,
                    itemsByDay: itemsByDay
                )
                .padding(16)
                .onChange(of: selectedDay) { selectedItemID = nil }

                Divider()
                bottomSplit
            }
        }
        .safeAreaInset(edge: .top, spacing: 0) {
            HStack {
                Text("Calendar")
                    .font(.largeTitle.bold())
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(.background)
        }
        .navigationTitle("")
        .task(id: accountManager.selectedCharacterID) { await loadAll() }
    }

    // MARK: Filter Bar

    private var filterBar: some View {
        VStack(spacing: 0) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    Button(allFiltersOn ? "None" : "All") {
                        withAnimation(.easeInOut(duration: 0.15)) {
                            activeFilters = allFiltersOn ? [] : Set(CalendarItemSource.allCases)
                        }
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.mini)
                    .foregroundStyle(.secondary)

                    Divider().frame(height: 18)

                    ForEach(CalendarItemSource.allCases, id: \.self) { source in
                        SourceFilterPill(source: source, isOn: activeFilters.contains(source)) {
                            withAnimation(.easeInOut(duration: 0.15)) {
                                if activeFilters.contains(source) { activeFilters.remove(source) }
                                else { activeFilters.insert(source) }
                            }
                        }
                    }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
            }

            Divider().opacity(0.5)

            HStack(spacing: 10) {
                if activeFilters.contains(.eveEvent) {
                    Picker("Response", selection: $eventResponseFilter) {
                        Text("All Responses").tag("all")
                        Text("Accepted").tag("accepted")
                        Text("Tentative").tag("tentative")
                        Text("Not Responded").tag("not_responded")
                        Text("Declined").tag("declined")
                    }
                    .labelsHidden()
                    .pickerStyle(.segmented)
                    .frame(maxWidth: 460)
                }
                Spacer()
                if isLoading { ProgressView().controlSize(.small) }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .frame(minHeight: 34)
            .background(.bar)
        }
        .background(.bar)
    }

    private var allFiltersOn: Bool { activeFilters.count == CalendarItemSource.allCases.count }

    // MARK: Bottom Split

    private var bottomSplit: some View {
        HSplitView {
            VStack(spacing: 0) {
                listHeader
                Divider()
                listBody
            }
            .frame(minWidth: 240)

            Group {
                if let item = selectedItem {
                    CalendarItemDetailView(item: item).id(item.id)
                } else {
                    emptyDetail
                }
            }
            .frame(minWidth: 300)
        }
    }

    private var emptyDetail: some View {
        VStack(spacing: 10) {
            Image(systemName: "calendar.badge.clock")
                .font(.system(size: 36))
                .foregroundStyle(.tertiary)
            Text("Select an item to view details")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: List

    private var listHeader: some View {
        HStack(spacing: 8) {
            if let day = selectedDay {
                Image(systemName: "calendar")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Color.accentColor)
                Text(day, format: .dateTime.weekday(.abbreviated).month(.abbreviated).day())
                    .font(.subheadline.weight(.medium))
                Spacer()
                Button("Clear") { withAnimation(.easeInOut(duration: 0.15)) { selectedDay = nil } }
                    .buttonStyle(.borderless).font(.caption).foregroundStyle(.secondary)
            } else {
                Image(systemName: "list.bullet")
                    .font(.system(size: 12)).foregroundStyle(.secondary)
                Text("Upcoming").font(.subheadline.weight(.medium))
                Spacer()
            }
            Text("\(dayFilteredItems.count)")
                .font(.caption).foregroundStyle(.tertiary).monospacedDigit()
        }
        .padding(.horizontal, 12).padding(.vertical, 9).background(.bar)
    }

    private var listBody: some View {
        Group {
            if dayFilteredItems.isEmpty {
                Text(selectedDay != nil ? "No events on this day" : "No upcoming events")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(dayFilteredItems, selection: $selectedItemID) { item in
                    CalendarItemRow(item: item)
                }
                .listStyle(.plain)
            }
        }
    }

    // MARK: Computed

    private var selectedItem: CalendarItem? {
        guard let id = selectedItemID else { return nil }
        return allItems.first { $0.id == id }
    }

    private var filteredItems: [CalendarItem] {
        allItems.filter { item in
            guard activeFilters.contains(item.source) else { return false }
            if case .eveEvent(let e) = item {
                return eventResponseFilter == "all" || e.eventResponse == eventResponseFilter
            }
            return true
        }
    }

    private var itemsByDay: [Date: [CalendarItem]] {
        var dict: [Date: [CalendarItem]] = [:]
        for item in filteredItems {
            guard let d = item.date else { continue }
            dict[Calendar.current.startOfDay(for: d), default: []].append(item)
        }
        return dict
    }

    private var dayFilteredItems: [CalendarItem] {
        guard let day = selectedDay else { return filteredItems }
        let start = Calendar.current.startOfDay(for: day)
        return filteredItems.filter {
            guard let d = $0.date else { return false }
            return Calendar.current.startOfDay(for: d) == start
        }
    }

    // MARK: Load

    private func loadAll() async {
        guard let account = accountManager.selectedAccount else { return }
        isLoading = true; error = nil
        do {
            let token  = try await accountManager.validToken(for: account)
            let charID = account.characterID
            let corpID = account.corporationID
            let now    = Date()

            async let calFetch: [ESICalendarEvent]      = ESIClient.shared.fetch("/characters/\(charID)/calendar/", token: token)
            async let skillFetch: [ESISkillQueue]       = ESIClient.shared.fetch("/characters/\(charID)/skillqueue/", token: token)
            async let jobFetch: [ESIIndustryJob]        = ESIClient.shared.fetch("/characters/\(charID)/industry/jobs/", token: token)
            async let contractFetch: [ESIContract]      = ESIClient.shared.fetch("/characters/\(charID)/contracts/", token: token)
            async let orderFetch: [ESIMarketOrder]      = ESIClient.shared.fetch("/characters/\(charID)/orders/", token: token)
            async let attrFetch: ESICharacterAttributes = ESIClient.shared.fetch("/characters/\(charID)/attributes/", token: token)
            async let colonyFetch: [ESIColony]          = ESIClient.shared.fetch("/characters/\(charID)/planets/", token: token)

            let calEvents    = (try? await calFetch)      ?? []
            let skillQueue   = (try? await skillFetch)    ?? []
            let industryJobs = (try? await jobFetch)      ?? []
            let contracts    = (try? await contractFetch) ?? []
            let orders       = (try? await orderFetch)    ?? []
            let attributes   = try? await attrFetch
            let colonies     = (try? await colonyFetch)   ?? []

            // Corp moon extractions — silently fails if no roles (403)
            let moonExtractions: [ESIMoonExtraction] = (try? await ESIClient.shared.fetch(
                "/corporation/\(corpID)/mining/extractions/", token: token
            )) ?? []

            // PI layouts — concurrent per colony
            var piData: [(ESIColony, [ESIPlanetPin])] = []
            await withTaskGroup(of: (ESIColony, [ESIPlanetPin])?.self) { group in
                for colony in colonies {
                    group.addTask {
                        guard let layout: ESIColonyLayout = try? await ESIClient.shared.fetch(
                            "/characters/\(charID)/planets/\(colony.planetId)/", token: token
                        ) else { return nil }
                        let expiring: [ESIPlanetPin] = layout.pins.filter { $0.expiryTime != nil }
                        return expiring.isEmpty ? nil : (colony, expiring)
                    }
                }
                for await r in group { if let r { piData.append(r) } }
            }

            // Name resolution
            let skillIDs   = skillQueue.compactMap { $0.finishDate != nil ? $0.skillId : nil }
            let jobTypeIDs = industryJobs.filter { $0.status == "active" }
                                         .map { $0.productTypeId ?? $0.blueprintTypeId }
            let orderIDs   = orders.map(\.typeId)
            let typeNames  = await UniverseCache.shared.types(ids: Array(Set(skillIDs + jobTypeIDs + orderIDs)))

            let systemNames = await NameResolver.shared.resolve(ids: Array(Set(colonies.map(\.solarSystemId))))

            let moonIDs   = moonExtractions.map(\.moonId)
            let moonNames = moonIDs.isEmpty ? [:] as [Int: String]
                                            : await NameResolver.shared.resolve(ids: moonIDs)

            // Build items
            var items: [CalendarItem] = []

            items += calEvents.map { .eveEvent($0) }

            items += skillQueue
                .filter { $0.finishDate != nil }
                .map { q in .skillCompletion(q, typeNames[q.skillId]?.name ?? "Unknown Skill") }

            items += industryJobs
                .filter { $0.status == "active" }
                .map { j in .industryJob(j, typeNames[j.productTypeId ?? j.blueprintTypeId]?.name) }

            for (colony, pins) in piData {
                items.append(.piExpiry(colony, pins, systemNames[colony.solarSystemId] ?? "Unknown"))
            }

            items += moonExtractions.map { .moonExtract($0, moonNames[$0.moonId]) }

            items += contracts
                .filter { $0.status == "outstanding" && $0.dateExpired > now }
                .map { .contractExpiry($0) }

            let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: now) ?? now
            items += orders.compactMap { o -> CalendarItem? in
                let expiry = o.issued.addingTimeInterval(Double(o.duration) * 86400)
                guard expiry > yesterday else { return nil }
                return .marketOrderExpiry(o, expiry, typeNames[o.typeId]?.name)
            }

            if let remapDate = attributes?.accruedRemapCooldownDate, remapDate > now {
                items.append(.attributeRemap(remapDate))
            }

            allItems = items.sorted { ($0.date ?? .distantFuture) < ($1.date ?? .distantFuture) }
        } catch {
            self.error = error.localizedDescription
        }
        isLoading = false
    }
}

// MARK:  Source Filter Pill

private struct SourceFilterPill: View {
    let source: CalendarItemSource
    let isOn: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(source.rawValue, systemImage: source.icon)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(isOn ? source.color : .secondary)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(isOn ? source.color.opacity(0.15) : Color.clear, in: Capsule())
                .overlay(Capsule().stroke(
                    isOn ? source.color.opacity(0.4) : Color.secondary.opacity(0.25),
                    lineWidth: 1
                ))
        }
        .buttonStyle(.plain)
    }
}

// MARK:  Calendar Grid

private struct CalendarGridView: View {
    @Binding var displayedMonth: Date
    @Binding var selectedDay: Date?
    let itemsByDay: [Date: [CalendarItem]]

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
                    .frame(width: 36, height: 36).contentShape(Rectangle())
            }
            .buttonStyle(.plain).foregroundStyle(.secondary)

            Spacer()

            VStack(spacing: 2) {
                Text(displayedMonth, format: .dateTime.month(.wide).year())
                    .font(.system(size: 15, weight: .semibold)).monospacedDigit()
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
                    .frame(width: 36, height: 36).contentShape(Rectangle())
            }
            .buttonStyle(.plain).foregroundStyle(.secondary)
        }
        .padding(.horizontal, 8).padding(.top, 10).padding(.bottom, 6)
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
                    items: itemsByDay[cal.startOfDay(for: date)] ?? []
                )
                .onTapGesture { handleDayTap(date) }
            }
        }
        .padding(.horizontal, 8).padding(.bottom, 10).padding(.top, 4)
        .id(displayedMonth)
        .transition(.opacity)
        .animation(.easeInOut(duration: 0.15), value: displayedMonth)
    }

    private var calendarDays: [Date] {
        guard let interval = cal.dateInterval(of: .month, for: displayedMonth),
              let count = cal.range(of: .day, in: .month, for: displayedMonth)?.count else { return [] }
        let firstDay = interval.start
        let offset = (cal.component(.weekday, from: firstDay) + 5) % 7
        let total  = ((offset + count + 6) / 7) * 7
        let start  = cal.date(byAdding: .day, value: -offset, to: firstDay) ?? firstDay
        return (0..<total).compactMap { cal.date(byAdding: .day, value: $0, to: start) }
    }

    private var isCurrentMonth: Bool {
        cal.isDate(displayedMonth, equalTo: Date(), toGranularity: .month)
    }

    private func handleDayTap(_ date: Date) {
        let already = selectedDay.map { cal.isDate(date, inSameDayAs: $0) } ?? false
        withAnimation(.easeInOut(duration: 0.12)) { selectedDay = already ? nil : date }
        if !cal.isDate(date, equalTo: displayedMonth, toGranularity: .month) {
            let comps = cal.dateComponents([.year, .month], from: date)
            withAnimation(.easeInOut(duration: 0.2)) { displayedMonth = cal.date(from: comps) ?? date }
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

// MARK:  Day Cell

private struct CalendarDayCell: View {
    let date: Date
    let isCurrentMonth: Bool
    let isSelected: Bool
    let isToday: Bool
    let items: [CalendarItem]

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
            // One dot per distinct source category present on this day
            HStack(spacing: 3) {
                let dots = categoryDots
                if dots.isEmpty {
                    Color.clear.frame(width: 5, height: 5)
                } else {
                    ForEach(Array(dots.prefix(5).enumerated()), id: \.offset) { _, src in
                        Circle()
                            .fill(isSelected ? Color.white.opacity(0.85) : src.color)
                            .frame(width: 5, height: 5)
                    }
                    if dots.count > 5 {
                        Text("+").font(.system(size: 7, weight: .bold)).foregroundStyle(.secondary)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 3)
        .opacity(isCurrentMonth ? 1.0 : 0.28)
    }

    private var categoryDots: [CalendarItemSource] {
        var seen = Set<CalendarItemSource>()
        var result: [CalendarItemSource] = []
        for item in items {
            if seen.insert(item.source).inserted { result.append(item.source) }
        }
        return result
    }
}

// MARK:  Item Row

private struct CalendarItemRow: View {
    let item: CalendarItem

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: item.icon)
                .foregroundStyle(item.color)
                .font(.body)
                .frame(width: 20)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 5) {
                    Text(item.title)
                        .font(.subheadline)
                        .lineLimit(1)
                    if case .eveEvent(let e) = item, (e.importance ?? 0) > 0 {
                        Image(systemName: "exclamationmark.circle.fill")
                            .foregroundStyle(.orange).font(.caption2)
                    }
                }
                if let d = item.date {
                    Text(d, style: .relative)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.vertical, 1)
    }
}

// MARK:  Detail Dispatcher

struct CalendarItemDetailView: View {
    let item: CalendarItem

    @ViewBuilder
    var body: some View {
        switch item {
        case .eveEvent(let e):
            CalendarEventDetailPanel(event: e)
        case .skillCompletion(let q, let name):
            SkillDeadlineView(queue: q, skillName: name)
        case .industryJob(let j, let name):
            IndustryJobDeadlineView(job: j, name: name)
        case .piExpiry(let colony, let pins, let sysName):
            PIExpiryDetailView(colony: colony, pins: pins, systemName: sysName)
        case .moonExtract(let m, let name):
            MoonExtractionDetailView(extraction: m, moonName: name)
        case .contractExpiry(let c):
            ContractDeadlineView(contract: c)
        case .marketOrderExpiry(let o, let expiry, let name):
            MarketOrderDeadlineView(order: o, expiry: expiry, typeName: name)
        case .attributeRemap(let d):
            AttributeRemapDetailView(remapDate: d)
        }
    }
}

// MARK:  Shared Detail Header

private struct DeadlineHeader: View {
    let title: String
    let source: CalendarItemSource
    let date: Date?

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Image(systemName: source.icon)
                        .foregroundStyle(source.color)
                        .font(.title3)
                    Text(title)
                        .font(.headline)
                        .lineLimit(2)
                }
                if let d = date {
                    Text(d, format: .dateTime.weekday(.abbreviated).month(.abbreviated).day().hour().minute())
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            Label(source.rawValue, systemImage: source.icon)
                .font(.caption.weight(.medium))
                .foregroundStyle(source.color)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(source.color.opacity(0.12), in: Capsule())
        }
        .padding(16)
        .background(.bar)
    }
}

// MARK:  Skill Deadline

private struct SkillDeadlineView: View {
    let queue: ESISkillQueue
    let skillName: String

    var body: some View {
        VStack(spacing: 0) {
            DeadlineHeader(
                title: "\(skillName) \(skillRoman(queue.finishedLevel))",
                source: .skill,
                date: queue.finishDate
            )
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    GroupBox {
                        Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 6) {
                            GridRow {
                                Text("Skill").foregroundStyle(.secondary)
                                Text(skillName)
                            }
                            GridRow {
                                Text("Level").foregroundStyle(.secondary)
                                Text(skillRoman(queue.finishedLevel))
                                    .foregroundStyle(.purple).fontWeight(.semibold)
                            }
                            GridRow {
                                Text("Queue Position").foregroundStyle(.secondary)
                                Text("\(queue.queuePosition + 1)")
                            }
                            if let start = queue.startDate {
                                GridRow {
                                    Text("Started").foregroundStyle(.secondary)
                                    Text(start, style: .date)
                                }
                            }
                            if let finish = queue.finishDate {
                                GridRow {
                                    Text("Completes").foregroundStyle(.secondary)
                                    Text(finish, format: .dateTime.month(.abbreviated).day().hour().minute())
                                }
                                GridRow {
                                    Text("Time Left").foregroundStyle(.secondary)
                                    Text(finish, style: .relative)
                                        .foregroundStyle(finish > Date() ? Color.primary : Color.green)
                                }
                            }
                        }
                        .font(.subheadline)
                    } label: {
                        Label("Skill Training", systemImage: "brain")
                            .font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                    }
                }
                .padding(16)
            }
        }
    }
}

// MARK:  Industry Job Deadline

private struct IndustryJobDeadlineView: View {
    let job: ESIIndustryJob
    let name: String?

    var body: some View {
        VStack(spacing: 0) {
            DeadlineHeader(title: name ?? "Industry Job", source: .industryJob, date: job.endDate)
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    GroupBox {
                        Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 6) {
                            GridRow {
                                Text("Activity").foregroundStyle(.secondary)
                                Text(activityName(job.activityId))
                                    .foregroundStyle(.orange).fontWeight(.semibold)
                            }
                            GridRow {
                                Text("Runs").foregroundStyle(.secondary)
                                Text("\(job.runs)")
                            }
                            GridRow {
                                Text("Status").foregroundStyle(.secondary)
                                Text(job.status.capitalized)
                            }
                            GridRow {
                                Text("Started").foregroundStyle(.secondary)
                                Text(job.startDate, format: .dateTime.month(.abbreviated).day().hour().minute())
                            }
                            GridRow {
                                Text("Completes").foregroundStyle(.secondary)
                                Text(job.endDate, format: .dateTime.month(.abbreviated).day().hour().minute())
                            }
                            GridRow {
                                Text("Time Left").foregroundStyle(.secondary)
                                Text(job.endDate, style: .relative)
                                    .foregroundStyle(job.endDate > Date() ? Color.primary : Color.green)
                            }
                            if let cost = job.cost, cost > 0 {
                                GridRow {
                                    Text("Cost").foregroundStyle(.secondary)
                                    Text("\(cost, format: .number.precision(.fractionLength(0))) ISK")
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                        .font(.subheadline)
                    } label: {
                        Label("Job Details", systemImage: "hammer")
                            .font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                    }
                }
                .padding(16)
            }
        }
    }

    private func activityName(_ id: Int) -> String {
        switch id {
        case 1:  return "Manufacturing"
        case 3:  return "TE Research"
        case 4:  return "ME Research"
        case 5:  return "Copying"
        case 7:  return "Reverse Engineering"
        case 8:  return "Invention"
        case 11: return "Reactions"
        default: return "Activity \(id)"
        }
    }
}

// MARK:  PI Expiry Detail

private struct PIExpiryDetailView: View {
    let colony: ESIColony
    let pins: [ESIPlanetPin]
    let systemName: String

    private var sortedPins: [ESIPlanetPin] {
        pins.compactMap { $0.expiryTime != nil ? $0 : nil }
            .sorted { ($0.expiryTime ?? .distantFuture) < ($1.expiryTime ?? .distantFuture) }
    }

    var body: some View {
        VStack(spacing: 0) {
            DeadlineHeader(
                title: "\(systemName) · \(colony.planetType.capitalized)",
                source: .piExpiry,
                date: sortedPins.first?.expiryTime
            )
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    GroupBox {
                        Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 6) {
                            GridRow {
                                Text("System").foregroundStyle(.secondary)
                                Text(systemName)
                            }
                            GridRow {
                                Text("Planet Type").foregroundStyle(.secondary)
                                Text(colony.planetType.capitalized)
                                    .foregroundStyle(.green).fontWeight(.semibold)
                            }
                            GridRow {
                                Text("Extractors").foregroundStyle(.secondary)
                                Text("\(sortedPins.count)")
                            }
                        }
                        .font(.subheadline)
                    } label: {
                        Label("Colony Info", systemImage: "globe.europe.africa")
                            .font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                    }

                    GroupBox {
                        VStack(alignment: .leading, spacing: 8) {
                            ForEach(sortedPins) { pin in
                                if let expiry = pin.expiryTime {
                                    let num = (sortedPins.firstIndex(where: { $0.pinId == pin.pinId }) ?? 0) + 1
                                    HStack {
                                        Image(systemName: "circle.fill")
                                            .font(.system(size: 6))
                                            .foregroundStyle(.green.opacity(0.8))
                                        Text("Extractor \(num)").font(.subheadline)
                                        Spacer()
                                        VStack(alignment: .trailing, spacing: 1) {
                                            Text(expiry, style: .relative)
                                                .font(.caption)
                                                .foregroundStyle(expiry > Date() ? Color.secondary : Color.red)
                                            Text(expiry, format: .dateTime.month(.abbreviated).day().hour().minute())
                                                .font(.caption2).foregroundStyle(.tertiary)
                                        }
                                    }
                                    if pin.pinId != sortedPins.last?.pinId { Divider() }
                                }
                            }
                        }
                    } label: {
                        Label("Extractor Expiry", systemImage: "arrow.down.circle")
                            .font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                    }
                }
                .padding(16)
            }
        }
    }
}

// MARK:  Moon Extraction Detail

private struct MoonExtractionDetailView: View {
    let extraction: ESIMoonExtraction
    let moonName: String?

    var body: some View {
        VStack(spacing: 0) {
            DeadlineHeader(
                title: moonName ?? "Moon Chunk Ready",
                source: .moonExtract,
                date: extraction.chunkArrivalTime
            )
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    GroupBox {
                        Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 6) {
                            GridRow {
                                Text("Moon").foregroundStyle(.secondary)
                                Text(moonName ?? "#\(extraction.moonId)")
                            }
                            GridRow {
                                Text("Extraction Start").foregroundStyle(.secondary)
                                Text(extraction.extractionStartTime,
                                     format: .dateTime.month(.abbreviated).day().hour().minute())
                            }
                            GridRow {
                                Text("Chunk Arrives").foregroundStyle(.secondary)
                                Text(extraction.chunkArrivalTime,
                                     format: .dateTime.month(.abbreviated).day().hour().minute())
                            }
                            GridRow {
                                Text("Time Until Pop").foregroundStyle(.secondary)
                                Text(extraction.chunkArrivalTime, style: .relative)
                                    .foregroundStyle(extraction.chunkArrivalTime > Date()
                                        ? .primary
                                        : Color(hue: 0.12, saturation: 0.85, brightness: 0.95))
                            }
                            GridRow {
                                Text("Auto-fires").foregroundStyle(.secondary)
                                Text(extraction.naturalDecayTime,
                                     format: .dateTime.month(.abbreviated).day().hour().minute())
                            }
                            GridRow {
                                Text("Decay In").foregroundStyle(.secondary)
                                Text(extraction.naturalDecayTime, style: .relative)
                                    .foregroundStyle(.red)
                            }
                        }
                        .font(.subheadline)
                    } label: {
                        Label("Extraction Details", systemImage: "moon.fill")
                            .font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                    }
                }
                .padding(16)
            }
        }
    }
}

// MARK:  Contract Deadline

private struct ContractDeadlineView: View {
    let contract: ESIContract

    var body: some View {
        let heading = contract.title.flatMap { $0.isEmpty ? nil : $0 } ?? contractTypeName(contract.type)
        VStack(spacing: 0) {
            DeadlineHeader(title: heading, source: .contractExpiry, date: contract.dateExpired)
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    GroupBox {
                        Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 6) {
                            GridRow {
                                Text("Type").foregroundStyle(.secondary)
                                Text(contractTypeName(contract.type))
                                    .foregroundStyle(.red).fontWeight(.semibold)
                            }
                            GridRow {
                                Text("Availability").foregroundStyle(.secondary)
                                Text(contract.availability.capitalized)
                            }
                            GridRow {
                                Text("Issued").foregroundStyle(.secondary)
                                Text(contract.dateIssued, format: .dateTime.month(.abbreviated).day().year())
                            }
                            GridRow {
                                Text("Expires").foregroundStyle(.secondary)
                                Text(contract.dateExpired, format: .dateTime.month(.abbreviated).day().year())
                            }
                            GridRow {
                                Text("Time Left").foregroundStyle(.secondary)
                                Text(contract.dateExpired, style: .relative)
                                    .foregroundStyle(contract.dateExpired > Date() ? Color.primary : Color.red)
                            }
                            if let price = contract.price, price > 0 {
                                GridRow {
                                    Text("Price").foregroundStyle(.secondary)
                                    Text("\(price, format: .number.precision(.fractionLength(0))) ISK")
                                }
                            }
                            if let reward = contract.reward, reward > 0 {
                                GridRow {
                                    Text("Reward").foregroundStyle(.secondary)
                                    Text("\(reward, format: .number.precision(.fractionLength(0))) ISK")
                                }
                            }
                            if let collateral = contract.collateral, collateral > 0 {
                                GridRow {
                                    Text("Collateral").foregroundStyle(.secondary)
                                    Text("\(collateral, format: .number.precision(.fractionLength(0))) ISK")
                                }
                            }
                        }
                        .font(.subheadline)
                    } label: {
                        Label("Contract Details", systemImage: "doc.text")
                            .font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                    }
                }
                .padding(16)
            }
        }
    }

    private func contractTypeName(_ type: String) -> String {
        switch type {
        case "item_exchange": return "Item Exchange"
        case "auction":       return "Auction"
        case "courier":       return "Courier"
        case "loan":          return "Loan"
        default:              return type.replacingOccurrences(of: "_", with: " ").capitalized
        }
    }
}

// MARK:  Market Order Deadline

private struct MarketOrderDeadlineView: View {
    let order: ESIMarketOrder
    let expiry: Date
    let typeName: String?

    var body: some View {
        let isBuy   = order.isBuyOrder == true
        let dir     = isBuy ? "Buy" : "Sell"
        let heading = typeName.map { "\($0) \(dir) Order" } ?? "\(dir) Order"
        VStack(spacing: 0) {
            DeadlineHeader(title: heading, source: .marketOrder, date: expiry)
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    GroupBox {
                        Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 6) {
                            GridRow {
                                Text("Item").foregroundStyle(.secondary)
                                Text(typeName ?? "#\(order.typeId)")
                            }
                            GridRow {
                                Text("Type").foregroundStyle(.secondary)
                                Text(isBuy ? "Buy Order" : "Sell Order")
                                    .foregroundStyle(.cyan).fontWeight(.semibold)
                            }
                            GridRow {
                                Text("Price").foregroundStyle(.secondary)
                                Text("\(order.price, format: .number.precision(.fractionLength(2))) ISK")
                            }
                            GridRow {
                                Text("Volume").foregroundStyle(.secondary)
                                Text("\(order.volumeRemain) / \(order.volumeTotal)")
                            }
                            GridRow {
                                Text("Range").foregroundStyle(.secondary)
                                Text(order.range.replacingOccurrences(of: "_", with: " ").capitalized)
                            }
                            GridRow {
                                Text("Duration").foregroundStyle(.secondary)
                                Text("\(order.duration) days")
                            }
                            GridRow {
                                Text("Expires").foregroundStyle(.secondary)
                                Text(expiry, format: .dateTime.month(.abbreviated).day().year())
                            }
                            GridRow {
                                Text("Time Left").foregroundStyle(.secondary)
                                Text(expiry, style: .relative)
                                    .foregroundStyle(expiry > Date() ? Color.primary : Color.red)
                            }
                        }
                        .font(.subheadline)
                    } label: {
                        Label("Order Details", systemImage: "cart")
                            .font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                    }
                }
                .padding(16)
            }
        }
    }
}

// MARK:  Attribute Remap Detail

private struct AttributeRemapDetailView: View {
    let remapDate: Date

    var body: some View {
        VStack(spacing: 0) {
            DeadlineHeader(title: "Attribute Remap Available", source: .attributeRemap, date: remapDate)
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    GroupBox {
                        Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 6) {
                            GridRow {
                                Text("Available On").foregroundStyle(.secondary)
                                Text(remapDate, format: .dateTime.month(.wide).day().year())
                            }
                            GridRow {
                                Text("Time Until").foregroundStyle(.secondary)
                                Text(remapDate, style: .relative)
                                    .foregroundStyle(remapDate > Date() ? Color.primary : Color.pink)
                            }
                        }
                        .font(.subheadline)
                    } label: {
                        Label("Remap Cooldown", systemImage: "slider.horizontal.3")
                            .font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                    }

                    GroupBox {
                        Text("When the cooldown expires you can reassign your base attributes (Charisma, Intelligence, Memory, Perception, Willpower) to optimise training time for a new skill plan.")
                            .font(.subheadline)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    } label: {
                        Label("About Remaps", systemImage: "info.circle")
                            .font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                    }
                }
                .padding(16)
            }
        }
    }
}

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
            } catch {}
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
                        Text(detail.text)
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
