import AppKit
import SwiftUI

/// Makes a control reachable with Tab even when macOS Keyboard navigation is
/// off, as it is by default, and Tab would otherwise reach only text fields
/// and lists.
///
/// With the setting on, macOS already focuses the control itself, so this
/// adds nothing and the control keeps a single Tab stop. With it off, the
/// control becomes focusable, handles its keys here, and draws a theme ring
/// only for keyboard focus, not after a click.
struct KeyboardReachable: ViewModifier {
    let theme: AppTheme
    let cornerRadius: CGFloat
    let outset: CGFloat
    let keys: Set<KeyEquivalent>
    let handle: (KeyPress) -> KeyPress.Result

    @Environment(\.isEnabled) private var isEnabled
    @FocusState private var focused: Bool
    @State private var ringVisible = false

    func body(content: Content) -> some View {
        if NSApplication.shared.isFullKeyboardAccessEnabled {
            content
        } else {
            content
                .overlay {
                    if ringVisible && focused {
                        FocusRing(theme: theme, cornerRadius: cornerRadius, outset: outset)
                    }
                }
                .focusable(isEnabled)
                .focusEffectDisabled()
                .focused($focused)
                .onChange(of: focused) { _, focused in
                    ringVisible = focused && !MenuPopoverView.focusCameFromPointer(NSApp.currentEvent?.type)
                }
                .onKeyPress(keys: keys) { press in
                    guard isEnabled else { return .ignored }
                    ringVisible = true
                    return handle(press)
                }
        }
    }
}

extension View {
    /// A button or link: Space activates it. Return stays with the window's
    /// default button, as on the Mac.
    func keyboardActivatable(
        theme: AppTheme = .ringStats,
        cornerRadius: CGFloat = 6,
        outset: CGFloat = 3,
        action: @escaping () -> Void
    ) -> some View {
        modifier(KeyboardReachable(theme: theme, cornerRadius: cornerRadius, outset: outset, keys: [.space]) { _ in
            action()
            return .handled
        })
    }

    /// A switch or checkbox: Space flips it.
    func keyboardToggle(_ isOn: Binding<Bool>, theme: AppTheme = .ringStats, cornerRadius: CGFloat = 11) -> some View {
        keyboardActivatable(theme: theme, cornerRadius: cornerRadius) { isOn.wrappedValue.toggle() }
    }

    /// A stepped control: the arrow keys move one step down or up.
    func keyboardStepper(theme: AppTheme = .ringStats, cornerRadius: CGFloat = 8, step: @escaping (Int) -> Void) -> some View {
        modifier(KeyboardReachable(
            theme: theme,
            cornerRadius: cornerRadius,
            outset: 3,
            keys: [.leftArrow, .rightArrow, .upArrow, .downArrow]
        ) { press in
            step(press.key == .leftArrow || press.key == .downArrow ? -1 : 1)
            return .handled
        })
    }
}
