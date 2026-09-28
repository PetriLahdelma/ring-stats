import AppKit
import SwiftUI
import RingStatsCore
import RingStatsOura

struct MenuPopoverBackground: View {
    /// Lets the state gallery supply the photograph, which lives in the app's
    /// compiled asset catalog and is not visible to the test process.
    @MainActor static var landscapeImageOverride: NSImage?

    let theme: AppTheme

    private var landscapeImage: Image {
        Self.landscapeImageOverride.map(Image.init(nsImage:)) ?? Image("LandscapeBackground")
    }

    var body: some View {
        if theme == .landscape {
            GeometryReader { geometry in
                ZStack {
                    landscapeImage
                        .resizable()
                        .scaledToFill()
                        .frame(width: geometry.size.width, height: geometry.size.height)
                        .clipped()
                    LinearGradient(
                        colors: [.black.opacity(0.38), .black.opacity(0.68)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                }
            }
        } else {
            Palette.canvasWarm
        }
    }
}

@MainActor
final class PopoverGeometryModel: ObservableObject {
    @Published var arrowX: CGFloat = 210
    /// Whether the panel is on screen. Timers inside the popover pause while it
    /// is hidden, because the hosting view lives for the life of the app.
    @Published var isPresented = true
}

extension EnvironmentValues {
    @Entry var popoverIsPresented = true
}

struct MenuPopoverBubbleShape: Shape {
    let arrowX: CGFloat
    private let arrowHeight: CGFloat = 11
    private let arrowWidth: CGFloat = 34
    private let cornerRadius: CGFloat = 20

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let body = CGRect(
            x: rect.minX,
            y: rect.minY + arrowHeight,
            width: rect.width,
            height: max(0, rect.height - arrowHeight)
        )

        let minimumArrowX = body.minX + cornerRadius + arrowWidth / 2
        let maximumArrowX = body.maxX - cornerRadius - arrowWidth / 2
        let resolvedArrowX = min(max(arrowX, minimumArrowX), maximumArrowX)
        let arrowLeft = resolvedArrowX - arrowWidth / 2
        let arrowRight = resolvedArrowX + arrowWidth / 2
        let arrowTip = CGPoint(x: resolvedArrowX, y: rect.minY + 1)

        path.move(to: CGPoint(x: body.minX + cornerRadius, y: body.minY))
        path.addLine(to: CGPoint(x: arrowLeft, y: body.minY))
        path.addCurve(
            to: arrowTip,
            control1: CGPoint(x: arrowLeft + 6, y: body.minY),
            control2: CGPoint(x: arrowTip.x - 3, y: arrowTip.y)
        )
        path.addCurve(
            to: CGPoint(x: arrowRight, y: body.minY),
            control1: CGPoint(x: arrowTip.x + 3, y: arrowTip.y),
            control2: CGPoint(x: arrowRight - 6, y: body.minY)
        )
        path.addLine(to: CGPoint(x: body.maxX - cornerRadius, y: body.minY))
        path.addArc(
            tangent1End: CGPoint(x: body.maxX, y: body.minY),
            tangent2End: CGPoint(x: body.maxX, y: body.minY + cornerRadius),
            radius: cornerRadius
        )
        path.addLine(to: CGPoint(x: body.maxX, y: body.maxY - cornerRadius))
        path.addArc(
            tangent1End: CGPoint(x: body.maxX, y: body.maxY),
            tangent2End: CGPoint(x: body.maxX - cornerRadius, y: body.maxY),
            radius: cornerRadius
        )
        path.addLine(to: CGPoint(x: body.minX + cornerRadius, y: body.maxY))
        path.addArc(
            tangent1End: CGPoint(x: body.minX, y: body.maxY),
            tangent2End: CGPoint(x: body.minX, y: body.maxY - cornerRadius),
            radius: cornerRadius
        )
        path.addLine(to: CGPoint(x: body.minX, y: body.minY + cornerRadius))
        path.addArc(
            tangent1End: CGPoint(x: body.minX, y: body.minY),
            tangent2End: CGPoint(x: body.minX + cornerRadius, y: body.minY),
            radius: cornerRadius
        )
        path.closeSubpath()
        return path
    }
}

struct MenuPopoverShell<Content: View>: View {
    @AppStorage(AppTheme.storageKey) private var selectedThemeRaw = AppTheme.ringStats.rawValue
    @ObservedObject private var geometry: PopoverGeometryModel
    private let content: Content

