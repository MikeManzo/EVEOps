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
// Renders the installer DMG's Finder-window background: a deep-space gradient with a
// deterministic starfield, a drag arrow between the app and Applications icon slots, and
// an install hint. Writes a 1x and 2x PNG; release.sh combines them into one HiDPI TIFF.
//
// Usage: swift Scripts/make_dmg_background.swift <output-dir>
//
// Layout must match the icon positions release.sh sets via Finder:
//   window 660×400, app icon centered at (170, 190), Applications at (490, 190).

import AppKit

let width: CGFloat = 660
let height: CGFloat = 400
let outDir = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "."

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

func render(scale: CGFloat) -> Data {
    let pw = Int(width * scale), ph = Int(height * scale)
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: pw, pixelsHigh: ph,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
    )!
    rep.size = NSSize(width: width, height: height)

    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let ctx = NSGraphicsContext.current!.cgContext

    // Deep-space base gradient (top-left navy → bottom-right violet), matching the About window.
    let base = NSGradient(
        starting: NSColor(red: 0.03, green: 0.05, blue: 0.14, alpha: 1),
        ending: NSColor(red: 0.07, green: 0.04, blue: 0.11, alpha: 1)
    )!
    base.draw(in: NSRect(x: 0, y: 0, width: width, height: height), angle: -35)

    // Soft teal nebula glow behind the arrow.
    let glow = NSGradient(colors: [
        NSColor(red: 0.20, green: 0.80, blue: 0.90, alpha: 0.18),
        NSColor(red: 0.20, green: 0.80, blue: 0.90, alpha: 0.0)
    ])!
    glow.draw(fromCenter: NSPoint(x: width / 2, y: 210), radius: 0,
              toCenter: NSPoint(x: width / 2, y: 210), radius: 300, options: [])

    // Starfield — fixed seed so every release looks the same.
    var rng = SplitMix64(state: 0xE7E0_95)
    for _ in 0..<170 {
        let x = rng.unit() * width
        let y = rng.unit() * height
        let r = 0.3 + rng.unit() * 0.9
        let a = 0.10 + rng.unit() * 0.50
        ctx.setFillColor(NSColor(white: 1, alpha: a).cgColor)
        ctx.fillEllipse(in: CGRect(x: x, y: y, width: r * 2, height: r * 2))
    }

    // Drag arrow between the two icon slots (AppKit origin is bottom-left; icons sit at y=190
    // from the top, i.e. 210 from the bottom).
    let arrowY: CGFloat = 210
    let arrow = NSBezierPath()
    arrow.move(to: NSPoint(x: 262, y: arrowY))
    arrow.line(to: NSPoint(x: 390, y: arrowY))
    arrow.lineWidth = 3
    arrow.lineCapStyle = .round
    let dash: [CGFloat] = [2, 9]
    arrow.setLineDash(dash, count: 2, phase: 0)
    NSColor(red: 0.20, green: 0.80, blue: 0.90, alpha: 0.85).setStroke()
    arrow.stroke()

    let head = NSBezierPath()
    head.move(to: NSPoint(x: 384, y: arrowY + 11))
    head.line(to: NSPoint(x: 400, y: arrowY))
    head.line(to: NSPoint(x: 384, y: arrowY - 11))
    head.lineWidth = 3
    head.lineCapStyle = .round
    head.lineJoinStyle = .round
    head.stroke()

    // Title and hint.
    let para = NSMutableParagraphStyle()
    para.alignment = .center
    let title = NSAttributedString(string: "EVEOps", attributes: [
        .font: NSFont.systemFont(ofSize: 26, weight: .bold),
        .foregroundColor: NSColor.white,
        .paragraphStyle: para,
        .kern: 0.5
    ])
    title.draw(in: NSRect(x: 0, y: height - 72, width: width, height: 34))

    let hint = NSAttributedString(string: "Drag EVEOps to your Applications folder to install", attributes: [
        .font: NSFont.systemFont(ofSize: 13, weight: .medium),
        .foregroundColor: NSColor(white: 1, alpha: 0.6),
        .paragraphStyle: para
    ])
    hint.draw(in: NSRect(x: 0, y: 56, width: width, height: 20))

    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

try FileManager.default.createDirectory(atPath: outDir, withIntermediateDirectories: true)
try render(scale: 1).write(to: URL(fileURLWithPath: "\(outDir)/background.png"))
try render(scale: 2).write(to: URL(fileURLWithPath: "\(outDir)/background@2x.png"))
print("Wrote \(outDir)/background.png and background@2x.png")
