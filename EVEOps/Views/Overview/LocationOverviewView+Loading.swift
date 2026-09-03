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
    // MARK:  Prefetcher Fast Path

    func buildFromPrefetcher() -> Bool {
        var data: [CharacterLocationInfo] = []
        for account in [accountManager.selectedAccount].compactMap({ $0 }) {
            guard let prefetched = prefetcher.data(for: account.characterID) else { return false }
            guard let systemInfo = prefetcher.resolvedSystems[prefetched.location.solarSystemId] else { return false }

            let constellation = prefetcher.resolvedConstellations[systemInfo.constellationId]
            let shipType = prefetcher.resolvedTypes[prefetched.ship.shipTypeId]
            var regionName: String?
            if let cId = constellation?.regionId {
                regionName = prefetcher.resolvedRegions[cId]?.name
            }
            var shipGroupName: String?
            if let gId = shipType?.groupId {
                shipGroupName = prefetcher.resolvedGroups[gId]?.name
            }

            data.append(CharacterLocationInfo(
                characterID: account.characterID,
                characterName: account.characterName,
                corporationName: account.corporationName,
                isOnline: prefetched.online.online,
                lastLogin: prefetched.online.lastLogin,
                lastLogout: prefetched.online.lastLogout,
                loginCount: prefetched.online.logins,
                systemId: prefetched.location.solarSystemId,
                constellationId: systemInfo.constellationId,
                systemName: systemInfo.name,
                securityValue: systemInfo.securityStatus,
                constellationName: constellation?.name,
                regionName: regionName,
                dockedAt: nil,  // Resolved in background refresh
                dockedStation: nil,
                systemStations: [],
                shipName: prefetched.ship.shipName,
                shipTypeName: shipType?.name ?? "Unknown",
                shipTypeId: prefetched.ship.shipTypeId,
                shipGroupName: shipGroupName,
                shipMass: shipType?.mass,
                shipVolume: shipType?.volume,
                shipCapacity: shipType?.capacity,
                starName: nil,
                starSpectralClass: nil,
                starTemperature: nil,
                starRadius: nil,
                starLuminosity: nil,
                starAge: nil,
                starTypeId: nil,
                planetCount: 0,
                moonCount: 0,
                asteroidBeltCount: 0,
                planetTypes: [],
                stationCountInSystem: 0,
                nearbySystems: []  // Resolved in background refresh
            ))
        }
        locations = data
        lastRefresh = Date()
        // Kick off background enrichment for star/nearby/docked data
        Task { await loadLocations() }
        return !data.isEmpty
    }

    // MARK:  Data Loading

    func loadLocations() async {
        if locations.isEmpty { isLoading = true }
        error = nil
        var data: [CharacterLocationInfo] = []
        var lastError: Error?
        for account in [accountManager.selectedAccount].compactMap({ $0 }) {
            do {
                let token = try await accountManager.validToken(for: account)

                async let fetchLocation: ESICharacterLocation = ESIClient.shared.fetch(
                    "/characters/\(account.characterID)/location/", token: token
                )
                async let fetchShip: ESICharacterShip = ESIClient.shared.fetch(
                    "/characters/\(account.characterID)/ship/", token: token
                )
                async let fetchOnline: ESICharacterOnline = ESIClient.shared.fetch(
                    "/characters/\(account.characterID)/online/", token: token
                )

                let (location, ship, online) = try await (fetchLocation, fetchShip, fetchOnline)

                // System → Constellation → Region chain (via UniverseCache)
                guard let systemInfo = await UniverseCache.shared.solarSystem(id: location.solarSystemId) else {
                    continue
                }

                async let fetchConstellation = UniverseCache.shared.constellation(id: systemInfo.constellationId)
                async let fetchShipType = UniverseCache.shared.type(id: ship.shipTypeId)

                let constellation = await fetchConstellation
                let shipType = await fetchShipType

                var region: ESIRegion?
                if let cId = constellation?.regionId {
                    region = await UniverseCache.shared.region(id: cId)
                }

                // Ship group name
                var shipGroup: ESIGroup?
                if let gId = shipType?.groupId {
                    shipGroup = await UniverseCache.shared.group(id: gId)
                }

                // Star info
                var star: ESIStar?
                if let starId = systemInfo.starId {
                    star = await UniverseCache.shared.star(id: starId)
                }

                // Nearby systems via stargates (ESIClient cache handles repeat fetches)
                var nearbySystems: [NearbySystem] = []
                if let gateIds = systemInfo.stargates, !gateIds.isEmpty {
                    let gates = await withTaskGroup(of: ESIStargate?.self) { group in
                        for gateId in gateIds {
                            group.addTask {
                                try? await ESIClient.shared.fetch("/universe/stargates/\(gateId)/") as ESIStargate
                            }
                        }
                        var results: [ESIStargate] = []
                        for await gate in group {
                            if let g = gate { results.append(g) }
                        }
                        return results
                    }
                    let destIds = gates.map(\.destination.systemId)
                    let constellationSystems = Set(constellation?.systems ?? [])
                    // Batch-fetch destination systems via UniverseCache
                    let destSystems = await withTaskGroup(of: ESISolarSystem?.self) { group in
                        for destId in destIds {
                            group.addTask {
                                await UniverseCache.shared.solarSystem(id: destId)
                            }
                        }
                        var results: [ESISolarSystem] = []
                        for await sys in group {
                            if let s = sys { results.append(s) }
                        }
                        return results
                    }
                    for dest in destSystems {
                        // Resolve where the gate leads: flag region crossings (the meaningful
                        // "external" case) and, failing that, constellation crossings.
                        var leadsToRegion: String?
                        var leadsToConstellation: String?
                        if dest.constellationId != systemInfo.constellationId {
                            let destCon = await UniverseCache.shared.constellation(id: dest.constellationId)
                            leadsToConstellation = destCon?.name
                            if let rid = destCon?.regionId, rid != constellation?.regionId {
                                leadsToRegion = await UniverseCache.shared.region(id: rid)?.name
                                leadsToConstellation = nil // region label supersedes
                            }
                        }
                        nearbySystems.append(NearbySystem(
                            systemId: dest.systemId,
                            name: dest.name,
                            securityStatus: dest.securityStatus,
                            isExternal: !constellationSystems.contains(dest.systemId),
                            stationCount: dest.stations?.count ?? 0,
                            leadsToRegion: leadsToRegion,
                            leadsToConstellation: leadsToConstellation
                        ))
                    }
                    nearbySystems.sort { $0.securityStatus > $1.securityStatus }
                }

                // System composition — planet / moon / belt counts and a planet-type histogram
                var planetCount = 0, moonCount = 0, asteroidBeltCount = 0
                var planetTypes: [PlanetTypeCount] = []
                if let planets = systemInfo.planets, !planets.isEmpty {
                    planetCount = planets.count
                    moonCount = planets.reduce(0) { $0 + ($1.moons?.count ?? 0) }
                    asteroidBeltCount = planets.reduce(0) { $0 + ($1.asteroidBelts?.count ?? 0) }
                    let typeIds = await withTaskGroup(of: Int?.self) { group in
                        for p in planets {
                            group.addTask { await UniverseCache.shared.planet(id: p.planetId)?.typeId }
                        }
                        var ids: [Int] = []
                        for await t in group { if let t { ids.append(t) } }
                        return ids
                    }
                    if !typeIds.isEmpty {
                        let typeMap = await UniverseCache.shared.types(ids: typeIds)
                        var histogram: [String: Int] = [:]
                        for tid in typeIds {
                            histogram[Self.planetTypeLabel(typeMap[tid]?.name ?? "Unknown"), default: 0] += 1
                        }
                        planetTypes = histogram
                            .map { PlanetTypeCount(type: $0.key, count: $0.value) }
                            .sorted { $0.count != $1.count ? $0.count > $1.count : $0.type < $1.type }
                    }
                }

                // Docked location
                var dockedAt: String?
                var dockedStation: ESIStation?
                if let stationId = location.stationId {
                    let station = await UniverseCache.shared.station(id: stationId)
                    dockedStation = station
                    dockedAt = station?.name
                } else if let structureId = location.structureId {
                    if let structure: ESIStructure = try? await ESIClient.shared.fetch(
                        "/universe/structures/\(structureId)/", token: token
                    ) {
                        dockedAt = structure.name
                    } else {
                        dockedAt = "Player Structure"
                    }
                }

                // Stations in current system
                let systemStations: [ESIStation]
                if let stationIds = systemInfo.stations, !stationIds.isEmpty {
                    systemStations = await withTaskGroup(of: ESIStation?.self) { group in
                        for sid in stationIds {
                            group.addTask { await UniverseCache.shared.station(id: sid) }
                        }
                        var results: [ESIStation] = []
                        for await s in group { if let s { results.append(s) } }
                        return results.sorted { $0.name < $1.name }
                    }
                } else {
                    systemStations = []
                }

                data.append(CharacterLocationInfo(
                    characterID: account.characterID,
                    characterName: account.characterName,
                    corporationName: account.corporationName,
                    isOnline: online.online,
                    lastLogin: online.lastLogin,
                    lastLogout: online.lastLogout,
                    loginCount: online.logins,
                    systemId: location.solarSystemId,
                    constellationId: systemInfo.constellationId,
                    systemName: systemInfo.name,
                    securityValue: systemInfo.securityStatus,
                    constellationName: constellation?.name,
                    regionName: region?.name,
                    dockedAt: dockedAt,
                    dockedStation: dockedStation,
                    systemStations: systemStations,
                    shipName: ship.shipName,
                    shipTypeName: shipType?.name ?? "Unknown",
                    shipTypeId: ship.shipTypeId,
                    shipGroupName: shipGroup?.name,
                    shipMass: shipType?.mass,
                    shipVolume: shipType?.volume,
                    shipCapacity: shipType?.capacity,
                    starName: star?.name,
                    starSpectralClass: star?.spectralClass,
                    starTemperature: star?.temperature,
                    starRadius: star?.radius,
                    starLuminosity: star?.luminosity,
                    starAge: star?.age,
                    starTypeId: star?.typeId,
                    planetCount: planetCount,
                    moonCount: moonCount,
                    asteroidBeltCount: asteroidBeltCount,
                    planetTypes: planetTypes,
                    stationCountInSystem: systemInfo.stations?.count ?? 0,
                    nearbySystems: nearbySystems
                ))
            } catch {
                lastError = error
            }
        }
        locations = data
        if data.isEmpty, let lastError {
            self.error = lastError.localizedDescription
        }
        lastRefresh = Date()
        isLoading = false
        await loadSituational()
    }

    /// Extracts the parenthetical from a planet type name — "Planet (Barren)" → "Barren".
    static func planetTypeLabel(_ raw: String) -> String {
        if let open = raw.firstIndex(of: "("), let close = raw.firstIndex(of: ")"), open < close {
            return String(raw[raw.index(after: open)..<close])
        }
        return raw.replacingOccurrences(of: "Planet ", with: "")
    }

    // MARK:  System Activity Loading

    func loadSystemActivity() async {
        async let fetchKills: [ESISystemKills] = (try? await ESIClient.shared.fetch("/universe/system_kills/")) ?? []
        async let fetchJumps: [ESISystemJumps] = (try? await ESIClient.shared.fetch("/universe/system_jumps/")) ?? []
        let (kills, jumps) = await (fetchKills, fetchJumps)

        let killsMap = Dictionary(kills.map { ($0.systemId, $0) }, uniquingKeysWith: { a, _ in a })
        let jumpsMap = Dictionary(jumps.map { ($0.systemId, $0.shipJumps) }, uniquingKeysWith: { a, _ in a })

        var map: [Int: SystemActivityData] = [:]
        let allIds = Set(kills.map(\.systemId)).union(Set(jumps.map(\.systemId)))
        for id in allIds {
            let k = killsMap[id]
            map[id] = SystemActivityData(
                shipKills: k?.shipKills ?? 0,
                podKills:  k?.podKills  ?? 0,
                npcKills:  k?.npcKills  ?? 0,
                jumps:     jumpsMap[id] ?? 0
            )
        }
        systemActivity = map
    }

    // MARK:  Situational Status (Faction Warfare · Incursions)

    /// Loads FW contest state and active incursions, then resolves faction names only for
    /// the systems currently on screen (current + connected). Both feeds are small.
    func loadSituational() async {
        async let fwRaw: [ESIFWSystem] = (try? await ESIClient.shared.fetch("/fw/systems/")) ?? []
        async let incRaw: [ESIIncursion] = (try? await ESIClient.shared.fetch("/incursions/")) ?? []
        let (fw, inc) = await (fwRaw, incRaw)

        let fwMap = Dictionary(fw.map { ($0.solarSystemId, $0) }, uniquingKeysWith: { a, _ in a })
        let onScreen = Set(locations.flatMap { [$0.systemId] + $0.nearbySystems.map(\.systemId) })

        var factionIds = Set<Int>()
        for id in onScreen {
            if let f = fwMap[id] {
                factionIds.insert(f.ownerFactionId)
                factionIds.insert(f.occupierFactionId)
            }
        }
        for i in inc where !onScreen.isDisjoint(with: Set(i.infestedSolarSystems)) {
            factionIds.insert(i.factionId)
        }
        let names = factionIds.isEmpty ? [:] : await NameResolver.shared.resolve(ids: Array(factionIds))

        fwSystems = fwMap
        incursions = inc
        situationalFactionNames = names
    }
}
