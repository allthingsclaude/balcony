cask "balcony" do
  version "0.1.30"
  sha256 "389745f0ebbbe42bf5790436185389b807c7ef58a1e3209d2a4c6ec26d8992c6"

  url "https://github.com/allthingsclaude/balcony/releases/download/v0.1.30/Balcony-0.1.30.dmg"
  name "Balcony"
  desc "Monitor and interact with Claude Code sessions from your iPhone"
  homepage "https://github.com/allthingsclaude/balcony"

  app "Balcony.app"
  binary "#{appdir}/Balcony.app/Contents/Resources/balcony-cli"

  zap trash: [
    "~/Library/Preferences/com.balcony.mac.plist",
  ]
end
