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

// MARK:  PresenceState localized display (SwiftUI layer)

extension PresenceState {
    var title: LocalizedStringKey {
        switch self {
        case .activeNow:      "Active Now"
        case .recentlyActive: "Recently Active"
        case .idle:           "Idle"
        case .offline:        "Offline"
        }
    }
}

// Mark:  Presence Badge

/// A small colored dot that conveys a character's inferred presence state.
/// Tap/click to reveal a detail popover with score, dominant signal, and last-seen time.
struct PresenceBadge: View {
    let score: PresenceScore
    var size: CGFloat = 10
    var showLabel: Bool = false

    @State private var showPopover = false

    var body: some View {
        Button {
            showPopover.toggle()
        } label: {
            HStack(spacing: 5) {
                presenceDot
                if showLabel {
                    Text(score.state.title)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .buttonStyle(.plain)
        .popover(isPresented: $showPopover, arrowEdge: .bottom) {
            PresenceDetailPopover(score: score)
        }
    }

    private var presenceDot: some View {
        ZStack {
            // Outer glow ring for "Active Now"
            if score.state == .activeNow {
                Circle()
                    .fill(stateColor.opacity(0.3))
                    .frame(width: size + 4, height: size + 4)
            }
            Circle()
                .fill(stateColor)
                .frame(width: size, height: size)
                .shadow(color: score.state == .activeNow ? stateColor.opacity(0.7) : .clear, radius: 3)
        }
    }

    private var stateColor: Color {
        switch score.state {
        case .activeNow:      return .green
        case .recentlyActive: return .yellow
        case .idle:           return .orange
        case .offline:        return Color.secondary.opacity(0.5)
        }
    }
}

// Mark:  Presence Detail Popover

struct PresenceDetailPopover: View {
    let score: PresenceScore

    private static let signalLabels: [String: LocalizedStringKey] = [
        "onlineNow":        "Online Status",
        "kill":             "Kill Activity",
        "location":         "Location Change",
        "corpMemberChange": "Corp Membership",
        "corpWallet":       "Corp Tax Activity",
        "transaction":      "Wallet Transaction",
        "industryJob":      "Industry Job",
        "marketOrder":      "Market Activity",
        "notification":     "Notification",
        "mail":             "Mail Activity",
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header
            HStack(spacing: 8) {
                stateIcon
                VStack(alignment: .leading, spacing: 1) {
                    Text(score.state.title)
                        .font(.subheadline.bold())
                        .foregroundStyle(stateColor)
                    Text("Confidence: \(score.score.formatted(.percent.precision(.fractionLength(0))))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Divider()

            // Dominant signal
            if let sig = score.dominantSignal,
               let label = Self.signalLabels[sig] {
                LabeledRow(icon: "waveform.path.ecg", label: "Signal", value: label)
            }

            // Last seen
            if let t = score.latestEventAt {
                LabeledRow(icon: "clock", label: "Last Activity", value: relativeTime(t))
            }

            // Score bar
            VStack(alignment: .leading, spacing: 4) {
                Text("Presence Score")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 3).fill(.quaternary)
                        RoundedRectangle(cornerRadius: 3)
                            .fill(stateColor)
                            .frame(width: geo.size.width * score.score)
                    }
                }
                .frame(height: 6)
            }

            Text("Based on publicly-observable signals.\nNot an exact online indicator.")
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .frame(width: 240)
    }

    private var stateIcon: some View {
        ZStack {
            Circle()
                .fill(stateColor.opacity(0.15))
                .frame(width: 28, height: 28)
            Circle()
                .fill(stateColor)
                .frame(width: 10, height: 10)
        }
    }

    private var stateColor: Color {
        switch score.state {
        case .activeNow:      return .green
        case .recentlyActive: return .yellow
        case .idle:           return .orange
        case .offline:        return .secondary
        }
    }

    private func relativeTime(_ date: Date) -> LocalizedStringKey {
        let age = Date().timeIntervalSince(date)
        switch age {
        case ..<60:   return "Just now"
        case ..<3600: return "\(Int(age / 60))m ago"
        case ..<86400: return "\(Int(age / 3600))h ago"
        default:      return "\(Int(age / 86400))d ago"
        }
    }
}

// Mark:  Helpers

private struct LabeledRow: View {
    let icon: String
    let label: LocalizedStringKey
    let value: LocalizedStringKey

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 14)
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .font(.caption.bold())
        }
    }
}

// Mark:  Offline Placeholder

/// A faded dot used when no score is available yet (loading state).
struct PresencePlaceholder: View {
    var size: CGFloat = 10

    var body: some View {
        Circle()
            .fill(Color.secondary.opacity(0.2))
            .frame(width: size, height: size)
    }
}
