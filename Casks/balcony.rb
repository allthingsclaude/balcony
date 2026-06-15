cask "balcony" do
  version "0.1.39"
  sha256 "6e9d345c71327248a45cb735eda7c941eabd540fda4b12ae7a0105aad7202b21"

  url "https://github.com/allthingsclaude/balcony/releases/download/v0.1.39/Balcony-0.1.39.dmg"
  name "Balcony"
  desc "Monitor and interact with Claude Code sessions from your iPhone"
  homepage "https://github.com/allthingsclaude/balcony"

  app "Balcony.app"
  binary "#{appdir}/Balcony.app/Contents/Resources/balcony-cli"

  zap trash: [
    "~/Library/Preferences/com.balcony.mac.plist",
  ]
end
