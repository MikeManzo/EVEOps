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

// Shared visual effects. Two rules hold for everything in this file:
//
// 1. Effects never take part in layout. They draw in backgrounds and overlays, or as
//    symbol effects and render-only transforms, so turning one on or off can't resize a
//    view. (A countdown that changed a view's size each second is what hung Training.)
// 2. Reduce Motion is respected here, once, so call sites don't each have to remember:
//    with it on, symbol effects don't play and scroll reveals only fade.

// MARK: - Selection glow

private struct EVESelectionGlowModifier: ViewModifier {
    let isActive: Bool
    let cornerRadius: CGFloat
    let outset: CGSize
    @Environment(ThemeManager.self) private var themeManager: ThemeManager?

    func body(content: Content) -> some View {
        let accent = themeManager?.palette.accent ?? .eveThemeAccent
        let shape = RoundedRectangle(cornerRadius: cornerRadius)
        content
            .background {
                shape
                    .fill(accent.opacity(isActive ? EVEOpacity.faint : 0))
                    .padding(.horizontal, -outset.width)
                    .padding(.vertical, -outset.height)
            }
            .overlay {
                shape
                    .strokeBorder(accent.opacity(isActive ? EVEOpacity.strong : 0), lineWidth: 1)
                    .shadow(color: accent.opacity(isActive ? 0.55 : 0), radius: 6)
                    .padding(.horizontal, -outset.width)
                    .padding(.vertical, -outset.height)
                    .allowsHitTesting(false)
            }
            .animation(.smooth(duration: 0.2), value: isActive)
            .accessibilityAddTraits(isActive ? .isSelected : [])
    }
}

extension View {
    /// The app's one selection treatment: a soft glow box in the theme accent. `outset`
    /// pushes the box past the view's edges without changing its size, for rows that sit
    /// tight against their neighbors.
    func eveSelectionGlow(
        isActive: Bool,
        cornerRadius: CGFloat = EVERadius.sm,
        outset: CGSize = .zero
    ) -> some View {
        modifier(EVESelectionGlowModifier(isActive: isActive, cornerRadius: cornerRadius, outset: outset))
    }
}

// MARK: - Symbol effects

private struct EVESymbolBounceModifier<V: Equatable>: ViewModifier {
    let value: V
    let wiggle: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        // With Reduce Motion the trigger never changes, so the effect never fires.
        let trigger: V? = reduceMotion ? nil : value
        if wiggle {
            content.symbolEffect(.wiggle, options: .nonRepeating, value: trigger)
        } else {
            content.symbolEffect(.bounce, options: .nonRepeating, value: trigger)
        }
    }
}

private struct EVESymbolLoopModifier: ViewModifier {
    enum Kind { case pulse, breathe }
    let kind: Kind
    let isActive: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        let active = isActive && !reduceMotion
        switch kind {
        case .pulse:   content.symbolEffect(.pulse, options: .repeat(.continuous), isActive: active)
        case .breathe: content.symbolEffect(.breathe, options: .repeat(.continuous), isActive: active)
        }
    }
}

extension View {
    /// Bounces an SF Symbol once each time `value` changes (not on first appearance).
    func eveBounce<V: Equatable>(on value: V) -> some View {
        modifier(EVESymbolBounceModifier(value: value, wiggle: false))
    }

    /// Wiggles an SF Symbol once each time `value` changes — for "something new arrived".
    func eveWiggle<V: Equatable>(on value: V) -> some View {
        modifier(EVESymbolBounceModifier(value: value, wiggle: true))
    }

    /// Pulses an SF Symbol continuously while `isActive` — for an ongoing problem state.
    func evePulse(isActive: Bool) -> some View {
        modifier(EVESymbolLoopModifier(kind: .pulse, isActive: isActive))
    }

    /// A slow, continuous breathe — for the icon of an empty state.
    func eveBreathe(isActive: Bool = true) -> some View {
        modifier(EVESymbolLoopModifier(kind: .breathe, isActive: isActive))
    }
}

// MARK: - Scroll reveal

