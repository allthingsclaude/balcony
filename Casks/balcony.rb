cask "balcony" do
  version "0.1.50"
  sha256 "0c0f0b3fc84de5ec4fbf7dab7cbc6c1ef08963f97f94cc01a22312ad542d9f68"

  url "https://github.com/allthingsclaude/balcony/releases/download/v0.1.50/Balcony-0.1.50.dmg"
  name "Balcony"
  desc "Monitor and interact with Claude Code sessions from your iPhone"
  homepage "https://github.com/allthingsclaude/balcony"

  app "Balcony.app"
  binary "#{appdir}/Balcony.app/Contents/Resources/balcony-cli"

  zap trash: [
    "~/Library/Preferences/com.balcony.mac.plist",
  ]
end
