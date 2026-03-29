cask "flint" do
  version "0.9.31"
  sha256 "5fe6a081e4903f95aeae2211baf1455d1dbc223b342b78f9e5741dd52e88d60e"

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
