// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import SwiftUI

/// Central design tokens: one place for text sizes and spacing so panels
/// read larger and more breathable. New and migrated views use `DS`;
/// unmigrated views keep their literals until their panel is adopted.
enum DS {
    enum Font {
        /// Card headings on Settings pages (was `.headline`, ~13).
        static let cardTitle = SwiftUI.Font.system(size: 15, weight: .semibold)
        /// Row titles in settings and panels (was implicit body, ~13).
        static let rowTitle = SwiftUI.Font.system(size: 14, weight: .regular)
        /// A palette result row's title: Tinycast's 13pt body, one step
        /// quieter than a settings row so a long list stays dense.
        static let resultRowTitle = SwiftUI.Font.system(size: 13, weight: .regular)
        /// A palette row's trailing kind label or secondary caption.
        static let resultRowTrailing = SwiftUI.Font.system(size: 12, weight: .regular)
        /// A palette row's accent value, such as a sum's result.
        static let resultRowValue = SwiftUI.Font.system(size: 12, weight: .semibold, design: .rounded)
        /// A symbol drawn in a palette row's icon slot.
        static let resultRowGlyph = SwiftUI.Font.system(size: 14, weight: .medium)
        /// Standard body text, and the point size for `SearchHighlightText`.
        static let bodySize: CGFloat = 13.5
        static let body = SwiftUI.Font.system(size: bodySize, weight: .regular)
        /// Explanations under row titles (was `.caption`, 11).
        static let caption = SwiftUI.Font.system(size: 12.5, weight: .regular)
        /// Tertiary hints (was `.caption2` / 9-10).
        static let footnote = SwiftUI.Font.system(size: 11.5, weight: .regular)
        /// Small badges (was 8 bold).
        static let badge = SwiftUI.Font.system(size: 10, weight: .bold)
        /// Uppercase section labels (was 10 semibold).
        static let section = SwiftUI.Font.system(size: 11, weight: .semibold)
        /// Panel row titles and values (was 9-10.5).
        static let panelTitle = SwiftUI.Font.system(size: 12.5, weight: .semibold)
        static let panelBody = SwiftUI.Font.system(size: 12, weight: .regular)
        /// Smallest text allowed in panels and the command bar (was 8-9.5).
        static let panelFloor = SwiftUI.Font.system(size: 11, weight: .regular)
        static let panelFloorEmphasis = SwiftUI.Font.system(size: 11, weight: .semibold)
        /// Row icon glyphs (was 12 semibold).
        static let rowIcon = SwiftUI.Font.system(size: 13, weight: .semibold)
        /// The clipboard header's query field, the palette's own 20pt bar text.
        static let searchField = SwiftUI.Font.system(size: 20, weight: .regular)
        /// A palette bar control's label.
        static let bar = SwiftUI.Font.system(size: 12, weight: .medium)
        /// A section header inside a list (subheadline medium).
        static let sectionHeader = SwiftUI.Font.system(size: 11, weight: .medium)
        /// A popover menu row.
        static let menuRow = SwiftUI.Font.system(size: 13, weight: .regular)
        /// A keycap legend, and a menu row's shortcut.
        static let keyCap = SwiftUI.Font.system(size: 11, weight: .regular)
        /// A palette keycap legend: Tinycast's 10pt caption, below the 11pt
        /// body floor because a keycap is a glyph, not prose.
        static let paletteKeyCap = SwiftUI.Font.system(size: 10, weight: .regular)
        /// The header's back chevron.
        static let headerIcon = SwiftUI.Font.system(size: 18, weight: .medium)
        /// A menu button's leading glyph, and the header filter's.
        static let menuIcon = SwiftUI.Font.system(size: 13, weight: .medium)
        /// A menu button's trailing disclosure chevron.
        static let disclosure = SwiftUI.Font.system(size: 10, weight: .semibold)
        /// The preview's monospaced body; `previewTextSize` feeds its AppKit twin.
        static let previewTextSize: CGFloat = 12
        static let previewText = SwiftUI.Font.system(size: previewTextSize, design: .monospaced)
    }

