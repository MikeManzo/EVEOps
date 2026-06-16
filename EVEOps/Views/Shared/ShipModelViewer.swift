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

// MARK: - SceneKit View

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
    let objURL:       URL
    var albedoDDSURL: URL? = nil

    func makeNSView(context: Context) -> SCNView {
        let v = SCNView()
        v.backgroundColor = NSColor(red: 0.04, green: 0.04, blue: 0.08, alpha: 1)
        v.allowsCameraControl = true
        v.autoenablesDefaultLighting = false
        v.antialiasingMode = .multisampling4X
        v.showsStatistics  = false

        if let scene = try? SCNScene(url: objURL, options: [.checkConsistency: false]) {
            addLighting(to: scene)
            let mat = buildMaterial(for: scene)
            apply(mat, to: scene.rootNode)
            v.scene = scene
            v.defaultCameraController.interactionMode = .orbitTurntable
        }
        return v
    }

    func updateNSView(_ v: SCNView, context: Context) {}

    // MARK: Lighting

    private func addLighting(to scene: SCNScene) {
        let key = SCNNode(); key.light = SCNLight()
        key.light!.type = .directional; key.light!.intensity = 900
        key.light!.color = NSColor.white
        key.eulerAngles = SCNVector3(-0.7, 0.8, 0)
        scene.rootNode.addChildNode(key)

        let fill = SCNNode(); fill.light = SCNLight()
        fill.light!.type = .directional; fill.light!.intensity = 350
        fill.light!.color = NSColor(calibratedRed: 0.35, green: 0.45, blue: 0.75, alpha: 1)
        fill.eulerAngles = SCNVector3(0.5, -1.1, 0)
        scene.rootNode.addChildNode(fill)

        let ambient = SCNNode(); ambient.light = SCNLight()
        ambient.light!.type = .ambient
        ambient.light!.color = NSColor(calibratedWhite: 0.1, alpha: 1)
        scene.rootNode.addChildNode(ambient)
    }

    // MARK: Material

    private func buildMaterial(for scene: SCNScene) -> SCNMaterial {
        let mat = SCNMaterial()
        mat.lightingModel = .physicallyBased

        if let ddsURL = albedoDDSURL,
           let ddsData = try? Data(contentsOf: ddsURL),
           let device  = MTLCreateSystemDefaultDevice() {

            // BC1/BC3: software CPU decode → CGImage
            // BC7/DX10: Metal render pass → CIContext readback → CGImage
            // CGImage (not MTLTexture) is required because SceneKit only auto-generates
            // the 'u_diffuseTexture' GLSL uniform for image-typed contents; MTLTexture
            // contents skip that step and the shader modifier can't find the sampler.
            var albedo: CGImage? = DDSDecoder.decode(ddsData)
            if albedo == nil {
                albedo = DDSDecoder.cgImage(from: ddsData, device: device)
            }

            if let img = albedo {
                // The .obj files from GetEveModels have UV coordinates, so the texture
                // maps correctly using SceneKit's standard diffuse channel — no shader
                // modifier needed. (Triplanar GLSL/MSL shader modifiers consistently
                // fail on modern SceneKit/Metal; the UV path looks correct anyway.)
                mat.diffuse.contents   = img
                mat.metalness.contents = NSNumber(value: 0.55)
                mat.roughness.contents = NSNumber(value: 0.45)
                return mat
            }
        }

        // Fallback: flat metallic grey
        mat.diffuse.contents   = NSColor(calibratedRed: 0.55, green: 0.58, blue: 0.62, alpha: 1)
        mat.metalness.contents = NSNumber(value: 0.75)
        mat.roughness.contents = NSNumber(value: 0.35)
        return mat
    }

    private func apply(_ mat: SCNMaterial, to node: SCNNode) {
        node.geometry?.materials = [mat]
        node.childNodes.forEach { apply(mat, to: $0) }
    }
}

// MARK: - Ship Model Sheet

struct ShipModelSheet: View {
    let shipName: String
    @Environment(\.dismiss) private var dismiss

    @State private var phase: Phase = .loading

    private enum Phase {
        case loading
        case ready(URL, URL?, String?)  // obj URL, DDS file URL, optional texture warning
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

        case .ready(let url, let ddsURL, let textureWarning):
            ZStack(alignment: .bottom) {
                ShipSceneKitView(objURL: url, albedoDDSURL: ddsURL)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                VStack(spacing: 4) {
                    if let warning = textureWarning {
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
            do {
                let ddsURL = try await ShipModelService.shared.localAlbedoURL(for: shipName)
                phase = .ready(objURL, ddsURL, nil)
            } catch {
                phase = .ready(objURL, nil, error.localizedDescription)
            }
        } catch {
            phase = .failed(error.localizedDescription)
        }
    }
}
