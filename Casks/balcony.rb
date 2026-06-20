cask "balcony" do
  version "0.1.45"
  sha256 "714b320fa02a7f5d08fbe34db9fa2f84f86938fc94dda3ce19d9adddccfe7aba"

  url "https://github.com/allthingsclaude/balcony/releases/download/v0.1.45/Balcony-0.1.45.dmg"
  name "Balcony"
  desc "Monitor and interact with Claude Code sessions from your iPhone"
  homepage "https://github.com/allthingsclaude/balcony"

  app "Balcony.app"
  binary "#{appdir}/Balcony.app/Contents/Resources/balcony-cli"

  zap trash: [
    "~/Library/Preferences/com.balcony.mac.plist",
  ]
end
