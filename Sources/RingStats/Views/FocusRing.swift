import SwiftUI

/// The keyboard focus ring around a stat tile: the theme's action color,
/// 2 points wide, following the tile's rounded shape. It meets 3:1 against
/// every theme's background (Signal Blue 6.99:1, white 6.37:1, Holographic
/// Ink 11.7:1).
struct MetricFocusRing: View {
    let theme: AppTheme
    @Environment(\.textScale) private var textScale

    var body: some View {
        FocusRing(theme: theme, cornerRadius: (14 * textScale).rounded(), outset: Self.outset)
    }

    /// How far the ring sits outside the tile, so it never touches the
    /// gauge.
    static let outset: CGFloat = 6
}

/// A keyboard focus ring in the theme's action color, drawn outside a
/// control. Used where the system's rectangular ring does not fit.
struct FocusRing: View {
    let theme: AppTheme
    let cornerRadius: CGFloat
    let outset: CGFloat

    var body: some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .strokeBorder(theme.action, lineWidth: 2)
            .padding(-outset)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}

extension View {
    /// An open hand over a stat tile, closed while it is dragged, where macOS
    /// supports pointer styles.
    @ViewBuilder
    func grabCursor(isDragging: Bool) -> some View {
        if #available(macOS 15, *) {
            pointerStyle(isDragging ? .grabActive : .grabIdle)
        } else {
            self
        }
    }
}
