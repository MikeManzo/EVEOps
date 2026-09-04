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
import SceneKit
import AppKit
import simd

// MARK:  GalaxyMap3DView

/// A rotatable / zoomable 3-D star map of known space: every k-space solar system
/// (~5,500 points) plus the stargate graph (~7,000 links), rendered with SceneKit.
///
/// Topology comes from `UniverseTopology` (a cached static snapshot). Colour modes,
/// route hand-off and constellation drill-down are shared with the 2-D `GalaxyMapView`.
struct GalaxyMap3DView: View {
    let currentSystemId: Int?
    let colorMode: MapColorMode
    /// `(constellationId, constellationName)` — opens the existing 2-D constellation map.
    var onOpenConstellation: (Int, String) -> Void
    /// `systemId` — parent switches back to the 2-D map in route mode.
    var onPlanRoute: (Int) -> Void
    /// `(systemId, label)` — set autopilot destination.
    var onSetDestination: (Int, String) -> Void

    @Environment(AccountManager.self) private var accountManager

    @State private var model = GalaxySceneModel()
    @State private var phase: Phase = .loading
    @State private var dangerMap: [Int: Int] = [:]
    @State private var selDetail: SelDetail?
    @State private var showGates = true
    @State private var hasCenteredOnLoad = false

    private enum Phase { case loading, ready, failed }
    private struct SelDetail: Equatable { let region: String; let constellation: String }

    var body: some View {
        GeometryReader { geo in
            ZStack {
                Color.black

                switch phase {
                case .loading:
                    loadingOverlay
                case .failed:
                    failedOverlay
                case .ready:
                    GalaxySceneRepresentable(model: model)
                    overlays(in: geo.size)
                }
            }
        }
        .task { await load() }
        .onChange(of: colorMode) { _, mode in Task { await applyColorMode(mode) } }
        .onChange(of: currentSystemId) { _, id in model.currentID = id }
        // `.task(id:)` restarts with a fresh capture whenever this computed key changes,
        // so — unlike a bare `.task {}` — it reliably sees `currentSystemId` resolving
        // after the map has already loaded (character location often arrives late).
        .task(id: phase == .ready ? currentSystemId : nil) {
            guard phase == .ready, let id = currentSystemId, !hasCenteredOnLoad else { return }
            hasCenteredOnLoad = true
            model.currentID = id
            model.focus(on: id, animated: false)
        }
        .task(id: model.selectedID) { await resolveSelectionNames() }
    }

    // MARK:  Overlays

    @ViewBuilder
    private func overlays(in size: CGSize) -> some View {
        // Hover chip at the cursor. `hoverInfo.screen` is AppKit-space (origin bottom-left).
        if let h = model.hoverInfo {
            hoverChip(h)
                .position(x: h.screen.x, y: size.height - h.screen.y - 22)
                .allowsHitTesting(false)
        }

        // Selected-system detail panel.
        if let s = model.selectedSystem {
            selectionPanel(s)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                .padding(12)
        }

        // Camera controls.
        VStack(alignment: .leading, spacing: 6) {
            controlBar
            Text("Drag to orbit · scroll to zoom · ⌥-drag to pan · click a constellation to dive in")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .padding(.leading, 4)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(12)

        // Current-location HUD.
        if let name = model.currentSystem?.name {
            locationHUD(name: name, security: model.currentSystem?.security ?? 0)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
                .padding(12)
        }

        legend
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
            .padding(12)
    }

    private var controlBar: some View {
        HStack(spacing: 6) {
            Button {
                model.frameGalaxy()
            } label: {
                Label("Frame Galaxy", systemImage: "arrow.up.left.and.arrow.down.right")
                    .font(.caption)
            }
            .buttonStyle(.bordered)
            .controlSize(.small)

            Button {
                if let id = currentSystemId {
                    model.focus(on: id)
                    model.selectedID = id
                }
            } label: {
                Label("Find Me", systemImage: "location.fill").font(.caption)
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .disabled(currentSystemId == nil)
            .help(currentSystemId == nil
                  ? "Current location not available yet — sign in and let character data sync"
                  : "Zoom to your current system")

            Divider().frame(height: 14)

            Button { model.zoomStep(closer: true) } label: {
                Image(systemName: "plus.magnifyingglass").font(.caption)
            }
            .buttonStyle(.bordered).controlSize(.small)

            Button { model.zoomStep(closer: false) } label: {
                Image(systemName: "minus.magnifyingglass").font(.caption)
            }
            .buttonStyle(.bordered).controlSize(.small)

            Divider().frame(height: 14)

            Toggle(isOn: $showGates) {
                Label("Gates", systemImage: "point.3.connected.trianglepath.dotted").font(.caption)
            }
            .toggleStyle(.button)
            .buttonStyle(.bordered)
            .controlSize(.small)
            .onChange(of: showGates) { _, on in model.setGatesVisible(on) }
        }
        .padding(6)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 8))
    }

    private func hoverChip(_ h: GalaxySceneModel.HoverInfo) -> some View {
        HStack(spacing: 5) {
            Text(h.name).font(.caption2.bold())
            Text(securityText(h.security))
                .font(.caption2.monospacedDigit())
                .foregroundStyle(Color(nsColor: GalaxyPalette.security(h.security)))
        }
        .padding(.horizontal, 6).padding(.vertical, 3)
        .background(.ultraThinMaterial, in: Capsule())
        .overlay(Capsule().stroke(.white.opacity(0.15), lineWidth: 0.5))
    }

