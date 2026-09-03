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

extension LocationOverviewView {
    // MARK:  Last Hour

    struct ConnectedActivity {
        var shipKills = 0
        var podKills = 0
        var npcKills = 0
        var jumps = 0
        var systemsWithData = 0
    }

    func connectedActivity(_ info: CharacterLocationInfo) -> ConnectedActivity {
        var agg = ConnectedActivity()
        for sys in info.nearbySystems {
            guard let a = systemActivity[sys.systemId] else { continue }
            agg.systemsWithData += 1
            agg.shipKills += a.shipKills
            agg.podKills += a.podKills
            agg.npcKills += a.npcKills
            agg.jumps += a.jumps
        }
        return agg
    }

    /// Connected system with the most player kills (ship + pod) in the last hour, if any.
    func activityHotspot(_ info: CharacterLocationInfo) -> (name: String, kills: Int)? {
        info.nearbySystems
            .compactMap { sys -> (String, Int)? in
                guard let a = systemActivity[sys.systemId] else { return nil }
                let k = a.shipKills + a.podKills
                return k > 0 ? (sys.name, k) : nil
            }
            .max { $0.1 < $1.1 }
            .map { (name: $0.0, kills: $0.1) }
    }

    /// Where this system ranks by ship jumps among all active k-space systems in the
    /// last-hour aggregate. `percentile` = share of active systems it out-jumps.
    func trafficStanding(_ info: CharacterLocationInfo) -> (percentile: Int, rank: Int, total: Int)? {
        guard let mine = systemActivity[info.systemId]?.jumps, mine > 0 else { return nil }
        let active = systemActivity
            .filter { $0.key < 31_000_000 && $0.value.jumps > 0 }
            .map(\.value.jumps)
        guard active.count > 1 else { return nil }
        let below = active.lazy.filter { $0 < mine }.count
        let above = active.lazy.filter { $0 > mine }.count
        let percentile = Int((Double(below) / Double(active.count) * 100).rounded())
        return (percentile, above + 1, active.count)
    }

