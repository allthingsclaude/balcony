cask "balcony" do
  version "0.1.57"
  sha256 "67eb55d34c539436127dc59f93917a889788a51d5ed358b94b63be7522bd8432"

  url "https://github.com/allthingsclaude/balcony/releases/download/v0.1.57/Balcony-0.1.57.dmg"
  name "Balcony"
  desc "Monitor and interact with Claude Code sessions from your iPhone"
  homepage "https://github.com/allthingsclaude/balcony"

  app "Balcony.app"
  binary "#{appdir}/Balcony.app/Contents/Resources/balcony-cli"

  zap trash: [
    "~/Library/Preferences/com.balcony.mac.plist",
  ]
end
