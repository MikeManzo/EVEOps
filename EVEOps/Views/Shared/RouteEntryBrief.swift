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

// MARK:  Wording

/// Turns a `SystemIntel` into the brief's plain-language lines. Kept apart from the views
/// so the wording reads in one place.
enum RouteEntryBriefText {
    /// One line per signal, most important first.
    /// - Parameters:
    ///   - previousSystemID: the system the pilot arrives from, to name "the gate you arrive on".
    ///   - nextSystemID: the system the pilot leaves for.
    static func reasons(_ intel: SystemIntel, previousSystemID: Int?, nextSystemID: Int?) -> [String] {
        var lines: [String] = []
        if intel.zkillFailed {
            lines.append("Couldn't reach zKillboard, so this only uses EVE's hourly kill count.")
        }
        for signal in intel.threat.signals {
            switch signal {
            case let .gateCamp(gate, kills, pilots, ships, lastKill):
                var where_ = "a stargate"
                if let dest = intel.gateDestinations[gate] {
                    where_ = "the \(intel.name(dest)) gate"
                    if dest == previousSystemID { where_ += " (the gate you arrive on)" }
                    else if dest == nextSystemID { where_ += " (the gate you leave by)" }
                }
                lines.append("Likely gate camp on \(where_): \(kills) kills by the same \(pilotCount(pilots)), "
                             + "last \(ago(lastKill)).\(flying(ships, intel))")
            case let .roamingGang(pilots, lastSeen, previous, ships, lastKill):
                let gang = "\(pilots)-pilot gang"
                if lastSeen == intel.threat.systemID {
                    lines.append("\(gang) killed here \(ago(lastKill)), coming from \(intel.name(previous)).\(flying(ships, intel))")
                } else {
                    lines.append("\(gang) last seen in \(intel.name(lastSeen)), one jump away, \(ago(lastKill)).\(flying(ships, intel))")
                }
            case let .soloHunter(kills, ship, lastKill):
                let hull = ship.map { " in a \(intel.name($0))" } ?? ""
                lines.append("\(kills == 1 ? "A kill" : "\(kills) kills") by a cloaky hunter\(hull), last \(ago(lastKill)). "
                             + "Hunters stay cloaked between kills.")
            case let .recentKills(count, lastKill):
                lines.append("\(count) other player kill\(count == 1 ? "" : "s"), last \(ago(lastKill)).")
            case let .unreportedKills(count):
                lines.append("EVE counts \(count) more kill\(count == 1 ? "" : "s") in the last hour than zKillboard has yet.")
            case let .quiet(hours):
                lines.append("No player kills in the last \(hours) hours.")
            }
        }
        return lines
    }

    static let caveat = "What this can't see: cloaked ships, pilots who haven't killed anyone yet, "
        + "and kills not yet posted to zKillboard. Recent kills describe the past, not who is there now."

    private static func ago(_ date: Date) -> String {
        date.formatted(.relative(presentation: .named, unitsStyle: .abbreviated))
    }

    private static func pilotCount(_ n: Int) -> String { n == 1 ? "pilot" : "\(n) pilots" }

    private static func flying(_ ships: [Int], _ intel: SystemIntel) -> String {
        guard !ships.isEmpty else { return "" }
        return " Flying " + ships.map(intel.name).formatted(.list(type: .and)) + "."
    }
}

func entryStatusColor(_ status: EntryStatus) -> Color {
    switch status {
    case .clear:   return .green
    case .caution: return .orange
    case .danger:  return .red
    }
}

// MARK:  Status Chip

/// The brief's verdict beside a route row: Clear, Caution or Danger.
struct EntryStatusChip: View {
    let intel: SystemIntel

    var body: some View {
        let status = intel.threat.status
        HStack(spacing: 3) {
            Image(systemName: icon(status)).font(.eveMicro)
            Text(status.label).font(.caption2.bold())
        }
        .foregroundStyle(entryStatusColor(status))
        .padding(.horizontal, EVESpacing.sm)
        .padding(.vertical, EVESpacing.xxs)
        .background(entryStatusColor(status).opacity(0.15), in: Capsule())
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Entry brief: \(status.label)")
    }

    private func icon(_ status: EntryStatus) -> String {
        switch status {
        case .clear:   return "checkmark.shield.fill"
        case .caution: return "exclamationmark.triangle.fill"
        case .danger:  return "xmark.shield.fill"
        }
    }
}

// MARK:  Detail

/// The expanded brief under a route row: reasons, how old the data is, what it can't see,
/// and a shortcut to Local Intel.
struct RouteEntryBriefDetail: View {
    let intel: SystemIntel
    let previousSystemID: Int?
    let nextSystemID: Int?

    var body: some View {
        VStack(alignment: .leading, spacing: EVESpacing.sm) {
            ForEach(Array(RouteEntryBriefText.reasons(intel, previousSystemID: previousSystemID,
                                                      nextSystemID: nextSystemID).enumerated()),
                    id: \.offset) { _, line in
                HStack(alignment: .firstTextBaseline, spacing: EVESpacing.sm) {
                    Circle().fill(entryStatusColor(intel.threat.status)).frame(width: 5, height: 5)
                        .accessibilityHidden(true)
                    Text(line).font(.caption).fixedSize(horizontal: false, vertical: true)
                }
            }

            Text(dataAge)
                .font(.caption2.monospacedDigit())
                .foregroundStyle(.secondary)

            Text(RouteEntryBriefText.caveat)
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)

            Button {
                AppRouter.shared.pendingSection = .localIntel
            } label: {
                Label("Paste Local before you jump in", systemImage: "binoculars.fill")
                    .font(.caption.weight(.medium))
            }
            .buttonStyle(.plain)
            .foregroundStyle(.tint)
            .help("Open Local Intel to check who is in the system right now")
        }
        .padding(EVESpacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(entryStatusColor(intel.threat.status).opacity(0.06),
                    in: RoundedRectangle(cornerRadius: EVERadius.md))
    }

    private var dataAge: String {
        var parts: [String] = []
        if let z = intel.zkillFetchedAt {
            parts.append("zKillboard \(z.formatted(.relative(presentation: .named, unitsStyle: .abbreviated)))")
        }
        if let e = intel.esiFetchedAt {
            parts.append("ESI \(e.formatted(.relative(presentation: .named, unitsStyle: .abbreviated)))")
        }
        return parts.isEmpty ? "Data age unknown" : "Data: " + parts.joined(separator: " · ")
    }
}
