cask "balcony" do
  version "0.1.18"
  sha256 "d2d9be3788a3ccbeea149cf1e2cc78bea4fd1a1f5074b5ee9056b1d9cc66479a"

  url "https://github.com/allthingsclaude/balcony/releases/download/v0.1.18/Balcony-0.1.18.dmg"
  name "Balcony"
  desc "Monitor and interact with Claude Code sessions from your iPhone"
  homepage "https://github.com/allthingsclaude/balcony"

  app "Balcony.app"
  binary "#{appdir}/Balcony.app/Contents/Resources/balcony-cli"

  zap trash: [
    "~/Library/Preferences/com.balcony.mac.plist",
  ]
end