    func lastHourColumn(_ info: CharacterLocationInfo) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "chart.bar.fill")
                    .foregroundStyle(.cyan)
                Text("Last Hour")
                    .font(.subheadline.bold())
            }

            // This system
            VStack(alignment: .leading, spacing: 4) {
//                activityCaption("This System")
                if let a = systemActivity[info.systemId] {
                    activityPillWrap(killMetrics(ship: a.shipKills, pod: a.podKills, npc: a.npcKills, jumps: a.jumps))
                } else {
                    ProgressView().controlSize(.mini)
                }
                if let standing = trafficStanding(info) {
                    HStack(alignment: .top, spacing: 4) {
                        Image(systemName: "chart.line.uptrend.xyaxis")
                            .font(.system(size: 9))
                            .foregroundStyle(.blue)
                        Text("Busier than \(standing.percentile)% of active systems  ·  #\(standing.rank.formatted()) / \(standing.total.formatted())")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }

            // Connected systems (within 1 jump)
            if !info.nearbySystems.isEmpty {
                let agg = connectedActivity(info)
                if agg.systemsWithData > 0 {
                    Divider()
                    VStack(alignment: .leading, spacing: 4) {
                        activityCaption("Within 1 Jump · \(info.nearbySystems.count) system\(info.nearbySystems.count == 1 ? "" : "s")")
                        activityPillWrap(killMetrics(ship: agg.shipKills, pod: agg.podKills, npc: agg.npcKills, jumps: agg.jumps))
                        if let hot = activityHotspot(info) {
                            HStack(spacing: 4) {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .font(.system(size: 9))
                                    .foregroundStyle(.orange)
                                Text("\(hot.name) · \(hot.kills) kill\(hot.kills == 1 ? "" : "s")")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                        }
                    }
                }
            }

            Text("ESI aggregates, ~1h delayed")
                .font(.system(size: 8))
                .foregroundStyle(.tertiary)
        }
    }

    func activityCaption(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 8, weight: .bold))
            .tracking(0.8)
            .foregroundStyle(.tertiary)
    }

    /// ship / pod / NPC kills are always shown (0 renders muted); jumps trailing.
    func killMetrics(ship: Int, pod: Int, npc: Int, jumps: Int) -> [(Int, String, Color)] {
        [
            (ship, ship == 1 ? "ship kill" : "ship kills", .red),
            (pod, pod == 1 ? "pod" : "pods", .orange),
            (npc, "NPC", .indigo),
            (jumps, "jumps", .blue),
        ]
    }

    func activityPillWrap(_ metrics: [(Int, String, Color)]) -> some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 92), spacing: 4, alignment: .leading)],
                  alignment: .leading, spacing: 4) {
            ForEach(Array(metrics.enumerated()), id: \.offset) { _, m in
                activityPill(m.0, m.1, color: m.2)
            }
        }
    }

    // MARK:  Wormhole Intel

    func wormholeSection(_ wh: WHSystemInfo) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "tornado.circle.fill")
                    .foregroundStyle(.purple)
                Text("Wormhole Space")
                    .font(.subheadline.bold())
            }

            HStack(alignment: .top, spacing: 16) {
                // Class column
                VStack(alignment: .leading, spacing: 4) {
                    Text("CLASS")
                        .font(.system(size: 8, weight: .bold))
                        .tracking(0.8)
                        .foregroundStyle(.tertiary)
                    HStack(spacing: 6) {
                        Text(wh.whClass.shortName)
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(wh.whClass.color)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(wh.whClass.color.opacity(0.15), in: Capsule())
                        Text(wh.whClass.displayName)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Text(wh.whClass.description)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                // Effect column
                if let effect = wh.effect {
                    Divider().frame(height: 50)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("SYSTEM EFFECT")
                            .font(.system(size: 8, weight: .bold))
                            .tracking(0.8)
                            .foregroundStyle(.tertiary)
                        HStack(spacing: 5) {
                            Image(systemName: effect.systemImage)
                                .font(.caption.bold())
                                .foregroundStyle(effect.color)
                            Text(effect.displayName)
                                .font(.caption.bold())
                                .foregroundStyle(effect.color)
                        }
                        Text(effect.mechanic)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }

    func activityPill(_ value: Int, _ label: String, color: Color) -> some View {
        let active = value > 0
        let tint: Color = active ? color : .secondary
        return HStack(spacing: 3) {
            Text(value.formatted(.number.grouping(.automatic)))
                .font(.caption.bold().monospacedDigit())
                .foregroundStyle(tint)
            Text(label)
                .font(.caption)
                .foregroundStyle(active ? .secondary : .tertiary)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(tint.opacity(active ? 0.12 : 0.06), in: Capsule())
    }

    // MARK:  Helpers

    func securityBadge(_ value: Double) -> some View {
        Text(String(format: "%.1f", value))
            .font(.caption.bold().monospacedDigit())
            .foregroundStyle(securityColor(value))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(securityColor(value).opacity(0.15), in: Capsule())
    }

    func securityColor(_ value: Double) -> Color {
        switch value {
        case 0.9...: return .cyan
        case 0.7..<0.9: return .green
        case 0.5..<0.7: return .yellow
        case 0.3..<0.5: return .orange
        case 0.1..<0.3: return Color(red: 1, green: 0.5, blue: 0)
        default: return .red
        }
    }

    func infoRow(label: String, value: String) -> some View {
        HStack(spacing: 6) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.tertiary)
                .frame(width: 80, alignment: .trailing)
            Text(value)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    func shipStat(label: String, value: String) -> some View {
        HStack(spacing: 4) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.tertiary)
            Text(value)
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
        }
    }

    func formatLarge(_ value: Double) -> String {
        if value >= 1_000_000_000 {
            return String(format: "%.1fB", value / 1_000_000_000)
        } else if value >= 1_000_000 {
            return String(format: "%.1fM", value / 1_000_000)
        } else if value >= 1_000 {
            return String(format: "%.1fK", value / 1_000)
        }
        return String(format: "%.0f", value)
    }

}
