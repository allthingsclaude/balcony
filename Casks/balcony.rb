cask "balcony" do
  version "0.1.54"
  sha256 "9b3fe53cf119d7a308a626c37014a8d0aa3802ba944a205e9cd5dd99ca705484"

  url "https://github.com/allthingsclaude/balcony/releases/download/v0.1.54/Balcony-0.1.54.dmg"
  name "Balcony"
  desc "Monitor and interact with Claude Code sessions from your iPhone"
  homepage "https://github.com/allthingsclaude/balcony"

  app "Balcony.app"
  binary "#{appdir}/Balcony.app/Contents/Resources/balcony-cli"

  zap trash: [
    "~/Library/Preferences/com.balcony.mac.plist",
  ]
end
