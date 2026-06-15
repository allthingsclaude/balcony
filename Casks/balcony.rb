cask "balcony" do
  version "0.1.40"
  sha256 "82ad7abd324f9557903f7911681d0c1fd9aa4feb7fac45027bbab3a5f0f785b1"

  url "https://github.com/allthingsclaude/balcony/releases/download/v0.1.40/Balcony-0.1.40.dmg"
  name "Balcony"
  desc "Monitor and interact with Claude Code sessions from your iPhone"
  homepage "https://github.com/allthingsclaude/balcony"

  app "Balcony.app"
  binary "#{appdir}/Balcony.app/Contents/Resources/balcony-cli"

  zap trash: [
    "~/Library/Preferences/com.balcony.mac.plist",
  ]
end
