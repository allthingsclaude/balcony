cask "balcony" do
  version "0.1.20"
  sha256 "338feb2de2093c88e42d475aeb9a638ad8528353e8136262b10eb9c601cbdac8"

  url "https://github.com/allthingsclaude/balcony/releases/download/v0.1.20/Balcony-0.1.20.dmg"
  name "Balcony"
  desc "Monitor and interact with Claude Code sessions from your iPhone"
  homepage "https://github.com/allthingsclaude/balcony"

  app "Balcony.app"
  binary "#{appdir}/Balcony.app/Contents/Resources/balcony-cli"

  zap trash: [
    "~/Library/Preferences/com.balcony.mac.plist",
  ]
end
