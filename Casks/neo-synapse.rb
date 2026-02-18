cask "neo-synapse" do
  version "2.0.0"
  sha256 "1c86b60cddf9b04f0558aaa5bdc47f23197a821203042dc40e998cfa919b5085"

  url "https://github.com/0smboy/neo-synapse/releases/download/v#{version}/NeoSynapse-v#{version}-macos-arm64.zip"
  name "Neo-Synapse"
  desc "Floating command center for macOS with Ray voice pet and Codex AI"
  homepage "https://github.com/0smboy/neo-synapse"

  depends_on macos: ">= :sonoma"

  app "Synapse.app"

  zap trash: [
    "~/Library/Preferences/com.oboy.neo-synapse.plist",
    "~/Library/Application Support/Synapse",
    "~/.synapse-voice",
  ]
end
