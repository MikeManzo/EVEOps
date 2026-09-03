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

    var title: LocalizedStringKey {
        switch self {
        case .eveEvent:       "Events"
        case .skill:          "Skills"
        case .industryJob:    "Industry"
        case .piExpiry:       "PI"
        case .moonExtract:    "Moon"
        case .contractExpiry: "Contracts"
        case .marketOrder:    "Market"
        case .attributeRemap: "Remap"
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
