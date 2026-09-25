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

/// Shown once after an update: the highlights of the running version, taken from the
/// same release notes Sparkle's update dialog shows (which most people click past).
struct WhatsNewView: View {
    let notes: WhatsNewService.Notes
    let onDone: () -> Void

    @Environment(ThemeManager.self) private var themeManager

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: EVESpacing.md) {
                Image(nsImage: NSApp.applicationIconImage)
                    .resizable()
                    .frame(width: 72, height: 72)
                    .shadow(color: .black.opacity(0.25), radius: 8, y: 4)
                    .accessibilityHidden(true)
                Text("What’s New in EVEOps \(notes.version)")
                    .font(.title2.bold())
                    .multilineTextAlignment(.center)
            }
            .padding(.top, EVESpacing.xxl)
            .padding(.bottom, EVESpacing.lg)

            ScrollView {
                VStack(alignment: .leading, spacing: EVESpacing.md) {
                    ForEach(Array(notes.items.enumerated()), id: \.offset) { _, item in
                        HStack(alignment: .firstTextBaseline, spacing: EVESpacing.md) {
                            Image(systemName: "sparkle")
                                .font(.caption)
                                .foregroundStyle(themeManager.palette.accent)
                            Text(item)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
                .padding(.horizontal, EVESpacing.xxl)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxHeight: 280)

            Divider().padding(.top, EVESpacing.lg)

            HStack {
                if let url = notes.releaseURL {
                    Link("Full Release Notes", destination: url)
                }
                Spacer()
                Button("Continue", action: onDone)
                    .buttonStyle(.borderedProminent)
                    .tint(themeManager.palette.accent)
                    .keyboardShortcut(.defaultAction)
            }
            .padding(EVESpacing.xl)
        }
        .frame(width: 480)
    }
}