    enum Space {
        static let micro: CGFloat = 2
        static let xxSmall: CGFloat = 4
        static let xSmall: CGFloat = 6
        static let small: CGFloat = 8
        static let medium: CGFloat = 12
        static let large: CGFloat = 16
        static let xLarge: CGFloat = 20
        /// Card outer padding (was 10-16 depending on surface).
        static let card: CGFloat = 18
        /// Vertical rhythm inside a card (was 13).
        static let cardStack: CGFloat = 16
        /// Row internals (was 12 / 2 / 6).
        static let rowGap: CGFloat = 14
        static let rowTextStack: CGFloat = 4
        static let rowTitleGap: CGFloat = 8
        /// An icon and the one-line title beside it.
        static let rowIconGap: CGFloat = 10
    }

    enum Radius {
        static let panel: CGFloat = 26
        static let card: CGFloat = 14
        static let row: CGFloat = 10
        static let thumbnail: CGFloat = 6
        static let keyCap: CGFloat = 6
        static let barControl: CGFloat = 8
        static let menuPanel: CGFloat = 16
        static let menuRow: CGFloat = 6
    }

    enum Size {
        /// The clipboard list column, fixed beside the preview.
        static let clipboardListWidth: CGFloat = 290
        static let headerHeight: CGFloat = 36
        static let headerPadding: CGFloat = 10
        static let headerIconSlot: CGFloat = 22
        static let bottomBarHeight: CGFloat = 52
        static let barButtonHeight: CGFloat = 28
        static let resultRowIcon: CGFloat = 26
        static let keyCap: CGFloat = 18
        static let menuButton: CGFloat = 36
        static let actionMenuWidth: CGFloat = 300
        static let clipboardFilterMenuWidth: CGFloat = 180
        static let menuRowHeight: CGFloat = 30
    }
}

/// Shared look & feel: brand colors, card styling and the brand mark.
enum Theme {
    /// Near-black background behind the brand mark. Neutral greys into black, no
    /// colour cast, with just a hint of depth so the badge does not read as flat.
    static let spaceGradient = LinearGradient(
        colors: [Color(white: 0.10),
                 Color(white: 0.04),
                 Color.black],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
}

enum PanelMetricColor {
    static func green(for scheme: ColorScheme) -> Color {
        scheme == .light ? Color(red: 0.00, green: 0.44, blue: 0.18) : .green
    }

    static func cyan(for scheme: ColorScheme) -> Color {
        scheme == .light ? Color(red: 0.00, green: 0.43, blue: 0.54) : .cyan
    }

    static func mint(for scheme: ColorScheme) -> Color {
        scheme == .light ? Color(red: 0.00, green: 0.44, blue: 0.40) : .mint
    }

    static func yellow(for scheme: ColorScheme) -> Color {
        scheme == .light ? Color(red: 0.56, green: 0.36, blue: 0.00) : .yellow
    }

    static func red(for scheme: ColorScheme) -> Color {
        scheme == .light ? Color(red: 0.68, green: 0.08, blue: 0.10) : .red
    }

    static func orange(for scheme: ColorScheme) -> Color {
        scheme == .light ? Color(red: 0.68, green: 0.30, blue: 0.00) : .orange
    }

    static func pink(for scheme: ColorScheme) -> Color {
        scheme == .light ? Color(red: 0.68, green: 0.06, blue: 0.34) : .pink
    }
}

private struct NotchPresentationKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    var notchPresentation: Bool {
        get { self[NotchPresentationKey.self] }
        set { self[NotchPresentationKey.self] = newValue }
    }
}

enum PanelSurface {
    /// Whether the menu popover hosts the panel across its whole balloon, so the
    /// panel's own surface can reach the arrow (#1030). Only macOS 26 lays the
    /// content out that way. On macOS 15, `hasFullSizeContent` publishes the
    /// full-size safe area but leaves the view at its content size in the frame's
    /// lower-left corner: the popover grows by that safe area, the panel sits off
    /// center, and a band of system material shows along the top and right edges.
    static var popoverHostsFullSizeContent: Bool {
        if #available(macOS 26.0, *) { return true }
        return false
    }

    static func baseFill(for scheme: ColorScheme) -> Color {
        scheme == .light ? Color.white.opacity(0.68) : Color.black.opacity(0.42)
    }

    static func cardFill(for scheme: ColorScheme) -> Color {
        scheme == .light ? Color.white.opacity(0.38) : Color.white.opacity(0.075)
    }

