import AppKit
import SwiftUI
import RingStatsCore

/// Where the first-run connection flow is. Oura requires each person to use
/// their own developer application, so onboarding explains that constraint in
/// two deliberate steps before it asks for a secret. The portal's create form
/// asks for the redirect URI, so the first step shows it; a separate step
/// for it sent people back to the portal twice.
enum ConnectionStep: String, CaseIterable {
    case createApplication = "create-application"
    case enterCredentials = "enter-credentials"
    case connected

    var number: Int? {
        switch self {
        case .createApplication: 1
        case .enterCredentials: 2
        case .connected: nil
        }
    }

    static let setupStepCount = 2
}

struct ConnectionSettingsView: View {
    @Environment(\.openURL) private var openURL
    static let windowWidth: CGFloat = 460
    static let windowHeight: CGFloat = 440
    /// The portal where the user creates their application, from the
    /// provider's descriptor.
    private var developerPortal: URL {
        model.descriptor.developerPortal ?? URL(string: "https://developer.ouraring.com/applications")!
    }

    @EnvironmentObject private var model: AppViewModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.textScale) private var textScale
    let onConnected: () -> Void
    @State private var step: ConnectionStep?
    @State private var clientID = ""
    @State private var clientSecret = ""
    @State private var callbackCopied = false
    /// Shown after the browser has been open a while with no callback: the
    /// usual cause is an error page in the browser that the app cannot see.
    @State private var browserHintVisible = false
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
        .scaledFont(.body)
        .frame(
            width: (Self.windowWidth * textScale).rounded(),
            height: (Self.windowHeight * textScale).rounded(),
            alignment: .topLeading
        )
        .background(Palette.canvasWarm)
        .foregroundStyle(Palette.ink)
        .confirmationDialog(
            "Disconnect and delete saved authorization?",
            isPresented: $showingDisconnectConfirmation
        ) {
            Button("Disconnect & Delete", role: .destructive) {
                Task { await model.disconnect() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Ring Stats will revoke the current \(model.descriptor.displayName) token and remove the saved OAuth token, Client ID, and Client Secret from macOS Keychain.")
        }
        .onChange(of: model.connected) { _, connected in
            // Only a connection made in this flow earns the confirmation step.
            if connected, step == .enterCredentials {
                step = .connected
                AccessibilityNotification.Announcement("Connected securely to \(model.descriptor.displayName)").post()
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
        case .enterCredentials:
            enterCredentialsStep
        case .connected:
            connectedStep
        }
    }

    private var createApplicationStep: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Create your \(model.descriptor.displayName) application")
                .scaledFont(.title)
            Text("\(model.descriptor.displayName) gives personal API access through a developer application that you own. Ring Stats has no server of its own, so it connects with your application instead of a shared one. Free, about two minutes.")
                .fixedSize(horizontal: false, vertical: true)
            Link(destination: developerPortal) {
                Label("Open \(model.descriptor.displayName) developer portal", systemImage: "arrow.up.right.square")
            }
            .foregroundStyle(Palette.signalBlue)
            .keyboardActivatable(cornerRadius: 4) { openURL(developerPortal) }
            Text("Give it any name and website, and paste this as its redirect URI:")
                .fixedSize(horizontal: false, vertical: true)
            callbackURLRow
            Text("Use localhost, not 127.0.0.1. Ring Stats listens for this address on this Mac only, during sign-in. Gen3 and Ring 4 need an active \(model.descriptor.displayName) Membership for API access.")
                .scaledFont(.caption)
                .foregroundStyle(Palette.secondaryInk)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            navigation(back: nil, next: .enterCredentials, nextTitle: "I Have Created It")
        }
    }

    private var callbackURLRow: some View {
        HStack(spacing: 10) {
            Text(OAuthLoopback.callbackURL)
                .scaledFont(.body, design: .monospaced)
                .textSelection(.enabled)
                .padding(.vertical, 6)
                .padding(.horizontal, 10)
                .background(Palette.card, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
            Button {
                copyCallbackURL()
            } label: {
                Label(callbackCopied ? "Copied" : "Copy", systemImage: callbackCopied ? "checkmark" : "doc.on.doc")
            }
            .keyboardActivatable { copyCallbackURL() }
            .accessibilityLabel(callbackCopied ? "Copied callback URL" : "Copy callback URL")
        }
    }

    private var enterCredentialsStep: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Enter your credentials")
                .scaledFont(.title)
            Text("Open your application in the \(model.descriptor.displayName) portal and copy its Client ID and Client Secret here.")
                .fixedSize(horizontal: false, vertical: true)
            Link(destination: developerPortal) {
                Label("Open \(model.descriptor.displayName) developer portal", systemImage: "arrow.up.right.square")
            }
            .foregroundStyle(Palette.signalBlue)
            .keyboardActivatable(cornerRadius: 4) { openURL(developerPortal) }
            TextField("Client ID", text: $clientID)
                .focused($focusedField, equals: .clientID)
                .disabled(model.state == .authorizing)
            SecureField("Client Secret", text: $clientSecret)
                .focused($focusedField, equals: .clientSecret)
                .disabled(model.state == .authorizing)
            Label {
                Text("Stored only in this Mac’s Keychain and sent only to \(model.descriptor.displayName). Disconnecting deletes them.")
                    .fixedSize(horizontal: false, vertical: true)
            } icon: {
                Image(systemName: "lock.fill")
            }
            .scaledFont(.caption)
            .foregroundStyle(Palette.secondaryInk)
            if model.state == .authorizing {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("Waiting for you to approve access in your browser…")
                        .scaledFont(.callout)
                }
                .accessibilityElement(children: .combine)
                if browserHintVisible {
                    Text("Seeing an error in the browser? The usual cause is a redirect URI that does not match the one in step 1 exactly. Cancel, check it in the \(model.descriptor.displayName) portal, and try again.")
                        .scaledFont(.caption)
                        .foregroundStyle(Palette.secondaryInk)
                        .fixedSize(horizontal: false, vertical: true)
                }
            } else if let error = model.errorMessage {
                Text(error)
                    .scaledFont(.caption)
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
                    .buttonStyle(.secondaryAction)
                    .keyboardActivatable { Task { await model.cancelAuthorization() } }
                } else {
                    Button("Back") { step = .createApplication }
                        .buttonStyle(.secondaryAction)
                        .keyboardActivatable { step = .createApplication }
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
                .buttonStyle(.primaryAction)
                .keyboardActivatable {
                    Task { await model.connect(clientID: clientID, clientSecret: clientSecret, metrics: visibleMetrics) }
                }
                .disabled(model.loading || clientID.isEmpty || clientSecret.isEmpty)
            }
        }
        .onAppear { focusedField = .clientID }
        .task(id: model.state == .authorizing) {
            browserHintVisible = false
            guard model.state == .authorizing else { return }
            try? await Task.sleep(for: .seconds(Self.browserHintDelay))
            if !Task.isCancelled { browserHintVisible = true }
        }
    }

    /// How long the browser may stay open before the hint about browser-side
    /// errors appears.
    static let browserHintDelay: TimeInterval = 20

    private var connectedStep: some View {
        VStack(alignment: .leading, spacing: 14) {
            Image(systemName: "checkmark.shield.fill")
                .scaledFont(size: 34, weight: .regular)
                .foregroundStyle(Palette.signalBlue)
                .accessibilityHidden(true)
            Text("Connected securely")
                .scaledFont(.title)
            Text("Ring Stats can now read the stats you chose. Today’s scores appear once your ring has synced with the \(model.descriptor.displayName) app, usually after you wake up.")
                .fixedSize(horizontal: false, vertical: true)
            Text("Your credentials and tokens stay in this Mac’s Keychain, and health data stays in memory only.")
                .fixedSize(horizontal: false, vertical: true)
            Text("Change permissions or disconnect at any time from Connection in the Ring Stats menu.")
                .scaledFont(.caption)
                .foregroundStyle(Palette.secondaryInk)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            HStack {
                Spacer()
                Button("Show My Stats", action: showMyStats)
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.primaryAction)
                    .keyboardActivatable(action: showMyStats)
            }
        }
    }

    private func showMyStats() {
        step = nil
        dismiss()
        onConnected()
    }

    private func navigation(back: ConnectionStep?, next: ConnectionStep, nextTitle: String) -> some View {
        HStack {
            if let back {
                Button("Back") { step = back }
                    .buttonStyle(.secondaryAction)
                    .keyboardActivatable { step = back }
            }
            Spacer()
            Button(nextTitle) { step = next }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.primaryAction)
                .keyboardActivatable { step = next }
        }
    }

    private func copyCallbackURL() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(OAuthLoopback.callbackURL, forType: .string)
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
            Text("\(model.descriptor.displayName) Connection")
                .scaledFont(.title)
            Label(
                model.connected ? "\(model.descriptor.displayName) account connected" : "\(model.descriptor.displayName) authorization required",
                systemImage: model.connected ? "checkmark.circle" : "exclamationmark.circle"
            )
            .scaledFont(.callout, weight: .medium)
            if let error = model.errorMessage {
                Text(error)
                    .scaledFont(.caption)
                    .foregroundStyle(Palette.alertText)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Button(model.loading ? "Reauthorizing…" : "Reauthorize Permissions") {
                Task { await model.reauthorize(metrics: visibleMetrics) }
            }
            .keyboardActivatable { Task { await model.reauthorize(metrics: visibleMetrics) } }
            .disabled(model.loading)

            Divider()
                .overlay(Palette.separator)

            VStack(alignment: .leading, spacing: 8) {
                Text("Disconnecting revokes the current token and deletes the saved client credentials from this Mac.")
                    .scaledFont(.caption)
                    .foregroundStyle(Palette.secondaryInk)
                    .fixedSize(horizontal: false, vertical: true)
                Button("Disconnect & Delete Local Data", role: .destructive) {
                    showingDisconnectConfirmation = true
                }
                .keyboardActivatable { showingDisconnectConfirmation = true }
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
                .scaledFont(.caption, weight: .medium)
                .foregroundStyle(Palette.secondaryInk)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Step \(current) of \(total)")
    }
}
