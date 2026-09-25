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
import Charts

// MARK: - Metrics

/// Spacing scale for padding and stack spacing. Values sit on a 2-pt grid with a 4-pt
/// rhythm for anything structural. Prefer these over raw literals in new code so panels
/// line up across screens.
enum EVESpacing {
    static let xxs: CGFloat = 2
    static let xs: CGFloat = 4
    static let sm: CGFloat = 6
    static let md: CGFloat = 8
    static let lg: CGFloat = 12
    static let xl: CGFloat = 16
    static let xxl: CGFloat = 24
}

/// Corner-radius scale. Screens had drifted onto a dozen different radii; everything now
/// snaps to one of these steps. Pick by the size of the shape, not by taste:
/// hairline for progress bars, xs for pills and chips, sm/md for rows and thumbnails,
/// lg/xl for cards, xxl for hero surfaces.
enum EVERadius {
    static let hairline: CGFloat = 2
    static let xs: CGFloat = 4
    static let sm: CGFloat = 6
    static let md: CGFloat = 8
    static let lg: CGFloat = 10
    static let xl: CGFloat = 12
    static let xxl: CGFloat = 14
}

// MARK: - Surfaces

/// Content surfaces. Glass (translucent materials, `.sidebar` list style) is reserved for
/// real sidebars and floating controls, per macOS 26 convention — everything in the
/// content area sits on these solid, appearance-adaptive fills so screens look alike no
/// matter how they're built (list, table or cards).
enum EVESurface {
    /// Side panels and inspectors within a screen (detail panes, plan panels).
    static var panel: some ShapeStyle { BackgroundStyle() }
    /// Header, filter and summary bars across a content pane — solid, one step apart
    /// from the panel so the bar still reads as a bar.
    static var bar: some ShapeStyle { BackgroundStyle().secondary }
}

// MARK: - Row density

/// List row density (Settings > General). Compact trims vertical padding on data-heavy
/// rows so dense screens (journal, mail, killmails, assets) fit ~30% more per screen,
/// in the spirit of Mail's list-preview setting.
enum EVERowDensity: String, CaseIterable, Identifiable {
    case comfortable, compact

    static let storageKey = "appearance.rowDensity"

    var id: String { rawValue }

    var title: LocalizedStringKey {
        switch self {
        case .comfortable: "Comfortable"
        case .compact:     "Compact"
        }
    }

    /// Vertical padding for a list row's content. Comfortable matches the rows' original
    /// padding, so the default look is unchanged.
    var rowPadding: CGFloat {
        switch self {
        case .comfortable: EVESpacing.xs
        case .compact:     1
        }
    }
}

extension EnvironmentValues {
    @Entry var eveRowDensity: EVERowDensity = .comfortable
}

private struct EVERowPaddingModifier: ViewModifier {
    @Environment(\.eveRowDensity) private var density
    func body(content: Content) -> some View {
        content.padding(.vertical, density.rowPadding)
    }
}

extension View {
    /// Vertical row padding that follows the user's row-density setting.
    func eveRowPadding() -> some View { modifier(EVERowPaddingModifier()) }
}

// MARK: - Typography

/// Named type scale. Sizes match what screens were already using as literals, so moving a
/// call site onto a token never changes how it looks — it just makes the hierarchy
/// explicit and editable in one place.
extension Font {
    /// 7 pt — map annotations and micro legends.
    static let eveNano = Font.system(size: 7)
    /// 7 pt bold.
    static let eveNanoBold = Font.system(size: 7, weight: .bold)
    /// 8 pt — the smallest readable secondary text.
    static let eveTiny = Font.system(size: 8)
    /// 8 pt bold — tiny badges and counters on icons.
    static let eveBadge = Font.system(size: 8, weight: .bold)
    /// 9 pt — dense table metadata, map labels.
    static let eveMicro = Font.system(size: 9)
    /// 9 pt bold — uppercase tags and tier labels.
    static let eveMicroBold = Font.system(size: 9, weight: .bold)
    /// 9 pt semibold.
    static let eveMicroSemibold = Font.system(size: 9, weight: .semibold)
    /// 10 pt — secondary detail lines.
    static let eveLabel = Font.system(size: 10)
    /// 10 pt medium.
    static let eveLabelMedium = Font.system(size: 10, weight: .medium)
    /// 10 pt semibold — small section headers.
    static let eveLabelSemibold = Font.system(size: 10, weight: .semibold)
    /// 10 pt bold.
    static let eveLabelBold = Font.system(size: 10, weight: .bold)
    /// 11 pt — compact body text.
    static let eveCaption = Font.system(size: 11)
    /// 11 pt medium.
    static let eveCaptionMedium = Font.system(size: 11, weight: .medium)
    /// 11 pt semibold.
    static let eveCaptionSemibold = Font.system(size: 11, weight: .semibold)
    /// 11 pt bold.
    static let eveCaptionBold = Font.system(size: 11, weight: .bold)
    /// 12 pt medium.
    static let eveCalloutMedium = Font.system(size: 12, weight: .medium)
    /// 12 pt semibold — dense row titles.
    static let eveCalloutSemibold = Font.system(size: 12, weight: .semibold)
    /// 13 pt semibold — row and card titles.
    static let eveRowTitle = Font.system(size: 13, weight: .semibold)
    /// 15 pt semibold.
    static let eveSubsectionTitle = Font.system(size: 15, weight: .semibold)
    /// 17 pt semibold — card headline figures.
    static let eveSectionTitle = Font.system(size: 17, weight: .semibold)
    /// Monospaced 9/10/11 pt — EFT text, IDs, raw log lines.
    static let eveCodeSmall = Font.system(size: 9, design: .monospaced)
    static let eveCode = Font.system(size: 10, design: .monospaced)
    static let eveCodeLarge = Font.system(size: 11, design: .monospaced)
    /// 13 pt rounded bold, tabular — the value inside a small metric tile.
    static let eveTileValue = Font.system(size: 13, weight: .bold, design: .rounded).monospacedDigit()
    /// Rounded, bold, tabular — a figure in a row of compact stat cards.
    static let eveStatCompact = Font.system(.title3, design: .rounded, weight: .bold).monospacedDigit()
    /// Rounded, bold, tabular — the headline number on a stat card.
    static let eveStat = Font.system(.title2, design: .rounded, weight: .bold).monospacedDigit()
    /// Rounded, bold, tabular — the single hero figure on a screen (net worth, total SP).
    static let eveHeroStat = Font.system(.title, design: .rounded, weight: .bold).monospacedDigit()
    /// Icon size for full-pane empty and placeholder states.
    static let eveEmptyStateIcon = Font.system(size: 40, weight: .light)
}

