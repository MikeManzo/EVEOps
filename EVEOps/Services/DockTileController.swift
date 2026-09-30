//
// This file is part of EVEOps.
//
// EVEOps is free software: you can redistribute it and/or modify
// it under the terms of the GNU General Public License as published by
// the Free Software Foundation, version 3 or later.
//
// Copyright (c) 2026 CitizenCoder
//

import AppKit
import SwiftUI

/// Drives the Dock icon's badge and optional training-progress ring from the latest
/// character summaries. Only visible while the Dock icon is shown (Settings > General);
/// updating the tile while the app runs as an accessory is harmless.
@MainActor
enum DockTileController {
    static let badgeKey = "dock.attentionBadge"
    static let progressKey = "dock.trainingProgress"

    /// Refreshes the badge and ring. Called after every summary rebuild.
    static func update(summaries: [CharacterSummary], selectedCharacterID: Int?) {
        let defaults = UserDefaults.standard
        let showBadge = defaults.object(forKey: badgeKey) as? Bool ?? true
        let showProgress = defaults.bool(forKey: progressKey)
        let tile = NSApp.dockTile

        // Badge: things that need the player's attention — idle skill queues and offline
        // PI extractors — the Dock equivalent of Mail's unread count.
        let attention = summaries.reduce(0) { total, s in
            let idleQueue = (s.isQueueEmpty && s.totalSP > 0 && s.loadError == nil) ? 1 : 0
            return total + idleQueue + s.expiredExtractorCount
        }
        tile.badgeLabel = (showBadge && attention > 0) ? "\(attention)" : nil

        // Ring: the selected (or first training) character's current-skill progress.
        let summary = summaries.first { $0.characterID == selectedCharacterID && !$0.isQueueEmpty }
            ?? summaries.first { !$0.isQueueEmpty }
        let progress: Double? = {
            guard showProgress, let s = summary,
                  let start = s.currentSkillStart, let finish = s.currentSkillFinish,
                  finish > start else { return nil }
            return min(max(Date().timeIntervalSince(start) / finish.timeIntervalSince(start), 0), 1)
        }()

        if let progress {
            let view = (tile.contentView as? ProgressTileView) ?? ProgressTileView()
            view.progress = progress
            tile.contentView = view
        } else {
            tile.contentView = nil
        }
        tile.display()
    }
}

/// App icon with a thin progress ring along its edge — the style Finder and Xcode use for
/// long-running work in the Dock.
private final class ProgressTileView: NSView {
    var progress: Double = 0

    override func draw(_ dirtyRect: NSRect) {
        NSApp.applicationIconImage?.draw(in: bounds)

        let inset = bounds.width * 0.1
        let rect = bounds.insetBy(dx: inset, dy: inset)
        let lineWidth = bounds.width * 0.055
        let center = NSPoint(x: rect.midX, y: rect.midY)
        let radius = rect.width / 2 - lineWidth / 2

        let track = NSBezierPath()
        track.appendArc(withCenter: center, radius: radius, startAngle: 0, endAngle: 360)
        track.lineWidth = lineWidth
        NSColor.black.withAlphaComponent(0.45).setStroke()
        track.stroke()

        let arc = NSBezierPath()
        arc.appendArc(withCenter: center, radius: radius,
                      startAngle: 90, endAngle: 90 - 360 * progress, clockwise: true)
        arc.lineWidth = lineWidth
        arc.lineCapStyle = .round
        FactionDockIcon.ringColor.setStroke()
        arc.stroke()
    }
}

/// Puts the theme faction's crest on the Dock icon (Caldari, Gallente, Amarr,
/// Minmatar), and colors the Dock progress ring to match. The default theme uses the
/// plain app icon. Setting `applicationIconImage` needs no system permission and is
/// undone by setting it back to nil.
@MainActor
enum FactionDockIcon {
    /// The progress ring's color; follows the theme accent.
    private(set) static var ringColor = NSColor(red: 0.30, green: 0.85, blue: 0.95, alpha: 1)

    static func apply(_ faction: FactionTheme) async {
        ringColor = NSColor(faction.palette.accent)
        guard let factionID = faction.factionID,
              let crestURL = EVEImageURL.factionCrest(factionID, size: 128),
              let crest = await ImageCache.shared.image(for: crestURL) else {
            NSApp.applicationIconImage = nil
            NSApp.dockTile.display()
            return
        }
        // The bundle's own icon, not `applicationIconImage`, which may already carry
        // a previous faction's crest.
        let base = NSWorkspace.shared.icon(forFile: Bundle.main.bundlePath)
        NSApp.applicationIconImage = composite(base: base, crest: crest, accent: ringColor)
        NSApp.dockTile.display()
    }

    /// The app icon with the crest in a small accent-rimmed disc at its lower right,
    /// like a document badge.
    private static func composite(base: NSImage, crest: NSImage, accent: NSColor) -> NSImage {
        let size = NSSize(width: 512, height: 512)
        return NSImage(size: size, flipped: false) { bounds in
            base.draw(in: bounds)
            let diameter = bounds.width * 0.40
            let disc = NSRect(x: bounds.maxX - diameter - bounds.width * 0.06,
                              y: bounds.minY + bounds.height * 0.06,
                              width: diameter, height: diameter)
            let circle = NSBezierPath(ovalIn: disc)
            NSColor(white: 0.08, alpha: 0.92).setFill()
            circle.fill()
            circle.lineWidth = bounds.width * 0.014
            accent.setStroke()
            circle.stroke()
            crest.draw(in: disc.insetBy(dx: diameter * 0.14, dy: diameter * 0.14),
                       from: .zero, operation: .sourceOver, fraction: 1)
            return true
        }
    }
}
