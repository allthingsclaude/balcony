cask "balcony" do
  version "0.1.35"
  sha256 "9b84d8e69afc2a0269d35da6544d473ac6877c70cbaadb9c17db378e2ffe2374"

  url "https://github.com/allthingsclaude/balcony/releases/download/v0.1.35/Balcony-0.1.35.dmg"
  name "Balcony"
  desc "Monitor and interact with Claude Code sessions from your iPhone"
  homepage "https://github.com/allthingsclaude/balcony"

  app "Balcony.app"
  binary "#{appdir}/Balcony.app/Contents/Resources/balcony-cli"

  zap trash: [
    "~/Library/Preferences/com.balcony.mac.plist",
  ]
end