// MARK: - Motion

enum EVEMotion {
    /// Default spring for state changes inside a card.
    static let snappy = Animation.snappy(duration: 0.28)
    /// Section-to-section content swaps.
    static let section = Animation.easeInOut(duration: 0.22)
    /// Value changes on animated numbers.
    static let numeric = Animation.smooth(duration: 0.45)
}

extension AnyTransition {
    /// Fade with a short upward drift — used when the main pane switches sections.
    ///
    /// Deliberately not a scale: a screen full of AppKit-backed controls (text fields,
    /// segmented pickers, progress indicators) gets measured under the scale transform
    /// mid-animation, and AppKit logs "maximum length … doesn't satisfy min <= max" for
    /// every control whose fixed height comes out fractional. An offset moves controls
    /// without resizing them.
    static var eveSection: AnyTransition {
        .opacity.combined(with: .offset(y: 6))
    }
}

// MARK: - Animated numbers

private struct EVENumericModifier<V: Equatable>: ViewModifier {
    let value: V
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .monospacedDigit()
            .contentTransition(reduceMotion ? .identity : .numericText())
            .animation(reduceMotion ? nil : EVEMotion.numeric, value: value)
    }
}

extension View {
    /// Tabular digits plus a rolling-counter transition whenever `value` changes. Use on
    /// Text showing a live figure (wallet, SP, prices) so updates read as a change rather
    /// than a flicker.
    func eveNumeric<V: Equatable>(_ value: V) -> some View {
        modifier(EVENumericModifier(value: value))
    }
}

// MARK: - Security badge

/// Solar-system security status as a compact pill — tabular digits on a tinted fill of the
/// in-game security color. The house style everywhere a system's security is shown.
struct EVESecurityBadge: View {
    let status: Double
    var compact: Bool = false
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let color = eveSecurityColor(status)
        // The in-game hues (bright yellow at 0.5, cyan at 1.0) are made for dark space;
        // as text on a light window they wash out, so darken the digits in Light mode
        // while the tinted fill keeps the true game color.
        let textColor = colorScheme == .light ? color.mix(with: .black, by: 0.4) : color
        Text(status, format: .number.precision(.fractionLength(1)))
            .font(compact ? .eveMicroBold.monospacedDigit() : .eveLabelBold.monospacedDigit())
            .foregroundStyle(textColor)
            .padding(.horizontal, compact ? EVESpacing.xs : EVESpacing.sm)
            .padding(.vertical, 1)
            .background(color.opacity(0.16), in: RoundedRectangle(cornerRadius: EVERadius.xs))
            .overlay(RoundedRectangle(cornerRadius: EVERadius.xs).strokeBorder(color.opacity(0.35), lineWidth: 0.5))
            .accessibilityLabel(Text("Security \(status, format: .number.precision(.fractionLength(1)))"))
    }
}

// MARK: - Standing

/// Standing value (-10...+10) as a signed, tinted number — e.g. "+7.5" in light blue.
struct EVEStandingBadge: View {
    let standing: Double

