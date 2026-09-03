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

// MARK: - Relative "updated N ago" label

/// Live-updating freshness label. Renders nothing until there is a date to show,
/// so callers can drop it in unconditionally.
struct RelativeTimestamp: View {
    let date: Date?
    var prefix: LocalizedStringKey = "Updated"

    var body: some View {
        if let date {
            TimelineView(.everyMinute) { _ in
                Text("\(Text(prefix)) \(Self.phrase(for: date))")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .help(date.formatted(date: .abbreviated, time: .standard))
            }
        }
    }

    private static func phrase(for date: Date) -> String {
        let elapsed = Date().timeIntervalSince(date)
        if elapsed < 45 { return String(localized: "just now") }
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}

// MARK: - Standard refresh button

/// Toolbar / header refresh control with a consistent look, tooltip, spinner
/// state and a ⌘R shortcut (the app has no menu bar to host one otherwise).
struct RefreshButton: View {
    var isRefreshing: Bool = false
    /// Off by default: ⌘R is owned globally by `MainContentView` and fans out via
    /// `AppRouter.refreshTick`, so binding it here too would double-register.
    var bindShortcut: Bool = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                Image(systemName: "arrow.clockwise")
                    .opacity(isRefreshing ? 0 : 1)
                if isRefreshing {
                    ProgressView().controlSize(.small)
                }
            }
        }
        .buttonStyle(.borderless)
        .help("Refresh")
        .disabled(isRefreshing)
        .modifier(OptionalCommandR(enabled: bindShortcut))
        .accessibilityLabel("Refresh")
    }
}

private struct OptionalCommandR: ViewModifier {
    let enabled: Bool
    func body(content: Content) -> some View {
        if enabled {
            content.keyboardShortcut("r", modifiers: .command)
        } else {
            content
        }
    }
}

// MARK: - Auto-refresh loop

private struct AutoRefreshModifier: ViewModifier {
    let interval: Double
    let enabled: Bool
    let action: () async -> Void

    private struct Key: Hashable { let interval: Double; let enabled: Bool }

    func body(content: Content) -> some View {
        content.task(id: Key(interval: interval, enabled: enabled)) {
            guard enabled, interval > 0 else { return }
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(interval))
                if Task.isCancelled { break }
                await action()
            }
        }
    }
}

extension View {
    /// Runs `action` every `interval` seconds while the view is alive. Replaces the
    /// hand-rolled `while !Task.isCancelled { sleep }` loop duplicated across views.
    /// Re-arms itself when `interval` or `enabled` changes.
    func autoRefresh(
        every interval: Double,
        enabled: Bool = true,
        _ action: @escaping () async -> Void
    ) -> some View {
        modifier(AutoRefreshModifier(interval: interval, enabled: enabled, action: action))
    }
}

// MARK: - Lightweight clock tick

private struct PeriodicTickModifier: ViewModifier {
    let interval: Double
    let action: () -> Void

    func body(content: Content) -> some View {
        content.task(id: interval) {
            guard interval > 0 else { return }
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(interval))
                if Task.isCancelled { break }
                action()
            }
        }
    }
}

extension View {
    /// Fire `action` every `interval` seconds — for live "x ago" / countdown
    /// labels that only need to re-render, not re-fetch. Replaces the hand-rolled
    /// `while !Task.isCancelled { sleep; now = Date() }` timers scattered across views.
    func periodicTick(every interval: Double, _ action: @escaping () -> Void) -> some View {
        modifier(PeriodicTickModifier(interval: interval, action: action))
    }
}

// MARK: - Skeleton placeholder

/// Redacted stand-in shown on a genuine cold load (no cached content yet), so a
/// freshly-opened screen reads as "loading this list" rather than a blank pane.
struct LoadingSkeleton: View {
    var rows: Int = 6
    var showsHeader: Bool = true

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if showsHeader {
                RoundedRectangle(cornerRadius: 6)
                    .fill(.quaternary)
                    .frame(width: 180, height: 22)
            }
            ForEach(0..<max(1, rows), id: \.self) { _ in
                HStack(spacing: 12) {
                    RoundedRectangle(cornerRadius: 6).fill(.quaternary)
                        .frame(width: 34, height: 34)
                    VStack(alignment: .leading, spacing: 6) {
                        RoundedRectangle(cornerRadius: 4).fill(.quaternary)
                            .frame(maxWidth: .infinity).frame(height: 12)
                        RoundedRectangle(cornerRadius: 4).fill(.quaternary)
                            .frame(width: 140, height: 10)
                    }
                }
            }
            Spacer(minLength: 0)
        }
        .padding()
        .redacted(reason: .placeholder)
        .shimmer()
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .accessibilityLabel("Loading")
    }
}

// MARK: - Shimmer

private struct Shimmer: ViewModifier {
    @State private var phase: CGFloat = -1

    func body(content: Content) -> some View {
        content
            .overlay {
                GeometryReader { geo in
                    LinearGradient(
                        colors: [.clear, .white.opacity(0.35), .clear],
                        startPoint: .leading, endPoint: .trailing
                    )
                    .frame(width: geo.size.width * 0.6)
                    .offset(x: phase * geo.size.width * 1.6)
                    .blendMode(.plusLighter)
                }
                .allowsHitTesting(false)
                .mask(content)
            }
            .task {
                while !Task.isCancelled {
                    withAnimation(.linear(duration: 1.3)) { phase = 1 }
                    try? await Task.sleep(for: .seconds(1.3))
                    phase = -1
                    try? await Task.sleep(for: .seconds(0.2))
                }
            }
    }
}

extension View {
    func shimmer() -> some View { modifier(Shimmer()) }
}
