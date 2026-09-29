import AppKit
import CoreImage
import SwiftUI

/// Pastel marbled foil, like the examples in "Creating Holographic Effects in
/// CSS" (OpenReplay): domain-warped noise mapped through a repeating ramp of
/// pink, butter yellow, pale cyan, lavender, and mint. It is rendered once by
/// `scripts/assets/holographic_marble.swift` (2400 x 1200, seed 21) and bundled,
/// so it costs nothing at rest and stays sharp at every popover size.
///
/// Under the pointer the foil twists up to three degrees toward the side the
/// pointer is on and pinches in at the pointer, like pressing on foil. Only
/// the background moves; text and gauges stay still. Reduce Motion keeps it
/// flat.
struct HolographicBackground: View {
    /// Lets the state gallery supply the image, which lives in the app's
    /// compiled asset catalog and is not visible to the test process.
    @MainActor static var imageOverride: NSImage?

    /// The pointer in this view's coordinates, or nil when it is elsewhere.
    var hover: CGPoint?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.displayScale) private var displayScale
    @StateObject private var distorter = HolographicDistorter()

    private var image: NSImage? {
        Self.imageOverride ?? NSImage(named: "HolographicMarble")
    }

    var body: some View {
        GeometryReader { geometry in
            let size = geometry.size
            let canvas = HolographicMotion.canvasSize(for: size)
            let pointer = reduceMotion ? nil : hover
            let twist = pointer.map { HolographicMotion.twist(at: $0, in: size) } ?? 0
            Group {
                if let pinched = distorter.image {
                    Image(decorative: pinched, scale: displayScale)
                        .resizable()
                } else if let image {
                    Image(nsImage: image)
                        .resizable()
                        .scaledToFill()
                }
            }
            .frame(width: canvas.width, height: canvas.height)
            .rotationEffect(.degrees(twist))
            .animation(.spring(response: 0.45, dampingFraction: 0.85), value: twist)
            .frame(width: size.width, height: size.height)
            .clipped()
            .onChange(of: pointer) { _, point in
                distorter.update(
                    source: image,
                    pointer: point.map { HolographicMotion.canvasPoint(for: $0, in: size, twist: twist) },
                    canvas: canvas,
                    scale: displayScale
                )
            }
        }
    }
}

/// The geometry of the hover effect, kept free of rendering so it can be
/// tested.
enum HolographicMotion {
    static let maximumTwist = 3.0
    /// Core Image pinch strength at full effect.
    static let pinchScale = 0.45

    /// Degrees of twist: the pointer's horizontal distance from the center,
    /// up to `maximumTwist` at either edge.
    static func twist(at point: CGPoint, in size: CGSize) -> Double {
        guard size.width > 0 else { return 0 }
        let offset = (point.x - size.width / 2) / (size.width / 2)
        return max(-1, min(1, offset)) * maximumTwist
    }

    /// The canvas the marble is drawn into, just large enough that twisting it
    /// by `maximumTwist` never reveals a corner.
    static func canvasSize(for size: CGSize) -> CGSize {
        let angle = CGFloat(maximumTwist * .pi / 180)
        let (w, h) = (size.width, size.height)
        guard w > 0, h > 0 else { return size }
        // The bounding box of the popover rotated by the maximum twist. The
        // marble fills it, so at rest it is barely larger than the popover.
        return CGSize(width: w * cos(angle) + h * sin(angle), height: w * sin(angle) + h * cos(angle))
    }

    /// Maps the pointer from the popover into the enlarged, twisted canvas, so
    /// the pinch lands under the pointer.
    static func canvasPoint(for point: CGPoint, in size: CGSize, twist: Double) -> CGPoint {
        let canvas = canvasSize(for: size)
        let center = CGPoint(x: size.width / 2, y: size.height / 2)
        let angle = CGFloat(-twist * .pi / 180)
        let dx = point.x - center.x, dy = point.y - center.y
        let unrotated = CGPoint(
            x: dx * cos(angle) - dy * sin(angle),
            y: dx * sin(angle) + dy * cos(angle)
        )
        return CGPoint(x: unrotated.x + canvas.width / 2, y: unrotated.y + canvas.height / 2)
    }
}

/// Renders the pinched marble with Core Image on the GPU. It keeps one
/// context, renders at most one frame per run-loop turn, and eases the pinch
/// out when the pointer leaves.
@MainActor
final class HolographicDistorter: ObservableObject {
    @Published private(set) var image: CGImage?

    private static let context = CIContext(options: [.cacheIntermediates: false])
    private var base: (source: ObjectIdentifier, image: CIImage)?
    private var lastPointer: CGPoint?
    private var fade: Task<Void, Never>?

    func update(source: NSImage?, pointer: CGPoint?, canvas: CGSize, scale: CGFloat) {
        guard let source, canvas.width > 0, canvas.height > 0 else { return }
        fade?.cancel()
        if let pointer {
            lastPointer = pointer
            image = render(source: source, pointer: pointer, strength: 1, canvas: canvas, scale: scale)
            return
        }
        guard let last = lastPointer else { return }
        fade = Task { [weak self] in
            for step in stride(from: 0.8, through: 0, by: -0.2) {
                try? await Task.sleep(for: .milliseconds(16))
                guard let self, !Task.isCancelled else { return }
                self.image = step > 0
                    ? self.render(source: source, pointer: last, strength: step, canvas: canvas, scale: scale)
                    : nil
            }
            self?.lastPointer = nil
        }
    }

    func render(source: NSImage, pointer: CGPoint, strength: Double, canvas: CGSize, scale: CGFloat) -> CGImage? {
        let id = ObjectIdentifier(source)
        if base?.source != id {
            guard let cgImage = source.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
            base = (id, CIImage(cgImage: cgImage))
        }
        guard let marble = base?.image else { return nil }
        let pixels = CGSize(width: (canvas.width * scale).rounded(), height: (canvas.height * scale).rounded())
        let fill = max(pixels.width / marble.extent.width, pixels.height / marble.extent.height)
        var placed = marble.transformed(by: CGAffineTransform(scaleX: fill, y: fill))
        placed = placed.transformed(by: CGAffineTransform(
            translationX: (pixels.width - placed.extent.width) / 2 - placed.extent.minX,
            y: (pixels.height - placed.extent.height) / 2 - placed.extent.minY
        ))
        guard let pinch = CIFilter(name: "CIPinchDistortion") else { return nil }
        pinch.setValue(placed, forKey: kCIInputImageKey)
        // Core Image's origin is at the bottom.
        pinch.setValue(CIVector(x: pointer.x * scale, y: pixels.height - pointer.y * scale), forKey: kCIInputCenterKey)
        pinch.setValue(min(pixels.width, pixels.height) * 0.6, forKey: kCIInputRadiusKey)
        pinch.setValue(HolographicMotion.pinchScale * strength, forKey: kCIInputScaleKey)
        let bounds = CGRect(origin: .zero, size: pixels)
        guard let output = pinch.outputImage?.cropped(to: bounds) else { return nil }
        return Self.context.createCGImage(output, from: bounds)
    }
}