    var body: some View {
        let color = eveStandingColor(standing)
        Text(standing, format: .number.precision(.fractionLength(1)).sign(strategy: .always(includingZero: false)))
            .font(.eveLabelBold.monospacedDigit())
            .foregroundStyle(color)
            .padding(.horizontal, EVESpacing.sm)
            .padding(.vertical, 1)
            .background(color.opacity(0.14), in: RoundedRectangle(cornerRadius: EVERadius.xs))
            .accessibilityLabel(Text("Standing \(standing, format: .number.precision(.fractionLength(1)))"))
    }
}

/// Diverging standing bar: centered at neutral, filling right (blue) for positive and left
/// (orange/red) for negative. A left-origin bar made -10 read as "empty" rather than hostile.
struct EVEStandingBar: View {
    let standing: Double
    var width: CGFloat = 64
    var height: CGFloat = 5

    var body: some View {
        let fraction = min(max(standing / 10, -1), 1)
        let half = width / 2
        ZStack {
            Capsule().fill(.quaternary)
            HStack(spacing: 0) {
                ZStack(alignment: .trailing) {
                    Color.clear
                    if fraction < 0 {
                        Capsule().fill(eveStandingColor(standing)).frame(width: half * -fraction)
                    }
                }
                ZStack(alignment: .leading) {
                    Color.clear
                    if fraction > 0 {
                        Capsule().fill(eveStandingColor(standing)).frame(width: half * fraction)
                    }
                }
            }
            Rectangle().fill(.secondary.opacity(0.5)).frame(width: 1)
        }
        .frame(width: width, height: height)
        .accessibilityHidden(true)
    }
}

// MARK: - Section title

/// Small uppercase secondary section title — the one header style for detail panes and
/// inspectors across the app (Xcode/Finder inspector convention).
struct EVESectionTitle: View {
    let title: Text

    init(_ title: LocalizedStringKey) { self.title = Text(title) }
    init(verbatim title: String) { self.title = Text(title) }

    var body: some View {
        title
            .font(.eveLabelSemibold)
            .textCase(.uppercase)
            .kerning(0.4)
            .foregroundStyle(.secondary)
            .accessibilityAddTraits(.isHeader)
    }
}

/// Label/value row for detail panes: secondary label, primary value, value selectable.
struct EVEInfoRow: View {
    let label: Text
    let value: String

    init(_ label: LocalizedStringKey, _ value: String) {
        self.label = Text(label)
        self.value = value
    }

    init(verbatim label: String, _ value: String) {
        self.label = Text(label)
        self.value = value
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: EVESpacing.md) {
            label
                .foregroundStyle(.secondary)
            Spacer(minLength: EVESpacing.md)
            Text(value)
                .multilineTextAlignment(.trailing)
                .textSelection(.enabled)
        }
        .font(.callout)
    }
}

// MARK: - Inspector section

/// Section in a detail/inspector pane: a small uppercase secondary title over content,
/// in the style of Xcode's and Finder's inspectors. One header style for every section,
/// rather than a differently tinted label per section.
struct EVEInspectorSection<Content: View>: View {
    let title: LocalizedStringKey
    @ViewBuilder var content: () -> Content

    init(_ title: LocalizedStringKey, @ViewBuilder content: @escaping () -> Content) {
        self.title = title
        self.content = content
    }

