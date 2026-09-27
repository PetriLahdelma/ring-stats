import AppKit
import SwiftUI

struct FreshnessPresentation: Equatable {
    let visual: String
    let accessibility: String
}

enum PopoverTimestampText {
    static func freshness(updatedAt: Date, now: Date, stale: Bool) -> FreshnessPresentation {
        let age = max(0, now.timeIntervalSince(updatedAt))
        let updated: String
        switch age {
        case ..<60: updated = "Updated now"
        case ..<3_600: updated = "Updated \(Int(age / 60))m ago"
        default: updated = "Updated \(Int(age / 3_600))h ago"
        }
        return FreshnessPresentation(
            visual: stale ? "Update failed · \(updated)" : updated,
            accessibility: stale ? "Update failed. Showing the last successful values." : updated
        )
    }

    static func batterySample(timestamp: String, now: Date) -> String? {
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        guard let observedAt = fractional.date(from: timestamp)
            ?? ISO8601DateFormatter().date(from: timestamp) else { return nil }
        let age = max(0, now.timeIntervalSince(observedAt))
        let value = age < 3_600
            ? "\(max(1, Int(age / 60)))m ago"
            : "\(Int(age / 3_600))h ago"
        return "Sampled \(value)"
    }
}

struct MenuPopoverView: View {
    @EnvironmentObject private var model: AppViewModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let refresh: () -> Void
    let showConnection: () -> Void
    let showAppearance: () -> Void
    let showAbout: () -> Void
    @AppStorage(AppTheme.storageKey) private var selectedThemeRaw = AppTheme.ringStats.rawValue
    @AppStorage(MetricConfiguration.storageKey) private var metricConfigurationRaw = MetricConfiguration.default.encoded
    @State private var reorderSession: MetricReorderSession?
    @State private var dragTranslationX: CGFloat = 0
    @State private var metricStripSize: CGSize = .zero
    @State private var settlingSourceOffsetX: CGFloat?
    @State private var settlementID: UUID?

    private var theme: AppTheme {
        AppTheme.resolve(selectedThemeRaw)
    }

    private var metricConfiguration: MetricConfiguration {
        MetricConfiguration.decode(metricConfigurationRaw)
    }

    private var displayedMetrics: [Metric] {
        reorderSession?.original.visibleMetrics ?? metricConfiguration.visibleMetrics
    }

    private var reorderAnimation: Animation? {
        reduceMotion ? nil : .easeOut(duration: 0.16)
    }

    private var customizeIconOffset: CGFloat {
        theme == .landscape ? 15 : 0
    }

    private var missingPermissionMetrics: [Metric] {
        metricConfiguration.visibleMetrics.filter {
            model.snapshot.readings[$0]?.availability == .permissionRequired
        }
    }

    private var permissionActionTitle: String {
        if missingPermissionMetrics.count == 1, let metric = missingPermissionMetrics.first {
            return "Enable \(metric.title) Access"
        }
        return "Enable Missing Permissions"
    }

    static func metricIsPending(reading: MetricReading?, loading: Bool) -> Bool {
        reading == nil && loading
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
            reorderSession = MetricReorderSession(
                source: metric,
                configuration: metricConfiguration
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

    private func metricOffsetX(for metric: Metric) -> CGFloat {
        guard let reorderSession else { return 0 }
        let translation = metric == reorderSession.source
            ? settlingSourceOffsetX ?? dragTranslationX
            : dragTranslationX
        return reorderSession.offsetX(for: metric, sourceTranslationX: translation)
    }

    private var customizeMetric: some View {
        Button(action: showAppearance) {
            VStack(spacing: 0) {
                Image(systemName: "pencil")
                    .font(.system(size: 20, weight: .regular))
                    .frame(width: 84, height: 84)
                    .offset(y: customizeIconOffset)
                Text("Customize")
                    .font(.system(size: 12, weight: .semibold))
                    .padding(.top, 12)
            }
            .frame(width: MetricStripLayout.itemWidth)
            .foregroundStyle(theme.primaryContent)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Customize stats")
        .accessibilityHint("Choose which stats appear and change their order")
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
                .font(.system(size: 16, weight: .medium))
                .frame(width: 28, height: 28)
                .contentShape(Rectangle())
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .foregroundStyle(theme.action)
        .accessibilityLabel("Ring Stats menu")
        .accessibilityHint("Contains appearance, About and Credits, reauthorization, and quit actions")
    }

    var body: some View {
        VStack(spacing: 20) {
            if model.connected || model.snapshot.hasData {
                ScrollView(.horizontal) {
                    HStack(alignment: .top, spacing: MetricStripLayout.spacing) {
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
                            .accessibilityHint("Drag to reorder. The same order appears in Appearance.")
                        }
                        customizeMetric
                    }
                    .coordinateSpace(name: MetricStripLayout.coordinateSpaceName)
                    .onGeometryChange(for: CGSize.self) { geometry in
                        geometry.size
                    } action: { size in
                        metricStripSize = size
                    }
                }
                .scrollIndicators(.hidden)
                if !missingPermissionMetrics.isEmpty {
                    Button {
                        Task { await model.reauthorize(metrics: Set(metricConfiguration.visibleMetrics)) }
                    } label: {
                        Label(
                            model.loading ? "Opening Oura…" : permissionActionTitle,
                            systemImage: "exclamationmark.circle"
                        )
                        .font(.system(size: 12, weight: .semibold))
                    }
                    .buttonStyle(.bordered)
                    .tint(theme.action)
                    .disabled(model.loading)
                    .accessibilityHint("Opens Oura authorization to grant the missing data permission")
                }
                if let error = model.errorMessage {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(theme.secondaryContent)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Divider().overlay(theme.divider)
                HStack {
                    BatteryRow(battery: model.snapshot.battery, loading: model.loading, theme: theme)
                    Spacer()
                    optionsMenu
                }
            } else {
                VStack(spacing: 10) {
                    RingStatsLogoView(size: 30, color: theme.action)
                    Text("Connect Oura to see today’s scores")
                        .font(.system(size: 14, weight: .medium))
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
            if (model.connected || model.snapshot.hasData), let freshnessLabel {
                Text(freshnessLabel)
                    .font(.system(size: 10))
                    .foregroundStyle(
                        model.isShowingStaleData ? Palette.alert : theme.secondaryContent
                    )
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(maxWidth: 280, alignment: .trailing)
                    .padding(.top, 10)
                    .padding(.trailing, 24)
                    .accessibilityLabel(freshnessAccessibilityLabel)
                    .accessibilitySortPriority(1)
            }
        }
        .onDisappear {
            settlementID = nil
            reorderSession = nil
            dragTranslationX = 0
            settlingSourceOffsetX = nil
        }
    }

    private var freshnessLabel: String? {
        guard let updatedAt = model.lastUpdatedAt else { return nil }
        return PopoverTimestampText.freshness(
            updatedAt: updatedAt,
            now: Date(),
            stale: model.isShowingStaleData
        ).visual
    }

    private var freshnessAccessibilityLabel: String {
        guard let updatedAt = model.lastUpdatedAt else { return "" }
        return PopoverTimestampText.freshness(
            updatedAt: updatedAt,
            now: Date(),
            stale: model.isShowingStaleData
        ).accessibility
    }
}
