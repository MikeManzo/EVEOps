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

extension View {
    /// Standard EVEOps card surface — regular material in a rounded rect. This is the
    /// default look most panels already use via `.background(.regularMaterial, in:
    /// RoundedRectangle(...))`; prefer this modifier for new cards so the corner radius
    /// stays consistent.
    func eveCard(cornerRadius: CGFloat = 12) -> some View {
        background(.regularMaterial, in: RoundedRectangle(cornerRadius: cornerRadius))
    }

    /// Elevated card surface for the one or two cards per screen that are the primary
    /// content (a net worth figure, the currently-training character) rather than
    /// secondary/supporting ones (a journal row, a stat tile). Same material, plus a
    /// subtle top-lit border and drop shadow so it reads as "the important one" next to
    /// flat neighbors instead of every panel looking identically weighted.
    func eveElevatedCard(cornerRadius: CGFloat = 12) -> some View {
        background(.regularMaterial, in: RoundedRectangle(cornerRadius: cornerRadius))
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .strokeBorder(
                        LinearGradient(
                            colors: [.white.opacity(0.16), .white.opacity(0)],
                            startPoint: .top,
                            endPoint: .bottom
                        ),
                        lineWidth: 1
                    )
            )
            .shadow(color: .black.opacity(0.28), radius: 10, y: 4)
    }
}

extension View {
    /// Selection that reliably uses the faction accent, for a `List` built *without* a
    /// `selection:` binding: tapping the row calls `onSelect`, and the selected row gets a
    /// plain accent-filled background.
    ///
    /// Why not a native `List(selection:)`: macOS draws its selection highlight in the
    /// app's static AccentColor asset, on top of anything we supply. `.listRowBackground`
    /// loses to it, and `.listItemTint` (the former `themedListRow`) didn't take in
    /// sectioned lists — screenshots kept showing the asset color. So when the theme color
    /// must win, don't let the system draw a selection at all; the main sidebar pioneered
    /// this and every selectable list in the app now uses it.
    ///
    /// Pair with `.onKeyPress` on the List for ↑/↓ navigation, which a selection-less List
    /// doesn't provide on its own.
    func eveSelectableListRow(isSelected: Bool, palette: EVEPalette, onSelect: @escaping () -> Void) -> some View {
        self
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .onTapGesture(perform: onSelect)
            .foregroundStyle(isSelected ? .white : .primary)
            // What the native selection does for us: tells hierarchical styles
            // (.secondary, .tertiary) they sit on a prominent fill, so they turn light.
            .environment(\.backgroundProminence, isSelected ? .increased : .standard)
            .listRowBackground(
                isSelected
                    ? RoundedRectangle(cornerRadius: EVERadius.sm)
                        .fill(palette.accent)
                        .padding(.horizontal, EVESpacing.sm)
                    : nil
            )
            .accessibilityAddTraits(isSelected ? [.isSelected, .isButton] : .isButton)
            .accessibilityAction { onSelect() }
            .modifier(CompactRowInsets())
    }
}

/// In Compact density, trims the List's own row insets — most of a macOS list row's
/// vertical space — not just the padding inside the row.
private struct CompactRowInsets: ViewModifier {
    @Environment(\.eveRowDensity) private var density

    func body(content: Content) -> some View {
        if density == .compact {
            content.listRowInsets(EdgeInsets(top: 1, leading: EVESpacing.lg, bottom: 1, trailing: EVESpacing.lg))
        } else {
            content
        }
    }
}

private struct EVEListKeyboardSelection<ID: Hashable>: ViewModifier {
    let ordered: [ID]
    let selection: ID?
    let onSelect: (ID?) -> Void

    func body(content: Content) -> some View {
        ScrollViewReader { proxy in
            content
                .focusable()
                .focusEffectDisabled()
                .onKeyPress(.downArrow) { move(1, proxy) }
                .onKeyPress(.upArrow) { move(-1, proxy) }
        }
    }

    private func move(_ delta: Int, _ proxy: ScrollViewProxy) -> KeyPress.Result {
        guard !ordered.isEmpty else { return .ignored }
        let next: ID
        if let selection, let index = ordered.firstIndex(of: selection) {
            next = ordered[min(max(index + delta, 0), ordered.count - 1)]
        } else {
            next = delta > 0 ? ordered[0] : ordered[ordered.count - 1]
        }
        onSelect(next)
        proxy.scrollTo(next)
        return .handled
    }
}

extension View {
    /// ↑/↓ row navigation for a `List` whose rows use `eveSelectableListRow` (and so has
    /// no native `selection:` binding to provide it). `ordered` is every selectable row ID
    /// in display order; rows must carry a matching `.id(_:)` for scrolling to work.
    func eveKeyboardSelection<ID: Hashable>(
        _ ordered: [ID],
        selection: ID?,
        onSelect: @escaping (ID?) -> Void
    ) -> some View {
        modifier(EVEListKeyboardSelection(ordered: ordered, selection: selection, onSelect: onSelect))
    }
}
