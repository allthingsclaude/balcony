cask "balcony" do
  version "0.1.37"
  sha256 "74667cebe7704063ed15a8d1e28682290be67b5b0a9c0263f65453156c842165"

  url "https://github.com/allthingsclaude/balcony/releases/download/v0.1.37/Balcony-0.1.37.dmg"
  name "Balcony"
  desc "Monitor and interact with Claude Code sessions from your iPhone"
  homepage "https://github.com/allthingsclaude/balcony"

  app "Balcony.app"
  binary "#{appdir}/Balcony.app/Contents/Resources/balcony-cli"

  zap trash: [
    "~/Library/Preferences/com.balcony.mac.plist",
  ]
end
