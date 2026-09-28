import SwiftUI
import RingStatsCore
import RingStatsOura

enum StripDirection: Sendable {
    case left
    case right
}

/// Keyboard movement through the visible stats. Pure so it can be tested.
enum MetricStripNavigation {
    /// The tile focus should move to, or nil at either end.
    static func neighbor(
        of metric: Metric,
        in visible: [Metric],
        direction: StripDirection
    ) -> Metric? {
        guard let index = visible.firstIndex(of: metric) else { return visible.first }
        let target = direction == .left ? index - 1 : index + 1
        return visible.indices.contains(target) ? visible[target] : nil
    }

    /// Moves a visible stat one place past its visible neighbor, or returns
    /// nil when it is already at that end.
    static func moving(
        _ metric: Metric,
        _ direction: StripDirection,
        in configuration: MetricConfiguration
    ) -> MetricConfiguration? {
        let visible = configuration.visibleMetrics
        guard let neighbor = neighbor(of: metric, in: visible, direction: direction),
              visible.contains(metric) else { return nil }
        return configuration.moving(metric, relativeTo: neighbor, after: direction == .right)
    }
}

struct MetricStripOverflow: Equatable {
    let leading: Bool
    let trailing: Bool
}

/// Horizontal geometry of the metric strip at a given text scale. The static
/// members describe the standard scale.
struct MetricStripLayout: Equatable, Sendable {
    static let coordinateSpaceName = "metric-strip"
    static let viewportSpaceName = "metric-strip-viewport"
    static let edgeFadeWidth: CGFloat = 28
    static let reorderHysteresis: CGFloat = 4
    static let standard = MetricStripLayout(scale: 1)

    let scale: CGFloat

    var itemWidth: CGFloat { (92 * scale).rounded() }
    var spacing: CGFloat { (16 * scale).rounded() }
    var stride: CGFloat { itemWidth + spacing }

    func centerX(at index: Int) -> CGFloat {
        itemWidth / 2 + CGFloat(index) * stride
    }

    static var itemWidth: CGFloat { standard.itemWidth }
    static var spacing: CGFloat { standard.spacing }
    static var stride: CGFloat { standard.stride }

    static func centerX(at index: Int) -> CGFloat {
        standard.centerX(at: index)
    }

    /// Which edges have stats scrolled past them. A one-point tolerance keeps
    /// rounding from flickering a fade on or off.
    static func overflow(
        contentWidth: CGFloat,
        viewportWidth: CGFloat,
        contentMinX: CGFloat
    ) -> MetricStripOverflow {
        guard contentWidth > 0, viewportWidth > 0 else {
            return MetricStripOverflow(leading: false, trailing: false)
        }
        return MetricStripOverflow(
            leading: contentMinX < -1,
            trailing: contentMinX + contentWidth > viewportWidth + 1
        )
    }

    static func contains(_ point: CGPoint, in size: CGSize) -> Bool {
        guard size.width > 0, size.height > 0 else { return true }
        return CGRect(origin: .zero, size: size).contains(point)
    }
}

enum MetricReorderMotion {
    static let settleDuration: TimeInterval = 0.16

    static func duration(reduceMotion: Bool) -> TimeInterval {
        reduceMotion ? 0 : settleDuration
    }
}

struct MetricReorderResolution: Equatable {
    let committedConfiguration: MetricConfiguration?
    let targetOffsetX: CGFloat
}

struct MetricReorderSession: Equatable {
    let source: Metric
    let original: MetricConfiguration
    let layout: MetricStripLayout
    private let originalSourceIndex: Int
    private(set) var provisional: MetricConfiguration

    init(source: Metric, configuration: MetricConfiguration, layout: MetricStripLayout = .standard) {
        self.source = source
        self.layout = layout
        self.original = configuration.normalized
        self.provisional = configuration.normalized
        self.originalSourceIndex = configuration.normalized.visibleMetrics.firstIndex(of: source) ?? 0
    }

    @discardableResult
    mutating func update(translationX: CGFloat) -> Bool {
        let draggedCenterX = self.draggedCenterX(translationX: translationX)
        var didMove = false

        while let sourceIndex = provisional.visibleMetrics.firstIndex(of: source) {
            let visibleMetrics = provisional.visibleMetrics
            if sourceIndex > 0 {
                let leftIndex = sourceIndex - 1
                let leftThreshold = layout.centerX(at: leftIndex)
                    - MetricStripLayout.reorderHysteresis
                if draggedCenterX < leftThreshold {
                    provisional = provisional.moving(
                        source,
                        relativeTo: visibleMetrics[leftIndex],
                        after: false
                    )
                    didMove = true
                    continue
                }
            }

            if sourceIndex < visibleMetrics.count - 1 {
                let rightIndex = sourceIndex + 1
                let rightThreshold = layout.centerX(at: rightIndex)
                    + MetricStripLayout.reorderHysteresis
                if draggedCenterX > rightThreshold {
                    provisional = provisional.moving(
                        source,
                        relativeTo: visibleMetrics[rightIndex],
                        after: true
                    )
                    didMove = true
                    continue
                }
            }
            break
        }

        return didMove
    }

    func draggedCenterX(translationX: CGFloat) -> CGFloat {
        layout.centerX(at: originalSourceIndex) + translationX
    }

    func offsetX(for metric: Metric, sourceTranslationX: CGFloat) -> CGFloat {
        if metric == source { return sourceTranslationX }
        guard let originalIndex = original.visibleMetrics.firstIndex(of: metric),
              let provisionalIndex = provisional.visibleMetrics.firstIndex(of: metric) else {
            return 0
        }
        return CGFloat(provisionalIndex - originalIndex) * layout.stride
    }

    var releaseTargetOffsetX: CGFloat {
        guard let provisionalIndex = provisional.visibleMetrics.firstIndex(of: source) else {
            return 0
        }
        return CGFloat(provisionalIndex - originalSourceIndex) * layout.stride
    }

    func resolution(isValidRelease: Bool) -> MetricReorderResolution {
        MetricReorderResolution(
            committedConfiguration: isValidRelease ? provisional : nil,
            targetOffsetX: isValidRelease ? releaseTargetOffsetX : 0
        )
    }

    @discardableResult
    mutating func resetPreview() -> Bool {
        guard provisional != original else { return false }
        provisional = original
        return true
    }
}
