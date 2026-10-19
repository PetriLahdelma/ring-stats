import SwiftUI
import RingStatsCore

struct AppearanceSettingsView: View {
    @AppStorage(AppTheme.storageKey) private var selectedThemeRaw = AppTheme.ringStats.rawValue
    @AppStorage(MetricConfiguration.storageKey) private var rawConfiguration = MetricConfiguration.default.encoded
    @AppStorage(TextSizePreference.storageKey) private var textSizeRaw = TextSizePreference.standard.rawValue
    @AppStorage(LowBatteryPreference.storageKey) private var lowBatteryAlerts = false
    @AppStorage(LowBatteryPreference.thresholdKey) private var lowBatteryThreshold = LowBatteryAlert.threshold
    @AppStorage(LowBatteryPreference.quietHoursKey) private var quietHoursOn = false
    @AppStorage(LowBatteryPreference.quietStartKey) private var quietStart = QuietHours.default.start
    @AppStorage(LowBatteryPreference.quietEndKey) private var quietEnd = QuietHours.default.end
    @AppStorage(LowBatteryPreference.bedtimeKey) private var bedtimeReminder = false
    @AppStorage(ScoresNotificationPreference.storageKey) private var scoresNotifications = false
    @AppStorage(MenuBarValuePreference.storageKey) private var menuBarValueRaw = MenuBarValuePreference.nothing.rawValue
    @State private var notificationsDenied = false

    private var textSize: Binding<TextSizePreference> {
        Binding(
            get: { TextSizePreference.resolve(textSizeRaw) },
            set: { textSizeRaw = $0.rawValue }
        )
    }
    @Environment(\.textScale) private var textScale

    static let windowWidth: CGFloat = 500

