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
import Charts
import FoundationModels

extension MarketBrowserView {
    // MARK:  Data Loading

    func loadInitialData() async {
        if let account = accountManager.selectedAccount,
           let data = prefetcher.data(for: account.characterID) {
            characterSystemId = data.location.solarSystemId
        }

        // Prefetcher data may not be ready yet (race at app launch) or may be stale.
        // Fall back to a direct ESI location fetch so jump distances always resolve.
        if characterSystemId == nil {
            await fetchCharacterLocation()
        }

        await withTaskGroup(of: Void.self) { group in
            group.addTask { await self.loadRegions() }
            group.addTask { await self.loadMarketGroups() }
            group.addTask { await self.loadMarketPrices() }
        }

        // Set region to character's current location unless overridden manually this session
        if !regionManuallyOverridden,
           let sysId = characterSystemId,
           let system = await UniverseCache.shared.solarSystem(id: sysId),
           let constellation = await UniverseCache.shared.constellation(id: system.constellationId),
           availableRegions.contains(where: { $0.id == constellation.regionId }) {
            selectedRegionId = constellation.regionId
        }

        // Restore last-viewed item for this session only (ESIClient cache makes this
        // cheap). Cleared on app relaunch, so a fresh launch starts with no selection.
        if Self.sessionTypeId > 0 && selectedTypeId == nil {
            let typeId = Self.sessionTypeId
            let name = Self.sessionTypeName
            selectedTypeId = typeId
            selectedTypeName = name
            await withTaskGroup(of: Void.self) { group in
                group.addTask { await self.loadOrders(typeId: typeId) }
                group.addTask {
                    let info = await UniverseCache.shared.type(id: typeId)
                    await MainActor.run { self.selectedTypeInfo = info }
                }
                group.addTask { await self.loadPriceHistory(typeId: typeId) }
            }
            insightResetKey = "\(typeId)-\(selectedRegionId)"
        }
    }

    func fetchCharacterLocation() async {
        guard let account = accountManager.selectedAccount,
              let token = try? await accountManager.validToken(for: account) else { return }
        let loc: ESICharacterLocation? = try? await ESIClient.shared.fetch(
            "/characters/\(account.characterID)/location/", token: token
        )
        if let sysId = loc?.solarSystemId {
            characterSystemId = sysId
        }
    }

    func recalculateJumps() async {
        guard let origin = characterSystemId else { return }
        let allOrders = sellOrders + buyOrders
        guard !allOrders.isEmpty else { return }
        let systemIds = Set(allOrders.map { $0.order.systemId })
        let jumps = await resolveJumps(systemIds: systemIds, originId: origin)
        for (sysId, count) in jumps { jumpCache[sysId] = count }
        sellOrders = sellOrders.map {
            var o = $0; o.jumps = jumps[o.order.systemId] ?? o.jumps; return o
        }
        buyOrders = buyOrders.map {
            var o = $0; o.jumps = jumps[o.order.systemId] ?? o.jumps; return o
        }
    }

    func loadRegions() async {
        guard availableRegions.isEmpty else { return }
        availableRegions = await UniverseCache.shared.knownSpaceRegions()
    }

    func loadMarketGroups() async {
        // If the tree is already populated (e.g. navigating back to this view),
        // skip the rebuild entirely — UniverseCache holds the data in memory.
        guard rootNodes.isEmpty else { return }
        isLoadingGroups = true

        // UniverseCache serves from its 7-day disk cache after the first load,
        // so repeat opens cost only an O(n) in-memory tree rebuild.
        fetchedGroups = await UniverseCache.shared.allMarketGroups()
        rebuildTree()
        isLoadingGroups = false
    }

    /// O(n) tree rebuild using a parent→children map rather than scanning all
    /// groups for each node (previously O(n²), called ~60 times during load).
    func rebuildTree() {
        var childrenByParent: [Int: [ESIMarketGroup]] = [:]
        var rootGroups: [ESIMarketGroup] = []

        for g in fetchedGroups.values {
            if let parentId = g.parentGroupId, fetchedGroups[parentId] != nil {
                childrenByParent[parentId, default: []].append(g)
            } else {
                rootGroups.append(g)
            }
        }

        func buildNode(_ group: ESIMarketGroup) -> MarketGroupNode {
            let children = (childrenByParent[group.marketGroupId] ?? [])
                .sorted { $0.name < $1.name }
                .map { buildNode($0) }
            return MarketGroupNode(group: group, children: children.isEmpty ? nil : children)
        }

        rootNodes = rootGroups.sorted { $0.name < $1.name }.map { buildNode($0) }
    }

