import AppKit
import SwiftUI

enum PopoverLayout {
    static let minimumWidth: CGFloat = 420
    static let maximumWidth: CGFloat = 840
    static let widthDefaultsKey = "popover-width"

    static func clampedWidth(_ proposedWidth: CGFloat, availableWidth: CGFloat) -> CGFloat {
        let resolvedMaximum = min(maximumWidth, max(minimumWidth, availableWidth))
        return min(resolvedMaximum, max(minimumWidth, proposedWidth))
    }
}

final class StatusPopoverPanel: NSPanel {
    override var canBecomeKey: Bool { true }

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
        collectionBehavior = [.transient, .moveToActiveSpace]
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
            ConnectionSettingsView().environmentObject(appDelegate.model)
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
    private var connectionWindowController: NSWindowController?
    private var appearanceWindowController: NSWindowController?
    private var aboutWindowController: NSWindowController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        configurePopover()
        configureStatusItem()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    private func configurePopover() {
        let rootView = MenuPopoverShell(geometry: popoverGeometry) {
            MenuPopoverView(
                showConnection: { [weak self] in self?.showConnectionWindow() },
                showAppearance: { [weak self] in self?.showAppearanceWindow() },
                showAbout: { [weak self] in self?.showAboutWindow() }
            )
            .environmentObject(model)
        }
        let hostingController = NSHostingController(rootView: rootView)
        hostingController.view.wantsLayer = true
        hostingController.view.layer?.backgroundColor = NSColor.clear.cgColor

        let panel = StatusPopoverPanel()
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
            ?? PopoverLayout.minimumWidth
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
        panel.orderFrontRegardless()
        installOutsideClickMonitor()
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
    }

    private func closePopover() {
        popoverPanel?.orderOut(nil)
        if let outsideClickMonitor {
            NSEvent.removeMonitor(outsideClickMonitor)
            self.outsideClickMonitor = nil
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

        let aboutItem = NSMenuItem(
            title: "About & Credits",
            action: #selector(openAboutFromMenu(_:)),
            keyEquivalent: ""
        )
        aboutItem.target = self
        menu.addItem(aboutItem)

        menu.addItem(.separator())

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

    private func makeWindow<Content: View>(
        title: String,
        width: CGFloat,
        minimumHeight: CGFloat,
        maximumHeight: CGFloat,
        content: Content
    ) -> NSWindowController {
        let hostingController = NSHostingController(rootView: content)
        let fittingSize = hostingController.sizeThatFits(
            in: NSSize(width: width, height: CGFloat.greatestFiniteMagnitude)
        )
        let contentHeight = max(minimumHeight, min(fittingSize.height, maximumHeight))
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: width, height: contentHeight),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = title
        window.contentViewController = hostingController
        window.isReleasedWhenClosed = false
        window.center()
        return NSWindowController(window: window)
    }

    private func showConnectionWindow() {
        prepareForWindowPresentation()
        if presentExistingWindow(connectionWindowController) { return }

        let view = ConnectionSettingsView(onConnected: { [weak self] in
            self?.connectionWindowController?.close()
        })
        .environmentObject(model)
        let controller = makeWindow(
            title: "Oura Connection",
            width: 460,
            minimumHeight: 260,
            maximumHeight: 560,
            content: view
        )
        connectionWindowController = controller
        controller.showWindow(self)
        controller.window?.makeKeyAndOrderFront(self)
    }

    private func showAppearanceWindow() {
        prepareForWindowPresentation()
        if presentExistingWindow(appearanceWindowController) { return }

        let controller = makeWindow(
            title: "Ring Stats Appearance",
            width: 500,
            minimumHeight: 620,
            maximumHeight: 620,
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
            width: 420,
            minimumHeight: 260,
            maximumHeight: 420,
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

    @objc private func openAboutFromMenu(_ sender: NSMenuItem) {
        DispatchQueue.main.async { [weak self] in
            self?.showAboutWindow()
        }
    }

    @objc private func reauthorizeFromMenu(_ sender: NSMenuItem) {
        Task { await model.reauthorize() }
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

    func windowDidMove(_ notification: Notification) {
        guard notification.object as? NSWindow === popoverPanel else { return }
        updatePopoverArrowPosition()
    }

    func windowDidEndLiveResize(_ notification: Notification) {
        guard let panel = notification.object as? NSWindow,
              panel === popoverPanel else { return }
        UserDefaults.standard.set(panel.contentLayoutRect.width, forKey: PopoverLayout.widthDefaultsKey)
        updatePopoverArrowPosition()
    }
}
