import AppKit
import Foundation
import SwiftUI
import Testing
@testable import RingStats

/// Renders the popover and connection window in every state that matters, at
/// every supported width and theme, and checks their geometry.
///
/// Each render is written to `.build/state-gallery` (or `RING_STATS_GALLERY_DIR`)
/// together with an `index.html` contact sheet, so a reviewer can see every
/// state at once. Assertions are semantic rather than pixel-based: pixel
/// comparisons break across macOS releases, while these properties should not.
@Suite(.serialized) @MainActor
struct StateGalleryTests {
    static let widths: [CGFloat] = [
        PopoverLayout.minimumWidth,
        PopoverLayout.defaultWidth,
        PopoverLayout.maximumWidth,
    ]

    @Test func popoverStatesRenderWithinBoundsAtEverySupportedWidth() async throws {
        let gallery = try GalleryWriter()
        for state in GalleryState.allCases {
            for theme in AppTheme.allCases {
                for width in Self.widths {
                    let fixture = try await GalleryFixture(state: state, theme: theme)
                    let render = try fixture.renderPopover(width: width)
                    try gallery.add(render, name: "popover-\(state.rawValue)-\(theme.rawValue)-\(Int(width))")

                    #expect(render.size.width == width, "\(state) \(theme) \(width)")
                    #expect(render.size.height >= 120, "\(state) \(theme) \(width) is collapsed")
                    #expect(render.size.height <= 800, "\(state) \(theme) \(width) exceeds the panel limit")
                    #expect(render.hasVisibleContent, "\(state) \(theme) \(width) rendered blank")
                }
            }
        }
        try gallery.writeIndex()
    }

    @Test func themesKeepTheSameLayoutForEveryState() async throws {
        // Semantic parity: Landscape may change color and imagery, but not
        // which lines exist. Equal heights mean neither theme drops a row.
        for state in GalleryState.allCases {
            let ringStats = try await GalleryFixture(state: state, theme: .ringStats)
                .renderPopover(width: PopoverLayout.defaultWidth)
            let landscape = try await GalleryFixture(state: state, theme: .landscape)
                .renderPopover(width: PopoverLayout.defaultWidth)
            #expect(ringStats.size.height == landscape.size.height, "\(state)")
        }
    }

    @Test func popoverHeightDoesNotDependOnWidth() async throws {
        // The panel resizes horizontally only; its height must not change
        // when the user drags it wider or narrower.
        for state in GalleryState.allCases {
            var heights: [CGFloat] = []
            for width in Self.widths {
                let fixture = try await GalleryFixture(state: state, theme: .ringStats)
                heights.append(try fixture.renderPopover(width: width).size.height)
            }
            #expect(Set(heights).count == 1, "\(state): \(heights)")
        }
    }

    @Test func metricTilesShareOneBaselineWhateverTheValueSize() throws {
        // Resilience uses a smaller value font. The tile anatomy aligns every
        // value to the same reference baseline, so tiles stay the same height.
        let regular = MetricReading(value: "72", detail: "Good", score: 72)
        let compact = MetricReading(value: "Solid", detail: "Long-term", score: nil)
        for theme in AppTheme.allCases {
            let heartRate = fittingSize(MetricGauge(metric: .heartRate, reading: regular, pending: false, theme: theme))
            let resilience = fittingSize(MetricGauge(metric: .resilience, reading: compact, pending: false, theme: theme))
            #expect(heartRate == resilience, "\(theme)")
            #expect(heartRate.width == MetricTileAnatomy.width)
        }
    }

    @Test func connectionStepsRenderWithoutClipping() async throws {
        let gallery = try GalleryWriter(subdirectory: "connection")
        for step in ConnectionStep.allCases {
            let model = AppViewModel(
                auth: AuthStub(configured: false, connected: false),
                api: SnapshotStub(results: []),
                checkConnectionOnInit: false
            )
            await model.updateConnectionState()
            let view = ConnectionSettingsView(initialStep: step).environmentObject(model)
            let render = try GalleryRender(view: view, width: ConnectionSettingsView.windowWidth)
            try gallery.add(render, name: "connection-\(step.rawValue)")
            #expect(render.size.height <= ConnectionSettingsView.windowHeight, "\(step) is taller than its window")
        }
        try gallery.writeIndex()
    }

    private func fittingSize<V: View>(_ view: V) -> CGSize {
        let hosting = NSHostingView(rootView: view)
        return hosting.fittingSize
    }
}

enum GalleryState: String, CaseIterable {
    case disconnected
    case connected
    case refreshing
    case partialFailure = "partial-failure"
    case failed
    case noData = "no-data"
    case permissionRequired = "permission-required"
    case resilienceAndLowBattery = "resilience-low-battery"
}

