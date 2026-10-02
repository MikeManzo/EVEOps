//
// This file is part of EVEOps.
//
// EVEOps is free software: you can redistribute it and/or modify
// it under the terms of the GNU General Public License as published by
// the Free Software Foundation, version 3 or later.
//
// Copyright (c) 2026 CitizenCoder
//

import Foundation
import OSLog

// MARK:  Snapshot

/// The pilot facts the inspector needs beyond the engine's input.
struct ReadyRoomPilotContext: Sendable {
    var currentSystemID: Int
    var shipTypeID: Int?
    var shipTypeName: String?
    /// Cargo capacity of the ship the pilot is in, m³.
    var shipCapacity: Double?
    /// Implants in the pilot's active clone.
    var implantIDs: [Int] = []
    /// Implant attribute bonuses, by attribute.
    var implantBonuses: [EVEAttribute: Int] = [:]
    var isRemapAvailable = false
    /// When the next clone jump is allowed; nil when it is already.
    var cloneJumpReadyAt: Date?
}

/// Everything the Ready Room shows for one pilot, plus the engine input it came from so
/// later stages (prices, jumps, the fitting check) fold in without refetching.
struct ReadyRoomSnapshot {
    let characterID: Int
    var input: ReadyRoomInput
    var reports: [ReadyRoomReport]
    var pilot: ReadyRoomPilotContext
    /// The system `input.jumps` was measured from.
    var jumpOrigin: Int?
    /// Set when corporation hangars were asked for but couldn't be read.
    var corporationNote: String?
    var fittingCheck: FittingCheckState = .pending
    /// Packaged volume (m³) per type in the fits, for the collection route's cargo check.
    var volumes: [Int: Double] = [:]

    enum FittingCheckState { case pending, unavailable, done }

    var places: [Int: ReadyRoomPlace] { input.places }
    var jumps: [Int: Int] { input.jumps }
}

// MARK:  Service

/// Loads and holds Ready Room results per pilot, for the screen, its sidebar badge, the
/// Dashboard's pinned-fits tile, and the background "now ready" notifications.
@MainActor
@Observable
final class ReadyRoomService {
    static let shared = ReadyRoomService()

    private(set) var snapshots: [Int: ReadyRoomSnapshot] = [:]
    private(set) var errors: [Int: String] = [:]
    private(set) var loading: Set<Int> = []
    /// Fits that became ready in the background since the pilot last opened the Ready Room.
    private(set) var unseenReady: [Int: Set<Int>] = [:]
    /// Bumped on pin changes so views reading `pinnedFittingIDs` re-render.
    private(set) var pinsVersion = 0

    var includeCorporation: Bool = UserDefaults.standard.bool(forKey: "readyRoom.includeCorp") {
        didSet { UserDefaults.standard.set(includeCorporation, forKey: "readyRoom.includeCorp") }
    }

    private var adjacencyCache: [Int: [Int]]?
    /// Fit-check results keyed by everything that affects them (hull, modules, skills,
    /// implants), so an unchanged fit isn't re-run through the engine on every refresh.
    private var fitCheckCache: [Int: ReadyRoomFittingCheck] = [:]
    private init() {}

    func isLoading(_ characterID: Int) -> Bool { loading.contains(characterID) }

    // MARK:  Pins

    private func pinsKey(_ characterID: Int) -> String { "readyRoom.pinned.\(characterID)" }

    func pinnedFittingIDs(for characterID: Int) -> Set<Int> {
        _ = pinsVersion
        return Set((UserDefaults.standard.array(forKey: pinsKey(characterID)) as? [Int]) ?? [])
    }

    func togglePin(_ fittingID: Int, characterID: Int) {
        var pins = pinnedFittingIDs(for: characterID)
        if !pins.insert(fittingID).inserted { pins.remove(fittingID) }
        UserDefaults.standard.set(Array(pins).sorted(), forKey: pinsKey(characterID))
        pinsVersion += 1
    }

    func markSeen(_ characterID: Int) {
        unseenReady[characterID] = nil
    }

    // MARK:  Topology

    /// Stargate adjacency, built once from the galaxy topology.
    func adjacency() async -> [Int: [Int]]? {
        if let adjacencyCache { return adjacencyCache }
        guard let topology = await UniverseTopology.shared.load() else { return nil }
        let built = await Task.detached(priority: .userInitiated) { ReadyRoomEngine.adjacency(topology.jumps) }.value
        adjacencyCache = built
        return built
    }

