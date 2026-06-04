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

// MARK:  Map Color Mode

private enum MapColorMode: Hashable { case region, security }

// MARK:  Private Models

private struct GalaxyPoint: Identifiable, Equatable {
    let id: Int          // constellationId
    let name: String
    let regionId: Int
    let regionName: String
    let x: Double
    let z: Double
    let systemCount: Int
    let systemIds: [Int]  // first used for route/autopilot

    static func == (lhs: GalaxyPoint, rhs: GalaxyPoint) -> Bool { lhs.id == rhs.id }
}

private struct RegionLabel {
    let name: String
    let regionId: Int
    let x: Double
    let z: Double
}

// MARK:  GalaxyMapView

struct GalaxyMapView: View {
    @Environment(AccountManager.self) private var accountManager
    @Environment(DashboardPrefetcher.self) private var prefetcher

    @State private var points: [GalaxyPoint] = []
    @State private var regionLabels: [RegionLabel] = []
    @State private var isLoading = true
    @State private var loadingProgress: Double = 0
    @State private var scale: CGFloat = 1.0
    @State private var baseScale: CGFloat = 1.0   // accumulates across pinch gestures
    @State private var offset: CGSize = .zero
    @State private var dragStart: CGSize = .zero
    @State private var hoveredId: Int?
    @State private var selectedPoint: GalaxyPoint?
    @State private var drillConstellationId: Int?
    @State private var drillConstellationName = ""
    @State private var searchText = ""
    @State private var starfieldSeeds: [(CGFloat, CGFloat, CGFloat)] = []
    @State private var canvasSize: CGSize = .zero
    @State private var currentConstellationId: Int?
    @State private var currentSystemName: String?
    @State private var currentSystemSecurity: Double?
    @State private var currentShipTypeName: String?
    @State private var currentShipCustomName: String?
    // Lazily populated on hover: maps constellationId → set of adjacent constellationIds
    @State private var adjacentConstellations: [Int: Set<Int>] = [:]
    @State private var hasCenteredOnLoad = false

    // Color mode
    @State private var colorMode: MapColorMode = .region
    @State private var constellationSecMap: [Int: Double] = [:]
    @State private var isLoadingSecMap = false

    // Route feature
    @State private var isRouteMode = false
    @State private var routeOriginId: Int?
    @State private var routeDestId: Int?
    @State private var routeConstellationPath: [Int] = []
    @State private var isLoadingRoute = false
    @State private var routeMessage: String?

    // Minimap
    @State private var showMinimap = true

    // Autopilot toast
    @State private var autopilotToast: String?

