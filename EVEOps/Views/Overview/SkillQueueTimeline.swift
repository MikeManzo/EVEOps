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

/// The skill queue as a horizontal timeline from now to the moment it runs dry: one
/// segment per skill, sized by remaining training time, labelled with its level where it
/// fits, and a warning tint on the end when the queue empties within a day — so "is my
/// queue about to run out?" is answerable without reading the list.
struct SkillQueueTimeline: View {
    let queue: [TrainingQueueEntry]
    let tint: Color

    private struct Segment: Identifiable {
        let entry: TrainingQueueEntry
        let start: Date
        let end: Date
        var id: String { "\(entry.skillId)-\(entry.level)" }
    }

    private static let warningWindow: TimeInterval = 24 * 3600

    var body: some View {
        TimelineView(.periodic(from: .now, by: 60)) { context in
            let now = context.date
            let segments = self.segments(now: now)
            if let first = segments.first, let last = segments.last {
                let total = max(last.end.timeIntervalSince(first.start), 1)
                let remaining = last.end.timeIntervalSince(now)
                let endsSoon = remaining < Self.warningWindow
                VStack(alignment: .leading, spacing: EVESpacing.sm) {
                    GeometryReader { geo in
                        HStack(spacing: 1.5) {
                            ForEach(Array(segments.enumerated()), id: \.element.id) { index, segment in
                                let width = geo.size.width * segment.end.timeIntervalSince(segment.start) / total
                                segmentView(segment, index: index, width: width,
                                            isLast: index == segments.count - 1, endsSoon: endsSoon)
                                    .frame(width: max(width - 1.5, 2))
                            }
                        }
                    }
                    .frame(height: 18)
                    .clipShape(RoundedRectangle(cornerRadius: EVERadius.xs))

                    HStack {
                        Label("Now", systemImage: "arrowtriangle.up.fill")
                            .labelStyle(.titleAndIcon)
                            .font(.eveLabel)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text("Queue ends \(EVEDates.short(last.end, now: now)) · \(EVEFormatters.timeUntil(last.end))")
                            .font(.eveLabel.monospacedDigit())
                            .foregroundStyle(endsSoon ? AnyShapeStyle(.orange) : AnyShapeStyle(.secondary))
                            .help(EVEDates.full(last.end))
                    }
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(Text("Skill queue: \(segments.count) skills, ends in \(EVEFormatters.timeUntil(last.end))"))
            }
        }
    }

    private func segments(now: Date) -> [Segment] {
        queue.compactMap { entry in
            guard let finish = entry.finishDate, finish > now else { return nil }
            let start = max(entry.startDate ?? now, now)
            return finish > start ? Segment(entry: entry, start: start, end: finish) : nil
        }
        .sorted { $0.start < $1.start }
    }

    private func segmentView(_ segment: Segment, index: Int, width: CGFloat, isLast: Bool, endsSoon: Bool) -> some View {
        // Alternate two shades of the knowledge color so adjacent skills read as separate.
        let base = (isLast && endsSoon) ? Color.orange : tint
        let fill = base.opacity(index.isMultiple(of: 2) ? 0.85 : 0.6)
        return ZStack {
            Rectangle().fill(fill)
            if width > 22 {
                Text(Self.roman(segment.entry.level))
                    .font(.eveMicroBold)
                    .foregroundStyle(.white)
                    .lineLimit(1)
            }
        }
        .help("\(segment.entry.skillName) \(Self.roman(segment.entry.level)) — done \(EVEDates.short(segment.end)) (\(EVEDates.full(segment.end)))")
    }

    private static func roman(_ level: Int) -> String {
        ["", "I", "II", "III", "IV", "V"][min(max(level, 0), 5)]
    }
}
