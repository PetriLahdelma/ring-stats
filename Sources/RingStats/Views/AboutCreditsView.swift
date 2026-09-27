import SwiftUI

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
            .font(.caption)
            .foregroundStyle(Palette.signalBlue)
        }
        .padding(24)
        .frame(width: 420)
        .background(Palette.canvasWarm)
        .foregroundStyle(Palette.ink)
        .preferredColorScheme(.light)
    }
}
