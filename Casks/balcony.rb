cask "balcony" do
  version "0.1.11"
  sha256 "PLACEHOLDER"

  url "https://github.com/allthingsclaude/balcony/releases/download/v0.1.11/Balcony-0.1.11.dmg"
  name "Balcony"
  desc "Monitor and interact with Claude Code sessions from your iPhone"
  homepage "https://github.com/allthingsclaude/balcony"

  app "Balcony.app"
  binary "#{appdir}/Balcony.app/Contents/Resources/balcony-cli"

  zap trash: [
    "~/Library/Preferences/com.balcony.mac.plist",
  ]
end
