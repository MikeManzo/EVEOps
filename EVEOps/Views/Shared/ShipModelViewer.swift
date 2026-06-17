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
import SceneKit

// MARK: Lighting Preset

enum LightingPreset: String, CaseIterable, Identifiable {
    case deepSpace = "Deep Space"
    case hangar    = "Hangar"
    case combat    = "Combat"
    var id: String { rawValue }
}

// MARK:  SceneKit View

/// Renders a ship .obj model in a SceneKit view with optional albedo texture.
///
/// Texture loading strategy:
///  1. MTKTextureLoader(URL:) — works for BC1/BC3 DDS (uses ModelIO under the hood).
///  2. DDSDecoder.rgbaTexture(from:device:) — fallback for BC7/DX10 DDS files.
///     MTKTextureLoader uses ImageIO which doesn't support BC7; instead we upload
///     the raw compressed blocks as an MTLTexture and transcode to RGBA8 via a
///     one-shot Metal render pass that Metal's GPU hardware can sample natively.
///
/// A triplanar GLSL shader projects the texture onto the geometry. Since the .obj
/// files from GetEveModels have no UV coordinates, triplanar projection uses model-
/// space position (recovered via u_inverseModelViewTransform) so the texture stays
/// locked to the hull as the camera orbits. Falls back to a PBR metallic material
/// when no texture is available.
struct ShipSceneKitView: NSViewRepresentable {
    let objURL:          URL
    var albedoDDSURL:    URL? = nil
    var normalDDSURL:    URL? = nil
    var roughnessDDSURL: URL? = nil
    var lightingPreset:  LightingPreset = .deepSpace

    func makeNSView(context: Context) -> SCNView {
        let v = SCNView()
        v.backgroundColor = NSColor(red: 0.01, green: 0.01, blue: 0.02, alpha: 1)
        v.allowsCameraControl = true
        v.autoenablesDefaultLighting = false
        v.antialiasingMode = .multisampling4X
        v.showsStatistics  = false

        if let scene = try? SCNScene(url: objURL, options: [.checkConsistency: false]) {
            addLighting(to: scene)
            scene.background.contents = makeStarfieldBackground()
            let mat = buildMaterial(for: scene)
            apply(mat, to: scene.rootNode)
            v.scene = scene
            v.defaultCameraController.interactionMode = .orbitTurntable
        }
        return v
    }

    func updateNSView(_ v: SCNView, context: Context) {
        guard let scene = v.scene else { return }
        applyLightingPreset(lightingPreset, to: scene)
    }

    // MARK: Lighting

    private func addLighting(to scene: SCNScene) {
        let key = SCNNode(); key.name = "keyLight"; key.light = SCNLight()
        key.light!.type = .directional
        scene.rootNode.addChildNode(key)

        let fill = SCNNode(); fill.name = "fillLight"; fill.light = SCNLight()
        fill.light!.type = .directional
        scene.rootNode.addChildNode(fill)

        let ambient = SCNNode(); ambient.name = "ambientLight"; ambient.light = SCNLight()
        ambient.light!.type = .ambient
        scene.rootNode.addChildNode(ambient)

        applyLightingPreset(lightingPreset, to: scene)
    }

    private func applyLightingPreset(_ preset: LightingPreset, to scene: SCNScene) {
        guard let keyNode = scene.rootNode.childNode(withName: "keyLight",     recursively: false),
              let fillNode = scene.rootNode.childNode(withName: "fillLight",   recursively: false),
              let ambNode  = scene.rootNode.childNode(withName: "ambientLight", recursively: false),
              let key = keyNode.light, let fill = fillNode.light, let amb = ambNode.light
        else { return }

        switch preset {
        case .deepSpace:
            key.intensity  = 900;  key.color  = NSColor.white
            keyNode.eulerAngles  = SCNVector3(-0.7,  0.8,  0)
            fill.intensity = 350;  fill.color = NSColor(calibratedRed: 0.35, green: 0.45, blue: 0.75, alpha: 1)
            fillNode.eulerAngles = SCNVector3( 0.5, -1.1,  0)
            amb.color = NSColor(calibratedWhite: 0.10, alpha: 1)

        case .hangar:
            key.intensity  = 1100; key.color  = NSColor(calibratedRed: 1.00, green: 0.92, blue: 0.78, alpha: 1)
            keyNode.eulerAngles  = SCNVector3(-1.2,  0.3,  0)
            fill.intensity = 450;  fill.color = NSColor(calibratedRed: 0.72, green: 0.68, blue: 0.62, alpha: 1)
            fillNode.eulerAngles = SCNVector3( 0.4, -0.8,  0)
            amb.color = NSColor(calibratedWhite: 0.18, alpha: 1)

        case .combat:
            key.intensity  = 900;  key.color  = NSColor(calibratedRed: 1.00, green: 0.35, blue: 0.15, alpha: 1)
            keyNode.eulerAngles  = SCNVector3(-0.5,  0.9,  0.2)
            fill.intensity = 200;  fill.color = NSColor(calibratedRed: 0.40, green: 0.12, blue: 0.05, alpha: 1)
            fillNode.eulerAngles = SCNVector3( 0.6, -1.0, -0.3)
            amb.color = NSColor(calibratedRed: 0.15, green: 0.02, blue: 0.02, alpha: 1)
        }
    }

