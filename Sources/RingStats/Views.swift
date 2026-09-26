import AppKit
import SwiftUI

enum Palette {
    static let canvasWarm = Color(red: 244 / 255, green: 241 / 255, blue: 236 / 255)
    static let separator = Color(red: 218 / 255, green: 211 / 255, blue: 202 / 255)
    static let signalBlue = Color(red: 55 / 255, green: 83 / 255, blue: 119 / 255)
    static let ink = Color(red: 24 / 255, green: 27 / 255, blue: 31 / 255)
    static let alert = Color(red: 224 / 255, green: 92 / 255, blue: 78 / 255)
}

private extension AppTheme {
    var primaryContent: Color {
        self == .landscape ? .white : Palette.ink
    }

    var secondaryContent: Color {
        self == .landscape ? .white.opacity(0.78) : Palette.ink.opacity(0.62)
    }

    var action: Color {
        self == .landscape ? .white : Palette.signalBlue
    }

    var divider: Color {
        self == .landscape ? .white.opacity(0.28) : Palette.separator
    }

    var score: Color {
        self == .landscape ? .white : Palette.signalBlue
    }
}

private struct MenuPopoverBackground: View {
    let theme: AppTheme

    var body: some View {
        if theme == .landscape {
            GeometryReader { geometry in
                ZStack {
                    Image("LandscapeBackground")
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
}

private struct MenuPopoverBubbleShape: Shape {
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
        .frame(minWidth: 420, maxWidth: .infinity)
        .background { MenuPopoverBackground(theme: theme) }
        .clipShape(MenuPopoverBubbleShape(arrowX: geometry.arrowX))
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

struct MenuPopoverView: View {
    @EnvironmentObject private var model: AppViewModel
    let showConnection: () -> Void
    let showAppearance: () -> Void
    let showAbout: () -> Void
    @AppStorage(AppTheme.storageKey) private var selectedThemeRaw = AppTheme.ringStats.rawValue
    @AppStorage(MetricConfiguration.storageKey) private var metricConfigurationRaw = MetricConfiguration.default.encoded
    @State private var dropTarget: Metric?

    private var theme: AppTheme {
        AppTheme.resolve(selectedThemeRaw)
    }

    private var metricConfiguration: MetricConfiguration {
        MetricConfiguration.decode(metricConfigurationRaw)
    }

    private var missingPermissionMetrics: [Metric] {
        metricConfiguration.visibleMetrics.filter {
            model.snapshot.readings[$0]?.detail == "Permission required"
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

    private func reorderMetric(_ source: Metric, relativeTo target: Metric, dropX: CGFloat) {
        let updated = metricConfiguration.moving(source, relativeTo: target, after: dropX >= 46)
        metricConfigurationRaw = updated.encoded
    }

    private var customizeMetric: some View {
        Button(action: showAppearance) {
            VStack(spacing: 0) {
                Image(systemName: "pencil")
                    .font(.system(size: 20, weight: .regular))
                    .frame(width: 84, height: 84)
                Text("Customize")
                    .font(.system(size: 12, weight: .semibold))
                    .padding(.top, 12)
            }
            .frame(width: 92)
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
            Button(action: showAbout) {
                Label("About & Credits", systemImage: "info.circle")
            }
            Divider()
            Button(model.loading ? "Reauthorizing…" : "Reauthorize Permissions") {
                Task { await model.reauthorize() }
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
            if model.connected {
                ScrollView(.horizontal) {
                    HStack(alignment: .top, spacing: 16) {
                        ForEach(metricConfiguration.visibleMetrics) { metric in
                            let reading = model.snapshot.readings[metric]
                            MetricGauge(
                                metric: metric,
                                reading: reading,
                                pending: Self.metricIsPending(reading: reading, loading: model.loading),
                                theme: theme
                            )
                            .contentShape(Rectangle())
                            .draggable(metric.rawValue)
                            .dropDestination(for: String.self) { values, location in
                                guard let rawValue = values.first,
                                      let source = Metric(rawValue: rawValue) else { return false }
                                reorderMetric(source, relativeTo: metric, dropX: location.x)
                                dropTarget = nil
                                return true
                            } isTargeted: { targeted in
                                dropTarget = targeted ? metric : nil
                            }
                            .overlay {
                                if dropTarget == metric {
                                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                                        .stroke(theme.action.opacity(0.72), lineWidth: 1.5)
                                }
                            }
                            .accessibilityHint("Drag to reorder. The same order appears in Appearance.")
                        }
                        customizeMetric
                    }
                    .animation(.easeInOut(duration: 0.16), value: metricConfigurationRaw)
                }
                .scrollIndicators(.hidden)
                if !missingPermissionMetrics.isEmpty {
                    Button {
                        Task { await model.reauthorize() }
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
        .task { await model.refresh() }
    }
}

struct MetricGauge: View {
    let metric: Metric
    let reading: MetricReading?
    let pending: Bool
    let theme: AppTheme

    private var fraction: Double {
        Double(max(0, min(reading?.score ?? 0, 100))) / 100
    }

    private var displayValue: String { reading?.value ?? "—" }

    private var valueFontSize: CGFloat {
        metric == .resilience ? 18 : 28
    }

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                if pending {
                    ScoreLoadingSpinner(theme: theme)
                        .accessibilityLabel("\(metric.title) updating")
                } else if theme == .landscape || !metric.isDailyScore {
                    VStack(spacing: 3) {
                        Image(systemName: metric.symbolName)
                            .font(.system(size: 18, weight: .regular))
                        Text(displayValue)
                            .font(.system(size: valueFontSize, weight: .medium, design: .rounded))
                            .monospacedDigit()
                    }
                    .foregroundStyle(theme.primaryContent)
                } else {
                    if reading?.score != nil {
                        Circle()
                            .trim(from: 0, to: fraction)
                            .stroke(theme.score, style: StrokeStyle(lineWidth: 8, lineCap: .round))
                            .rotationEffect(.degrees(-90))
                    }
                    Text(displayValue)
                        .font(.system(size: 28, weight: .medium, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(theme.primaryContent)
                }
            }
            .frame(width: 84, height: 84)
            .accessibilityHidden(true)
            VStack(spacing: 2) {
                Text(metric.title)
                    .font(.system(size: 12, weight: .semibold))
                if theme != .landscape {
                    Text(pending ? "Updating…" : reading?.detail ?? "No data")
                    .font(.system(size: 11))
                    .foregroundStyle(theme.secondaryContent)
                    .lineLimit(1)
                    .contentTransition(.opacity)
                }
            }
            .padding(.top, 12)
        }
        .frame(width: 92)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            pending
                ? "\(metric.title) updating"
                : "\(metric.title), \(reading?.value ?? "no data"), \(reading?.detail ?? "")"
        )
    }
}

private struct ScoreLoadingSpinner: View {
    let theme: AppTheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var rotating = false

    var body: some View {
        Circle()
            .trim(from: 0.08, to: 0.72)
            .stroke(
                theme.primaryContent.opacity(theme == .landscape ? 0.72 : 0.56),
                style: StrokeStyle(lineWidth: 2.5, lineCap: .round)
            )
            .frame(width: 18, height: 18)
            .rotationEffect(.degrees(rotating ? 360 : 0))
            .onAppear {
                guard !reduceMotion else { return }
                withAnimation(.linear(duration: 0.8).repeatForever(autoreverses: false)) {
                    rotating = true
                }
            }
    }
}

struct BatteryRow: View {
    let battery: BatteryRecord?
    let loading: Bool
    let theme: AppTheme

    private var batteryStatus: String {
        guard let battery else { return "Battery" }
        return battery.level.map { "Battery \($0)%" } ?? "Battery —"
    }

    private var chargingStatus: String {
        guard let battery else { return loading ? "Updating…" : "Unavailable" }
        return battery.charging == true || battery.inCharger == true ? "Charging" : "Not charging"
    }

    var body: some View {
        HStack(spacing: 7) {
            BatteryStatusIcon(
                level: battery?.level,
                charging: battery?.charging == true || battery?.inCharger == true,
                theme: theme
            )
            HStack(spacing: 8) {
                Text(batteryStatus)
                    .monospacedDigit()
                    .foregroundStyle(theme.primaryContent)
                Text(chargingStatus)
                    .foregroundStyle(theme.primaryContent.opacity(0.5))
            }
        }
        .font(.system(size: 12, weight: .medium))
        .accessibilityElement(children: .combine)
    }
}

struct BatteryStatusIcon: View {
    let level: Int?
    let charging: Bool
    let theme: AppTheme

    private var symbolName: String {
        guard let level else { return "battery.0" }
        return switch level {
        case ..<13: "battery.0"
        case ..<38: "battery.25"
        case ..<63: "battery.50"
        case ..<88: "battery.75"
        default: "battery.100"
        }
    }

    private var tint: Color {
        if theme == .landscape { return .white }
        guard let level else { return Palette.alert }
        return level < 20 ? Palette.alert : Palette.signalBlue
    }

    var body: some View {
        ZStack {
            Image(systemName: symbolName)
                .font(.system(size: 17, weight: .medium))
            if charging {
                Image(systemName: "bolt.fill")
                    .font(.system(size: 7, weight: .bold))
            }
        }
        .frame(width: 22, height: 20)
        .foregroundStyle(tint)
        .accessibilityHidden(true)
    }
}

struct AppearanceSettingsView: View {
    @AppStorage(AppTheme.storageKey) private var selectedThemeRaw = AppTheme.ringStats.rawValue
    @AppStorage(MetricConfiguration.storageKey) private var rawConfiguration = MetricConfiguration.default.encoded
    @State private var configuration: MetricConfiguration

    init() {
        let stored = UserDefaults.standard.string(forKey: MetricConfiguration.storageKey)
        _configuration = State(initialValue: MetricConfiguration.decode(stored))
    }

    private var selectedTheme: AppTheme {
        AppTheme.resolve(selectedThemeRaw)
    }

    private func apply(_ updated: MetricConfiguration) {
        let normalized = updated.normalized
        configuration = normalized
        rawConfiguration = normalized.encoded
    }

    private func visibilityBinding(for metric: Metric) -> Binding<Bool> {
        Binding {
            !configuration.hidden.contains(metric)
        } set: { visible in
            var updated = configuration
            if visible {
                updated.hidden.remove(metric)
            } else if updated.visibleMetrics.count > 1 {
                updated.hidden.insert(metric)
            }
            apply(updated)
        }
    }

    private func move(_ metric: Metric, offset: Int) {
        guard let source = configuration.order.firstIndex(of: metric) else { return }
        let destination = source + offset
        guard configuration.order.indices.contains(destination) else { return }
        var updated = configuration
        updated.order.swapAt(source, destination)
        apply(updated)
    }

    private func themeOption(_ theme: AppTheme) -> some View {
        let selected = selectedTheme == theme
        return Button {
            selectedThemeRaw = theme.rawValue
        } label: {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(selected ? Palette.signalBlue : Palette.ink.opacity(0.36))
                    .frame(width: 20, height: 20)

                VStack(alignment: .leading, spacing: 3) {
                    Text(theme.title)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(Palette.ink)
                    Text(theme.summary)
                        .font(.caption)
                        .foregroundStyle(Palette.ink.opacity(0.62))
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(theme.title)
        .accessibilityValue(selected ? "Selected" : "Not selected")
        .accessibilityHint(theme.summary)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Appearance")
                .font(.title2.weight(.semibold))
            Text("Choose the popover theme, visible stats, and their order.")
                .foregroundStyle(.secondary)

            Text("Theme")
                .font(.headline)
                .padding(.top, 6)

            VStack(spacing: 0) {
                themeOption(.ringStats)
                Divider()
                    .overlay(Palette.separator)
                    .padding(.leading, 46)
                themeOption(.landscape)
            }
            .background(.white.opacity(0.66))
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(Palette.separator, lineWidth: 1)
            }

            Divider()
                .overlay(Palette.separator)
                .padding(.vertical, 6)

            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Stats")
                        .font(.headline)
                    Text("Show, hide, or reorder the items in the popover.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("Reset") {
                    apply(.default)
                }
            }

            List {
                ForEach(configuration.order) { metric in
                    HStack(spacing: 10) {
                        Toggle(isOn: visibilityBinding(for: metric)) {
                            Label(metric.title, systemImage: metric.symbolName)
                        }
                        .toggleStyle(.checkbox)

                        Spacer()

                        let index = configuration.order.firstIndex(of: metric) ?? 0
                        Button {
                            move(metric, offset: -1)
                        } label: {
                            Image(systemName: "chevron.up")
                        }
                        .buttonStyle(.borderless)
                        .disabled(index == configuration.order.startIndex)
                        .accessibilityLabel("Move \(metric.title) up")

                        Button {
                            move(metric, offset: 1)
                        } label: {
                            Image(systemName: "chevron.down")
                        }
                        .buttonStyle(.borderless)
                        .disabled(index == configuration.order.index(before: configuration.order.endIndex))
                        .accessibilityLabel("Move \(metric.title) down")
                    }
                    .padding(.vertical, 3)
                }
            }
            .frame(height: 260)
            .scrollContentBackground(.hidden)

            Text("At least one stat must remain visible. You can also drag visible stats directly in the popover.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(24)
        .frame(width: 500, height: 620, alignment: .topLeading)
        .background(Palette.canvasWarm)
        .foregroundStyle(Palette.ink)
        .preferredColorScheme(.light)
        .onChange(of: rawConfiguration) { _, newValue in
            let updated = MetricConfiguration.decode(newValue)
            if updated != configuration {
                configuration = updated
            }
        }
    }
}

struct AboutCreditsView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Ring Stats")
                .font(.title2.weight(.semibold))
            Text("Version \(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0")")
                .font(.caption)
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 2) {
                Text("Created by")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("Digitaltableteur")
                    .font(.callout.weight(.medium))
            }
            .accessibilityElement(children: .combine)

            Text("A small independent menu-bar viewer for your Oura data. Not affiliated with or endorsed by Oura Health Oy.")
                .fixedSize(horizontal: false, vertical: true)
            Text("Oura and Oura Ring are trademarks of Oura Health Oy. Data supplied by the Oura API. Built with SwiftUI.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(24)
        .frame(width: 420)
        .background(Palette.canvasWarm)
        .foregroundStyle(Palette.ink)
        .preferredColorScheme(.light)
    }
}

struct ConnectionSettingsView: View {
    @EnvironmentObject private var model: AppViewModel
    @Environment(\.dismiss) private var dismiss
    let onConnected: () -> Void
    @State private var clientID = ""
    @State private var clientSecret = ""
    @State private var showingDisconnectConfirmation = false

    init(onConnected: @escaping () -> Void = {}) {
        self.onConnected = onConnected
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Oura Connection")
                .font(.title2.weight(.semibold))

            if model.connected {
                Label("Oura account connected", systemImage: "checkmark.circle")
                    .font(.callout.weight(.medium))
                if let error = model.errorMessage {
                    Text(error).font(.caption).foregroundStyle(.red).textSelection(.enabled)
                }
                Button(model.loading ? "Reauthorizing…" : "Reauthorize Permissions") {
                    Task { await model.reauthorize() }
                }
                .disabled(model.loading)

                Divider()
                    .overlay(Palette.separator)

                VStack(alignment: .leading, spacing: 8) {
                    Text("Disconnecting revokes the current token and deletes the saved client credentials from this Mac.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Button("Disconnect & Delete Local Data", role: .destructive) {
                        showingDisconnectConfirmation = true
                    }
                    .disabled(model.loading)
                }
            } else {
                Text("Create an application in Oura’s developer portal and use this exact callback URL:")
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Link("Open Oura developer portal", destination: URL(string: "https://developer.ouraring.com/applications")!)
                    .foregroundStyle(Palette.signalBlue)
                Text(OAuthClient.callbackURL).font(.system(.body, design: .monospaced)).textSelection(.enabled)
                TextField("Client ID", text: $clientID)
                SecureField("Client Secret", text: $clientSecret)
                if let error = model.errorMessage {
                    Text(error).font(.caption).foregroundStyle(.red).textSelection(.enabled)
                }
                HStack {
                    Spacer()
                    Button(model.loading ? "Connecting…" : "Connect in Browser") {
                        Task { await model.connect(clientID: clientID, clientSecret: clientSecret) }
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(Palette.signalBlue)
                    .disabled(model.loading || clientID.isEmpty || clientSecret.isEmpty)
                }
            }
        }
        .padding(24)
        .frame(width: 460)
        .background(Palette.canvasWarm)
        .foregroundStyle(Palette.ink)
        .preferredColorScheme(.light)
        .confirmationDialog(
            "Disconnect and delete saved authorization?",
            isPresented: $showingDisconnectConfirmation
        ) {
            Button("Disconnect & Delete", role: .destructive) {
                Task { await model.disconnect() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Ring Stats will revoke the current Oura token and remove the saved OAuth token, Client ID, and Client Secret from macOS Keychain.")
        }
        .onChange(of: model.connected) { _, connected in
            if connected {
                dismiss()
                onConnected()
            }
        }
    }
}