    static func controlFill(for scheme: ColorScheme) -> Color {
        scheme == .light ? Color.black.opacity(0.055) : Color.white.opacity(0.085)
    }

    /// A list row's selected fill, and the fainter layer under a resting pointer.
    static func selectionFill(for scheme: ColorScheme) -> Color {
        scheme == .light ? Color.black.opacity(0.09) : Color.white.opacity(0.10)
    }

    static func rowHoverFill(for scheme: ColorScheme) -> Color {
        scheme == .light ? Color.black.opacity(0.045) : Color.white.opacity(0.05)
    }

    /// A row added to a batch selection; it stays lit while the pointer is away.
    static func batchSelectionFill(for scheme: ColorScheme) -> Color {
        Color.accentColor.opacity(scheme == .light ? 0.14 : 0.16)
    }

    /// Raised contrast is asked for by someone who cannot see a hairline at a
    /// tenth of an opacity, so the outlines that separate one card from the
    /// next are the ones that answer. A panel is rebuilt every time it opens,
    /// which is when a change to this setting shows.
    static func border(for scheme: ColorScheme) -> Color {
        let raised = NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast
        return scheme == .light
            ? Color.black.opacity(raised ? 0.24 : 0.09)
            : Color.white.opacity(raised ? 0.28 : 0.11)
    }

    /// An outlined keycap's edge: darker than a panel border so the cap reads
    /// as a key, at Tinycast's fixed 0.20 dark / 0.18 light.
    static func keyCapBorder(for scheme: ColorScheme) -> Color {
        scheme == .light ? Color.black.opacity(0.18) : Color.white.opacity(0.20)
    }

    /// A control that sits ON a glass surface rather than in it: the system's
    /// own round toggles read as physical because they are lighter than what
    /// is behind them and carry their own shadow.
    static func raisedFill(for scheme: ColorScheme) -> Color {
        scheme == .light ? Color.white.opacity(0.88) : Color.white.opacity(0.14)
    }

    static func raisedBorder(for scheme: ColorScheme) -> Color {
        let raised = NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast
        return scheme == .light
            ? Color.black.opacity(raised ? 0.22 : 0.07)
            : Color.white.opacity(raised ? 0.32 : 0.16)
    }

    static func raisedShadow(for scheme: ColorScheme) -> Color {
        scheme == .light ? Color.black.opacity(0.14) : Color.black.opacity(0.38)
    }

    /// The lit edge of a glass surface: bright where the light comes from,
    /// gone by the bottom. Without it a translucent panel reads as paper.
    static func rimHighlight(for scheme: ColorScheme) -> LinearGradient {
        LinearGradient(colors: [Color.white.opacity(scheme == .light ? 0.95 : 0.30),
                                Color.white.opacity(scheme == .light ? 0.12 : 0.04)],
                       startPoint: .top,
                       endPoint: .bottom)
    }
}

func sectionTitle(_ text: String) -> some View {
    Text(text.uppercased())
        .font(DS.Font.section)
        .kerning(0.5)
        .foregroundStyle(.secondary)
}

extension View {
    /// The rounded card background used by every panel section. A card
    /// holding a list of rows is not padded: each row brings its own insets,
    /// so hover highlights and separators can reach the card's edges.
    func panelCard(interactive: Bool = true, padded: Bool = true) -> some View {
        modifier(PanelCardModifier(interactive: interactive, padded: padded))
    }

    /// A restrained glass base for the menu panel: still translucent, but with a
    /// stable tint so text and controls do not depend too much on the wallpaper.
    /// It reaches the popover's arrow; see PanelGlassSurface.
    func panelGlassSurface() -> some View {
        background(PanelGlassSurface())
    }
}

private struct PanelCardModifier: ViewModifier {
    var interactive: Bool
    var padded = true
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.notchPresentation) private var notchPresentation

    func body(content: Content) -> some View {
        if notchPresentation {
            content.padding(padded ? DS.Space.card : 0).modifier(NotchControlSurface(cornerRadius: 18, interactive: interactive))
        } else {
        content
            .padding(padded ? DS.Space.medium : 0)
            .background(
                RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous)
                    .fill(PanelSurface.cardFill(for: colorScheme))
            )
            .overlay(
                RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous)
                    .strokeBorder(PanelSurface.border(for: colorScheme), lineWidth: 0.7)
            )
        }
    }
}

