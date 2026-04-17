cask "balcony" do
  version "0.1.24"
  sha256 "6da39f5e352689bef008f5a707b7e115fa197083536a5355212eafbaf75f4e5f"

  url "https://github.com/allthingsclaude/balcony/releases/download/v0.1.24/Balcony-0.1.24.dmg"
  name "Balcony"
  desc "Monitor and interact with Claude Code sessions from your iPhone"
  homepage "https://github.com/allthingsclaude/balcony"

  app "Balcony.app"
  binary "#{appdir}/Balcony.app/Contents/Resources/balcony-cli"

  zap trash: [
    "~/Library/Preferences/com.balcony.mac.plist",
  ]
end
