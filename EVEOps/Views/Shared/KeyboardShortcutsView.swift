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

/// Every keyboard shortcut in one sheet (Help > Keyboard Shortcuts, ⌘/). The ⌘1–⌘9 list
/// is built from `NavigationSection.quickJumpSlots`, the same source `AppCommands` binds,
/// so this reference can't drift from the real shortcuts.
struct KeyboardShortcutsView: View {
    let onClose: () -> Void

    private struct Shortcut: Identifiable {
        let keys: String
        let action: LocalizedStringKey
        var id: String { keys }
    }

    private var navigation: [Shortcut] {
        [
            .init(keys: "⌘K", action: "Quick switcher — screens, systems, items, pilots"),
            .init(keys: "⌘0", action: "Dashboard"),
            .init(keys: "⌘[", action: "Previous screen"),
            .init(keys: "⌘]", action: "Next screen"),
        ]
    }

    private var quickJumps: [Shortcut] {
        NavigationSection.quickJumpSlots.enumerated().map { index, section in
            .init(keys: "⌘\(index + 1)", action: section.title)
        }
    }

    private var actions: [Shortcut] {
        [
            .init(keys: "⌘R", action: "Refresh the current screen"),
            .init(keys: "⌘N", action: "Add a character"),
            .init(keys: "⌘,", action: "Settings"),
            .init(keys: "⌘/", action: "This list"),
        ]
    }

    private var lists: [Shortcut] {
        [
            .init(keys: "↑  ↓", action: "Move the selection"),
            .init(keys: "Esc", action: "Close a detail panel"),
            .init(keys: "⌘C", action: "Copy selected table rows"),
        ]
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Keyboard Shortcuts")
                    .font(.title2.bold())
                Spacer()
                Button("Done", action: onClose)
                    .keyboardShortcut(.defaultAction)
            }
            .padding(EVESpacing.xl)

            Divider()

            ScrollView {
                HStack(alignment: .top, spacing: EVESpacing.xxl) {
                    VStack(alignment: .leading, spacing: EVESpacing.xl) {
                        group("Navigation", navigation)
                        group("Actions", actions)
                        group("Lists & Tables", lists)
                    }
                    group("Jump To", quickJumps)
                }
                .padding(EVESpacing.xl)
            }
        }
        .frame(width: 620, height: 460)
    }

    private func group(_ title: LocalizedStringKey, _ shortcuts: [Shortcut]) -> some View {
        EVEInspectorSection(title) {
            Grid(alignment: .leading, horizontalSpacing: EVESpacing.lg, verticalSpacing: EVESpacing.sm) {
                ForEach(shortcuts) { shortcut in
                    GridRow {
                        Text(shortcut.keys)
                            .font(.callout.monospaced().weight(.semibold))
                            .padding(.horizontal, EVESpacing.sm)
                            .padding(.vertical, 2)
                            .background(Color.primary.opacity(0.07), in: RoundedRectangle(cornerRadius: EVERadius.xs))
                            .gridColumnAlignment(.trailing)
                        Text(shortcut.action)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .frame(minWidth: 260, alignment: .leading)
    }
}
