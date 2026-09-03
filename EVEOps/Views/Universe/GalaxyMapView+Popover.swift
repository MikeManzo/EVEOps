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

extension GalaxyMapView {
    // MARK:  Constellation Popover

    func popoverView(_ pt: GalaxyPoint) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(pt.name).font(.caption.bold())
                    HStack(spacing: 4) {
                        Circle().fill(regionColor(pt.regionId)).frame(width: 6, height: 6)
                        Text(pt.regionName).font(.caption2).foregroundStyle(.secondary)
                    }
                }
                Spacer()
                Button { selectedPoint = nil } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }

            if pt.id == currentConstellationId {
                Label("Current constellation", systemImage: "location.fill")
                    .font(.caption2).foregroundStyle(.blue)
            }

            Label("\(pt.systemCount) solar system\(pt.systemCount == 1 ? "" : "s")", systemImage: "sun.max.fill")
                .font(.caption2).foregroundStyle(.secondary)

            if dangerMapAt != nil {
                let kills = constellationDangerMap[pt.id] ?? 0
                Label(
                    kills == 0 ? "No kills in the last hour" : "\(kills) ship + pod kill\(kills == 1 ? "" : "s") in the last hour",
                    systemImage: kills == 0 ? "checkmark.shield.fill" : "flame.fill"
                )
                .font(.caption2)
                .foregroundStyle(kills == 0 ? Color.green : killHeatColor(kills))
            }

            if let adjIds = adjacentConstellations[pt.id] {
                Label("\(adjIds.count) constellation connection\(adjIds.count == 1 ? "" : "s")", systemImage: "point.3.connected.trianglepath.dotted")
                    .font(.caption2).foregroundStyle(.secondary)
            } else {
                Label("Loading connections…", systemImage: "point.3.connected.trianglepath.dotted")
                    .font(.caption2).foregroundStyle(.tertiary)
            }

            Divider()

            Button {
                drillConstellationId = pt.id
                drillConstellationName = pt.name
                selectedPoint = nil
            } label: {
                Label("View Constellation Map", systemImage: "map.fill")
                    .font(.caption)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.blue)

            // Set autopilot destination to first system in this constellation
            if let systemId = pt.systemIds.first, accountManager.selectedAccount != nil {
                Button {
                    selectedPoint = nil
                    Task { await setAutopilotDestination(systemId: systemId, label: pt.name) }
                } label: {
                    Label("Set Destination", systemImage: "paperplane.fill")
                        .font(.caption)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.blue)
            }

            // Start a route from this constellation
            Button {
                selectedPoint = nil
                isRouteMode = true
                routeOriginId = pt.id
                routeDestId = nil
                routeConstellationPath = []
                routeMessage = nil
            } label: {
                Label("Plan Route From Here", systemImage: "point.3.connected.trianglepath.dotted")
                    .font(.caption)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.orange)
        }
        .padding(12)
        .frame(width: 230)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 10))
        .padding(12)
    }

    // MARK:  Route Handling

    func handleRouteTap(_ pt: GalaxyPoint) {
        if routeOriginId == nil {
            // Set origin
            routeOriginId = pt.id
            routeDestId = nil
            routeConstellationPath = []
            routeMessage = nil
        } else if pt.id == routeOriginId {
            // Tap origin again to deselect it
            routeOriginId = nil
        } else {
            // Set destination and calculate
            routeDestId = pt.id
            Task { await calculateRoute() }
        }
    }

    func calculateRoute() async {
        guard let originPt = points.first(where: { $0.id == routeOriginId }),
              let destPt   = points.first(where: { $0.id == routeDestId }),
              let originSys = originPt.systemIds.first,
              let destSys   = destPt.systemIds.first else {
            routeMessage = "Missing system data"
            return
        }

        isLoadingRoute = true
        routeConstellationPath = []
        routeMessage = nil

        do {
            // ESI returns a list of solar system IDs for the route (public endpoint, no auth needed)
            let sysIds: [Int] = try await ESIClient.shared.fetch("/route/\(originSys)/\(destSys)/")

            // Map each system → constellation, deduplicating consecutive same-constellation entries
            var conPath: [Int] = []
            for sysId in sysIds {
                if let sys = await UniverseCache.shared.solarSystem(id: sysId) {
                    let cid = sys.constellationId
                    if conPath.last != cid { conPath.append(cid) }
                }
            }

            routeConstellationPath = conPath
            let jumps = sysIds.count - 1
            routeMessage = "\(jumps) jump\(jumps == 1 ? "" : "s") · \(conPath.count) constellation\(conPath.count == 1 ? "" : "s")"
        } catch {
            routeMessage = "No route found"
        }

        isLoadingRoute = false
    }

    func clearRoute() {
        routeOriginId = nil
        routeDestId = nil
        routeConstellationPath = []
        routeMessage = nil
        isLoadingRoute = false
    }

}