    var body: some View {
        VStack(alignment: .leading, spacing: EVESpacing.md) {
            EVESectionTitle(title)
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Progress bar

/// Thin capsule progress bar drawn in SwiftUI. Use instead of
/// `ProgressView(value:).frame(height:)` when a bar must be thinner than AppKit's linear
/// indicator: forcing that control's fixed height logs a "min <= max" layout assertion.
struct EVEProgressBar: View {
    let value: Double
    var tint: Color = .eveThemeAccent
    var height: CGFloat = 3

    var body: some View {
        let clamped = value.isFinite ? min(max(value, 0), 1) : 0
        Capsule()
            .fill(tint.opacity(0.18))
            .overlay(alignment: .leading) {
                GeometryReader { geo in
                    Capsule()
                        .fill(tint)
                        .frame(width: geo.size.width * clamped)
                }
            }
            .frame(height: height)
            .animation(.smooth(duration: 0.4), value: clamped)
            .accessibilityElement()
            .accessibilityValue(Text(clamped, format: .percent.precision(.fractionLength(0))))
    }
}

// MARK: - Truncation tooltip

private struct TruncationHelpModifier: ViewModifier {
    let fullText: String
    @State private var fullWidth: CGFloat = 0
    @State private var shownWidth: CGFloat = 0

    func body(content: Content) -> some View {
        content
            .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { shownWidth = $0 }
            .background(alignment: .leading) {
                // The same view laid out at its ideal (untruncated) width, invisible — the
                // only reliable way to learn whether SwiftUI had to truncate the real one.
                content
                    .fixedSize(horizontal: true, vertical: false)
                    .hidden()
                    .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { fullWidth = $0 }
                    .accessibilityHidden(true)
            }
            .help(fullWidth > shownWidth + 0.5 ? fullText : "")
    }
}

extension View {
    /// Shows `fullText` as a tooltip only when this single-line text is actually cut off
    /// with "…", as Finder does — no redundant tooltips on names that fit.
    func eveTruncationHelp(_ fullText: String) -> some View {
        modifier(TruncationHelpModifier(fullText: fullText))
    }
}

// MARK: - Scroll edge fade

private struct EVEEdgeFadeModifier: ViewModifier {
    let width: CGFloat
    @State private var fadesLeading = false
    @State private var fadesTrailing = false

    private struct Edges: Equatable { let leading: Bool; let trailing: Bool }

    func body(content: Content) -> some View {
        content
            .onScrollGeometryChange(for: Edges.self) { geo in
                let maxOffset = geo.contentSize.width - geo.containerSize.width
                return Edges(
                    leading: geo.contentOffset.x > 1,
                    trailing: maxOffset > 1 && geo.contentOffset.x < maxOffset - 1
                )
            } action: { _, edges in
                fadesLeading = edges.leading
                fadesTrailing = edges.trailing
            }
            .mask {
                HStack(spacing: 0) {
                    LinearGradient(colors: [.black.opacity(fadesLeading ? 0 : 1), .black],
                                   startPoint: .leading, endPoint: .trailing)
                        .frame(width: width)
                    Rectangle()
                    LinearGradient(colors: [.black, .black.opacity(fadesTrailing ? 0 : 1)],
                                   startPoint: .leading, endPoint: .trailing)
                        .frame(width: width)
                }
            }
            .animation(.easeOut(duration: 0.15), value: fadesLeading)
            .animation(.easeOut(duration: 0.15), value: fadesTrailing)
    }
}

extension View {
    /// Fades a horizontal `ScrollView`'s edges only where more content lies beyond them,
    /// so a chip row that overflows reads as scrollable instead of looking clipped. Apply
    /// to the `ScrollView` itself.
    func eveEdgeFade(width: CGFloat = 28) -> some View {
        modifier(EVEEdgeFadeModifier(width: width))
    }
}

// MARK: - Menu picker

/// One choice in an `EVEMenuPicker`.
struct EVEMenuOption<Value: Hashable>: Identifiable {
    let value: Value
    let title: Text
    var systemImage: String? = nil
    /// A custom icon (e.g. a faction crest) — takes precedence over `systemImage`.
    var image: Image? = nil
    /// Draw a separator above this option (e.g. between "All" and the specific choices).
    var dividerBefore = false

    var id: Value { value }

    init(_ value: Value, _ title: LocalizedStringKey, systemImage: String? = nil, dividerBefore: Bool = false) {
        self.value = value
        self.title = Text(title)
        self.systemImage = systemImage
        self.dividerBefore = dividerBefore
    }

    init(_ value: Value, verbatim title: String, systemImage: String? = nil, image: Image? = nil, dividerBefore: Bool = false) {
        self.value = value
        self.title = Text(title)
        self.systemImage = systemImage
        self.image = image
        self.dividerBefore = dividerBefore
    }
}

/// A popup picker that follows the faction theme end to end.
///
/// Why not `Picker(.menu)`: on macOS it's an AppKit popup button whose chevron ignores
/// `.tint`, and its open menu is an `NSMenu` highlighted in the app's *static*
/// AccentColor asset — macOS has no API to change an app's accent at runtime, so no
/// native menu can follow the theme. This draws both the control and the open list in
/// SwiftUI (a popover), themed throughout: accent chevron, accent hover/selection
/// highlight, accent checkmark. ↑/↓ move, Return chooses, Escape closes.
///
/// Set `EVEMenuPicker.usesNativeMenu` to fall back to a native menu everywhere.
struct EVEMenuPicker<Value: Hashable>: View {
    static var usesNativeMenu: Bool { false }

    let title: LocalizedStringKey
    @Binding var selection: Value
    let options: [EVEMenuOption<Value>]

    @Environment(ThemeManager.self) private var themeManager
    @Environment(\.isEnabled) private var isEnabled
    @State private var isHovering = false
    @State private var isOpen = false

    init(_ title: LocalizedStringKey, selection: Binding<Value>, options: [EVEMenuOption<Value>]) {
        self.title = title
        self._selection = selection
        self.options = options
    }

    private var current: EVEMenuOption<Value>? { options.first { $0.value == selection } }

    var body: some View {
        if Self.usesNativeMenu {
            nativeMenu
        } else {
            Button { isOpen.toggle() } label: { controlLabel }
                .buttonStyle(.plain)
                .fixedSize()
                .onHover { isHovering = $0 }
                .animation(.easeOut(duration: 0.12), value: isHovering)
                .popover(isPresented: $isOpen, arrowEdge: .bottom) {
                    EVEMenuList(options: options, selection: $selection, accent: themeManager.palette.accent) {
                        isOpen = false
                    }
                }
                .accessibilityLabel(Text(title))
                .accessibilityValue(current?.title ?? Text(verbatim: ""))
                .accessibilityHint(Text("Opens a list of choices"))
        }
    }

    private var controlLabel: some View {
        HStack(spacing: EVESpacing.sm) {
            if let image = current?.image {
                image.resizable().interpolation(.high)
                    .frame(width: 14, height: 14)
                    .clipShape(RoundedRectangle(cornerRadius: 3))
            } else if let symbol = current?.systemImage {
                Image(systemName: symbol).foregroundStyle(.secondary)
            }
            (current?.title ?? Text(verbatim: "—"))
                .lineLimit(1)
            Image(systemName: "chevron.up.chevron.down")
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(isEnabled ? themeManager.palette.accent : Color.secondary)
        }
        .font(.callout)
        .padding(.horizontal, EVESpacing.md + 2)
        .padding(.vertical, 4)
        .background(Color.primary.opacity(isHovering || isOpen ? 0.1 : 0.06),
                    in: RoundedRectangle(cornerRadius: EVERadius.sm))
        .contentShape(Rectangle())
    }

    private var nativeMenu: some View {
        Menu {
            Picker(title, selection: $selection) {
                ForEach(options) { option in
                    if option.dividerBefore { Divider() }
                    if let symbol = option.systemImage {
                        Label { option.title } icon: { Image(systemName: symbol) }.tag(option.value)
                    } else {
                        option.title.tag(option.value)
                    }
                }
            }
            .pickerStyle(.inline)
            .labelsHidden()
        } label: { controlLabel }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
    }
}

/// The open list of an `EVEMenuPicker`: rows drawn in SwiftUI so hover, keyboard focus
/// and the selected checkmark all use the faction accent.
private struct EVEMenuList<Value: Hashable>: View {
    let options: [EVEMenuOption<Value>]
    @Binding var selection: Value
    let accent: Color
    let dismiss: () -> Void

    @State private var highlighted: Value?
    @FocusState private var focused: Bool

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 1) {
                    ForEach(options) { option in
                        if option.dividerBefore {
                            Divider().padding(.vertical, EVESpacing.xs).padding(.horizontal, EVESpacing.md)
                        }
                        row(option).id(option.value)
                    }
                }
                .padding(EVESpacing.xs + 1)
            }
            .frame(minWidth: 200)
            .frame(maxHeight: 420)
            .fixedSize(horizontal: true, vertical: options.count <= 14)
            .focusable()
            .focusEffectDisabled()
            .focused($focused)
            .onAppear {
                highlighted = selection
                focused = true
                proxy.scrollTo(selection, anchor: .center)
            }
            .onKeyPress(.downArrow) { move(1, proxy); return .handled }
            .onKeyPress(.upArrow) { move(-1, proxy); return .handled }
            .onKeyPress(.return) {
                if let highlighted { choose(highlighted) }
                return .handled
            }
            .onKeyPress(.escape) { dismiss(); return .handled }
        }
    }

    private func row(_ option: EVEMenuOption<Value>) -> some View {
        let isHighlighted = highlighted == option.value
        let isSelected = selection == option.value
        return HStack(spacing: EVESpacing.sm) {
            Image(systemName: "checkmark")
                .font(.caption.weight(.bold))
                .foregroundStyle(isHighlighted ? Color.white : accent)
                .opacity(isSelected ? 1 : 0)
                .frame(width: 12)
            if let image = option.image {
                image.resizable().interpolation(.high)
                    .frame(width: 16, height: 16)
                    .clipShape(RoundedRectangle(cornerRadius: 3))
                    .frame(width: 18)
            } else if let symbol = option.systemImage {
                Image(systemName: symbol)
                    .foregroundStyle(isHighlighted ? Color.white : accent)
                    .frame(width: 18)
            }
            option.title
                .foregroundStyle(isHighlighted ? Color.white : Color.primary)
                .lineLimit(1)
            Spacer(minLength: EVESpacing.lg)
        }
        .font(.body)
        .padding(.horizontal, EVESpacing.sm)
        .padding(.vertical, 5)
        .background(
            RoundedRectangle(cornerRadius: EVERadius.sm)
                .fill(isHighlighted ? accent : .clear)
        )
        .contentShape(Rectangle())
        .onHover { if $0 { highlighted = option.value } }
        .onTapGesture { choose(option.value) }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }

    private func move(_ delta: Int, _ proxy: ScrollViewProxy) {
        guard !options.isEmpty else { return }
        let index = options.firstIndex { $0.value == highlighted } ?? -1
        let next = options[min(max(index + delta, 0), options.count - 1)].value
        highlighted = next
        proxy.scrollTo(next)
    }

    private func choose(_ value: Value) {
        selection = value
        dismiss()
    }
}

