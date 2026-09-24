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

/// Three-step welcome shown once, right after the first character is added: pick a
/// faction theme, meet the ⌘K switcher, learn pinning. Each step is something the user
/// would otherwise only discover by accident.
struct OnboardingView: View {
    static let completedKey = "onboarding.completed"

    let characterName: String?
    let onFinish: () -> Void

    @Environment(ThemeManager.self) private var themeManager
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var step = 0

    private let stepCount = 3

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                switch step {
                case 0: themeStep.transition(stepTransition)
                case 1: switcherStep.transition(stepTransition)
                default: pinStep.transition(stepTransition)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(.horizontal, EVESpacing.xxl * 2)
            .padding(.top, EVESpacing.xxl * 1.5)

            footer
        }
        .frame(width: 560, height: 480)
        .background(EVEAmbientBackground())
        .animation(reduceMotion ? nil : EVEMotion.snappy, value: step)
        .animation(reduceMotion ? nil : EVEMotion.snappy, value: themeManager.faction)
    }

    private var stepTransition: AnyTransition {
        .asymmetric(insertion: .opacity.combined(with: .offset(x: 24)),
                    removal: .opacity.combined(with: .offset(x: -24)))
    }

    // MARK: Steps

    private var themeStep: some View {
        VStack(spacing: EVESpacing.xl) {
            stepHeader(
                symbol: "paintpalette.fill",
                title: characterName.map { "Welcome aboard, \($0)" } ?? String(localized: "Welcome to EVEOps"),
                message: "Pick the empire whose colors EVEOps should wear. You can change it any time in Settings."
            )
            HStack(spacing: EVESpacing.xl) {
                ForEach(FactionTheme.allCases) { faction in
                    let isSelected = themeManager.faction == faction
                    Button {
                        themeManager.faction = faction
                    } label: {
                        VStack(spacing: EVESpacing.sm) {
                            FactionCrestSwatch(faction: faction, size: 52)
                                .overlay(Circle().strokeBorder(faction.palette.accent, lineWidth: 2))
                                .overlay {
                                    if isSelected {
                                        Circle().strokeBorder(faction.palette.accent, lineWidth: 2).padding(-4)
                                    }
                                }
                                .scaleEffect(isSelected && !reduceMotion ? 1.06 : 1)
                            Text(faction.displayName)
                                .font(.caption)
                                .foregroundStyle(isSelected ? .primary : .secondary)
                        }
                    }
                    .buttonStyle(.plain)
                    .help(faction.tagline)
                    .accessibilityAddTraits(isSelected ? .isSelected : [])
                }
            }
            Text(themeManager.faction.tagline)
                .font(.callout)
                .foregroundStyle(.secondary)
                .contentTransition(.opacity)
        }
    }

    private var switcherStep: some View {
        VStack(spacing: EVESpacing.xl) {
            stepHeader(
                symbol: "magnifyingglass",
                title: String(localized: "Jump Anywhere"),
                message: "Press ⌘K from anywhere to open the quick switcher — type a screen, a system, an item, a pilot, or a command and hit Return."
            )
            HStack(spacing: EVESpacing.sm) {
                keyCap("⌘")
                keyCap("K")
            }
            VStack(alignment: .leading, spacing: EVESpacing.sm) {
                shortcutRow("⌘R", "Refresh the current screen")
                shortcutRow("⌘[  ⌘]", "Previous / next screen")
                shortcutRow("⌘0", "Back to the Dashboard")
            }
            .padding(EVESpacing.lg)
            .eveCard(cornerRadius: EVERadius.lg)
        }
    }

    private var pinStep: some View {
        VStack(spacing: EVESpacing.xl) {
            stepHeader(
                symbol: "pin.fill",
                title: String(localized: "Pin Your Favorites"),
                message: "Use the pin button in any screen's toolbar to add it to the Pinned group at the top of the sidebar."
            )
            HStack(spacing: EVESpacing.md) {
                ForEach(1...5, id: \.self) { n in
                    keyCap("⌘\(n)")
                }
            }
            Text("And ⌘1 through ⌘9 jump straight to the everyday screens — \(quickJumpNames).")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
    }

    /// "Location, Training, Skill Planner, and more" — the first few ⌘-number targets.
    private var quickJumpNames: String {
        let names = NavigationSection.quickJumpSlots.prefix(3).map(\.rawValue)
        return names.joined(separator: ", ") + String(localized: ", and more")
    }

    // MARK: Pieces

    private func stepHeader(symbol: String, title: String, message: LocalizedStringKey) -> some View {
        VStack(spacing: EVESpacing.md) {
            Image(systemName: symbol)
                .font(.system(size: 34, weight: .regular))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(themeManager.palette.accent)
                .frame(width: 72, height: 72)
                .background(themeManager.palette.accent.opacity(0.12), in: Circle())
                .accessibilityHidden(true)
            Text(title)
                .font(.title.bold())
                .multilineTextAlignment(.center)
            Text(message)
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func keyCap(_ label: String) -> some View {
        Text(label)
            .font(.system(.title3, design: .rounded, weight: .semibold))
            .frame(minWidth: 40, minHeight: 40)
            .padding(.horizontal, EVESpacing.sm)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: EVERadius.md))
            .overlay(RoundedRectangle(cornerRadius: EVERadius.md).strokeBorder(.primary.opacity(0.15)))
            .shadow(color: .black.opacity(0.15), radius: 0, y: 2)
    }

    private func shortcutRow(_ keys: String, _ label: LocalizedStringKey) -> some View {
        HStack(spacing: EVESpacing.lg) {
            Text(keys)
                .font(.callout.monospaced().weight(.semibold))
                .frame(width: 64, alignment: .leading)
            Text(label)
                .font(.callout)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: Footer

    private var footer: some View {
        HStack {
            Button("Skip") { onFinish() }
                .buttonStyle(.borderless)
                .foregroundStyle(.secondary)
                .opacity(step < stepCount - 1 ? 1 : 0)
                .disabled(step >= stepCount - 1)

            Spacer()

            HStack(spacing: EVESpacing.sm) {
                ForEach(0..<stepCount, id: \.self) { i in
                    Capsule()
                        .fill(i == step ? themeManager.palette.accent : Color.primary.opacity(0.2))
                        .frame(width: i == step ? 18 : 7, height: 7)
                }
            }
            .accessibilityElement()
            .accessibilityLabel(Text("Step \(step + 1) of \(stepCount)"))

            Spacer()

            HStack(spacing: EVESpacing.sm) {
                if step > 0 {
                    Button("Back") { step -= 1 }
                }
                Button(step < stepCount - 1 ? "Continue" : "Get Started") {
                    if step < stepCount - 1 { step += 1 } else { onFinish() }
                }
                .buttonStyle(.borderedProminent)
                .tint(themeManager.palette.accent)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(EVESpacing.xl)
        .background(.bar)
    }
}
