// ShipModelViewer.swift
// EVEOps
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
import RealityKit
import ModelIO
import Metal
import CoreGraphics
import AppKit
import UniformTypeIdentifiers
import OSLog

// MARK: - LightingPreset

enum LightingPreset: String, CaseIterable, Identifiable {
    case deepSpace = "Deep Space"
    case hangar    = "Hangar"
    case combat    = "Combat"
    case wormhole  = "Wormhole"
    var id: String { rawValue }
    var title: LocalizedStringKey {
        switch self {
        case .deepSpace: "Deep Space"
        case .hangar:    "Hangar"
        case .combat:    "Combat"
        case .wormhole:  "Wormhole"
        }
    }
}

// MARK: - Drag state (reference type — shared between event monitor closures)

private final class DragState {
    var active    = false
    var lastPoint = CGPoint.zero
}

// MARK: - Applied-state tracker (reference type — mutations stay out of SwiftUI state)

private final class AppliedState {
    var albedo:    URL? = nil
    var normal:    URL? = nil
    var roughness: URL? = nil
    var emissive:  URL? = nil
    var preset:    LightingPreset? = nil
    var skyboxTex: TextureResource?     = nil
    var envRes:    EnvironmentResource? = nil
}

// MARK: - Scene entity bag

// Reference type so mutations don't trigger SwiftUI diff when we update
// entity transforms directly.
private final class ShipScene {
    var pivot:     Entity?      = nil
    var camera:    Entity?      = nil
    var ship:      ModelEntity? = nil
    var keyLight:  Entity?      = nil
    var fillLight: Entity?      = nil
    var rimLight:  Entity?      = nil
    var skybox:    ModelEntity? = nil
    var iblEntity: Entity?      = nil
}

// MARK: - ShipRealityKitView

/// Renders a ship .obj model using RealityKit with PhysicallyBasedMaterial.
/// Orbit via drag, zoom via scroll/pinch. Replaces the former SceneKit-based viewer.
struct ShipRealityKitView: View {
    let objURL:          URL
    var albedoDDSURL:    URL? = nil
    var normalDDSURL:    URL? = nil
    var roughnessDDSURL: URL? = nil
    var emissiveDDSURL:  URL? = nil
    var lightingPreset:  LightingPreset = .deepSpace
    var wireframe:       Bool = false  // reserved — not currently supported in RealityKit

    // MARK: Input state
    @State private var yaw:         Float = 0.25
    @State private var pitch:       Float = -0.15
    @State private var cameraZ:     Float = 5.0
    @State private var minCameraZ:  Float = 0.5     // updated after mesh loads
    @State private var maxCameraZ:  Float = 500.0   // updated after mesh loads
    @State private var isHovered = false
    @State private var monitors: [Any] = []
    private let drag = DragState()

    // MARK: Pre-loaded texture resources
    @State private var albedoTex:   TextureResource? = nil
    @State private var normalTex:   TextureResource? = nil
    @State private var roughTex:    TextureResource? = nil
    @State private var metalTex:    TextureResource? = nil
    @State private var aoTex:       TextureResource? = nil
    @State private var emissiveTex: TextureResource? = nil

    // MARK: Environment / skybox resources (updated per lighting preset)
    @State private var skyboxTex:   TextureResource?    = nil
    @State private var envResource: EnvironmentResource? = nil

    // MARK: Applied-state tracking (reference type — never triggers SwiftUI invalidation)
    private let applied = AppliedState()

    @State private var scene = ShipScene()

    private var textureKey: String {
        [albedoDDSURL, normalDDSURL, roughnessDDSURL, emissiveDDSURL]
            .map { $0?.lastPathComponent ?? "-" }.joined(separator: "|")
    }

    // MARK: Body

    var body: some View {
        RealityView { content in
            for entity in buildSceneEntities() { content.add(entity) }
        } update: { _ in
            updateScene()
        }
        .background(Color.black)
        .onHover { isHovered = $0 }
        .onAppear  { installMonitors() }
        .onDisappear { removeMonitors() }
        .task(id: lightingPreset.id) { await loadEnvironment() }
        .task(id: textureKey) { await loadTextures() }
    }

    // MARK: Event monitors
    //
    // NSEvent local monitors receive all window events regardless of which NSView the
    // cursor is over — bypassing the NSView hit-test routing that fails with RealityKit's
    // backing view. .onHover guards them so they only fire when the cursor is over this view.

    private func installMonitors() {
        guard monitors.isEmpty else { return }
        let drag = self.drag  // capture the reference-type DragState

        let scroll = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [self] event in
            guard isHovered else { return event }
            // Proportional zoom: each unit of delta scales cameraZ by a fixed percentage
            // so feel is consistent regardless of current distance. Scroll up = zoom in.
            let sensitivity: Float = event.hasPreciseScrollingDeltas ? 0.004 : 0.04
            let factor = 1.0 + Float(event.scrollingDeltaY) * sensitivity
            cameraZ = max(minCameraZ, min(maxCameraZ, cameraZ / max(0.01, factor)))
            return event
        }

        let magnify = NSEvent.addLocalMonitorForEvents(matching: .magnify) { [self] event in
            guard isHovered else { return event }
            // magnification > 0 = pinch out = zoom in = camera moves closer
            let factor = Float(1.0 + event.magnification)
            cameraZ = max(minCameraZ, min(maxCameraZ, cameraZ / max(0.01, factor)))
            return event
        }