    /// The stats list shows every row without scrolling. A row is 38 pt
    /// until Extra Large text outgrows that; the insets are the list's own.
    static func listHeight(rows: Int, textScale: CGFloat) -> CGFloat {
        let row = max(38, (17 * textScale).rounded() + 16)
        return CGFloat(rows) * row + 20
    }
    @State private var configuration: MetricConfiguration
    /// The stats list's selected row, which Space shows or hides and
    /// Option-Up and Option-Down move.
    @State private var selectedMetric: Metric?
    @FocusState private var themeGroupFocused: Bool
    @State private var themeFocusRingVisible = false

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
        selectedMetric = metric
        if let position = configuration.reorderCapabilities(for: metric)?.position {
            AccessibilityNotification.Announcement("\(metric.title) moved to position \(position)").post()
        }
    }

    /// Space shows or hides the selected stat; Option-Up and Option-Down move
    /// it. Plain arrows stay with the list, which moves the selection.
    private func handleListKey(_ press: KeyPress) -> KeyPress.Result {
        guard let metric = selectedMetric else { return .ignored }
        switch press.key {
        case .space:
            let binding = visibilityBinding(for: metric)
            let lastVisible = configuration.visibleMetrics.count == 1 && binding.wrappedValue
            guard !lastVisible else { return .handled }
            binding.wrappedValue.toggle()
            return .handled
        case .upArrow where press.modifiers.contains(.option):
            if configuration.reorderCapabilities(for: metric)?.canMoveUp == true { move(metric, offset: -1) }
            return .handled
        case .downArrow where press.modifiers.contains(.option):
            if configuration.reorderCapabilities(for: metric)?.canMoveDown == true { move(metric, offset: 1) }
            return .handled
        default:
            return .ignored
        }
    }

    /// The theme choices as one keyboard stop, like a macOS radio group: Tab
    /// reaches it whatever the Keyboard navigation setting, and the arrow
    /// keys change the theme.
    private var themeGroup: some View {
        VStack(spacing: 0) {
            themeOption(.ringStats)
            Divider()
                .overlay(Palette.separator)
                .padding(.leading, 46)
            themeOption(.landscape)
            Divider()
                .overlay(Palette.separator)
                .padding(.leading, 46)
            themeOption(.holographic)
        }
        .background(Palette.card)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(Palette.separator, lineWidth: 1)
        }
        .overlay {
            if themeFocusRingVisible && themeGroupFocused {
                FocusRing(theme: .ringStats, cornerRadius: 12, outset: 3)
            }
        }
        .focusable()
        .focusEffectDisabled()
        .focused($themeGroupFocused)
        .onChange(of: themeGroupFocused) { _, focused in
            themeFocusRingVisible = focused && !MenuPopoverView.focusCameFromPointer(NSApp.currentEvent?.type)
        }
        .onKeyPress(keys: [.upArrow, .downArrow, .leftArrow, .rightArrow]) { press in
            themeFocusRingVisible = true
            let offset = press.key == .upArrow || press.key == .leftArrow ? -1 : 1
            guard let next = selectedTheme.neighbor(offset) else { return .handled }
            selectedThemeRaw = next.rawValue
            AccessibilityNotification.Announcement("\(next.title) theme").post()
            return .handled
        }
    }

    private func themeOption(_ theme: AppTheme) -> some View {
        let selected = selectedTheme == theme
        // Not a Button: the whole group is one keyboard stop (see
        // themeGroup), so the rows must not add stops of their own when
        // macOS Keyboard navigation is on.
        return HStack(alignment: .top, spacing: 12) {
            Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                .scaledFont(size: 16, weight: .medium)
                .foregroundStyle(selected ? Palette.signalBlue : Palette.secondaryInk)
                .frame(width: 20, height: 20)

            VStack(alignment: .leading, spacing: 3) {
                Text(theme.title)
                    .scaledFont(size: 14, weight: .medium)
                    .foregroundStyle(Palette.ink)
                Text(theme.summary)
                    .scaledFont(.caption)
                    .foregroundStyle(Palette.secondaryInk)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .contentShape(Rectangle())
        .onTapGesture { selectedThemeRaw = theme.rawValue }
        .accessibilityElement(children: .ignore)
        .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
        .accessibilityAction { selectedThemeRaw = theme.rawValue }
        .accessibilityLabel(theme.title)
        .accessibilityValue(selected ? "Selected" : "Not selected")
        .accessibilityHint(theme.summary)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Appearance")
                .scaledFont(.title)
            Text("Choose the theme, text size, notifications, and which stats show.")
                .foregroundStyle(Palette.secondaryInk)

            Text("Theme")
                .scaledFont(.headline)
                .padding(.top, 6)

            themeGroup

            HStack(alignment: .firstTextBaseline) {
                Text("Text size")
                    .scaledFont(.headline)
                Spacer()
                TextSizeSlider(selection: textSize)
                    .keyboardStepper { offset in
                        let sizes = TextSizePreference.allCases
                        let index = (sizes.firstIndex(of: textSize.wrappedValue) ?? 0) + offset
                        if sizes.indices.contains(index) { textSize.wrappedValue = sizes[index] }
                    }
            }
            .padding(.top, 4)

            notificationsSection

            HStack(alignment: .center, spacing: 16) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("In the menu bar")
                        .scaledFont(.headline)
                    Text("Show a value beside the icon, so a glance needs no click. Anyone who sees your screen sees it too.")
                        .scaledFont(.caption)
                        .foregroundStyle(Palette.secondaryInk)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
                Picker("In the menu bar", selection: $menuBarValueRaw) {
                    ForEach(MenuBarValuePreference.allCases) { choice in
                        Text(choice.title).tag(choice.rawValue)
                    }
                }
                .labelsHidden()
                .fixedSize()
                .keyboardStepper(cornerRadius: 6) { offset in
                    let all = MenuBarValuePreference.allCases
                    let index = (all.firstIndex(of: MenuBarValuePreference.resolve(menuBarValueRaw)) ?? 0) + offset
                    if all.indices.contains(index) { menuBarValueRaw = all[index].rawValue }
                }
                .accessibilityHint("Shows the chosen stat beside the menu bar icon")
            }

            Divider()
                .overlay(Palette.separator)
                .padding(.vertical, 6)

            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Stats")
                        .scaledFont(.headline)
                    Text("Show or hide stats, and drag rows to reorder them.")
                        .scaledFont(.caption)
                        .foregroundStyle(Palette.secondaryInk)
                }
                Spacer()
                Button("Reset") {
                    apply(.default)
                }
                .keyboardActivatable { apply(.default) }
            }

            List(selection: $selectedMetric) {
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
                            .foregroundStyle(Palette.secondaryInk)
                            .frame(width: 24, height: 24)
                            .contentShape(Rectangle())
                            .accessibilityLabel("Reorder \(metric.title)")
                            .accessibilityValue(
                                "Position \(capabilities?.position ?? 1) of \(capabilities?.total ?? configuration.order.count)"
                            )
                            .accessibilityHint("Drag, or select the row and press Option-Up or Option-Down, to move this stat")
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
                    .tag(metric)
                }
                .onMove { offsets, destination in
                    apply(configuration.moving(fromOffsets: offsets, toOffset: destination))
                }
            }
            .frame(height: Self.listHeight(rows: configuration.order.count, textScale: textScale))
            .scrollContentBackground(.hidden)
            .onKeyPress(keys: [.space, .upArrow, .downArrow], action: handleListKey)

            Text("At least one stat must remain visible. To reorder stats, including hidden ones, drag a row, or select it and press Option with the Up or Down Arrow. Space shows or hides the selected stat.")
                .scaledFont(.caption)
                .foregroundStyle(Palette.secondaryInk)
        }
        .padding(24)
        .scaledFont(.body)
        .frame(width: (Self.windowWidth * textScale).rounded(), alignment: .topLeading)
        .fixedSize(horizontal: false, vertical: true)
        .background(Palette.canvasWarm)
        .foregroundStyle(Palette.ink)
        .onChange(of: rawConfiguration) { _, newValue in
            let updated = MetricConfiguration.decode(newValue)
            if updated != configuration {
                configuration = updated
            }
        }
    }
}

