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

/// Local stargate-graph pathfinder used when a route needs to avoid specific systems.
/// ESI's `/route/{origin}/{destination}/` endpoint has no avoidance parameter, so this
/// walks the stargate graph directly with A*, lazily resolving each system's gates and
/// each gate's destination through `UniverseCache` (same fetch-and-disk-cache pattern
/// used for every other piece of static universe data — nothing here is bundled).
enum RoutePathfinder {

    enum RouteFlag: String {
        case shortest, secure, insecure
    }

    struct NoRouteError: LocalizedError {
        let avoidedCount: Int
        var errorDescription: String? {
            avoidedCount > 0
                ? "No route exists between these systems while avoiding \(avoidedCount) system(s)."
                : "No route found between these systems."
        }
    }

    /// Conservative upper bound on how far apart two stargate-connected systems can be.
    /// Used only to scale the A* heuristic — must never *underestimate* the true
    /// per-jump distance, or the heuristic stops being admissible and paths can come
    /// out non-optimal. 500 ly is comfortably above every known stargate span in New Eden.
    private static let maxJumpLightYears = 500.0
    private static let metersPerLightYear = 9.4607e15

    /// Returns the ordered list of system IDs from `originId` to `destinationId` (inclusive),
    /// avoiding every system in `avoid` (origin/destination are never treated as avoidable,
    /// even if present in the set). Throws `NoRouteError` if no such path exists.
    static func findRoute(
        from originId: Int,
        to destinationId: Int,
        avoiding avoid: Set<Int>,
        flag: RouteFlag
    ) async throws -> [Int] {
        let effectiveAvoid = avoid.subtracting([originId, destinationId])

        if originId == destinationId { return [originId] }

        guard let originSystem = await UniverseCache.shared.solarSystem(id: originId),
              let destinationSystem = await UniverseCache.shared.solarSystem(id: destinationId)
        else {
            throw NoRouteError(avoidedCount: effectiveAvoid.count)
        }

        var gScore: [Int: Double] = [originId: 0]
        var cameFrom: [Int: Int] = [:]
        var closed: Set<Int> = []
        var open = PriorityQueue<Int>()
        open.push(originId, priority: heuristic(from: originSystem, to: destinationSystem))

        while let current = open.pop() {
            guard !closed.contains(current) else { continue }
            if current == destinationId {
                return reconstructPath(cameFrom: cameFrom, current: current)
            }
            closed.insert(current)

            guard let currentSystem = await UniverseCache.shared.solarSystem(id: current) else { continue }
            let neighborIds = await neighbors(of: currentSystem)

            for neighborId in neighborIds {
                guard !effectiveAvoid.contains(neighborId), !closed.contains(neighborId) else { continue }
                guard let neighborSystem = await UniverseCache.shared.solarSystem(id: neighborId) else { continue }

                let tentativeG = (gScore[current] ?? .infinity) + edgeCost(entering: neighborSystem, flag: flag)
                if tentativeG < (gScore[neighborId] ?? .infinity) {
                    cameFrom[neighborId] = current
                    gScore[neighborId] = tentativeG
                    let f = tentativeG + heuristic(from: neighborSystem, to: destinationSystem)
                    open.push(neighborId, priority: f)
                }
            }
        }

        throw NoRouteError(avoidedCount: effectiveAvoid.count)
    }

    // MARK: Graph expansion

    private static func neighbors(of system: ESISolarSystem) async -> [Int] {
        guard let gates = system.stargates, !gates.isEmpty else { return [] }
        return await withTaskGroup(of: Int?.self) { group -> [Int] in
            for gateId in gates {
                group.addTask {
                    await UniverseCache.shared.stargate(id: gateId)?.destination.systemId
                }
            }
            var result: [Int] = []
            for await systemId in group {
                if let systemId { result.append(systemId) }
            }
            return result
        }
    }

    // MARK: Cost model — mirrors ESI's own shortest/secure/insecure `flag` semantics

    private static func edgeCost(entering system: ESISolarSystem, flag: RouteFlag) -> Double {
        switch flag {
        case .shortest:
            return 1
        case .secure:
            return system.securityStatus >= 0.5 ? 1 : 1000
        case .insecure:
            return system.securityStatus < 0.5 ? 1 : 1000
        }
    }

    /// Admissible A* heuristic: straight-line distance converted to a lower-bound jump
    /// count. Always an underestimate of true remaining cost since every edge costs >= 1.
    private static func heuristic(from: ESISolarSystem, to: ESISolarSystem) -> Double {
        guard let a = from.position, let b = to.position else { return 0 }
        let dx = a.x - b.x, dy = a.y - b.y, dz = a.z - b.z
        let distance = (dx * dx + dy * dy + dz * dz).squareRoot()
        return distance / (maxJumpLightYears * metersPerLightYear)
    }

    private static func reconstructPath(cameFrom: [Int: Int], current: Int) -> [Int] {
        var path = [current]
        var node = current
        while let previous = cameFrom[node] {
            path.append(previous)
            node = previous
        }
        return path.reversed()
    }
}

/// Minimal binary min-heap. No decrease-key support — callers push a fresh (lower)
/// priority for a node instead of updating in place, and skip stale pops via a
/// closed-set check (standard "lazy deletion" approach for array-backed A* heaps).
private struct PriorityQueue<Element> {
    private var storage: [(priority: Double, element: Element)] = []

    var isEmpty: Bool { storage.isEmpty }

    mutating func push(_ element: Element, priority: Double) {
        storage.append((priority, element))
        siftUp(from: storage.count - 1)
    }

    mutating func pop() -> Element? {
        guard !storage.isEmpty else { return nil }
        storage.swapAt(0, storage.count - 1)
        let top = storage.removeLast()
        siftDown(from: 0)
        return top.element
    }

    private mutating func siftUp(from index: Int) {
        var child = index
        while child > 0 {
            let parent = (child - 1) / 2
            guard storage[child].priority < storage[parent].priority else { break }
            storage.swapAt(child, parent)
            child = parent
        }
    }

    private mutating func siftDown(from index: Int) {
        var parent = index
        while true {
            let left = 2 * parent + 1
            let right = 2 * parent + 2
            var smallest = parent
            if left < storage.count, storage[left].priority < storage[smallest].priority { smallest = left }
            if right < storage.count, storage[right].priority < storage[smallest].priority { smallest = right }
            guard smallest != parent else { break }
            storage.swapAt(parent, smallest)
            parent = smallest
        }
    }
}
