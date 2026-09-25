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
import Observation

/// Brief confirmation for actions that otherwise happen silently — copying, setting a
/// destination, pinning — shown as a small capsule at the bottom of the focused window.
@MainActor
@Observable
final class ToastCenter {
    static let shared = ToastCenter()

    struct Toast: Identifiable, Equatable {
        enum Style { case success, failure, info }
        let id = UUID()
        let message: String
        let systemImage: String
        let style: Style
    }

    private(set) var current: Toast?
    @ObservationIgnored private var dismissTask: Task<Void, Never>?

    private init() {}

    func show(_ message: String, systemImage: String? = nil, style: Toast.Style = .success) {
        let symbol = systemImage ?? {
            switch style {
            case .success: return "checkmark.circle.fill"
            case .failure: return "exclamationmark.triangle.fill"
            case .info:    return "info.circle.fill"
            }
        }()
        current = Toast(message: message, systemImage: symbol, style: style)
        dismissTask?.cancel()
        let duration: Duration = style == .failure ? .seconds(3.5) : .seconds(1.8)
        dismissTask = Task { [weak self] in
            try? await Task.sleep(for: duration)
            guard !Task.isCancelled else { return }
            self?.current = nil
        }
    }

    // Common confirmations, worded once.
    func copied(_ what: String? = nil) {
        show(what.map { String(localized: "Copied \($0)") } ?? String(localized: "Copied"), systemImage: "doc.on.doc.fill")
    }
}

/// Displays `ToastCenter`'s current toast at the bottom of the window it's attached to —
/// only while that window is key, so multiple windows don't all echo the same toast.
private struct ToastOverlayModifier: ViewModifier {
    @Environment(\.controlActiveState) private var activeState
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(ThemeManager.self) private var themeManager

    func body(content: Content) -> some View {
        content.overlay(alignment: .bottom) {
            if activeState == .key, let toast = ToastCenter.shared.current {
                HStack(spacing: EVESpacing.sm) {
                    Image(systemName: toast.systemImage)
                        .foregroundStyle(color(toast.style))
                    Text(toast.message)
                        .lineLimit(2)
                }
                .font(.callout.weight(.medium))
                .padding(.horizontal, EVESpacing.lg)
                .padding(.vertical, EVESpacing.md)
                .glassEffect(.regular, in: Capsule())
                .shadow(color: .black.opacity(0.2), radius: 10, y: 4)
                .padding(.bottom, EVESpacing.xxl)
                .id(toast.id)
                .transition(reduceMotion ? .opacity : .opacity.combined(with: .offset(y: 12)))
                .accessibilityElement(children: .combine)
                .accessibilityAddTraits(.updatesFrequently)
                .allowsHitTesting(false)
            }
        }
        .animation(reduceMotion ? nil : .snappy(duration: 0.28), value: ToastCenter.shared.current)
        .onChange(of: ToastCenter.shared.current) { _, toast in
            // VoiceOver hears the confirmation too.
            if let toast, activeState == .key {
                AccessibilityNotification.Announcement(toast.message).post()
            }
        }
    }

    private func color(_ style: ToastCenter.Toast.Style) -> Color {
        switch style {
        case .success: .green
        case .failure: .orange
        case .info:    themeManager.palette.accent
        }
    }
}

extension View {
    /// Shows `ToastCenter` toasts over this window's content. Applied once per window root.
    func eveToastOverlay() -> some View { modifier(ToastOverlayModifier()) }
}
