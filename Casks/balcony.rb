cask "balcony" do
  version "0.1.43"
  sha256 "c3d6d2b11e12f3a3551573183e9bceba9977542bf282fd7afd282dd4bb4e0971"

  url "https://github.com/allthingsclaude/balcony/releases/download/v0.1.43/Balcony-0.1.43.dmg"
  name "Balcony"
  desc "Monitor and interact with Claude Code sessions from your iPhone"
  homepage "https://github.com/allthingsclaude/balcony"

  app "Balcony.app"
  binary "#{appdir}/Balcony.app/Contents/Resources/balcony-cli"

  zap trash: [
    "~/Library/Preferences/com.balcony.mac.plist",
  ]
end
