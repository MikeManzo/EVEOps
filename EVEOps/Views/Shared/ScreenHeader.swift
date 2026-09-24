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

/// Where screen titles render. One switch for every screen, so the presentation can be
/// flipped without touching 40+ views.
/// - `.hybrid`: a display-size title (and subtitle) as the toolbar's leading item, controls
///   (refresh, pin) as its trailing capsule. The standard (small) toolbar title is removed
///   so it isn't shown twice; the window keeps its name for the Window menu.
/// - `.toolbar`: title, subtitle and controls all in the toolbar. Most compact, but macOS
///   fixes the toolbar title at a small size.
/// - `.inline`: everything in a large-title bar inside the content (the original look).
enum EVEScreenHeaderStyle {
    case hybrid, toolbar, inline

    static let current: EVEScreenHeaderStyle = .hybrid
}

private struct EVEScreenHeaderModifier<Trailing: View>: ViewModifier {
    let title: Text
    let subtitle: Text?
    let section: NavigationSection?
    @ViewBuilder var trailing: () -> Trailing

    /// The screen's title at display size, sitting in the toolbar row itself (leading edge,
    /// in line with the controls capsule) rather than in a band below it — the toolbar
    /// row is there anyway, so a separate header would just stack empty height on top.
    private var largeTitle: some View {
        HStack(alignment: .firstTextBaseline, spacing: EVESpacing.md) {
            title
                .font(.title.bold())
                .lineLimit(1)
            if let subtitle {
                subtitle
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .contentTransition(.opacity)
            }
        }
        .fixedSize()
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }

    /// Screen controls plus the pin, as one toolbar group so they share a single glass
    /// capsule. `isInToolbar` tells buttons that normally carry `.plain`/`.borderless`
    /// (pin, refresh) to keep the toolbar's own button style — padding, hit area, hover.
    @ToolbarContentBuilder
    private var toolbarControls: some ToolbarContent {
        ToolbarItemGroup(placement: .primaryAction) {
            Group {
                trailing()
                if let section {
                    PinToggleButton(section: section)
                }
            }
            .environment(\.isInToolbar, true)
        }
    }

    func body(content: Content) -> some View {
        switch EVEScreenHeaderStyle.current {
        case .hybrid:
            content
                .navigationTitle(title)
                .toolbar(removing: .title)
                .toolbar {
                    ToolbarItem(placement: .navigation) { largeTitle }
                        .sharedBackgroundVisibility(.hidden)
                    toolbarControls
                }
        case .toolbar:
            content
                .navigationTitle(title)
                .navigationSubtitle(subtitle ?? Text(verbatim: ""))
                .toolbar { toolbarControls }
        case .inline:
            content
                .safeAreaInset(edge: .top, spacing: 0) {
                    HStack(alignment: .firstTextBaseline, spacing: EVESpacing.md) {
                        VStack(alignment: .leading, spacing: 2) {
                            title.font(.largeTitle.bold())
                            if let subtitle {
                                subtitle.font(.subheadline).foregroundStyle(.secondary)
                            }
                        }
                        if let section { PinToggleButton(section: section) }
                        Spacer()
                        trailing()
                    }
                    .padding(.horizontal, EVESpacing.xl)
                    .padding(.vertical, EVESpacing.lg)
                    .background(.background)
                }
                .navigationTitle("")
        }
    }
}

extension View {
    /// Runtime-string variant (e.g. a title computed from a mode enum).
    func eveScreenHeader<Trailing: View>(
        verbatim title: String,
        subtitle: Text? = nil,
        section: NavigationSection? = nil,
        @ViewBuilder trailing: @escaping () -> Trailing
    ) -> some View {
        modifier(EVEScreenHeaderModifier(title: Text(title), subtitle: subtitle, section: section, trailing: trailing))
    }

    /// The screen's title bar: title, optional subtitle, the sidebar pin toggle for
    /// `section`, and trailing controls (refresh, status). Rendered per
    /// `EVEScreenHeaderStyle.current`.
    func eveScreenHeader<Trailing: View>(
        _ title: LocalizedStringKey,
        subtitle: Text? = nil,
        section: NavigationSection? = nil,
        @ViewBuilder trailing: @escaping () -> Trailing
    ) -> some View {
        modifier(EVEScreenHeaderModifier(title: Text(title), subtitle: subtitle, section: section, trailing: trailing))
    }

    func eveScreenHeader(
        _ title: LocalizedStringKey,
        subtitle: Text? = nil,
        section: NavigationSection? = nil
    ) -> some View {
        eveScreenHeader(title, subtitle: subtitle, section: section) { EmptyView() }
    }
}

extension EnvironmentValues {
    /// True for controls hosted in the window toolbar via `eveScreenHeader`. Buttons that
    /// apply `.plain`/`.borderless` for in-content use skip it there, so the toolbar's own
    /// button style (padding, hit area, glass hover) applies.
    @Entry var isInToolbar: Bool = false
}

extension View {
    /// Applies `style` except inside the window toolbar (see `isInToolbar`).
    func buttonStyleOutsideToolbar<S: PrimitiveButtonStyle>(_ style: S) -> some View {
        modifier(ButtonStyleOutsideToolbar(style: style))
    }
}

private struct ButtonStyleOutsideToolbar<S: PrimitiveButtonStyle>: ViewModifier {
    let style: S
    @Environment(\.isInToolbar) private var isInToolbar

    func body(content: Content) -> some View {
        if isInToolbar {
            content
        } else {
            content.buttonStyle(style)
        }
    }
}
