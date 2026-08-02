cask "balcony" do
  version "0.1.55"
  sha256 "d747097025bf56d2dd1bcd9c03906fce4221c81e6944ec8f45f5acdfd4decde0"

  url "https://github.com/allthingsclaude/balcony/releases/download/v0.1.55/Balcony-0.1.55.dmg"
  name "Balcony"
  desc "Monitor and interact with Claude Code sessions from your iPhone"
  homepage "https://github.com/allthingsclaude/balcony"

  app "Balcony.app"
  binary "#{appdir}/Balcony.app/Contents/Resources/balcony-cli"

  zap trash: [
    "~/Library/Preferences/com.balcony.mac.plist",
  ]
end
