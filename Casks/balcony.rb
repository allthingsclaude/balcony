cask "balcony" do
  version "0.1.51"
  sha256 "9ee2a09a49295b519ddea31db9564a159a34f876fed455ff738f652fc0dcf68f"

  url "https://github.com/allthingsclaude/balcony/releases/download/v0.1.51/Balcony-0.1.51.dmg"
  name "Balcony"
  desc "Monitor and interact with Claude Code sessions from your iPhone"
  homepage "https://github.com/allthingsclaude/balcony"

  app "Balcony.app"
  binary "#{appdir}/Balcony.app/Contents/Resources/balcony-cli"

  zap trash: [
    "~/Library/Preferences/com.balcony.mac.plist",
  ]
end
