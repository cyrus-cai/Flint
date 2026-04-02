cask "flint" do
  version "0.9.32"
  sha256 "e205f19b22ec3bd9ee657feaed5653d4cec24def6df75e74de984a0a5551fb2e"

  url "https://github.com/cyrus-cai/Flint/releases/download/v#{version}-beta/Flint.zip"
  name "Flint"
  desc "Lightweight note-taking app with MCP support for AI agents"
  homepage "https://github.com/cyrus-cai/Flint"

  depends_on macos: ">= :sequoia"
  depends_on arch: :arm64

  app "Flint.app"

  zap trash: [
    "~/Library/Preferences/com.cyrus.Flint.plist",
    "~/Library/Application Support/Flint",
  ]
end
