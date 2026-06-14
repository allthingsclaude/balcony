cask "balcony" do
  version "0.1.32"
  sha256 "54a96a75e0b438590834c755ee20c5a72a395ea0ef849905adcfbe85eec92cf9"

  url "https://github.com/allthingsclaude/balcony/releases/download/v0.1.32/Balcony-0.1.32.dmg"
  name "Balcony"
  desc "Monitor and interact with Claude Code sessions from your iPhone"
  homepage "https://github.com/allthingsclaude/balcony"

  app "Balcony.app"
  binary "#{appdir}/Balcony.app/Contents/Resources/balcony-cli"

  zap trash: [
    "~/Library/Preferences/com.balcony.mac.plist",
  ]
end