    private func selectionPanel(_ s: TopoSystem) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(s.name).font(.caption.bold())
                    HStack(spacing: 4) {
                        Circle().fill(Color(nsColor: model.regionColor(s.regionID)))
                            .frame(width: 6, height: 6)
                        Text(selDetail?.region ?? "…").font(.caption2).foregroundStyle(.secondary)
                    }
                }
                Spacer()
                Button { model.selectedID = nil } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }

            if s.id == currentSystemId {
                Label("Current system", systemImage: "location.fill")
                    .font(.caption2).foregroundStyle(.blue)
            }

            HStack(spacing: 6) {
                Text("Security").font(.caption2).foregroundStyle(.secondary)
                Text(securityText(s.security))
                    .font(.caption2.bold().monospacedDigit())
                    .foregroundStyle(Color(nsColor: GalaxyPalette.security(s.security)))
                    .padding(.horizontal, 4).padding(.vertical, 1)
                    .background(Color(nsColor: GalaxyPalette.security(s.security)).opacity(0.15), in: Capsule())
            }

            Label(selDetail?.constellation ?? "…", systemImage: "point.3.filled.connected.trianglepath.dotted")
                .font(.caption2).foregroundStyle(.secondary)

            if let kills = dangerMap[s.id], colorMode == .danger {
                Label("\(kills) ship + pod kill\(kills == 1 ? "" : "s") · last hour", systemImage: "flame.fill")
                    .font(.caption2)
                    .foregroundStyle(Color(nsColor: GalaxyPalette.killHeat(kills)))
            }

            Divider()

            Button {
                onOpenConstellation(s.constellationID, selDetail?.constellation ?? "")
            } label: {
                Label("View Constellation Map", systemImage: "map.fill").font(.caption)
            }
            .buttonStyle(.plain).foregroundStyle(.blue)

            if accountManager.selectedAccount != nil {
                Button {
                    onSetDestination(s.id, s.name)
                } label: {
                    Label("Set Destination", systemImage: "paperplane.fill").font(.caption)
                }
                .buttonStyle(.plain).foregroundStyle(.blue)
            }

            Button {
                onPlanRoute(s.id)
            } label: {
                Label("Plan Route From Here", systemImage: "point.3.connected.trianglepath.dotted").font(.caption)
            }
            .buttonStyle(.plain).foregroundStyle(.orange)
        }
        .padding(12)
        .frame(width: 232)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 10))
    }

    private func locationHUD(name: String, security: Double) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "location.fill").font(.caption2).foregroundStyle(.blue)
            Text(name).font(.caption.bold())
            Text(securityText(security))
                .font(.caption2.bold().monospacedDigit())
                .foregroundStyle(Color(nsColor: GalaxyPalette.security(security)))
        }
        .padding(8)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 8))
    }

    private var legend: some View {
        let items: [(String, NSColor)]
        switch colorMode {
        case .region:
            items = []
        case .space:
            items = [("Hi", GalaxyPalette.space(0)), ("Low", GalaxyPalette.space(1)),
                     ("Null", GalaxyPalette.space(2)), ("Pochven", GalaxyPalette.space(3))]
        case .security:
            items = [("1.0", GalaxyPalette.security(1.0)), ("0.7", GalaxyPalette.security(0.7)),
                     ("0.5", GalaxyPalette.security(0.5)), ("0.1", GalaxyPalette.security(0.1)),
                     ("0.0", GalaxyPalette.security(-0.1))]
        case .danger:
            items = [("0", GalaxyPalette.killHeat(0)), ("1+", GalaxyPalette.killHeat(2)),
                     ("5+", GalaxyPalette.killHeat(10)), ("20+", GalaxyPalette.killHeat(30)),
                     ("60+", GalaxyPalette.killHeat(80))]
        }
        return Group {
            if !items.isEmpty {
                HStack(spacing: 8) {
                    ForEach(items, id: \.0) { label, color in
                        HStack(spacing: 3) {
                            Circle().fill(Color(nsColor: color)).frame(width: 6, height: 6)
                            Text(label).font(.caption2).foregroundStyle(.secondary)
                        }
                    }
                }
                .padding(.horizontal, 8).padding(.vertical, 5)
                .background(.ultraThinMaterial, in: Capsule())
            }
        }
    }

    private var loadingOverlay: some View {
        VStack(spacing: 12) {
            ProgressView()
            Text("Downloading star-map data…").font(.subheadline)
            Text("First run only — cached on disk afterwards.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    private var failedOverlay: some View {
        VStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle").font(.title2).foregroundStyle(.orange)
            Text("Couldn't load the star-map data.").font(.subheadline)
            Text("Check your connection and try again.")
                .font(.caption).foregroundStyle(.secondary)
            Button("Retry") { phase = .loading; Task { await load() } }
                .controlSize(.small)
        }
    }

    private func securityText(_ v: Double) -> String {
        v < -0.49 ? "WH" : String(format: "%.1f", max(0, v))
    }

    // MARK:  Loading

    private func load() async {
        guard let topo = await UniverseTopology.shared.load() else {
            phase = .failed
            return
        }
        model.build(topo)
        model.currentID = currentSystemId
        model.recolor(mode: colorMode, danger: [:])
        model.setGatesVisible(showGates)
        // Framed here as a baseline; the `.task(id:)` below immediately re-centers on
        // the current system once `phase` flips to `.ready`, if it's already known.
        model.frameGalaxy(animated: false)
        phase = .ready
        await model.loadRegionLabels()
        if colorMode == .danger { await applyColorMode(.danger) }
    }

    private func applyColorMode(_ mode: MapColorMode) async {
        guard phase == .ready else { return }
        if mode == .danger {
            if dangerMap.isEmpty,
               let snap = try? await SystemDangerService.shared.snapshot() {
                var m: [Int: Int] = [:]
                for s in model.allSystems {
                    let k = snap.danger(for: s.id).combatKills
                    if k > 0 { m[s.id] = k }
                }
                dangerMap = m
            }
            model.recolor(mode: .danger, danger: dangerMap)
        } else {
            model.recolor(mode: mode, danger: [:])
        }
    }

    private func resolveSelectionNames() async {
        selDetail = nil
        guard let s = model.selectedSystem else { return }
        async let region = UniverseCache.shared.region(id: s.regionID)?.name
        async let cons = UniverseCache.shared.constellation(id: s.constellationID)?.name
        let (rn, cn) = await (region, cons)
        selDetail = SelDetail(
            region: rn ?? "Region \(s.regionID)",
            constellation: cn ?? "Constellation \(s.constellationID)"
        )
    }
}

// MARK:  GalaxySceneModel

/// Owns the SceneKit scene, the system / stargate geometry, an explicit orbit-camera
/// rig and the ray-pick logic. All access is main-actor; SwiftUI observes
/// `selectedID` / `hoverInfo` / `currentID`.
@MainActor
@Observable
final class GalaxySceneModel {

    struct HoverInfo: Equatable {
        let id: Int
        let name: String
        let security: Double
        let screen: CGPoint
    }

    let scene = SCNScene()

    // Observed by SwiftUI
    var selectedID: Int? {
        didSet {
            guard oldValue != selectedID else { return }
            refreshOverlayNodes()
            updateRegionHighlight()
        }
    }
    var hoverInfo: HoverInfo?
    var currentID: Int? { didSet { if oldValue != currentID { refreshOverlayNodes() } } }

    // Scene plumbing (not observed)
    @ObservationIgnored private(set) var isBuilt = false
    @ObservationIgnored weak var view: SCNView?
    @ObservationIgnored let cameraNode = SCNNode()

    @ObservationIgnored private var systems: [TopoSystem] = []
    @ObservationIgnored private var idToIndex: [Int: Int] = [:]
    @ObservationIgnored private var worldPos: [SIMD3<Double>] = []
    @ObservationIgnored private var jumps: [(Int, Int)] = []

    @ObservationIgnored private var center = SIMD3<Double>(repeating: 0)
    @ObservationIgnored private var worldScale: Double = 1
    @ObservationIgnored private let yExaggeration: Double = 6
    @ObservationIgnored private var galaxyRadius: Double = 110

    @ObservationIgnored private let systemsRoot = SCNNode()
    @ObservationIgnored private let linesNode = SCNNode()
    @ObservationIgnored private let regionLinesNode = SCNNode()
    @ObservationIgnored private let overlayRoot = SCNNode()
    @ObservationIgnored private let labelsRoot = SCNNode()
    @ObservationIgnored private let systemLabelsRoot = SCNNode()
    @ObservationIgnored private var lastHoverID: Int?
    @ObservationIgnored private var lastHoverConsID: Int?
    @ObservationIgnored private var gatesVisible = true

