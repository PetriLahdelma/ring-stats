import AppKit
import SwiftUI
import RingStatsCore

/// What the top-right status shows. `label` stays populated while hidden so
/// the text can fade out instead of vanishing, and `accessibility` is always
/// available to VoiceOver even when nothing is drawn.
struct RefreshStatusPresentation: Equatable {
    enum Tone: Equatable {
        case neutral
        case alert
    }

    let label: String
    let accessibility: String
    let isVisible: Bool
    let showsSpinner: Bool
    let tone: Tone
    /// Whether the status offers to run a refresh when clicked.
    var isRetryable = false
}

enum PopoverTimestampText {
    /// How long "Updated just now" stays after a successful refresh.
    static let confirmationDuration: TimeInterval = 3

    static func refreshStatus(
        isRefreshing: Bool,
        outcome: RefreshOutcome,
        lastUpdatedAt: Date?,
        now: Date,
        refreshInterval: TimeInterval
    ) -> RefreshStatusPresentation? {
        if isRefreshing {
            return RefreshStatusPresentation(
                label: "Refreshing…",
                accessibility: "Refreshing stats",
                isVisible: true,
                showsSpinner: true,
                tone: .neutral
            )
        }
        switch outcome {
        case .none:
            return nil
        case .failed:
            guard let lastUpdatedAt else {
                return RefreshStatusPresentation(
                    label: "Update failed · Retry",
                    accessibility: "Update failed. Retry.",
                    isVisible: true,
                    showsSpinner: false,
                    tone: .alert,
                    isRetryable: true
                )
            }
            let age = relativeAge(since: lastUpdatedAt, now: now)
            return RefreshStatusPresentation(
                label: "Update failed · \(age) · Retry",
                accessibility: "Update failed. Showing values from \(age). Retry.",
                isVisible: true,
                showsSpinner: false,
                tone: .alert,
                isRetryable: true
            )
        case .partial(let at):
            let age = relativeAge(since: at, now: now)
            return RefreshStatusPresentation(
                label: "Some stats not updated · \(age) · Retry",
                accessibility: "Updated \(age). Some stats could not be updated and show their last known values. Retry.",
                isVisible: true,
                showsSpinner: false,
                tone: .alert,
                isRetryable: true
            )
        case .succeeded(let at):
            // Always visible: the age is the freshness promise, and hiding it
            // between the confirmation and the next refresh hid it most of
            // the time.
            let label = "Updated \(relativeAge(since: at, now: now))"
            return RefreshStatusPresentation(
                label: label,
                accessibility: label,
                isVisible: true,
                showsSpinner: false,
                tone: .neutral,
                isRetryable: true
            )
        }
    }

    static func relativeAge(since date: Date, now: Date) -> String {
        let age = max(0, now.timeIntervalSince(date))
        return switch age {
        case ..<60: "just now"
        case ..<3_600: "\(Int(age / 60))m ago"
        case ..<86_400: "\(Int(age / 3_600))h ago"
        default: "\(Int(age / 86_400))d ago"
        }
    }
}

/// What VoiceOver says when a refresh someone asked for finishes. The status
/// label changes silently, so without this a VoiceOver user gets no answer.
enum RefreshAnnouncement {
    static func text(for outcome: RefreshOutcome) -> String? {
        switch outcome {
        case .none: nil
        case .succeeded: "Stats updated"
        case .partial: "Some stats could not be updated and show their last known values"
        case .failed: "Update failed"
        }
    }

    @MainActor static func post(for outcome: RefreshOutcome) {
        guard let text = text(for: outcome) else { return }
        AccessibilityNotification.Announcement(text).post()
    }
}

