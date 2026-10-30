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

    /// The distinct controls Tab visits in a window.
    ///
    /// Two sources, matched by geometry rather than by press, because their
    /// timing differs between macOS releases. Keyboard-reachable controls
    /// write their frame to `KeyboardFocusLog` when focus arrives; every
    /// logged control is a stop. AppKit's first responder moves to a proxy
    /// view for most other SwiftUI focus (tiles, the stats list, the theme
    /// group, text fields), and its frame is a stop unless its center falls
    /// inside a logged control, in which case it is that control's proxy and
    /// is not counted again. On macOS 15 the proxy for a logged control can
    /// land a press late, or not at all; neither changes the result.
    private func tabStops(in window: NSWindow) async -> [NSRect] {
        window.contentView?.layoutSubtreeIfNeeded()
        window.makeKey()
        // Windows the test opened a moment ago still hand their first
        // responder out asynchronously; let that happen before recording, so
        // their focus arrivals are not taken for stops in this window.
        for _ in 0..<30 { await turnRunLoop() }
        KeyboardFocusLog.reset()
        KeyboardFocusLog.isRecording = true
        defer { KeyboardFocusLog.isRecording = false }
        let thisWindow = ObjectIdentifier(window)
        func loggedHere() -> [KeyboardFocusLog.Stop] {
            KeyboardFocusLog.stops.filter { $0.window == nil || $0.window == thisWindow }
        }
        var responderFrames: [NSRect] = []
        var previous: NSRect?
        for _ in 0..<24 {
            let loggedBefore = loggedHere().count
            window.selectNextKeyView(nil)
            var frame: NSRect?
            var unchangedReads = 0
            let deadline = Date().addingTimeInterval(1)
            while Date() < deadline {
                await turnRunLoop()
                let logged = loggedHere().count > loggedBefore
                guard let view = window.firstResponder as? NSView, view !== window.contentView else {
                    if logged { break }
                    continue
                }
                let current = view.convert(view.bounds, to: nil)
                if current == frame {
                    unchangedReads += 1
                } else {
                    frame = current
                    unchangedReads = 0
                }
                if unchangedReads >= 3, logged || current != previous { break }
            }
            if let frame {
                previous = frame
                if !responderFrames.contains(frame) { responderFrames.append(frame) }
            }
        }
        // Logged frames are in the hosting view's own space; the hosting view
        // converts them into the window space the responder frames use.
        let hosting = Self.hostingView(in: window.contentView)
        var loggedFrames: [NSRect] = []
        for stop in loggedHere() {
            let inWindow = (hosting?.convert(stop.frame, to: nil) ?? stop.frame).insetBy(dx: -4, dy: -4)
            if !loggedFrames.contains(inWindow) { loggedFrames.append(inWindow) }
        }
        // The hosting view converts x exactly, but its y comes out a constant
        // 36 points off (the scroll view it sits in), so the proxy test is x
        // containment plus a y band wide enough for that and narrower than
        // the gap between stacked controls.
        let unlogged = responderFrames.filter { responder in
            !loggedFrames.contains { logged in
                logged.minX <= responder.midX && responder.midX <= logged.maxX
                    && abs(responder.midY - logged.midY) <= 48
            }
        }
        return loggedFrames.enumerated().map { NSRect(x: -1, y: -CGFloat($0.offset + 1), width: 0, height: 0) } + unlogged
    }

    /// The SwiftUI hosting view inside a window, wherever the shell put it.
    private static func hostingView(in view: NSView?) -> NSView? {
        guard let view else { return nil }
        if String(describing: type(of: view)).hasPrefix("NSHostingView") { return view }
        for child in view.subviews {
            if let found = hostingView(in: child) { return found }
        }
        return nil
    }

    /// One turn of the main run loop, so AppKit and SwiftUI can lay out the
    /// focus proxy. A plain `Task.yield` runs other tasks but not the loop.
    private func turnRunLoop() async {
        await withCheckedContinuation { continuation in
            DispatchQueue.main.async { continuation.resume() }
        }
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
            // Tab bar, theme group, text size: the Look tab the window opens
            // on. The other tabs are counted in `tabReachesEveryAppearanceTab`.
            ("Appearance", connected.appearanceWindowController, 3),
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
        // Open Oura developer portal, Copy callback URL, I Have Created It.
        #expect(await tabStops(in: window).count == 3)
    }

    /// Every control on each Appearance tab is a Tab stop, with the system
    /// Keyboard navigation setting off: the tab bar, then the tab's controls.
    @Test func tabReachesEveryAppearanceTab() async throws {
        let model = await delegate().model
        let expected: [(AppearanceTab, Int)] = [
            // Tab bar, theme group, text size.
            (.look, 3),
            // Tab bar, four switches (the pickers appear once a switch is on).
            (.notifications, 5),
            // Tab bar, Reset, stats list, menu bar value.
            (.stats, 4),
        ]
        for (tab, count) in expected {
            let hosting = NSHostingView(rootView: AppearanceSettingsView(initialTab: tab).environmentObject(model))
            let size = hosting.fittingSize
            hosting.frame = CGRect(origin: .zero, size: size)
            let window = NSWindow(contentRect: hosting.frame, styleMask: [.titled, .closable], backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            window.contentView = hosting
            window.orderFrontRegardless()
            defer { window.close() }
            let stops = await tabStops(in: window)
            #expect(stops.count == count, "\(tab): \(stops)")
        }
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
            "Appearance…", "Connection…", "About Ring Stats", "Diagnostics…", "",
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