    func loadGroupTypes(group: ESIMarketGroup) async {
        groupTypes = []
        guard !group.types.isEmpty else { return }

        isLoadingGroupTypes = true
        defer { isLoadingGroupTypes = false }

        let typeMap = await UniverseCache.shared.types(ids: group.types)
        groupTypes = group.types.compactMap { typeId in
            guard let info = typeMap[typeId], info.published else { return nil }
            return MarketTypeResult(typeId: typeId, name: info.name)
        }.sorted { $0.name < $1.name }
    }

    func performSearch(_ query: String) async {
        struct SearchResp: Decodable { let inventoryType: [Int]? }
        struct NameEntry: Decodable { let id: Int; let name: String }

        if let account = accountManager.selectedAccount,
           let token = try? await accountManager.validToken(for: account) {
            let resp: SearchResp? = try? await ESIClient.shared.fetch(
                "/characters/\(account.characterID)/search/",
                token: token,
                queryItems: [
                    URLQueryItem(name: "categories", value: "inventory_type"),
                    URLQueryItem(name: "search",     value: query),
                    URLQueryItem(name: "strict",     value: "false")
                ]
            )
            let ids = Array((resp?.inventoryType ?? []).prefix(100))
            guard !ids.isEmpty else {
                isSearching = false
                searchResults = []
                return
            }
            let names: [NameEntry] = (try? await ESIClient.shared.post("/universe/names/", body: ids)) ?? []
            let lower = query.lowercased()
            searchResults = names
                .map { MarketTypeResult(typeId: $0.id, name: $0.name) }
                .sorted { a, b in
                    let aL = a.name.lowercased(), bL = b.name.lowercased()
                    let aExact = aL == lower,  bExact = bL == lower
                    if aExact != bExact { return aExact }
                    let aPrefix = aL.hasPrefix(lower), bPrefix = bL.hasPrefix(lower)
                    if aPrefix != bPrefix { return aPrefix }
                    return aL < bL
                }
        } else {
            struct IDResp: Decodable { let inventoryTypes: [ESIIDName]? }
            let resp: IDResp? = try? await ESIClient.shared.post("/universe/ids/", body: [query])
            searchResults = (resp?.inventoryTypes ?? [])
                .map { MarketTypeResult(typeId: $0.id, name: $0.name) }
                .sorted { $0.name < $1.name }
        }
        isSearching = false
    }

    // MARK:  Type Selection & Order Loading

    func selectType(_ typeId: Int, name: String) async {
        // Ignore no-op re-selections. The List(selection:) bindings re-emit the
        // current value whenever their data reloads (group switch, search refresh),
        // which would otherwise trigger a full reload and rewrite the remembered item.
        guard typeId != selectedTypeId else { return }

        selectedTypeId = typeId
        selectedTypeName = name
        Self.sessionTypeId = typeId
        Self.sessionTypeName = name
        selectedOrderTab = 0
        selectedTypeInfo = nil
        priceHistory = []
        sellOrders = []
        buyOrders = []
        insightResetKey = ""

        await withTaskGroup(of: Void.self) { group in
            group.addTask { await self.loadOrders(typeId: typeId) }
            group.addTask {
                let info = await UniverseCache.shared.type(id: typeId)
                await MainActor.run { self.selectedTypeInfo = info }
            }
            group.addTask { await self.loadPriceHistory(typeId: typeId) }
        }
        insightResetKey = "\(typeId)-\(selectedRegionId)"
    }

