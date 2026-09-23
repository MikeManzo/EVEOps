#!/usr/bin/env swift
//
// This file is part of EVEOps.
//
// EVEOps is free software: you can redistribute it and/or modify
// it under the terms of the GNU General Public License as published by
// the Free Software Foundation, version 3 or later.
//
// Copyright (c) 2026 CitizenCoder
//
// Renders the glyph app icon: a procedural spiral nebula in the original artwork's
// palette, with the EVEOps ship glyph — the same silhouette as the menu bar template
// icon — lit on top. Unlike the wordmark,
// the glyph stays legible down to 16 pt in the Dock, Finder lists and Spotlight.
//
// Usage: swift Scripts/make_app_icon.swift Scripts/icon/nebula-wordmark-1024.png EVEOps/Assets.xcassets/AppIcon.appiconset
// (The previous wordmark icon is kept at Scripts/icon/nebula-wordmark-1024.png.)

import AppKit
import CoreImage

let args = CommandLine.arguments
guard args.count == 3, let source = NSImage(contentsOfFile: args[1]),
      let sourceCG = source.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
    print("Usage: swift make_app_icon.swift <source-1024.png> <output-dir>")
    exit(1)
}
let outDir = args[2]

// Glyph geometry from EveOpsTemplate.svg (22×22 viewBox), kept in sync by hand.
func glyphPath(in rect: CGRect) -> CGPath {
    let s = rect.width / 22
    func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
        // SVG y grows downward; Core Graphics y grows upward.
        CGPoint(x: rect.minX + x * s, y: rect.maxY - y * s)
    }
    let path = CGMutablePath()
    // Hull
    path.move(to: p(11, 1.5))
    for (x, y) in [(13.5, 7), (14.5, 13), (13, 18.5), (12, 20.5), (10, 20.5), (9, 18.5), (7.5, 13), (8.5, 7)] {
        path.addLine(to: p(CGFloat(x), CGFloat(y)))
    }
    path.closeSubpath()
    // Wings
    path.move(to: p(7.5, 13)); path.addLine(to: p(1, 16)); path.addLine(to: p(2, 18.5)); path.addLine(to: p(9, 15.5)); path.closeSubpath()
    path.move(to: p(14.5, 13)); path.addLine(to: p(21, 16)); path.addLine(to: p(20, 18.5)); path.addLine(to: p(13, 15.5)); path.closeSubpath()
    return path
}

/// Cockpit cut-out (drawn as a separate inner diamond so it can glow).
func cockpitPath(in rect: CGRect) -> CGPath {
    let s = rect.width / 22
    func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: rect.minX + x * s, y: rect.maxY - y * s) }
    let path = CGMutablePath()
    path.move(to: p(11, 7.5)); path.addLine(to: p(12.5, 10)); path.addLine(to: p(11, 12)); path.addLine(to: p(9.5, 10)); path.closeSubpath()
    return path
}

