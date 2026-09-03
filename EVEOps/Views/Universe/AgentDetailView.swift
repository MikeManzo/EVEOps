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

struct AgentDetailView: View {
    let agent: ResolvedAgent
    var onDestinationSet: (String) -> Void = { _ in }

    @Environment(AccountManager.self) private var accountManager

    @State private var isSetting        = false
    @State private var autopilotMessage: String? = nil

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                header
                Divider()
                actionBar
                Divider()
                infoSection
                    .padding(16)
            }
        }
        .background(.regularMaterial)
    }

    // MARK: Header

    private var header: some View {
        ZStack(alignment: .bottomLeading) {
            LinearGradient(
                colors: [Color.blue.opacity(0.4), Color.blue.opacity(0.1)],
                startPoint: .topLeading, endPoint: .bottomTrailing
            )
            .frame(height: 90)

            HStack(spacing: 10) {
                CachedAsyncImage(url: URL(string: "https://images.evetech.net/characters/\(agent.agent.agentID)/portrait?size=64")) { phase in
                    if let img = phase.image {
                        img.resizable().frame(width: 64, height: 64).clipShape(RoundedRectangle(cornerRadius: 8))
                    } else {
                        RoundedRectangle(cornerRadius: 8).fill(.blue.opacity(0.3)).frame(width: 64, height: 64)
                    }
                }
                VStack(alignment: .leading, spacing: 3) {
                    Text(agent.displayName).font(.headline).foregroundStyle(.primary)
                    Text(agent.displayCorp).font(.caption).foregroundStyle(.secondary)
                }
            }
            .padding(12)
        }
    }

    // MARK: Action Bar

    private var actionBar: some View {
        HStack(spacing: 8) {
            if accountManager.selectedAccount != nil {
                Button {
                    Task { await setDestination() }
                } label: {
                    Label(isSetting ? "Setting…" : "Set Destination", systemImage: "paperplane.fill")
                        .font(.caption.weight(.semibold))
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .disabled(agent.systemID == nil || isSetting)
            }
            Spacer()
            if let msg = autopilotMessage {
                Label(msg, systemImage: msg.hasPrefix("Destination") ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(msg.hasPrefix("Destination") ? .green : .orange)
                    .lineLimit(1)
            }
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
        .background(.bar)
    }

    // MARK: Info

    private var infoSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("Details", systemImage: "person.text.rectangle.fill")
                .font(.subheadline.bold())

            infoRow("Level",       "L\(agent.agent.level)")
            infoRow("Agent ID",    "\(agent.agent.agentID)")
            infoRow("Corp ID",     "\(agent.agent.corporationID)")

            if let access = agent.access {
                Divider()
                accessSection(access)
            }

            Divider()
            Label("Location", systemImage: "location.fill")
                .font(.subheadline.bold()).foregroundStyle(.blue)

            HStack(spacing: 6) {
                if let sec = agent.securityStatus {
                    Circle().fill(agentSecColor(sec)).frame(width: 8, height: 8)
                }
                Text(agent.displaySystem).font(.body.bold())
                if let sec = agent.securityStatus {
                    agentSecBadge(sec)
                }
                if let j = agent.jumpCount { agentJumpBadge(j) }
            }
            if let c = agent.constellationName { infoRow("Constellation", c) }
            if let r = agent.regionName        { infoRow("Region", r) }
        }
    }

    private func infoRow(_ label: String, _ value: String) -> some View {
        HStack(spacing: 6) {
            Text(label).font(.caption).foregroundStyle(.tertiary).frame(width: 90, alignment: .trailing)
            Text(value).font(.caption).foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private func accessSection(_ access: AgentAccessResult) -> some View {
        Label("Agent Access", systemImage: access.canAccess ? "checkmark.shield.fill" : "lock.shield.fill")
            .font(.subheadline.bold())
            .foregroundStyle(access.canAccess ? .green : .orange)

        if access.level <= 1 {
            Text("Level 1 agents have no standing requirement.")
                .font(.caption).foregroundStyle(.secondary)
        } else {
            infoRow("Required", String(format: "%.1f", access.requiredStanding))
            infoRow("Effective", String(format: "%.2f", access.effectiveStanding))
            if access.hasStandingData {
                infoRow("Best via", "\(access.basis.rawValue) \(String(format: "%+.2f", access.baseStanding))")
            } else {
                infoRow("Best via", "No standing on record")
            }
            if access.skillLevel > 0 {
                infoRow("Skill", "\(access.skillName) \(romanNumeral(access.skillLevel))")
            }
            if access.canAccess {
                Text("You can accept missions from this agent.")
                    .font(.caption).foregroundStyle(.green)
            } else {
                Text("Raise your effective standing by \(String(format: "%.2f", access.gap)) to unlock — via \(access.basis == .neutral ? "any relevant faction, corp or agent" : access.basis.rawValue.lowercased()) standing"
                     + (access.skillLevel < 5 ? ", or by training \(access.skillName)." : "."))
                    .font(.caption).foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func romanNumeral(_ n: Int) -> String {
        ["0", "I", "II", "III", "IV", "V"][max(0, min(5, n))]
    }

    // MARK: Autopilot

    private func setDestination() async {
        guard let account = accountManager.selectedAccount, let sysID = agent.systemID else { return }
        isSetting = true; autopilotMessage = nil
        do {
            let token = try await accountManager.validToken(for: account)
            try await ESIClient.shared.postAction(
                "/ui/autopilot/waypoint/", token: token,
                queryItems: [
                    URLQueryItem(name: "add_to_beginning",      value: "false"),
                    URLQueryItem(name: "clear_other_waypoints", value: "true"),
                    URLQueryItem(name: "destination_id",        value: "\(sysID)"),
                ]
            )
            autopilotMessage = "Destination set to \(agent.displaySystem)."
        } catch ESIError.unauthorized {
            autopilotMessage = "Needs esi-ui.write_waypoint.v1 scope."
        } catch {
            autopilotMessage = error.localizedDescription
        }
        isSetting = false
    }
}

// MARK:  Shared Badges

func agentSecBadge(_ status: Double) -> some View {
    Text(String(format: "%.1f", max(0.0, status)))
        .font(.caption.bold().monospacedDigit())
        .foregroundStyle(agentSecColor(status))
        .padding(.horizontal, 7).padding(.vertical, 3)
        .background(agentSecColor(status).opacity(0.15), in: Capsule())
}

@ViewBuilder
func agentAccessBadge(_ access: AgentAccessResult) -> some View {
    if access.canAccess {
        Label("Access", systemImage: "checkmark.circle.fill")
            .labelStyle(.iconOnly)
            .font(.caption)
            .foregroundStyle(.green)
            .help(access.level <= 1
                  ? "Level 1 agents have no standing requirement"
                  : "Effective standing \(String(format: "%.2f", access.effectiveStanding)) ≥ required \(String(format: "%.1f", access.requiredStanding)) (via \(access.basis.rawValue.lowercased()))")
    } else {
        HStack(spacing: 3) {
            Image(systemName: "lock.fill").font(.system(size: 9))
            Text("+\(String(format: "%.1f", access.gap))")
                .font(.caption2.bold().monospacedDigit())
        }
        .foregroundStyle(.orange)
        .padding(.horizontal, 5).padding(.vertical, 1)
        .background(.orange.opacity(0.15), in: Capsule())
        .help("Needs \(String(format: "%.1f", access.requiredStanding)) effective standing for a level \(access.level) agent — you have \(String(format: "%.2f", access.effectiveStanding))")
    }
}

func agentJumpBadge(_ jumps: Int) -> some View {
    Group {
        if jumps == 0 {
            Text("here").font(.caption.bold()).foregroundStyle(.green)
                .padding(.horizontal, 6).padding(.vertical, 2)
                .background(.green.opacity(0.12), in: Capsule())
        } else {
            Text("\(jumps) jumps").font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                .padding(.horizontal, 6).padding(.vertical, 2)
                .background(.secondary.opacity(0.1), in: Capsule())
        }
    }
}

func agentSecColor(_ status: Double) -> Color {
    switch status {
    case 0.9...:    return Color(red: 0.3, green: 0.9, blue: 1.0)
    case 0.8..<0.9: return Color(red: 0.0, green: 0.9, blue: 0.8)
    case 0.7..<0.8: return Color(red: 0.0, green: 0.9, blue: 0.4)
    case 0.6..<0.7: return Color(red: 0.4, green: 0.9, blue: 0.0)
    case 0.5..<0.6: return Color(red: 0.9, green: 0.9, blue: 0.0)
    case 0.4..<0.5: return Color(red: 1.0, green: 0.6, blue: 0.0)
    case 0.3..<0.4: return Color(red: 1.0, green: 0.4, blue: 0.0)
    case 0.2..<0.3: return Color(red: 1.0, green: 0.2, blue: 0.0)
    case 0.1..<0.2: return Color(red: 0.9, green: 0.0, blue: 0.0)
    default:        return Color(red: 0.6, green: 0.0, blue: 0.0)
    }
}