        let mouse = NSEvent.addLocalMonitorForEvents(
            matching: [.leftMouseDown, .leftMouseDragged, .leftMouseUp]
        ) { [self] event in
            switch event.type {
            case .leftMouseDown:
                if isHovered {
                    drag.active    = true
                    drag.lastPoint = NSEvent.mouseLocation
                }
            case .leftMouseDragged where drag.active:
                let loc = NSEvent.mouseLocation
                let dx  =  Float(loc.x - drag.lastPoint.x) * 0.005
                // Screen Y grows upward; dragging down should pitch down, so negate.
                let dy  = -Float(loc.y - drag.lastPoint.y) * 0.005
                drag.lastPoint = loc
                yaw   += dx
                pitch  = max(-.pi / 2 + 0.05, min(.pi / 2 - 0.05, pitch + dy))
            case .leftMouseUp:
                drag.active = false
            default:
                break
            }
            return event
        }

        monitors = [scroll, magnify, mouse].compactMap { $0 }
    }

    private func removeMonitors() {
        monitors.forEach { NSEvent.removeMonitor($0) }
        monitors = []
    }

    // MARK: - Environment loading

    /// Generates the nebula CGImage, converts it to a skybox TextureResource and an
    /// EnvironmentResource for IBL. Both drive the scene: the TextureResource is applied
    /// to the skybox sphere geometry; the EnvironmentResource provides image-based lighting
    /// so the ship's PBR material picks up ambient color from the space environment.
    private func loadEnvironment() async {
        let preset = lightingPreset
        let genTask = Task.detached(priority: .utility) {
            ShipRealityKitView.makeNebulaImage(for: preset)
        }
        guard let img = await genTask.value else { return }

        skyboxTex   = await cgImageToTexture(img)
        envResource = try? await EnvironmentResource(equirectangular: img, withName: nil)
    }

    // MARK: - Procedural nebula generator

    /// Generates a 2048×1024 equirectangular nebula image tuned to each lighting preset.
    /// Called on a background thread; uses only CoreGraphics (thread-safe for isolated contexts).
    nonisolated static func makeNebulaImage(for preset: LightingPreset) -> CGImage? {
        let W = 2048, H = 1024
        let cs = CGColorSpaceCreateDeviceRGB()
        guard let ctx = CGContext(
            data: nil, width: W, height: H,
            bitsPerComponent: 8, bytesPerRow: W * 4,
            space: cs, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        let FW = CGFloat(W), FH = CGFloat(H)

        struct Blob {
            let cx, cy, radius: CGFloat
            let r, g, b, alpha: CGFloat
            // Emission hot spots use a steeper gradient falloff to simulate ionised gas regions.
            var isHotSpot: Bool = false
        }

        let (baseR, baseG, baseB): (CGFloat, CGFloat, CGFloat)
        let blobs: [Blob]
        let starCount: Int
        let warmBias: CGFloat

        switch preset {
        case .deepSpace:  // Caldari — cold industrial blue
            (baseR, baseG, baseB) = (0.003, 0.005, 0.015)
            blobs = [
                // Wide atmospheric haze
                Blob(cx: 0.50, cy: 0.50, radius: 0.95, r: 0.02, g: 0.05, b: 0.18, alpha: 0.20),
                // Main nebula arms
                Blob(cx: 0.62, cy: 0.46, radius: 0.60, r: 0.04, g: 0.14, b: 0.45, alpha: 0.38),
                Blob(cx: 0.20, cy: 0.60, radius: 0.46, r: 0.02, g: 0.18, b: 0.32, alpha: 0.32),
                Blob(cx: 0.82, cy: 0.32, radius: 0.42, r: 0.05, g: 0.10, b: 0.28, alpha: 0.28),
                // Dense cores
                Blob(cx: 0.48, cy: 0.44, radius: 0.30, r: 0.02, g: 0.08, b: 0.30, alpha: 0.35),
                Blob(cx: 0.35, cy: 0.68, radius: 0.24, r: 0.02, g: 0.22, b: 0.38, alpha: 0.30),
                // Emission hot spots
                Blob(cx: 0.58, cy: 0.46, radius: 0.07, r: 0.12, g: 0.45, b: 1.00, alpha: 0.72, isHotSpot: true),
                Blob(cx: 0.24, cy: 0.54, radius: 0.05, r: 0.08, g: 0.65, b: 0.85, alpha: 0.65, isHotSpot: true),
                Blob(cx: 0.78, cy: 0.36, radius: 0.06, r: 0.15, g: 0.35, b: 0.75, alpha: 0.60, isHotSpot: true),
            ]
            starCount = 14000; warmBias = 0.10

        case .hangar:  // Amarr — warm ancient gold
            (baseR, baseG, baseB) = (0.018, 0.008, 0.002)
            blobs = [
                Blob(cx: 0.50, cy: 0.50, radius: 0.90, r: 0.28, g: 0.13, b: 0.02, alpha: 0.18),
                Blob(cx: 0.56, cy: 0.46, radius: 0.58, r: 0.50, g: 0.25, b: 0.05, alpha: 0.38),
                Blob(cx: 0.28, cy: 0.62, radius: 0.44, r: 0.32, g: 0.15, b: 0.02, alpha: 0.32),
                Blob(cx: 0.74, cy: 0.66, radius: 0.34, r: 0.24, g: 0.14, b: 0.02, alpha: 0.28),
                Blob(cx: 0.42, cy: 0.36, radius: 0.26, r: 0.18, g: 0.10, b: 0.01, alpha: 0.34),
                Blob(cx: 0.65, cy: 0.54, radius: 0.18, r: 0.40, g: 0.22, b: 0.04, alpha: 0.32),
                Blob(cx: 0.52, cy: 0.48, radius: 0.08, r: 1.00, g: 0.60, b: 0.10, alpha: 0.75, isHotSpot: true),
                Blob(cx: 0.38, cy: 0.60, radius: 0.06, r: 0.90, g: 0.45, b: 0.08, alpha: 0.68, isHotSpot: true),
                Blob(cx: 0.70, cy: 0.40, radius: 0.05, r: 0.80, g: 0.50, b: 0.12, alpha: 0.62, isHotSpot: true),
            ]
            starCount = 10000; warmBias = 0.80

        case .combat:  // Minmatar — blood-red, violent
            (baseR, baseG, baseB) = (0.014, 0.004, 0.002)
            blobs = [
                Blob(cx: 0.50, cy: 0.50, radius: 0.92, r: 0.22, g: 0.04, b: 0.01, alpha: 0.18),
                Blob(cx: 0.42, cy: 0.48, radius: 0.62, r: 0.38, g: 0.08, b: 0.01, alpha: 0.38),
                Blob(cx: 0.70, cy: 0.38, radius: 0.46, r: 0.26, g: 0.05, b: 0.00, alpha: 0.32),
                Blob(cx: 0.22, cy: 0.64, radius: 0.40, r: 0.28, g: 0.08, b: 0.01, alpha: 0.28),
                Blob(cx: 0.56, cy: 0.54, radius: 0.26, r: 0.16, g: 0.05, b: 0.01, alpha: 0.35),
                Blob(cx: 0.35, cy: 0.42, radius: 0.20, r: 0.20, g: 0.07, b: 0.01, alpha: 0.32),
                Blob(cx: 0.44, cy: 0.46, radius: 0.09, r: 1.00, g: 0.25, b: 0.02, alpha: 0.78, isHotSpot: true),
                Blob(cx: 0.67, cy: 0.40, radius: 0.07, r: 0.90, g: 0.35, b: 0.04, alpha: 0.70, isHotSpot: true),
                Blob(cx: 0.28, cy: 0.58, radius: 0.06, r: 0.80, g: 0.18, b: 0.02, alpha: 0.65, isHotSpot: true),
            ]
            starCount = 12000; warmBias = 0.58

        case .wormhole:  // J-space — alien violet, eerie teal wisps
            (baseR, baseG, baseB) = (0.006, 0.002, 0.020)
            blobs = [
                Blob(cx: 0.50, cy: 0.50, radius: 0.95, r: 0.12, g: 0.03, b: 0.32, alpha: 0.20),
                Blob(cx: 0.52, cy: 0.50, radius: 0.65, r: 0.25, g: 0.06, b: 0.60, alpha: 0.38),
                Blob(cx: 0.24, cy: 0.56, radius: 0.50, r: 0.04, g: 0.34, b: 0.30, alpha: 0.32),
                Blob(cx: 0.78, cy: 0.60, radius: 0.44, r: 0.16, g: 0.05, b: 0.50, alpha: 0.28),
                Blob(cx: 0.38, cy: 0.38, radius: 0.28, r: 0.03, g: 0.40, b: 0.32, alpha: 0.35),
                Blob(cx: 0.68, cy: 0.44, radius: 0.22, r: 0.06, g: 0.28, b: 0.24, alpha: 0.30),
                Blob(cx: 0.50, cy: 0.48, radius: 0.10, r: 0.50, g: 0.18, b: 1.00, alpha: 0.75, isHotSpot: true),
                Blob(cx: 0.30, cy: 0.54, radius: 0.07, r: 0.05, g: 0.90, b: 0.70, alpha: 0.70, isHotSpot: true),
                Blob(cx: 0.74, cy: 0.46, radius: 0.08, r: 0.40, g: 0.12, b: 0.85, alpha: 0.68, isHotSpot: true),
            ]
            starCount = 16000; warmBias = 0.05
        }

        // 1. Base fill
        ctx.setFillColor(CGColor(colorSpace: cs, components: [baseR, baseG, baseB, 1])!)
        ctx.fill(CGRect(x: 0, y: 0, width: W, height: H))

        // 2. Nebula blobs — layered radial gradients.
        //    Structural blobs have a gradual falloff (visible out to 55% radius).
        //    Emission hot spots fall off steeply, simulating ionised gas pockets.
        for b in blobs {
            let center   = CGPoint(x: FW * b.cx, y: FH * b.cy)
            let radius   = FW * b.radius
            let midStop: CGFloat  = b.isHotSpot ? 0.25 : 0.55
            let midAlpha: CGFloat = b.isHotSpot ? b.alpha * 0.80 : b.alpha * 0.45
            let midScale: CGFloat = b.isHotSpot ? 0.90 : 0.55
            guard let grad = CGGradient(
                colorsSpace: cs,
                colors: [
                    CGColor(colorSpace: cs, components: [b.r, b.g, b.b, b.alpha])!,
                    CGColor(colorSpace: cs, components: [b.r * midScale, b.g * midScale,
                                                         b.b * midScale, midAlpha])!,
                    CGColor(colorSpace: cs, components: [0, 0, 0, 0])!,
                ] as CFArray,
                locations: [0.0, midStop, 1.0]
            ) else { continue }
            ctx.drawRadialGradient(grad, startCenter: center, startRadius: 0,
                                   endCenter: center, endRadius: radius,
                                   options: .drawsAfterEndLocation)
        }

        // 3. Milky Way band — a horizontal elliptical glow compressed along the equator,
        //    produced by squashing a radial gradient via a CTM scale transform.
        ctx.saveGState()
        ctx.translateBy(x: FW * 0.5, y: FH * 0.5)
        ctx.scaleBy(x: 1.0, y: 0.14)
        if let mwGrad = CGGradient(
            colorsSpace: cs,
            colors: [
                CGColor(colorSpace: cs, components: [0.08, 0.09, 0.12, 0.38])!,
                CGColor(colorSpace: cs, components: [0.04, 0.04, 0.06, 0.16])!,
                CGColor(colorSpace: cs, components: [0,    0,    0,    0   ])!,
            ] as CFArray,
            locations: [0.0, 0.45, 1.0]
        ) {
            ctx.drawRadialGradient(mwGrad, startCenter: .zero, startRadius: 0,
                                   endCenter: .zero, endRadius: FW * 0.58,
                                   options: .drawsAfterEndLocation)
        }
        ctx.restoreGState()

        // 4. Stars — power-law brightness distribution, preset-tuned spectral mix
        for _ in 0 ..< starCount {
            let sx  = CGFloat.random(in: 0 ..< FW)
            let sy  = CGFloat.random(in: 0 ..< FH)
            let lum = pow(CGFloat.random(in: 0...1), 2.4)   // steep curve: mostly dim
            let vis = 0.35 + lum * 0.65

            let t = CGFloat.random(in: 0...1)
            let (r, g, b): (CGFloat, CGFloat, CGFloat)
            if t < warmBias {
                (r, g, b) = t < warmBias * 0.55
                    ? (vis, vis * 0.75, vis * 0.50)   // orange
                    : (vis, vis * 0.90, vis * 0.74)   // yellow-white
            } else {
                let t2 = (t - warmBias) / max(0.001, 1 - warmBias)
                (r, g, b) = t2 < 0.55
                    ? (vis, vis, vis)                   // white
                    : (vis * 0.80, vis * 0.88, vis)     // blue-white
            }

            let sz: CGFloat = lum < 0.50 ? 1.0 : lum < 0.80 ? 1.5 : 2.0
            ctx.setFillColor(CGColor(colorSpace: cs, components: [r, g, b, 1])!)
            ctx.fillEllipse(in: CGRect(x: sx - sz/2, y: sy - sz/2, width: sz, height: sz))

            if lum > 0.90 {
                // Soft diffuse glow around bright stars
                let gr = sz * 4.5
                ctx.setFillColor(CGColor(colorSpace: cs, components: [r, g, b, 0.06])!)
                ctx.fillEllipse(in: CGRect(x: sx - gr/2, y: sy - gr/2, width: gr, height: gr))
            }
        }

        // 5. Bright foreground stars — a handful of prominent nearby stars with layered halos,
        //    placed at fixed positions so the skybox has stable landmarks.
        let fgPositions: [(CGFloat, CGFloat)] = [
            (0.12, 0.22), (0.88, 0.18), (0.05, 0.72), (0.93, 0.76),
            (0.48, 0.08), (0.55, 0.91), (0.30, 0.14), (0.72, 0.86),
        ]
        for (fx, fy) in fgPositions {
            let sx = FW * fx, sy = FH * fy
            ctx.setFillColor(CGColor(colorSpace: cs, components: [0.9, 0.9, 1.0, 0.04])!)
            ctx.fillEllipse(in: CGRect(x: sx - 22, y: sy - 22, width: 44, height: 44))
            ctx.setFillColor(CGColor(colorSpace: cs, components: [1.0, 1.0, 1.0, 0.14])!)
            ctx.fillEllipse(in: CGRect(x: sx - 7,  y: sy - 7,  width: 14, height: 14))
            ctx.setFillColor(CGColor(colorSpace: cs, components: [1.0, 1.0, 1.0, 1.00])!)
            ctx.fillEllipse(in: CGRect(x: sx - 1.5, y: sy - 1.5, width: 3, height: 3))
        }

        return ctx.makeImage()
    }

    // MARK: Scene construction

    private func buildSceneEntities() -> [Entity] {
        var entities: [Entity] = []

        // Lights
        let key  = Entity(); key.name  = "key";  scene.keyLight  = key;  entities.append(key)
        let fill = Entity(); fill.name = "fill"; scene.fillLight  = fill; entities.append(fill)
        let rim  = Entity(); rim.name  = "rim";  scene.rimLight   = rim;  entities.append(rim)
        applyPreset(lightingPreset)
        applied.preset = lightingPreset

        // Camera — PerspectiveCameraComponent makes this entity the active camera
        let cam = Entity()
        cam.name = "shipCamera"
        var camComp = PerspectiveCameraComponent()
        camComp.fieldOfViewInDegrees = 40
        camComp.near = 0.01
        camComp.far  = 10000
        cam.components.set(camComp)
        cam.position = [0, 0, cameraZ]
        scene.camera = cam
        entities.append(cam)

        // Ship pivot — rotation is applied here so the camera stays still
        let pivot = Entity()
        pivot.name = "shipPivot"
        scene.pivot = pivot
        entities.append(pivot)

        // Geometry
        if let (mesh, shipRadius) = buildMesh(from: objURL) {
            let shipEntity = ModelEntity(mesh: mesh, materials: [defaultMaterial()])
            shipEntity.name = "shipModel"
            pivot.addChild(shipEntity)
            scene.ship = shipEntity
            cameraZ    = shipRadius * 2.5
            minCameraZ = shipRadius * 0.4
            maxCameraZ = shipRadius * 12.0
            cam.position = [0, 0, cameraZ]
        }

        // Skybox sphere — large enough to enclose the scene; rendered inside-out so
        // the texture is visible from inside. Not parented to the pivot so it stays
        // fixed while the ship rotates, matching EVE's fixed-sky/rotating-ship behaviour.
        let skyMesh = MeshResource.generateSphere(radius: 9000)
        var skyMat  = UnlitMaterial(color: .black)
        skyMat.faceCulling = .front
        let skyEntity = ModelEntity(mesh: skyMesh, materials: [skyMat])
        skyEntity.name = "skybox"
        scene.skybox = skyEntity
        entities.append(skyEntity)

        // IBL entity — receives ImageBasedLightComponent once the environment loads.
        let iblEnt = Entity()
        iblEnt.name = "ibl"
        scene.iblEntity = iblEnt
        entities.append(iblEnt)

        return entities
    }

    // MARK: Scene update (called by RealityView.update)

    private func updateScene() {
        // Orbit rotation applied to the pivot; camera stays at a fixed position.
        let q = simd_quatf(angle: yaw,   axis: [0, 1, 0]) *
                simd_quatf(angle: pitch, axis: [1, 0, 0])
        scene.pivot?.transform.rotation = q

        // Zoom — move the camera along Z (ship stays at origin)
        scene.camera?.position = [0, 0, cameraZ]

        // Lighting preset
        if lightingPreset != applied.preset {
            applied.preset = lightingPreset
            applyPreset(lightingPreset)
        }

        // Skybox sphere texture — updated whenever the environment loads for a new preset
        if skyboxTex !== applied.skyboxTex {
            applied.skyboxTex = skyboxTex
            if let tex = skyboxTex, let skybox = scene.skybox {
                var mat = UnlitMaterial()
                mat.color      = .init(texture: .init(tex))
                mat.faceCulling = .front
                if var model = skybox.model {
                    model.materials = [mat]
                    skybox.model = model
                }
            }
        }

        // IBL — once the EnvironmentResource is ready, wire it up so the ship's PBR
        // material receives ambient lighting from the space environment.
        if envResource !== applied.envRes {
            applied.envRes = envResource
            if let env = envResource, let iblEnt = scene.iblEntity {
                iblEnt.components.set(
                    ImageBasedLightComponent(source: .single(env),
                                            intensityExponent: 0.0)
                )
                scene.ship?.components.set(
                    ImageBasedLightReceiverComponent(imageBasedLight: iblEnt)
                )
            }
        }

        // Material — only when texture URLs actually change
        guard albedoDDSURL    != applied.albedo    ||
              normalDDSURL    != applied.normal    ||
              roughnessDDSURL != applied.roughness ||
              emissiveDDSURL  != applied.emissive  else { return }
        applied.albedo    = albedoDDSURL
        applied.normal    = normalDDSURL
        applied.roughness = roughnessDDSURL
        applied.emissive  = emissiveDDSURL
        applyMaterial()
    }

    // MARK: Async texture loading

    private func loadTextures() async {
        let device = MTLCreateSystemDefaultDevice()

        async let a = loadOneDDS(url: albedoDDSURL,    device: device, isNormal: false)
        async let n = loadOneDDS(url: normalDDSURL,    device: device, isNormal: true)
        async let e = loadOneDDS(url: emissiveDDSURL,  device: device, isNormal: false)
        albedoTex   = await a
        normalTex   = await n
        emissiveTex = await e

        // Packed roughness map — split R/G/B channels
        if let url = roughnessDDSURL,
           let data = try? Data(contentsOf: url),
           let dev  = device {
            var img: CGImage? = DDSDecoder.decode(data)
            if img == nil { img = DDSDecoder.cgImage(from: data, device: dev) }
            if let img {
                if let split = DDSDecoder.splitRoughnessChannels(from: img) {
                    roughTex = await cgImageToTexture(split.roughness)
                    metalTex = await cgImageToTexture(split.metalness)
                    aoTex    = await cgImageToTexture(split.ao)
                } else {
                    roughTex = await cgImageToTexture(img)
                }
            }
        }

        applyMaterial()
    }

    private func loadOneDDS(url: URL?, device: MTLDevice?, isNormal: Bool) async -> TextureResource? {
        guard let url, let data = try? Data(contentsOf: url), let dev = device else { return nil }
        var img: CGImage? = DDSDecoder.decode(data)
        if img == nil { img = DDSDecoder.cgImage(from: data, device: dev) }
        if isNormal && img == nil { img = DDSDecoder.cgImageNormal(from: data, device: dev) }
        guard let img else { return nil }
        return await cgImageToTexture(img)
    }

    /// Writes a CGImage to a temp PNG file and loads it as a TextureResource.
    /// This round-trip is the guaranteed-correct path; avoid caching the temp file.
    private func cgImageToTexture(_ image: CGImage) async -> TextureResource? {
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString + ".png")
        guard let dest = CGImageDestinationCreateWithURL(
            tmp as CFURL, UTType.png.identifier as CFString, 1, nil
        ) else { return nil }
        CGImageDestinationAddImage(dest, image, nil)
        guard CGImageDestinationFinalize(dest) else { return nil }
        defer { try? FileManager.default.removeItem(at: tmp) }
        return try? await TextureResource(contentsOf: tmp, withName: nil)
    }

    // MARK: Material

    private func defaultMaterial() -> PhysicallyBasedMaterial {
        var mat = PhysicallyBasedMaterial()
        mat.baseColor = .init(tint: NSColor(calibratedRed: 0.55, green: 0.58, blue: 0.62, alpha: 1))
        mat.roughness = .init(floatLiteral: 0.75)
        mat.metallic  = .init(floatLiteral: 0.30)
        return mat
    }

    private func applyMaterial() {
        guard let ship = scene.ship else { return }
        var mat = PhysicallyBasedMaterial()
        if let t = albedoTex   { mat.baseColor       = .init(texture: .init(t)) }
        else                   { mat.baseColor       = .init(tint: NSColor(calibratedRed: 0.55, green: 0.58, blue: 0.62, alpha: 1)) }
        if let t = normalTex   { mat.normal          = .init(texture: .init(t)) }
        if let t = roughTex    { mat.roughness       = .init(texture: .init(t)) }
        else                   { mat.roughness       = .init(floatLiteral: 0.75) }
        if let t = metalTex    { mat.metallic        = .init(texture: .init(t)) }
        else                   { mat.metallic        = .init(floatLiteral: 0.30) }
        if let t = aoTex       { mat.ambientOcclusion = .init(texture: .init(t)) }
        if let t = emissiveTex { mat.emissiveColor   = .init(texture: .init(t))
                                 mat.emissiveIntensity = 1.0 }
        if var model = ship.model {
            model.materials = [mat]
            ship.model = model
        }
    }

    // MARK: Geometry

    private func buildMesh(from url: URL) -> (MeshResource, Float)? {
        let asset = MDLAsset(url: url, vertexDescriptor: nil, bufferAllocator: nil)
        var meshes: [MDLMesh] = []
        func collect(_ obj: MDLObject) {
            if let m = obj as? MDLMesh { meshes.append(m) }
            obj.children.objects.forEach { collect($0) }
        }
        for i in 0..<asset.count { collect(asset.object(at: i)) }
        guard !meshes.isEmpty else { return nil }

        // Global bounding box — needed for stable outward-normal reference
        var gMin = SIMD3<Float>(repeating:  Float.infinity)
        var gMax = SIMD3<Float>(repeating: -Float.infinity)
        for m in meshes {
            let bb = m.boundingBox
            gMin = min(gMin, SIMD3<Float>(bb.minBounds.x, bb.minBounds.y, bb.minBounds.z))
            gMax = max(gMax, SIMD3<Float>(bb.maxBounds.x, bb.maxBounds.y, bb.maxBounds.z))
        }
        let centre  = (gMin + gMax) * 0.5
        let extent  = gMax - gMin
        let maxExt  = max(extent.x, max(extent.y, extent.z))
        let tpScale = maxExt > 0 ? Float(1.0 / maxExt) : 0.001

        var descriptors: [MeshDescriptor] = []
        for m in meshes {
            m.addNormals(withAttributeNamed: MDLVertexAttributeNormal, creaseThreshold: 0.5)
            fixNormals(in: m, centre: centre)
            if let desc = makeDescriptor(from: m, tpScale: tpScale) {
                descriptors.append(desc)
            }
        }
        guard !descriptors.isEmpty,
              let mesh = try? MeshResource.generate(from: descriptors)
        else { return nil }

        return (mesh, Float(maxExt * 0.5))
    }

    /// Negates any vertex normal whose dot product with the outward direction is negative.
    private func fixNormals(in mesh: MDLMesh, centre: SIMD3<Float>) {
        guard let normData = mesh.vertexAttributeData(forAttributeNamed: MDLVertexAttributeNormal),
              let posData  = mesh.vertexAttributeData(forAttributeNamed: MDLVertexAttributePosition)
        else { return }
        for i in 0..<mesh.vertexCount {
            let pBase = posData.dataStart.advanced(by:  i * posData.stride)
            let nBase = normData.dataStart.advanced(by: i * normData.stride)
            let pos = SIMD3<Float>(pBase.load(fromByteOffset: 0, as: Float.self),
                                   pBase.load(fromByteOffset: 4, as: Float.self),
                                   pBase.load(fromByteOffset: 8, as: Float.self))
            let n   = SIMD3<Float>(nBase.load(fromByteOffset: 0, as: Float.self),
                                   nBase.load(fromByteOffset: 4, as: Float.self),
                                   nBase.load(fromByteOffset: 8, as: Float.self))
            let olen = simd_length(pos - centre)
            guard olen > 1e-3 else { continue }
            if dot(n, pos - centre) < 0 {
                nBase.storeBytes(of: -n.x, toByteOffset: 0, as: Float.self)
                nBase.storeBytes(of: -n.y, toByteOffset: 4, as: Float.self)
                nBase.storeBytes(of: -n.z, toByteOffset: 8, as: Float.self)
            }
        }
    }

    /// Builds a MeshDescriptor from an MDLMesh, generating dominant-axis UV projection.
    private func makeDescriptor(from mesh: MDLMesh, tpScale: Float) -> MeshDescriptor? {
        guard let posAttr  = mesh.vertexAttributeData(forAttributeNamed: MDLVertexAttributePosition),
              let normAttr = mesh.vertexAttributeData(forAttributeNamed: MDLVertexAttributeNormal),
              let submeshes = mesh.submeshes, submeshes.count > 0
        else { return nil }

        let count = mesh.vertexCount
        var positions: [SIMD3<Float>] = []; positions.reserveCapacity(count)
        var normals:   [SIMD3<Float>] = []; normals.reserveCapacity(count)
        var uvs:       [SIMD2<Float>] = []; uvs.reserveCapacity(count)

        for i in 0..<count {
            let p  = posAttr.dataStart.advanced(by: i * posAttr.stride)
            let n  = normAttr.dataStart.advanced(by: i * normAttr.stride)
            let px = p.load(fromByteOffset: 0, as: Float.self)
            let py = p.load(fromByteOffset: 4, as: Float.self)
            let pz = p.load(fromByteOffset: 8, as: Float.self)
            let nx = n.load(fromByteOffset: 0, as: Float.self)
            let ny = n.load(fromByteOffset: 4, as: Float.self)
            let nz = n.load(fromByteOffset: 8, as: Float.self)
            positions.append([px, py, pz])
            normals.append([nx, ny, nz])
            // Dominant-axis UV projection — same logic as former SceneKit path
            let ax = abs(nx), ay = abs(ny), az = abs(nz)
            if ax >= ay && ax >= az {
                uvs.append([ pz * tpScale, -py * tpScale])
            } else if ay >= ax && ay >= az {
                uvs.append([ px * tpScale, -pz * tpScale])
            } else {
                uvs.append([ px * tpScale, -py * tpScale])
            }
        }

        var indices: [UInt32] = []
        for case let sub as MDLSubmesh in submeshes {
            guard sub.geometryType == .triangles, sub.indexCount > 0 else { continue }
            let map = sub.indexBuffer.map()
            switch sub.indexType {
            case .uint32:
                let ptr = map.bytes.bindMemory(to: UInt32.self, capacity: sub.indexCount)
                indices.append(contentsOf: UnsafeBufferPointer(start: ptr, count: sub.indexCount))
            case .uint16:
                let ptr = map.bytes.bindMemory(to: UInt16.self, capacity: sub.indexCount)
                indices.append(contentsOf: UnsafeBufferPointer(start: ptr, count: sub.indexCount).map { UInt32($0) })
            case .uint8:
                let ptr = map.bytes.bindMemory(to: UInt8.self, capacity: sub.indexCount)
                indices.append(contentsOf: UnsafeBufferPointer(start: ptr, count: sub.indexCount).map { UInt32($0) })
            default:
                continue
            }
        }
        guard !indices.isEmpty else { return nil }

        var desc = MeshDescriptor(name: mesh.name)
        desc.positions          = MeshBuffer(positions)
        desc.normals            = MeshBuffer(normals)
        desc.textureCoordinates = MeshBuffer(uvs)
        desc.primitives         = .triangles(indices)
        return desc
    }

    // MARK: Lighting

    private func applyPreset(_ preset: LightingPreset) {
        guard let key  = scene.keyLight,
              let fill = scene.fillLight,
              let rim  = scene.rimLight else { return }
        switch preset {
        case .deepSpace:
            setLight(key,  intensity: 3000, color: .white,
                     euler: (-0.7,  0.8))
            setLight(fill, intensity:  900, color: NSColor(calibratedRed: 0.35, green: 0.45, blue: 0.75, alpha: 1),
                     euler: ( 0.5, -1.1))
            setLight(rim,  intensity:  500, color: NSColor(calibratedRed: 0.40, green: 0.50, blue: 0.90, alpha: 1),
                     euler: ( 0.3, -2.34))
        case .hangar:
            setLight(key,  intensity: 3500, color: NSColor(calibratedRed: 1.00, green: 0.92, blue: 0.78, alpha: 1),
                     euler: (-1.2,  0.3))
            setLight(fill, intensity: 1200, color: NSColor(calibratedRed: 0.72, green: 0.68, blue: 0.62, alpha: 1),
                     euler: ( 0.4, -0.8))
            setLight(rim,  intensity:  500, color: NSColor(calibratedRed: 0.80, green: 0.75, blue: 0.68, alpha: 1),
                     euler: ( 0.3, -2.7))
        case .combat:
            setLight(key,  intensity: 2800, color: NSColor(calibratedRed: 1.00, green: 0.35, blue: 0.15, alpha: 1),
                     euler: (-0.5,  0.9))
            setLight(fill, intensity:  500, color: NSColor(calibratedRed: 0.40, green: 0.12, blue: 0.05, alpha: 1),
                     euler: ( 0.6, -1.0))
            setLight(rim,  intensity:  200, color: NSColor(calibratedRed: 0.60, green: 0.10, blue: 0.05, alpha: 1),
                     euler: ( 0.4, -2.5))
        case .wormhole:
            setLight(key,  intensity: 1800, color: NSColor(calibratedRed: 0.90, green: 0.80, blue: 1.00, alpha: 1),
                     euler: (-0.5,  1.2))
            setLight(fill, intensity: 1500, color: NSColor(calibratedRed: 0.10, green: 0.85, blue: 0.75, alpha: 1),
                     euler: ( 0.4, -0.9))
            setLight(rim,  intensity:  450, color: NSColor(calibratedRed: 0.70, green: 0.50, blue: 1.00, alpha: 1),
                     euler: ( 0.2, -2.6))
        }
    }

    private func setLight(_ entity: Entity, intensity: Float, color: NSColor,
                          euler: (Float, Float)) {
        var comp = DirectionalLightComponent()
        comp.intensity = intensity
        comp.color     = color
        entity.components.set(comp)
        entity.orientation = simd_quatf(angle: euler.0, axis: [1, 0, 0]) *
                             simd_quatf(angle: euler.1, axis: [0, 1, 0])
    }
}

