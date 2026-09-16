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
