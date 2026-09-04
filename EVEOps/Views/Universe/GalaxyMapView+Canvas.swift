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
    // MARK:  Galaxy Canvas

    var galaxyCanvas: some View {
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
                let dangerMap = constellationDangerMap
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
                    } else if mode == .space {
                        color = secMap[pt.id].map { spaceColor($0) } ?? Color(white: 0.45)
                    } else if mode == .danger {
                        color = dangerMap[pt.id].map { killHeatColor($0) } ?? Color(white: 0.28)
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
    func minimapView(mainSize: CGSize) -> some View {
        let mmW: CGFloat = 130
        let mmH: CGFloat = 84
        let pts = points
        let secMap = constellationSecMap
        let dangerMap = constellationDangerMap
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
                } else if mode == .space, let sec = secMap[pt.id] {
                    col = spaceColor(sec)
                } else if mode == .danger, let kills = dangerMap[pt.id] {
                    col = killHeatColor(kills)
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
    var locationHUD: some View {
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

}
