import AppKit
import SwiftUI

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
    let model = AppViewModel()

    private let popoverGeometry = PopoverGeometryModel()
    private var statusItem: NSStatusItem?
    private var popoverPanel: StatusPopoverPanel?
    private var popoverSizeProvider: ((CGFloat) -> NSSize)?
    private var outsideClickMonitor: Any?
    private var localClickMonitor: Any?
    private var connectionWindowController: NSWindowController?
    private var appearanceWindowController: NSWindowController?
    private var aboutWindowController: NSWindowController?
    private var diagnosticsWindowController: NSWindowController?
    private var lastAppliedTextSize = UserDefaults.standard.string(forKey: TextSizePreference.storageKey) ?? ""
    private var defaultsObserver: NSObjectProtocol?

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

    private func configurePopover() {
        popoverGeometry.isPresented = false
        let rootView = MenuPopoverShell(geometry: popoverGeometry) {
            MenuPopoverView(
                refresh: { [weak self] in self?.refreshPopover(force: true) },
                showConnection: { [weak self] in self?.showConnectionWindow() },
                showAppearance: { [weak self] in self?.showAppearanceWindow() },
                showAbout: { [weak self] in self?.showAboutWindow() },
                showDiagnostics: { [weak self] in self?.showDiagnosticsWindow() }
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
        if event.type == .rightMouseUp || event.modifierFlags.contains(.control) {
            showContextMenu(for: sender, event: event)
        } else {
            togglePopover(relativeTo: sender)
        }
    }

    private func togglePopover(relativeTo button: NSStatusBarButton) {
        guard let panel = popoverPanel, let statusWindow = button.window else { return }
        if panel.isVisible {
            closePopover()
            return
        }

        let screen = statusWindow.screen ?? NSScreen.main
        let availableWidth = max(
            PopoverLayout.minimumWidth,
            (screen?.visibleFrame.width ?? PopoverLayout.maximumWidth) - 16
        )
        let savedWidth = UserDefaults.standard.object(forKey: PopoverLayout.widthDefaultsKey)
            .map { _ in CGFloat(UserDefaults.standard.double(forKey: PopoverLayout.widthDefaultsKey)) }
            ?? PopoverLayout.defaultWidth
        let width = PopoverLayout.clampedWidth(savedWidth, availableWidth: availableWidth)
        let size = popoverSizeProvider?(width) ?? NSSize(width: width, height: 260)
        let maximumWidth = PopoverLayout.clampedWidth(
            PopoverLayout.maximumWidth,
            availableWidth: availableWidth
        )
        panel.contentMinSize = NSSize(width: PopoverLayout.minimumWidth, height: size.height)
        panel.contentMaxSize = NSSize(width: maximumWidth, height: size.height)
        panel.setContentSize(size)

        let buttonInWindow = button.convert(button.bounds, to: nil)
        let buttonOnScreen = statusWindow.convertToScreen(buttonInWindow)
        let idealX = round(buttonOnScreen.midX - size.width / 2)
        let horizontalMargin: CGFloat = 8
        let originX = screen.map {
            min(
                max(idealX, $0.visibleFrame.minX + horizontalMargin),
                $0.visibleFrame.maxX - size.width - horizontalMargin
            )
        } ?? idealX
        let origin = NSPoint(
            x: originX,
            y: round(buttonOnScreen.minY - size.height + 1)
        )
        panel.setFrameOrigin(origin)
        updatePopoverArrowPosition()
        popoverGeometry.isPresented = true
        panel.makeKeyAndOrderFront(nil)
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
        guard let panel = popoverPanel,
              let button = statusItem?.button,
              let statusWindow = button.window else { return }
        let buttonOnScreen = statusWindow.convertToScreen(button.convert(button.bounds, to: nil))
        popoverGeometry.arrowX = buttonOnScreen.midX - panel.frame.minX
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

    private func closePopover() {
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

    private func showContextMenu(for button: NSStatusBarButton, event: NSEvent) {
        closePopover()
        let menu = NSMenu(title: "Ring Stats")
        menu.autoenablesItems = false

        let appearanceItem = NSMenuItem(
            title: "Appearance…",
            action: #selector(openAppearanceFromMenu(_:)),
            keyEquivalent: ""
        )
        appearanceItem.target = self
        menu.addItem(appearanceItem)

        let connectionItem = NSMenuItem(
            title: "Connection…",
            action: #selector(openConnectionFromMenu(_:)),
            keyEquivalent: ""
        )
        connectionItem.target = self
        menu.addItem(connectionItem)

        let aboutItem = NSMenuItem(
            title: "About & Credits",
            action: #selector(openAboutFromMenu(_:)),
            keyEquivalent: ""
        )
        aboutItem.target = self
        menu.addItem(aboutItem)

        let diagnosticsItem = NSMenuItem(
            title: "Diagnostics…",
            action: #selector(openDiagnosticsFromMenu(_:)),
            keyEquivalent: ""
        )
        diagnosticsItem.target = self
        menu.addItem(diagnosticsItem)

        menu.addItem(.separator())

        let refreshItem = NSMenuItem(
            title: model.loading ? "Refreshing…" : "Refresh Now",
            action: #selector(refreshFromMenu(_:)),
            keyEquivalent: "r"
        )
        refreshItem.target = self
        refreshItem.isEnabled = model.connected && !model.loading
        menu.addItem(refreshItem)

        let reauthorizeItem = NSMenuItem(
            title: model.loading ? "Reauthorizing…" : "Reauthorize Permissions",
            action: #selector(reauthorizeFromMenu(_:)),
            keyEquivalent: ""
        )
        reauthorizeItem.target = self
        reauthorizeItem.isEnabled = model.configured && !model.loading
        menu.addItem(reauthorizeItem)

        menu.addItem(.separator())

        let quitItem = NSMenuItem(
            title: "Quit Ring Stats",
            action: #selector(quitFromMenu(_:)),
            keyEquivalent: "q"
        )
        quitItem.target = self
        quitItem.keyEquivalentModifierMask = .command
        menu.addItem(quitItem)

        NSMenu.popUpContextMenu(menu, with: event, for: button)
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
        let hostingController = NSHostingController(rootView: content.followsTextSizePreference())
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: hostingController.view.fittingSize),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = title
        window.contentViewController = hostingController
        window.isReleasedWhenClosed = false
        window.center()
        return NSWindowController(window: window)
    }

    /// Resizes open windows after the Text Size preference changes, keeping
    /// each window's top edge in place.
    private func refitWindowsForTextSize() {
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
            guard let content = window.contentViewController?.view else { continue }
            content.layoutSubtreeIfNeeded()
            let size = content.fittingSize
            let top = window.frame.maxY
            window.setContentSize(size)
            window.setFrameOrigin(NSPoint(x: window.frame.minX, y: top - window.frame.height))
        }
        if popoverPanel?.isVisible == true {
            resizeVisiblePopoverToFit()
        }
    }

    private func showConnectionWindow() {
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

    private func showAppearanceWindow() {
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

    private func showAboutWindow() {
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

    private func showDiagnosticsWindow() {
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
        Task { await model.refreshNow(metrics: visibleMetrics) }
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