// MARK: - Ship Model Sheet

struct ShipModelSheet: View {
    let shipName:  String
    var shipClass: String = ""
    @Environment(\.dismiss) private var dismiss

    @State private var phase:          Phase          = .loading
    @State private var lightingPreset: LightingPreset = .deepSpace
    @State private var wireframe:      Bool           = false

    private struct ReadyPayload {
        let objURL:          URL
        var albedoURL:       URL?
        var normalURL:       URL?
        var roughURL:        URL?
        var emissiveURL:     URL?
        var warning:         String?
        var texturesLoading: Bool = false
    }

    private enum Phase {
        case loading
        case ready(ReadyPayload)
        case unavailable
        case failed(String)
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            content
        }
        .frame(minWidth: 680, idealWidth: 800, maxWidth: .infinity,
               minHeight: 520, idealHeight: 600, maxHeight: .infinity)
        .background(Color(.windowBackgroundColor))
        .task { await load() }
    }

    // MARK: Header

    private var header: some View {
        HStack(spacing: 10) {
            Image(systemName: "cube.transparent").foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 1) {
                Text(shipName).font(.headline)
                Text("3D Ship Model").font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            if case .ready = phase {
                Picker("", selection: $lightingPreset) {
                    ForEach(LightingPreset.allCases) { preset in
                        Text(preset.title).tag(preset)
                    }
                }
                .pickerStyle(.menu)
                .labelsHidden()
                .frame(width: 120)

                Button {
                    WindowService.shared.showShipModel(shipName: shipName, shipClass: shipClass)
                    dismiss()
                } label: {
                    Image(systemName: "arrow.up.left.and.arrow.down.right")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("Open in dedicated window")
            }
            Spacer()
            Button { dismiss() } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.title2).foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .keyboardShortcut(.cancelAction)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    // MARK: Content

    @ViewBuilder
    private var content: some View {
        switch phase {
        case .loading:
            VStack(spacing: 14) {
                ProgressView()
                Text("Fetching model…").font(.subheadline).foregroundStyle(.secondary)
                Text("Downloads are cached after the first view")
                    .font(.caption).foregroundStyle(.tertiary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

        case .ready(let p):
            ShipRealityKitView(
                objURL:          p.objURL,
                albedoDDSURL:    p.albedoURL,
                normalDDSURL:    p.normalURL,
                roughnessDDSURL: p.roughURL,
                emissiveDDSURL:  p.emissiveURL,
                lightingPreset:  lightingPreset,
                wireframe:       wireframe
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .overlay(alignment: .topLeading) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(shipName).font(.headline.bold()).foregroundStyle(.white)
                    if !shipClass.isEmpty {
                        Text(shipClass).font(.caption).foregroundStyle(.white.opacity(0.65))
                    }
                }
                .padding(.horizontal, 10).padding(.vertical, 8)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 8))
                .padding(12)
            }
            .overlay(alignment: .bottom) {
                VStack(spacing: 4) {
                    if p.texturesLoading {
                        HStack(spacing: 6) {
                            ProgressView().scaleEffect(0.7)
                            Text("Loading textures…")
                                .font(.caption2).foregroundStyle(.white.opacity(0.55))
                        }
                        .padding(.horizontal, 10).padding(.vertical, 5)
                        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 8))
                    }
                    if let warning = p.warning {
                        Label(warning, systemImage: "exclamationmark.triangle.fill")
                            .font(.caption2)
                            .foregroundStyle(.orange)
                            .padding(.horizontal, 10).padding(.vertical, 5)
                            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 8))
                    }
                    Text("Drag to rotate  ·  Scroll to zoom  ·  Pinch to zoom")
                        .font(.caption2)
                        .foregroundStyle(.white.opacity(0.35))
                }
                .padding(.bottom, 10)
            }

        case .unavailable:
            VStack(spacing: 14) {
                Image(systemName: "cube.transparent")
                    .font(.system(size: 44)).foregroundStyle(.tertiary)
                Text("No 3D model available")
                    .font(.title3.bold()).foregroundStyle(.secondary)
                Text("This ship doesn't have a model in the community library yet.")
                    .font(.subheadline).foregroundStyle(.tertiary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

        case .failed(let msg):
            VStack(spacing: 14) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 44)).foregroundStyle(.orange)
                Text("Could not load model").font(.title3.bold())
                Text(msg).font(.caption).foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    // MARK: Load

    private func load() async {
        do {
            guard let objURL = try await ShipModelService.shared.modelURL(for: shipName) else {
                phase = .unavailable
                return
            }
            phase = .ready(ReadyPayload(objURL: objURL, texturesLoading: true))

            var albedoURL: URL?
            var warning:   String?
            do    { albedoURL = try await ShipModelService.shared.localAlbedoURL(for: shipName) }
            catch { warning = error.localizedDescription }

            if case .ready(var p) = phase {
                p.albedoURL = albedoURL
                p.warning   = warning
                phase = .ready(p)
            }

            async let normalFetch   = ShipModelService.shared.localNormalURL(for: shipName)
            async let roughFetch    = ShipModelService.shared.localRoughnessURL(for: shipName)
            async let emissiveFetch = ShipModelService.shared.localEmissiveURL(for: shipName)
            let normalURL   = try? await normalFetch
            let roughURL    = try? await roughFetch
            let emissiveURL = try? await emissiveFetch

            if case .ready(var p) = phase {
                p.normalURL       = normalURL
                p.roughURL        = roughURL
                p.emissiveURL     = emissiveURL
                p.texturesLoading = false
                phase = .ready(p)
            }
        } catch {
            phase = .failed(error.localizedDescription)
        }
    }
}