    func loadOrders(typeId: Int, regionOverride: Int? = nil) async {
        isLoadingOrders = true
        ordersError = nil
        sellOrders = []
        buyOrders = []

        // Capture auth token on main actor before launching child tasks
        let token = accountManager.selectedAccount.flatMap {
            !$0.isTokenExpired ? $0.accessToken : nil
        }
        let originId = characterSystemId

        let orders: [ESIRegionMarketOrder]
        do {
            orders = try await ESIClient.shared.fetch(
                "/markets/\(regionOverride ?? selectedRegionId)/orders/",
                queryItems: [
                    URLQueryItem(name: "type_id", value: "\(typeId)"),
                    URLQueryItem(name: "order_type", value: "all")
                ]
            )
        } catch {
            ordersError = error.localizedDescription
            isLoadingOrders = false
            return
        }

        // Show prices/quantities immediately; location and system names resolve below.
        let sortedSell = orders.filter { !$0.isBuyOrder }.sorted { $0.price < $1.price }
        let sortedBuy  = orders.filter {  $0.isBuyOrder }.sorted { $0.price > $1.price }
        sellOrders = sortedSell.map { ResolvedOrder(order: $0, locationName: "…", systemName: "…", securityStatus: 0, jumps: nil) }
        buyOrders  = sortedBuy .map { ResolvedOrder(order: $0, locationName: "…", systemName: "…", securityStatus: 0, jumps: nil) }
        isLoadingOrders = false

        let uniqueLocationIds = Set(orders.map { $0.locationId })
        let uniqueSystemIds = Set(orders.map { $0.systemId })

        async let locationNamesTask = resolveLocations(ids: uniqueLocationIds, token: token)
        async let systemDataTask = resolveSystems(ids: uniqueSystemIds)
        async let jumpsTask = resolveJumps(systemIds: uniqueSystemIds, originId: originId)

        let (locationNames, systemData, jumps) = await (locationNamesTask, systemDataTask, jumpsTask)

        for (sysId, count) in jumps { jumpCache[sysId] = count }

        func resolve(_ order: ESIRegionMarketOrder) -> ResolvedOrder {
            let (sysName, sec) = systemData[order.systemId] ?? ("Unknown", 0.0)
            return ResolvedOrder(
                order: order,
                locationName: locationNames[order.locationId] ?? "Unknown Location",
                systemName: sysName,
                securityStatus: sec,
                jumps: jumps[order.systemId]
            )
        }

        sellOrders = sortedSell.map(resolve)
        buyOrders  = sortedBuy.map(resolve)
    }

    func resolveLocations(ids: Set<Int>, token: String?) async -> [Int: String] {
        var result: [Int: String] = [:]
        await withTaskGroup(of: (Int, String?).self) { group in
            for locationId in ids {
                group.addTask {
                    if locationId < 1_000_000_000 {
                        let station = await UniverseCache.shared.station(id: locationId)
                        return (locationId, station?.name)
                    } else if let token {
                        let structure: ESIStructure? = try? await ESIClient.shared.fetch(
                            "/universe/structures/\(locationId)/", token: token
                        )
                        return (locationId, structure?.name ?? "Player Structure")
                    } else {
                        return (locationId, "Player Structure")
                    }
                }
            }
            for await (id, name) in group {
                if let name { result[id] = name }
            }
        }
        return result
    }

    func resolveSystems(ids: Set<Int>) async -> [Int: (String, Double)] {
        var result: [Int: (String, Double)] = [:]
        await withTaskGroup(of: (Int, ESISolarSystem?).self) { group in
            for sysId in ids {
                group.addTask {
                    (sysId, await UniverseCache.shared.solarSystem(id: sysId))
                }
            }
            for await (id, sys) in group {
                if let sys { result[id] = (sys.name, sys.securityStatus) }
            }
        }
        return result
    }

    func resolveJumps(systemIds: Set<Int>, originId: Int?) async -> [Int: Int] {
        guard let origin = originId else { return [:] }
        var result: [Int: Int] = [:]
        var toFetch: [Int] = []

        for sysId in systemIds {
            if sysId == origin {
                result[sysId] = 0
            } else if let cached = jumpCache[sysId] {
                result[sysId] = cached
            } else {
                toFetch.append(sysId)
            }
        }

        // Cap route fetches to avoid hammering the API
        let limited = Array(toFetch.prefix(30))
        let routes = await withTaskGroup(of: (Int, Int?).self) { group in
            for destId in limited {
                group.addTask {
                    let route: [Int]? = try? await ESIClient.shared.fetch("/route/\(origin)/\(destId)/")
                    return (destId, route.map { max(0, $0.count - 1) })
                }
            }
            var out: [(Int, Int?)] = []
            for await r in group { out.append(r) }
            return out
        }

        for (sysId, jumps) in routes {
            if let jumps { result[sysId] = jumps }
        }
        return result
    }

