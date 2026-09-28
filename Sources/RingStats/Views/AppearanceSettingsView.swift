import SwiftUI
import RingStatsCore
import RingStatsOura

struct AppearanceSettingsView: View {
    @AppStorage(AppTheme.storageKey) private var selectedThemeRaw = AppTheme.ringStats.rawValue
    @AppStorage(MetricConfiguration.storageKey) private var rawConfiguration = MetricConfiguration.default.encoded
    @AppStorage(TextSizePreference.storageKey) private var textSizeRaw = TextSizePreference.standard.rawValue

    private var textSize: Binding<TextSizePreference> {
        Binding(
            get: { TextSizePreference.resolve(textSizeRaw) },
            set: { textSizeRaw = $0.rawValue }
        )
    }
    @Environment(\.textScale) private var textScale

    static let baseSize = CGSize(width: 500, height: 690)
    @State private var configuration: MetricConfiguration
    @FocusState private var focusedReorderMetric: Metric?

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
        apply(configuration.moving(metric, by: offset))
        focusedReorderMetric = metric
    }

    private func themeOption(_ theme: AppTheme) -> some View {
        let selected = selectedTheme == theme
        return Button {
            selectedThemeRaw = theme.rawValue
        } label: {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                    .scaledFont(size: 16, weight: .medium)
                    .foregroundStyle(selected ? Palette.signalBlue : Palette.ink.opacity(0.36))
                    .frame(width: 20, height: 20)

                VStack(alignment: .leading, spacing: 3) {
                    Text(theme.title)
                        .scaledFont(size: 14, weight: .medium)
                        .foregroundStyle(Palette.ink)
                    Text(theme.summary)
                        .scaledFont(.caption)
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
                .scaledFont(.title)
            Text("Choose the popover theme, visible stats, and their order.")
                .foregroundStyle(.secondary)

            Text("Theme")
                .scaledFont(.headline)
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

            HStack(alignment: .firstTextBaseline) {
                Text("Text size")
                    .scaledFont(.headline)
                Spacer()
                TextSizeSlider(selection: textSize)
            }
            .padding(.top, 4)

            Divider()
                .overlay(Palette.separator)
                .padding(.vertical, 6)

            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Stats")
                        .scaledFont(.headline)
                    Text("Show or hide stats, and drag rows to reorder them.")
                        .scaledFont(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("Reset") {
                    apply(.default)
                }
            }

            List {
                ForEach(configuration.order) { metric in
                    let capabilities = configuration.reorderCapabilities(for: metric)
                    HStack(spacing: 10) {
                        Toggle(isOn: visibilityBinding(for: metric)) {
                            Label(metric.title, systemImage: metric.symbolName)
                                .scaledFont(.body)
                        }
                        .toggleStyle(.checkbox)
                        .disabled(
                            configuration.visibleMetrics.count == 1
                                && !configuration.hidden.contains(metric)
                        )

                        Spacer()
                        Image(systemName: "line.3.horizontal")
                            .scaledFont(size: 12, weight: .medium)
                            .foregroundStyle(.secondary.opacity(0.55))
                            .frame(width: 24, height: 24)
                            .contentShape(Rectangle())
                            .focusable()
                            .focused($focusedReorderMetric, equals: metric)
                            .onMoveCommand { direction in
                                switch direction {
                                case .up where capabilities?.canMoveUp == true:
                                    move(metric, offset: -1)
                                case .down where capabilities?.canMoveDown == true:
                                    move(metric, offset: 1)
                                default:
                                    break
                                }
                            }
                            .accessibilityLabel("Reorder \(metric.title)")
                            .accessibilityValue(
                                "Position \(capabilities?.position ?? 1) of \(capabilities?.total ?? configuration.order.count)"
                            )
                            .accessibilityHint("Drag, or use the Up and Down Arrow keys, to move this stat")
                            .accessibilityActions {
                                if capabilities?.canMoveUp == true {
                                    Button("Move Up") { move(metric, offset: -1) }
                                }
                                if capabilities?.canMoveDown == true {
                                    Button("Move Down") { move(metric, offset: 1) }
                                }
                            }
                    }
                    .padding(.vertical, 3)
                }
                .onMove { offsets, destination in
                    apply(configuration.moving(fromOffsets: offsets, toOffset: destination))
                }
            }
            .frame(height: (260 * textScale).rounded())
            .scrollContentBackground(.hidden)

            Text("At least one stat must remain visible. Drag any row to reorder all stats, including hidden ones; visible stats can also be dragged in the popover.")
                .scaledFont(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(24)
        .scaledFont(.body)
        .frame(
            width: (Self.baseSize.width * textScale).rounded(),
            height: (Self.baseSize.height * textScale).rounded(),
            alignment: .topLeading
        )
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
