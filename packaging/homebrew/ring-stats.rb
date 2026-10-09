# Homebrew cask for Ring Stats. The copy that users install is in the tap
# repository PetriLahdelma/homebrew-ring-stats (Casks/ring-stats.rb); keep
# the two identical. It moves to homebrew-cask once the project meets its
# acceptance thresholds.
#   brew install --cask PetriLahdelma/ring-stats/ring-stats
# Update version and sha256 for each release (shasum -a 256 Ring-Stats-<v>.dmg).
cask "ring-stats" do
  version "1.4.0"
  sha256 "815024e9e79485731cd10800cd824808b92c11972244924e419ae006a6e4c081"

  url "https://github.com/PetriLahdelma/ring-stats/releases/download/v#{version}/Ring-Stats-#{version}.dmg"
  name "Ring Stats"
  desc "Oura ring stats in the Mac menu bar"
  homepage "https://github.com/PetriLahdelma/ring-stats"

  livecheck do
    url :url
    strategy :github_latest
  end

  depends_on macos: :sonoma

  app "Ring Stats.app"

  uninstall quit: "com.digitaltableteur.ringstats"

  zap trash: [
    "~/Library/Containers/com.digitaltableteur.ringstats",
    "~/Library/Preferences/com.digitaltableteur.ringstats.plist",
  ]

  caveats <<~EOS
    Ring Stats stores your Oura credentials in the macOS Keychain. Choose
    "Disconnect & Delete Local Data" in the app before uninstalling to revoke
    the authorization and remove them; brew zap does not touch the Keychain.
  EOS
end
