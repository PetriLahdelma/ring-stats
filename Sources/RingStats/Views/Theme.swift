import AppKit
import SwiftUI
import RingStatsCore
import RingStatsOura

enum Palette {
    static let canvasWarm = Color(red: 244 / 255, green: 241 / 255, blue: 236 / 255)
    static let separator = Color(red: 218 / 255, green: 211 / 255, blue: 202 / 255)
    static let signalBlue = Color(red: 55 / 255, green: 83 / 255, blue: 119 / 255)
    static let ink = Color(red: 24 / 255, green: 27 / 255, blue: 31 / 255)
    static let alert = Color(red: 224 / 255, green: 92 / 255, blue: 78 / 255)
    /// Alert red dark enough for small text on the warm canvas (at least 4.5:1).
    /// `alert` stays for icons, where 3:1 is the requirement.
    static let alertText = Color(red: 178 / 255, green: 58 / 255, blue: 46 / 255)

    /// Captions and control glyphs in the light windows: 4.65:1 on the warm
    /// canvas, where the system secondary label color is only 3.88:1. Solid
    /// ink while Increase Contrast is on.
    static var secondaryInk: Color { secondaryInk(increasedContrast: AppTheme.increasesContrast) }

    static func secondaryInk(increasedContrast: Bool) -> Color {
        increasedContrast ? ink : ink.opacity(0.62)
    }

    /// The Holographic theme's text colors. Contrast is measured against the
    /// darkest pixel of the marble, pink `#F3B9DF`.
    enum Holographic {
        /// 11.7:1; details use it at 68% (5.4:1).
        static let ink = Color(red: 13 / 255, green: 15 / 255, blue: 16 / 255)
        /// 5.2:1, for failure text and the low-battery icon.
        static let alert = Color(red: 140 / 255, green: 42 / 255, blue: 31 / 255)
    }
}

extension AppTheme {
    var primaryContent: Color {
        switch self {
        case .ringStats: Palette.ink
        case .landscape: .white
        case .holographic: Palette.Holographic.ink
        }
    }

    /// Whether macOS's Increase Contrast setting is on. Faded text and control
    /// tokens become solid while it is.
    static var increasesContrast: Bool {
        NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast
    }

    var secondaryContent: Color {
        secondaryContent(increasedContrast: Self.increasesContrast)
    }

    func secondaryContent(increasedContrast: Bool) -> Color {
        if increasedContrast { return primaryContent }
        return switch self {
        case .ringStats: Palette.ink.opacity(0.62)
        case .landscape: .white.opacity(0.78)
        case .holographic: Palette.Holographic.ink.opacity(0.68)
        }
    }

    var action: Color {
        switch self {
        case .ringStats: Palette.signalBlue
        case .landscape: .white
        case .holographic: Palette.Holographic.ink
        }
    }

    var divider: Color {
        switch self {
        case .ringStats: Palette.separator
        case .landscape: .white.opacity(0.28)
        case .holographic: Palette.Holographic.ink.opacity(0.16)
        }
    }

    /// Failure and staleness text. Landscape uses a lighter tint that stays
    /// legible on the darkened photograph.
    var alert: Color {
        switch self {
        case .ringStats: Palette.alertText
        case .landscape: Color(red: 1, green: 212 / 255, blue: 204 / 255)
        case .holographic: Palette.Holographic.alert
        }
    }

    var score: Color {
        switch self {
        case .ringStats: Palette.signalBlue
        case .landscape: .white
        case .holographic: Palette.Holographic.ink
        }
    }
}

/// The user's chosen text size. macOS does not apply Dynamic Type to these
/// views, so Ring Stats scales its own type and the tile geometry around it.
enum TextSizePreference: String, CaseIterable, Identifiable, Sendable {
    case standard
    case large
    case extraLarge = "extra-large"

    static let storageKey = "text-size"

    static func resolve(_ storedValue: String) -> TextSizePreference {
        TextSizePreference(rawValue: storedValue) ?? .standard
    }

    var id: String { rawValue }

    var title: String {
        switch self {
        case .standard: "Standard"
        case .large: "Large"
        case .extraLarge: "Extra Large"
        }
    }

    var scale: CGFloat {
        switch self {
        case .standard: 1
        case .large: 1.15
        case .extraLarge: 1.3
        }
    }
}

extension EnvironmentValues {
    /// Multiplier for every text size and text-bearing dimension.
    @Entry var textScale: CGFloat = 1
}

/// Named sizes for the settings windows, matching macOS's own text styles at
/// the standard size.
enum ScaledTextStyle {
    case title
    case headline
    case body
    case callout
    case caption

    var baseSize: CGFloat {
        switch self {
        case .title: 17
        case .headline, .body: 13
        case .callout: 12
        case .caption: 10
        }
    }

    var defaultWeight: Font.Weight {
        switch self {
        case .title: .semibold
        case .headline: .bold
        case .body, .callout, .caption: .regular
        }
    }
}

private struct ScaledFont: ViewModifier {
    @Environment(\.textScale) private var scale
    let size: CGFloat
    let weight: Font.Weight
    let design: Font.Design

    func body(content: Content) -> some View {
        content.font(.system(size: (size * scale).rounded(), weight: weight, design: design))
    }
}

extension View {
    /// A fixed-size font that follows the Text Size preference.
    func scaledFont(size: CGFloat, weight: Font.Weight = .regular, design: Font.Design = .default) -> some View {
        modifier(ScaledFont(size: size, weight: weight, design: design))
    }

    func scaledFont(_ style: ScaledTextStyle, weight: Font.Weight? = nil, design: Font.Design = .default) -> some View {
        modifier(ScaledFont(size: style.baseSize, weight: weight ?? style.defaultWeight, design: design))
    }

    /// Reads the stored Text Size preference and applies it to this subtree.
    /// Every window root and the popover shell use it.
    func followsTextSizePreference() -> some View {
        modifier(TextSizePreferenceReader())
    }
}

private struct TextSizePreferenceReader: ViewModifier {
    @AppStorage(TextSizePreference.storageKey) private var stored = TextSizePreference.standard.rawValue

    func body(content: Content) -> some View {
        content.environment(\.textScale, TextSizePreference.resolve(stored).scale)
    }
}