// MARK: - Segmented pickers

extension View {
    /// Segmented picker style, pinned to its natural height. AppKit's segmented control
    /// has a fixed height; when SwiftUI stretches it to a row's fractional height (for
    /// example while a spinner or progress bar sits beside it) AppKit logs
    /// "has a maximum length … that doesn't satisfy min <= max". Width is unaffected, so
    /// full-width pickers still stretch.
    func eveSegmentedPicker() -> some View {
        pickerStyle(.segmented)
            .fixedSize(horizontal: false, vertical: true)
    }
}

// MARK: - Hover

private struct EVEHoverModifier: ViewModifier {
    let cornerRadius: CGFloat
    let lift: Bool
    @Environment(ThemeManager.self) private var themeManager
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isHovering = false

    func body(content: Content) -> some View {
        content
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius)
                    .fill(themeManager.palette.accent.opacity(isHovering ? 0.08 : 0))
                    .allowsHitTesting(false)
            }
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius)
                    .strokeBorder(themeManager.palette.accent.opacity(isHovering ? 0.7 : 0), lineWidth: 1.5)
                    .allowsHitTesting(false)
            }
            .shadow(color: themeManager.palette.accent.opacity(lift && isHovering ? 0.25 : 0), radius: 8)
            .scaleEffect(lift && isHovering && !reduceMotion ? 1.015 : 1)
            .animation(.easeOut(duration: 0.15), value: isHovering)
            .onHover { isHovering = $0 }
            .pointerStyle(.link)
    }
}

