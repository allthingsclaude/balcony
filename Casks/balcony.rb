cask "balcony" do
  version "0.1.34"
  sha256 "680a582736e52dccd05a476e0c5486fb7c253de0bdf39d8c570864400e8419bb"

  url "https://github.com/allthingsclaude/balcony/releases/download/v0.1.34/Balcony-0.1.34.dmg"
  name "Balcony"
  desc "Monitor and interact with Claude Code sessions from your iPhone"
  homepage "https://github.com/allthingsclaude/balcony"

  app "Balcony.app"
  binary "#{appdir}/Balcony.app/Contents/Resources/balcony-cli"

  zap trash: [
    "~/Library/Preferences/com.balcony.mac.plist",
  ]
end