struct MenuPopoverView: View {
    @EnvironmentObject private var model: AppViewModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.textScale) private var textScale
    let showConnection: () -> Void
    /// Runs a refresh now; the status line calls it.
    var requestRefresh: () -> Void = {}
    /// Draws the keyboard focus ring on this tile without real focus, for the
    /// state gallery.
    var previewFocusRing: Metric?
    /// Draws the ☰ button's keyboard focus ring, for the state gallery.
    var previewMenuFocusRing = false
    /// Opens the options menu below the given ☰ frame, in the popover's
    /// SwiftUI global coordinates.
    var showMenu: (CGRect) -> Void = { _ in }
    @AppStorage(AppTheme.storageKey) private var selectedThemeRaw = AppTheme.ringStats.rawValue
    @AppStorage(MetricConfiguration.storageKey) private var metricConfigurationRaw = MetricConfiguration.default.encoded
    @State private var reorderSession: MetricReorderSession?
    @State private var dragTranslationX: CGFloat = 0
    @State private var metricStripSize: CGSize = .zero
    @State private var stripViewportWidth: CGFloat = 0
    @State private var stripContentMinX: CGFloat = 0
    @State private var settlingSourceOffsetX: CGFloat?
    @State private var settlementID: UUID?
    @FocusState private var focusedMetric: Metric?
    /// Whether the focused tile shows its ring. Only keyboard focus does; a
    /// click or drag also focuses a tile, and a ring then is just noise.
    @State private var focusRingVisible = false
    @FocusState private var menuButtonFocused: Bool
    @State private var menuFocusRingVisible = false
    @State private var menuButtonFrame = CGRect.zero
    @GestureState private var menuButtonPressed = false
    /// Bumped to scroll a tile into view when focus itself does not change,
    /// such as after a keyboard move of the focused tile.
    @State private var scrollRequest = (metric: Metric?.none, id: 0)

    private var theme: AppTheme {
        AppTheme.resolve(selectedThemeRaw)
    }

    private var stripLayout: MetricStripLayout { MetricStripLayout(scale: textScale) }

    private var metricConfiguration: MetricConfiguration {
        MetricConfiguration.decode(metricConfigurationRaw)
    }

    private var displayedMetrics: [Metric] {
        reorderSession?.original.visibleMetrics ?? metricConfiguration.visibleMetrics
    }

    private var reorderAnimation: Animation? {
        reduceMotion ? nil : .easeOut(duration: 0.16)
    }

    private var missingPermissionMetrics: [Metric] {
        metricConfiguration.visibleMetrics.filter {
            model.snapshot.readings[$0]?.availability == .permissionRequired
        }
    }

    private var batteryNeedsAccess: Bool { model.snapshot.batteryNeedsPermission }

    private var hasMissingPermissions: Bool {
        !missingPermissionMetrics.isEmpty || batteryNeedsAccess
    }

    private var permissionActionTitle: String {
        switch (missingPermissionMetrics.count, batteryNeedsAccess) {
        case (0, true): "Enable Battery Access"
        case (1, false): "Enable \(missingPermissionMetrics[0].title) Access"
        default: "Enable Missing Permissions"
        }
    }

    /// Whether the event that moved focus came from a pointer rather than
    /// the keyboard.
    static func focusCameFromPointer(_ eventType: NSEvent.EventType?) -> Bool {
        switch eventType {
        case .leftMouseDown, .leftMouseUp, .leftMouseDragged,
             .rightMouseDown, .rightMouseUp, .otherMouseDown, .otherMouseUp:
            true
        default:
            false
        }
    }

    static func metricIsPending(reading: MetricReading?, loading: Bool) -> Bool {
        reading == nil && loading
    }

    /// Handles arrow keys on a focused tile: arrows move focus, Option-arrows
    /// move the stat itself.
    private func handleArrow(_ press: KeyPress, on metric: Metric) -> KeyPress.Result {
        focusRingVisible = true
        let direction: StripDirection = press.key == .leftArrow ? .left : .right
        if press.modifiers.contains(.option) {
            moveMetric(metric, direction)
        } else if let next = MetricStripNavigation.neighbor(
            of: metric,
            in: metricConfiguration.visibleMetrics,
            direction: direction
        ) {
            focusedMetric = next
        }
        return .handled
    }

    private func moveMetric(_ metric: Metric, _ direction: StripDirection) {
        // A pointer drag owns the order until it settles.
        guard reorderSession == nil, settlementID == nil else { return }
        guard let updated = MetricStripNavigation.moving(metric, direction, in: metricConfiguration) else {
            AccessibilityNotification.Announcement(
                "\(metric.title) is already \(direction == .left ? "first" : "last")"
            ).post()
            return
        }
        withAnimation(reorderAnimation) {
            metricConfigurationRaw = updated.encoded
        }
        focusedMetric = metric
        scrollRequest = (metric, scrollRequest.id + 1)
        if let index = updated.visibleMetrics.firstIndex(of: metric) {
            AccessibilityNotification.Announcement("\(metric.title) moved to position \(index + 1)").post()
        }
    }

    private func commitReordering(_ completed: MetricReorderSession) {
        let updated = completed.provisional
        guard updated != completed.original else { return }
        metricConfigurationRaw = updated.encoded
        if let index = updated.visibleMetrics.firstIndex(of: completed.source) {
            AccessibilityNotification.Announcement(
                "\(completed.source.title) moved to position \(index + 1)"
            ).post()
        }
    }

    private func updateReordering(
        metric: Metric,
        translationX: CGFloat,
        location: CGPoint
    ) {
        guard settlementID == nil else { return }
        if reorderSession == nil {
            // A pointer drag is not keyboard navigation; drop any focus ring.
            focusedMetric = nil
            focusRingVisible = false
            reorderSession = MetricReorderSession(
                source: metric,
                configuration: metricConfiguration,
                layout: stripLayout
            )
        }
        guard var updated = reorderSession, updated.source == metric else { return }
        dragTranslationX = translationX
        guard MetricStripLayout.contains(location, in: metricStripSize) else {
            if updated.resetPreview() {
                withAnimation(reorderAnimation) {
                    reorderSession = updated
                }
            }
            return
        }
        if updated.update(translationX: translationX) {
            withAnimation(reorderAnimation) {
                reorderSession = updated
            }
        }
    }

    private func finishReordering(
        metric: Metric,
        translationX: CGFloat,
        location: CGPoint
    ) {
        guard var completed = reorderSession,
              completed.source == metric,
              settlementID == nil else { return }
        dragTranslationX = translationX
        let isValidRelease = MetricStripLayout.contains(location, in: metricStripSize)
        if isValidRelease, completed.update(translationX: translationX) {
            withAnimation(reorderAnimation) {
                reorderSession = completed
            }
        } else if !isValidRelease, completed.resetPreview() {
            withAnimation(reorderAnimation) {
                reorderSession = completed
            }
        }

        let resolution = completed.resolution(isValidRelease: isValidRelease)
        if resolution.committedConfiguration != nil {
            commitReordering(completed)
        }
        if reduceMotion {
            var transaction = Transaction(animation: nil)
            transaction.disablesAnimations = true
            withTransaction(transaction) {
                reorderSession = nil
                dragTranslationX = 0
                settlingSourceOffsetX = nil
            }
            return
        }

        let identifier = UUID()
        settlementID = identifier
        withAnimation(
            .easeOut(duration: MetricReorderMotion.settleDuration),
            completionCriteria: .logicallyComplete
        ) {
            settlingSourceOffsetX = resolution.targetOffsetX
        } completion: {
            guard settlementID == identifier else { return }
            var transaction = Transaction(animation: nil)
            transaction.disablesAnimations = true
            withTransaction(transaction) {
                reorderSession = nil
                dragTranslationX = 0
                settlingSourceOffsetX = nil
                settlementID = nil
            }
        }
    }

    private var overflowEdges: MetricStripOverflow {
        MetricStripLayout.overflow(
            contentWidth: metricStripSize.width,
            viewportWidth: stripViewportWidth,
            contentMinX: stripContentMinX
        )
    }

    /// Fades an edge only where stats continue past it, so overflow is visible
    /// without a scroll bar.
    private var overflowMask: some View {
        HStack(spacing: 0) {
            LinearGradient(
                colors: [.black.opacity(overflowEdges.leading ? 0 : 1), .black],
                startPoint: .leading,
                endPoint: .trailing
            )
            .frame(width: MetricStripLayout.edgeFadeWidth)
            Rectangle().fill(.black)
            LinearGradient(
                colors: [.black, .black.opacity(overflowEdges.trailing ? 0 : 1)],
                startPoint: .leading,
                endPoint: .trailing
            )
            .frame(width: MetricStripLayout.edgeFadeWidth)
        }
    }

    private func metricOffsetX(for metric: Metric) -> CGFloat {
        guard let reorderSession else { return 0 }
        let translation = metric == reorderSession.source
            ? settlingSourceOffsetX ?? dragTranslationX
            : dragTranslationX
        return reorderSession.offsetX(for: metric, sourceTranslationX: translation)
    }

    /// The ☰ button. It opens the same native menu as right-clicking the
    /// menu-bar icon, so both menus stay identical. Unlike a SwiftUI `Menu`,
    /// it is reachable with Tab whatever the system Keyboard navigation
    /// setting, and opens with Space, Return, or Down Arrow.
    private var optionsMenu: some View {
        let side = (28 * textScale).rounded()
        return Image(systemName: "line.3.horizontal")
            .scaledFont(size: 16, weight: .medium)
            .frame(width: side, height: side)
            .contentShape(Rectangle())
            .foregroundStyle(theme.action)
            .overlay {
                if previewMenuFocusRing || (menuFocusRingVisible && menuButtonFocused) {
                    FocusRing(theme: theme, cornerRadius: (8 * textScale).rounded(), outset: 2)
                }
            }
            .onGeometryChange(for: CGRect.self) { geometry in
                geometry.frame(in: .global)
            } action: { frame in
                menuButtonFrame = frame
            }
            // Menus open on mouse down on the Mac.
            .gesture(
                DragGesture(minimumDistance: 0)
                    .updating($menuButtonPressed) { _, pressed, _ in
                        guard !pressed else { return }
                        pressed = true
                        openOptionsMenu()
                    }
            )
            .focusable()
            .focusEffectDisabled()
            .focused($menuButtonFocused)
            .onChange(of: menuButtonFocused) { _, focused in
                menuFocusRingVisible = focused && !Self.focusCameFromPointer(NSApp.currentEvent?.type)
            }
            .onKeyPress(keys: [.space, .return, .downArrow]) { _ in
                menuFocusRingVisible = true
                openOptionsMenu()
                return .handled
            }
            .accessibilityAddTraits(.isButton)
            .accessibilityLabel("Ring Stats menu")
            .accessibilityHint("Contains appearance, connection, About and Credits, diagnostics, refresh, reauthorization, and quit actions")
            .accessibilityAction { openOptionsMenu() }
    }

    private func openOptionsMenu() {
        let frame = menuButtonFrame
        // Leave the gesture or key callback before the menu's tracking loop.
        DispatchQueue.main.async { showMenu(frame) }
    }

    var body: some View {
        VStack(spacing: 20) {
            if model.connected || model.snapshot.hasData {
                ScrollViewReader { scroller in
                ScrollView(.horizontal) {
                    HStack(alignment: .top, spacing: stripLayout.spacing) {
                        ForEach(displayedMetrics) { metric in
                            let reading = model.snapshot.readings[metric]
                            let isDragging = reorderSession?.source == metric
                            let showsFocusRing = previewFocusRing == metric
                                || (focusRingVisible && focusedMetric == metric && reorderSession == nil)
                            MetricGauge(
                                metric: metric,
                                reading: reading,
                                pending: Self.metricIsPending(reading: reading, loading: model.loading),
                                theme: theme
                            )
                            .contentShape(Rectangle())
                            .overlay {
                                if showsFocusRing {
                                    MetricFocusRing(theme: theme)
                                }
                            }
                            .scaleEffect(isDragging ? 1.06 : 1)
                            .animation(reorderAnimation, value: isDragging)
                            .offset(x: metricOffsetX(for: metric))
                            .zIndex(isDragging ? 1 : 0)
                            .gesture(
                                DragGesture(
                                    minimumDistance: 4,
                                    coordinateSpace: .named(MetricStripLayout.coordinateSpaceName)
                                )
                                    .onChanged { value in
                                        updateReordering(
                                            metric: metric,
                                            translationX: value.translation.width,
                                            location: value.location
                                        )
                                    }
                                    .onEnded { value in
                                        finishReordering(
                                            metric: metric,
                                            translationX: value.translation.width,
                                            location: value.location
                                        )
                                    }
                            )
                            .grabCursor(isDragging: isDragging)
                            .id(metric)
                            .focusable()
                            // The system ring is a rectangle that ignores the
                            // tile's lift and offset; MetricFocusRing replaces it.
                            .focusEffectDisabled()
                            .focused($focusedMetric, equals: metric)
                            .onKeyPress(keys: [.leftArrow, .rightArrow]) { press in
                                handleArrow(press, on: metric)
                            }
                            .accessibilityHint(
                                "Drag, or press Option with the Left or Right Arrow key, to reorder. The same order appears in Appearance."
                            )
                            .accessibilityActions {
                                Button("Move Left") { moveMetric(metric, .left) }
                                Button("Move Right") { moveMetric(metric, .right) }
                            }
                        }
                    }
                    .coordinateSpace(name: MetricStripLayout.coordinateSpaceName)
                    .onGeometryChange(for: CGSize.self) { geometry in
                        geometry.size
                    } action: { size in
                        metricStripSize = size
                    }
                    .onGeometryChange(for: CGFloat.self) { geometry in
                        geometry.frame(in: .named(MetricStripLayout.viewportSpaceName)).minX
                    } action: { minX in
                        stripContentMinX = minX
                    }
                    // Room for the focus ring, which the scroll view would
                    // otherwise clip; the negative padding below gives it back
                    // so the popover keeps its size.
                    .padding(MetricFocusRing.outset + 1)
                }
                .scrollIndicators(.hidden)
                .coordinateSpace(name: MetricStripLayout.viewportSpaceName)
                .onGeometryChange(for: CGFloat.self) { geometry in
                    geometry.size.width
                } action: { width in
                    stripViewportWidth = width
                }
                .mask { overflowMask }
                .padding(-(MetricFocusRing.outset + 1))
                .onChange(of: focusedMetric) { _, metric in
                    focusRingVisible = metric != nil
                        && !Self.focusCameFromPointer(NSApp.currentEvent?.type)
                    guard let metric else { return }
                    withAnimation(reorderAnimation) {
                        scroller.scrollTo(metric)
                    }
                }
                .onChange(of: scrollRequest.id) { _, _ in
                    guard let metric = scrollRequest.metric else { return }
                    withAnimation(reorderAnimation) {
                        scroller.scrollTo(metric)
                    }
                }
                }
                .accessibilityHint(overflowEdges.trailing ? "More stats are available by scrolling" : "")
                if hasMissingPermissions {
                    Button {
                        Task { await model.reauthorize(metrics: Set(metricConfiguration.visibleMetrics)) }
                    } label: {
                        Label(
                            model.loading ? "Opening \(model.descriptor.displayName)…" : permissionActionTitle,
                            systemImage: "exclamationmark.circle"
                        )
                        .scaledFont(size: 12, weight: .semibold)
                    }
                    .buttonStyle(.themedAction(theme))
                    .keyboardActivatable(theme: theme) {
                        Task { await model.reauthorize(metrics: Set(metricConfiguration.visibleMetrics)) }
                    }
                    .disabled(model.loading)
                    .accessibilityHint("Opens \(model.descriptor.displayName) authorization to grant the missing data permission")
                }
                Divider().overlay(theme.divider)
                HStack {
                    BatteryRow(
                        battery: model.snapshot.battery,
                        loading: model.loading,
                        stale: model.snapshot.batteryIsStale,
                        staleSince: model.snapshot.batteryFetchedAt,
                        needsPermission: batteryNeedsAccess,
                        theme: theme
                    )
                    Spacer()
                    optionsMenu
                }
            } else {
                VStack(spacing: 10) {
                    RingStatsLogoView(size: 30, color: theme.action)
                    Text("Connect \(model.descriptor.displayName) to see today’s scores")
                        .scaledFont(size: 14, weight: .medium)
                    Button("Connect", action: showConnection)
                        .buttonStyle(.themedAction(theme))
                        .keyboardActivatable(theme: theme, action: showConnection)
                }
                .frame(maxWidth: .infinity, minHeight: 132)
                HStack {
                    if model.state == .authorizing {
                        Button("Cancel") {
                            Task { await model.cancelAuthorization() }
                        }
                        .keyboardActivatable(theme: theme) { Task { await model.cancelAuthorization() } }
                    }
                    Spacer()
                    optionsMenu
                }
            }
        }
        .padding(.horizontal, 24)
        .padding(.top, 32)
        .padding(.bottom, 22)
        .frame(minWidth: 420, maxWidth: .infinity)
        .foregroundStyle(theme.primaryContent)
        .preferredColorScheme(theme.preferredColorScheme)
        .overlay(alignment: .topTrailing) {
            if model.connected || model.snapshot.hasData {
                RefreshStatusView(theme: theme, requestRefresh: requestRefresh)
                    .padding(.top, 10)
                    .padding(.trailing, 24)
            }
        }
        .onDisappear {
            settlementID = nil
            reorderSession = nil
            dragTranslationX = 0
            settlingSourceOffsetX = nil
        }
    }

}