    // Constellation level-of-detail (zoomed out: one dot per constellation)
    @ObservationIgnored private let constellationsRoot = SCNNode()
    @ObservationIgnored private let constellationLinesNode = SCNNode()
    @ObservationIgnored private var consList: [Int] = []
    @ObservationIgnored private var consWorld: [SIMD3<Double>] = []
    @ObservationIgnored private var consCentroid: [Int: SIMD3<Double>] = [:]
    @ObservationIgnored private var consRegion: [Int: Int] = [:]
    @ObservationIgnored private var consAvgSec: [Int: Double] = [:]
    @ObservationIgnored private var consSystemIDs: [Int: [Int]] = [:]
    @ObservationIgnored private var consJumps: [(Int, Int)] = []
    @ObservationIgnored private var consNameCache: [Int: String] = [:]
    @ObservationIgnored private var lodConstellations = false
    @ObservationIgnored private var lodEnterDistance: Double = 0
    @ObservationIgnored private var lodExitDistance: Double = 0

    // Region colouring + labels
    @ObservationIgnored private var regionOrdinal: [Int: Int] = [:]
    @ObservationIgnored private var regionCentroid: [Int: SIMD3<Double>] = [:]
    @ObservationIgnored private var labelDistanceThreshold: Double = 0

    // Zoom-in system labels
    @ObservationIgnored private var systemLabelCache: [Int: SCNNode] = [:]
    @ObservationIgnored private var labelAnchors: [ObjectIdentifier: SIMD3<Float>] = [:]
    @ObservationIgnored private var lastLabelTarget = SIMD3<Double>(repeating: .infinity)
    @ObservationIgnored private var lastLabelDistance = -1.0

    // Orbit-camera rig (spherical around a target)
    @ObservationIgnored private var camTarget = SIMD3<Double>(repeating: 0)
    @ObservationIgnored private var camDistance: Double = 360
    @ObservationIgnored private var camYaw: Double = 0.6
    @ObservationIgnored private var camPitch: Double = 0.5
    @ObservationIgnored private var minDistance: Double = 1.5
    @ObservationIgnored private var maxDistance: Double = 1200

    var allSystems: [TopoSystem] { systems }
    var selectedSystem: TopoSystem? { selectedID.flatMap(system) }
    var currentSystem: TopoSystem? { currentID.flatMap(system) }
    func system(_ id: Int) -> TopoSystem? { idToIndex[id].map { systems[$0] } }

    // MARK: Build

    func build(_ topo: GalaxyTopology) {
        guard !isBuilt else { return }

        systems = topo.systems
        jumps = topo.jumps
        idToIndex = Dictionary(uniqueKeysWithValues: systems.enumerated().map { ($1.id, $0) })

        var lo = SIMD3<Double>(repeating: .greatestFiniteMagnitude)
        var hi = SIMD3<Double>(repeating: -.greatestFiniteMagnitude)
        for s in systems {
            let p = SIMD3(s.x, s.y, s.z)
            lo = simd_min(lo, p)
            hi = simd_max(hi, p)
        }
        center = (lo + hi) / 2
        let extent = hi - lo
        let maxExtent = max(extent.x, extent.y, extent.z, 1)
        worldScale = 220.0 / maxExtent
        worldPos = systems.map { scenePosition(SIMD3($0.x, $0.y, $0.z)) }
        galaxyRadius = (worldPos.map { simd_length($0) }.max() ?? 110)
        maxDistance = galaxyRadius * 6

        // Stable per-region ordinal → evenly spaced hues; region centroids for labels.
        let sortedRegions = Array(Set(systems.map(\.regionID))).sorted()
        regionOrdinal = Dictionary(uniqueKeysWithValues: sortedRegions.enumerated().map { ($1, $0) })
        var sums: [Int: (SIMD3<Double>, Int)] = [:]
        for (i, s) in systems.enumerated() {
            let e = sums[s.regionID] ?? (SIMD3<Double>(repeating: 0), 0)
            sums[s.regionID] = (e.0 + worldPos[i], e.1 + 1)
        }
        regionCentroid = sums.mapValues { $0.0 / Double(max($0.1, 1)) }
        labelDistanceThreshold = galaxyRadius * 1.4

        buildConstellationAggregates()
        lodEnterDistance = galaxyRadius * 0.55
        lodExitDistance = galaxyRadius * 0.45

        rebuildSystemNodes(mode: .region, danger: [:])
        rebuildConstellationNodes(mode: .region, danger: [:])
        rebuildLines()
        rebuildConstellationLines()

        systemsRoot.name = "systems"
        constellationsRoot.isHidden = true
        scene.rootNode.addChildNode(systemsRoot)
        scene.rootNode.addChildNode(constellationsRoot)
        scene.rootNode.addChildNode(linesNode)
        scene.rootNode.addChildNode(constellationLinesNode)
        scene.rootNode.addChildNode(regionLinesNode)
        scene.rootNode.addChildNode(overlayRoot)
        scene.rootNode.addChildNode(labelsRoot)
        scene.rootNode.addChildNode(systemLabelsRoot)

        setupCamera()
        setupBackground()
        isBuilt = true
        updateCamera()
    }

    /// One centroid, region, mean security, member list and adjacency edge set per
    /// constellation — the data behind the zoomed-out level of detail.
    private func buildConstellationAggregates() {
        var sums: [Int: (SIMD3<Double>, Int, Double)] = [:]
        for (i, s) in systems.enumerated() {
            var e = sums[s.constellationID] ?? (SIMD3<Double>(repeating: 0), 0, 0)
            e.0 += worldPos[i]; e.1 += 1; e.2 += s.security
            sums[s.constellationID] = e
            consRegion[s.constellationID] = s.regionID
            consSystemIDs[s.constellationID, default: []].append(s.id)
        }
        consList = sums.keys.sorted()
        consWorld = consList.map { sums[$0]!.0 / Double(sums[$0]!.1) }
        for cid in consList {
            let e = sums[cid]!
            consCentroid[cid] = e.0 / Double(e.1)
            consAvgSec[cid] = e.2 / Double(e.1)
        }

        var seen = Set<Int64>()
        for (a, b) in jumps {
            guard let ia = idToIndex[a], let ib = idToIndex[b] else { continue }
            let ca = systems[ia].constellationID, cb = systems[ib].constellationID
            guard ca != cb else { continue }
            let lo = min(ca, cb), hi = max(ca, cb)
            if seen.insert(Int64(lo) << 32 | Int64(hi)).inserted { consJumps.append((lo, hi)) }
        }
    }

    func regionColor(_ regionID: Int) -> NSColor {
        GalaxyPalette.region(ordinal: regionOrdinal[regionID] ?? regionID)
    }

    private func scenePosition(_ raw: SIMD3<Double>) -> SIMD3<Double> {
        let c = (raw - center) * worldScale
        return SIMD3(c.x, c.y * yExaggeration, c.z)
    }

    private func scn(_ v: SIMD3<Double>) -> SCNVector3 {
        SCNVector3(CGFloat(v.x), CGFloat(v.y), CGFloat(v.z))
    }

    // MARK: System geometry (one point-cloud node per colour bucket)

    private func rebuildSystemNodes(mode: MapColorMode, danger: [Int: Int]) {
        systemsRoot.childNodes.forEach { $0.removeFromParentNode() }

        var buckets: [Int: (color: NSColor, indices: [Int])] = [:]
        for (i, s) in systems.enumerated() {
            let key: Int
            let color: NSColor
            switch mode {
            case .region:
                key = s.regionID
                color = regionColor(s.regionID)
            case .security:
                let b = Self.securityBucket(s.security)
                key = 100_000 + b
                color = GalaxyPalette.security(Self.securityBucketMidpoint(b))
            case .danger:
                let b = Self.killBucket(danger[s.id] ?? 0)
                key = 200_000 + b
                color = GalaxyPalette.killHeat(Self.killBucketMidpoint(b))
            case .space:
                let b = Self.spaceBucket(regionID: s.regionID, security: s.security)
                key = 300_000 + b
                color = GalaxyPalette.space(b)
            }
            buckets[key, default: (color, [])].indices.append(i)
        }

        for (_, bucket) in buckets {
            let node = makePointNode(
                positions: bucket.indices.map { worldPos[$0] },
                color: bucket.color,
                sizePx: 7, minPx: 2.0,
                depthTested: true
            )
            systemsRoot.addChildNode(node)
        }
    }

