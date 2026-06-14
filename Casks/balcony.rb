cask "balcony" do
  version "0.1.27"
  sha256 "aa3cf5678d5413e6f12a94db2cd4d2d58447dd213fec4038412e74b7068ef13a"

  url "https://github.com/allthingsclaude/balcony/releases/download/v0.1.27/Balcony-0.1.27.dmg"
  name "Balcony"
  desc "Monitor and interact with Claude Code sessions from your iPhone"
  homepage "https://github.com/allthingsclaude/balcony"

  app "Balcony.app"
  binary "#{appdir}/Balcony.app/Contents/Resources/balcony-cli"

  zap trash: [
    "~/Library/Preferences/com.balcony.mac.plist",
  ]
end
