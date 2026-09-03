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

struct IncursionsView: View {
    @State private var incursions: [ResolvedIncursion] = []
    @State private var isLoading = true
    @State private var error: String?
    @State private var selected: ResolvedIncursion?

    var body: some View {
        LoadingStateView(isLoading: isLoading, error: error,
                         isEmpty: incursions.isEmpty, emptyMessage: "No active incursions") {
            HStack(spacing: 0) {
                List(incursions) { incursion in
                    Button { selected = incursion } label: {
                        IncursionRow(incursion: incursion)
                    }
                    .buttonStyle(.plain)
                    .listRowBackground(selected?.id == incursion.id ? Color.accentColor.opacity(0.12) : Color.clear)
                }
                if let selected {
                    Divider()
                    IncursionDetailPane(incursion: selected, onClose: { self.selected = nil })
                        .frame(width: 340)
                        .id(selected.id)
                }
            }
        }
        .safeAreaInset(edge: .top, spacing: 0) {
            HStack {
                Text("Incursions")
                    .font(.largeTitle.bold())
                Spacer()
                if !incursions.isEmpty {
                    Text("\(incursions.count) active")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(.background)
        }
        .navigationTitle("")
        .task { await load() }
    }

    private func load() async {
        isLoading = true
        error = nil

        do {
            let raw: [ESIIncursion] = try await ESIClient.shared.fetch("/incursions/")

            let factionIds = Array(Set(raw.map(\.factionId)))
            let stagingIds = raw.map(\.stagingSolarSystemId)
            async let factionNames = NameResolver.shared.resolve(ids: factionIds)
            async let systemNames = NameResolver.shared.resolve(ids: stagingIds)
            let (fNames, sNames) = await (factionNames, systemNames)

            var resolved: [ResolvedIncursion] = []
            for inc in raw {
                let constellation = await UniverseCache.shared.constellation(id: inc.constellationId)
                var region: ESIRegion?
                if let constellation {
                    region = await UniverseCache.shared.region(id: constellation.regionId)
                }
                resolved.append(ResolvedIncursion(
                    incursion: inc,
                    factionName: fNames[inc.factionId] ?? "Faction #\(inc.factionId)",
                    stagingSystemName: sNames[inc.stagingSolarSystemId] ?? "System #\(inc.stagingSolarSystemId)",
                    constellationName: constellation?.name ?? "Constellation #\(inc.constellationId)",
                    regionName: region?.name ?? "Unknown Region"
                ))
            }

            incursions = resolved.sorted { lhs, rhs in
                if lhs.incursion.state != rhs.incursion.state {
                    return stateSortOrder(lhs.incursion.state) < stateSortOrder(rhs.incursion.state)
                }
                return lhs.incursion.influence > rhs.incursion.influence
            }
        } catch {
            self.error = error.localizedDescription
        }

        isLoading = false
    }

    private func stateSortOrder(_ state: String) -> Int {
        switch state {
        case "established": return 0
        case "mobilizing": return 1
        case "withdrawing": return 2
        default: return 3
        }
    }
}

// MARK:  Row

private struct IncursionRow: View {
    let incursion: ResolvedIncursion

    private var inc: ESIIncursion { incursion.incursion }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            CachedAsyncImage(url: EVEImageURL.corporationLogo(inc.factionId, size: 64)) { image in
                image.resizable().scaledToFit()
            } placeholder: {
                RoundedRectangle(cornerRadius: 8).fill(.quaternary)
            }
            .frame(width: 44, height: 44)
            .clipShape(RoundedRectangle(cornerRadius: 8))

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text(incursion.constellationName)
                        .font(.subheadline.bold())
                    stateBadge
                    if inc.hasBoss {
                        Label("Boss", systemImage: "crown.fill")
                            .font(.caption2.bold())
                            .foregroundStyle(.yellow)
                    }
                }
                Text(incursion.regionName)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("Staging: \(incursion.stagingSystemName)")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                Text("\(inc.infestedSolarSystems.count) infested systems")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)

