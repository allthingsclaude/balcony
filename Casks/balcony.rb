cask "balcony" do
  version "0.1.25"
  sha256 "9105e19f69a9fd66c319b4adb701d1c64e1ff630dc789ba70f5926a1b0ac1701"

  url "https://github.com/allthingsclaude/balcony/releases/download/v0.1.25/Balcony-0.1.25.dmg"
  name "Balcony"
  desc "Monitor and interact with Claude Code sessions from your iPhone"
  homepage "https://github.com/allthingsclaude/balcony"

  app "Balcony.app"
  binary "#{appdir}/Balcony.app/Contents/Resources/balcony-cli"

  zap trash: [
    "~/Library/Preferences/com.balcony.mac.plist",
  ]
end