private struct PanelGlassSurface: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.notchPresentation) private var notchPresentation
    @Environment(\.notchGlassSurface) private var notchGlassSurface
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @AppStorage(DefaultsKey.liquidGlassEnabled) private var liquidGlassEnabled = false

    var body: some View {
        // AppKit hands the hosted panel a safe area for the popover's border and
        // arrow, so a surface that stopped at the panel would leave the tip in the
        // plain system material. The panel content keeps that inset and never sits
        // under the arrow; only this background bleeds into it. The popover clips
        // it to its own balloon, so the surface is a plain rectangle: rounding would
        // expose the system material at the corners, while stroking would duplicate
        // the outline AppKit already draws. Where the popover still insets its
        // content, the panel is a card inside the balloon instead; see
        // PanelSurface.popoverHostsFullSizeContent.
        if notchPresentation {
            Rectangle().fill(notchGlassSurface ? Color.clear : .black)
        } else if PanelSurface.popoverHostsFullSizeContent {
            surface.ignoresSafeArea()
        } else {
            insetSurface
        }
    }

    @ViewBuilder
    private var surface: some View {
#if compiler(>=6.2)
        if #available(macOS 26.0, *), liquidGlassEnabled, !reduceTransparency {
            Rectangle()
                .fill(Color.clear)
                .glassEffect(.regular, in: Rectangle())
                .overlay(
                    Rectangle()
                        .fill(PanelSurface.baseFill(for: colorScheme).opacity(colorScheme == .light ? 0.35 : 0.45))
                )
        } else {
            standardSurface
        }
#else
        standardSurface
#endif
    }

    @ViewBuilder
    private var standardSurface: some View {
        Rectangle()
            .fill(.regularMaterial)
            .overlay(Rectangle().fill(PanelSurface.baseFill(for: colorScheme)))
    }

    /// The panel as a card inside a popover that insets its content (before
    /// macOS 26): the balloon's rounding never reaches it there, so it carries
    /// its own rounding and rim. Liquid Glass needs macOS 26, so this is always
    /// the standard material.
    private var insetSurface: some View {
        let shape = RoundedRectangle(cornerRadius: 18, style: .continuous)
        return shape
            .fill(.regularMaterial)
            .overlay(shape.fill(PanelSurface.baseFill(for: colorScheme)))
            .overlay(shape.strokeBorder(PanelSurface.border(for: colorScheme), lineWidth: 0.8))
    }
}

func appDelegate() -> AppDelegate? {
    NSApp.delegate as? AppDelegate
}

/// The official mark (Resources/Brand/logo.png, trimmed at build time),
/// tintable for light or dark surfaces.
struct BrandMark: View {
    var width: CGFloat
    var tint: Color = .white

    private static let mark: NSImage? = {
        guard let url = Bundle.main.url(forResource: "BrandMark", withExtension: "png") else { return nil }
        return NSImage(contentsOf: url)
    }()

    var body: some View {
        if let mark = Self.mark {
            Image(nsImage: mark)
                .renderingMode(.template)
                .interpolation(.high)
                .antialiased(true)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .foregroundStyle(tint)
                .frame(width: width)
        } else {
            Image(systemName: "circle.fill")
                .resizable()
                .aspectRatio(contentMode: .fit)
                .foregroundStyle(tint)
                .frame(width: width * 0.5)
        }
    }
}

struct DiscordMark: View {
    var width: CGFloat

    private static let mark: NSImage? = {
        guard let url = Bundle.main.url(forResource: "discord-symbol",
                                        withExtension: "svg",
                                        subdirectory: "Images") else { return nil }
        return NSImage(contentsOf: url)
    }()

    var body: some View {
        if let mark = Self.mark {
            Image(nsImage: mark)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: width)
        }
    }
}

/// Squircle badge with the mark on the space gradient — the app's face in the
/// About tab and onboarding.
struct BrandBadge: View {
    var size: CGFloat

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.26, style: .continuous)
                .fill(Theme.spaceGradient)
            BrandMark(width: size * 0.8)
        }
        .frame(width: size, height: size)
    }
}
