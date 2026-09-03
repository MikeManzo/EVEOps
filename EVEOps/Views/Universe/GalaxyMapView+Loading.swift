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
    // MARK:  Data Loading

    func loadData() async {
        isLoading = true
        loadingProgress = 0

        let allRegions = await UniverseCache.shared.knownSpaceRegions()
        guard !allRegions.isEmpty else { isLoading = false; return }
        loadingProgress = 0.05

        var regionEntries: [(id: Int, name: String, constellationIds: [Int])] = []
        await withTaskGroup(of: (Int, String, [Int]?).self) { group in
            for (id, name, _) in allRegions {
                group.addTask {
                    let r = await UniverseCache.shared.region(id: id)
                    return (id, name, r?.constellations)
                }
            }
            for await (id, name, cids) in group {
                if let cids, !cids.isEmpty { regionEntries.append((id, name, cids)) }
            }
        }
        loadingProgress = 0.15

        var consToRegion: [Int: (id: Int, name: String)] = [:]
        for entry in regionEntries {
            for cid in entry.constellationIds { consToRegion[cid] = (entry.id, entry.name) }
        }
        let allConsIds = Array(consToRegion.keys)
        let total = Double(allConsIds.count)
        var loaded = 0
        var newPoints: [GalaxyPoint] = []

        await withTaskGroup(of: (Int, ESIConstellation?).self) { group in
            for cid in allConsIds {
                group.addTask { (cid, await UniverseCache.shared.constellation(id: cid)) }
            }
            for await (cid, cons) in group {
                loaded += 1
                if loaded % 20 == 0 || loaded == Int(total) {
                    loadingProgress = 0.15 + Double(loaded) / total * 0.8
                }
                guard let cons, let pos = cons.position,
                      let region = consToRegion[cid] else { continue }
                newPoints.append(GalaxyPoint(
                    id: cid, name: cons.name,
                    regionId: region.id, regionName: region.name,
                    x: pos.x, z: pos.z,
                    systemCount: cons.systems?.count ?? 0,
                    systemIds: cons.systems ?? []
                ))
            }
        }

        var centroids: [Int: (sumX: Double, sumZ: Double, count: Int, name: String)] = [:]
        for pt in newPoints {
            var c = centroids[pt.regionId] ?? (0, 0, 0, pt.regionName)
            c.sumX += pt.x; c.sumZ += pt.z; c.count += 1
            centroids[pt.regionId] = c
        }
        let labels = centroids.compactMap { id, c -> RegionLabel? in
            guard c.count > 0 else { return nil }
            return RegionLabel(name: c.name, regionId: id,
                               x: c.sumX / Double(c.count), z: c.sumZ / Double(c.count))
        }

        points = newPoints
        regionLabels = labels
        loadingProgress = 1.0
        isLoading = false

        await resolveCurrentLocation()
    }

    /// Loads average security status per constellation in the background.
    /// Called the first time the user switches to Security color mode.
    func loadSecurityMap() async {
        guard !isLoadingSecMap else { return }
        isLoadingSecMap = true
        let pts = points
        var secMap: [Int: Double] = [:]

        await withTaskGroup(of: (Int, Double?).self) { group in
            for pt in pts {
                group.addTask {
                    let sysIds = pt.systemIds
                    guard !sysIds.isEmpty else { return (pt.id, nil) }
                    var total = 0.0
                    var count = 0
                    for sysId in sysIds {
                        if let sys = await UniverseCache.shared.solarSystem(id: sysId) {
                            total += sys.securityStatus
                            count += 1
                        }
                    }
                    return (pt.id, count > 0 ? total / Double(count) : nil)
                }
            }
            for await (id, sec) in group {
                if let sec { secMap[id] = sec }
            }
        }

        constellationSecMap = secMap
        isLoadingSecMap = false
    }

    /// Sums the hourly ship + pod kills of each constellation's systems.
    /// Called whenever the user switches to the "Kills" colour mode.
    func loadDangerMap() async {
        guard !isLoadingDangerMap else { return }
        isLoadingDangerMap = true
        defer { isLoadingDangerMap = false }

        guard let snapshot = try? await SystemDangerService.shared.snapshot() else { return }

        var map: [Int: Int] = [:]
        map.reserveCapacity(points.count)
        for pt in points {
            var total = 0
            for sysId in pt.systemIds {
                total += snapshot.danger(for: sysId).combatKills
            }
            if total > 0 { map[pt.id] = total }
        }
        constellationDangerMap = map
        dangerMapAt = snapshot.fetchedAt
    }

    /// Loads stargate adjacency for a constellation on first select.
    /// Walks constellation → systems → stargates → destination systems → destination constellations.
    func loadAdjacency(for constellationId: Int) async {
        guard adjacentConstellations[constellationId] == nil else { return }

        guard let cons = await UniverseCache.shared.constellation(id: constellationId),
              let systemIds = cons.systems else {
            adjacentConstellations[constellationId] = []
            return
        }

        let adjIds: Set<Int> = await withTaskGroup(of: Set<Int>.self) { group in
            for sysId in systemIds {
                group.addTask {
                    guard let sys = await UniverseCache.shared.solarSystem(id: sysId),
                          let gateIds = sys.stargates else { return [] }
                    var local: Set<Int> = []
                    for gateId in gateIds {
                        guard let gate: ESIStargate = try? await ESIClient.shared.fetch(
                            "/universe/stargates/\(gateId)/") else { continue }
                        let destSysId = gate.destination.systemId
                        if let destSys = await UniverseCache.shared.solarSystem(id: destSysId),
                           destSys.constellationId != constellationId {
                            local.insert(destSys.constellationId)
                        }
                    }
                    return local
                }
            }
            var result: Set<Int> = []
            for await partial in group { result.formUnion(partial) }
            return result
        }

        adjacentConstellations[constellationId] = adjIds
    }

    func resolveCurrentLocation() async {
        guard let account = accountManager.selectedAccount else { return }
        let charID = account.characterID

        if let data = prefetcher.data(for: charID) {
            let sysId = data.location.solarSystemId
            if let sys = prefetcher.resolvedSystems[sysId] {
                applyLocationInfo(sys: sys, ship: data.ship, charID: charID)
                return
            }
            if let sys = await UniverseCache.shared.solarSystem(id: sysId) {
                applyLocationInfo(sys: sys, ship: data.ship, charID: charID)
                return
            }
        }

        guard !account.isTokenExpired,
              let token = try? await accountManager.validToken(for: account),
              let location: ESICharacterLocation = try? await ESIClient.shared.fetch(
                  "/characters/\(charID)/location/", token: token),
              let sys = await UniverseCache.shared.solarSystem(id: location.solarSystemId)
        else { return }

        var ship: ESICharacterShip? = nil
        if let prefetchedShip = prefetcher.data(for: charID)?.ship {
            ship = prefetchedShip
        } else {
            ship = try? await ESIClient.shared.fetch("/characters/\(charID)/ship/", token: token)
        }
        applyLocationInfo(sys: sys, ship: ship, charID: charID)
    }

    func applyLocationInfo(sys: ESISolarSystem, ship: ESICharacterShip?, charID: Int) {
        currentConstellationId = sys.constellationId
        currentSystemName = sys.name
        currentSystemSecurity = sys.securityStatus

        if let ship {
            let typeName = prefetcher.resolvedTypes[ship.shipTypeId]?.name
            currentShipTypeName = typeName
            currentShipCustomName = (ship.shipName != typeName && !ship.shipName.isEmpty) ? ship.shipName : nil
        }

        let cid = sys.constellationId
        if adjacentConstellations[cid] == nil {
            Task { await loadAdjacency(for: cid) }
        }

        if !hasCenteredOnLoad && canvasSize != .zero {
            hasCenteredOnLoad = true
            selectedPoint = points.first(where: { $0.id == sys.constellationId })
            centerOnCurrentLocation()
        }
    }
}
