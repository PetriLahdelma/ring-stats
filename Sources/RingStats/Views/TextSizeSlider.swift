import AppKit
import SwiftUI

/// A stepped slider from a small to a large "Aa", as macOS presents text size.
///
/// SwiftUI's `Slider(step:)` drags smoothly on macOS and reports every
/// intermediate value, which re-laid out every window mid-drag. This AppKit
/// slider snaps to one tick mark per size and reports only when released, so
/// the text size changes once, to a real step.
struct TextSizeSlider: View {
    @Binding var selection: TextSizePreference

    var body: some View {
        HStack(spacing: 8) {
            // The end labels show real sizes, so they do not scale.
            Text("Aa").font(.system(size: 11, weight: .medium)).accessibilityHidden(true)
            SteppedSlider(selection: $selection)
                .frame(width: 140)
            Text("Aa").font(.system(size: 17, weight: .medium)).accessibilityHidden(true)
        }
        .fixedSize()
    }
}

struct SteppedSlider: NSViewRepresentable {
    @Binding var selection: TextSizePreference

    static let sizes = TextSizePreference.allCases

    func makeNSView(context: Context) -> NSSlider {
        let slider = NSSlider(
            value: 0,
            minValue: 0,
            maxValue: Double(Self.sizes.count - 1),
            target: context.coordinator,
            action: #selector(Coordinator.changed(_:))
        )
        slider.numberOfTickMarks = Self.sizes.count
        slider.allowsTickMarkValuesOnly = true
        slider.isContinuous = false
        slider.setAccessibilityLabel("Text size")
        slider.setAccessibilityHelp("Scales the text and stats in the popover and every Ring Stats window")
        update(slider)
        return slider
    }

    func updateNSView(_ slider: NSSlider, context: Context) {
        context.coordinator.selection = $selection
        update(slider)
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(selection: $selection)
    }

    private func update(_ slider: NSSlider) {
        let index = Double(Self.sizes.firstIndex(of: selection) ?? 0)
        if slider.doubleValue != index { slider.doubleValue = index }
        slider.setAccessibilityValueDescription(selection.title)
    }

    @MainActor
    final class Coordinator: NSObject {
        var selection: Binding<TextSizePreference>

        init(selection: Binding<TextSizePreference>) {
            self.selection = selection
        }

        @objc func changed(_ slider: NSSlider) {
            let index = min(max(Int(slider.doubleValue.rounded()), 0), SteppedSlider.sizes.count - 1)
            let size = SteppedSlider.sizes[index]
            if selection.wrappedValue != size { selection.wrappedValue = size }
        }
    }
}