    private func rebuildLines() {
        var verts: [SCNVector3] = []
        verts.reserveCapacity(jumps.count * 2)
        for (a, b) in jumps {
            guard let ia = idToIndex[a], let ib = idToIndex[b] else { continue }
            verts.append(scn(worldPos[ia]))
            verts.append(scn(worldPos[ib]))
        }
        guard !verts.isEmpty else { return }

        let vSource = SCNGeometrySource(vertices: verts)
        let indices = Array(UInt32(0)..<UInt32(verts.count))
        let element = SCNGeometryElement(indices: indices, primitiveType: .line)

        let geo = SCNGeometry(sources: [vSource], elements: [element])
        let mat = SCNMaterial()
        mat.lightingModel = .constant
        mat.diffuse.contents = NSColor(calibratedWhite: 0.5, alpha: 0.11)
        mat.blendMode = .add
        mat.writesToDepthBuffer = false
        mat.isDoubleSided = true
        geo.firstMaterial = mat
        linesNode.geometry = geo
    }

    // MARK: Constellation level of detail

    private func rebuildConstellationNodes(mode: MapColorMode, danger: [Int: Int]) {
        constellationsRoot.childNodes.forEach { $0.removeFromParentNode() }

        var buckets: [Int: (color: NSColor, indices: [Int])] = [:]
        for (idx, cid) in consList.enumerated() {
            let region = consRegion[cid] ?? 0
            let sec = consAvgSec[cid] ?? 0
            let key: Int
            let color: NSColor
            switch mode {
            case .region:
                key = region
                color = regionColor(region)
            case .security:
                let b = Self.securityBucket(sec)
                key = 100_000 + b
                color = GalaxyPalette.security(Self.securityBucketMidpoint(b))
            case .danger:
                let kills = (consSystemIDs[cid] ?? []).reduce(0) { $0 + (danger[$1] ?? 0) }
                let b = Self.killBucket(kills)
                key = 200_000 + b
                color = GalaxyPalette.killHeat(Self.killBucketMidpoint(b))
            case .space:
                let b = Self.spaceBucket(regionID: region, security: sec)
                key = 300_000 + b
                color = GalaxyPalette.space(b)
            }
            buckets[key, default: (color, [])].indices.append(idx)
        }

        for (_, bucket) in buckets {
            let node = makePointNode(
                positions: bucket.indices.map { consWorld[$0] },
                color: bucket.color,
                sizePx: 13, minPx: 5,
                depthTested: true, halo: true
            )
            constellationsRoot.addChildNode(node)
        }
    }

    private func rebuildConstellationLines() {
        var verts: [SCNVector3] = []
        for (a, b) in consJumps {
            guard let pa = consCentroid[a], let pb = consCentroid[b] else { continue }
            verts.append(scn(pa))
            verts.append(scn(pb))
        }
        guard !verts.isEmpty else { return }

        let element = SCNGeometryElement(
            indices: Array(UInt32(0)..<UInt32(verts.count)),
            primitiveType: .line
        )
        let geo = SCNGeometry(sources: [SCNGeometrySource(vertices: verts)], elements: [element])
        let mat = SCNMaterial()
        mat.lightingModel = .constant
        mat.diffuse.contents = NSColor(calibratedWhite: 0.6, alpha: 0.18)
        mat.blendMode = .add
        mat.writesToDepthBuffer = false
        mat.isDoubleSided = true
        geo.firstMaterial = mat
        constellationLinesNode.geometry = geo
    }

    /// Hard swap (with hysteresis) between the ~5,500-system view and the ~800-dot
    /// constellation view as the camera pulls back / dives in.
    private func applyLOD() {
        guard isBuilt, !consList.isEmpty else { return }
        let was = lodConstellations
        if lodConstellations {
            if camDistance < lodExitDistance { lodConstellations = false }
        } else if camDistance > lodEnterDistance {
            lodConstellations = true
        }
        guard lodConstellations != was else { return }
        systemsRoot.isHidden = lodConstellations
        constellationsRoot.isHidden = !lodConstellations
        updateGateVisibility()
    }

    func setGatesVisible(_ visible: Bool) {
        gatesVisible = visible
        updateGateVisibility()
    }

    private func updateGateVisibility() {
        linesNode.isHidden = !(gatesVisible && !lodConstellations)
        constellationLinesNode.isHidden = !(gatesVisible && lodConstellations)
    }

    private func setMainLineAlpha(_ alpha: CGFloat) {
        linesNode.geometry?.firstMaterial?.diffuse.contents = NSColor(calibratedWhite: 0.5, alpha: alpha)
    }

    /// Neighborhood focus: with a system selected, its whole region's gate graph is
    /// drawn bright and the rest of the web is dimmed right down.
    private func updateRegionHighlight() {
        guard isBuilt else { return }
        guard let sid = selectedID, let sel = system(sid) else {
            regionLinesNode.geometry = nil
            setMainLineAlpha(0.11)
            return
        }
        let rid = sel.regionID
        var verts: [SCNVector3] = []
        for (a, b) in jumps {
            guard let ia = idToIndex[a], let ib = idToIndex[b] else { continue }
            if systems[ia].regionID == rid || systems[ib].regionID == rid {
                verts.append(scn(worldPos[ia]))
                verts.append(scn(worldPos[ib]))
            }
        }
        guard !verts.isEmpty else {
            regionLinesNode.geometry = nil
            setMainLineAlpha(0.11)
            return
        }
        let vSource = SCNGeometrySource(vertices: verts)
        let element = SCNGeometryElement(
            indices: Array(UInt32(0)..<UInt32(verts.count)),
            primitiveType: .line
        )
        let geo = SCNGeometry(sources: [vSource], elements: [element])
        let mat = SCNMaterial()
        mat.lightingModel = .constant
        mat.diffuse.contents = NSColor(srgbRed: 0.55, green: 0.85, blue: 1.0, alpha: 0.85)
        mat.blendMode = .add
        mat.writesToDepthBuffer = false
        mat.isDoubleSided = true
        geo.firstMaterial = mat
        regionLinesNode.geometry = geo
        regionLinesNode.renderingOrder = 5
        setMainLineAlpha(gatesVisible ? 0.04 : 0.11)
    }

