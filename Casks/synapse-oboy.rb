cask "synapse-oboy" do
  version "1.3.1"
  sha256 "e7c79df1171734922697e0e7580800624147a203257eadac7c3d7600c0f199c5"

  url "https://github.com/0smboy/Synapse/releases/download/v#{version}/Synapse-v#{version}-macos-arm64.zip"
  name "Synapse"
  desc "Floating command center for macOS with Codex-powered workflows"
  homepage "https://github.com/0smboy/Synapse"

  depends_on macos: ">= :sonoma"

  app "Synapse.app"

  zap trash: [
    "~/Library/Preferences/com.oboy.synapse.plist",
    "~/Library/Application Support/Synapse",
  ]
end