    func loadMarketPrices() async {
        guard marketPrices.isEmpty else { return }
        let prices: [ESIMarketPrice]? = try? await ESIClient.shared.fetch("/markets/prices/")
        if let prices {
            var map: [Int: ESIMarketPrice] = [:]
            for price in prices { map[price.typeId] = price }
            marketPrices = map
        }
    }

    func loadPriceHistory(typeId: Int, regionOverride: Int? = nil) async {
        let history: [ESIMarketHistory]? = try? await ESIClient.shared.fetch(
            "/markets/\(regionOverride ?? selectedRegionId)/history/",
            queryItems: [URLQueryItem(name: "type_id", value: "\(typeId)")]
        )
        priceHistory = (history ?? []).sorted { $0.date < $1.date }

        if let price = marketPrices[typeId] {
            adjustedPrice = price.adjustedPrice
            averagePrice = price.averagePrice
        } else {
            adjustedPrice = nil
            averagePrice = nil
        }
    }

    func openInEVE(typeId: Int, token: String) async {
        openInEVEMessage = nil
        do {
            try await ESIClient.shared.postAction(
                "/ui/openwindow/marketdetails/",
                token: token,
                queryItems: [URLQueryItem(name: "type_id", value: "\(typeId)")]
            )
        } catch ESIError.forbidden {
            openInEVEMessage = "Needs esi-ui.open_window.v1 scope — re-add your character."
        } catch {
            openInEVEMessage = error.localizedDescription
        }
    }

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

    // MARK:  Computed Helpers

    var characterSkillMap: [Int: Int]? {
        guard let account = accountManager.selectedAccount else { return nil }
        // Access characterData directly (no 2-min freshness check) — a market session can
        // run longer than that window. This is safe because BackgroundMonitor refreshes
        // characterData on the user's configured poll interval, so staleness here is bounded
        // by that interval rather than by how long the view has been open.
        return prefetcher.characterData[account.characterID]
            .map { Dictionary(uniqueKeysWithValues: $0.skills.skills.map { ($0.skillId, $0.activeSkillLevel) }) }
    }

    var filteredHistory: [ESIMarketHistory] {
        guard let cutoff = Calendar.current.date(byAdding: .day, value: -historyDays, to: Date()) else {
            return priceHistory
        }
        let cutoffStr = historyDateString(cutoff)
        return priceHistory.filter { $0.date >= cutoffStr }
    }

