import SwiftUI
import RingStatsCore

struct AboutCreditsView: View {
    static let baseWidth: CGFloat = 420
    @Environment(\.textScale) private var textScale
    @Environment(\.openURL) private var openURL

    private static let links: [(title: String, url: URL)] = [
        ("GitHub", URL(string: "https://github.com/PetriLahdelma/ring-stats")!),
        ("Privacy", URL(string: "https://github.com/PetriLahdelma/ring-stats/blob/main/PRIVACY.md")!),
        ("Releases", URL(string: "https://github.com/PetriLahdelma/ring-stats/releases")!),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Ring Stats")
                .scaledFont(.title)
            Text("Version \(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0")")
                .scaledFont(.caption)
                .foregroundStyle(Palette.secondaryInk)

            VStack(alignment: .leading, spacing: 2) {
                Text("Created by")
                    .scaledFont(.caption)
                    .foregroundStyle(Palette.secondaryInk)
                Text("Digitaltableteur")
                    .scaledFont(.callout, weight: .medium)
            }
            .accessibilityElement(children: .combine)

            Text("A small independent menu-bar viewer for your Oura data. Not affiliated with or endorsed by Oura Health Oy.")
                .fixedSize(horizontal: false, vertical: true)
            Text("Oura and Oura Ring are trademarks of Oura Health Oy. Data supplied by the Oura API. Built with SwiftUI.")
                .scaledFont(.caption)
                .foregroundStyle(Palette.secondaryInk)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 16) {
                ForEach(Self.links, id: \.title) { link in
                    Link(link.title, destination: link.url)
                        .keyboardActivatable(cornerRadius: 4) { openURL(link.url) }
                }
            }
            .scaledFont(.caption)
            .foregroundStyle(Palette.signalBlue)
        }
        .padding(24)
        .scaledFont(.body)
        .frame(width: (Self.baseWidth * textScale).rounded())
        .background(Palette.canvasWarm)
        .foregroundStyle(Palette.ink)
    }
}