    /// A screen-space-sized point cloud: `minimumPointScreenSpaceRadius` /
    /// `maximumPointScreenSpaceRadius` keep dots a stable pixel size at every zoom.
    /// With `halo`, a larger dim additive point sits behind each for a star-like glow.
    private func makePointNode(positions: [SIMD3<Double>], color: NSColor,
                               sizePx: CGFloat, minPx: CGFloat, depthTested: Bool,
                               halo: Bool = false) -> SCNNode {
        let verts = positions.map(scn)

        func pointGeometry(size: CGFloat, minRadius: CGFloat) -> SCNGeometry {
            let src = SCNGeometrySource(vertices: verts)
            let element = SCNGeometryElement(
                indices: Array(UInt32(0)..<UInt32(verts.count)),
                primitiveType: .point
            )
            element.pointSize = size
            element.minimumPointScreenSpaceRadius = minRadius
            element.maximumPointScreenSpaceRadius = size
            return SCNGeometry(sources: [src], elements: [element])
        }

        let core = pointGeometry(size: sizePx, minRadius: minPx)
        let coreMat = SCNMaterial()
        coreMat.lightingModel = .constant
        coreMat.diffuse.contents = color
        coreMat.emission.contents = color
        coreMat.readsFromDepthBuffer = depthTested
        coreMat.writesToDepthBuffer = depthTested
        core.firstMaterial = coreMat
        let node = SCNNode(geometry: core)

        if halo {
            let glow = pointGeometry(size: sizePx * 2.6, minRadius: minPx * 2.4)
            let glowMat = SCNMaterial()
            glowMat.lightingModel = .constant
            glowMat.diffuse.contents = color.withAlphaComponent(0.16)
            glowMat.emission.contents = color.withAlphaComponent(0.16)
            glowMat.blendMode = .add
            glowMat.readsFromDepthBuffer = false
            glowMat.writesToDepthBuffer = false
            glow.firstMaterial = glowMat
            let glowNode = SCNNode(geometry: glow)
            glowNode.renderingOrder = -1
            node.addChildNode(glowNode)
        }
        return node
    }

    func recolor(mode: MapColorMode, danger: [Int: Int]) {
        guard isBuilt else { return }
        rebuildSystemNodes(mode: mode, danger: danger)
        rebuildConstellationNodes(mode: mode, danger: danger)
    }

    // MARK: Region labels

    /// Resolves region names (cached ESI) and drops a billboarded label at each region
    /// centroid. Cheap: ~65 names, ~65 textured planes. Visibility is zoom-gated.
    func loadRegionLabels() async {
        guard isBuilt, labelsRoot.childNodes.isEmpty else { return }
        let ids = Array(regionCentroid.keys)
        var names: [Int: String] = [:]
        await withTaskGroup(of: (Int, String?).self) { group in
            for id in ids { group.addTask { (id, await UniverseCache.shared.region(id: id)?.name) } }
            for await (id, name) in group where name != nil { names[id] = name }
        }
        for (id, centroid) in regionCentroid {
            guard let name = names[id] else { continue }
            labelsRoot.addChildNode(makeLabelNode(text: name, at: centroid, heightFactor: 0.02))
        }
        labelsRoot.isHidden = camDistance < labelDistanceThreshold
    }

    /// System-name labels for whatever is near the camera target, shown only once
    /// zoomed well in. Region labels hide before these appear (no overlap zone).
    private func updateSystemLabels() {
        guard isBuilt else { return }
        let near = camDistance <= galaxyRadius * 0.22
        systemLabelsRoot.isHidden = !near
        guard near else { return }

        // Recompute the visible set only when the view has actually moved.
        if simd_distance(lastLabelTarget, camTarget) < galaxyRadius * 0.008,
           abs(lastLabelDistance - camDistance) < camDistance * 0.04 { return }
        lastLabelTarget = camTarget
        lastLabelDistance = camDistance

        let radius = camDistance * 1.7
        var picks: [(Int, Double)] = []
        for (i, wp) in worldPos.enumerated() {
            let d = simd_distance(wp, camTarget)
            if d < radius { picks.append((i, d)) }
        }
        picks.sort { $0.1 < $1.1 }
        let chosen = Set(picks.prefix(35).map { systems[$0.0].id })

        for (id, node) in systemLabelCache where !chosen.contains(id) {
            node.removeFromParentNode()
        }
        for id in chosen {
            guard let idx = idToIndex[id] else { continue }
            let node: SCNNode
            if let cached = systemLabelCache[id] {
                node = cached
            } else {
                node = makeLabelNode(text: systems[idx].name, at: worldPos[idx], heightFactor: 0.006,
                                     color: GalaxyPalette.security(systems[idx].security))
                systemLabelCache[id] = node
            }
            if node.parent == nil { systemLabelsRoot.addChildNode(node) }
        }
        if systemLabelCache.count > 400 {
            for (id, node) in systemLabelCache where node.parent == nil {
                systemLabelCache.removeValue(forKey: id)
                labelAnchors.removeValue(forKey: ObjectIdentifier(node))
            }
        }
    }

    private func makeLabelNode(text: String, at pos: SIMD3<Double>, heightFactor: Double,
                               color: NSColor = .white) -> SCNNode {
        let image = Self.makeLabelImage(text, color: color)
        let aspect = image.size.width / max(image.size.height, 1)
        let height = CGFloat(galaxyRadius * heightFactor)
        let plane = SCNPlane(width: height * aspect, height: height)
        let mat = SCNMaterial()
        mat.lightingModel = .constant
        mat.diffuse.contents = image
        mat.isDoubleSided = true
        mat.writesToDepthBuffer = false
        mat.readsFromDepthBuffer = false
        plane.firstMaterial = mat

        let node = SCNNode(geometry: plane)
        node.simdPosition = SIMD3<Float>(Float(pos.x), Float(pos.y), Float(pos.z))
        node.constraints = [SCNBillboardConstraint()]
        node.renderingOrder = 20
        labelAnchors[ObjectIdentifier(node)] = node.simdPosition
        return node
    }

    /// Per-camera-move label layout: scales each label so it tracks the scene zoom but
    /// stays within a readable pixel band, hides labels that are off-screen / behind the
    /// camera, drops any that would overlap one already placed, and caps the total.
    private func layoutLabels(_ root: SCNNode, minPx: CGFloat, maxPx: CGFloat, limit: Int, gapPx: CGFloat) {
        guard let view, !root.isHidden else { return }
        let children = root.childNodes
        guard !children.isEmpty else { return }

        let cam = cameraNode.simdWorldPosition
        let forward = simd_normalize(cameraNode.simdWorldFront)
        let up = simd_normalize(cameraNode.simdWorldUp)
        let fovRad = CGFloat((cameraNode.camera?.fieldOfView ?? 55) * .pi / 180)
        let halfTan = tan(fovRad / 2)
        let vpH = max(view.bounds.height, 1)
        let vpW = view.bounds.width

        // Nearest labels win contested screen space.
        let ordered = children.sorted {
            let a = labelAnchors[ObjectIdentifier($0)] ?? $0.simdWorldPosition
            let b = labelAnchors[ObjectIdentifier($1)] ?? $1.simdWorldPosition
            return simd_distance(a, cam) < simd_distance(b, cam)
        }

        var placed: [CGRect] = []
        var shown = 0
        for node in ordered {
            guard let plane = node.geometry as? SCNPlane else { continue }
            let anchor = labelAnchors[ObjectIdentifier(node)] ?? node.simdWorldPosition
            let rel = anchor - cam
            let dist = simd_length(rel)
            if dist < 0.001 || simd_dot(rel, forward) <= 0 { node.isHidden = true; continue }

            let sp = view.projectPoint(SCNVector3(CGFloat(anchor.x), CGFloat(anchor.y), CGFloat(anchor.z)))
            guard sp.z > 0, sp.z < 1 else { node.isHidden = true; continue }
            let px = CGFloat(sp.x), py = CGFloat(sp.y)
            if px < -80 || px > vpW + 80 || py < -60 || py > vpH + 60 { node.isHidden = true; continue }

            // Natural on-screen height of the base plane at this distance, clamped.
            let natural = vpH * plane.height / (2 * CGFloat(dist) * halfTan)
            let target = min(maxPx, max(minPx, natural))
            let scale = target / max(natural, 0.001)
            node.simdScale = SIMD3<Float>(repeating: Float(scale))

            // Nudge the label a fixed number of pixels above its dot (converted to world
            // units at this distance) so the gap stays constant at every zoom.
            let riseWorld = Float((gapPx + target / 2) * (2 * CGFloat(dist) * halfTan) / vpH)
            node.simdPosition = anchor + up * riseWorld

            let w = target * (plane.width / plane.height)
            let cy = py + gapPx + target / 2
            let rect = CGRect(x: px - w / 2, y: cy - target / 2, width: w, height: target)
                .insetBy(dx: -3, dy: -2)
            if shown >= limit || placed.contains(where: { $0.intersects(rect) }) {
                node.isHidden = true
            } else {
                node.isHidden = false
                placed.append(rect)
                shown += 1
            }
        }
    }