    // MARK:  Refresh

    /// Loads the board for `account` in stages, publishing after each: the board itself,
    /// then prices and jump counts, then the dogma fitting check. `interactive` false
    /// (background polling) skips prices and never starts a download.
    func refresh(_ account: StoredAccount, accountManager: AccountManager, prefetcher: DashboardPrefetcher,
                 force: Bool = false, interactive: Bool = true) async {
        let characterID = account.characterID
        guard loading.insert(characterID).inserted else { return }
        defer { loading.remove(characterID) }

        do {
            let token = try await accountManager.validToken(for: account)
            let loader = Loader(characterID: characterID, corporationID: account.corporationID, token: token,
                                force: force, prefetched: prefetcher.data(for: characterID),
                                includeCorporation: includeCorporation)
            var snapshot = try await loader.board()
            let previous = snapshots[characterID]
            snapshot.input.prices = previous?.input.prices ?? [:]
            if previous?.jumpOrigin == snapshot.pilot.currentSystemID {
                snapshot.input.jumps = previous?.input.jumps ?? [:]
                snapshot.jumpOrigin = previous?.jumpOrigin
            }
            // Keep the last fitting check until a new one runs, so fits don't jump tiers
            // in between (or, in the background, without the engine at all).
            if let previous, previous.fittingCheck == .done {
                snapshot.input.fittingChecks = previous.input.fittingChecks
                snapshot.input.requirements.merge(previous.input.requirements) { new, _ in new }
                snapshot.input.skillInfo.merge(previous.input.skillInfo) { new, _ in new }
                snapshot.fittingCheck = .done
            }
            await publish(snapshot)
            errors[characterID] = nil

            if interactive {
                // Prices and distances.
                let typeIDs = Array(Set(snapshot.input.fittings.flatMap { [$0.shipTypeId] + $0.items.map(\.typeId) }))
                async let pricesRequest = FuzzworkClient.shared.prices(typeIds: typeIDs)
                async let adjacencyRequest = adjacency()
                if let prices = try? await pricesRequest {
                    snapshot.input.prices = prices.compactMapValues { $0.sellMin > 0 ? $0.sellMin : nil }
                }
                if let adjacency = await adjacencyRequest {
                    let origin = snapshot.pilot.currentSystemID
                    snapshot.input.jumps = await Task.detached(priority: .userInitiated) {
                        ReadyRoomEngine.jumpDistances(from: origin, adjacency: adjacency)
                    }.value
                    snapshot.jumpOrigin = origin
                }
                await publish(snapshot)
            }

            // Does it actually fit? (CPU / powergrid / calibration.)
            if await ReadyRoomFittingChecker.prepareEngine(allowLoad: interactive) {
                var cache = fitCheckCache
                await loader.addFittingChecks(to: &snapshot, cache: &cache)
                fitCheckCache = cache
                snapshot.fittingCheck = .done
            } else if snapshot.fittingCheck != .done {
                snapshot.fittingCheck = .unavailable
            }
            await publish(snapshot)
        } catch {
            errors[characterID] = error.localizedDescription
        }
    }

    /// Runs the engine off the main actor, stores the result, and records each fit's tier
    /// so the background check can tell what changed.
    private func publish(_ snapshot: ReadyRoomSnapshot) async {
        var snapshot = snapshot
        let input = snapshot.input
        snapshot.reports = await Task.detached(priority: .userInitiated) { ReadyRoomEngine.reports(input) }.value
        snapshots[snapshot.characterID] = snapshot
    }

    // MARK:  Background

    private func tiersKey(_ characterID: Int) -> String { "readyRoom.tiers.\(characterID)" }