extension View {
    /// Hover affordance for clickable cards and rows: a faint fill, an accent border,
    /// and (optionally) a tiny lift. Apply after the card's background so the overlay
    /// follows its shape.
    func eveHoverable(cornerRadius: CGFloat = EVERadius.xl, lift: Bool = false) -> some View {
        modifier(EVEHoverModifier(cornerRadius: cornerRadius, lift: lift))
    }
}

// MARK: - Empty state

/// House style for "nothing here" and "pick something" panes — a thin wrapper around
/// `ContentUnavailableView` so every empty pane shares one layout, icon weight and tint.
struct EVEEmptyState<Actions: View>: View {
    let title: Text
    let systemImage: String
    var message: Text?
    var tint: Color?
    @ViewBuilder var actions: () -> Actions

    init(
        title: Text,
        systemImage: String,
        message: Text? = nil,
        tint: Color? = nil,
        @ViewBuilder actions: @escaping () -> Actions
    ) {
        self.title = title
        self.systemImage = systemImage
        self.message = message
        self.tint = tint
        self.actions = actions
    }

    init(
        _ title: LocalizedStringKey,
        systemImage: String,
        message: Text? = nil,
        tint: Color? = nil,
        @ViewBuilder actions: @escaping () -> Actions
    ) {
        self.init(title: Text(title), systemImage: systemImage, message: message, tint: tint, actions: actions)
    }

