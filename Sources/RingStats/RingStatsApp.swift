import AppKit
import SwiftUI
import RingStatsCore
import RingStatsOura

enum PopoverLayout {
    static let minimumWidth: CGFloat = 420
    static let defaultWidth: CGFloat = 680
    static let maximumWidth: CGFloat = 840
    static let widthDefaultsKey = "popover-width"

    static func clampedWidth(_ proposedWidth: CGFloat, availableWidth: CGFloat) -> CGFloat {
        let resolvedMaximum = min(maximumWidth, max(minimumWidth, availableWidth))
        return min(resolvedMaximum, max(minimumWidth, proposedWidth))
    }
}

/// Where the popover panel goes for a status-item anchor. Pure so the
/// geometry is testable without a menu bar.
struct PopoverPlacement: Equatable {
    static let horizontalMargin: CGFloat = 8

    let size: NSSize
    let origin: NSPoint
    let maximumWidth: CGFloat
    let arrowX: CGFloat

    /// - Parameters:
    ///   - anchor: The status-item button's frame in screen coordinates.
    ///   - visibleFrame: The screen's visible frame, if known.
    ///   - preferredWidth: The saved or default width.
    ///   - height: The content height for a given width.
    static func compute(
        anchor: NSRect,
        visibleFrame: NSRect?,
        preferredWidth: CGFloat,
        height: (CGFloat) -> CGFloat
    ) -> PopoverPlacement {
        let availableWidth = max(
            PopoverLayout.minimumWidth,
            (visibleFrame?.width ?? PopoverLayout.maximumWidth) - 2 * horizontalMargin
        )
        let width = PopoverLayout.clampedWidth(preferredWidth, availableWidth: availableWidth)
        let size = NSSize(width: width, height: height(width))
        let idealX = (anchor.midX - width / 2).rounded()
        let originX = visibleFrame.map {
            min(max(idealX, $0.minX + horizontalMargin), $0.maxX - width - horizontalMargin)
        } ?? idealX
        return PopoverPlacement(
            size: size,
            origin: NSPoint(x: originX, y: (anchor.minY - size.height + 1).rounded()),
            maximumWidth: PopoverLayout.clampedWidth(PopoverLayout.maximumWidth, availableWidth: availableWidth),
            arrowX: anchor.midX - originX
        )
    }
}

/// Keeps a window's content size within the screen, leaving room for its
/// title bar. Content taller than that scrolls inside the window.
enum WindowSizing {
    static let titleBarAllowance: CGFloat = 40

    static func clamped(_ content: NSSize, visibleFrame: NSRect?) -> NSSize {
        guard let visibleFrame else { return content }
        return NSSize(
            width: min(content.width, visibleFrame.width),
            height: min(content.height, visibleFrame.height - titleBarAllowance)
        )
    }
}

/// What a status-item click does: left-click toggles the popover; right-click
/// or Control-click opens the native menu.
enum StatusItemClickAction: Equatable {
    case togglePopover
    case showMenu

    static func action(for type: NSEvent.EventType, modifiers: NSEvent.ModifierFlags) -> StatusItemClickAction {
        type == .rightMouseUp || modifiers.contains(.control) ? .showMenu : .togglePopover
    }
}

final class StatusPopoverPanel: NSPanel {
    var onCancel: (() -> Void)?

    override var canBecomeKey: Bool { true }

    override func cancelOperation(_ sender: Any?) {
        onCancel?()
    }

    init() {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: PopoverLayout.minimumWidth, height: 260),
            styleMask: [.borderless, .nonactivatingPanel, .resizable],
            backing: .buffered,
            defer: false
        )
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        level = .popUpMenu
        collectionBehavior = [.transient, .moveToActiveSpace, .fullScreenAuxiliary]
        hidesOnDeactivate = false
        isFloatingPanel = true
        becomesKeyOnlyIfNeeded = true
        showsResizeIndicator = true
        preservesContentDuringLiveResize = true
    }
}

