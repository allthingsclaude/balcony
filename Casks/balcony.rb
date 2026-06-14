cask "balcony" do
  version "0.1.28"
  sha256 "ecee23f65a445f93c3581a54b635559826c2c021c040a7e292d5537ebacfe725"

  url "https://github.com/allthingsclaude/balcony/releases/download/v0.1.28/Balcony-0.1.28.dmg"
  name "Balcony"
  desc "Monitor and interact with Claude Code sessions from your iPhone"
  homepage "https://github.com/allthingsclaude/balcony"

  app "Balcony.app"
  binary "#{appdir}/Balcony.app/Contents/Resources/balcony-cli"

  zap trash: [
    "~/Library/Preferences/com.balcony.mac.plist",
  ]
end
