cask "balcony" do
  version "0.1.59"
  sha256 "18c42dea721aacce527c3c9054ea53b8e6b5b2dfc2ecd79f1e00e0fb37424dd1"

  url "https://github.com/allthingsclaude/balcony/releases/download/v0.1.59/Balcony-0.1.59.dmg"
  name "Balcony"
  desc "Monitor and interact with Claude Code sessions from your iPhone"
  homepage "https://github.com/allthingsclaude/balcony"

  app "Balcony.app"
  binary "#{appdir}/Balcony.app/Contents/Resources/balcony-cli"

  zap trash: [
    "~/Library/Preferences/com.balcony.mac.plist",
  ]
end