/// The top-right refresh status. It redraws every second so relative ages
/// stay truthful while the popover is open.
struct RefreshStatusView: View {
    @EnvironmentObject private var model: AppViewModel
    @Environment(\.textScale) private var textScale
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.popoverIsPresented) private var isPresented
    let theme: AppTheme
    var requestRefresh: () -> Void = {}

    var body: some View {
        TimelineView(.animation(minimumInterval: 1, paused: !isPresented)) { context in
            if let status = PopoverTimestampText.refreshStatus(
                isRefreshing: model.isRefreshing,
                outcome: model.lastRefreshOutcome,
                lastUpdatedAt: model.lastUpdatedAt,
                now: context.date,
                refreshInterval: model.refreshInterval
            ) {
                // The status is the retry control: clicking "Updated 2m ago"
                // refreshes, and a failure says "Retry" in the line itself.
                Button(action: requestRefresh) {
                    HStack(spacing: 5) {
                        if status.showsSpinner {
                            ScoreLoadingSpinner(theme: theme, diameter: (9 * textScale).rounded(), lineWidth: 1.5)
                        }
                        Text(status.label)
                            .scaledFont(size: 10)
                            .lineLimit(1)
                            .truncationMode(.tail)
                    }
                    .foregroundStyle(status.tone == .alert ? theme.alert : theme.secondaryContent)
                    .frame(maxWidth: 300, alignment: .trailing)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(!status.isRetryable)
                .keyboardActivatable(theme: theme, cornerRadius: 4, action: requestRefresh)
                .accessibilityLabel(status.accessibility)
                .accessibilityHint(status.isRetryable ? "Refreshes the stats now" : "")
                .accessibilitySortPriority(1)
            }
        }
    }
}

