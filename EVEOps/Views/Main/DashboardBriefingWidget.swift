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

// MARK: Daily Briefing Widget
//
// Turns data EVEOps already has in memory into one prioritized "what needs attention"
// list: empty/expiring skill queues, idle PI extractors, industry jobs wrapping up, and
// days spent more than earned. All of that comes straight off the CharacterSummary the
// Dashboard already builds — no extra ESI calls.
//
// Opportunistically, it also surfaces the most recent Apple Intelligence insights already
// generated elsewhere in the app this session (Finances, Skill Planner, Killmails, Industry,
// Assets, Clones/Implants) via IntelligenceService.recentBriefingEntries(). This never
// triggers new generation — only reads what's already cached — so it costs nothing and
// stays silent until the user has actually visited those tabs.

struct BriefingItem: Identifiable {
    enum Severity: Int, Comparable {
        case urgent, notice, info
        static func < (lhs: Severity, rhs: Severity) -> Bool { lhs.rawValue < rhs.rawValue }
    }

    let id = UUID()
    let severity: Severity
    let icon: String
    let color: Color
    let title: String
    let detail: String
}

/// Availability-agnostic mirror of IntelligenceService.BriefingEntry so this view can be
/// used on any macOS version — the macOS-26-only lookup happens once, inside loadAIEntries().
private struct BriefingAIEntry {
    let domainLabel: String
    let icon: String
    let headline: String
    let suggestion: String
}

struct DashboardBriefingWidgetView: View {
    let summaries: [CharacterSummary]
    let characterNames: [Int: String]
    @Binding var isExpanded: Bool

    @AppStorage("aiInsightsEnabled") private var aiInsightsEnabled = false
    @AppStorage("aiInsightBriefing") private var aiInsightBriefing = true
    @State private var aiEntries: [BriefingAIEntry] = []

    private var items: [BriefingItem] {
        var result: [BriefingItem] = []

        for summary in summaries {
            let name = characterNames[summary.characterID] ?? "Character"

            if summary.isQueueEmpty {
                result.append(BriefingItem(
                    severity: .urgent, icon: "graduationcap.fill", color: .red,
                    title: "Skill queue empty",
                    detail: "\(name)'s training queue is empty — SP is being wasted."
                ))
            } else if let end = summary.queueEnd, end.timeIntervalSinceNow > 0, end.timeIntervalSinceNow < 86_400 {
                result.append(BriefingItem(
                    severity: .notice, icon: "graduationcap", color: .orange,
                    title: "Skill queue ending soon",
                    detail: "\(name)'s queue finishes \(end.formatted(.relative(presentation: .named)))."
                ))
            }

            if summary.expiredExtractorCount > 0 {
                result.append(BriefingItem(
                    severity: .notice, icon: "globe.americas.fill", color: .orange,
                    title: "PI extractors idle",
                    detail: "\(name) has \(summary.expiredExtractorCount) expired extractor head(s) sitting idle."
                ))
            }

            if let next = summary.nextJobFinish, next.timeIntervalSinceNow > 0, next.timeIntervalSinceNow < 7_200 {
                result.append(BriefingItem(
                    severity: .info, icon: "hammer.fill", color: .blue,
                    title: "Industry job finishing soon",
                    detail: "\(name) has a job completing \(next.formatted(.relative(presentation: .named)))."
                ))
            }

            if summary.dailyISKNet < -1_000_000 {
                result.append(BriefingItem(
                    severity: .info, icon: "arrow.down.right.circle", color: .secondary,
                    title: "Spent more than earned today",
                    detail: "\(name) is net \(EVEFormatters.formatISKShort(summary.dailyISKNet)) today."
                ))
            }
        }

        for entry in aiEntries {
            result.append(BriefingItem(
                severity: .info, icon: entry.icon, color: .purple,
                title: "\(entry.domainLabel) insight",
                detail: entry.suggestion.isEmpty ? entry.headline : entry.suggestion
            ))
        }

        return result.sorted { $0.severity < $1.severity }
    }

    private var accent: Color {
        if items.contains(where: { $0.severity == .urgent }) { return .red }
        if items.contains(where: { $0.severity == .notice }) { return .orange }
        return .green
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                isExpanded.toggle()
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "list.bullet.clipboard.fill")
                        .foregroundStyle(accent)
                        .font(.callout)
                    Text("Daily Briefing")
                        .font(.title3.bold())
                    if !items.isEmpty {
                        Text("(\(items.count))")
                            .font(.title3)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.caption.bold())
                        .foregroundStyle(.tertiary)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(accent.opacity(0.07), in: RoundedRectangle(cornerRadius: 10))
                .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(accent.opacity(0.15), lineWidth: 1))
            }
            .buttonStyle(.plain)

            if isExpanded {
                content
                    .padding(.horizontal, 12)
                    .padding(.top, 12)
                    .padding(.bottom, 4)
            }
        }
        .task(id: aiInsightsEnabled) {
            await loadAIEntries()
        }
    }

    @ViewBuilder
    private var content: some View {
        if items.isEmpty {
            HStack(spacing: 6) {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                Text("All clear — nothing needs your attention right now.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        } else {
            LazyVGrid(
                columns: [GridItem(.flexible(), spacing: 16, alignment: .top), GridItem(.flexible(), alignment: .top)],
                alignment: .leading, spacing: 10
            ) {
                ForEach(items) { item in
                    itemRow(item)
                }
            }
        }
    }

    private func itemRow(_ item: BriefingItem) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: item.icon)
                .font(.caption)
                .foregroundStyle(item.color)
                .frame(width: 16)
            VStack(alignment: .leading, spacing: 2) {
                Text(item.title)
                    .font(.caption.weight(.medium))
                Text(item.detail)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
        }
    }

    /// Reads whatever IntelligenceService has already cached this session — never triggers
    /// new generation. Gated behind #available since IntelligenceService requires macOS 26.
    private func loadAIEntries() async {
        guard aiInsightsEnabled, aiInsightBriefing else {
            aiEntries = []
            return
        }
        if #available(macOS 26.0, *), IntelligenceService.isSupported {
            let entries = await IntelligenceService.shared.recentBriefingEntries(limit: 4)
            aiEntries = entries.map {
                BriefingAIEntry(
                    domainLabel: $0.domain.label,
                    icon: $0.domain.icon,
                    headline: $0.headline,
                    suggestion: $0.suggestion
                )
            }
        } else {
            aiEntries = []
        }
    }
}
