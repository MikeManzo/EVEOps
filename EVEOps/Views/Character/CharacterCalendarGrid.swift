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

// MARK:  Source Filter Pill

struct SourceFilterPill: View {
    let source: CalendarItemSource
    let isOn: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(source.title, systemImage: source.icon)
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

struct CalendarGridView: View {
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

struct CalendarDayCell: View {
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

struct CalendarItemRow: View {
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