    var body: some View {
        ContentUnavailableView {
            Label {
                title
            } icon: {
                Image(systemName: systemImage)
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(tint ?? .secondary)
            }
        } description: {
            if let message { message }
        } actions: {
            actions()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

extension EVEEmptyState where Actions == EmptyView {
    init(title: Text, systemImage: String, message: Text? = nil, tint: Color? = nil) {
        self.init(title: title, systemImage: systemImage, message: message, tint: tint) { EmptyView() }
    }

    init(_ title: LocalizedStringKey, systemImage: String, message: Text? = nil, tint: Color? = nil) {
        self.init(title: Text(title), systemImage: systemImage, message: message, tint: tint) { EmptyView() }
    }

    init(_ title: LocalizedStringKey, systemImage: String, message: LocalizedStringKey, tint: Color? = nil) {
        self.init(title: Text(title), systemImage: systemImage, message: Text(message), tint: tint) { EmptyView() }
    }

    /// Runtime-string title (e.g. a caller-supplied `emptyMessage`).
    init<S: StringProtocol>(verbatim title: S, systemImage: String, message: Text? = nil, tint: Color? = nil) {
        self.init(title: Text(title), systemImage: systemImage, message: message, tint: tint) { EmptyView() }
    }
}

// MARK: - Portraits

extension LinearGradient {
    /// Top-lit accent gradient used to ring portraits and logos.
    static func evePortraitRing(_ accent: Color) -> LinearGradient {
        LinearGradient(
            colors: [accent.opacity(0.95), accent.opacity(0.35), .white.opacity(0.15)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
}

extension View {
    /// Faction-tinted ring for character portraits and corp logos — follows the active
    /// theme instead of a flat white hairline.
    func evePortraitRing(cornerRadius: CGFloat, accent: Color, lineWidth: CGFloat = 1.5) -> some View {
        overlay(
            RoundedRectangle(cornerRadius: cornerRadius)
                .strokeBorder(LinearGradient.evePortraitRing(accent), lineWidth: lineWidth)
        )
    }

    /// Circular variant of `evePortraitRing`.
    func evePortraitRingCircle(accent: Color, lineWidth: CGFloat = 1.5) -> some View {
        overlay(Circle().strokeBorder(LinearGradient.evePortraitRing(accent), lineWidth: lineWidth))
    }
}

// MARK: - Hero backdrop

/// Blurred, faction-vignetted image behind a detail screen's header — a ship render,
/// a portrait or a faction crest. Purely decorative: no hit testing, hidden from
/// accessibility, and falls back to a plain accent gradient while the image loads.
struct EVEHeroBackdrop: View {
    let url: URL?
    var height: CGFloat = 160
    var blur: CGFloat = 18

    @Environment(ThemeManager.self) private var themeManager
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let accent = themeManager.palette.accent
        // Dark mode seats the image with a black vignette; on a light card that reads as
        // grime, so Light mode vignettes with the accent tint alone.
        let vignetteEdge: Color = colorScheme == .dark ? .black.opacity(0.35) : accent.opacity(0.12)
        ZStack {
            LinearGradient(
                colors: [accent.opacity(0.35), accent.opacity(0.05)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            if let url {
                CachedAsyncImage(url: url) { phase in
                    if let image = phase.image {
                        image.resizable()
                            .aspectRatio(contentMode: .fill)
                            .blur(radius: blur)
                            .saturation(0.9)
                            .opacity(0.55)
                            .transition(.opacity)
                    }
                }
            }
            RadialGradient(
                colors: [.clear, accent.opacity(0.18), vignetteEdge],
                center: .center,
                startRadius: 40,
                endRadius: 420
            )
        }
        // Fade out through a mask rather than painting a window-colored gradient, so the
        // backdrop blends into whatever surface sits behind it (card material or window).
        .mask(
            LinearGradient(
                colors: [.black, .black.opacity(0.6), .clear],
                startPoint: .top,
                endPoint: .bottom
            )
        )
        .frame(height: height)
        .frame(maxWidth: .infinity)
        .clipped()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

extension View {
    /// Places an `EVEHeroBackdrop` behind the top of this view.
    func eveHeroBackdrop(_ url: URL?, height: CGFloat = 160) -> some View {
        background(alignment: .top) {
            EVEHeroBackdrop(url: url, height: height)
        }
    }
}

// MARK: - Ambient background

/// Optional deep-space backdrop for the main content area: a sparse, deterministic
/// starfield (Dark) or chart-style dot grid (Light) over a faint faction-tinted nebula. Static (no animation), so it costs one
/// Canvas draw per resize and never fights Reduce Motion. Off by default — enabled from
/// Settings > General.
struct EVEAmbientBackground: View {
    @Environment(ThemeManager.self) private var themeManager
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        if reduceTransparency {
            Color.clear
        } else {
            let accent = themeManager.palette.accent
            let isDark = colorScheme == .dark
            ZStack {
                RadialGradient(
                    colors: [accent.opacity(isDark ? 0.10 : 0.06), .clear],
                    center: UnitPoint(x: 0.85, y: 0.05),
                    startRadius: 0,
                    endRadius: 700
                )
                RadialGradient(
                    colors: [accent.opacity(isDark ? 0.06 : 0.03), .clear],
                    center: UnitPoint(x: 0.1, y: 0.95),
                    startRadius: 0,
                    endRadius: 600
                )
                if !isDark {
                    // Light mode: a faint navigation-chart dot grid instead of stars —
                    // white stars vanish on a light window, and a grid keeps the
                    // "star map" feel without competing with content.
                    Canvas(rendersAsynchronously: true) { context, size in
                        let spacing: CGFloat = 22
                        var y: CGFloat = spacing / 2
                        var row = 0
                        while y < size.height {
                            var x: CGFloat = row.isMultiple(of: 2) ? spacing / 2 : spacing
                            while x < size.width {
                                context.fill(
                                    Path(ellipseIn: CGRect(x: x - 0.75, y: y - 0.75, width: 1.5, height: 1.5)),
                                    with: .color(.black.opacity(0.07))
                                )
                                x += spacing
                            }
                            y += spacing * 0.866   // hex packing
                            row += 1
                        }
                    }
                    .mask(
                        RadialGradient(
                            colors: [.black, .black.opacity(0.25)],
                            center: UnitPoint(x: 0.85, y: 0.05),
                            startRadius: 0,
                            endRadius: 900
                        )
                    )
                }
                if isDark {
                    Canvas(rendersAsynchronously: true) { context, size in
                        var rng = SeededGenerator(seed: 0xE7E0_95)
                        let count = Int(size.width * size.height / 5200)
                        for _ in 0..<count {
                            let x = CGFloat.random(in: 0...size.width, using: &rng)
                            let y = CGFloat.random(in: 0...size.height, using: &rng)
                            let r = CGFloat.random(in: 0.3...1.1, using: &rng)
                            let a = Double.random(in: 0.08...0.45, using: &rng)
                            context.fill(
                                Path(ellipseIn: CGRect(x: x, y: y, width: r * 2, height: r * 2)),
                                with: .color(.white.opacity(a))
                            )
                        }
                    }
                }
            }
            .ignoresSafeArea()
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        }
    }
}

/// Small deterministic PRNG (SplitMix64) so the starfield is identical on every launch
/// and every redraw instead of reshuffling on resize.
private struct SeededGenerator: RandomNumberGenerator {
    private var state: UInt64
    init(seed: UInt64) { state = seed }
    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}

// MARK: - Charts

extension ShapeStyle where Self == LinearGradient {
    /// Vertical fade used under every line/area series so charts share one fill style.
    static func eveAreaFill(_ color: Color) -> LinearGradient {
        LinearGradient(
            colors: [color.opacity(0.28), color.opacity(0.02)],
            startPoint: .top,
            endPoint: .bottom
        )
    }
}

extension View {
    /// Standard ISK value axis: compact labels (1.2B, 450M) on light grid lines, trailing.
    func eveISKYAxis(desiredCount: Int = 4) -> some View {
        chartYAxis {
            AxisMarks(position: .trailing, values: .automatic(desiredCount: desiredCount)) { value in
                AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5, dash: [2, 3]))
                    .foregroundStyle(.secondary.opacity(0.4))
                AxisValueLabel {
                    if let d = value.as(Double.self) {
                        Text(d.formatted(.number.notation(.compactName)))
                            .font(.eveMicro)
                            .monospacedDigit()
                    }
                }
            }
        }
    }

    /// Standard date axis: abbreviated month + day, sparse ticks, no vertical grid noise.
    func eveDateXAxis(desiredCount: Int = 4) -> some View {
        chartXAxis {
            AxisMarks(values: .automatic(desiredCount: desiredCount)) { _ in
                AxisTick(stroke: StrokeStyle(lineWidth: 0.5))
                AxisValueLabel(format: .dateTime.month(.abbreviated).day())
                    .font(.eveMicro)
            }
        }
    }
}

/// Callout bubble for a hovered chart point — shared so every interactive chart's
/// tooltip looks the same.
struct EVEChartCallout: View {
    let title: String
    let value: String
    var tint: Color = .eveThemeAccent

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(title)
                .font(.eveMicro)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.eveCaptionSemibold)
                .monospacedDigit()
                .foregroundStyle(tint)
        }
        .padding(.horizontal, EVESpacing.sm)
        .padding(.vertical, EVESpacing.xs)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: EVERadius.sm))
        .overlay(RoundedRectangle(cornerRadius: EVERadius.sm).strokeBorder(tint.opacity(0.35), lineWidth: 0.5))
        .shadow(color: .black.opacity(0.2), radius: 4, y: 2)
    }
}

// MARK: - Chart accessibility

/// VoiceOver audio-graph support for a date → value series: a spoken summary (range,
/// start/end, overall change) plus data points VoiceOver can step through or play as tones.
struct EVETimeSeriesChartDescriptor: AXChartDescriptorRepresentable {
    let title: String
    let points: [(date: Date, value: Double)]
    /// Formats a value for speech, e.g. ISK abbreviations.
    let format: @Sendable (Double) -> String

