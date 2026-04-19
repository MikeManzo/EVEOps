import SwiftUI

struct ConstellationMapView: View {
    let constellationId: Int
    let currentSystemId: Int
    let constellationName: String

    @State private var systems: [MapSystem] = []
    @State private var connections: [MapConnection] = []
    @State private var externalConnections: [ExternalConnection] = []
    @State private var killsData: [Int: ESISystemKills] = [:]
    @State private var jumpsData: [Int: Int] = [:]
    @State private var isLoading = true
    @State private var hoveredSystem: Int?
    @State private var selectedSystem: MapSystem?
    @State private var scale: CGFloat = 1.0
    @State private var offset: CGSize = .zero
    @State private var dragStart: CGSize = .zero
    @State private var pulsePhase: CGFloat = 0
    @State private var showActivity = true
    @State private var starfieldSeeds: [(CGFloat, CGFloat, CGFloat)] = []

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            mapHeader

            if isLoading {
                ProgressView("Loading star map...")
                    .frame(maxWidth: .infinity, minHeight: 350)
            } else {
                ZStack {
                    mapCanvas
                    if let sys = selectedSystem {
                        systemPopover(sys)
                    }
                }

                mapLegend
            }
        }
        .task { await loadConstellationData() }
        .task(id: "pulse") {
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(50))
                withAnimation(.linear(duration: 0.05)) {
                    pulsePhase += 0.03
                    if pulsePhase > .pi * 2 { pulsePhase -= .pi * 2 }
                }
            }
        }
        .onAppear {
            if starfieldSeeds.isEmpty {
                starfieldSeeds = (0..<120).map { _ in
                    (CGFloat.random(in: 0...1), CGFloat.random(in: 0...1), CGFloat.random(in: 0.2...0.8))
                }
            }
        }
    }

    // MARK:  Header

    private var mapHeader: some View {
        HStack {
            Image(systemName: "map.fill")
                .foregroundStyle(.blue)
            Text(constellationName)
                .font(.subheadline.bold())
            Text("(\(systems.count) systems)")
                .font(.caption)
                .foregroundStyle(.secondary)

            Spacer()

            Toggle(isOn: $showActivity) {
                Label("Activity", systemImage: "flame.fill")
                    .font(.caption)
            }
            .toggleStyle(.switch)
            .controlSize(.mini)

            HStack(spacing: 4) {
                Button { withAnimation { scale = max(0.5, scale - 0.25) } } label: {
                    Image(systemName: "minus.magnifyingglass").font(.caption)
                }
                .buttonStyle(.plain)

                Text("\(Int(scale * 100))%")
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .frame(width: 36)

                Button { withAnimation { scale = min(3.0, scale + 0.25) } } label: {
                    Image(systemName: "plus.magnifyingglass").font(.caption)
                }
                .buttonStyle(.plain)

                Button {
                    withAnimation { scale = 1.0; offset = .zero; dragStart = .zero }
                } label: {
                    Image(systemName: "arrow.counterclockwise").font(.caption)
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK:  Map Canvas

    private var mapCanvas: some View {
        GeometryReader { geo in
            let size = geo.size
            let projected = projectSystems(in: size)

            Canvas { context, canvasSize in
                // Starfield background
                for seed in starfieldSeeds {
                    let pt = CGPoint(x: seed.0 * canvasSize.width, y: seed.1 * canvasSize.height)
                    let r: CGFloat = seed.2 < 0.4 ? 0.5 : (seed.2 < 0.7 ? 1.0 : 1.5)
                    let rect = CGRect(x: pt.x - r, y: pt.y - r, width: r * 2, height: r * 2)
                    context.fill(Circle().path(in: rect), with: .color(.white.opacity(Double(seed.2) * 0.4)))
                }

                // External constellation connections (faded, going to edge)
                for ext in externalConnections {
                    guard let fromPt = projected[ext.fromSystemId] else { continue }
                    let from = applyTransform(fromPt, size: canvasSize)

                    // Project toward edge of canvas
                    let angle = ext.angle
                    let edgePt = CGPoint(
                        x: from.x + cos(angle) * 200,
                        y: from.y + sin(angle) * 200
                    )

                    var path = Path()
                    path.move(to: from)
                    path.addLine(to: edgePt)

                    context.stroke(
                        path,
                        with: .color(.white.opacity(0.08)),
                        style: StrokeStyle(lineWidth: 1, dash: [4, 4])
                    )

                    // Constellation name at edge
                    let label = Text(ext.destinationName)
                        .font(.system(size: 8))
                        .foregroundColor(.white.opacity(0.3))
                    let resolved = context.resolve(label)
                    context.draw(resolved, at: edgePt)
                }

                // Internal connections
                for conn in connections {
                    guard let from = projected[conn.fromSystemId],
                          let to = projected[conn.toSystemId] else { continue }
                    let fromPt = applyTransform(from, size: canvasSize)
                    let toPt = applyTransform(to, size: canvasSize)

                    var path = Path()
                    path.move(to: fromPt)
                    path.addLine(to: toPt)

                    let touchesCurrent = conn.fromSystemId == currentSystemId || conn.toSystemId == currentSystemId

                    // Color by destination security
                    let destSec = conn.fromSystemId == currentSystemId
                        ? (systems.first { $0.systemId == conn.toSystemId }?.securityStatus ?? 0)
                        : (systems.first { $0.systemId == conn.fromSystemId }?.securityStatus ?? 0)

                    let lineColor: Color = touchesCurrent
                        ? securityColor(destSec).opacity(0.7)
                        : .white.opacity(0.15)
                    let lineWidth: CGFloat = touchesCurrent ? 2.0 : 1.0

                    context.stroke(path, with: .color(lineColor), lineWidth: lineWidth)
                }

                // Systems
                for sys in systems {
                    guard let pt = projected[sys.systemId] else { continue }
                    let transformed = applyTransform(pt, size: canvasSize)

                    let isCurrent = sys.systemId == currentSystemId
                    let isHovered = sys.systemId == hoveredSystem

                    // Activity rings (kills/jumps)
                    if showActivity {
                        let kills = killsData[sys.systemId]
                        let shipKills = kills?.shipKills ?? 0
                        let npcKills = kills?.npcKills ?? 0
                        let jumps = jumpsData[sys.systemId] ?? 0

                        // Jump activity - outer blue ring
                        if jumps > 0 {
                            let jumpRadius = CGFloat(min(jumps, 500)) / 500.0 * 16 + 10
                            let jumpRect = CGRect(
                                x: transformed.x - jumpRadius,
                                y: transformed.y - jumpRadius,
                                width: jumpRadius * 2, height: jumpRadius * 2
                            )
                            context.stroke(
                                Circle().path(in: jumpRect),
                                with: .color(.blue.opacity(0.2)),
                                lineWidth: 1.5
                            )
                        }

                        // Ship kills - red ring
                        if shipKills > 0 {
                            let killRadius = CGFloat(min(shipKills, 100)) / 100.0 * 12 + 8
                            let killRect = CGRect(
                                x: transformed.x - killRadius,
                                y: transformed.y - killRadius,
                                width: killRadius * 2, height: killRadius * 2
                            )
                            context.fill(
                                Circle().path(in: killRect),
                                with: .color(.red.opacity(Double(min(shipKills, 50)) / 50.0 * 0.25))
                            )
                        }

                        // NPC kills - subtle orange dot if high
                        if npcKills > 100 {
                            let npcRadius = CGFloat(min(npcKills, 5000)) / 5000.0 * 10 + 6
                            let npcRect = CGRect(
                                x: transformed.x - npcRadius,
                                y: transformed.y - npcRadius,
                                width: npcRadius * 2, height: npcRadius * 2
                            )
                            context.fill(
                                Circle().path(in: npcRect),
                                with: .color(.orange.opacity(0.08))
                            )
                        }
                    }

                    // Pulse glow for current system
                    if isCurrent {
                        let pulseSize = 14 + sin(pulsePhase) * 4
                        let glowRect = CGRect(
                            x: transformed.x - pulseSize,
                            y: transformed.y - pulseSize,
                            width: pulseSize * 2, height: pulseSize * 2
                        )
                        context.fill(
                            Circle().path(in: glowRect),
                            with: .color(.blue.opacity(0.15 + sin(pulsePhase) * 0.1))
                        )
                    }

                    let radius: CGFloat = isCurrent ? 8 : (isHovered ? 7 : 5)
                    let rect = CGRect(
                        x: transformed.x - radius,
                        y: transformed.y - radius,
                        width: radius * 2, height: radius * 2
                    )
                    context.fill(Circle().path(in: rect), with: .color(securityColor(sys.securityStatus)))
                    context.stroke(
                        Circle().path(in: rect),
                        with: .color(isCurrent ? .white : .white.opacity(0.3)),
                        lineWidth: isCurrent ? 2 : 0.5
                    )

                    // Station indicator
                    if sys.stationCount > 0 {
                        let stationRect = CGRect(x: transformed.x + radius - 1, y: transformed.y - radius - 2, width: 4, height: 4)
                        context.fill(
                            RoundedRectangle(cornerRadius: 1).path(in: stationRect),
                            with: .color(.teal)
                        )
                    }

                    // System name label
                    let label = Text(sys.name)
                        .font(.system(size: isCurrent ? 11 : 9, weight: isCurrent ? .bold : .regular))
                        .foregroundColor(isCurrent ? .white : .white.opacity(0.7))
                    let resolved = context.resolve(label)
                    let labelSize = resolved.measure(in: canvasSize)
                    context.draw(
                        resolved,
                        at: CGPoint(x: transformed.x, y: transformed.y + radius + labelSize.height / 2 + 3)
                    )

                    // Security + activity numbers
                    var subLabels: [String] = [String(format: "%.1f", sys.securityStatus)]
                    if showActivity {
                        let kills = killsData[sys.systemId]
                        if let sk = kills?.shipKills, sk > 0 { subLabels.append("\(sk)k") }
                        if let j = jumpsData[sys.systemId], j > 0 { subLabels.append("\(j)j") }
                    }
                    let secLabel = Text(subLabels.joined(separator: " "))
                        .font(.system(size: 8))
                        .foregroundColor(securityColor(sys.securityStatus).opacity(0.8))
                    let resolvedSec = context.resolve(secLabel)
                    context.draw(
                        resolvedSec,
                        at: CGPoint(x: transformed.x, y: transformed.y + radius + labelSize.height + 12)
                    )
                }
            }
            // Hit testing overlay
            .overlay {
                ForEach(systems, id: \.systemId) { sys in
                    if let pt = projected[sys.systemId] {
                        let transformed = applyTransform(pt, size: size)
                        Circle()
                            .fill(.clear)
                            .frame(width: 30, height: 30)
                            .contentShape(Circle())
                            .position(transformed)
                            .onHover { hovering in hoveredSystem = hovering ? sys.systemId : nil }
                            .onTapGesture {
                                withAnimation(.easeInOut(duration: 0.2)) {
                                    selectedSystem = (selectedSystem?.systemId == sys.systemId) ? nil : sys
                                }
                            }
                    }
                }
            }
            .gesture(
                DragGesture()
                    .onChanged { value in
                        offset = CGSize(
                            width: dragStart.width + value.translation.width,
                            height: dragStart.height + value.translation.height
                        )
                    }
                    .onEnded { _ in dragStart = offset }
            )
            .gesture(
                MagnifyGesture()
                    .onChanged { value in scale = min(3.0, max(0.5, value.magnification)) }
            )
        }
        .frame(minHeight: 380)
        .background(Color(white: 0.03), in: RoundedRectangle(cornerRadius: 8))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    // MARK:  System Popover

    private func systemPopover(_ sys: MapSystem) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(sys.name).font(.caption.bold())
                securityBadge(sys.securityStatus)
                Spacer()
                Button { selectedSystem = nil } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }

            if sys.systemId == currentSystemId {
                Label("You are here", systemImage: "location.fill")
                    .font(.caption2).foregroundStyle(.blue)
            }

            let connCount = connections.filter { $0.fromSystemId == sys.systemId || $0.toSystemId == sys.systemId }.count
            let extCount = externalConnections.filter { $0.fromSystemId == sys.systemId }.count

            Label("\(connCount) internal gate\(connCount == 1 ? "" : "s")", systemImage: "arrow.triangle.branch")
                .font(.caption2).foregroundStyle(.secondary)

            if extCount > 0 {
                let extNames = externalConnections
                    .filter { $0.fromSystemId == sys.systemId }
                    .map(\.destinationName)
                Label("\(extCount) external \u{2192} \(extNames.joined(separator: ", "))", systemImage: "arrow.right.circle")
                    .font(.caption2).foregroundStyle(.orange)
            }

            if sys.stationCount > 0 {
                Label("\(sys.stationCount) station\(sys.stationCount == 1 ? "" : "s")", systemImage: "building.2.fill")
                    .font(.caption2).foregroundStyle(.teal)
            }

            // Connected systems within constellation
            let connectedNames = connections
                .filter { $0.fromSystemId == sys.systemId || $0.toSystemId == sys.systemId }
                .compactMap { conn -> String? in
                    let otherId = conn.fromSystemId == sys.systemId ? conn.toSystemId : conn.fromSystemId
                    return systems.first { $0.systemId == otherId }?.name
                }
            if !connectedNames.isEmpty {
                Text("Connects to: \(connectedNames.joined(separator: ", "))")
                    .font(.caption2).foregroundStyle(.secondary)
            }

            // Activity data
            if let kills = killsData[sys.systemId] {
                Divider()
                HStack(spacing: 12) {
                    if kills.shipKills > 0 {
                        Label("\(kills.shipKills) ship kills", systemImage: "flame.fill")
                            .font(.caption2).foregroundStyle(.red)
                    }
                    if kills.podKills > 0 {
                        Label("\(kills.podKills) pod kills", systemImage: "person.fill.xmark")
                            .font(.caption2).foregroundStyle(.red)
                    }
                    if kills.npcKills > 0 {
                        Label("\(kills.npcKills) NPC kills", systemImage: "target")
                            .font(.caption2).foregroundStyle(.orange)
                    }
                }
            }
            if let jumps = jumpsData[sys.systemId], jumps > 0 {
                Label("\(jumps) jumps (last hour)", systemImage: "arrow.left.arrow.right")
                    .font(.caption2).foregroundStyle(.blue)
            }
        }
        .padding(10)
        .frame(width: 260)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 8))
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
        .padding(8)
    }

    // MARK:  Legend

    private var mapLegend: some View {
        HStack(spacing: 10) {
            legendItem(color: .cyan, label: "1.0")
            legendItem(color: .green, label: "0.7+")
            legendItem(color: .yellow, label: "0.5+")
            legendItem(color: .orange, label: "0.1+")
            legendItem(color: .red, label: "0.0-")

            Divider().frame(height: 12)

            HStack(spacing: 4) {
                Circle().fill(.blue).frame(width: 8, height: 8)
                    .overlay(Circle().strokeBorder(.white, lineWidth: 1.5))
                Text("Current").font(.caption2).foregroundStyle(.secondary)
            }
            HStack(spacing: 4) {
                RoundedRectangle(cornerRadius: 1).fill(.teal).frame(width: 6, height: 6)
                Text("Station").font(.caption2).foregroundStyle(.secondary)
            }

            if showActivity {
                Divider().frame(height: 12)
                HStack(spacing: 4) {
                    Circle().strokeBorder(.blue.opacity(0.5), lineWidth: 1.5).frame(width: 8, height: 8)
                    Text("Jumps").font(.caption2).foregroundStyle(.secondary)
                }
                HStack(spacing: 4) {
                    Circle().fill(.red.opacity(0.4)).frame(width: 8, height: 8)
                    Text("PvP").font(.caption2).foregroundStyle(.secondary)
                }
            }

            Spacer()
        }
    }

    // MARK:  Projection

    private func projectSystems(in size: CGSize) -> [Int: CGPoint] {
        guard !systems.isEmpty else { return [:] }
        let xs = systems.compactMap(\.x)
        let zs = systems.compactMap(\.z)
        guard let minX = xs.min(), let maxX = xs.max(),
              let minZ = zs.min(), let maxZ = zs.max() else { return [:] }

        let rangeX = maxX - minX
        let rangeZ = maxZ - minZ
        let maxRange = max(rangeX, rangeZ, 1)

        let padding: CGFloat = 60
        let availW = size.width - padding * 2
        let availH = size.height - padding * 2
        let mapScale = min(availW, availH) / CGFloat(maxRange)

        let centerX = (minX + maxX) / 2
        let centerZ = (minZ + maxZ) / 2

        var result: [Int: CGPoint] = [:]
        for sys in systems {
            guard let sx = sys.x, let sz = sys.z else { continue }
            let px = size.width / 2 + CGFloat(sx - centerX) * mapScale
            let py = size.height / 2 + CGFloat(sz - centerZ) * mapScale
            result[sys.systemId] = CGPoint(x: px, y: py)
        }
        return result
    }

    private func applyTransform(_ point: CGPoint, size: CGSize) -> CGPoint {
        let cx = size.width / 2
        let cy = size.height / 2
        return CGPoint(
            x: cx + (point.x - cx) * scale + offset.width,
            y: cy + (point.y - cy) * scale + offset.height
        )
    }

    // MARK:  Helpers

    private func securityColor(_ value: Double) -> Color {
        switch value {
        case 0.9...: return .cyan
        case 0.7..<0.9: return .green
        case 0.5..<0.7: return .yellow
        case 0.3..<0.5: return .orange
        case 0.1..<0.3: return Color(red: 1, green: 0.4, blue: 0)
        default: return .red
        }
    }

    private func securityBadge(_ value: Double) -> some View {
        Text(String(format: "%.1f", value))
            .font(.caption2.bold().monospacedDigit())
            .foregroundStyle(securityColor(value))
            .padding(.horizontal, 5)
            .padding(.vertical, 1)
            .background(securityColor(value).opacity(0.15), in: Capsule())
    }

    private func legendItem(color: Color, label: String) -> some View {
        HStack(spacing: 3) {
            Circle().fill(color).frame(width: 6, height: 6)
            Text(label).font(.caption2).foregroundStyle(.secondary)
        }
    }

    // MARK:  Data Loading

    private func loadConstellationData() async {
        isLoading = true

        guard let constellation = await UniverseCache.shared.constellation(id: constellationId),
                  let systemIds = constellation.systems, !systemIds.isEmpty else {
                isLoading = false
                return
            }

            // Fetch systems, kills, and jumps concurrently
            async let fetchedSystems = withTaskGroup(of: ESISolarSystem?.self) { group in
                for sysId in systemIds {
                    group.addTask {
                        await UniverseCache.shared.solarSystem(id: sysId)
                    }
                }
                var results: [ESISolarSystem] = []
                for await sys in group {
                    if let s = sys { results.append(s) }
                }
                return results
            }

            async let fetchKills: [ESISystemKills] = {
                (try? await ESIClient.shared.fetch("/universe/system_kills/")) ?? []
            }()

            async let fetchJumps: [ESISystemJumps] = {
                (try? await ESIClient.shared.fetch("/universe/system_jumps/")) ?? []
            }()

            let (sysList, allKills, allJumps) = await (fetchedSystems, fetchKills, fetchJumps)

            // Index kills and jumps by system
            let constellationSystemIds = Set(systemIds)
            var killsMap: [Int: ESISystemKills] = [:]
            for k in allKills where constellationSystemIds.contains(k.systemId) {
                killsMap[k.systemId] = k
            }
            var jumpsMap: [Int: Int] = [:]
            for j in allJumps where constellationSystemIds.contains(j.systemId) {
                jumpsMap[j.systemId] = j.shipJumps
            }

            // Build map systems
            var mapSystems: [MapSystem] = []
            for sys in sysList {
                mapSystems.append(MapSystem(
                    systemId: sys.systemId,
                    name: sys.name,
                    securityStatus: sys.securityStatus,
                    x: sys.position?.x,
                    y: sys.position?.y,
                    z: sys.position?.z,
                    stargateIds: sys.stargates ?? [],
                    stationCount: sys.stations?.count ?? 0
                ))
            }

            // Fetch all stargates concurrently
            let allStargateIds = sysList.flatMap { $0.stargates ?? [] }
            let fetchedGates = await withTaskGroup(of: ESIStargate?.self) { group in
                for gateId in allStargateIds {
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

            // Build connections
            var connectionSet: Set<String> = []
            var mapConnections: [MapConnection] = []
            var extConns: [ExternalConnection] = []
            var resolvedExtSystems: Set<Int> = []

            for gate in fetchedGates {
                let destSystem = gate.destination.systemId
                if constellationSystemIds.contains(destSystem) {
                    // Internal connection
                    let key = "\(min(gate.systemId, destSystem))-\(max(gate.systemId, destSystem))"
                    if connectionSet.insert(key).inserted {
                        mapConnections.append(MapConnection(
                            fromSystemId: gate.systemId,
                            toSystemId: destSystem
                        ))
                    }
                } else if !resolvedExtSystems.contains(destSystem) {
                    // External connection to another constellation
                    resolvedExtSystems.insert(destSystem)
                    // We'll resolve the name after
                    extConns.append(ExternalConnection(
                        fromSystemId: gate.systemId,
                        toSystemId: destSystem,
                        destinationName: "...",
                        angle: 0
                    ))
                }
            }

            // Resolve external system names and compute angles
            let extSystemIds = extConns.map(\.toSystemId)
            let extNames = await NameResolver.shared.resolve(ids: extSystemIds)

            // Compute angles for external connections
            var resolvedExtConns: [ExternalConnection] = []
            for ext in extConns {
                guard let fromPt = mapSystems.first(where: { $0.systemId == ext.fromSystemId }),
                      let fx = fromPt.x, let fz = fromPt.z else { continue }

                // Try to get destination system position for angle
                var angle: CGFloat = CGFloat.random(in: 0...(.pi * 2))
                if let destSys = await UniverseCache.shared.solarSystem(id: ext.toSystemId),
                   let destPos = destSys.position {
                    angle = atan2(CGFloat(destPos.z - fz), CGFloat(destPos.x - fx))
                }

                resolvedExtConns.append(ExternalConnection(
                    fromSystemId: ext.fromSystemId,
                    toSystemId: ext.toSystemId,
                    destinationName: extNames[ext.toSystemId] ?? "Unknown",
                    angle: angle
                ))
            }

            systems = mapSystems
            connections = mapConnections
            externalConnections = resolvedExtConns
            killsData = killsMap
            jumpsData = jumpsMap

        isLoading = false
    }
}

// MARK:  Map Data Models

struct MapSystem {
    let systemId: Int
    let name: String
    let securityStatus: Double
    let x: Double?
    let y: Double?
    let z: Double?
    let stargateIds: [Int]
    let stationCount: Int
}

struct MapConnection {
    let fromSystemId: Int
    let toSystemId: Int
}

struct ExternalConnection {
    let fromSystemId: Int
    let toSystemId: Int
    let destinationName: String
    let angle: CGFloat
}
