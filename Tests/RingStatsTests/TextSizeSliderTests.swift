import AppKit
import SwiftUI
import Testing
@testable import RingStats

/// The Appearance text size control is a real stepped slider.
@MainActor
struct TextSizeSliderTests {
    private final class Box {
        var value: TextSizePreference = .standard
        var writes: [TextSizePreference] = []
    }

    private func hostedSlider(_ box: Box) throws -> NSSlider {
        let binding = Binding(get: { box.value }, set: { box.value = $0; box.writes.append($0) })
        let host = NSHostingView(rootView: TextSizeSlider(selection: binding))
        host.frame = NSRect(x: 0, y: 0, width: 240, height: 40)
        host.layoutSubtreeIfNeeded()
        func find(_ view: NSView) -> NSSlider? {
            if let slider = view as? NSSlider { return slider }
            return view.subviews.lazy.compactMap(find).first
        }
        return try #require(find(host))
    }

    @Test func hasOneTickPerSizeAndSnapsToThem() throws {
        let slider = try hostedSlider(Box())
        #expect(slider.numberOfTickMarks == TextSizePreference.allCases.count)
        #expect(TextSizePreference.allCases.count == 3)
        #expect(slider.allowsTickMarkValuesOnly)
        #expect(slider.minValue == 0 && slider.maxValue == 2)
    }

    @Test func reportsOnlyWhenReleased() throws {
        let slider = try hostedSlider(Box())
        #expect(!slider.isContinuous)
    }

    @Test func releasingOnAStepSavesThatSizeOnce() throws {
        let box = Box()
        let slider = try hostedSlider(box)
        slider.doubleValue = 2
        slider.sendAction(slider.action, to: slider.target)
        #expect(box.writes == [.extraLarge])
        slider.sendAction(slider.action, to: slider.target)
        #expect(box.writes == [.extraLarge])
    }

    @Test func voiceOverHearsTheSizeName() throws {
        let box = Box()
        box.value = .large
        let slider = try hostedSlider(box)
        #expect(slider.doubleValue == 1)
        #expect(slider.accessibilityValueDescription() == "Large")
        #expect(slider.accessibilityLabel() == "Text size")
    }
}