/// The keyboard focus ring around a stat tile: the theme's action color,
/// 2 points wide, following the tile's rounded shape. It meets 3:1 against
/// every theme's background (Signal Blue 6.99:1, white 6.37:1, Holographic
/// Ink 11.7:1).
struct MetricFocusRing: View {
    let theme: AppTheme
    @Environment(\.textScale) private var textScale

    var body: some View {
        FocusRing(theme: theme, cornerRadius: (14 * textScale).rounded(), outset: Self.outset)
    }

    /// How far the ring sits outside the tile, so it never touches the
    /// gauge.
    static let outset: CGFloat = 6
}

/// A keyboard focus ring in the theme's action color, drawn outside a
/// control. Used where the system's rectangular ring does not fit.
struct FocusRing: View {
    let theme: AppTheme
    let cornerRadius: CGFloat
    let outset: CGFloat

    var body: some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .strokeBorder(theme.action, lineWidth: 2)
            .padding(-outset)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}

extension View {
    /// An open hand over a stat tile, closed while it is dragged, where macOS
    /// supports pointer styles.
    @ViewBuilder
    func grabCursor(isDragging: Bool) -> some View {
        if #available(macOS 15, *) {
            pointerStyle(isDragging ? .grabActive : .grabIdle)
        } else {
            self
        }
    }
}
