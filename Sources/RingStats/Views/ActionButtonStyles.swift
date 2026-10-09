import SwiftUI

/// The step's main action: filled signal blue with white text.
///
/// `.borderedProminent` turns grey whenever its window is not the active one,
/// which is common for a menu-bar app's windows, and then the main action looks
/// no different from Back. These styles keep the hierarchy in every state.
struct PrimaryActionButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        ActionButtonBody(configuration: configuration, prominence: .primary)
    }
}

/// A secondary action such as Back or Cancel: signal-blue outline and text.
struct SecondaryActionButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        ActionButtonBody(configuration: configuration, prominence: .secondary)
    }
}

extension ButtonStyle where Self == PrimaryActionButtonStyle {
    static var primaryAction: PrimaryActionButtonStyle { PrimaryActionButtonStyle() }
}

/// The popover's main action in the current theme: filled with the theme's
/// action color. The popover panel is never the key window, so the system
/// prominent style always drew it grey, as if disabled.
struct ThemedActionButtonStyle: ButtonStyle {
    let theme: AppTheme
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        let shape = RoundedRectangle(cornerRadius: 7, style: .continuous)
        configuration.label
            .scaledFont(.body, weight: .medium)
            .lineLimit(1)
            .padding(.horizontal, 14)
            .padding(.vertical, 5)
            .frame(minHeight: 28)
            .foregroundStyle(theme.actionLabel)
            .background(shape.fill(theme.action))
            .contentShape(shape)
            .opacity(isEnabled ? (configuration.isPressed ? 0.85 : 1) : 0.45)
    }
}

extension ButtonStyle where Self == ThemedActionButtonStyle {
    static func themedAction(_ theme: AppTheme) -> ThemedActionButtonStyle { ThemedActionButtonStyle(theme: theme) }
}

extension ButtonStyle where Self == SecondaryActionButtonStyle {
    static var secondaryAction: SecondaryActionButtonStyle { SecondaryActionButtonStyle() }
}

private struct ActionButtonBody: View {
    enum Prominence { case primary, secondary }

    let configuration: ButtonStyleConfiguration
    let prominence: Prominence
    @Environment(\.isEnabled) private var isEnabled

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: 7, style: .continuous)
    }

    var body: some View {
        configuration.label
            .scaledFont(.body, weight: .medium)
            .lineLimit(1)
            .padding(.horizontal, 14)
            .padding(.vertical, 5)
            .frame(minHeight: 28)
            .foregroundStyle(prominence == .primary ? Color.white : Palette.signalBlue)
            .background {
                if prominence == .primary {
                    shape.fill(Palette.signalBlue)
                } else {
                    shape.fill(Palette.signalBlue.opacity(configuration.isPressed ? 0.1 : 0))
                }
            }
            .overlay {
                if prominence == .secondary {
                    shape.strokeBorder(Palette.signalBlue, lineWidth: 1)
                }
            }
            .contentShape(shape)
            .opacity(isEnabled ? (prominence == .primary && configuration.isPressed ? 0.85 : 1) : 0.45)
    }
}