    /// Refreshes every pilot and notifies about fits that became ready (or flyable) since
    /// the last check. The first check for a pilot only records a baseline.
    func backgroundCheck(accountManager: AccountManager, prefetcher: DashboardPrefetcher) async {
        let defaults = UserDefaults.standard
        guard defaults.object(forKey: "notificationsEnabled") as? Bool ?? true,
              defaults.object(forKey: "notifyReadyRoom") as? Bool ?? true else { return }

        for account in accountManager.accounts {
            await refresh(account, accountManager: accountManager, prefetcher: prefetcher, interactive: false)
            guard let snapshot = snapshots[account.characterID], snapshot.fittingCheck != .pending else { continue }

            let key = tiersKey(account.characterID)
            let stored = defaults.dictionary(forKey: key) as? [String: Int]
            var current: [String: Int] = [:]
            for report in snapshot.reports { current[String(report.fittingID)] = report.tier.rawValue }
            defaults.set(current, forKey: key)
            guard let stored else { continue }

            let improved = snapshot.reports.filter { report in
                guard let raw = stored[String(report.fittingID)], let before = ReadyRoomTier(rawValue: raw) else { return false }
                let becameReady = report.tier == .ready && before != .ready
                let becameFlyable = before >= .train && report.tier < .train
                return becameReady || becameFlyable
            }
            guard !improved.isEmpty else { continue }
            unseenReady[account.characterID, default: []].formUnion(improved.map(\.fittingID))
            await NotificationService.shared.notifyReadyRoom(
                characterID: account.characterID,
                characterName: account.characterName,
                fits: improved.map { report in
                    (name: report.name,
                     detail: report.tier == .ready
                        ? String(localized: "ready to undock")
                        : String(localized: "now flyable"),
                     shipTypeID: report.shipTypeID)
                }
            )
        }
    }
}

// MARK:  Loader

/// One pilot's fetches and the engine input built from them.
@MainActor
private struct Loader {
    let characterID: Int
    let corporationID: Int
    let token: String
    let force: Bool
    let prefetched: DashboardPrefetcher.PrefetchedCharacterData?
    let includeCorporation: Bool

    private struct PilotState {
        let skills: ESISkillsResponse
        let queue: [ESISkillQueue]
        let attributes: ESICharacterAttributes?
        let location: ESICharacterLocation
        let ship: ESICharacterShip?
        let implants: [Int]
        let clones: ESIClonesResponse?
        let orders: [ESIMarketOrder]
        let jobs: [ESIIndustryJob]
        let contracts: [ESIContract]
    }

    // MARK:  Board

