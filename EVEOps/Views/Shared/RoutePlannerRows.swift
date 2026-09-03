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

struct RouteSystemRow: View {
    let system: RouteSystem
    let jumpNumber: Int
    let isLast: Bool
    let isFirst: Bool
    var showWaypointButton: Bool = false
    var onSetDestination: (() async -> Void)? = nil
    var onAddWaypoint: (() async -> Void)? = nil

    @State private var showWaypointMenu = false

    var body: some View {
        HStack(spacing: 0) {
            // Vertical connector track
            VStack(spacing: 0) {
                Rectangle()
                    .fill(isFirst ? Color.clear : Color.secondary.opacity(0.25))
                    .frame(width: 2)
                    .frame(maxHeight: .infinity)
                Circle()
                    .fill(isFirst ? Color.blue : isLast ? Color.green : system.securityColor)
                    .frame(width: 8, height: 8)
                Rectangle()
                    .fill(isLast ? Color.clear : Color.secondary.opacity(0.25))
                    .frame(width: 2)
                    .frame(maxHeight: .infinity)
            }
            .frame(width: 20)
            .padding(.leading, 8)

            HStack(spacing: 10) {
                // Jump number
                Text("\(jumpNumber)")
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.tertiary)
                    .frame(width: 24, alignment: .trailing)

                // Security badge
                Text(system.displaySecurity)
                    .font(.caption.bold().monospacedDigit())
                    .foregroundStyle(system.securityColor)
                    .frame(width: 30, alignment: .center)
                    .padding(.vertical, 2)
                    .background(system.securityColor.opacity(0.15), in: RoundedRectangle(cornerRadius: 5))

                // System name
                Text(system.name)
                    .font(.subheadline)
                    .fontWeight(isFirst || isLast ? .semibold : .regular)

                if system.danger.combatKills > 0 {
                    HStack(spacing: 3) {
                        Image(systemName: "flame.fill").font(.system(size: 9))
                        Text("\(system.danger.combatKills)")
                            .font(.caption2.bold().monospacedDigit())
                    }
                    .foregroundStyle(dangerColor(system.dangerLevel))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(dangerColor(system.dangerLevel).opacity(0.15), in: Capsule())
                    .help(rowDangerTooltip(system))
                }

                if system.danger.shipJumps >= 1000 {
                    HStack(spacing: 3) {
                        Image(systemName: "arrow.left.arrow.right").font(.system(size: 8))
                        Text(system.danger.shipJumps.formatted(.number.notation(.compactName)))
                            .font(.caption2.monospacedDigit())
                    }
                    .foregroundStyle(.tertiary)
                    .help("\(system.danger.shipJumps) ship jumps through \(system.name) in the last hour")
                }

                Spacer()

                if isFirst {
                    Text("ORIGIN").font(.caption2.bold()).foregroundStyle(.blue)
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(.blue.opacity(0.15), in: Capsule())
                } else if isLast {
                    Text("DEST").font(.caption2.bold()).foregroundStyle(.green)
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(.green.opacity(0.15), in: Capsule())
                }

                if showWaypointButton {
                    Menu {
                        Button("Set Destination") { Task { await onSetDestination?() } }
                        Button("Add Waypoint") { Task { await onAddWaypoint?() } }
                    } label: {
                        Image(systemName: "paperplane")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .padding(5)
                            .background(.quaternary.opacity(0.6), in: RoundedRectangle(cornerRadius: 5))
                    }
                    .menuStyle(.button)
                    .buttonStyle(.plain)
                    .help("Send to autopilot")
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
        }
        .frame(minHeight: 36)
        .background(isFirst ? Color.blue.opacity(0.05) : isLast ? Color.green.opacity(0.05) : Color.clear)
    }
}

// MARK:  Thera Connection Row

struct TheraConnectionRow: View {
    let connection: EVEScoutConnection
    let isOnRoute: Bool
    let isSelected: Bool
    let onTap: () -> Void
    let onSetAsOrigin: () -> Void
    let onSetAsDestination: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                Circle()
                    .fill(destinationColor)
                    .frame(width: 8, height: 8)

