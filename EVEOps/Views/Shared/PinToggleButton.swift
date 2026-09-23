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

extension Color {
    /// The pin feature's own color — kept apart from `.accentColor` (selection)
    /// and `.orange` (warnings/reauth) so a pinned state is never ambiguous
    /// with either.
    static let pinAccent = Color(red: 0.85, green: 0.65, blue: 0.13)
}

/// Pin/unpin toggle for a sidebar destination, meant to sit right after a
/// page's title. Reads and writes the same `sidebar.pinnedSections`
/// `@AppStorage` key `SidebarView` uses to populate its "Pinned" section, so
/// toggling here is immediately reflected there.
struct PinToggleButton: View {
    let section: NavigationSection

    @AppStorage("sidebar.pinnedSections") private var pinnedSectionsRaw =
        NavigationSection.quickJumpSlots.map(\.rawValue).joined(separator: ",")

    private static let maxPinned = 9

    private var pinnedSections: [NavigationSection] {
        pinnedSectionsRaw
            .split(separator: ",")
            .compactMap { NavigationSection(rawValue: String($0)) }
    }

    private var isPinned: Bool { pinnedSections.contains(section) }

    var body: some View {
        Button {
            togglePin()
        } label: {
            Image(systemName: isPinned ? "pin.fill" : "pin")
                .font(.callout)
                .foregroundStyle(isPinned ? Color.pinAccent : Color.secondary.opacity(0.6))
                // Unpinned reads as a loose pin lying on its side, tip to the
                // left; pinned stands upright as if stuck into the sidebar.
                .rotationEffect(isPinned ? .zero : .degrees(90))
                .contentTransition(.symbolEffect(.replace))
                .animation(.spring(response: 0.3, dampingFraction: 0.6), value: isPinned)
        }
        .accessibilityLabel(isPinned ? "Unpin" : "Pin")
        .buttonStyle(.plain)
        .disabled(!isPinned && pinnedSections.count >= Self.maxPinned)
        .help(
            isPinned ? "Unpin from the sidebar's Pinned section"
                : pinnedSections.count >= Self.maxPinned ? "Pinned is full — unpin something first (\(Self.maxPinned) max)"
                : "Pin to the top of the sidebar"
        )
        .accessibilityLabel(isPinned ? "Unpin \(section.rawValue)" : "Pin \(section.rawValue)")
    }

    private func togglePin() {
        var current = pinnedSections
        if let index = current.firstIndex(of: section) {
            current.remove(at: index)
        } else {
            guard current.count < Self.maxPinned else { return }
            current.append(section)
        }
        pinnedSectionsRaw = current.map(\.rawValue).joined(separator: ",")
    }
}
