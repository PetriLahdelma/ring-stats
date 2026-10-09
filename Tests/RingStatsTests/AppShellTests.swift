import AppKit
import Foundation
import SwiftUI
import Testing
@testable import RingStats
@testable import RingStatsCore
@testable import RingStatsOura

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
            descriptor: OuraProvider.descriptor,
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

        // Use this machine's real screen: macOS moves a window that would sit
        // off-screen, so a synthetic screen larger than the real one (as on a
        // CI runner) would fail for reasons unrelated to the app.
        let visible = NSScreen.main?.visibleFrame ?? Self.screen
        let anchor = NSRect(x: visible.midX - 12, y: visible.maxY - 40, width: 24, height: 24)
        delegate.showPopover(anchoredTo: anchor, visibleFrame: visible)

        #expect(panel.isVisible)
        #expect(delegate.popoverGeometry.isPresented)
        #expect(abs(panel.frame.maxY - (anchor.minY + 1)) <= 1)
        #expect(delegate.popoverGeometry.arrowX == anchor.midX - panel.frame.minX)
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

    /// Tab reaches every stat and then the ☰ button, even with the system
    /// Keyboard navigation setting off, as it is by default.
    @Test func tabReachesEveryStatAndTheOptionsMenu() async throws {
        let delegate = await delegate()
        delegate.showPopover(anchoredTo: Self.menuBarButton, visibleFrame: Self.screen)
        defer { delegate.closePopover() }
        let panel = try #require(delegate.popoverPanel)
        let stops = await tabStops(in: panel)
        let stats = Metric.defaultVisible.count
        // Every stat, the ☰ button, and the status line.
        #expect(stops.count == stats + 2, "\(stops)")
        #expect(stops.contains { $0.width == 28 && $0.height == 28 }, "no 28-point ☰ stop in \(stops)")
    }

    @Test func optionsMenuOpensBelowTheButton() {
        let button = CGRect(x: 380, y: 200, width: 28, height: 28)
        #expect(AppDelegate.menuOrigin(below: button, inHeight: 260, flipped: true) == NSPoint(x: 380, y: 232))
        #expect(AppDelegate.menuOrigin(below: button, inHeight: 260, flipped: false) == NSPoint(x: 380, y: 28))
    }

    /// Escape closes every Ring Stats window.
    @Test func escapeClosesEveryWindow() async throws {
        let delegate = await delegate()
        delegate.showAppearanceWindow()
        delegate.showAboutWindow()
        delegate.showDiagnosticsWindow()
        delegate.showConnectionWindow()
        let windows = [
            delegate.appearanceWindowController, delegate.aboutWindowController,
            delegate.diagnosticsWindowController, delegate.connectionWindowController,
        ].compactMap { $0?.window }
        #expect(windows.count == 4)
        for window in windows {
            #expect(window.isVisible)
            window.cancelOperation(nil)
            #expect(!window.isVisible, "\(window.title)")
        }
    }

    /// The distinct controls Tab visits in a window, in order, with each
    /// one's frame when last focused. Controls are told apart by identity,
    /// not position: on a slow machine the layout can still be settling, and
    /// a control that moves between two visits must count once.
    private func tabStops(in window: NSWindow) async -> [NSRect] {
        window.contentView?.layoutSubtreeIfNeeded()
        var order: [ObjectIdentifier] = []
        var frames: [ObjectIdentifier: NSRect] = [:]
        for _ in 0..<24 {
            window.selectNextKeyView(nil)
            for _ in 0..<3 { await Task.yield() }
            guard let view = window.firstResponder as? NSView, view !== window.contentView else { continue }
            let id = ObjectIdentifier(view)
            if frames[id] == nil { order.append(id) }
            frames[id] = view.convert(view.bounds, to: nil)
        }
        return order.compactMap { frames[$0] }
    }

    /// Tab reaches every control in every window, with the system Keyboard
    /// navigation setting off as it is by default.
    @Test func tabReachesEveryControlInEveryWindow() async throws {
        let connected = await delegate()
        connected.showAppearanceWindow()
        connected.showAboutWindow()
        connected.showDiagnosticsWindow()
        connected.showConnectionWindow()
        defer { NSApp.windows.forEach { $0.close() } }
        let expected: [(String, NSWindowController?, Int)] = [
            // Theme group, text size, low battery alert, menu bar value,
            // Reset, stats list.
            ("Appearance", connected.appearanceWindowController, 6),
            // GitHub, Privacy, Releases.
            ("About", connected.aboutWindowController, 3),
            // Refresh Report, Copy, Save.
            ("Diagnostics", connected.diagnosticsWindowController, 3),
            // Reauthorize Permissions, Disconnect & Delete Local Data.
            ("Connection", connected.connectionWindowController, 2),
        ]
        for (name, controller, count) in expected {
            let window = try #require(controller?.window, "\(name)")
            let stops = await tabStops(in: window)
            #expect(stops.count == count, "\(name): \(stops)")
        }

        let setup = await delegate(connected: false)
        setup.showConnectionWindow()
        let window = try #require(setup.connectionWindowController?.window)
        // Open Oura developer portal, I Have Created It.
        #expect(await tabStops(in: window).count == 2)
    }

    @Test func themeArrowsStopAtEitherEnd() {
        #expect(AppTheme.ringStats.neighbor(1) == .landscape)
        #expect(AppTheme.holographic.neighbor(-1) == .landscape)
        #expect(AppTheme.ringStats.neighbor(-1) == nil)
        #expect(AppTheme.holographic.neighbor(1) == nil)
    }

    @Test func escapeClosesThePopover() async throws {
        let delegate = await delegate()
        delegate.showPopover(anchoredTo: Self.menuBarButton, visibleFrame: Self.screen)
        let panel = try #require(delegate.popoverPanel)
        panel.cancelOperation(nil)
        #expect(!panel.isVisible)
    }

    // MARK: Context menu

    /// Both the ☰ button and the menu-bar icon open this menu, so every item
    /// carries its icon.
    @Test func everyMenuItemHasAnIcon() async {
        let menu = await delegate(connected: true).makeContextMenu()
        for item in menu.items where !item.isSeparatorItem {
            #expect(item.image != nil, "\(item.title)")
            #expect(item.image?.isTemplate == true, "\(item.title)")
            // One icon width, so every title starts at the same edge.
            #expect(item.image?.size == NSSize(width: AppDelegate.menuIconSide, height: AppDelegate.menuIconSide), "\(item.title)")
        }
    }

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
