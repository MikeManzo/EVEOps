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

extension GalaxyMarketSearchView {
    // MARK:  Empty State

    @ViewBuilder
    var emptyStateView: some View {
        if let error = searchError {
            VStack(spacing: 12) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 36))
                    .foregroundStyle(.orange)
                Text("Search Failed")
                    .font(.headline)
                Text(error)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 400)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            VStack(spacing: 14) {
                Image(systemName: "globe.europe.africa.fill")
                    .font(.system(size: 48))
                    .foregroundStyle(Color(red: 0.2, green: 0.75, blue: 0.8).opacity(0.5))
                Text("Galaxy Market Search")
                    .font(.title3.bold())
                    .foregroundStyle(.secondary)
                VStack(spacing: 4) {
                    Text("Search sell orders, buy orders, or both across all k-space regions.")
                    Text("Filter by high-sec stations and jump distance from your location.")
                }
                .font(.subheadline)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    // MARK:  Item Search Logic

    func onItemSearchChanged(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        if trimmed == selectedTypeName, selectedTypeId != nil { return }
        if selectedTypeId != nil {
            selectedTypeId = nil
            selectedTypeName = ""
        }
        itemSearchTask?.cancel()
        guard trimmed.count >= 3 else {
            itemSearchResults = []
            isSearchingItems = false
            return
        }
        isSearchingItems = true
        itemSearchTask = Task {
            try? await Task.sleep(for: .milliseconds(400))
            guard !Task.isCancelled else { return }
            await searchItems(trimmed)
        }
    }

    func clearItemSelection() {
        selectedTypeId = nil
        selectedTypeName = ""
        selectedTypeInfo = nil
        itemSearchText = ""
        itemSearchResults = []
        orders = []
        searchError = nil
    }

    func searchItems(_ query: String) async {
        struct SearchResp: Decodable { let inventoryType: [Int]? }
        struct NameEntry: Decodable { let id: Int; let name: String }

        if let account = accountManager.selectedAccount,
           let token = try? await accountManager.validToken(for: account) {
            // Authenticated prefix search — works with 3+ chars
            let resp: SearchResp? = try? await ESIClient.shared.fetch(
                "/characters/\(account.characterID)/search/",
                token: token,
                queryItems: [
                    URLQueryItem(name: "categories", value: "inventory_type"),
                    URLQueryItem(name: "search",     value: query),
                    URLQueryItem(name: "strict",     value: "false")
                ]
            )
            // Take up to 100 IDs so relevant items (e.g. the base ship) aren't
            // truncated before names are resolved — ESI returns them in arbitrary order.
            let ids = Array((resp?.inventoryType ?? []).prefix(100))
            guard !ids.isEmpty else {
                isSearchingItems = false
                itemSearchResults = []
                return
            }
            let names: [NameEntry] = (try? await ESIClient.shared.post("/universe/names/", body: ids)) ?? []
            isSearchingItems = false
            let lower = query.lowercased()
            itemSearchResults = names
                .map { GalaxyTypeResult(typeId: $0.id, name: $0.name) }
                .sorted { a, b in
                    let aL = a.name.lowercased(), bL = b.name.lowercased()
                    let aExact = aL == lower,  bExact = bL == lower
                    if aExact != bExact { return aExact }
                    let aPrefix = aL.hasPrefix(lower), bPrefix = bL.hasPrefix(lower)
                    if aPrefix != bPrefix { return aPrefix }
                    return aL < bL
                }
        } else {
            // Fallback for unauthenticated: exact name match only
            struct IDResp: Decodable { let inventoryTypes: [ESIIDName]? }
            let resp: IDResp? = try? await ESIClient.shared.post("/universe/ids/", body: [query])
            isSearchingItems = false
            itemSearchResults = (resp?.inventoryTypes ?? [])
                .map { GalaxyTypeResult(typeId: $0.id, name: $0.name) }
                .sorted { $0.name < $1.name }
        }
    }

    // MARK:  Galaxy Search Logic

    func performGalaxySearch() async {
        guard let typeId = selectedTypeId else { return }
        galaxyTask?.cancel()
        isSearching = true
        isComputingJumps = false
        searchError = nil
        orders = []
        regionsSearched = 0
        // Set natural sort direction for the selected order type
        if sortColumn == .price {
            sortAscending = orderTypeFilter != .buy
        }

        galaxyTask = Task { await runGalaxySearch(typeId: typeId) }
    }

    func runGalaxySearch(typeId: Int) async {
        let regions = await UniverseCache.shared.knownSpaceRegions()
        totalRegions = regions.count

        // Always fetch "all" from ESI — filter locally so switching the picker
        // doesn't require a second network pass.
        let allPairs: [(regionId: Int, order: ESIRegionMarketOrder)] =
            await withTaskGroup(of: [(Int, ESIRegionMarketOrder)].self) { group in
                for region in regions {
                    let rid = region.id
                    group.addTask {
                        let fetched: [ESIRegionMarketOrder] = (try? await ESIClient.shared.fetch(
                            "/markets/\(rid)/orders/",
                            queryItems: [
                                URLQueryItem(name: "type_id", value: "\(typeId)"),
                                URLQueryItem(name: "order_type", value: "all")
                            ]
                        )) ?? []
                        return fetched.map { (rid, $0) }
                    }
                }
                var out: [(Int, ESIRegionMarketOrder)] = []
                for await chunk in group {
                    out.append(contentsOf: chunk)
                    regionsSearched += 1
                }
                return out
            }

        guard !Task.isCancelled else {
            isSearching = false
            return
        }

        // Sort: sell orders cheapest first, buy orders highest first
        let sorted = allPairs.sorted {
            if $0.order.isBuyOrder != $1.order.isBuyOrder {
                return !$0.order.isBuyOrder  // sell before buy in combined view
            }
            return $0.order.isBuyOrder
                ? $0.order.price > $1.order.price   // highest buy first
                : $0.order.price < $1.order.price   // lowest sell first
        }

        // Resolve system security/name for every unique system
        let uniqueSystemIds = Set(sorted.map { $0.order.systemId })
        var systemData: [Int: (name: String, sec: Double)] = [:]
        await withTaskGroup(of: (Int, ESISolarSystem?).self) { group in
            for sysId in uniqueSystemIds {
                group.addTask { (sysId, await UniverseCache.shared.solarSystem(id: sysId)) }
            }
            for await (id, sys) in group {
                if let sys { systemData[id] = (sys.name, sys.securityStatus) }
            }
        }

        // Apply high-sec filter
        let secFiltered = highSecOnly
            ? sorted.filter { (systemData[$0.order.systemId]?.sec ?? 0) >= 0.45 }
            : sorted

        // Cap to top 200 sell + top 200 buy to bound downstream work
        let topSell = Array(secFiltered.filter { !$0.order.isBuyOrder }.prefix(200))
        let topBuy  = Array(secFiltered.filter {  $0.order.isBuyOrder }.prefix(200))
        let topPairs = topSell + topBuy

        // Resolve station / structure names
        let token = accountManager.selectedAccount.flatMap {
            !$0.isTokenExpired ? $0.accessToken : nil
        }
        let uniqueLocations = Set(topPairs.map { $0.order.locationId })
        var locationNames: [Int: String] = [:]
        await withTaskGroup(of: (Int, String?).self) { group in
            for locId in uniqueLocations {
                group.addTask {
                    if locId < 1_000_000_000 {
                        return (locId, await UniverseCache.shared.station(id: locId)?.name)
                    } else if let token {
                        let s: ESIStructure? = try? await ESIClient.shared.fetch(
                            "/universe/structures/\(locId)/", token: token
                        )
                        return (locId, s?.name ?? "Player Structure")
                    } else {
                        return (locId, "Player Structure")
                    }
                }
            }
            for await (id, name) in group {
                if let name { locationNames[id] = name }
            }
        }

        let regionNames = Dictionary(uniqueKeysWithValues: regions.map { ($0.id, $0.name) })

        let initialOrders: [GalaxyOrder] = topPairs.map { (regionId, order) in
            let sys = systemData[order.systemId]
            return GalaxyOrder(
                order: order,
                isBuyOrder: order.isBuyOrder,
                regionName: regionNames[regionId] ?? "Unknown",
                systemName: sys?.name ?? "Unknown",
                locationName: locationNames[order.locationId] ?? "Unknown Location",
                securityStatus: sys?.sec ?? 0.0,
                jumps: nil
            )
        }
        orders = initialOrders
        isSearching = false

        guard let originId = characterSystemId else { return }

        isComputingJumps = true
        let uniqueDestSystems = Array(Set(topPairs.map { $0.order.systemId }))
        let routeFlag = secureRoute ? "secure" : "shortest"
        var newCache = jumpCache

        var toFetch: [Int] = []
        for destId in uniqueDestSystems {
            if destId == originId {
                newCache[destId] = 0
            } else if newCache[destId] == nil {
                toFetch.append(destId)
            }
        }

        let jumpResults = await withTaskGroup(of: (Int, Int?).self) { group in
            for destId in toFetch {
                group.addTask {
                    let route: [Int]? = try? await ESIClient.shared.fetch(
                        "/route/\(originId)/\(destId)/",
                        queryItems: [URLQueryItem(name: "flag", value: routeFlag)]
                    )
                    return (destId, route.map { max(0, $0.count - 1) })
                }
            }
            var out: [(Int, Int?)] = []
            for await r in group { out.append(r) }
            return out
        }
        for (sysId, j) in jumpResults { if let j { newCache[sysId] = j } }
        jumpCache = newCache

        var withJumps: [GalaxyOrder] = initialOrders.map { order in
            var updated = order
            updated.jumps = newCache[order.order.systemId]
            return updated
        }
        if maxJumps > 0 {
            withJumps = withJumps.filter { ($0.jumps ?? Int.max) <= maxJumps }
        }
        orders = withJumps
        isComputingJumps = false
    }

    // MARK:  Location Helpers

    func loadCharacterLocation() {
        if let account = accountManager.selectedAccount,
           let data = prefetcher.data(for: account.characterID) {
            characterSystemId = data.location.solarSystemId
        }
    }

    func fetchCurrentLocation() async {
        guard let account = accountManager.selectedAccount,
              let token = try? await accountManager.validToken(for: account) else { return }
        let loc: ESICharacterLocation? = try? await ESIClient.shared.fetch(
            "/characters/\(account.characterID)/location/", token: token, bypassCache: true
        )
        if let sysId = loc?.solarSystemId {
            characterSystemId = sysId
        }
    }

    // MARK:  Autopilot

    func setWaypoint(destinationId: Int, clear: Bool) async {
        guard let account = accountManager.selectedAccount else {
            waypointMessage = "No character logged in."
            return
        }
        waypointMessage = nil
        do {
            let token = try await accountManager.validToken(for: account)
            try await ESIClient.shared.postAction(
                "/ui/autopilot/waypoint/",
                token: token,
                queryItems: [
                    URLQueryItem(name: "add_to_beginning", value: "false"),
                    URLQueryItem(name: "clear_other_waypoints", value: clear ? "true" : "false"),
                    URLQueryItem(name: "destination_id", value: "\(destinationId)")
                ]
            )
            waypointMessage = clear ? "Destination set in EVE client." : "Waypoint added in EVE client."
        } catch ESIError.unauthorized {
            waypointMessage = "Requires esi-ui.write_waypoint.v1 scope — re-add your character to grant autopilot access."
        } catch {
            waypointMessage = error.localizedDescription
        }
    }

    // MARK:  Helpers

    func securityColor(_ sec: Double) -> Color {
        switch sec {
        case 0.45...: return .green
        case 0.0..<0.45: return .orange
        default: return .red
        }
    }

    func formatCount(_ value: Int) -> String {
        switch value {
        case 1_000_000_000...: return String(format: "%.1fB", Double(value) / 1_000_000_000)
        case 1_000_000...:     return String(format: "%.1fM", Double(value) / 1_000_000)
        case 10_000...:        return String(format: "%.1fK", Double(value) / 1_000)
        default:               return "\(value)"
        }
    }

    func formatRange(_ range: String) -> String {
        switch range {
        case "station":     return "Station"
        case "solarsystem": return "System"
        case "region":      return "Region"
        case "1":           return "1 jump"
        case "2":           return "2 jumps"
        case "3":           return "3 jumps"
        case "4":           return "4 jumps"
        case "5":           return "5 jumps"
        case "10":          return "10 jumps"
        case "20":          return "20 jumps"
        case "30":          return "30 jumps"
        case "40":          return "40 jumps"
        default:            return range
        }
    }
}