                influenceBar
            }

            Spacer(minLength: 0)
        }
        .padding(.vertical, 4)
    }

    private var stateBadge: some View {
        let (label, color): (String, Color) = switch inc.state {
        case "established": ("Established", .red)
        case "mobilizing": ("Mobilizing", .yellow)
        case "withdrawing": ("Withdrawing", .green)
        default: (inc.state.capitalized, .secondary)
        }
        return Text(label)
            .font(.caption2.bold())
            .foregroundStyle(color)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(color.opacity(0.15), in: Capsule())
    }

    private var influenceBar: some View {
        HStack(spacing: 6) {
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.secondary.opacity(0.15))
                    Capsule()
                        .fill(.orange)
                        .frame(width: geo.size.width * CGFloat(inc.influence))
                }
            }
            .frame(height: 5)
            Text(inc.influence.formatted(.percent.precision(.fractionLength(0))))
                .font(.caption2.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: 36, alignment: .trailing)
        }
        .frame(maxWidth: 220)
        .padding(.top, 2)
    }
}

// MARK:  Model

private struct ResolvedIncursion: Identifiable {
    let incursion: ESIIncursion
    let factionName: String
    let stagingSystemName: String
    let constellationName: String
    let regionName: String

    var id: Int { incursion.id }
}

// MARK:  Detail Pane

private struct IncursionDetailPane: View {
    let incursion: ResolvedIncursion
    var onClose: () -> Void = {}

    @Environment(AccountManager.self) private var accountManager
    @State private var destMessage: String?

