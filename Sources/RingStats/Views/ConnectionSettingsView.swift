import AppKit
import SwiftUI

struct ConnectionSettingsView: View {
    @EnvironmentObject private var model: AppViewModel
    @Environment(\.dismiss) private var dismiss
    let onConnected: () -> Void
    @State private var clientID = ""
    @State private var clientSecret = ""
    @State private var showingDisconnectConfirmation = false
    @AppStorage(MetricConfiguration.storageKey) private var metricConfigurationRaw = MetricConfiguration.default.encoded

    private var visibleMetrics: Set<Metric> {
        Set(MetricConfiguration.decode(metricConfigurationRaw).visibleMetrics)
    }

    init(onConnected: @escaping () -> Void = {}) {
        self.onConnected = onConnected
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Oura Connection")
                .font(.title2.weight(.semibold))

            if model.configured {
                Label(
                    model.connected ? "Oura account connected" : "Oura authorization required",
                    systemImage: model.connected ? "checkmark.circle" : "exclamationmark.circle"
                )
                    .font(.callout.weight(.medium))
                if let error = model.errorMessage {
                    Text(error).font(.caption).foregroundStyle(.red).textSelection(.enabled)
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
            } else {
                Text("Create an application in Oura’s developer portal and use this exact callback URL:")
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Link("Open Oura developer portal", destination: URL(string: "https://developer.ouraring.com/applications")!)
                    .foregroundStyle(Palette.signalBlue)
                HStack(spacing: 8) {
                    Text(OAuthClient.callbackURL)
                        .font(.system(.body, design: .monospaced))
                        .textSelection(.enabled)
                    Button {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(OAuthClient.callbackURL, forType: .string)
                    } label: {
                        Image(systemName: "doc.on.doc")
                    }
                    .buttonStyle(.borderless)
                    .accessibilityLabel("Copy callback URL")
                }
                TextField("Client ID", text: $clientID)
                SecureField("Client Secret", text: $clientSecret)
                if let error = model.errorMessage {
                    Text(error).font(.caption).foregroundStyle(.red).textSelection(.enabled)
                }
                HStack {
                    Spacer()
                    Button(model.loading ? "Connecting…" : "Connect in Browser") {
                        Task {
                            await model.connect(
                                clientID: clientID,
                                clientSecret: clientSecret,
                                metrics: visibleMetrics
                            )
                        }
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
        .onDisappear {
            if model.state == .authorizing {
                Task { await model.cancelAuthorization() }
            }
        }
    }
}