private struct EVEScrollRevealModifier: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        let reduceMotion = reduceMotion
        return content.scrollTransition(.animated(.smooth(duration: 0.3))) { view, phase in
            // Opacity plus a small offset, never a scale: offsets move AppKit-backed
            // controls without resizing them (see `AnyTransition.eveSection`).
            view
                .opacity(phase.isIdentity ? 1 : 0.4)
                .offset(y: reduceMotion || phase.isIdentity ? 0 : phase.value * 8)
        }
    }
}

extension View {
    /// Fades cards in (and out) as they scroll into view. For items in a scrolling list.
    func eveScrollReveal() -> some View {
        modifier(EVEScrollRevealModifier())
    }
}

// MARK: - Completion ping

/// An accent ring that swells and fades out once each time `trigger` changes — the
/// "that just finished" moment. Put it in an `.overlay` of a fixed-size view; it draws
/// with scale and opacity only and never affects layout.
struct EVECompletionPing<T: Equatable>: View {
    let trigger: T
    var color: Color = .green
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Circle()
            .strokeBorder(color, lineWidth: 3)
            .keyframeAnimator(initialValue: PingFrame(), trigger: reduceMotion ? nil : trigger) { ring, frame in
                ring
                    .scaleEffect(frame.scale)
                    .opacity(frame.opacity)
            } keyframes: { _ in
                KeyframeTrack(\.opacity) {
                    LinearKeyframe(0.9, duration: 0.05)
                    LinearKeyframe(0, duration: 1.1)
                }
                KeyframeTrack(\.scale) {
                    LinearKeyframe(1, duration: 0.05)
                    SpringKeyframe(1.6, duration: 1.1, spring: .smooth)
                }
            }
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }

    private struct PingFrame {
        var scale: Double = 1
        var opacity: Double = 0
    }
}

// MARK: - Standing ring

extension View {
    /// Rings a portrait or logo in its standing color (EVE's blue-to-red scale). Draws
    /// nothing for a neutral or unknown standing, so strangers keep a plain portrait. The
    /// overlay is always attached and only fades, so the portrait keeps its identity (and
    /// its loaded image) when standings arrive.
    func eveStandingRing(_ standing: Double?, circle: Bool = true, cornerRadius: CGFloat = EVERadius.sm,
                         lineWidth: CGFloat = 1.5) -> some View {
        let shown = standing.map { $0 != 0 } ?? false
        let color = eveStandingColor(standing ?? 0)
        return overlay {
            Group {
                if circle {
                    Circle().strokeBorder(color, lineWidth: lineWidth)
                } else {
                    RoundedRectangle(cornerRadius: cornerRadius).strokeBorder(color, lineWidth: lineWidth)
                }
            }
            .opacity(shown ? 1 : 0)
            .allowsHitTesting(false)
        }
        .help(shown ? Text("Standing \((standing ?? 0).formatted(.number.precision(.fractionLength(1)).sign(strategy: .always())))") : Text(verbatim: ""))
    }
}

// MARK: - Roll-in numbers

/// Shows a headline figure rolling into place the first time it appears. It starts at
/// the value's leading digit (1,234,567 → 1,000,000), which has the same number of
/// digits, so with tabular digits the text never changes width while it rolls. Use with
/// `eveNumeric` inside `content`, which does the rolling. Skipped under Reduce Motion.
struct EVERollIn<Content: View>: View {
    let value: Double
    @ViewBuilder let content: (Double) -> Content
    @State private var start: Double?
    @State private var hasAppeared = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(_ value: Double, @ViewBuilder content: @escaping (Double) -> Content) {
        self.value = value
        self.content = content
    }

    var body: some View {
        content(start ?? value)
            .onAppear {
                guard !hasAppeared else { return }
                hasAppeared = true
                guard !reduceMotion, abs(value) >= 10 else { return }
                start = Self.leadingDigit(value)
                Task {
                    try? await Task.sleep(for: .milliseconds(150))
                    start = nil
                }
            }
    }

    private static func leadingDigit(_ value: Double) -> Double {
        let magnitude = pow(10, floor(log10(abs(value))))
        return (value / magnitude).rounded(.towardZero) * magnitude
    }
}