    func makeChartDescriptor() -> AXChartDescriptor {
        let dates = points.map(\.date)
        let values = points.map(\.value)
        let minDate = dates.min() ?? .now
        let maxDate = dates.max() ?? .now
        let minValue = values.min() ?? 0
        let maxValue = values.max() ?? 0

        let xAxis = AXNumericDataAxisDescriptor(
            title: String(localized: "Date"),
            range: minDate.timeIntervalSince1970...max(maxDate.timeIntervalSince1970, minDate.timeIntervalSince1970 + 1),
            gridlinePositions: []
        ) { Date(timeIntervalSince1970: $0).formatted(date: .abbreviated, time: .omitted) }

        let yAxis = AXNumericDataAxisDescriptor(
            title: title,
            range: minValue...max(maxValue, minValue + 1),
            gridlinePositions: []
        ) { format($0) }

        let series = AXDataSeriesDescriptor(
            name: title,
            isContinuous: true,
            dataPoints: points.map { AXDataPoint(x: $0.date.timeIntervalSince1970, y: $0.value) }
        )

        var summary = String(localized: "\(points.count) points from \(format(minValue)) to \(format(maxValue)).")
        if let first = points.first, let last = points.last, first.value != 0 {
            let change = (last.value - first.value) / abs(first.value)
            let direction = change >= 0 ? String(localized: "up") : String(localized: "down")
            summary += " " + String(localized: "Overall \(direction) \(abs(change).formatted(.percent.precision(.fractionLength(1)))), ending at \(format(last.value)).")
        }

        return AXChartDescriptor(title: title, summary: summary, xAxis: xAxis, yAxis: yAxis,
                                 additionalAxes: [], series: [series])
    }
}

extension View {
    /// Makes a date/value chart explorable as a VoiceOver audio graph.
    func eveChartAccessibility(_ title: String, points: [(date: Date, value: Double)],
                               format: @escaping @Sendable (Double) -> String = { EVEFormatters.formatISKShort($0) }) -> some View {
        accessibilityChartDescriptor(EVETimeSeriesChartDescriptor(title: title, points: points, format: format))
    }
}
