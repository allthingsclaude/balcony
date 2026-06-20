cask "balcony" do
  version "0.1.44"
  sha256 "aa2639d09046cd86d22fe16bbfeab507aeab8b96c04e0f06e3a88ec850df7819"

  url "https://github.com/allthingsclaude/balcony/releases/download/v0.1.44/Balcony-0.1.44.dmg"
  name "Balcony"
  desc "Monitor and interact with Claude Code sessions from your iPhone"
  homepage "https://github.com/allthingsclaude/balcony"

  app "Balcony.app"
  binary "#{appdir}/Balcony.app/Contents/Resources/balcony-cli"

  zap trash: [
    "~/Library/Preferences/com.balcony.mac.plist",
  ]
end
