import AppKit
import SwiftUI

/// Where the first-run connection flow is. Oura requires each person to use
/// their own developer application, so onboarding explains that constraint in
/// three deliberate steps before it asks for a secret.
enum ConnectionStep: String, CaseIterable {
    case createApplication = "create-application"
    case registerCallback = "register-callback"
    case enterCredentials = "enter-credentials"
    case connected

    var number: Int? {
        switch self {
        case .createApplication: 1
        case .registerCallback: 2
        case .enterCredentials: 3
        case .connected: nil
        }
    }

    static let setupStepCount = 3
}

struct ConnectionSettingsView: View {
    static let windowWidth: CGFloat = 460
    static let windowHeight: CGFloat = 440
    static let developerPortal = URL(string: "https://developer.ouraring.com/applications")!

    @EnvironmentObject private var model: AppViewModel
    @Environment(\.dismiss) private var dismiss
    let onConnected: () -> Void
    @State private var step: ConnectionStep?
    @State private var clientID = ""
    @State private var clientSecret = ""
    @State private var callbackCopied = false
    @State private var showingDisconnectConfirmation = false
    @FocusState private var focusedField: CredentialField?
    @AppStorage(MetricConfiguration.storageKey) private var metricConfigurationRaw = MetricConfiguration.default.encoded

    private enum CredentialField {
        case clientID
        case clientSecret
    }

    private var visibleMetrics: Set<Metric> {
        Set(MetricConfiguration.decode(metricConfigurationRaw).visibleMetrics)
    }