    private var displayPoints: [GalaxyPoint] {
        guard !searchText.isEmpty else { return points }
        return points.filter {
            $0.name.localizedCaseInsensitiveContains(searchText) ||
            $0.regionName.localizedCaseInsensitiveContains(searchText)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider()
            if isRouteMode && !isLoading && drillConstellationId == nil {
                routeBanner
                Divider()
            }
            if isLoading {
                loadingView
            } else if let cid = drillConstellationId {
                ConstellationMapView(
                    constellationId: cid,
                    currentSystemId: 0,
                    constellationName: drillConstellationName
                )
                .padding()
            } else {
                ZStack(alignment: .topTrailing) {
                    galaxyCanvas
                    if let sel = selectedPoint, !isRouteMode {
                        popoverView(sel)
                    }
                }
            }
        }
        .safeAreaInset(edge: .top, spacing: 0) {
            HStack {
                Text("Galaxy Map")
                    .font(.largeTitle.bold())
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(.background)
        }
        .navigationTitle("Galaxy Map")
        .task { await loadData() }
        .onAppear {
            if starfieldSeeds.isEmpty {
                starfieldSeeds = (0..<250).map { _ in
                    (CGFloat.random(in: 0...1), CGFloat.random(in: 0...1), CGFloat.random(in: 0.1...1.0))
                }
            }
        }
        .onChange(of: colorMode) { _, newMode in
            if newMode == .security && constellationSecMap.isEmpty && !isLoadingSecMap {
                Task { await loadSecurityMap() }
            }
        }
    }

    // MARK:  Toolbar

    private var toolbar: some View {
        HStack(spacing: 10) {
            if drillConstellationId != nil {
                Button {
                    withAnimation { drillConstellationId = nil; selectedPoint = nil }
                } label: {
                    Label("Galaxy Map", systemImage: "chevron.left")
                        .font(.subheadline)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.blue)
            } else {
                Image(systemName: "globe").foregroundStyle(.blue)
                Text("New Eden").font(.subheadline.bold())
                if !isLoading {
                    Text("(\(points.count) constellations)")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }

            Spacer()

            if drillConstellationId == nil && !isLoading {
                // Color mode
                Picker("Color Mode", selection: $colorMode) {
                    Text("Region").tag(MapColorMode.region)
                    Text("Security").tag(MapColorMode.security)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .controlSize(.small)
                .frame(width: 130)
                .overlay(alignment: .trailing) {
                    if isLoadingSecMap && colorMode == .security {
                        ProgressView().controlSize(.mini).offset(x: -2)
                    }
                }

                Divider().frame(height: 16)

                // Route mode toggle
                Toggle(isOn: $isRouteMode) {
                    Label("Route", systemImage: "point.3.connected.trianglepath.dotted")
                        .font(.caption)
                }
                .toggleStyle(.button)
                .buttonStyle(.bordered)
                .controlSize(.small)
                .tint(isRouteMode ? .orange : nil)
                .onChange(of: isRouteMode) { _, on in
                    if !on { clearRoute() }
                }

                Divider().frame(height: 16)

                HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.secondary).font(.caption)
                    TextField("Search constellation or region…", text: $searchText)
                        .textFieldStyle(.plain).font(.caption).frame(width: 200)
                }
                .padding(.horizontal, 8).padding(.vertical, 4)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 6))

                Divider().frame(height: 16)

                if currentConstellationId != nil {
                    Button { centerOnCurrentLocation() } label: {
                        Label("Find My Location", systemImage: "location.fill")
                            .font(.caption)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)

                    Divider().frame(height: 16)
                }

                HStack(spacing: 4) {
                    Button { withAnimation { scale = max(0.3, scale - 0.3); baseScale = scale } } label: {
                        Image(systemName: "minus.magnifyingglass").font(.caption)
                    }.buttonStyle(.plain)

                    Text("\(Int(scale * 100))%")
                        .font(.caption2.monospacedDigit()).foregroundStyle(.secondary).frame(width: 36)

                    Button { withAnimation { scale = min(6.0, scale + 0.3); baseScale = scale } } label: {
                        Image(systemName: "plus.magnifyingglass").font(.caption)
                    }.buttonStyle(.plain)

                    Button {
                        withAnimation { scale = 1.0; baseScale = 1.0; offset = .zero; dragStart = .zero }
                    } label: {
                        Image(systemName: "arrow.counterclockwise").font(.caption)
                    }.buttonStyle(.plain)
                }
            }
        }
        .padding(.horizontal, 16).padding(.vertical, 8)
    }

    // MARK:  Route Banner

    private var routeBanner: some View {
        HStack(spacing: 8) {
            if isLoadingRoute {
                ProgressView().controlSize(.mini)
                Text("Calculating route…").font(.caption).foregroundStyle(.secondary)
            } else if let msg = routeMessage {
                Image(systemName: routeConstellationPath.isEmpty ? "exclamationmark.triangle" : "checkmark.circle.fill")
                    .foregroundStyle(routeConstellationPath.isEmpty ? Color.orange : Color.green)
                    .font(.caption)
                Text(msg).font(.caption)
            } else if routeOriginId == nil {
                Image(systemName: "1.circle.fill").foregroundStyle(.blue).font(.caption)
                Text("Click a constellation to set the route origin").font(.caption).foregroundStyle(.secondary)
            } else {
                Image(systemName: "2.circle.fill").foregroundStyle(.orange).font(.caption)
                if let origin = points.first(where: { $0.id == routeOriginId }) {
                    HStack(spacing: 3) {
                        Text("Origin:").font(.caption).foregroundStyle(.secondary)
                        Text(origin.name).font(.caption.bold())
                    }
                }
                Text("— click the destination").font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            if routeOriginId != nil || !routeConstellationPath.isEmpty {
                Button("Clear") { clearRoute() }
                    .buttonStyle(.plain)
                    .font(.caption)
                    .foregroundStyle(.blue)
            }
        }
        .padding(.horizontal, 16).padding(.vertical, 6)
        .background(Color.orange.opacity(0.06))
    }

    // MARK:  Loading View

    private var loadingView: some View {
        VStack(spacing: 16) {
            Spacer()
            ProgressView(value: loadingProgress) {
                Text("Loading galaxy map…").font(.subheadline)
            } currentValueLabel: {
                Text("\(Int(loadingProgress * 100))%")
                    .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
            }
            .frame(maxWidth: 320)
            Text("Fetching constellation positions — cached after first load")
                .font(.caption).foregroundStyle(.secondary)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK:  Galaxy Canvas

    private var galaxyCanvas: some View {
        GeometryReader { geo in
            Canvas { ctx, canvasSize in
                let seeds = starfieldSeeds
                let allPoints = points
                let labels = regionLabels
                let currentScale = scale
                let currentOffset = offset
                let hlId = currentConstellationId
                let hovered = hoveredId
                let selectedId = selectedPoint?.id
                let search = searchText
                let filtered: Set<Int> = search.isEmpty ? [] : Set(allPoints.filter {
                    $0.name.localizedCaseInsensitiveContains(search) ||
                    $0.regionName.localizedCaseInsensitiveContains(search)
                }.map(\.id))
                let mode = colorMode
                let secMap = constellationSecMap
                let routePath = routeConstellationPath
                let routeOrigin = routeOriginId
                let routeDest = routeDestId

                let project = makeBaseProjector(points: allPoints, size: canvasSize)
                let ptById = Dictionary(uniqueKeysWithValues: allPoints.map { ($0.id, $0) })

                func transform(_ pt: CGPoint) -> CGPoint {
                    let cx = canvasSize.width / 2, cy = canvasSize.height / 2
                    return CGPoint(
                        x: cx + (pt.x - cx) * currentScale + currentOffset.width,
                        y: cy + (pt.y - cy) * currentScale + currentOffset.height
                    )
                }

                // Starfield
                for seed in seeds {
                    let pt = CGPoint(x: seed.0 * canvasSize.width, y: seed.1 * canvasSize.height)
                    let r: CGFloat = seed.2 < 0.4 ? 0.5 : (seed.2 < 0.7 ? 1.0 : 1.5)
                    let rect = CGRect(x: pt.x - r, y: pt.y - r, width: r * 2, height: r * 2)
                    ctx.fill(Circle().path(in: rect), with: .color(.white.opacity(Double(seed.2) * 0.3)))
                }

                // Region labels (fade out when zoomed in)
                if currentScale < 2.5 && search.isEmpty {
                    for label in labels {
                        let raw = project(label.x, label.z)
                        let screen = transform(raw)
                        let fontSize = max(7.0, min(11.0, 9.0 * Double(currentScale)))
                        let opacity = max(0.08, 0.2 - Double(currentScale) * 0.06)
                        let text = Text(label.name)
                            .font(.system(size: fontSize, weight: .light))
                            .foregroundColor(.white.opacity(opacity))
                        ctx.draw(ctx.resolve(text), at: screen)
                    }
                }

                // Route path lines (drawn before dots so dots appear on top)
                if !routePath.isEmpty {
                    var prevScreen: CGPoint? = nil
                    for cid in routePath {
                        guard let pt = ptById[cid] else { continue }
                        let raw = project(pt.x, pt.z)
                        let screen = transform(raw)
                        if let prev = prevScreen {
                            var path = Path()
                            path.move(to: prev)
                            path.addLine(to: screen)
                            ctx.stroke(path, with: .color(.orange.opacity(0.55)),
                                       style: StrokeStyle(lineWidth: 1.5))
                        }
                        prevScreen = screen
                    }
                }

                // Adjacency lines — shown for the selected constellation (click to reveal).
                // Solid for same-region connections, dashed for cross-region jumps.
                let adjMap = adjacentConstellations
                if let selId = selectedId, let adjIds = adjMap[selId],
                   let selPt = ptById[selId] {
                    let selScreen = transform(project(selPt.x, selPt.z))
                    for adjId in adjIds {
                        guard let adjPt = ptById[adjId] else { continue }
                        let adjScreen = transform(project(adjPt.x, adjPt.z))
                        let crossRegion = adjPt.regionId != selPt.regionId
                        var path = Path()
                        path.move(to: selScreen)
                        path.addLine(to: adjScreen)
                        ctx.stroke(path, with: .color(.white.opacity(crossRegion ? 0.2 : 0.45)),
                                   style: StrokeStyle(lineWidth: crossRegion ? 0.8 : 1.2,
                                                      dash: crossRegion ? [4, 3] : []))
                    }
                }

                // Constellation dots + progressive name labels.
                var placedLabelRects: [CGRect] = []

                for pt in allPoints {
                    let isMatch = search.isEmpty || filtered.contains(pt.id)
                    let isCurrent = pt.id == hlId
                    let isHovered = pt.id == hovered
                    let isRouteOrigin = pt.id == routeOrigin
                    let isRouteDest   = pt.id == routeDest
                    let isOnRoute     = !isRouteOrigin && !isRouteDest && routePath.contains(pt.id)

                    let raw = project(pt.x, pt.z)
                    let screen = transform(raw)

                    guard screen.x >= -30 && screen.x <= canvasSize.width + 30 &&
                          screen.y >= -30 && screen.y <= canvasSize.height + 30 else { continue }

                    // Dot color based on mode
                    let color: Color
                    if isRouteOrigin {
                        color = .blue
                    } else if isRouteDest {
                        color = .green
                    } else if mode == .security {
                        color = secMap[pt.id].map { securityColor($0) } ?? Color(white: 0.45)
                    } else {
                        color = regionColor(pt.regionId)
                    }

                    let isSelected = pt.id == selectedId
                    let radius: CGFloat = (isSelected || isCurrent || isRouteOrigin || isRouteDest) ? 12.0
                                        : (isHovered ? 10.0 : 8.0)
                    let dotAlpha: Double = isMatch ? 1.0 : 0.07

                    // Outer glow for highlighted dots
                    if (isCurrent || isSelected || isRouteOrigin || isRouteDest) && isMatch {
                        let glowR: CGFloat = radius + 7
                        let glowRect = CGRect(x: screen.x - glowR, y: screen.y - glowR, width: glowR * 2, height: glowR * 2)
                        ctx.fill(Circle().path(in: glowRect), with: .color(.white.opacity(0.12)))
                        let innerR: CGFloat = radius + 3
                        let innerRect = CGRect(x: screen.x - innerR, y: screen.y - innerR, width: innerR * 2, height: innerR * 2)
                        ctx.fill(Circle().path(in: innerRect), with: .color(color.opacity(0.3)))
                    }

                    // Subtle glow for intermediate route waypoints
                    if isOnRoute && isMatch {
                        let glowR: CGFloat = radius + 4
                        let glowRect = CGRect(x: screen.x - glowR, y: screen.y - glowR, width: glowR * 2, height: glowR * 2)
                        ctx.fill(Circle().path(in: glowRect), with: .color(Color.orange.opacity(0.15)))
                    }

                    let rect = CGRect(x: screen.x - radius, y: screen.y - radius, width: radius * 2, height: radius * 2)

                    // Sphere shading: light from top-left
                    let lightCenter = CGPoint(x: screen.x - radius * 0.35, y: screen.y - radius * 0.35)
                    ctx.fill(Circle().path(in: rect), with: .radialGradient(
                        Gradient(stops: [
                            .init(color: color.opacity(dotAlpha),              location: 0.0),
                            .init(color: color.opacity(dotAlpha * 0.55),       location: 0.5),
                            .init(color: Color.black.opacity(dotAlpha * 0.9),  location: 1.0)
                        ]),
                        center: lightCenter,
                        startRadius: 0,
                        endRadius: radius * 2.2
                    ))

                    // Specular highlight
                    if isMatch {
                        let specR = max(1.2, radius * 0.32)
                        let specRect = CGRect(
                            x: screen.x - radius * 0.38 - specR,
                            y: screen.y - radius * 0.38 - specR,
                            width: specR * 2, height: specR * 2
                        )
                        ctx.fill(Circle().path(in: specRect), with: .color(.white.opacity(0.75)))
                    }

                    if isCurrent && isMatch {
                        ctx.stroke(Circle().path(in: rect), with: .color(.white.opacity(0.85)), lineWidth: 1.5)
                    } else if isRouteOrigin && isMatch {
                        ctx.stroke(Circle().path(in: rect), with: .color(.blue.opacity(0.9)), lineWidth: 2)
                    } else if isRouteDest && isMatch {
                        ctx.stroke(Circle().path(in: rect), with: .color(.green.opacity(0.9)), lineWidth: 2)
                    } else if (isSelected || isHovered) && isMatch {
                        ctx.stroke(Circle().path(in: rect), with: .color(.white.opacity(0.5)), lineWidth: 1)
                    }

                    guard isMatch else { continue }

                    let showLabel: Bool
                    if isHovered || isCurrent || isRouteOrigin || isRouteDest {
                        showLabel = true
                    } else if currentScale >= 3.0 {
                        showLabel = true
                    } else if currentScale >= 1.8 {
                        let fontSize = 6.0 + Double(currentScale) * 1.5
                        let estWidth = CGFloat(pt.name.count) * CGFloat(fontSize) * 0.58
                        let labelRect = CGRect(
                            x: screen.x - estWidth / 2,
                            y: screen.y - radius - CGFloat(fontSize) - 4,
                            width: estWidth,
                            height: CGFloat(fontSize) + 2
                        )
                        let overlaps = placedLabelRects.contains { $0.intersects(labelRect) }
                        if !overlaps {
                            placedLabelRects.append(labelRect)
                            showLabel = true
                        } else {
                            showLabel = false
                        }
                    } else {
                        showLabel = false
                    }

                    if showLabel {
                        let fontSize: CGFloat = isCurrent
                            ? max(10, min(13, 8 + currentScale * 1.5))
                            : max(8,  min(11, 6 + currentScale * 1.5))
                        let labelAlpha = isCurrent ? 1.0 : min(1.0, 0.45 + (currentScale - 1.8) * 0.4)
                        let nameLabel = Text(pt.name)
                            .font(.system(size: fontSize, weight: isCurrent ? .semibold : .regular))
                            .foregroundColor(.white.opacity(labelAlpha))
                        let resolved = ctx.resolve(nameLabel)
                        let labelSize = resolved.measure(in: canvasSize)
                        ctx.draw(resolved, at: CGPoint(
                            x: screen.x,
                            y: screen.y - radius - labelSize.height / 2 - 2
                        ))
                    }
                }
            }
            .overlay {
                let proj = makeBaseProjector(points: points, size: geo.size)

                // Constellation hit targets
                ForEach(displayPoints) { pt in
                    let raw = proj(pt.x, pt.z)
                    let screen = applyTransform(raw, size: geo.size)
                    Circle()
                        .fill(.clear)
                        .frame(width: 28, height: 28)
                        .contentShape(Circle())
                        .position(screen)
                        .onHover { hoveredId = $0 ? pt.id : nil }
                        .onTapGesture {
                            if isRouteMode {
                                handleRouteTap(pt)
                            } else {
                                withAnimation(.easeInOut(duration: 0.2)) {
                                    selectedPoint = (selectedPoint?.id == pt.id) ? nil : pt
                                }
                            }
                        }
                }

                // Region label hit targets — invisible tap areas over each region label.
                // Only shown when labels are visible (low zoom, no active search).
                if scale < 2.5 && searchText.isEmpty {
                    ForEach(regionLabels, id: \.regionId) { label in
                        let raw = proj(label.x, label.z)
                        let screen = applyTransform(raw, size: geo.size)
                        Button { centerOnRegion(label.regionId) } label: {
                            Color.clear.frame(width: 90, height: 24)
                        }
                        .buttonStyle(.plain)
                        .position(screen)
                        .help("Zoom to \(label.name)")
                    }
                }
            }
            .overlay(alignment: .bottomLeading) {
                locationHUD
            }
            .overlay(alignment: .bottomTrailing) {
                if showMinimap && !points.isEmpty {
                    minimapView(mainSize: geo.size)
                }
            }
            .overlay(alignment: .top) {
                if let toast = autopilotToast {
                    Text(toast)
                        .font(.caption)
                        .padding(.horizontal, 12).padding(.vertical, 6)
                        .background(.thinMaterial, in: Capsule())
                        .padding(.top, 8)
                        .transition(.move(edge: .top).combined(with: .opacity))
                }
            }
            .animation(.easeInOut(duration: 0.3), value: autopilotToast)
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
                    .onChanged { value in
                        scale = min(6.0, max(0.3, baseScale * value.magnification))
                    }
                    .onEnded { value in
                        baseScale = min(6.0, max(0.3, baseScale * value.magnification))
                        scale = baseScale
                    }
            )
            .onAppear { canvasSize = geo.size }
            .onChange(of: geo.size) { canvasSize = $1 }
            .onChange(of: canvasSize) { _, newSize in
                if newSize != .zero && !hasCenteredOnLoad, let cid = currentConstellationId {
                    hasCenteredOnLoad = true
                    selectedPoint = points.first(where: { $0.id == cid })
                    centerOnCurrentLocation()
                }
            }
            .onChange(of: selectedPoint) { _, newSel in
                if let pt = newSel, adjacentConstellations[pt.id] == nil {
                    Task { await loadAdjacency(for: pt.id) }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(white: 0.03))
    }

    // MARK:  Minimap

    /// Small overview in the bottom-right corner showing the full galaxy and a viewport rectangle.
    private func minimapView(mainSize: CGSize) -> some View {
        let mmW: CGFloat = 130
        let mmH: CGFloat = 84
        let pts = points
        let secMap = constellationSecMap
        let mode = colorMode
        let hlId = currentConstellationId
        let routePath = routeConstellationPath
        let currentScale = scale
        let currentOffset = offset

        return Canvas { ctx, mmSize in
            // Background
            ctx.fill(Rectangle().path(in: CGRect(origin: .zero, size: mmSize)),
                     with: .color(Color(white: 0.06).opacity(0.92)))

            guard !pts.isEmpty else { return }

            // Galaxy bounds for minimap projection
            let xs = pts.map(\.x), zs = pts.map(\.z)
            let minX = xs.min()!, maxX = xs.max()!
            let minZ = zs.min()!, maxZ = zs.max()!
            let maxRange = max(maxX - minX, maxZ - minZ, 1)
            let mmPad: CGFloat = 5
            let sMini = min(mmSize.width - mmPad * 2, mmSize.height - mmPad * 2) / CGFloat(maxRange)
            let cxGal = (minX + maxX) / 2
            let czGal = (minZ + maxZ) / 2

            func projMini(_ x: Double, _ z: Double) -> CGPoint {
                CGPoint(x: mmSize.width / 2 + CGFloat(x - cxGal) * sMini,
                        y: mmSize.height / 2 + CGFloat(z - czGal) * sMini)
            }

            // Draw route path first (so dots sit on top)
            if routePath.count >= 2 {
                let ptById = Dictionary(uniqueKeysWithValues: pts.map { ($0.id, $0) })
                var prevMm: CGPoint? = nil
                for cid in routePath {
                    guard let pt = ptById[cid] else { continue }
                    let mm = projMini(pt.x, pt.z)
                    if let prev = prevMm {
                        var path = Path()
                        path.move(to: prev)
                        path.addLine(to: mm)
                        ctx.stroke(path, with: .color(Color.orange.opacity(0.7)),
                                   style: StrokeStyle(lineWidth: 0.75))
                    }
                    prevMm = mm
                }
            }

            // Constellation dots
            for pt in pts {
                let screen = projMini(pt.x, pt.z)
                let isOnRoute = routePath.contains(pt.id)
                let r: CGFloat = isOnRoute ? 1.3 : 0.85
                let rect = CGRect(x: screen.x - r, y: screen.y - r, width: r * 2, height: r * 2)
                let col: Color
                if isOnRoute {
                    col = .orange
                } else if mode == .security, let sec = secMap[pt.id] {
                    col = securityColor(sec)
                } else {
                    col = regionColor(pt.regionId)
                }
                ctx.fill(Circle().path(in: rect), with: .color(col.opacity(isOnRoute ? 0.9 : 0.6)))
            }

            // Current location
            if let cid = hlId, let pt = pts.first(where: { $0.id == cid }) {
                let screen = projMini(pt.x, pt.z)
                let gr: CGFloat = 4
                ctx.fill(Circle().path(in: CGRect(x: screen.x - gr, y: screen.y - gr, width: gr * 2, height: gr * 2)),
                         with: .color(.white.opacity(0.2)))
                let r: CGFloat = 2.5
                ctx.fill(Circle().path(in: CGRect(x: screen.x - r, y: screen.y - r, width: r * 2, height: r * 2)),
                         with: .color(.white))
            }

            // Viewport rectangle.
            // sMain and sMini share the same maxRange, so ratio = sMini / sMain.
            let mainPad: CGFloat = 40
            let sMain = min(mainSize.width - mainPad * 2, mainSize.height - mainPad * 2) / CGFloat(maxRange)
            let ratio = CGFloat(sMini / sMain)

            // Viewport center in main canvas raw-projection coords (scale=1, offset=0):
            //   vpCenterRaw = mainCenter - offset / scale
            let vpCenterRawX = mainSize.width  / 2 - currentOffset.width  / currentScale
            let vpCenterRawY = mainSize.height / 2 - currentOffset.height / currentScale
            let vpHalfW = (mainSize.width  / 2) / currentScale
            let vpHalfH = (mainSize.height / 2) / currentScale

            let mmCx = mmSize.width  / 2
            let mmCy = mmSize.height / 2
            let mainCx = mainSize.width  / 2
            let mainCy = mainSize.height / 2

            let vpLeft   = mmCx + (vpCenterRawX - mainCx - vpHalfW) * ratio
            let vpRight  = mmCx + (vpCenterRawX - mainCx + vpHalfW) * ratio
            let vpTop    = mmCy + (vpCenterRawY - mainCy - vpHalfH) * ratio
            let vpBottom = mmCy + (vpCenterRawY - mainCy + vpHalfH) * ratio

            if vpRight > vpLeft + 1 && vpBottom > vpTop + 1 {
                let vr = CGRect(x: vpLeft, y: vpTop, width: vpRight - vpLeft, height: vpBottom - vpTop)
                ctx.fill(Rectangle().path(in: vr), with: .color(.white.opacity(0.04)))
                ctx.stroke(Rectangle().path(in: vr), with: .color(.white.opacity(0.45)), lineWidth: 0.75)
            }
        }
        .frame(width: mmW, height: mmH)
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.white.opacity(0.15), lineWidth: 0.5))
        .padding(12)
    }

    // MARK:  Location HUD

    @ViewBuilder
    private var locationHUD: some View {
        if let sysName = currentSystemName,
           let sec = currentSystemSecurity,
           let consId = currentConstellationId,
           let pt = points.first(where: { $0.id == consId }) {
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 6) {
                    Image(systemName: "location.fill")
                        .font(.caption2).foregroundStyle(.blue)
                    Text(accountManager.selectedAccount?.characterName ?? "")
                        .font(.caption.bold())
                }

                Divider()

                HStack(spacing: 6) {
                    Text(sysName).font(.caption.bold())
                    Text(String(format: "%.1f", sec))
                        .font(.caption2.bold().monospacedDigit())
                        .foregroundStyle(securityColor(sec))
                        .padding(.horizontal, 4).padding(.vertical, 1)
                        .background(securityColor(sec).opacity(0.15), in: Capsule())
                }

                if let shipType = currentShipTypeName {
                    HStack(spacing: 4) {
                        Image(systemName: "airplane").font(.caption2).foregroundStyle(.secondary)
                        if let customName = currentShipCustomName {
                            Text("\"\(customName)\"").font(.caption2).italic()
                            Text("(\(shipType))").font(.caption2).foregroundStyle(.secondary)
                        } else {
                            Text(shipType).font(.caption2).foregroundStyle(.secondary)
                        }
                    }
                }

                HStack(spacing: 4) {
                    Image(systemName: "star.fill").font(.caption2).foregroundStyle(.secondary)
                    Text(pt.name).font(.caption2).foregroundStyle(.secondary)
                    Text("·").foregroundStyle(.tertiary).font(.caption2)
                    Text(pt.regionName).font(.caption2).foregroundStyle(.secondary)
                }
            }
            .padding(10)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 8))
            .padding(12)
        }
    }

    // MARK:  Constellation Popover

    private func popoverView(_ pt: GalaxyPoint) -> some View {
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

    private func handleRouteTap(_ pt: GalaxyPoint) {
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

    private func calculateRoute() async {
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

    private func clearRoute() {
        routeOriginId = nil
        routeDestId = nil
        routeConstellationPath = []
        routeMessage = nil
        isLoadingRoute = false
    }

    // MARK:  Autopilot

    private func setAutopilotDestination(systemId: Int, label: String) async {
        guard let account = accountManager.selectedAccount, !account.isTokenExpired else { return }
        do {
            let token = try await accountManager.validToken(for: account)
            try await ESIClient.shared.postAction(
                "/ui/autopilot/waypoint/",
                token: token,
                queryItems: [
                    URLQueryItem(name: "add_to_beginning",    value: "false"),
                    URLQueryItem(name: "clear_other_waypoints", value: "true"),
                    URLQueryItem(name: "destination_id",       value: "\(systemId)")
                ]
            )
            withAnimation { autopilotToast = "Destination set: \(label)" }
        } catch let err as ESIError {
            switch err {
            case .serverError(let code, _) where code == 403:
                withAnimation { autopilotToast = "Requires esi-ui.write_waypoint.v1 scope" }
            default:
                withAnimation { autopilotToast = "Could not set destination" }
            }
        } catch {
            withAnimation { autopilotToast = "Could not set destination" }
        }
        try? await Task.sleep(for: .seconds(3))
        withAnimation { autopilotToast = nil }
    }

    // MARK:  Center On Location

    private func centerOnCurrentLocation() {
        guard let cid = currentConstellationId,
              let pt = points.first(where: { $0.id == cid }),
              canvasSize != .zero else { return }
        let proj = makeBaseProjector(points: points, size: canvasSize)
        let raw = proj(pt.x, pt.z)
        let targetScale: CGFloat = 3.5
        let cx = canvasSize.width / 2, cy = canvasSize.height / 2
        let newOffset = CGSize(width: -(raw.x - cx) * targetScale, height: -(raw.y - cy) * targetScale)
        withAnimation(.easeInOut(duration: 0.5)) {
            scale = targetScale
            baseScale = targetScale
            offset = newOffset
            dragStart = newOffset
        }
    }

    // MARK:  Center On Region

    /// Animate the viewport to fit the selected region.
    private func centerOnRegion(_ regionId: Int) {
        let regionPts = points.filter { $0.regionId == regionId }
        guard !regionPts.isEmpty, canvasSize != .zero else { return }
        let proj = makeBaseProjector(points: points, size: canvasSize)
        let screens = regionPts.map { proj($0.x, $0.z) }
        let minX = screens.map(\.x).min()!
        let maxX = screens.map(\.x).max()!
        let minY = screens.map(\.y).min()!
        let maxY = screens.map(\.y).max()!
        let midX = (minX + maxX) / 2
        let midY = (minY + maxY) / 2
        let rangeX = maxX - minX + 120
        let rangeY = maxY - minY + 80
        let targetScale = min(canvasSize.width / rangeX, canvasSize.height / rangeY, 5.0)
        let cx = canvasSize.width / 2, cy = canvasSize.height / 2
        let newOffset = CGSize(width: -(midX - cx) * targetScale, height: -(midY - cy) * targetScale)
        withAnimation(.easeInOut(duration: 0.5)) {
            scale = targetScale
            baseScale = targetScale
            offset = newOffset
            dragStart = newOffset
        }
    }

    // MARK:  Projection Helpers

    private func makeBaseProjector(points: [GalaxyPoint], size: CGSize) -> (Double, Double) -> CGPoint {
        guard !points.isEmpty else { return { _, _ in CGPoint(x: size.width / 2, y: size.height / 2) } }
        let xs = points.map(\.x), zs = points.map(\.z)
        let minX = xs.min()!, maxX = xs.max()!
        let minZ = zs.min()!, maxZ = zs.max()!
        let maxRange = max(maxX - minX, maxZ - minZ, 1)
        let padding: CGFloat = 40
        let s = min(size.width - padding * 2, size.height - padding * 2) / CGFloat(maxRange)
        let cx = (minX + maxX) / 2, cz = (minZ + maxZ) / 2
        return { x, z in
            CGPoint(
                x: size.width / 2 + CGFloat(x - cx) * s,
                y: size.height / 2 + CGFloat(z - cz) * s
            )
        }
    }

    private func applyTransform(_ pt: CGPoint, size: CGSize) -> CGPoint {
        let cx = size.width / 2, cy = size.height / 2
        return CGPoint(
            x: cx + (pt.x - cx) * scale + offset.width,
            y: cy + (pt.y - cy) * scale + offset.height
        )
    }

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

    private func regionColor(_ regionId: Int) -> Color {
        let hash = (regionId &* 2654435761) >> 8
        let hue = Double(hash & 0xFFFFFF) / Double(0xFFFFFF)
        return Color(hue: hue, saturation: 0.65, brightness: 0.95)
    }

    // MARK:  Data Loading

    private func loadData() async {
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
    private func loadSecurityMap() async {
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

    /// Loads stargate adjacency for a constellation on first select.
    /// Walks constellation → systems → stargates → destination systems → destination constellations.
    private func loadAdjacency(for constellationId: Int) async {
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

    private func resolveCurrentLocation() async {
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

    private func applyLocationInfo(sys: ESISolarSystem, ship: ESICharacterShip?, charID: Int) {
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
