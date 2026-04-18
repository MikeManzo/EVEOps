import SwiftUI

// MARK: - Private Models

private struct GalaxyPoint: Identifiable {
    let id: Int          // constellationId
    let name: String
    let regionId: Int
    let regionName: String
    let x: Double
    let z: Double
    let systemCount: Int
}

private struct RegionLabel {
    let name: String
    let regionId: Int
    let x: Double
    let z: Double
}

// MARK: - GalaxyMapView

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
                    if let sel = selectedPoint {
                        popoverView(sel)
                    }
                }
            }
        }
        .task { await loadData() }
        .onAppear {
            if starfieldSeeds.isEmpty {
                starfieldSeeds = (0..<250).map { _ in
                    (CGFloat.random(in: 0...1), CGFloat.random(in: 0...1), CGFloat.random(in: 0.1...1.0))
                }
            }
        }
    }

    // MARK: - Toolbar

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

    // MARK: - Loading View

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

    // MARK: - Galaxy Canvas

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
                let search = searchText
                let filtered: Set<Int> = search.isEmpty ? [] : Set(allPoints.filter {
                    $0.name.localizedCaseInsensitiveContains(search) ||
                    $0.regionName.localizedCaseInsensitiveContains(search)
                }.map(\.id))

                let project = makeBaseProjector(points: allPoints, size: canvasSize)

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

                // Constellation dots + progressive name labels.
                // Labels fade in as zoom increases, with overlap avoidance at lower zoom levels
                // so the map stays readable across the full zoom range.
                var placedLabelRects: [CGRect] = []

                for pt in allPoints {
                    let isMatch = search.isEmpty || filtered.contains(pt.id)
                    let isCurrent = pt.id == hlId
                    let isHovered = pt.id == hovered

                    let raw = project(pt.x, pt.z)
                    let screen = transform(raw)

                    // Cull off-screen points (keep a small margin for labels that bleed in)
                    guard screen.x >= -30 && screen.x <= canvasSize.width + 30 &&
                          screen.y >= -30 && screen.y <= canvasSize.height + 30 else { continue }

                    let color = regionColor(pt.regionId)
                    let opacity = isMatch ? 1.0 : 0.05
                    let radius: CGFloat = isCurrent ? 5.0 : (isHovered ? 4.5 : 2.5)

                    if isCurrent && isMatch {
                        let glowRect = CGRect(x: screen.x - 13, y: screen.y - 13, width: 26, height: 26)
                        ctx.fill(Circle().path(in: glowRect), with: .color(.white.opacity(0.15)))
                        let innerGlow = CGRect(x: screen.x - 8, y: screen.y - 8, width: 16, height: 16)
                        ctx.fill(Circle().path(in: innerGlow), with: .color(color.opacity(0.35)))
                    }

                    let rect = CGRect(x: screen.x - radius, y: screen.y - radius, width: radius * 2, height: radius * 2)
                    ctx.fill(Circle().path(in: rect), with: .color(color.opacity(opacity)))

                    if isCurrent && isMatch {
                        ctx.stroke(Circle().path(in: rect), with: .color(.white.opacity(0.9)), lineWidth: 1.5)
                    } else if isHovered && isMatch {
                        ctx.stroke(Circle().path(in: rect), with: .color(.white.opacity(0.6)), lineWidth: 1)
                    }

                    guard isMatch else { continue }

                    // Determine whether to draw a name label for this dot:
                    //   - Hovered or current: always
                    //   - scale >= 3.0: all visible labels (few enough that overlap isn't an issue)
                    //   - scale 1.8–3.0: overlap-avoided labels (fade in as zoom increases)
                    //   - scale < 1.8: no labels (too dense — region labels provide orientation)
                    let showLabel: Bool
                    if isHovered || isCurrent {
                        showLabel = true
                    } else if currentScale >= 3.0 {
                        showLabel = true
                    } else if currentScale >= 1.8 {
                        // Estimate label footprint; skip if it overlaps an already-placed label.
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
                ForEach(displayPoints) { pt in
                    let raw = proj(pt.x, pt.z)
                    let screen = applyTransform(raw, size: geo.size)
                    Circle()
                        .fill(.clear)
                        .frame(width: 20, height: 20)
                        .contentShape(Circle())
                        .position(screen)
                        .onHover { hoveredId = $0 ? pt.id : nil }
                        .onTapGesture {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                selectedPoint = (selectedPoint?.id == pt.id) ? nil : pt
                            }
                        }
                }
            }
            .overlay(alignment: .bottomLeading) {
                locationHUD
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
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(white: 0.03))
    }

    // MARK: - Location HUD

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

    // MARK: - Constellation Popover

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
        }
        .padding(12)
        .frame(width: 230)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 10))
        .padding(12)
    }

    // MARK: - Center On Location

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

    // MARK: - Projection Helpers

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

    // MARK: - Data Loading

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
                    systemCount: cons.systems?.count ?? 0
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

        // Resolve current character location
        await resolveCurrentLocation()
    }

    private func resolveCurrentLocation() async {
        guard let account = accountManager.selectedAccount else { return }
        let charID = account.characterID

        // Try prefetcher first (instant, no network)
        if let data = prefetcher.data(for: charID) {
            let sysId = data.location.solarSystemId
            if let sys = prefetcher.resolvedSystems[sysId] {
                applyLocationInfo(sys: sys, ship: data.ship, charID: charID)
                return
            }
            // System not pre-resolved — fetch it
            if let sys = await UniverseCache.shared.solarSystem(id: sysId) {
                applyLocationInfo(sys: sys, ship: data.ship, charID: charID)
                return
            }
        }

        // Fallback: live fetch
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
            // Show custom name only if different from the type name
            currentShipCustomName = (ship.shipName != typeName && !ship.shipName.isEmpty) ? ship.shipName : nil
        }
    }
}
