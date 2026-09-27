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
                        VStack(alignment: .leading, spacing: EVESpacing.xxs) {
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

// MARK: - Search field

/// The app's one search/filter field: magnifier, plain text field, clear button (or a
/// spinner while `isBusy`), on a rounded, appearance-adaptive fill. Edit › Find (⌘F)
/// focuses it. Screens had grown four different looks for this — plain, card, rounded
/// border, bare — so every filter in the app now reads as the same control.
///
/// Attach `.onChange(of:)` / `.onSubmit` to the field itself as you would a `TextField`.
struct EVESearchField: View {
    let prompt: Text
    @Binding var text: String
    var isBusy = false
    var controlSize: ControlSize = .regular
    /// Runs instead of the default "clear the text" when the clear button is pressed —
    /// for fields where clearing also resets a selection.
    var onClear: (() -> Void)?

    init(_ prompt: LocalizedStringKey, text: Binding<String>, isBusy: Bool = false,
         controlSize: ControlSize = .regular, onClear: (() -> Void)? = nil) {
        self.init(prompt: Text(prompt), text: text, isBusy: isBusy, controlSize: controlSize, onClear: onClear)
    }

    init(prompt: Text, text: Binding<String>, isBusy: Bool = false,
         controlSize: ControlSize = .regular, onClear: (() -> Void)? = nil) {
        self.prompt = prompt
        self._text = text
        self.isBusy = isBusy
        self.controlSize = controlSize
        self.onClear = onClear
    }

    private var isSmall: Bool { controlSize == .small || controlSize == .mini }

    var body: some View {
        HStack(spacing: EVESpacing.sm) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
                .imageScale(.small)
                .accessibilityHidden(true)
            TextField(text: $text) { prompt }
                .textFieldStyle(.plain)
                .eveFindTarget()
            if isBusy {
                ProgressView().controlSize(.mini)
            } else if !text.isEmpty {
                Button {
                    if let onClear { onClear() } else { text = "" }
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear Search")
                .help("Clear")
            }
        }
        .font(isSmall ? .caption : .body)
        .padding(.horizontal, EVESpacing.md)
        .padding(.vertical, isSmall ? 3 : 5)
        .background(EVEFill.track.opacity(0.6), in: RoundedRectangle(cornerRadius: EVERadius.md))
        .overlay(
            RoundedRectangle(cornerRadius: EVERadius.md)
                .strokeBorder(EVEFill.trackBorder, lineWidth: 0.5)
        )
    }
}

// MARK: - Find (⌘F)

private struct FindTargetModifier: ViewModifier {
    @FocusState private var isFocused: Bool
    @Environment(\.controlActiveState) private var activeState

    func body(content: Content) -> some View {
        content
            .focused($isFocused)
            .onChange(of: AppRouter.shared.findTick) { _, _ in
                // Only the focused window's field answers, so ⌘F in the Galaxy Market
                // Search window doesn't also grab the main window's search.
                if activeState == .key { isFocused = true }
            }
    }
}

extension View {
    /// Makes this text field the screen's search: Edit › Find (⌘F) focuses it.
    func eveFindTarget() -> some View { modifier(FindTargetModifier()) }
}
