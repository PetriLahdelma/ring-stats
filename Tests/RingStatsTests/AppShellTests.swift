import AppKit
import Foundation
import SwiftUI
import Testing
@testable import RingStats

/// The AppKit shell: popover placement and lifecycle, status-item routing, the
/// context menu, and window management. The delegate gets a stubbed model, so
/// no test touches the real Keychain or network.
@Suite(.serialized) @MainActor
struct AppShellTests {
    private static let screen = NSRect(x: 0, y: 0, width: 1_440, height: 875)
    private static let menuBarButton = NSRect(x: 1_200, y: 875, width: 24, height: 24)

    private func delegate(connected: Bool = true) async -> AppDelegate {
        let snapshot = GalleryFixture.snapshot(
            metrics: Set(Metric.defaultVisible),
            at: Date(),
            lowBattery: false
        )
        let model = AppViewModel(
            auth: AuthStub(configured: connected, connected: connected),
            api: SnapshotStub(results: [.success(snapshot), .success(snapshot)]),
            checkConnectionOnInit: false
        )
        await model.updateConnectionState()
        let delegate = AppDelegate(model: model)
        delegate.configurePopover()
        return delegate
    }

    // MARK: Placement

    @Test func popoverCentersUnderTheStatusItem() {
        let placement = PopoverPlacement.compute(
            anchor: Self.menuBarButton,
            visibleFrame: Self.screen,
            preferredWidth: 420
        ) { _ in 300 }
        #expect(placement.size == NSSize(width: 420, height: 300))
        #expect(placement.origin.x == (Self.menuBarButton.midX - 210).rounded())
        #expect(placement.origin.y == Self.menuBarButton.minY - 300 + 1)
        #expect(placement.arrowX == 210)
    }

    @Test func popoverStaysOnScreenAndTheArrowFollowsTheIcon() {
        let nearRightEdge = NSRect(x: 1_420, y: 875, width: 20, height: 24)
        let placement = PopoverPlacement.compute(
            anchor: nearRightEdge,
            visibleFrame: Self.screen,
            preferredWidth: 680
        ) { _ in 300 }
        #expect(placement.origin.x + placement.size.width <= Self.screen.maxX - PopoverPlacement.horizontalMargin)
        // The panel shifts left, so the arrow moves right to stay under the icon.
        #expect(placement.arrowX == nearRightEdge.midX - placement.origin.x)
        #expect(placement.arrowX > placement.size.width / 2)
    }

    @Test func popoverWidthNeverExceedsANarrowScreen() {
        let narrow = NSRect(x: 0, y: 0, width: 600, height: 800)
        let placement = PopoverPlacement.compute(
            anchor: NSRect(x: 300, y: 800, width: 24, height: 24),
            visibleFrame: narrow,
            preferredWidth: 840
        ) { _ in 280 }
        #expect(placement.size.width == 584)
        #expect(placement.maximumWidth == 584)
        #expect(placement.origin.x >= narrow.minX + PopoverPlacement.horizontalMargin)
    }

    @Test func windowsNeverExceedTheVisibleScreen() {
        let laptop = NSRect(x: 0, y: 0, width: 1_440, height: 806)
        let tall = NSSize(width: 650, height: 897)
        let clamped = WindowSizing.clamped(tall, visibleFrame: laptop)
        #expect(clamped.height == 806 - WindowSizing.titleBarAllowance)
        #expect(clamped.width == 650)
        let small = NSSize(width: 420, height: 262)
        #expect(WindowSizing.clamped(small, visibleFrame: laptop) == small)
    }

    // MARK: Click routing

    @Test func leftClickTogglesAndRightOrControlClickShowsTheMenu() {
        #expect(StatusItemClickAction.action(for: .leftMouseUp, modifiers: []) == .togglePopover)
        #expect(StatusItemClickAction.action(for: .rightMouseUp, modifiers: []) == .showMenu)
        #expect(StatusItemClickAction.action(for: .leftMouseUp, modifiers: .control) == .showMenu)
    }

    // MARK: Popover lifecycle

    @Test func showingThePopoverPlacesItRefreshesAndClosingHidesIt() async throws {
        let delegate = await delegate()
        let panel = try #require(delegate.popoverPanel)
        #expect(!delegate.popoverGeometry.isPresented)

        delegate.showPopover(anchoredTo: Self.menuBarButton, visibleFrame: Self.screen)

        #expect(panel.isVisible)
        #expect(delegate.popoverGeometry.isPresented)
        #expect(abs(panel.frame.maxY - (Self.menuBarButton.minY + 1)) <= 1)
        #expect(delegate.popoverGeometry.arrowX == Self.menuBarButton.midX - panel.frame.minX)
        await waitUntil("refresh on open") { delegate.model.lastRefreshOutcome != .none }

        delegate.closePopover()
        #expect(!panel.isVisible)
        #expect(!delegate.popoverGeometry.isPresented)
    }