    private var inc: ESIIncursion { incursion.incursion }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Text(incursion.constellationName).font(.headline)
                stateBadge
                Spacer()
                Button { onClose() } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .keyboardShortcut(.escape)
            }
            .padding(.horizontal, 14).padding(.vertical, 10)
            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    factionBox

                    VStack(alignment: .leading, spacing: 6) {
                        Text("INFLUENCE").font(.caption2.bold()).foregroundStyle(.tertiary)
                        influenceBar
                        Text(inc.influence < 0.5
                             ? "Low influence — Sansha response is suppressed; rewards are reduced."
                             : "High influence — full rewards, but a stronger Sansha response.")
                            .font(.caption2).foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        metaRow("Region", incursion.regionName)
                        metaRow("Constellation", incursion.constellationName)
                        metaRow("Mothership", inc.hasBoss ? "Present" : "Not yet spawned")
                        metaRow("Infested systems", "\(inc.infestedSolarSystems.count)")
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        Text("SYSTEMS").font(.caption2.bold()).foregroundStyle(.tertiary)
                        InfestedSystemRow(systemId: inc.stagingSolarSystemId, isStaging: true,
                                          onSetDestination: { await setDestination(systemId: $0) })
                        ForEach(inc.infestedSolarSystems.filter { $0 != inc.stagingSolarSystemId }, id: \.self) { sysId in
                            InfestedSystemRow(systemId: sysId, isStaging: false,
                                              onSetDestination: { await setDestination(systemId: $0) })
                        }
                    }

                    HStack(spacing: 8) {
                        if let url = URL(string: "https://evemaps.dotlan.net/map/\(incursion.regionName.replacingOccurrences(of: " ", with: "_"))/\(incursion.constellationName.replacingOccurrences(of: " ", with: "_"))") {
                            Link(destination: url) {
                                Label("Dotlan", systemImage: "arrow.up.right.square").font(.caption)
                            }
                            .buttonStyle(.bordered).controlSize(.small)
                        }
                    }

                    if let destMessage {
                        Label(destMessage, systemImage: "paperplane.fill")
                            .font(.caption).foregroundStyle(.green)
                    }
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .frame(maxHeight: .infinity)
        .background(.regularMaterial)
    }

    private var stateBadge: some View {
        let (label, color): (String, Color) = switch inc.state {
        case "established": ("Established", .red)
        case "mobilizing": ("Mobilizing", .yellow)
        case "withdrawing": ("Withdrawing", .green)
        default: (inc.state.capitalized, .secondary)
        }
        return Text(label)
            .font(.caption2.bold())
            .foregroundStyle(color)
            .padding(.horizontal, 6).padding(.vertical, 2)
            .background(color.opacity(0.15), in: Capsule())
    }

    private var factionBox: some View {
        HStack(spacing: 12) {
            CachedAsyncImage(url: EVEImageURL.corporationLogo(inc.factionId, size: 128)) { $0.resizable().scaledToFit() }
            placeholder: { RoundedRectangle(cornerRadius: 8).fill(.quaternary) }
            .frame(width: 48, height: 48).clipShape(RoundedRectangle(cornerRadius: 8))
            VStack(alignment: .leading, spacing: 2) {
                Text(incursion.factionName).font(.headline)
                if inc.hasBoss {
                    Label("Mothership present", systemImage: "crown.fill")
                        .font(.caption2).foregroundStyle(.yellow)
                }
            }
            Spacer()
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 10))
    }

    private var influenceBar: some View {
        HStack(spacing: 8) {
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.secondary.opacity(0.15))
                    Capsule().fill(.orange).frame(width: geo.size.width * CGFloat(inc.influence))
                }
            }
            .frame(height: 6)
            Text(inc.influence.formatted(.percent.precision(.fractionLength(0))))
                .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                .frame(width: 40, alignment: .trailing)
        }
    }

    private func metaRow(_ label: String, _ value: String) -> some View {
        HStack(spacing: 6) {
            Text(label).font(.caption).foregroundStyle(.secondary)
            Spacer()
            Text(value).font(.caption.monospacedDigit())
        }
    }

    private func setDestination(systemId: Int) async {
        guard let account = accountManager.selectedAccount,
              let token = try? await accountManager.validToken(for: account) else {
            destMessage = "Sign in to set a destination."
            return
        }
        do {
            try await ESIClient.shared.postAction("/ui/autopilot/waypoint/", token: token, queryItems: [
                URLQueryItem(name: "add_to_beginning", value: "false"),
                URLQueryItem(name: "clear_other_waypoints", value: "true"),
                URLQueryItem(name: "destination_id", value: "\(systemId)")
            ])
            destMessage = "Destination set in the EVE client."
        } catch {
            destMessage = "Couldn't set destination (needs esi-ui.write_waypoint.v1)."
        }
    }
}

// MARK:  Infested System Row

private struct InfestedSystemRow: View {
    let systemId: Int
    let isStaging: Bool
    var onSetDestination: (Int) async -> Void = { _ in }

    @State private var name: String?
    @State private var sec: Double?

    var body: some View {
        HStack(spacing: 6) {
            if let sec {
                Text(String(format: "%.1f", sec))
                    .font(.caption2.bold().monospacedDigit())
                    .foregroundStyle(incSecColor(sec))
            }
            Text(name ?? "System #\(systemId)").font(.caption)
            if isStaging {
                Text("STAGING")
                    .font(.system(size: 8).bold())
                    .foregroundStyle(.blue)
                    .padding(.horizontal, 4).padding(.vertical, 1)
                    .background(.blue.opacity(0.15), in: Capsule())
            }
            Spacer()
            Button { Task { await onSetDestination(systemId) } } label: {
                Image(systemName: "paperplane").font(.caption2)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .help("Set as autopilot destination")
        }
        .task(id: systemId) {
            guard name == nil else { return }
            if let sys = await UniverseCache.shared.solarSystem(id: systemId) {
                name = sys.name
                sec = sys.securityStatus
            }
        }
    }
}

private func incSecColor(_ status: Double) -> Color {
    switch status {
    case 0.5...:    return Color(red: 0.4, green: 0.8, blue: 0.3)
    case 0.1..<0.5: return .orange
    default:        return Color(red: 0.9, green: 0.2, blue: 0.2)
    }
}
