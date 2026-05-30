#!/usr/bin/env swift

// Generates EFTDocument.icns: EVEOps galaxy imagery inside a macOS document shape.
// Usage: swift scripts/make_eft_icon.swift

import AppKit
import CoreGraphics

// MARK: - Paths

let projectRoot = URL(fileURLWithPath: #file).deletingLastPathComponent().deletingLastPathComponent()
let sourcePNG   = projectRoot.appendingPathComponent("EVEOps/Assets.xcassets/AppIcon.appiconset/icon_512x512@2x.png")
let iconsetDir  = projectRoot.appendingPathComponent("scripts/EFTDocument.iconset")
let outputICNS  = projectRoot.appendingPathComponent("EVEOps/EVEOps/EFTDocument.icns")

// MARK: - Load source image

guard let sourceImage = NSImage(contentsOf: sourcePNG) else {
    fputs("ERROR: Cannot load source image at \(sourcePNG.path)\n", stderr)
    exit(1)
}

// MARK: - Icon sizes for iconutil

let sizes: [(name: String, pixels: Int)] = [
    ("icon_16x16",      16),
    ("icon_16x16@2x",   32),
    ("icon_32x32",      32),
    ("icon_32x32@2x",   64),
    ("icon_128x128",    128),
    ("icon_128x128@2x", 256),
    ("icon_256x256",    256),
    ("icon_256x256@2x", 512),
    ("icon_512x512",    512),
    ("icon_512x512@2x", 1024),
]

// MARK: - Draw document icon at a given canvas size

func drawDocumentIcon(canvasSize: Int, source: NSImage) -> NSImage {
    let cs = CGFloat(canvasSize)

    // Document proportions within the canvas (centered, slight padding)
    let pad   = cs * 0.06
    let docW  = cs - pad * 2
    let docH  = docW * 1.25          // classic 4:5 document ratio
    let docX  = pad
    let docY  = (cs - docH) / 2

    let corner = docW * 0.22         // folded-corner size
    let radius  = docW * 0.07        // rounded corner radius

    let result = NSImage(size: NSSize(width: cs, height: cs))
    result.lockFocus()
    defer { result.unlockFocus() }

    guard let ctx = NSGraphicsContext.current?.cgContext else { return result }

    ctx.saveGState()

    // ----- Build document clip path (page with folded top-right corner) -----
    // Coordinate system: AppKit (origin bottom-left)
    // Corners in AppKit coords:
    //   bottom-left:  (docX, docY)
    //   bottom-right: (docX+docW, docY)
    //   top-right before fold: (docX+docW, docY+docH)
    //   top-left:     (docX, docY+docH)

    let left   = docX
    let right  = docX + docW
    let bottom = docY
    let top    = docY + docH

    let pagePath = CGMutablePath()
    // Start at bottom-left (above radius)
    pagePath.move(to: CGPoint(x: left, y: bottom + radius))
    // Bottom-left corner
    pagePath.addArc(center: CGPoint(x: left + radius, y: bottom + radius),
                    radius: radius, startAngle: .pi, endAngle: .pi * 1.5, clockwise: false)
    // Bottom edge → bottom-right corner
    pagePath.addArc(center: CGPoint(x: right - radius, y: bottom + radius),
                    radius: radius, startAngle: .pi * 1.5, endAngle: 0, clockwise: false)
    // Right edge up to fold notch
    pagePath.addLine(to: CGPoint(x: right, y: top - corner))
    // Fold diagonal to top-right notch
    pagePath.addLine(to: CGPoint(x: right - corner, y: top))
    // Top edge → top-left corner
    pagePath.addArc(center: CGPoint(x: left + radius, y: top - radius),
                    radius: radius, startAngle: .pi * 0.5, endAngle: .pi, clockwise: false)
    // Left edge back down
    pagePath.closeSubpath()

    // Clip everything to the document shape
    ctx.addPath(pagePath)
    ctx.clip()

    // ----- Fill with galaxy image -----
    let srcRect = NSRect(x: 0, y: 0, width: cs, height: cs)
    let destRect = NSRect(x: docX, y: docY, width: docW, height: docH)

    // Draw galaxy image scaled to fill the document face
    source.draw(in: destRect, from: srcRect, operation: .sourceOver, fraction: 1.0)

    // Subtle dark vignette overlay to reinforce document edges
    let vignette = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                               colors: [CGColor.clear,
                                        CGColor(red: 0, green: 0, blue: 0, alpha: 0.35)] as CFArray,
                               locations: [0.55, 1.0])!
    ctx.drawRadialGradient(vignette,
                            startCenter: CGPoint(x: docX + docW/2, y: docY + docH/2),
                            startRadius: docW * 0.25,
                            endCenter: CGPoint(x: docX + docW/2, y: docY + docH/2),
                            endRadius: docW * 0.78,
                            options: [.drawsAfterEndLocation])

    ctx.restoreGState()

    // ----- Thin page border -----
    ctx.saveGState()
    ctx.addPath(pagePath)
    ctx.setStrokeColor(CGColor(red: 0.3, green: 0.3, blue: 0.45, alpha: 0.55))
    ctx.setLineWidth(max(0.5, cs * 0.004))
    ctx.strokePath()
    ctx.restoreGState()

    // ----- Fold triangle (top-right) -----
    // The fold flap covers the notch and shows a lighter crease
    let foldPath = CGMutablePath()
    foldPath.move(to: CGPoint(x: right - corner, y: top))
    foldPath.addLine(to: CGPoint(x: right, y: top - corner))
    foldPath.addLine(to: CGPoint(x: right - corner, y: top - corner))
    foldPath.closeSubpath()

    ctx.saveGState()
    // Slightly lighter galaxy tint for the fold flap
    ctx.addPath(foldPath)
    ctx.clip()
    let foldRect = NSRect(x: right - corner, y: top - corner, width: corner, height: corner)
    source.draw(in: foldRect, from: srcRect, operation: .sourceOver, fraction: 1.0)
    // Lighten the fold
    ctx.setFillColor(CGColor(red: 0.7, green: 0.75, blue: 1.0, alpha: 0.30))
    ctx.fill(CGRect(x: right - corner, y: top - corner, width: corner, height: corner))
    ctx.restoreGState()

    // Fold crease line
    ctx.saveGState()
    ctx.move(to: CGPoint(x: right - corner, y: top))
    ctx.addLine(to: CGPoint(x: right - corner, y: top - corner))
    ctx.addLine(to: CGPoint(x: right, y: top - corner))
    ctx.setStrokeColor(CGColor(red: 0.4, green: 0.45, blue: 0.65, alpha: 0.7))
    ctx.setLineWidth(max(0.5, cs * 0.004))
    ctx.strokePath()
    ctx.restoreGState()

    // ----- "EFT" label at bottom of document (only for larger sizes) -----
    if canvasSize >= 128 {
        let fontSize = docW * 0.13
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.boldSystemFont(ofSize: fontSize),
            .foregroundColor: NSColor(white: 1.0, alpha: 0.85)
        ]
        let label = NSAttributedString(string: "EFT", attributes: attrs)
        let labelSize = label.size()
        let labelX = docX + (docW - labelSize.width) / 2
        let labelY = docY + docH * 0.07
        label.draw(at: NSPoint(x: labelX, y: labelY))
    }

    return result
}

// MARK: - Write PNGs and build ICNS

try? FileManager.default.createDirectory(at: iconsetDir, withIntermediateDirectories: true)

for size in sizes {
    let img = drawDocumentIcon(canvasSize: size.pixels, source: sourceImage)
    guard let tiff = img.tiffRepresentation,
          let bitmap = NSBitmapImageRep(data: tiff),
          let png = bitmap.representation(using: .png, properties: [:]) else {
        fputs("ERROR: Failed to encode \(size.name)\n", stderr)
        exit(1)
    }
    let dest = iconsetDir.appendingPathComponent("\(size.name).png")
    try png.write(to: dest)
    print("  wrote \(size.name).png (\(size.pixels)px)")
}

// Use iconutil to produce the final .icns
let task = Process()
task.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
task.arguments = ["-c", "icns", "-o", outputICNS.path, iconsetDir.path]
try task.run()
task.waitUntilExit()

if task.terminationStatus == 0 {
    print("\nDone — \(outputICNS.path)")
} else {
    fputs("ERROR: iconutil failed (exit \(task.terminationStatus))\n", stderr)
    exit(1)
}
