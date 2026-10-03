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

// Small pieces shared by the cross-pilot screens (Login Planner, Dead Stock, Hangar
// Matrix, Skill ROI).

/// A headline number on a card: label, value, one line of detail.
struct InsightStat: View {
    let label: String
    let value: String
    let detail: String
    var tint: Color = .primary

    var body: some View {
        VStack(alignment: .leading, spacing: EVESpacing.xs) {
            Text(verbatim: label)
                .font(.eveCaptionMedium)
                .foregroundStyle(.secondary)
            Text(verbatim: value)
                .font(.eveStat)
                .foregroundStyle(tint)
                .contentTransition(.numericText())
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(verbatim: detail)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(EVESpacing.lg)
        .eveCard(cornerRadius: EVERadius.xl)
        .accessibilityElement(children: .combine)
    }
}

/// A row of `InsightStat`s that wraps on narrow windows.
struct InsightStatRow<Content: View>: View {
    @ViewBuilder let content: () -> Content

    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 180), spacing: EVESpacing.md)], spacing: EVESpacing.md) {
            content()
        }
    }
}

/// A round character portrait.
struct PilotPortrait: View {
    let characterID: Int
    var size: CGFloat = 24
    var ring: Color? = nil

    var body: some View {
        CachedAsyncImage(url: EVEImageURL.characterPortrait(characterID, size: size > 48 ? 128 : 64)) { image in
            image.resizable().aspectRatio(contentMode: .fill)
        } placeholder: {
            Circle().fill(.quaternary)
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .overlay(Circle().strokeBorder(ring ?? .primary.opacity(0.08), lineWidth: ring == nil ? 0.5 : 1.5))
    }
}

/// A tinted capsule toggle for filter bars.
struct InsightToggleChip: View {
    let title: Text
    var systemImage: String? = nil
    let isOn: Bool
    let tint: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: EVESpacing.xs) {
                if let systemImage { Image(systemName: systemImage) }
                title
            }
        }
        .buttonStyle(.plain)
        .modifier(ReadyRoomChipStyle(tint: isOn ? tint : .secondary))
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }
}

enum InsightClipboard {
    static func copy(_ text: String, toast: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        ToastCenter.shared.show(toast, systemImage: "doc.on.clipboard")
    }
}
