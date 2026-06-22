cask "balcony" do
  version "0.1.49"
  sha256 "fbdaa5484cdf2ee6cd58a21adec3e133d3a0751c8b620ef96c6a18f3ab727b51"

  url "https://github.com/allthingsclaude/balcony/releases/download/v0.1.49/Balcony-0.1.49.dmg"
  name "Balcony"
  desc "Monitor and interact with Claude Code sessions from your iPhone"
  homepage "https://github.com/allthingsclaude/balcony"

  app "Balcony.app"
  binary "#{appdir}/Balcony.app/Contents/Resources/balcony-cli"

  zap trash: [
    "~/Library/Preferences/com.balcony.mac.plist",
  ]
end
