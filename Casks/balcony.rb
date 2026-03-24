cask "balcony" do
  version "0.1.16"
  sha256 "8a654690c71e99ecefbb6788adb3b1bad360c718ef4dd3639b4d899d079b08f0"

  url "https://github.com/allthingsclaude/balcony/releases/download/v0.1.16/Balcony-0.1.16.dmg"
  name "Balcony"
  desc "Monitor and interact with Claude Code sessions from your iPhone"
  homepage "https://github.com/allthingsclaude/balcony"

  app "Balcony.app"
  binary "#{appdir}/Balcony.app/Contents/Resources/balcony-cli"

  zap trash: [
    "~/Library/Preferences/com.balcony.mac.plist",
  ]
end
