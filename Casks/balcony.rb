cask "balcony" do
  version "0.1.53"
  sha256 "27592218ff52e2fc48f6dbe1f07e6236f7f5313c63fa277d494b157033dfedfe"

  url "https://github.com/allthingsclaude/balcony/releases/download/v0.1.53/Balcony-0.1.53.dmg"
  name "Balcony"
  desc "Monitor and interact with Claude Code sessions from your iPhone"
  homepage "https://github.com/allthingsclaude/balcony"

  app "Balcony.app"
  binary "#{appdir}/Balcony.app/Contents/Resources/balcony-cli"

  zap trash: [
    "~/Library/Preferences/com.balcony.mac.plist",
  ]
end
