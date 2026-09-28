import AppKit
import SwiftUI
import RingStatsCore
import RingStatsOura

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
                accessibility: "Refreshing Oura data",
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
                    label: "Update failed",
                    accessibility: "Update failed",
                    isVisible: true,
                    showsSpinner: false,
                    tone: .alert
                )
            }
            let age = relativeAge(since: lastUpdatedAt, now: now)
            return RefreshStatusPresentation(
                label: "Update failed · \(age)",
                accessibility: "Update failed. Showing values from \(age).",
                isVisible: true,
                showsSpinner: false,
                tone: .alert
            )
        case .partial(let at):
            let age = relativeAge(since: at, now: now)
            return RefreshStatusPresentation(
                label: "Some stats not updated",
                accessibility: "Updated \(age). Some stats could not be updated and show their last known values.",
                isVisible: true,
                showsSpinner: false,
                tone: .alert
            )
        case .succeeded(let at):
            let sinceRefresh = max(0, now.timeIntervalSince(at))
            let label = "Updated \(relativeAge(since: at, now: now))"
            let isVisible = sinceRefresh < confirmationDuration || sinceRefresh >= refreshInterval
            return RefreshStatusPresentation(
                label: label,
                accessibility: label,
                isVisible: isVisible,
                showsSpinner: false,
                tone: .neutral
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

struct MenuPopoverView: View {
    @EnvironmentObject private var model: AppViewModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.textScale) private var textScale
    let refresh: () -> Void
    let showConnection: () -> Void
    let showAppearance: () -> Void
    let showAbout: () -> Void
    var showDiagnostics: () -> Void = {}
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

    static func metricIsPending(reading: MetricReading?, loading: Bool) -> Bool {
        reading == nil && loading
    }

    /// Handles arrow keys on a focused tile: arrows move focus, Option-arrows
    /// move the stat itself.
    private func handleArrow(_ press: KeyPress, on metric: Metric) -> KeyPress.Result {
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

    private var optionsMenu: some View {
        Menu {
            Button(action: showAppearance) {
                Label("Appearance", systemImage: "paintpalette")
            }
            Button(action: showConnection) {
                Label("Connection", systemImage: "person.crop.circle")
            }
            Button(action: showAbout) {
                Label("About & Credits", systemImage: "info.circle")
            }
            Button(action: showDiagnostics) {
                Label("Diagnostics…", systemImage: "stethoscope")
            }
            Divider()
            Button(action: refresh) {
                Label(model.loading ? "Refreshing…" : "Refresh Now", systemImage: "arrow.clockwise")
            }
            .disabled(!model.connected || model.loading)
            Button(model.loading ? "Reauthorizing…" : "Reauthorize Permissions") {
                Task { await model.reauthorize(metrics: Set(metricConfiguration.visibleMetrics)) }
            }
            .disabled(!model.configured || model.loading)
            Divider()
            Button("Quit Ring Stats") {
                NSApp.terminate(nil)
            }
            .keyboardShortcut("q")
        } label: {
            Image(systemName: "line.3.horizontal")
                .scaledFont(size: 16, weight: .medium)
                .frame(width: (28 * textScale).rounded(), height: (28 * textScale).rounded())
                .contentShape(Rectangle())
        }
        // A plain-styled button menu draws its label with SwiftUI, so it takes
        // the theme color.
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
        .foregroundStyle(theme.action)
        .accessibilityLabel("Ring Stats menu")
        .accessibilityHint("Contains appearance, connection, About and Credits, diagnostics, refresh, reauthorization, and quit actions")
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
                            MetricGauge(
                                metric: metric,
                                reading: reading,
                                pending: Self.metricIsPending(reading: reading, loading: model.loading),
                                theme: theme
                            )
                            .contentShape(Rectangle())
                            .scaleEffect(isDragging ? 1.035 : 1)
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
                            .id(metric)
                            .focusable()
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
                }
                .scrollIndicators(.hidden)
                .coordinateSpace(name: MetricStripLayout.viewportSpaceName)
                .onGeometryChange(for: CGFloat.self) { geometry in
                    geometry.size.width
                } action: { width in
                    stripViewportWidth = width
                }
                .mask { overflowMask }
                .onChange(of: focusedMetric) { _, metric in
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
                            model.loading ? "Opening Oura…" : permissionActionTitle,
                            systemImage: "exclamationmark.circle"
                        )
                        .scaledFont(size: 12, weight: .semibold)
                    }
                    .buttonStyle(.bordered)
                    .tint(theme.action)
                    .disabled(model.loading)
                    .accessibilityHint("Opens Oura authorization to grant the missing data permission")
                }
                if let error = model.errorMessage {
                    Text(error)
                        .scaledFont(.caption)
                        .foregroundStyle(theme.secondaryContent)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Divider().overlay(theme.divider)
                HStack {
                    BatteryRow(
                        battery: model.snapshot.battery,
                        loading: model.loading,
                        stale: model.snapshot.batteryIsStale,
                        needsPermission: batteryNeedsAccess,
                        theme: theme
                    )
                    Spacer()
                    optionsMenu
                }
            } else {
                VStack(spacing: 10) {
                    RingStatsLogoView(size: 30, color: theme.action)
                    Text("Connect Oura to see today’s scores")
                        .scaledFont(size: 14, weight: .medium)
                    if theme == .landscape {
                        Button("Connect", action: showConnection)
                            .buttonStyle(.bordered)
                            .tint(.white)
                    } else {
                        Button("Connect", action: showConnection)
                            .buttonStyle(.borderedProminent)
                            .tint(Palette.signalBlue)
                    }
                }
                .frame(maxWidth: .infinity, minHeight: 132)
                HStack {
                    if model.state == .authorizing {
                        Button("Cancel") {
                            Task { await model.cancelAuthorization() }
                        }
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
        .preferredColorScheme(theme == .landscape ? .dark : .light)
        .overlay(alignment: .topTrailing) {
            if model.connected || model.snapshot.hasData {
                RefreshStatusView(theme: theme)
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

    var body: some View {
        TimelineView(.animation(minimumInterval: 1, paused: !isPresented)) { context in
            if let status = PopoverTimestampText.refreshStatus(
                isRefreshing: model.isRefreshing,
                outcome: model.lastRefreshOutcome,
                lastUpdatedAt: model.lastUpdatedAt,
                now: context.date,
                refreshInterval: model.refreshInterval
            ) {
                ZStack(alignment: .trailing) {
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
                    .frame(maxWidth: 280, alignment: .trailing)
                    .opacity(status.isVisible ? 1 : 0)
                    .animation(reduceMotion ? nil : .easeOut(duration: 0.4), value: status.isVisible)
                    .accessibilityHidden(true)

                    // Stays readable to VoiceOver while the visual label is faded out.
                    Color.clear
                        .frame(width: 1, height: 1)
                        .accessibilityElement()
                        .accessibilityLabel(status.accessibility)
                        .accessibilitySortPriority(1)
                }
            }
        }
    }
}