    private var theme: AppTheme {
        AppTheme.resolve(selectedThemeRaw)
    }

    init(geometry: PopoverGeometryModel, @ViewBuilder content: () -> Content) {
        self.geometry = geometry
        self.content = content()
    }

    var body: some View {
        VStack(spacing: 0) {
            Color.clear.frame(height: 11)
            content
        }
        .environment(\.popoverIsPresented, geometry.isPresented)
        .followsTextSizePreference()
        .frame(minWidth: 420, maxWidth: .infinity)
        // Clip only the background. Clipping the whole popover to this custom
        // shape masks the content layer, which renders multi-layer SF Symbols
        // such as the battery gauge white instead of their foreground color.
        .background {
            MenuPopoverBackground(theme: theme)
                .clipShape(MenuPopoverBubbleShape(arrowX: geometry.arrowX))
        }
        .overlay {
            MenuPopoverBubbleShape(arrowX: geometry.arrowX)
                .stroke(
                    theme == .landscape ? .white.opacity(0.24) : .black.opacity(0.18),
                    lineWidth: 1
                )
        }
    }
}

struct RingStatsLogoView: View {
    let size: CGFloat
    var color: Color = .primary

    var body: some View {
        Canvas { context, canvas in
            let sourceWidth: CGFloat = 526
            let sourceHeight: CGFloat = 251.512
            let scale = min(canvas.width / sourceWidth, canvas.height / sourceHeight)
            let xOffset = (canvas.width - sourceWidth * scale) / 2
            let yOffset = (canvas.height - sourceHeight * scale) / 2
            func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
                CGPoint(x: xOffset + x * scale, y: yOffset + y * scale)
            }

            var lowerRing = Path()
            lowerRing.move(to: point(517.817, 110.911))
            lowerRing.addCurve(to: point(526, 142.113), control1: point(523.16, 120.887), control2: point(526, 131.342))
            lowerRing.addCurve(to: point(263, 251.512), control1: point(526, 211.465), control2: point(408.251, 251.512))
            lowerRing.addCurve(to: point(0, 142.113), control1: point(117.749, 251.512), control2: point(0.000492217, 211.465))
            lowerRing.addCurve(to: point(8.18262, 110.911), control1: point(0, 131.342), control2: point(2.84024, 120.887))
            lowerRing.addCurve(to: point(263, 169.517), control1: point(62.6995, 146.215), control2: point(156.469, 169.517))
            lowerRing.addCurve(to: point(517.817, 110.911), control1: point(369.531, 169.517), control2: point(463.301, 146.215))
            lowerRing.closeSubpath()
            context.fill(lowerRing, with: .color(color))

            var upperRing = Path()
            upperRing.move(to: point(98.1716, 81.6885))
            upperRing.addCurve(to: point(54.6316, 50.6807), control1: point(70.8771, 73.1177), control2: point(54.6316, 62.361))
            upperRing.addCurve(to: point(263, 0), control1: point(54.6325, 22.6905), control2: point(147.922, 0.0000915429))
            upperRing.addCurve(to: point(471.369, 50.6807), control1: point(378.078, 0.00000816373), control2: point(471.368, 22.6904))
            upperRing.addCurve(to: point(427.83, 81.6885), control1: point(471.369, 62.3608), control2: point(455.124, 73.1177))
            upperRing.addCurve(to: point(263, 50.8291), control1: point(395.481, 63.2731), control2: point(333.787, 50.8291))
            upperRing.addCurve(to: point(98.1716, 81.6885), control1: point(192.213, 50.8292), control2: point(130.521, 63.2735))
            upperRing.closeSubpath()
            context.fill(upperRing, with: .color(color))
        }
        .frame(width: size, height: size * 251.512 / 526)
    }
}