// Procedural nebula background, rendered once at 1024 and downsampled per size: soft
// colour blobs in the original artwork's palette, twisted into a spiral, plus stars.
// (Blurring the original art left a grey smear where the wordmark was.)
let ci = CIContext()
struct SplitMix64 {
    var state: UInt64
    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
    mutating func unit() -> CGFloat { CGFloat(next() % 10_000) / 10_000 }
}
let blurred: CGImage = {
    let n = 1024
    let px = CGFloat(n)
    let cs = CGColorSpace(name: CGColorSpace.sRGB)!
    let ctx = CGContext(data: nil, width: n, height: n, bitsPerComponent: 8, bytesPerRow: 0,
                        space: cs, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.setFillColor(CGColor(red: 0.015, green: 0.02, blue: 0.07, alpha: 1))
    ctx.fill(CGRect(x: 0, y: 0, width: px, height: px))
    ctx.setBlendMode(.screen)
    // (x, y, radius, r, g, b, alpha) — unit coordinates, y up.
    let blobs: [(CGFloat, CGFloat, CGFloat, CGFloat, CGFloat, CGFloat, CGFloat)] = [
        (0.50, 0.50, 0.55, 0.10, 0.22, 0.70, 0.95),   // deep blue core
        (0.30, 0.64, 0.42, 0.20, 0.42, 1.00, 0.80),   // bright blue arm
        (0.72, 0.36, 0.40, 0.52, 0.20, 0.85, 0.75),   // violet arm
        (0.62, 0.72, 0.30, 0.80, 0.25, 0.60, 0.45),   // magenta wisp
        (0.30, 0.28, 0.30, 0.15, 0.70, 0.90, 0.45),   // teal wisp
        (0.50, 0.50, 0.16, 0.65, 0.85, 1.00, 0.55)    // hot centre
    ]
    for (x, y, r, cr, cg, cb, a) in blobs {
        let g = CGGradient(colorsSpace: cs, colors: [
            CGColor(red: cr, green: cg, blue: cb, alpha: a),
            CGColor(red: cr, green: cg, blue: cb, alpha: 0)
        ] as CFArray, locations: [0, 1])!
        let c = CGPoint(x: x * px, y: y * px)
        ctx.drawRadialGradient(g, startCenter: c, startRadius: 0, endCenter: c, endRadius: r * px, options: [])
    }
    let base = ctx.makeImage()!
    // Twist into a spiral, then soften.
    let twisted = CIImage(cgImage: base)
        .clampedToExtent()
        .applyingFilter("CITwirlDistortion", parameters: [
            kCIInputCenterKey: CIVector(x: px / 2, y: px / 2),
            kCIInputRadiusKey: px * 0.62,
            kCIInputAngleKey: 3.6
        ])
        .applyingGaussianBlur(sigma: 18)
        .cropped(to: CGRect(x: 0, y: 0, width: px, height: px))
    let nebula = ci.createCGImage(twisted, from: CGRect(x: 0, y: 0, width: px, height: px))!

    // Stars on top of the nebula.
    let out = CGContext(data: nil, width: n, height: n, bitsPerComponent: 8, bytesPerRow: 0,
                        space: cs, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    out.draw(nebula, in: CGRect(x: 0, y: 0, width: px, height: px))
    var rng = SplitMix64(state: 0xE7E0_95)
    for _ in 0..<220 {
        let x = rng.unit() * px, y = rng.unit() * px
        let r = 0.6 + rng.unit() * 1.8
        out.setFillColor(CGColor(gray: 1, alpha: 0.25 + rng.unit() * 0.6))
        out.fillEllipse(in: CGRect(x: x, y: y, width: r * 2, height: r * 2))
    }
    return out.makeImage()!
}()
_ = sourceCG  // the original art is no longer sampled; kept as an argument for provenance

func render(size: Int) -> Data {
    let px = CGFloat(size)
    let cs = CGColorSpace(name: CGColorSpace.sRGB)!
    let ctx = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0,
                        space: cs, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.interpolationQuality = .high
    let full = CGRect(x: 0, y: 0, width: px, height: px)

    // Background: procedural nebula.
    ctx.draw(blurred, in: full)

    // Vignette to seat the glyph.
    let vignette = CGGradient(colorsSpace: cs, colors: [
        CGColor(red: 0, green: 0, blue: 0, alpha: 0),
        CGColor(red: 0.02, green: 0.02, blue: 0.08, alpha: 0.65)
    ] as CFArray, locations: [0.35, 1])!
    ctx.drawRadialGradient(vignette, startCenter: CGPoint(x: px / 2, y: px / 2), startRadius: 0,
                           endCenter: CGPoint(x: px / 2, y: px / 2), endRadius: px * 0.72, options: [])

    // Glyph, centered, ~62% of the canvas.
    let g = px * 0.62
    let glyphRect = CGRect(x: (px - g) / 2, y: (px - g) / 2 - px * 0.01, width: g, height: g)
    let glyph = glyphPath(in: glyphRect)
    let teal = CGColor(red: 0.30, green: 0.85, blue: 0.95, alpha: 1)

    // Outer glow (skipped at the smallest sizes, where it only muddies the silhouette).
    if size >= 64 {
        ctx.saveGState()
        ctx.setShadow(offset: .zero, blur: px * 0.06, color: teal.copy(alpha: 0.85))
        ctx.addPath(glyph)
        ctx.setFillColor(CGColor(gray: 1, alpha: 1))
        ctx.fillPath(using: .evenOdd)
        ctx.restoreGState()
    }

    // Glyph body: top-lit white → pale teal.
    ctx.saveGState()
    ctx.addPath(glyph)
    ctx.clip(using: .evenOdd)
    let body = CGGradient(colorsSpace: cs, colors: [
        CGColor(red: 1, green: 1, blue: 1, alpha: 1),
        CGColor(red: 0.72, green: 0.93, blue: 1.0, alpha: 1)
    ] as CFArray, locations: [0, 1])!
    ctx.drawLinearGradient(body, start: CGPoint(x: 0, y: glyphRect.maxY), end: CGPoint(x: 0, y: glyphRect.minY), options: [])
    ctx.restoreGState()

    // Cockpit glow.
    ctx.saveGState()
    if size >= 64 { ctx.setShadow(offset: .zero, blur: px * 0.025, color: teal) }
    ctx.addPath(cockpitPath(in: glyphRect))
    ctx.setFillColor(teal)
    ctx.fillPath()
    ctx.restoreGState()

    let rep = NSBitmapImageRep(cgImage: ctx.makeImage()!)
    return rep.representation(using: .png, properties: [:])!
}

let sizes: [(String, Int)] = [
    ("icon_16x16.png", 16), ("icon_16x16@2x.png", 32),
    ("icon_32x32.png", 32), ("icon_32x32@2x.png", 64),
    ("icon_128x128.png", 128), ("icon_128x128@2x.png", 256),
    ("icon_256x256.png", 256), ("icon_256x256@2x.png", 512),
    ("icon_512x512.png", 512), ("icon_512x512@2x.png", 1024)
]
try FileManager.default.createDirectory(atPath: outDir, withIntermediateDirectories: true)
for (name, size) in sizes {
    try render(size: size).write(to: URL(fileURLWithPath: "\(outDir)/\(name)"))
}
print("Wrote \(sizes.count) icons to \(outDir)")
