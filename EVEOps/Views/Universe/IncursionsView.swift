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

    var body: some View {
        LoadingStateView(isLoading: isLoading, error: error,
                         isEmpty: incursions.isEmpty, emptyMessage: "No active incursions") {
            List(incursions) { incursion in
                IncursionRow(incursion: incursion)
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
            AsyncImage(url: EVEImageURL.corporationLogo(inc.factionId, size: 64)) { image in
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