@main
struct RingStatsApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        Settings {
            ConnectionSettingsView()
                .environmentObject(appDelegate.model)
                .followsTextSizePreference()
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    let model: AppViewModel

    override convenience init() {
        self.init(model: AppViewModel())
    }

    /// - Parameter model: Injected so tests can drive the shell with stubs and
    ///   never touch the real Keychain.
    init(model: AppViewModel) {
        self.model = model
        super.init()
        ShortcutBridge.model = model
    }

    let popoverGeometry = PopoverGeometryModel()
    /// The status-item frame the visible popover is anchored to.
    private var popoverAnchor: NSRect?
    private var statusItem: NSStatusItem?
    private(set) var popoverPanel: StatusPopoverPanel?
    private var popoverSizeProvider: ((CGFloat) -> NSSize)?
    private var outsideClickMonitor: Any?
    private var localClickMonitor: Any?
    private(set) var connectionWindowController: NSWindowController?
    private(set) var appearanceWindowController: NSWindowController?
    private(set) var aboutWindowController: NSWindowController?
    private(set) var diagnosticsWindowController: NSWindowController?
    private var lastAppliedTextSize = UserDefaults.standard.string(forKey: TextSizePreference.storageKey) ?? ""
    private var defaultsObserver: NSObjectProtocol?
    private(set) var backgroundRefresher: BackgroundRefresher?
    private(set) var lowBatteryWatcher: LowBatteryWatcher?
    /// Re-measures each window's content at the current Text Size.
    private var windowContentMeasurers: [ObjectIdentifier: () -> NSSize] = [:]

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        defaultsObserver = NotificationCenter.default.addObserver(
            forName: UserDefaults.didChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.refitWindowsForTextSize() }
        }
        configurePopover()
        configureStatusItem()
        lowBatteryWatcher = LowBatteryWatcher(model: model)
        let refresher = BackgroundRefresher(model: model) { [weak self] in self?.visibleMetrics ?? [] }
        refresher.start()
        backgroundRefresher = refresher
        Task { [weak self] in
            guard let self else { return }
            await model.updateConnectionState()
            if !model.configured {
                showConnectionWindow()
            }
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func configurePopover() {
        popoverGeometry.isPresented = false
        let rootView = MenuPopoverShell(geometry: popoverGeometry) {
            MenuPopoverView(
                showConnection: { [weak self] in self?.showConnectionWindow() },
                showMenu: { [weak self] frame in self?.showOptionsMenu(below: frame) }
            )
            .environmentObject(model)
        }
        let hostingController = NSHostingController(rootView: rootView)
        hostingController.view.wantsLayer = true
        hostingController.view.layer?.backgroundColor = NSColor.clear.cgColor

        let panel = StatusPopoverPanel()
        panel.onCancel = { [weak self] in self?.closePopover() }
        panel.delegate = self
        panel.contentViewController = hostingController
        popoverPanel = panel
        popoverSizeProvider = { [weak hostingController] width in
            guard let hostingController else { return NSSize(width: width, height: 260) }
            let size = hostingController.sizeThatFits(
                in: NSSize(width: width, height: 800)
            )
            return NSSize(width: width, height: min(800, max(120, size.height)))
        }
    }

    private func configureStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        guard let button = item.button,
              let image = NSImage(named: NSImage.Name("RingStatsMenuIcon")) else {
            assertionFailure("RingStatsMenuIcon is missing from the app asset catalog")
            return
        }

        image.isTemplate = true
        image.size = NSSize(width: 17, height: 17)
        button.image = image
        button.imagePosition = .imageOnly
        button.imageScaling = .scaleProportionallyDown
        button.toolTip = "Ring Stats"
        button.setAccessibilityLabel("Ring Stats")
        button.target = self
        button.action = #selector(handleStatusItemClick(_:))
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        statusItem = item
    }

    @objc private func handleStatusItemClick(_ sender: NSStatusBarButton) {
        guard let event = NSApp.currentEvent else { return }
        switch StatusItemClickAction.action(for: event.type, modifiers: event.modifierFlags) {
        case .showMenu:
            showContextMenu(for: sender, event: event)
        case .togglePopover:
            togglePopover(relativeTo: sender)
        }
    }

    private func togglePopover(relativeTo button: NSStatusBarButton) {
        guard let panel = popoverPanel, let statusWindow = button.window else { return }
        if panel.isVisible {
            closePopover()
            return
        }
        let anchor = statusWindow.convertToScreen(button.convert(button.bounds, to: nil))
        let screen = statusWindow.screen ?? NSScreen.main
        showPopover(anchoredTo: anchor, visibleFrame: screen?.visibleFrame)
    }

    /// Sizes, places, and shows the popover under a status-item frame, then
    /// refreshes if the data is stale.
    func showPopover(anchoredTo anchor: NSRect, visibleFrame: NSRect?) {
        guard let panel = popoverPanel else { return }
        let savedWidth = UserDefaults.standard.object(forKey: PopoverLayout.widthDefaultsKey)
            .map { _ in CGFloat(UserDefaults.standard.double(forKey: PopoverLayout.widthDefaultsKey)) }
            ?? PopoverLayout.defaultWidth
        let placement = PopoverPlacement.compute(
            anchor: anchor,
            visibleFrame: visibleFrame,
            preferredWidth: savedWidth
        ) { [popoverSizeProvider] width in
            popoverSizeProvider?(width).height ?? 260
        }
        popoverAnchor = anchor
        panel.contentMinSize = NSSize(width: PopoverLayout.minimumWidth, height: placement.size.height)
        panel.contentMaxSize = NSSize(width: placement.maximumWidth, height: placement.size.height)
        panel.setContentSize(placement.size)
        panel.setFrameOrigin(placement.origin)
        updatePopoverArrowPosition()
        popoverGeometry.isPresented = true
        panel.makeKeyAndOrderFront(nil)
        // Becoming key would otherwise focus the first stat tile and draw a
        // focus ring on every open. Keyboard users reach the tiles with Tab.
        panel.makeFirstResponder(nil)
        installOutsideClickMonitor()
        refreshPopover(force: false)
    }

    private var visibleMetrics: Set<Metric> {
        let stored = UserDefaults.standard.string(forKey: MetricConfiguration.storageKey)
        return Set(MetricConfiguration.decode(stored).visibleMetrics)
    }

    private func refreshPopover(force: Bool) {
        Task { [weak self] in
            guard let self else { return }
            if force {
                await model.refreshNow(metrics: visibleMetrics)
                RefreshAnnouncement.post(for: model.lastRefreshOutcome)
            } else {
                await model.refreshOnOpen(metrics: visibleMetrics)
            }
            resizeVisiblePopoverToFit()
        }
    }

    private func resizeVisiblePopoverToFit() {
        guard let panel = popoverPanel, panel.isVisible else { return }
        let width = panel.contentLayoutRect.width
        let previousTop = panel.frame.maxY
        let size = popoverSizeProvider?(width) ?? panel.frame.size
        panel.contentMinSize = NSSize(width: PopoverLayout.minimumWidth, height: size.height)
        panel.contentMaxSize = NSSize(width: panel.contentMaxSize.width, height: size.height)
        panel.setContentSize(size)
        panel.setFrameOrigin(NSPoint(x: panel.frame.minX, y: previousTop - panel.frame.height))
        updatePopoverArrowPosition()
    }

    private func updatePopoverArrowPosition() {
        guard let panel = popoverPanel, let popoverAnchor else { return }
        popoverGeometry.arrowX = popoverAnchor.midX - panel.frame.minX
    }

    private func installOutsideClickMonitor() {
        guard outsideClickMonitor == nil else { return }
        outsideClickMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown]
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.closePopover()
            }
        }
        localClickMonitor = NSEvent.addLocalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown]
        ) { [weak self] event in
            guard let self else { return event }
            if event.window !== popoverPanel,
               event.window !== statusItem?.button?.window {
                closePopover()
            }
            return event
        }
    }

    func closePopover() {
        popoverPanel?.orderOut(nil)
        popoverGeometry.isPresented = false
        if let outsideClickMonitor {
            NSEvent.removeMonitor(outsideClickMonitor)
            self.outsideClickMonitor = nil
        }
        if let localClickMonitor {
            NSEvent.removeMonitor(localClickMonitor)
            self.localClickMonitor = nil
        }
    }

    /// Opens the status item's menu below the popover's ☰ button. `frame` is
    /// in the popover's SwiftUI global coordinates, whose origin is the top
    /// left of the hosting view.
    func showOptionsMenu(below frame: CGRect) {
        guard let view = popoverPanel?.contentView else { return }
        let origin = Self.menuOrigin(below: frame, inHeight: view.bounds.height, flipped: view.isFlipped)
        makeContextMenu().popUp(positioning: nil, at: origin, in: view)
    }

    /// The menu's top-left corner, 4 points below the button, in the view's
    /// own coordinates.
    static func menuOrigin(below frame: CGRect, inHeight height: CGFloat, flipped: Bool) -> NSPoint {
        let gap: CGFloat = 4
        return NSPoint(x: frame.minX, y: flipped ? frame.maxY + gap : height - frame.maxY - gap)
    }

    private func showContextMenu(for button: NSStatusBarButton, event: NSEvent) {
        closePopover()
        NSMenu.popUpContextMenu(makeContextMenu(), with: event, for: button)
    }

    /// A menu item icon drawn from an SF Symbol. macOS 27 hides symbol images
    /// in the menus of apps built with an earlier SDK, but still shows drawn
    /// images, so the symbol is redrawn as a template image. With the macOS 27
    /// SDK, set `preferredImageVisibility` instead.
    ///
    /// Every icon is centered in the same square, so the titles after them
    /// start at one edge whatever each symbol's own width.
    static let menuIconSide: CGFloat = 18

    static func menuIcon(_ symbolName: String) -> NSImage? {
        guard let symbol = NSImage(systemSymbolName: symbolName, accessibilityDescription: nil)?
            .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 13, weight: .regular))
        else { return nil }
        let canvas = NSSize(width: menuIconSide, height: menuIconSide)
        let natural = symbol.size
        let scale = min(1, canvas.width / natural.width, canvas.height / natural.height)
        let drawn = NSSize(width: natural.width * scale, height: natural.height * scale)
        let image = NSImage(size: canvas, flipped: false) { _ in
            symbol.draw(in: NSRect(
                x: (canvas.width - drawn.width) / 2,
                y: (canvas.height - drawn.height) / 2,
                width: drawn.width,
                height: drawn.height
            ))
            return true
        }
        image.isTemplate = true
        return image
    }

    /// The status item's right-click menu for the current model state.
    func makeContextMenu() -> NSMenu {
        let menu = NSMenu(title: "Ring Stats")
        menu.autoenablesItems = false

        let appearanceItem = NSMenuItem(
            title: "Appearance…",
            action: #selector(openAppearanceFromMenu(_:)),
            keyEquivalent: ""
        )
        appearanceItem.target = self
        appearanceItem.image = Self.menuIcon("paintpalette")
        menu.addItem(appearanceItem)

        let connectionItem = NSMenuItem(
            title: "Connection…",
            action: #selector(openConnectionFromMenu(_:)),
            keyEquivalent: ""
        )
        connectionItem.target = self
        connectionItem.image = Self.menuIcon("person.crop.circle")
        menu.addItem(connectionItem)

        let aboutItem = NSMenuItem(
            title: "About & Credits",
            action: #selector(openAboutFromMenu(_:)),
            keyEquivalent: ""
        )
        aboutItem.target = self
        aboutItem.image = Self.menuIcon("info.circle")
        menu.addItem(aboutItem)

        let diagnosticsItem = NSMenuItem(
            title: "Diagnostics…",
            action: #selector(openDiagnosticsFromMenu(_:)),
            keyEquivalent: ""
        )
        diagnosticsItem.target = self
        diagnosticsItem.image = Self.menuIcon("stethoscope")
        menu.addItem(diagnosticsItem)

        menu.addItem(.separator())

        let refreshItem = NSMenuItem(
            title: model.loading ? "Refreshing…" : "Refresh Now",
            action: #selector(refreshFromMenu(_:)),
            keyEquivalent: "r"
        )
        refreshItem.target = self
        refreshItem.image = Self.menuIcon("arrow.clockwise")
        refreshItem.isEnabled = model.connected && !model.loading
        menu.addItem(refreshItem)

        let reauthorizeItem = NSMenuItem(
            title: model.loading ? "Reauthorizing…" : "Reauthorize Permissions",
            action: #selector(reauthorizeFromMenu(_:)),
            keyEquivalent: ""
        )
        reauthorizeItem.target = self
        reauthorizeItem.image = Self.menuIcon("key")
        reauthorizeItem.isEnabled = model.configured && !model.loading
        menu.addItem(reauthorizeItem)

        menu.addItem(.separator())

        let quitItem = NSMenuItem(
            title: "Quit Ring Stats",
            action: #selector(quitFromMenu(_:)),
            keyEquivalent: "q"
        )
        quitItem.target = self
        quitItem.image = Self.menuIcon("power")
        quitItem.keyEquivalentModifierMask = .command
        menu.addItem(quitItem)
        return menu
    }

    private func prepareForWindowPresentation() {
        closePopover()
        NSApp.activate(ignoringOtherApps: true)
    }

    private func presentExistingWindow(_ controller: NSWindowController?) -> Bool {
        guard let controller, let window = controller.window else { return false }
        controller.showWindow(self)
        window.makeKeyAndOrderFront(self)
        return true
    }

    /// Every window root sets its own frame from the Text Size preference, so
    /// the window simply fits its content.
    private func makeWindow<Content: View>(title: String, content: Content) -> NSWindowController {
        // Measure the content itself, then host it in a scroll view so a
        // window clamped to a small screen can still reach everything.
        let measure = {
            NSHostingController(rootView: content.followsTextSizePreference()).sizeThatFits(
                in: NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
            )
        }
        let measured = measure()
        let hostingController = NSHostingController(
            rootView: ScrollView(.vertical) { content.followsTextSizePreference() }
                .scrollBounceBehavior(.basedOnSize)
        )
        let size = WindowSizing.clamped(measured, visibleFrame: NSScreen.main?.visibleFrame)
        let window = EscapeClosingWindow(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = title
        // Assigning the controller resizes the window to its not-yet-laid-out
        // view, so apply the measured size afterwards.
        window.contentViewController = hostingController
        window.setContentSize(size)
        window.isReleasedWhenClosed = false
        window.center()
        windowContentMeasurers[ObjectIdentifier(window)] = measure
        return NSWindowController(window: window)
    }

    /// Resizes open windows after the Text Size preference changes, keeping
    /// each window's top edge in place.
    func refitWindowsForTextSize() {
        let stored = UserDefaults.standard.string(forKey: TextSizePreference.storageKey) ?? ""
        guard stored != lastAppliedTextSize else { return }
        lastAppliedTextSize = stored
        let controllers = [
            connectionWindowController,
            appearanceWindowController,
            aboutWindowController,
            diagnosticsWindowController,
        ]
        for window in controllers.compactMap({ $0?.window }) {
            guard let measure = windowContentMeasurers[ObjectIdentifier(window)] else { continue }
            let size = WindowSizing.clamped(measure(), visibleFrame: window.screen?.visibleFrame)
            let top = window.frame.maxY
            window.setContentSize(size)
            window.setFrameOrigin(NSPoint(x: window.frame.minX, y: top - window.frame.height))
        }
        if popoverPanel?.isVisible == true {
            resizeVisiblePopoverToFit()
        }
    }

    func showConnectionWindow() {
        prepareForWindowPresentation()
        if presentExistingWindow(connectionWindowController) { return }

        let view = ConnectionSettingsView(onConnected: { [weak self] in
            self?.connectionWindowController?.close()
            self?.showPopoverAfterConnecting()
        })
        .environmentObject(model)
        let controller = makeWindow(
            title: "Oura Connection",
            content: view
        )
        connectionWindowController = controller
        controller.showWindow(self)
        controller.window?.makeKeyAndOrderFront(self)
    }

    /// Opens the popover under the status item so a new connection ends on
    /// the user's first populated glance rather than a closed window.
    private func showPopoverAfterConnecting() {
        guard let button = statusItem?.button, popoverPanel?.isVisible == false else { return }
        DispatchQueue.main.async { [weak self] in
            self?.togglePopover(relativeTo: button)
        }
    }

    func showAppearanceWindow() {
        prepareForWindowPresentation()
        if presentExistingWindow(appearanceWindowController) { return }

        let controller = makeWindow(
            title: "Ring Stats Appearance",
            content: AppearanceSettingsView()
        )
        appearanceWindowController = controller
        controller.showWindow(self)
        controller.window?.makeKeyAndOrderFront(self)
    }

    func showAboutWindow() {
        prepareForWindowPresentation()
        if presentExistingWindow(aboutWindowController) { return }

        let controller = makeWindow(
            title: "About Ring Stats",
            content: AboutCreditsView()
        )
        aboutWindowController = controller
        controller.showWindow(self)
        controller.window?.makeKeyAndOrderFront(self)
    }

    @objc private func openAppearanceFromMenu(_ sender: NSMenuItem) {
        DispatchQueue.main.async { [weak self] in
            self?.showAppearanceWindow()
        }
    }

    @objc private func openConnectionFromMenu(_ sender: NSMenuItem) {
        DispatchQueue.main.async { [weak self] in
            self?.showConnectionWindow()
        }
    }

    @objc private func openDiagnosticsFromMenu(_ sender: NSMenuItem) {
        DispatchQueue.main.async { [weak self] in
            self?.showDiagnosticsWindow()
        }
    }

    func showDiagnosticsWindow() {
        prepareForWindowPresentation()
        if presentExistingWindow(diagnosticsWindowController) { return }

        let controller = makeWindow(
            title: "Ring Stats Diagnostics",
            content: DiagnosticsView().environmentObject(model)
        )
        diagnosticsWindowController = controller
        controller.showWindow(self)
        controller.window?.makeKeyAndOrderFront(self)
    }

    @objc private func openAboutFromMenu(_ sender: NSMenuItem) {
        DispatchQueue.main.async { [weak self] in
            self?.showAboutWindow()
        }
    }

    @objc private func reauthorizeFromMenu(_ sender: NSMenuItem) {
        Task { await model.reauthorize(metrics: visibleMetrics) }
    }

    @objc private func refreshFromMenu(_ sender: NSMenuItem) {
        // Announces the result and refits the popover if it is open.
        refreshPopover(force: true)
    }

    @objc private func quitFromMenu(_ sender: NSMenuItem) {
        NSApp.terminate(nil)
    }

    func applicationWillTerminate(_ notification: Notification) {
        closePopover()
    }

    func windowDidResize(_ notification: Notification) {
        guard notification.object as? NSWindow === popoverPanel else { return }
        updatePopoverArrowPosition()
    }

    func windowDidEndLiveResize(_ notification: Notification) {
        guard let panel = notification.object as? NSWindow,
              panel === popoverPanel else { return }
        UserDefaults.standard.set(panel.contentLayoutRect.width, forKey: PopoverLayout.widthDefaultsKey)
        // Text can wrap differently at the new width; refit so nothing clips.
        resizeVisiblePopoverToFit()
        updatePopoverArrowPosition()
    }

    func windowDidMove(_ notification: Notification) {
        guard notification.object as? NSWindow === popoverPanel else { return }
        updatePopoverArrowPosition()
    }
}

/// A Ring Stats window that Escape closes, like a panel. Escape reaches the
/// window only when no control handled it first, such as a text field.
final class EscapeClosingWindow: NSWindow {
    override func cancelOperation(_ sender: Any?) {
        performClose(sender)
    }
}