                VStack(alignment: .leading, spacing: 1) {
                    HStack(spacing: 6) {
                        Text(connection.destinationSystemName)
                            .font(.caption.bold())
                        if isOnRoute {
                            Text("ON ROUTE")
                                .font(.system(size: 9).bold())
                                .foregroundStyle(.green)
                                .padding(.horizontal, 5).padding(.vertical, 2)
                                .background(.green.opacity(0.15), in: Capsule())
                        }
                        if connection.isNearEOL {
                            Image(systemName: "exclamationmark.circle.fill")
                                .foregroundStyle(.red).font(.system(size: 10))
                                .help("Near end of life")
                        }
                    }
                    Text(connection.destinationRegionName)
                        .font(.system(size: 10)).foregroundStyle(.secondary)
                }

                Spacer()

                HStack(spacing: 6) {
                    if let eol = connection.estimatedEol {
                        Text(eol)
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundStyle(connection.isNearEOL ? Color.red : Color.secondary)
                    }

                    Text(connection.maxShipSize.label)
                        .font(.system(size: 10).bold())
                        .padding(.horizontal, 5).padding(.vertical, 2)
                        .background(.quaternary, in: RoundedRectangle(cornerRadius: 4))
                        .help(connection.maxShipSize.tooltip)

                    Circle()
                        .fill(massColor)
                        .frame(width: 7, height: 7)
                        .help(connection.massStatus.tooltip)

                    Text(connection.signatureId)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(.tertiary)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)

            if isSelected {
                HStack(spacing: 8) {
                    Spacer()
                    Button("Set as Origin") { onSetAsOrigin() }
                        .buttonStyle(.bordered).controlSize(.small)
                    Button("Set as Destination") { onSetAsDestination() }
                        .buttonStyle(.borderedProminent).controlSize(.small)
                }
                .padding(.horizontal, 8)
                .padding(.bottom, 6)
            }
        }
        .background(
            isSelected ? Color.accentColor.opacity(0.1) : isOnRoute ? Color.green.opacity(0.06) : Color.clear,
            in: RoundedRectangle(cornerRadius: 6)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .strokeBorder(isSelected ? Color.accentColor.opacity(0.3) : Color.clear, lineWidth: 1)
        )
        .contentShape(Rectangle())
        .onTapGesture { onTap() }
        .contextMenu {
            Button("Set as Route Origin") { onSetAsOrigin() }
            Button("Set as Destination") { onSetAsDestination() }
        }
    }

    private var destinationColor: Color {
        switch connection.destinationSecurity.lowercased() {
        case "highsec": return eveSecurityColor(0.9)
        case "lowsec":  return eveSecurityColor(0.3)
        case "nullsec": return eveSecurityColor(-0.1)
        case "pochven": return .purple
        default:        return .gray
        }
    }

    private var massColor: Color {
        switch connection.massStatus {
        case .stable:       return .green
        case .destabilized: return .yellow
        case .critical:     return .red
        case .unknown:      return .gray
        }
    }
}

// MARK:  Helpers

func dangerColor(_ level: DangerLevel) -> Color {
    switch level {
    case .quiet:    return .green
    case .elevated: return .yellow
    case .high:     return .orange
    case .extreme:  return .red
    }
}

func rowDangerTooltip(_ system: RouteSystem) -> String {
    let d = system.danger
    var parts = ["\(system.name): \(d.shipKills) ship / \(d.podKills) pod kill\(d.podKills == 1 ? "" : "s") in the last hour"]
    if d.npcKills > 0 { parts.append("\(d.npcKills) NPC kills") }
    if d.shipJumps > 0 { parts.append("\(d.shipJumps) ship jumps") }
    return parts.joined(separator: " · ")
}

func eveSecurityColor(_ status: Double) -> Color {
    switch status {
    case 0.9...: return Color(red: 0.3, green: 0.9, blue: 1.0)
    case 0.8..<0.9: return Color(red: 0.0, green: 0.9, blue: 0.8)
    case 0.7..<0.8: return Color(red: 0.0, green: 0.9, blue: 0.4)
    case 0.6..<0.7: return Color(red: 0.4, green: 0.9, blue: 0.0)
    case 0.5..<0.6: return Color(red: 0.9, green: 0.9, blue: 0.0)
    case 0.4..<0.5: return Color(red: 1.0, green: 0.6, blue: 0.0)
    case 0.3..<0.4: return Color(red: 1.0, green: 0.4, blue: 0.0)
    case 0.2..<0.3: return Color(red: 1.0, green: 0.2, blue: 0.0)
    case 0.1..<0.2: return Color(red: 0.9, green: 0.0, blue: 0.0)
    default: return Color(red: 0.6, green: 0.0, blue: 0.0)
    }
}