    func board() async throws -> ReadyRoomSnapshot {
        async let fittingsRequest: [ESIFitting] = ESIClient.shared.fetch(
            "/characters/\(characterID)/fittings/", token: token, bypassCache: force
        )
        async let assetsRequest: [ESIAsset] = ESIClient.shared.fetchPages(
            "/characters/\(characterID)/assets/", token: token, bypassCache: force
        )
        let pilot = try await pilotState()
        let fittings = try await fittingsRequest
        let assets = Self.deduplicated(try await assetsRequest)

        var corporationAssets: [ESIAsset] = []
        var corporationNote: String?
        if includeCorporation {
            do {
                corporationAssets = Self.deduplicated(try await ESIClient.shared.fetchPages(
                    "/corporations/\(corporationID)/assets/", token: token, bypassCache: force
                ))
            } catch ESIError.forbidden {
                corporationNote = String(localized: "Corporation hangars need the Director role.")
            } catch {
                corporationNote = String(localized: "Couldn’t read corporation hangars: \(error.localizedDescription)")
            }
        }

        let hullIDs = Set(fittings.map(\.shipTypeId))
        let fitTypeIDs = hullIDs.union(fittings.flatMap(\.items).map(\.typeId))
        let jobProducts = Set(pilot.jobs.compactMap(\.productTypeId))
        var typeIDs = fitTypeIDs.union(jobProducts).union(pilot.implants)
        if let ship = pilot.ship { typeIDs.insert(ship.shipTypeId) }
        let types = await UniverseCache.shared.types(ids: Array(typeIDs))

        // Ship classes: the Fittings screen's static table first, then the live group name.
        var shipClassNames: [Int: String] = [:]
        for hull in hullIDs {
            guard let groupID = types[hull]?.groupId else { continue }
            if let name = CharacterFittingsView.eveShipGroups[groupID] {
                shipClassNames[hull] = name
            } else if let group = await UniverseCache.shared.group(id: groupID) {
                shipClassNames[hull] = group.name
            }
        }

        // Skills gate the hull and fitted modules; cargo never does.
        let gatedTypeIDs = hullIDs.union(fittings.flatMap(\.items)
            .filter { ReadyRoomEngine.slotCategory($0.flag) != "Cargo" }
            .map(\.typeId))
        let requirements = await SkillPrerequisites.shared.requirements(for: Array(gatedTypeIDs))
        let skillInfo = await SkillPrerequisites.shared.trainingInfo(for: Array(Set(requirements.values.flatMap(\.keys))))

        let location = pilot.location
        let currentPlaceID = location.stationId ?? location.structureId ?? location.solarSystemId
        let holdings = ReadyRoomEngine.holdings(from: assets, pilotedShip: pilot.ship, pilotPlaceID: currentPlaceID)
            + ReadyRoomEngine.holdings(from: corporationAssets, pilotedShip: nil, pilotPlaceID: nil, isCorporation: true)
        let incoming = await incoming(pilot: pilot, fitTypeIDs: fitTypeIDs, types: types,
                                      roots: .init(byID: Dictionary(assets.map { ($0.itemId, $0) }, uniquingKeysWith: { a, _ in a })))

        // Only places holding (or receiving) something a fit uses need names — big asset
        // lists span hundreds of stations.
        var placeIDs = Set(holdings.filter { fitTypeIDs.contains($0.typeID) }.map(\.placeID))
        placeIDs.formUnion(incoming.compactMap(\.placeID))
        placeIDs.insert(currentPlaceID)
        let places = await resolvePlaces(placeIDs)

        var skills: [Int: ReadyRoomSkillLevel] = [:]
        for skill in pilot.skills.skills {
            skills[skill.skillId] = ReadyRoomSkillLevel(active: skill.activeSkillLevel, trained: skill.trainedSkillLevel,
                                                        sp: skill.skillpointsInSkill)
        }

        var input = ReadyRoomInput(
            fittings: fittings,
            typeNames: types.mapValues(\.name),
            shipClassNames: shipClassNames,
            requirements: requirements,
            skillInfo: skillInfo,
            skills: skills,
            skillQueue: pilot.queue,
            attributes: pilot.attributes,
            holdings: holdings,
            places: places,
            currentPlaceID: currentPlaceID,
            jumps: [:],
            prices: [:]
        )
        input.incoming = incoming
        input.jumpClonePlaceIDs = Set(pilot.clones?.jumpClones.map(\.locationId) ?? [])

        let shipType = pilot.ship.flatMap { types[$0.shipTypeId] }
        let context = ReadyRoomPilotContext(
            currentSystemID: location.solarSystemId,
            shipTypeID: pilot.ship?.shipTypeId,
            shipTypeName: shipType?.name,
            shipCapacity: shipType?.capacity,
            implantIDs: pilot.implants,
            implantBonuses: Self.implantBonuses(pilot.implants.compactMap { types[$0] }),
            isRemapAvailable: pilot.attributes.map(Self.isRemapAvailable) ?? false,
            cloneJumpReadyAt: Self.cloneJumpReadyAt(pilot.clones, skills: skills)
        )

        return ReadyRoomSnapshot(
            characterID: characterID,
            input: input,
            reports: [],
            pilot: context,
            jumpOrigin: nil,
            corporationNote: corporationNote,
            volumes: types.compactMapValues { $0.packagedVolume ?? $0.volume }
        )
    }

    private static func deduplicated(_ assets: [ESIAsset]) -> [ESIAsset] {
        // ESI can repeat an item across pages while it moves; keep the first copy.
        var seen = Set<Int>()
        return assets.filter { seen.insert($0.itemId).inserted }
    }

