import SwiftUI

enum Palette {
    static let canvasWarm = Color(red: 244 / 255, green: 241 / 255, blue: 236 / 255)
    static let separator = Color(red: 218 / 255, green: 211 / 255, blue: 202 / 255)
    static let signalBlue = Color(red: 55 / 255, green: 83 / 255, blue: 119 / 255)
    static let ink = Color(red: 24 / 255, green: 27 / 255, blue: 31 / 255)
    static let alert = Color(red: 224 / 255, green: 92 / 255, blue: 78 / 255)
    /// Alert red dark enough for small text on the warm canvas (at least 4.5:1).
    /// `alert` stays for icons, where 3:1 is the requirement.
    static let alertText = Color(red: 178 / 255, green: 58 / 255, blue: 46 / 255)
}

extension AppTheme {
    var primaryContent: Color {
        self == .landscape ? .white : Palette.ink
    }

    var secondaryContent: Color {
        self == .landscape ? .white.opacity(0.78) : Palette.ink.opacity(0.62)
    }

    var action: Color {
        self == .landscape ? .white : Palette.signalBlue
    }

    var divider: Color {
        self == .landscape ? .white.opacity(0.28) : Palette.separator
    }

    /// Failure and staleness text. Landscape uses a lighter tint that stays
    /// legible on the darkened photograph.
    var alert: Color {
        self == .landscape ? Color(red: 1, green: 0.74, blue: 0.68) : Palette.alertText
    }

    var score: Color {
        self == .landscape ? .white : Palette.signalBlue
    }
}
