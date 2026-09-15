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