    /// The pilot's own state, from the prefetcher when it's fresh, otherwise from ESI.
    private func pilotState() async throws -> PilotState {
        if let data = prefetched {
            return PilotState(skills: data.skills, queue: data.skillQueue, attributes: data.attributes,
                              location: data.location, ship: data.ship, implants: data.implantIDs,
                              clones: data.clones, orders: data.marketOrders, jobs: data.industryJobs,
                              contracts: data.contracts)
        }
        let base = "/characters/\(characterID)"
        async let skills: ESISkillsResponse = ESIClient.shared.fetch("\(base)/skills/", token: token)
        async let queue: [ESISkillQueue] = ESIClient.shared.fetch("\(base)/skillqueue/", token: token)
        async let attributes: ESICharacterAttributes? = try? ESIClient.shared.fetch("\(base)/attributes/", token: token)
        async let location: ESICharacterLocation = ESIClient.shared.fetch("\(base)/location/", token: token)
        async let ship: ESICharacterShip? = try? ESIClient.shared.fetch("\(base)/ship/", token: token)
        async let implants: [Int]? = try? ESIClient.shared.fetch("\(base)/implants/", token: token)
        async let clones: ESIClonesResponse? = try? ESIClient.shared.fetch("\(base)/clones/", token: token)
        async let orders: [ESIMarketOrder]? = try? ESIClient.shared.fetch("\(base)/orders/", token: token)
        async let jobs: [ESIIndustryJob]? = try? ESIClient.shared.fetch("\(base)/industry/jobs/", token: token)
        async let contracts: [ESIContract]? = try? ESIClient.shared.fetchPages("\(base)/contracts/", token: token)
        return try await PilotState(skills: skills, queue: queue, attributes: attributes, location: location,
                                    ship: ship, implants: implants ?? [], clones: clones, orders: orders ?? [],
                                    jobs: jobs ?? [], contracts: contracts ?? [])
    }

    // MARK:  Incoming

    private struct ContractItem: Decodable {
        let typeId: Int
        let quantity: Int
        let isIncluded: Bool
    }

    /// Parts on their way: open buy orders, manufacturing jobs, and courier contracts the
    /// pilot issued — only for types the fits use.
    private func incoming(pilot: PilotState, fitTypeIDs: Set<Int>, types: [Int: ESIType],
                          roots: ReadyRoomEngine.RootResolver) async -> [ReadyRoomIncoming] {
        var out: [ReadyRoomIncoming] = []
        for order in pilot.orders where order.isBuyOrder == true && fitTypeIDs.contains(order.typeId) && order.volumeRemain > 0 {
            out.append(ReadyRoomIncoming(kind: .buyOrder, typeID: order.typeId, quantity: order.volumeRemain,
                                         placeID: order.locationId, eta: nil))
        }
        for job in pilot.jobs where job.activityId == 1 && ["active", "paused", "ready"].contains(job.status) {
            guard let product = job.productTypeId, fitTypeIDs.contains(product) else { continue }
            let perRun = max(types[product]?.portionSize ?? 1, 1)
            out.append(ReadyRoomIncoming(kind: .industry, typeID: product, quantity: job.runs * perRun,
                                         placeID: roots.root(of: job.outputLocationId), eta: job.endDate))
        }
        let couriers = pilot.contracts.filter {
            $0.type == "courier" && $0.issuerId == characterID && ["outstanding", "in_progress"].contains($0.status)
        }.prefix(20)
        for contract in couriers {
            guard let items: [ContractItem] = try? await ESIClient.shared.fetch(
                "/characters/\(characterID)/contracts/\(contract.contractId)/items/", token: token
            ) else { continue }
            let due = contract.dateAccepted.flatMap { accepted in
                contract.daysToComplete.map { accepted.addingTimeInterval(Double($0) * 86_400) }
            }
            for item in items where item.isIncluded && fitTypeIDs.contains(item.typeId) {
                out.append(ReadyRoomIncoming(kind: .courier, typeID: item.typeId, quantity: item.quantity,
                                             placeID: contract.endLocationId, eta: due))
            }
        }
        return out
    }

    // MARK:  Pilot facts

    /// Implant attribute bonuses, the same way Training reads them.
    private static func implantBonuses(_ implants: [ESIType]) -> [EVEAttribute: Int] {
        var out: [EVEAttribute: Int] = [:]
        for implant in implants {
            for attribute in EVEAttribute.allCases {
                if let v = implant.dogmaAttributes?.first(where: { $0.attributeId == attribute.implantBonusDogmaID })?.value, v > 0 {
                    out[attribute, default: 0] += Int(v)
                }
            }
        }
        return out
    }

    private static func isRemapAvailable(_ attributes: ESICharacterAttributes) -> Bool {
        if (attributes.bonusRemaps ?? 0) > 0 { return true }
        if let cooldown = attributes.accruedRemapCooldownDate { return cooldown <= .now }
        guard let last = attributes.lastRemapDate else { return true }
        return (Calendar.current.date(byAdding: .year, value: 1, to: last) ?? .distantFuture) <= .now
    }