/// A view model driven into one gallery state through its public API.
@MainActor
struct GalleryFixture {
    let model: AppViewModel
    let defaults: UserDefaults
    let theme: AppTheme
    /// Ends any operation the fixture holds open.
    private(set) var release: @Sendable () -> Void = {}

    init(state: GalleryState, theme: AppTheme) async throws {
        Self.loadLandscapePhoto()
        self.theme = theme
        let suite = "ring-stats-gallery-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defaults.set(theme.rawValue, forKey: AppTheme.storageKey)
        var configuration = MetricConfiguration.default
        if state == .resilienceAndLowBattery {
            configuration.hidden = []
        }
        defaults.set(configuration.encoded, forKey: MetricConfiguration.storageKey)
        self.defaults = defaults

        let now = Date()
        let metrics = Set(configuration.visibleMetrics)
        let full = Self.snapshot(metrics: metrics, at: now, lowBattery: false)
        let earlier = Self.snapshot(metrics: metrics, at: now.addingTimeInterval(-3_600), lowBattery: false)
        switch state {
        case .disconnected:
            model = AppViewModel(
                auth: AuthStub(configured: false, connected: false),
                api: SnapshotStub(results: []),
                now: { now },
                checkConnectionOnInit: false
            )
            await model.updateConnectionState()
        case .connected:
            model = try await Self.connected(results: [.success(full)], metrics: metrics, now: now)
        case .refreshing:
            // The second refresh is held open, leaving the model visibly
            // refreshing over the data from the first.
            let api = SnapshotStub(results: [.success(full), .success(full)], heldCall: 2)
            model = try await Self.connected(api: api, results: [.success(full)], metrics: metrics, now: now)
            let model = model
            Task { await model.refreshNow(metrics: metrics) }
            await api.started.wait()
            release = { api.release.open() }
        case .partialFailure:
            var partial = full
            partial.readings[.sleep] = OuraAPI.placeholder(for: .timedOut)
            partial.failedMetrics = [.sleep: .timedOut]
            partial.battery = nil
            partial.batteryFailed = true
            model = try await Self.connected(results: [.success(earlier), .success(partial)], metrics: metrics, now: now)
        case .failed:
            model = try await Self.connected(
                results: [.success(earlier), .failure(.timedOut)],
                metrics: metrics,
                now: now
            )
        case .noData:
            var empty = full
            for metric in metrics {
                empty.readings[metric] = OuraAPI.placeholder(for: nil)
            }
            model = try await Self.connected(results: [.success(empty)], metrics: metrics, now: now)
        case .permissionRequired:
            var denied = full
            denied.readings[.stress] = OuraAPI.placeholder(for: .insufficientScope)
            denied.failedMetrics = [.stress: .insufficientScope]
            model = try await Self.connected(results: [.success(denied)], metrics: metrics, now: now)
        case .resilienceAndLowBattery:
            let low = Self.snapshot(metrics: metrics, at: now, lowBattery: true)
            model = try await Self.connected(results: [.success(low)], metrics: metrics, now: now)
        }
    }

    private static func loadLandscapePhoto() {
        guard MenuPopoverBackground.landscapeImageOverride == nil else { return }
        let photo = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Sources/RingStats/Resources/Assets.xcassets/LandscapeBackground.imageset/LandscapeBackground.png")
        MenuPopoverBackground.landscapeImageOverride = NSImage(contentsOf: photo)
    }

    private static func connected(
        api: SnapshotStub? = nil,
        results: [Result<HealthSnapshot, RingStatsError>],
        metrics: Set<Metric>,
        now: Date
    ) async throws -> AppViewModel {
        let api = api ?? SnapshotStub(results: results)
        let model = AppViewModel(
            auth: AuthStub(configured: true, connected: true),
            api: api,
            now: { now },
            checkConnectionOnInit: false
        )
        await model.updateConnectionState()
        let calls = max(1, results.count)
        for _ in 0..<calls {
            await model.refreshNow(metrics: metrics)
        }
        return model
    }