    /// - Parameter initialStep: Starts onboarding at a given step. Used for the
    ///   state gallery; the app lets the model decide.
    init(initialStep: ConnectionStep? = nil, onConnected: @escaping () -> Void = {}) {
        _step = State(initialValue: initialStep)
        self.onConnected = onConnected
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if let step {
                onboarding(step)
            } else if model.configured {
                management
            } else {
                onboarding(.createApplication)
            }
        }
        .padding(24)
        .frame(
            width: Self.windowWidth,
            height: Self.windowHeight,
            alignment: .topLeading
        )
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
            // Only a connection made in this flow earns the confirmation step.
            if connected, step == .enterCredentials {
                step = .connected
                AccessibilityNotification.Announcement("Connected securely to Oura").post()
            }
        }
        .onDisappear {
            if model.state == .authorizing {
                Task { await model.cancelAuthorization() }
            }
            // The window is reused, so a closed confirmation must not greet the
            // next visit; configured users should land on management.
            if step == .connected {
                step = nil
            }
        }
    }

    // MARK: Onboarding

    @ViewBuilder
    private func onboarding(_ current: ConnectionStep) -> some View {
        if let number = current.number {
            StepIndicator(current: number, total: ConnectionStep.setupStepCount)
        }
        switch current {
        case .createApplication:
            createApplicationStep
        case .registerCallback:
            registerCallbackStep
        case .enterCredentials:
            enterCredentialsStep
        case .connected:
            connectedStep
        }
    }

    private var createApplicationStep: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Create your Oura application")
                .font(.title2.weight(.semibold))
            Text("Oura gives personal API access through a developer application that you own. Ring Stats has no server of its own, so it connects with your application instead of a shared one.")
                .fixedSize(horizontal: false, vertical: true)
            Text("It takes about two minutes and needs no special settings beyond the callback in the next step.")
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Link(destination: Self.developerPortal) {
                Label("Open Oura developer portal", systemImage: "arrow.up.right.square")
            }
            .foregroundStyle(Palette.signalBlue)
            Spacer(minLength: 0)
            navigation(back: nil, next: .registerCallback, nextTitle: "I Have Created It")
        }
    }

    private var registerCallbackStep: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Add the callback URL")
                .font(.title2.weight(.semibold))
            Text("In your application’s settings, add this exact redirect URI. Oura returns you to Ring Stats through it after you approve access.")
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 10) {
                Text(OAuthClient.callbackURL)
                    .font(.system(.body, design: .monospaced))
                    .textSelection(.enabled)
                    .padding(.vertical, 6)
                    .padding(.horizontal, 10)
                    .background(.white.opacity(0.7), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                Button {
                    copyCallbackURL()
                } label: {
                    Label(callbackCopied ? "Copied" : "Copy", systemImage: callbackCopied ? "checkmark" : "doc.on.doc")
                }
                .accessibilityLabel(callbackCopied ? "Callback URL copied" : "Copy callback URL")
            }
            Text("It uses 127.0.0.1 rather than localhost so the callback can only reach this Mac’s IPv4 loopback address.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            navigation(back: .createApplication, next: .enterCredentials, nextTitle: "I Have Added It")
        }
    }

    private var enterCredentialsStep: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Enter your credentials")
                .font(.title2.weight(.semibold))
            Text("Copy the Client ID and Client Secret from the same application.")
                .fixedSize(horizontal: false, vertical: true)
            TextField("Client ID", text: $clientID)
                .focused($focusedField, equals: .clientID)
                .disabled(model.state == .authorizing)
            SecureField("Client Secret", text: $clientSecret)
                .focused($focusedField, equals: .clientSecret)
                .disabled(model.state == .authorizing)
            Label {
                Text("Stored only in this Mac’s Keychain and sent only to Oura. Disconnecting deletes them.")
                    .fixedSize(horizontal: false, vertical: true)
            } icon: {
                Image(systemName: "lock.fill")
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            if model.state == .authorizing {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("Waiting for you to approve access in your browser…")
                        .font(.callout)
                }
                .accessibilityElement(children: .combine)
            } else if let error = model.errorMessage {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(Palette.alertText)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
            HStack {
                if model.state == .authorizing {
                    Button("Cancel") {
                        Task { await model.cancelAuthorization() }
                    }
                } else {
                    Button("Back") { step = .registerCallback }
                }
                Spacer()
                Button(model.state == .authorizing ? "Connecting…" : "Connect in Browser") {
                    Task {
                        await model.connect(
                            clientID: clientID,
                            clientSecret: clientSecret,
                            metrics: visibleMetrics
                        )
                    }
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
                .tint(Palette.signalBlue)
                .disabled(model.loading || clientID.isEmpty || clientSecret.isEmpty)
            }
        }
        .onAppear { focusedField = .clientID }
    }

    private var connectedStep: some View {
        VStack(alignment: .leading, spacing: 14) {
            Image(systemName: "checkmark.shield.fill")
                .font(.system(size: 34, weight: .regular))
                .foregroundStyle(Palette.signalBlue)
                .accessibilityHidden(true)
            Text("Connected securely")
                .font(.title2.weight(.semibold))
            Text("Ring Stats can now read the stats you chose. Your credentials and tokens stay in this Mac’s Keychain, and health data stays in memory only.")
                .fixedSize(horizontal: false, vertical: true)
            Text("Change permissions or disconnect at any time from Connection in the Ring Stats menu.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            HStack {
                Spacer()
                Button("Show My Stats") {
                    step = nil
                    dismiss()
                    onConnected()
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
                .tint(Palette.signalBlue)
            }
        }
    }

    private func navigation(back: ConnectionStep?, next: ConnectionStep, nextTitle: String) -> some View {
        HStack {
            if let back {
                Button("Back") { step = back }
            }
            Spacer()
            Button(nextTitle) { step = next }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
                .tint(Palette.signalBlue)
        }
    }

    private func copyCallbackURL() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(OAuthClient.callbackURL, forType: .string)
        callbackCopied = true
        AccessibilityNotification.Announcement("Callback URL copied").post()
        Task {
            try? await Task.sleep(for: .seconds(2))
            callbackCopied = false
        }
    }

    // MARK: Management

    private var management: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Oura Connection")
                .font(.title2.weight(.semibold))
            Label(
                model.connected ? "Oura account connected" : "Oura authorization required",
                systemImage: model.connected ? "checkmark.circle" : "exclamationmark.circle"
            )
            .font(.callout.weight(.medium))
            if let error = model.errorMessage {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(Palette.alertText)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Button(model.loading ? "Reauthorizing…" : "Reauthorize Permissions") {
                Task { await model.reauthorize(metrics: visibleMetrics) }
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
        }
    }
}

/// "Step 2 of 3" with matching dots; read as one phrase by VoiceOver.
private struct StepIndicator: View {
    let current: Int
    let total: Int

    var body: some View {
        HStack(spacing: 8) {
            HStack(spacing: 5) {
                ForEach(1...total, id: \.self) { index in
                    Capsule()
                        .fill(index <= current ? Palette.signalBlue : Palette.separator)
                        .frame(width: index == current ? 18 : 8, height: 6)
                }
            }
            Text("Step \(current) of \(total)")
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Step \(current) of \(total)")
    }
}