    /// Re-runs the camera + label layout once the `SCNView` exists (`projectPoint`
    /// needs it), so labels are sized correctly on first display.
    func viewAttached() {
        guard isBuilt else { return }
        updateCamera()
    }

    private static func makeLabelImage(_ text: String, color: NSColor = .white) -> NSImage {
        let font = NSFont.systemFont(ofSize: 42, weight: .semibold)
        let para = NSMutableParagraphStyle(); para.alignment = .center
        let tint = (color.usingColorSpace(.sRGB) ?? color).blended(withFraction: 0.15, of: .white) ?? color
        let attrs: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: tint.withAlphaComponent(0.95),
            .paragraphStyle: para,
        ]
        let string = NSAttributedString(string: text, attributes: attrs)
        var size = string.size()
        size.width = ceil(size.width) + 24
        size.height = ceil(size.height) + 16

        let image = NSImage(size: size)
        image.lockFocus()
        let shadow = NSShadow()
        shadow.shadowColor = NSColor.black.withAlphaComponent(0.95)
        shadow.shadowBlurRadius = 4
        shadow.shadowOffset = .zero
        shadow.set()
        string.draw(in: NSRect(x: 12, y: 8, width: size.width - 24, height: size.height - 16))
        image.unlockFocus()
        return image
    }

    // MARK: Overlay dots (current / selected / hover) — always drawn on top

    func refreshOverlayNodes() {
        guard isBuilt else { return }
        overlayRoot.childNodes.forEach { $0.removeFromParentNode() }

        func dot(_ id: Int?, color: NSColor, sizePx: CGFloat) {
            guard let id, let idx = idToIndex[id] else { return }
            overlayRoot.addChildNode(makePointNode(
                positions: [worldPos[idx]], color: color,
                sizePx: sizePx, minPx: sizePx, depthTested: false
            ))
        }
        dot(currentID, color: NSColor(srgbRed: 0.25, green: 0.78, blue: 1.0, alpha: 1), sizePx: 16)
        if selectedID != currentID { dot(selectedID, color: .white, sizePx: 11) }
        if lastHoverID != selectedID, lastHoverID != currentID {
            dot(lastHoverID, color: NSColor.white.withAlphaComponent(0.7), sizePx: 8)
        }
        if let id = currentID, let idx = idToIndex[id] {
            overlayRoot.addChildNode(makePulseNode(at: worldPos[idx]))
        }
    }

    /// A billboarded "sonar ping" ring that continuously pulses on the signed-in
    /// character's current system. Sized in *screen* pixels each frame from the live
    /// camera distance (same idea as the label layout pass) — small and quiet at every
    /// zoom level instead of a fixed world size that vanishes when zoomed out or
    /// balloons when zoomed in.
    private func makePulseNode(at pos: SIMD3<Double>) -> SCNNode {
        let plane = SCNPlane(width: 1, height: 1)   // scaled to a world size every frame
        let mat = SCNMaterial()
        mat.lightingModel = .constant
        mat.diffuse.contents = Self.pulseRingImage
        mat.blendMode = .add
        mat.writesToDepthBuffer = false
        mat.readsFromDepthBuffer = false
        mat.isDoubleSided = true
        plane.firstMaterial = mat

        let node = SCNNode(geometry: plane)
        node.simdPosition = SIMD3<Float>(Float(pos.x), Float(pos.y), Float(pos.z))
        node.constraints = [SCNBillboardConstraint()]
        node.renderingOrder = 25
        node.opacity = 0
        node.simdScale = SIMD3<Float>(repeating: 0.001)

        let period: CGFloat = 2.0
        let minPx: CGFloat = 13
        let maxPx: CGFloat = 30
        let ping = SCNAction.customAction(duration: TimeInterval(period)) { [weak self] n, elapsed in
            guard let self, let view = self.view else { return }
            let world = SIMD3<Double>(Double(n.simdPosition.x), Double(n.simdPosition.y), Double(n.simdPosition.z))
            let camPos = self.cameraNode.simdPosition
            let cam = SIMD3<Double>(Double(camPos.x), Double(camPos.y), Double(camPos.z))
            let dist = simd_distance(world, cam)
            guard dist > 0.001 else { return }

            let fovRad = CGFloat((self.cameraNode.camera?.fieldOfView ?? 55) * .pi / 180)
            let vpH = max(view.bounds.height, 1)
            let worldPerPx = (2 * CGFloat(dist) * tan(fovRad / 2)) / vpH

            let p = max(0, min(1, elapsed / period))
            let px = minPx + p * (maxPx - minPx)   // 13px -> 30px ripple, at every zoom
            let worldSize = Float(px * worldPerPx)
            n.simdScale = SIMD3<Float>(repeating: worldSize)
            n.opacity = 0.5 * (1 - p) * (1 - p)
        }
        node.runAction(.repeatForever(ping))
        return node
    }

    private static let pulseRingImage: NSImage = {
        let d: CGFloat = 128
        let image = NSImage(size: NSSize(width: d, height: d))
        image.lockFocus()
        if let ctx = NSGraphicsContext.current?.cgContext {
            ctx.setLineWidth(10)
            ctx.setStrokeColor(NSColor(srgbRed: 0.35, green: 0.8, blue: 1.0, alpha: 1).cgColor)
            ctx.strokeEllipse(in: CGRect(x: 14, y: 14, width: d - 28, height: d - 28))
        }
        image.unlockFocus()
        return image
    }()

    // MARK: Camera

    private func setupCamera() {
        guard cameraNode.camera == nil else { return }
        let cam = SCNCamera()
        cam.zNear = 0.05
        cam.zFar = 20_000
        cam.fieldOfView = 55
        // Bloom makes the points read as glowing stars, distinct from the gate haze.
        cam.wantsHDR = true
        cam.wantsExposureAdaptation = false
        cam.bloomIntensity = 0.6
        cam.bloomThreshold = 0.55
        cam.bloomBlurRadius = 8
        cameraNode.camera = cam
        scene.rootNode.addChildNode(cameraNode)
    }

    private func setupBackground() {
        // Flat near-black ground + distance fog: far systems fade out, so the eye can
        // parse the 3-D structure instead of a flat wall of dots.
        let bg = NSColor(calibratedWhite: 0.02, alpha: 1)
        scene.background.contents = bg
        scene.fogColor = bg
        scene.fogStartDistance = galaxyRadius * 0.25
        scene.fogEndDistance = galaxyRadius * 3.2
        scene.fogDensityExponent = 2
    }

    private func updateCamera(animated: Bool = false) {
        let t = camTarget
        let d = camDistance
        let pos = SIMD3<Double>(
            t.x + d * cos(camPitch) * sin(camYaw),
            t.y + d * sin(camPitch),
            t.z + d * cos(camPitch) * cos(camYaw)
        )
        let apply = {
            self.cameraNode.simdPosition = SIMD3<Float>(Float(pos.x), Float(pos.y), Float(pos.z))
            self.cameraNode.look(at: SCNVector3(CGFloat(t.x), CGFloat(t.y), CGFloat(t.z)))
        }
        SCNTransaction.begin()
        SCNTransaction.animationDuration = animated ? 0.45 : 0
        apply()
        SCNTransaction.commit()

        applyLOD()
        // Region labels are an overview aid — only while zoomed out.
        labelsRoot.isHidden = camDistance < labelDistanceThreshold
        updateSystemLabels()
        layoutLabels(labelsRoot, minPx: 11, maxPx: 44, limit: 18, gapPx: 14)
        layoutLabels(systemLabelsRoot, minPx: 10, maxPx: 30, limit: 44, gapPx: 7)
    }

    // Input hooks (called from the SCNView subclass)

    func orbit(dx: CGFloat, dy: CGFloat) {
        camYaw -= Double(dx) * 0.007
        camPitch = min(1.45, max(-1.45, camPitch + Double(dy) * 0.007))
        updateCamera()
    }

    func pan(dx: CGFloat, dy: CGFloat) {
        let right = SIMD3<Double>(cos(camYaw), 0, -sin(camYaw))
        let up = SIMD3<Double>(-sin(camPitch) * sin(camYaw), cos(camPitch), -sin(camPitch) * cos(camYaw))
        let s = camDistance * 0.0016
        camTarget -= right * (Double(dx) * s)
        camTarget += up * (Double(dy) * s)
        updateCamera()
    }

    /// `delta > 0` zooms in (wheel-up / pinch-out).
    func zoom(delta: CGFloat) {
        camDistance = min(maxDistance, max(minDistance, camDistance * pow(0.9965, Double(delta))))
        updateCamera()
    }

    func zoomStep(closer: Bool) {
        camDistance = min(maxDistance, max(minDistance, camDistance * (closer ? 0.6 : 1.0 / 0.6)))
        updateCamera(animated: true)
    }

    func focus(on id: Int, animated: Bool = true) {
        guard let idx = idToIndex[id] else { return }
        camTarget = worldPos[idx]
        camDistance = max(minDistance, galaxyRadius * 0.06)
        updateCamera(animated: animated)
    }

    /// Fly to a constellation's centroid and drop just inside the system-level detail.
    func focusConstellation(_ cid: Int) {
        guard let c = consCentroid[cid] else { return }
        camTarget = c
        camDistance = galaxyRadius * 0.34
        updateCamera(animated: true)
    }

    func frameGalaxy(animated: Bool = true) {
        camTarget = .zero
        camDistance = galaxyRadius * 2.6
        camYaw = 0.6
        camPitch = 0.62
        updateCamera(animated: animated)
    }

    // MARK: Picking

    func handleClick(at point: CGPoint) {
        if lodConstellations {
            if let cid = nearestConstellation(to: point) { focusConstellation(cid) }
            return
        }
        let id = nearestSystem(to: point)
        selectedID = (id != nil && id == selectedID) ? nil : id
    }

    func handleHover(at point: CGPoint) {
        if lodConstellations {
            let cid = point.x < 0 ? nil : nearestConstellation(to: point)
            lastHoverConsID = cid
            if let cid {
                if consNameCache[cid] == nil {
                    Task {
                        let name = await UniverseCache.shared.constellation(id: cid)?.name
                        guard let name else { return }
                        consNameCache[cid] = name
                        if lastHoverConsID == cid, let hi = hoverInfo, hi.id == -cid {
                            hoverInfo = HoverInfo(id: -cid, name: name, security: hi.security, screen: hi.screen)
                        }
                    }
                }
                hoverInfo = HoverInfo(id: -cid, name: consNameCache[cid] ?? "Constellation",
                                      security: consAvgSec[cid] ?? 0, screen: point)
            } else {
                hoverInfo = nil
            }
            return
        }

        let id = point.x < 0 ? nil : nearestSystem(to: point)
        if id != lastHoverID {
            lastHoverID = id
            refreshOverlayNodes()
        }
        if let id, let s = system(id) {
            hoverInfo = HoverInfo(id: id, name: s.name, security: s.security, screen: point)
        } else {
            hoverInfo = nil
        }
    }

    /// Ray-casts the screen point against every position in `points` and returns the
    /// index of the one closest to the ray (within a camera-distance-scaled slack).
    /// O(n) — fine for ~5,500 points at mouse-move rates.
    private func nearestIndex(to p: CGPoint, in points: [SIMD3<Double>], slackScale: Double) -> Int? {
        guard let view, isBuilt, !points.isEmpty else { return nil }
        let near = view.unprojectPoint(SCNVector3(p.x, p.y, 0))
        let far = view.unprojectPoint(SCNVector3(p.x, p.y, 1))
        let o = SIMD3(Double(near.x), Double(near.y), Double(near.z))
        let dv = SIMD3(Double(far.x - near.x), Double(far.y - near.y), Double(far.z - near.z))
        guard simd_length(dv) > 0 else { return nil }
        let d = simd_normalize(dv)

        let cam = SIMD3(Double(cameraNode.simdPosition.x),
                        Double(cameraNode.simdPosition.y),
                        Double(cameraNode.simdPosition.z))
        let maxSlack = galaxyRadius * slackScale

        var best: Int?
        var bestAlong = Double.greatestFiniteMagnitude
        for (i, wp) in points.enumerated() {
            let rel = wp - o
            let along = simd_dot(rel, d)
            guard along > 0, along < bestAlong else { continue }
            let perp = simd_distance(o + d * along, wp)
            let slack = min(maxSlack, max(0.6, simd_distance(cam, wp) * 0.012))
            if perp < slack {
                bestAlong = along
                best = i
            }
        }
        return best
    }

    private func nearestSystem(to p: CGPoint) -> Int? {
        nearestIndex(to: p, in: worldPos, slackScale: 0.04).map { systems[$0].id }
    }

    private func nearestConstellation(to p: CGPoint) -> Int? {
        nearestIndex(to: p, in: consWorld, slackScale: 0.08).map { consList[$0] }
    }

    // MARK: Buckets

    static func securityBucket(_ v: Double) -> Int {
        switch v {
        case 0.9...: return 0
        case 0.7..<0.9: return 1
        case 0.5..<0.7: return 2
        case 0.3..<0.5: return 3
        case 0.1..<0.3: return 4
        default: return 5
        }
    }
    static func securityBucketMidpoint(_ b: Int) -> Double { [1.0, 0.8, 0.6, 0.4, 0.2, -0.1][b] }

    static func killBucket(_ k: Int) -> Int {
        switch k {
        case ..<1: return 0
        case 1..<5: return 1
        case 5..<20: return 2
        case 20..<60: return 3
        default: return 4
        }
    }
    static func killBucketMidpoint(_ b: Int) -> Int { [0, 2, 10, 30, 80][b] }

    /// 0 high-sec · 1 low-sec · 2 null-sec · 3 Pochven.
    static func spaceBucket(regionID: Int, security: Double) -> Int {
        if regionID == 10_000_070 { return 3 }
        switch security {
        case 0.45...: return 0
        case 0.0..<0.45: return 1
        default: return 2
        }
    }
}