extension AppearanceSettingsView {
    /// The notification switches. Each asks macOS for permission the first
    /// time it is turned on and turns itself back off when that is refused.
    fileprivate var notificationsSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Notifications")
                .scaledFont(.headline)
            if notificationsDenied {
                Text("Notifications are off for Ring Stats. Allow them in System Settings, Notifications.")
                    .scaledFont(.caption)
                    .foregroundStyle(Palette.alertText)
                    .fixedSize(horizontal: false, vertical: true)
            }
            notificationRow(
                "Low battery alert",
                caption: "Notifies you once when the ring drops below the level you choose, and again only after it has charged.",
                isOn: $lowBatteryAlerts,
                hint: "Notifies you when the ring battery drops below \(lowBatteryThreshold)%"
            ) {
                if lowBatteryAlerts {
                    Picker("Below", selection: $lowBatteryThreshold) {
                        ForEach(LowBatteryAlert.thresholds, id: \.self) { level in
                            Text("Below \(level)%").tag(level)
                        }
                    }
                    .labelsHidden()
                    .fixedSize()
                    .keyboardStepper(cornerRadius: 6) { offset in
                        let all = LowBatteryAlert.thresholds
                        let index = (all.firstIndex(of: lowBatteryThreshold) ?? 2) + offset
                        if all.indices.contains(index) { lowBatteryThreshold = all[index] }
                    }
                    .accessibilityLabel("Low battery level")
                }
            }
            notificationRow(
                "Quiet hours",
                caption: "No notifications between these hours; a low battery is announced afterwards if it is still low.",
                isOn: $quietHoursOn,
                hint: "Holds notifications between the chosen hours",
                requiresPermission: false
            ) {
                if quietHoursOn {
                    HStack(spacing: 6) {
                        hourPicker("From", selection: $quietStart)
                        Text("to").scaledFont(.caption).foregroundStyle(Palette.secondaryInk)
                        hourPicker("To", selection: $quietEnd)
                    }
                }
            }
            notificationRow(
                "Charge before bed",
                caption: "In the evening, if the ring is draining fast enough to be low by morning, suggests charging it. Uses the quiet hours as night, or 22:00 to 07:00.",
                isOn: $bedtimeReminder,
                hint: "Suggests charging in the evening when the ring will not last the night"
            ) { EmptyView() }
            notificationRow(
                "Today's scores are in",
                caption: "Once a day, when the morning sync lands. The notification names no value.",
                isOn: $scoresNotifications,
                hint: "Notifies you once a day when today's scores arrive"
            ) { EmptyView() }
        }
    }

    private func hourPicker(_ label: String, selection: Binding<Int>) -> some View {
        Picker(label, selection: selection) {
            ForEach(0..<24, id: \.self) { hour in
                Text(String(format: "%02d:00", hour)).tag(hour)
            }
        }
        .labelsHidden()
        .fixedSize()
        .keyboardStepper(cornerRadius: 6) { offset in
            selection.wrappedValue = (selection.wrappedValue + offset + 24) % 24
        }
        .accessibilityLabel("Quiet hours \(label.lowercased())")
    }

    private func notificationRow<Accessory: View>(
        _ title: String,
        caption: String,
        isOn: Binding<Bool>,
        hint: String,
        requiresPermission: Bool = true,
        @ViewBuilder accessory: () -> Accessory
    ) -> some View {
        HStack(alignment: .center, spacing: 16) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .scaledFont(.headline)
                Text(caption)
                    .scaledFont(.caption)
                    .foregroundStyle(Palette.secondaryInk)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
            accessory()
            Toggle(title, isOn: isOn)
                .keyboardToggle(isOn)
                .toggleStyle(.switch)
                .labelsHidden()
                .tint(Palette.signalBlue)
                .accessibilityHint(hint)
        }
        .onChange(of: isOn.wrappedValue) { _, enabled in
            guard enabled, requiresPermission else { return }
            Task {
                let granted = await UserNotificationsNotifier().requestAuthorization()
                notificationsDenied = !granted
                if !granted { isOn.wrappedValue = false }
            }
        }
    }
}