    // DateFormatter is expensive to construct; share a single static instance.
    static let historyDateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.timeZone = TimeZone(identifier: "UTC")
        return f
    }()

    func parseHistoryDate(_ str: String) -> Date? {
        Self.historyDateFormatter.date(from: str)
    }

    func historyDateString(_ date: Date) -> String {
        Self.historyDateFormatter.string(from: date)
    }

    func fiveDayAvgVolume(_ history: [ESIMarketHistory]) -> String {
        let recent = history.suffix(5)
        guard !recent.isEmpty else { return "—" }
        let avg = recent.map { Double($0.volume) }.reduce(0, +) / Double(recent.count)
        return formatCount(Int(avg))
    }

    func closestHistoryEntry(to date: Date) -> ESIMarketHistory? {
        filteredHistory.compactMap { entry -> (ESIMarketHistory, TimeInterval)? in
            guard let d = parseHistoryDate(entry.date) else { return nil }
            return (entry, abs(d.timeIntervalSince(date)))
        }.min(by: { $0.1 < $1.1 })?.0
    }

    /// Maps top-level market group names to EVE-relevant SF Symbols and accent colors.
    func marketGroupIcon(_ name: String) -> (symbol: String, color: Color) {
        let lower = name.lowercased()
        if lower.contains("ship")                                   { return ("airplane", Color(red: 0.35, green: 0.65, blue: 0.90)) }
        if lower.contains("module") || lower.contains("fitting")    { return ("cpu", .orange) }
        if lower.contains("ammo") || lower.contains("charge") || lower.contains("missile") { return ("bolt.fill", .yellow) }
        if lower.contains("drone")                                  { return ("ant.fill", .green) }
        if lower.contains("structure")                              { return ("building.2.fill", Color(red: 0.6, green: 0.6, blue: 0.7)) }
        if lower.contains("skill")                                  { return ("book.fill", Color(red: 0.35, green: 0.65, blue: 0.90)) }
        if lower.contains("implant") || lower.contains("booster")  { return ("brain.head.profile", .purple) }
        if lower.contains("blueprint")                              { return ("doc.fill", Color(red: 0.2, green: 0.75, blue: 0.8)) }
        if lower.contains("apparel") || lower.contains("clothing")  { return ("tshirt.fill", .pink) }
        if lower.contains("deployable")                             { return ("antenna.radiowaves.left.and.right", .cyan) }
        if lower.contains("fuel")                                   { return ("flame.fill", .orange) }
        if lower.contains("planetary") || lower.contains("colony") { return ("globe", .teal) }
        if lower.contains("commodity") || lower.contains("material") { return ("cube.fill", Color(red: 0.65, green: 0.5, blue: 0.35)) }
        if lower.contains("plex") || lower.contains("token")       { return ("creditcard.fill", .yellow) }
        return ("tag.fill", .secondary)
    }

    func securityColor(_ sec: Double) -> Color {
        switch sec {
        case 0.45...: return .green
        case 0.0..<0.45: return .orange
        default: return .red
        }
    }

    func regionEmoji(_ regionId: Int) -> String {
        switch regionId {
        case 10000002, 10000016, 10000033, 10000069:                    return "🔵" // Caldari
        case 10000036, 10000038, 10000043, 10000052, 10000054, 10000065: return "🟡" // Amarr
        case 10000032, 10000037, 10000044, 10000048, 10000064, 10000068: return "🟢" // Gallente
        case 10000028, 10000030, 10000042:                              return "🔴" // Minmatar
        case 10000001, 10000049:                                        return "🟡" // Ammatar/Khanid
        case 10000015:                                                  return "🟠" // Thukker
        default:                                                        return "⚫" // null-sec
        }
    }

    // Hardcoded region → faction color. Region faction affiliations are static
    // game data that essentially never changes between EVE patches.
    func regionColor(_ regionId: Int) -> Color {
        switch regionId {
        // Caldari — blue
        case 10000002, 10000016, 10000033, 10000069:
            return Color(red: 0.35, green: 0.65, blue: 0.90)
        // Amarr — gold
        case 10000036, 10000038, 10000043, 10000052, 10000054, 10000065:
            return Color(red: 0.90, green: 0.75, blue: 0.20)
        // Gallente — green
        case 10000032, 10000037, 10000044, 10000048, 10000064, 10000068:
            return Color(red: 0.25, green: 0.70, blue: 0.35)
        // Minmatar — red
        case 10000028, 10000030, 10000042:
            return Color(red: 0.85, green: 0.35, blue: 0.25)
        // Ammatar Mandate (Amarr-aligned) — dark gold
        case 10000001:
            return Color(red: 0.75, green: 0.60, blue: 0.15)
        // Khanid Kingdom — dark gold
        case 10000049:
            return Color(red: 0.75, green: 0.60, blue: 0.15)
        // Thukker Tribe lowsec — orange
        case 10000015:
            return Color(red: 0.85, green: 0.50, blue: 0.20)
        // Null-sec / NPC null / unaffiliated
        default:
            return Color.secondary
        }
    }

    static let countNumberFormatter: NumberFormatter = {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        return f
    }()

    func formatCount(_ value: Int) -> String {
        let abs = value < 0 ? -value : value
        switch abs {
        case 1_000_000_000...: return String(format: "%.1fB", Double(value) / 1_000_000_000)
        case 1_000_000...:     return String(format: "%.1fM", Double(value) / 1_000_000)
        case 10_000...:        return String(format: "%.1fK", Double(value) / 1_000)
        default:
            return Self.countNumberFormatter.string(from: NSNumber(value: value)) ?? "\(value)"
        }
    }

    func formatRange(_ range: String) -> String {
        switch range {
        case "station":    return "Station"
        case "solarsystem": return "System"
        case "region":     return "Region"
        case "1":          return "1 jump"
        case "2":          return "2 jumps"
        case "3":          return "3 jumps"
        case "4":          return "4 jumps"
        case "5":          return "5 jumps"
        case "10":         return "10 jumps"
        case "20":         return "20 jumps"
        case "30":         return "30 jumps"
        case "40":         return "40 jumps"
        default:           return range
        }
    }
}