    @Test func openingThePopoverDoesNotFocusAStatTile() async throws {
        let delegate = await delegate()
        delegate.showPopover(anchoredTo: Self.menuBarButton, visibleFrame: Self.screen)
        defer { delegate.closePopover() }
        let panel = try #require(delegate.popoverPanel)
        // A focus ring on the first tile at every open would be noise; keyboard
        // users reach the tiles with Tab.
        func nothingFocused() -> Bool {
            let responder = panel.firstResponder
            return responder === panel || responder == nil
        }
        #expect(nothingFocused())
        // SwiftUI may assign focus on a later pass; it must still be clear.
        for _ in 0..<5 { await Task.yield() }
        #expect(nothingFocused())

        // Tab still reaches the stat tiles.
        panel.selectNextKeyView(nil)
        #expect(!nothingFocused())
    }

    @Test func escapeClosesThePopover() async throws {
        let delegate = await delegate()
        delegate.showPopover(anchoredTo: Self.menuBarButton, visibleFrame: Self.screen)
        let panel = try #require(delegate.popoverPanel)
        panel.cancelOperation(nil)
        #expect(!panel.isVisible)
    }

    // MARK: Context menu

    @Test func contextMenuReflectsConnectionState() async {
        let connected = await delegate(connected: true).makeContextMenu()
        #expect(connected.items.map(\.title) == [
            "Appearance…", "Connection…", "About & Credits", "Diagnostics…", "",
            "Refresh Now", "Reauthorize Permissions", "", "Quit Ring Stats",
        ])
        #expect(connected.item(withTitle: "Refresh Now")?.isEnabled == true)
        #expect(connected.item(withTitle: "Reauthorize Permissions")?.isEnabled == true)
        #expect(connected.item(withTitle: "Connection…")?.isEnabled == true)

        let disconnected = await delegate(connected: false).makeContextMenu()
        #expect(disconnected.item(withTitle: "Refresh Now")?.isEnabled == false)
        #expect(disconnected.item(withTitle: "Reauthorize Permissions")?.isEnabled == false)
        // Connection stays reachable in every state.
        #expect(disconnected.item(withTitle: "Connection…")?.isEnabled == true)
    }

    // MARK: Windows

    @Test func everyWindowOpensOnceAndIsReused() async {
        let delegate = await delegate()
        let openers: [(String, () -> Void, () -> NSWindowController?)] = [
            ("Oura Connection", delegate.showConnectionWindow, { delegate.connectionWindowController }),
            ("Ring Stats Appearance", delegate.showAppearanceWindow, { delegate.appearanceWindowController }),
            ("About Ring Stats", delegate.showAboutWindow, { delegate.aboutWindowController }),
            ("Ring Stats Diagnostics", delegate.showDiagnosticsWindow, { delegate.diagnosticsWindowController }),
        ]
        for (title, open, controller) in openers {
            open()
            let first = controller()
            #expect(first?.window?.title == title)
            #expect(first?.window?.isVisible == true)
            #expect((first?.window?.frame.width ?? 0) > 300, "\(title) did not fit its content")
            open()
            #expect(controller() === first, "\(title) opened a second window")
            first?.close()
        }
    }

    @Test func openingAWindowClosesThePopover() async {
        let delegate = await delegate()
        delegate.showPopover(anchoredTo: Self.menuBarButton, visibleFrame: Self.screen)
        delegate.showAboutWindow()
        #expect(delegate.popoverPanel?.isVisible == false)
        delegate.aboutWindowController?.close()
    }

    @Test func windowsRefitWhenTextSizeChanges() async throws {
        let key = TextSizePreference.storageKey
        let original = UserDefaults.standard.string(forKey: key)
        defer {
            if let original {
                UserDefaults.standard.set(original, forKey: key)
            } else {
                UserDefaults.standard.removeObject(forKey: key)
            }
        }
        UserDefaults.standard.set(TextSizePreference.standard.rawValue, forKey: key)
        let delegate = await delegate()
        delegate.refitWindowsForTextSize()
        delegate.showAboutWindow()
        let window = try #require(delegate.aboutWindowController?.window)
        let standardWidth = window.frame.width
        let top = window.frame.maxY

        UserDefaults.standard.set(TextSizePreference.extraLarge.rawValue, forKey: key)
        delegate.refitWindowsForTextSize()

        #expect(window.frame.width > standardWidth)
        #expect(abs(window.frame.maxY - top) <= 1, "the window should grow downward from its top edge")
        delegate.aboutWindowController?.close()
    }
}
