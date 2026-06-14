cask "balcony" do
  version "0.1.29"
  sha256 "3120cb116d2e562102e12fdf044219d4428db9604ea4f05bdda0328da8427eb8"

  url "https://github.com/allthingsclaude/balcony/releases/download/v0.1.29/Balcony-0.1.29.dmg"
  name "Balcony"
  desc "Monitor and interact with Claude Code sessions from your iPhone"
  homepage "https://github.com/allthingsclaude/balcony"

  app "Balcony.app"
  binary "#{appdir}/Balcony.app/Contents/Resources/balcony-cli"

  zap trash: [
    "~/Library/Preferences/com.balcony.mac.plist",
  ]
end