// MARK:  SceneKit host

private struct GalaxySceneRepresentable: NSViewRepresentable {
    let model: GalaxySceneModel

    func makeNSView(context: Context) -> SCNView {
        let v = OrbitSCNView()
        v.scene = model.scene
        v.pointOfView = model.cameraNode
        v.allowsCameraControl = false
        v.autoenablesDefaultLighting = false
        v.backgroundColor = .black
        v.antialiasingMode = .multisampling4X
        v.rendersContinuously = false

        v.onOrbit = { dx, dy in model.orbit(dx: dx, dy: dy) }
        v.onPan = { dx, dy in model.pan(dx: dx, dy: dy) }
        v.onZoom = { d in model.zoom(delta: d) }
        v.onClick = { p in model.view = v; model.handleClick(at: p) }
        v.onHoverMove = { p in model.view = v; model.handleHover(at: p) }
        v.onHoverExit = { model.handleHover(at: CGPoint(x: -1, y: -1)) }

        model.view = v
        Task { @MainActor in model.viewAttached() }
        return v
    }

    func updateNSView(_ nsView: SCNView, context: Context) {}
}

/// `SCNView` subclass with an explicit orbit-camera input model: left-drag orbits,
/// ⌥/⌘-drag and right-drag pan, scroll / pinch zoom, a click (no drag) selects, and
/// a tracking area reports hover.
private final class OrbitSCNView: SCNView {
    var onOrbit: ((CGFloat, CGFloat) -> Void)?
    var onPan: ((CGFloat, CGFloat) -> Void)?
    var onZoom: ((CGFloat) -> Void)?
    var onClick: ((CGPoint) -> Void)?
    var onHoverMove: ((CGPoint) -> Void)?
    var onHoverExit: (() -> Void)?

