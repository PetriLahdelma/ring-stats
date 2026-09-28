import SwiftUI
import RingStatsCore
import RingStatsOura

struct AboutCreditsView: View {
    static let baseWidth: CGFloat = 420
    @Environment(\.textScale) private var textScale

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Ring Stats")
                .scaledFont(.title)
            Text("Version \(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0")")
                .scaledFont(.caption)
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 2) {
                Text("Created by")
                    .scaledFont(.caption)
                    .foregroundStyle(.secondary)
                Text("Digitaltableteur")
                    .scaledFont(.callout, weight: .medium)
            }
            .accessibilityElement(children: .combine)

            Text("A small independent menu-bar viewer for your Oura data. Not affiliated with or endorsed by Oura Health Oy.")
                .fixedSize(horizontal: false, vertical: true)
            Text("Oura and Oura Ring are trademarks of Oura Health Oy. Data supplied by the Oura API. Built with SwiftUI.")
                .scaledFont(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 16) {
                Link("GitHub", destination: URL(string: "https://github.com/PetriLahdelma/ring-stats")!)
                Link(
                    "Privacy",
                    destination: URL(string: "https://github.com/PetriLahdelma/ring-stats/blob/main/PRIVACY.md")!
                )
                Link(
                    "Releases",
                    destination: URL(string: "https://github.com/PetriLahdelma/ring-stats/releases")!
                )
            }
            .scaledFont(.caption)
            .foregroundStyle(Palette.signalBlue)
        }
        .padding(24)
        .scaledFont(.body)
        .frame(width: (Self.baseWidth * textScale).rounded())
        .background(Palette.canvasWarm)
        .foregroundStyle(Palette.ink)
        .preferredColorScheme(.light)
    }
}