    // MARK: Starfield

    /// Generates a 2048×1024 equirectangular star-field used as the scene skybox.
    /// Simple approach: uniform deep-black base + 5 500 stars with realistic spectral
    /// colours + a barely-visible centred depth glow. Centred-only gradients mean the
    /// equirectangular wrap seam is completely invisible.
    private func makeStarfieldBackground() -> CGImage? {
        let W = 2048, H = 1024
        let cs = CGColorSpaceCreateDeviceRGB()
        guard let ctx = CGContext(
            data: nil, width: W, height: H,
            bitsPerComponent: 8, bytesPerRow: W * 4,
            space: cs,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }

        let FW = CGFloat(W), FH = CGFloat(H)

        // ── 1. Pure deep-space black (very slight blue tint) ─────────────────────────
        ctx.setFillColor(CGColor(colorSpace: cs, components: [0.005, 0.006, 0.014, 1])!)
        ctx.fill(CGRect(x: 0, y: 0, width: W, height: H))

        // ── 2. One faint centred depth glow — symmetric so the wrap seam is invisible ─
        if let grad = CGGradient(
            colorsSpace: cs,
            colors: [CGColor(colorSpace: cs, components: [0.02, 0.03, 0.10, 0.14])!,
                     CGColor(colorSpace: cs, components: [0,    0,    0,    0   ])!] as CFArray,
            locations: [0, 1])
        {
            let c = CGPoint(x: FW * 0.5, y: FH * 0.5)
            ctx.drawRadialGradient(grad, startCenter: c, startRadius: 0,
                                   endCenter: c, endRadius: FW * 0.55,
                                   options: .drawsAfterEndLocation)
        }

        // ── 3. Stars ─────────────────────────────────────────────────────────────────
        for _ in 0 ..< 5500 {
            let sx  = CGFloat.random(in: 0 ..< FW)
            let sy  = CGFloat.random(in: 0 ..< FH)
            let lum = pow(CGFloat.random(in: 0...1), 2.4)  // steep power-law → mostly dim
            let vis = 0.35 + lum * 0.65

            let t = CGFloat.random(in: 0...1)
            let (r, g, b): (CGFloat, CGFloat, CGFloat)
            if      t < 0.55 { (r, g, b) = (vis,        vis,        vis       ) } // white
            else if t < 0.75 { (r, g, b) = (vis * 0.82, vis * 0.91, vis       ) } // blue-white
            else if t < 0.88 { (r, g, b) = (vis,        vis * 0.94, vis * 0.76) } // yellow-white
            else             { (r, g, b) = (vis,        vis * 0.72, vis * 0.50) } // orange

            let sz: CGFloat = lum < 0.50 ? 1.0 : lum < 0.80 ? 1.5 : 2.5

            ctx.setFillColor(CGColor(colorSpace: cs, components: [r, g, b, 1])!)
            ctx.fillEllipse(in: CGRect(x: sx - sz/2, y: sy - sz/2, width: sz, height: sz))

            // Very subtle bloom on only the very brightest stars
            if lum > 0.92 {
                ctx.setFillColor(CGColor(colorSpace: cs, components: [r, g, b, 0.04])!)
                let gr = sz * 3
                ctx.fillEllipse(in: CGRect(x: sx - gr/2, y: sy - gr/2, width: gr, height: gr))
            }
        }

        return ctx.makeImage()
    }

