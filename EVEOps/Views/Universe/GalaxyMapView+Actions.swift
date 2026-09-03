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
    // MARK:  Autopilot

    func setAutopilotDestination(systemId: Int, label: String) async {
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

    func centerOnCurrentLocation() {
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
    func centerOnRegion(_ regionId: Int) {
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

    func makeBaseProjector(points: [GalaxyPoint], size: CGSize) -> (Double, Double) -> CGPoint {
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

    func applyTransform(_ pt: CGPoint, size: CGSize) -> CGPoint {
        let cx = size.width / 2, cy = size.height / 2
        return CGPoint(
            x: cx + (pt.x - cx) * scale + offset.width,
            y: cy + (pt.y - cy) * scale + offset.height
        )
    }

    func securityColor(_ value: Double) -> Color {
        switch value {
        case 0.9...: return .cyan
        case 0.7..<0.9: return .green
        case 0.5..<0.7: return .yellow
        case 0.3..<0.5: return .orange
        case 0.1..<0.3: return Color(red: 1, green: 0.4, blue: 0)
        default: return .red
        }
    }

    func regionColor(_ regionId: Int) -> Color {
        let hash = (regionId &* 2654435761) >> 8
        let hue = Double(hash & 0xFFFFFF) / Double(0xFFFFFF)
        return Color(hue: hue, saturation: 0.65, brightness: 0.95)
    }

    /// Colour for a constellation's total ship + pod kills in the last hour.
    /// Bands are wider than the per-system ones in `DangerLevel` because a
    /// constellation aggregates several systems.
    func killHeatColor(_ kills: Int) -> Color {
        switch kills {
        case ..<1:    return Color(white: 0.30)
        case 1..<5:   return .green
        case 5..<20:  return .yellow
        case 20..<60: return .orange
        default:      return .red
        }
    }

}
