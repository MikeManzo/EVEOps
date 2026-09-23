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
    /// Recolors a `List` row's native selection highlight with the live faction accent.
    ///
    /// Two `.listRowBackground`-based approaches were tried before this and both failed the
    /// same way: on macOS, the system's own selection layer paints *on top of* whatever
    /// `.listRowBackground` supplies, not behind it — screenshots confirmed the native color
    /// (from the app's static AccentColor asset) stayed visible across most of the row, with
    /// our fill only showing at the margins. No amount of opacity or padding on a background
    /// view can win a fight with something drawn after it.
    ///
    /// `.listItemTint(_:)` is Apple's actual mechanism for this — it's what backs Reminders'
    /// and Notes' per-list colored sidebars — but it has to be applied to each row's own
    /// content directly. Applying it once from a distant ancestor (tried first, before either
    /// `.listRowBackground` attempt) didn't visibly take, which is presumably why: it needs
    /// to reach the row itself, not just be present somewhere in the environment.
    ///
    /// Caveat: it doesn't take in every list — the Station Browser (sectioned, sidebar
    /// style) kept showing the static AccentColor with it applied. Where the selection
    /// color must follow the theme, use `eveSelectableListRow` instead.
    func themedListRow(isSelected: Bool, palette: EVEPalette) -> some View {
        self
            .foregroundStyle(isSelected ? .white : .primary)
            .listItemTint(.fixed(palette.accent))
    }
}

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
    /// plain accent-filled background. This is the sidebar's technique — macOS paints a
    /// `List(selection:)` highlight on top of anything we supply, and `.listItemTint` (see
    /// `themedListRow`) doesn't take in every list configuration, so when the theme color
    /// must win, don't let the system draw a selection at all.
    ///
    /// Pair with `.onKeyPress` on the List for ↑/↓ navigation, which a selection-less List
    /// doesn't provide on its own.
    func eveSelectableListRow(isSelected: Bool, palette: EVEPalette, onSelect: @escaping () -> Void) -> some View {
        self
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .onTapGesture(perform: onSelect)
            .foregroundStyle(isSelected ? .white : .primary)
            .listRowBackground(
                isSelected
                    ? RoundedRectangle(cornerRadius: EVERadius.sm)
                        .fill(palette.accent)
                        .padding(.horizontal, EVESpacing.sm)
                    : nil
            )
            .accessibilityAddTraits(isSelected ? [.isSelected, .isButton] : .isButton)
            .accessibilityAction { onSelect() }
    }
}