    static func snapshot(metrics: Set<Metric>, at date: Date, lowBattery: Bool) -> HealthSnapshot {
        let today = QueryDates.dayString(for: date)
        var readings: [Metric: MetricReading] = [:]
        let scores: [Metric: Int] = [.readiness: 84, .sleep: 78, .activity: 91]
        for metric in metrics {
            switch metric {
            case .readiness, .sleep, .activity:
                let score = scores[metric]!
                readings[metric] = MetricReading(
                    value: String(score),
                    detail: ScoreBand.label(for: score),
                    score: score,
                    sourceDay: today
                )
            case .heartRate:
                readings[metric] = MetricReading(
                    value: "58",
                    detail: "bpm",
                    score: nil,
                    observedAt: date.addingTimeInterval(-420)
                )
            case .stress:
                readings[metric] = MetricReading(value: "42m", detail: "Normal", score: nil, sourceDay: today)
            case .resilience:
                readings[metric] = MetricReading(value: "Solid", detail: "Long-term", score: nil, sourceDay: today)
            }
        }
        let formatter = ISO8601DateFormatter()
        return HealthSnapshot(
            readings: readings,
            battery: BatteryRecord(
                level: lowBattery ? 12 : 76,
                charging: false,
                inCharger: false,
                timestamp: formatter.string(from: date.addingTimeInterval(-900))
            ),
            fetchedAt: date,
            coveredMetrics: metrics
        )
    }

    func renderPopover(width: CGFloat) throws -> GalleryRender {
        let view = MenuPopoverShell(geometry: PopoverGeometryModel()) {
            MenuPopoverView(refresh: {}, showConnection: {}, showAppearance: {}, showAbout: {})
                .environmentObject(model)
        }
        .defaultAppStorage(defaults)
        defer { release() }
        return try GalleryRender(view: view, width: width)
    }
}

/// A view laid out in an offscreen window and captured at 2x.
@MainActor
struct GalleryRender {
    let size: CGSize
    let png: Data
    let hasVisibleContent: Bool

    init<V: View>(view: V, width: CGFloat) throws {
        let hosting = NSHostingView(rootView: view.frame(width: width))
        let fitted = hosting.fittingSize
        let size = CGSize(width: width, height: min(fitted.height, 1_200))
        hosting.frame = CGRect(origin: .zero, size: size)
        let window = NSWindow(
            contentRect: hosting.frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        window.backgroundColor = .clear
        window.contentView = hosting
        hosting.layoutSubtreeIfNeeded()
        // Let SwiftUI settle onAppear-driven state before capturing.
        RunLoop.main.run(until: Date().addingTimeInterval(0.05))
        hosting.layoutSubtreeIfNeeded()

        let scale: CGFloat = 2
        guard let bitmap = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: Int(size.width * scale),
            pixelsHigh: Int(size.height * scale),
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ) else { throw GalleryError.renderFailed }
        bitmap.size = size
        hosting.cacheDisplay(in: hosting.bounds, to: bitmap)
        window.close()

        guard let png = bitmap.representation(using: .png, properties: [:]) else {
            throw GalleryError.renderFailed
        }
        self.size = size
        self.png = png
        self.hasVisibleContent = Self.countOpaquePixels(bitmap) > Int(size.width * size.height * 0.2)
    }

    private static func countOpaquePixels(_ bitmap: NSBitmapImageRep) -> Int {
        var count = 0
        for y in Swift.stride(from: 0, to: bitmap.pixelsHigh, by: 4) {
            for x in Swift.stride(from: 0, to: bitmap.pixelsWide, by: 4) {
                if (bitmap.colorAt(x: x, y: y)?.alphaComponent ?? 0) > 0.5 { count += 16 }
            }
        }
        return count / 4
    }
}

enum GalleryError: Error {
    case renderFailed
}

/// Writes renders and an HTML contact sheet for human review.
struct GalleryWriter {
    let directory: URL
    private let names = NameList()

    init(subdirectory: String = "popover") throws {
        let root = ProcessInfo.processInfo.environment["RING_STATS_GALLERY_DIR"].map(URL.init(fileURLWithPath:))
            ?? URL(fileURLWithPath: #filePath)
                .deletingLastPathComponent()
                .deletingLastPathComponent()
                .deletingLastPathComponent()
                .appendingPathComponent(".build/state-gallery")
        directory = root.appendingPathComponent(subdirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    func add(_ render: GalleryRender, name: String) throws {
        try render.png.write(to: directory.appendingPathComponent("\(name).png"))
        names.append(name)
    }

    func writeIndex() throws {
        let items = names.values.map { name in
            "<figure><img src=\"\(name).png\"><figcaption>\(name)</figcaption></figure>"
        }.joined(separator: "\n")
        let html = """
        <!doctype html><meta charset="utf-8"><title>Ring Stats state gallery</title>
        <style>body{font:13px -apple-system;background:#888;margin:24px}figure{display:inline-block;margin:12px;vertical-align:top}
        img{display:block;max-width:420px;height:auto}figcaption{color:#fff;margin-top:4px}</style>
        \(items)
        """
        try Data(html.utf8).write(to: directory.appendingPathComponent("index.html"))
    }
}

private final class NameList: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: [String] = []
    var values: [String] { lock.withLock { stored } }
    func append(_ name: String) { lock.withLock { stored.append(name) } }
}
