import AppKit
import SwiftUI
import UniformTypeIdentifiers
import RingStatsCore
import RingStatsOura

/// Shows the redacted diagnostics report so the user can read exactly what
/// they would share before copying or saving it. Nothing is sent anywhere.
struct DiagnosticsView: View {
    @EnvironmentObject private var model: AppViewModel
    @State private var report = ""
    @State private var copied = false
    @Environment(\.textScale) private var textScale

    static let baseSize = CGSize(width: 560, height: 520)

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Diagnostics")
                .scaledFont(.title)
            Text("Review this report before sharing it. It lists app state and recent events, and never includes health values, credentials, tokens, or account identifiers.")
                .foregroundStyle(Palette.secondaryInk)
                .fixedSize(horizontal: false, vertical: true)
            ScrollView {
                Text(report)
                    .scaledFont(.caption, design: .monospaced)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(10)
            }
            .background(.white.opacity(0.7), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .accessibilityLabel("Diagnostics report")
            HStack {
                Button("Refresh Report") { regenerate() }
                Spacer()
                Button(copied ? "Copied" : "Copy") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(report, forType: .string)
                    copied = true
                    AccessibilityNotification.Announcement("Diagnostics report copied").post()
                }
                Button("Save…") { save() }
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
                    .tint(Palette.signalBlue)
            }
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
        .onAppear { regenerate() }
    }

    private func regenerate() {
        report = DiagnosticsReport.make(model: model)
        copied = false
    }

    private func save() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.plainText]
        panel.nameFieldStringValue = "Ring Stats Diagnostics.txt"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        try? Data(report.utf8).write(to: url, options: .atomic)
    }
}
