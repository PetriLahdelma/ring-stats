import AppKit
import Foundation
import Testing
@testable import RingStats

/// The Holographic hover twist and pinch.
@MainActor
struct HolographicMotionTests {
    private let size = CGSize(width: 840, height: 260)

    @Test func twistFollowsThePointerUpToThreeDegrees() {
        #expect(HolographicMotion.twist(at: CGPoint(x: 420, y: 100), in: size) == 0)
        #expect(HolographicMotion.twist(at: CGPoint(x: 840, y: 100), in: size) == 3)
        #expect(HolographicMotion.twist(at: CGPoint(x: 0, y: 100), in: size) == -3)
        #expect(HolographicMotion.twist(at: CGPoint(x: 630, y: 100), in: size) == 1.5)
        #expect(HolographicMotion.twist(at: CGPoint(x: 2000, y: 100), in: size) == 3)
    }

    /// Every corner of the popover, rotated by the maximum twist, stays inside
    /// the enlarged canvas, so no edge of the marble ever shows.
    @Test(arguments: [CGSize(width: 840, height: 260), CGSize(width: 420, height: 300), CGSize(width: 680, height: 600)])
    func twistedCanvasAlwaysCoversThePopover(size: CGSize) {
        let canvas = HolographicMotion.canvasSize(for: size)
        for sign in [-1.0, 1.0] {
            let angle = CGFloat(sign * HolographicMotion.maximumTwist * .pi / 180)
            for corner in [CGPoint(x: -1, y: -1), CGPoint(x: 1, y: -1), CGPoint(x: -1, y: 1), CGPoint(x: 1, y: 1)] {
                let x = corner.x * size.width / 2, y = corner.y * size.height / 2
                let rx = x * cos(angle) - y * sin(angle), ry = x * sin(angle) + y * cos(angle)
                #expect(abs(rx) <= canvas.width / 2 + 0.001, "\(size) \(sign)")
                #expect(abs(ry) <= canvas.height / 2 + 0.001, "\(size) \(sign)")
            }
        }
    }

    @Test func pointerMapsIntoTheCanvasThroughTheTwist() {
        let canvas = HolographicMotion.canvasSize(for: size)
        let center = HolographicMotion.canvasPoint(for: CGPoint(x: 420, y: 130), in: size, twist: 3)
        #expect(abs(center.x - canvas.width / 2) < 0.001 && abs(center.y - canvas.height / 2) < 0.001)
        let flat = HolographicMotion.canvasPoint(for: CGPoint(x: 700, y: 60), in: size, twist: 0)
        #expect(abs(flat.x - (700 + (canvas.width - 840) / 2)) < 0.001)
        let twisted = HolographicMotion.canvasPoint(for: CGPoint(x: 700, y: 60), in: size, twist: 3)
        #expect(twisted != flat)
    }

    /// A pinch at the very edge must not pull the edge inward and leave it
    /// empty: every pixel along each side stays fully opaque.
    @Test(arguments: [CGPoint(x: 2, y: 130), CGPoint(x: 838, y: 20), CGPoint(x: 420, y: 258)])
    func pinchNearAnEdgeKeepsTheEdgeFilled(pointer: CGPoint) throws {
        let source = try #require(NSImage(contentsOf: Self.marbleURL))
        let canvas = HolographicMotion.canvasSize(for: size)
        let point = HolographicMotion.canvasPoint(for: pointer, in: size, twist: 0)
        let image = try #require(HolographicDistorter().render(source: source, pointer: point, strength: 1, canvas: canvas, scale: 1))
        let width = image.width, height = image.height
        let context = try #require(CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        let pixels = try #require(context.data).bindMemory(to: UInt8.self, capacity: width * height * 4)
        var transparent = 0
        for y in 0..<height {
            for x in [0, 1, width - 2, width - 1] where pixels[(y * width + x) * 4 + 3] < 255 { transparent += 1 }
        }
        for x in 0..<width {
            for y in [0, 1, height - 2, height - 1] where pixels[(y * width + x) * 4 + 3] < 255 { transparent += 1 }
        }
        #expect(transparent == 0, "\(transparent) edge pixels are not opaque for a pinch at \(pointer)")
    }

    private static let marbleURL = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("Sources/RingStats/Resources/Assets.xcassets/HolographicMarble.imageset/HolographicMarble.jpg")

    @Test func distorterRendersTheCanvasAtDisplayScale() throws {
        let marble = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Sources/RingStats/Resources/Assets.xcassets/HolographicMarble.imageset/HolographicMarble.jpg")
        let source = try #require(NSImage(contentsOf: marble))
        let canvas = HolographicMotion.canvasSize(for: size)
        let image = try #require(HolographicDistorter().render(
            source: source, pointer: CGPoint(x: 600, y: 90), strength: 1, canvas: canvas, scale: 2
        ))
        #expect(image.width == Int((canvas.width * 2).rounded()))
        #expect(image.height == Int((canvas.height * 2).rounded()))
    }
}
