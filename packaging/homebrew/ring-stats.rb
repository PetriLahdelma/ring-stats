# Homebrew cask for Ring Stats. Lives in a tap until the repository meets
# homebrew-cask's acceptance thresholds:
#   brew tap PetriLahdelma/ring-stats https://github.com/PetriLahdelma/homebrew-ring-stats
#   brew install --cask ring-stats
# Update version and sha256 for each release (shasum -a 256 Ring-Stats-<v>.dmg).
cask "ring-stats" do
  version "1.3.6"
  sha256 "43fed8d4ada8da8265ef319fa02a2b7b1cc4816255dc8f0b06ab4f7c57b29087"

  url "https://github.com/PetriLahdelma/ring-stats/releases/download/v#{version}/Ring-Stats-#{version}.dmg",
      verified: "github.com/PetriLahdelma/ring-stats/"
  name "Ring Stats"
  desc "Oura ring stats in the Mac menu bar"
  homepage "https://github.com/PetriLahdelma/ring-stats"

  livecheck do
    url :url
    strategy :github_latest
  end

  depends_on macos: ">= :sonoma"

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
