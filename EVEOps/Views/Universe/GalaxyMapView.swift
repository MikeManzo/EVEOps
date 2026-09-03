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

enum MapColorMode: Hashable { case region, security, danger }

// MARK:  Private Models

struct GalaxyPoint: Identifiable, Equatable {
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

struct RegionLabel {
    let name: String
    let regionId: Int
    let x: Double
    let z: Double
}

// MARK:  GalaxyMapView

struct GalaxyMapView: View {
    @Environment(AccountManager.self) var accountManager
    @Environment(DashboardPrefetcher.self) var prefetcher

    @State var points: [GalaxyPoint] = []
    @State var regionLabels: [RegionLabel] = []
    @State var isLoading = true
    @State var loadingProgress: Double = 0
    @State var scale: CGFloat = 1.0
    @State var baseScale: CGFloat = 1.0   // accumulates across pinch gestures
    @State var offset: CGSize = .zero
    @State var dragStart: CGSize = .zero
    @State var hoveredId: Int?
    @State var selectedPoint: GalaxyPoint?
    @State var drillConstellationId: Int?
    @State var drillConstellationName = ""
    @State var searchText = ""
    @State var starfieldSeeds: [(CGFloat, CGFloat, CGFloat)] = []
    @State var canvasSize: CGSize = .zero
    @State var currentConstellationId: Int?
    @State var currentSystemName: String?
    @State var currentSystemSecurity: Double?
    @State var currentShipTypeName: String?
    @State var currentShipCustomName: String?
    // Lazily populated on hover: maps constellationId → set of adjacent constellationIds
    @State var adjacentConstellations: [Int: Set<Int>] = [:]
    @State var hasCenteredOnLoad = false

    // Color mode
    @State var colorMode: MapColorMode = .region
    @State var constellationSecMap: [Int: Double] = [:]
    @State var isLoadingSecMap = false
    // Kill heat: constellationId → total ship + pod kills across its systems in the last hour
    @State var constellationDangerMap: [Int: Int] = [:]
    @State var isLoadingDangerMap = false
    @State var dangerMapAt: Date?

    // Route feature
    @State var isRouteMode = false
    @State var routeOriginId: Int?
    @State var routeDestId: Int?
    @State var routeConstellationPath: [Int] = []
    @State var isLoadingRoute = false
    @State var routeMessage: String?

    // Minimap
    @State var showMinimap = true

    // Autopilot toast
    @State var autopilotToast: String?

    var displayPoints: [GalaxyPoint] {
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
        .navigationTitle("")
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
            if newMode == .danger && !isLoadingDangerMap {
                Task { await loadDangerMap() }
            }
        }
    }

}
