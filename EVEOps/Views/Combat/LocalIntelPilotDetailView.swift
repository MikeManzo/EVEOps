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

/// Detail sheet shown when tapping a pilot resolved by `LocalIntelView`.
struct LocalIntelPilotDetailView: View {
    let pilot: LocalIntelPilot
    @Environment(\.dismiss) private var dismiss
    @Environment(ThemeManager.self) private var themeManager

    var body: some View {
        VStack(spacing: 16) {
            CachedAsyncImage(url: EVEImageURL.characterPortrait(pilot.characterId, size: 256)) { phase in
                if case .success(let image) = phase {
                    image.resizable().scaledToFit()
                } else {
                    RoundedRectangle(cornerRadius: EVERadius.xl).fill(.quaternary)
                }
            }
            .frame(width: 128, height: 128)
            .clipShape(RoundedRectangle(cornerRadius: EVERadius.xl))
            .evePortraitRing(cornerRadius: EVERadius.xl, accent: themeManager.palette.accent)
            .shadow(color: .black.opacity(0.4), radius: 10, y: 4)

            Text(pilot.name)
                .font(.title2.bold())

            VStack(alignment: .leading, spacing: 10) {
                detailRow(
                    icon: "building.2.fill",
                    label: "Corporation",
                    value: pilot.corporationName.map { "\($0) [\(pilot.corporationTicker ?? "?")]" } ?? "Unknown"
                )
                if let allianceName = pilot.allianceName {
                    detailRow(
                        icon: "flag.2.crossed.fill",
                        label: "Alliance",
                        value: "\(allianceName) <\(pilot.allianceTicker ?? "?")>"
                    )
                }
                detailRow(
                    icon: "star.fill",
                    label: "Security Status",
                    value: pilot.securityStatus.map { String(format: "%.2f", $0) } ?? "Unknown",
                    valueColor: pilot.securityStatus.map(pilotSecurityColor)
                )
                detailRow(
                    icon: "calendar",
                    label: "Started",
                    value: pilot.birthday.formatted(date: .abbreviated, time: .omitted)
                )
                if let joinDate = pilot.corporationJoinDate {
                    detailRow(
                        icon: "arrow.right.arrow.left",
                        label: "Current Corp Since",
                        value: pilot.corporationCount.map { "\(joinDate.formatted(date: .abbreviated, time: .omitted)) · \($0) corps" }
                            ?? joinDate.formatted(date: .abbreviated, time: .omitted)
                    )
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if let stats = pilot.zkbStats {
                Divider()
                zkbStatsSection(stats)
            }

            HStack {
                Button {
                    open("https://zkillboard.com/character/\(pilot.characterId)/")
                } label: {
                    Label("zKillboard", systemImage: "arrow.up.right.square")
                }

                Spacer()

                Button("Close") { dismiss() }
                    .keyboardShortcut(.cancelAction)
            }
        }
        .padding(24)
        .frame(width: 360)
    }

    @ViewBuilder
    private func zkbStatsSection(_ stats: ZKBCharacterStats) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("zKillboard")
                .font(.caption.bold())
                .foregroundStyle(.secondary)

            if let danger = stats.dangerRatio {
                detailRow(
                    icon: "exclamationmark.triangle.fill",
                    label: "Danger Rating",
                    value: "\(Int(danger))",
                    valueColor: zkbDangerColor(danger)
                )
            }
            if let destroyed = stats.shipsDestroyed, let lost = stats.shipsLost {
                detailRow(icon: "burst.fill", label: "Kills / Losses", value: "\(destroyed) / \(lost)")
            }
            if let iskDestroyed = stats.iskDestroyed {
                detailRow(icon: "arrow.up.circle.fill", label: "ISK Destroyed", value: EVEFormatters.formatISKShort(iskDestroyed))
            }
            if let iskLost = stats.iskLost {
                detailRow(icon: "arrow.down.circle.fill", label: "ISK Lost", value: EVEFormatters.formatISKShort(iskLost))
            }
            if let gangRatio = stats.gangRatio {
                detailRow(icon: "person.3.fill", label: "Gang Ratio", value: "\(Int(gangRatio))%")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func detailRow(icon: String, label: String, value: String, valueColor: Color? = nil) -> some View {
        HStack {
            Image(systemName: icon)
                .foregroundStyle(.secondary)
                .frame(width: 20)
            Text(label)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .foregroundStyle(valueColor ?? .primary)
        }
        .font(.callout)
    }

    private func open(_ string: String) {
        guard let url = URL(string: string) else { return }
        NSWorkspace.shared.open(url)
    }
}