    private var lastDrag: NSPoint?
    private var dragged = false
    private var tracking: NSTrackingArea?

    override var acceptsFirstResponder: Bool { true }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let tracking { removeTrackingArea(tracking) }
        let area = NSTrackingArea(
            rect: bounds,
            options: [.activeInKeyWindow, .mouseMoved, .mouseEnteredAndExited, .inVisibleRect],
            owner: self, userInfo: nil
        )
        addTrackingArea(area)
        tracking = area
    }

    override func scrollWheel(with event: NSEvent) {
        let d = event.hasPreciseScrollingDeltas ? event.scrollingDeltaY : event.scrollingDeltaY * 8
        onZoom?(d)
    }

    override func magnify(with event: NSEvent) {
        onZoom?(event.magnification * 900)
    }

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        lastDrag = event.locationInWindow
        dragged = false
    }

    override func mouseDragged(with event: NSEvent) {
        guard let l = lastDrag else { return }
        let dx = event.locationInWindow.x - l.x
        let dy = event.locationInWindow.y - l.y
        if abs(dx) + abs(dy) > 2 { dragged = true }
        lastDrag = event.locationInWindow
        if event.modifierFlags.contains(.option) || event.modifierFlags.contains(.command) {
            onPan?(dx, dy)
        } else {
            onOrbit?(dx, dy)
        }
    }

    override func mouseUp(with event: NSEvent) {
        if !dragged { onClick?(convert(event.locationInWindow, from: nil)) }
        lastDrag = nil
        dragged = false
    }

    override func rightMouseDown(with event: NSEvent) { lastDrag = event.locationInWindow }

    override func rightMouseDragged(with event: NSEvent) {
        guard let l = lastDrag else { lastDrag = event.locationInWindow; return }
        let dx = event.locationInWindow.x - l.x
        let dy = event.locationInWindow.y - l.y
        lastDrag = event.locationInWindow
        onPan?(dx, dy)
    }

    override func rightMouseUp(with event: NSEvent) { lastDrag = nil }

    override func mouseMoved(with event: NSEvent) {
        super.mouseMoved(with: event)
        onHoverMove?(convert(event.locationInWindow, from: nil))
    }

    override func mouseExited(with event: NSEvent) {
        super.mouseExited(with: event)
        onHoverExit?()
    }
}

// MARK:  Palette

enum GalaxyPalette {
    /// Evenly spaced hues via the golden ratio so neighbouring ordinals stay distinct.
    static func region(ordinal: Int) -> NSColor {
        let hue = (Double(ordinal) * 0.6180339887).truncatingRemainder(dividingBy: 1.0)
        return NSColor(calibratedHue: CGFloat(hue), saturation: 0.6, brightness: 1.0, alpha: 1)
    }

    static func security(_ v: Double) -> NSColor {
        switch v {
        case 0.9...:     return NSColor(srgbRed: 0.36, green: 0.87, blue: 0.97, alpha: 1)
        case 0.7..<0.9:  return NSColor(srgbRed: 0.34, green: 0.82, blue: 0.40, alpha: 1)
        case 0.5..<0.7:  return NSColor(srgbRed: 0.96, green: 0.89, blue: 0.36, alpha: 1)
        case 0.3..<0.5:  return NSColor(srgbRed: 0.97, green: 0.62, blue: 0.26, alpha: 1)
        case 0.1..<0.3:  return NSColor(srgbRed: 1.00, green: 0.44, blue: 0.10, alpha: 1)
        default:         return NSColor(srgbRed: 0.90, green: 0.28, blue: 0.28, alpha: 1)
        }
    }

    static func killHeat(_ kills: Int) -> NSColor {
        switch kills {
        case ..<1:    return NSColor(calibratedWhite: 0.42, alpha: 1)
        case 1..<5:   return NSColor(srgbRed: 0.34, green: 0.82, blue: 0.40, alpha: 1)
        case 5..<20:  return NSColor(srgbRed: 0.96, green: 0.89, blue: 0.36, alpha: 1)
        case 20..<60: return NSColor(srgbRed: 0.97, green: 0.62, blue: 0.26, alpha: 1)
        default:      return NSColor(srgbRed: 0.90, green: 0.28, blue: 0.28, alpha: 1)
        }
    }

    /// 0 high-sec · 1 low-sec · 2 null-sec · 3 Pochven.
    static func space(_ bucket: Int) -> NSColor {
        switch bucket {
        case 0:  return NSColor(srgbRed: 0.32, green: 0.76, blue: 0.96, alpha: 1)
        case 1:  return NSColor(srgbRed: 0.98, green: 0.68, blue: 0.22, alpha: 1)
        case 3:  return NSColor(srgbRed: 0.66, green: 0.36, blue: 0.90, alpha: 1)
        default: return NSColor(srgbRed: 0.88, green: 0.27, blue: 0.30, alpha: 1)
        }
    }
}
