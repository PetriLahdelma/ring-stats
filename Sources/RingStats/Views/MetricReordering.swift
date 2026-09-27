import SwiftUI

enum MetricStripLayout {
    static let coordinateSpaceName = "metric-strip"
    static let itemWidth: CGFloat = 92
    static let spacing: CGFloat = 16
    static let reorderHysteresis: CGFloat = 4

    static var stride: CGFloat { itemWidth + spacing }

    static func centerX(at index: Int) -> CGFloat {
        itemWidth / 2 + CGFloat(index) * stride
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
    private let originalSourceIndex: Int
    private(set) var provisional: MetricConfiguration

    init(source: Metric, configuration: MetricConfiguration) {
        self.source = source
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
                let leftThreshold = MetricStripLayout.centerX(at: leftIndex)
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
                let rightThreshold = MetricStripLayout.centerX(at: rightIndex)
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
        MetricStripLayout.centerX(at: originalSourceIndex) + translationX
    }

    func offsetX(for metric: Metric, sourceTranslationX: CGFloat) -> CGFloat {
        if metric == source { return sourceTranslationX }
        guard let originalIndex = original.visibleMetrics.firstIndex(of: metric),
              let provisionalIndex = provisional.visibleMetrics.firstIndex(of: metric) else {
            return 0
        }
        return CGFloat(provisionalIndex - originalIndex) * MetricStripLayout.stride
    }

    var releaseTargetOffsetX: CGFloat {
        guard let provisionalIndex = provisional.visibleMetrics.firstIndex(of: source) else {
            return 0
        }
        return CGFloat(provisionalIndex - originalSourceIndex) * MetricStripLayout.stride
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