    private static func cloneJumpReadyAt(_ clones: ESIClonesResponse?, skills: [Int: ReadyRoomSkillLevel]) -> Date? {
        IdleCapacityEngine.cloneJumpReadyAt(
            lastJump: clones?.lastCloneJumpDate,
            infomorphSynchronizing: skills[IdleCapacityEngine.Skill.infomorphSynchronizing]?.active ?? 0
        )
    }

    // MARK:  Places

    /// Names, systems and security for stations, structures and (for ships in space)
    /// solar systems, resolved in parallel.
    private func resolvePlaces(_ ids: Set<Int>) async -> [Int: ReadyRoomPlace] {
        let token = token
        return await withTaskGroup(of: ReadyRoomPlace.self) { group in
            for id in ids {
                group.addTask {
                    var name: String?
                    var systemID: Int?
                    switch id {
                    case 30_000_000..<33_000_000:
                        systemID = id
                    case 60_000_000..<64_000_000:
                        if let station = await UniverseCache.shared.station(id: id) {
                            name = station.name
                            systemID = station.systemId
                        }
                    case 1_000_000_000...:
                        if let structure: ESIStructure = try? await ESIClient.shared.fetch("/universe/structures/\(id)/", token: token) {
                            name = structure.name
                            systemID = structure.solarSystemId
                        }
                    default:
                        break
                    }
                    var system: ESISolarSystem?
                    if let systemID { system = await UniverseCache.shared.solarSystem(id: systemID) }
                    let resolvedName: String
                    if let name {
                        resolvedName = name
                    } else if let system {
                        resolvedName = String(localized: "In space · \(system.name)")
                    } else {
                        resolvedName = await NameResolver.shared.resolveLocation(id: id, token: token)
                    }
                    return ReadyRoomPlace(id: id, name: resolvedName, systemID: systemID,
                                          systemName: system?.name, security: system?.securityStatus)
                }
            }
            var out: [Int: ReadyRoomPlace] = [:]
            for await place in group { out[place.id] = place }
            return out
        }
    }

    // MARK:  Fitting check

    /// Runs each fit through the dogma engine, and adds the fitting skills' own
    /// prerequisites and training info so the engine can cost them.
    func addFittingChecks(to snapshot: inout ReadyRoomSnapshot, cache: inout [Int: ReadyRoomFittingCheck]) async {
        let fittings = snapshot.input.fittings
        let typeIDs = Set(fittings.flatMap { [$0.shipTypeId] + $0.items.map(\.typeId) })
        let types = await UniverseCache.shared.types(ids: Array(typeIDs))
        let skills = snapshot.input.skills.mapValues(\.active)
        let implants = snapshot.pilot.implantIDs

        var pilotKey = Hasher()
        for (skill, level) in skills.sorted(by: { $0.key < $1.key }) { pilotKey.combine(skill); pilotKey.combine(level) }
        pilotKey.combine(implants)
        let pilotHash = pilotKey.finalize()

        var checks: [Int: ReadyRoomFittingCheck] = [:]
        for fitting in fittings {
            var key = Hasher()
            key.combine(pilotHash)
            key.combine(fitting.shipTypeId)
            key.combine(fitting.items)
            let cacheKey = key.finalize()
            if let cached = cache[cacheKey] {
                checks[fitting.fittingId] = cached
                continue
            }
            if let check = ReadyRoomFittingChecker.check(fitting: fitting, skills: skills, implants: implants,
                                                         shipType: types[fitting.shipTypeId], moduleTypes: types) {
                checks[fitting.fittingId] = check
                cache[cacheKey] = check
            }
            await Task.yield()   // the engine runs on the main actor; keep the UI responsive
        }
        snapshot.input.fittingChecks = checks

        let fittingSkills = Set(checks.values.flatMap(\.skillsToFit.keys))
        guard !fittingSkills.isEmpty else { return }
        let extra = await SkillPrerequisites.shared.requirements(for: Array(fittingSkills))
        snapshot.input.requirements.merge(extra) { _, new in new }
        let allSkills = fittingSkills.union(extra.values.flatMap(\.keys))
        let info = await SkillPrerequisites.shared.trainingInfo(for: Array(allSkills))
        snapshot.input.skillInfo.merge(info) { _, new in new }
    }
}