    // MARK: Material

    private func buildMaterial(for scene: SCNScene) -> SCNMaterial {
        let mat    = SCNMaterial()
        mat.lightingModel = .physicallyBased
        let device = MTLCreateSystemDefaultDevice()

        // Albedo (BC1/BC3 software path or BC7 Metal path)
        if let url = albedoDDSURL, let data = try? Data(contentsOf: url), let dev = device {
            var img: CGImage? = DDSDecoder.decode(data)
            if img == nil { img = DDSDecoder.cgImage(from: data, device: dev) }
            mat.diffuse.contents = img ?? NSColor(calibratedRed: 0.55, green: 0.58, blue: 0.62, alpha: 1)
        } else {
            mat.diffuse.contents = NSColor(calibratedRed: 0.55, green: 0.58, blue: 0.62, alpha: 1)
        }

        // Normal map (BC5/ATI2 → Z-reconstructed RGBA, or BC7/BC1 fallback)
        if let url = normalDDSURL, let data = try? Data(contentsOf: url), let dev = device {
            var img: CGImage? = DDSDecoder.decode(data)
            if img == nil { img = DDSDecoder.cgImage(from: data, device: dev) }
            if img == nil { img = DDSDecoder.cgImageNormal(from: data, device: dev) }
            if let img { mat.normal.contents = img }
        }

        // Roughness map (R channel = roughness; metalness from fixed value)
        if let url = roughnessDDSURL, let data = try? Data(contentsOf: url), let dev = device {
            var img: CGImage? = DDSDecoder.decode(data)
            if img == nil { img = DDSDecoder.cgImage(from: data, device: dev) }
            if let img {
                mat.roughness.contents = img
                mat.metalness.contents = NSNumber(value: 0.65)
            } else {
                mat.metalness.contents = NSNumber(value: 0.55)
                mat.roughness.contents = NSNumber(value: 0.45)
            }
        } else {
            mat.metalness.contents = NSNumber(value: 0.55)
            mat.roughness.contents = NSNumber(value: 0.45)
        }

        return mat
    }

    private func apply(_ mat: SCNMaterial, to node: SCNNode) {
        node.geometry?.materials = [mat]
        node.childNodes.forEach { apply(mat, to: $0) }
    }
}

// MARK:  Ship Model Sheet

struct ShipModelSheet: View {
    let shipName: String
    @Environment(\.dismiss) private var dismiss

    @State private var phase:          Phase          = .loading
    @State private var lightingPreset: LightingPreset = .deepSpace

    private struct ReadyPayload {
        let objURL:      URL
        let albedoURL:   URL?
        let normalURL:   URL?
        let roughURL:    URL?
        let warning:     String?
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
        .frame(width: 680, height: 560)
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
                        Text(preset.rawValue).tag(preset)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: 220)
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
            ZStack(alignment: .bottom) {
                ShipSceneKitView(
                    objURL:          p.objURL,
                    albedoDDSURL:    p.albedoURL,
                    normalDDSURL:    p.normalURL,
                    roughnessDDSURL: p.roughURL,
                    lightingPreset:  lightingPreset
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                VStack(spacing: 4) {
                    if let warning = p.warning {
                        Label(warning, systemImage: "exclamationmark.triangle.fill")
                            .font(.caption2)
                            .foregroundStyle(.orange)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 8))
                    }
                    Text("Drag to rotate  ·  Scroll to zoom  ·  ⌘-drag to pan")
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
            var albedoURL: URL?
            var normalURL: URL?
            var roughURL:  URL?
            var warning:   String?

            do    { albedoURL = try await ShipModelService.shared.localAlbedoURL(for: shipName) }
            catch { warning = error.localizedDescription }

            do    { normalURL = try await ShipModelService.shared.localNormalURL(for: shipName) }
            catch { }

            do    { roughURL = try await ShipModelService.shared.localRoughnessURL(for: shipName) }
            catch { }

            phase = .ready(ReadyPayload(
                objURL:    objURL,
                albedoURL: albedoURL,
                normalURL: normalURL,
                roughURL:  roughURL,
                warning:   warning
            ))
        } catch {
            phase = .failed(error.localizedDescription)
        }
    }
}
