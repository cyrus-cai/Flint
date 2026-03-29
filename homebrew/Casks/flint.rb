cask "flint" do
  version "0.9.30"
  sha256 "7a029ec70400d12cd4e94219bd5d15dcc3f483aff0220862a4acf0c5acc7b12c"

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
