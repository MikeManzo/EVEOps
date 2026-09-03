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
    // MARK:  Toolbar

    var toolbar: some View {
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
                    Text("Kills").tag(MapColorMode.danger)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .controlSize(.small)
                .frame(width: 190)
                .overlay(alignment: .trailing) {
                    if (isLoadingSecMap && colorMode == .security) || (isLoadingDangerMap && colorMode == .danger) {
                        ProgressView().controlSize(.mini).offset(x: -2)
                    }
                }

                if colorMode == .danger, let dangerMapAt {
                    Text("as of \(dangerMapAt, format: .relative(presentation: .named))")
                        .font(.caption2).foregroundStyle(.tertiary)
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

                    Text(Double(scale).formatted(.percent.precision(.fractionLength(0))))
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

    var routeBanner: some View {
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

    var loadingView: some View {
        VStack(spacing: 16) {
            Spacer()
            ProgressView(value: loadingProgress) {
                Text("Loading galaxy map…").font(.subheadline)
            } currentValueLabel: {
                Text(loadingProgress.formatted(.percent.precision(.fractionLength(0))))
                    .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
            }
            .frame(maxWidth: 320)
            Text("Fetching constellation positions — cached after first load")
                .font(.caption).foregroundStyle(.secondary)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

}
