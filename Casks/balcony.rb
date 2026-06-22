cask "balcony" do
  version "0.1.48"
  sha256 "028b745ea9c30fa139ef839e2d2b6ce9a8357d3da86fdd536b72b62587382cda"

  url "https://github.com/allthingsclaude/balcony/releases/download/v0.1.48/Balcony-0.1.48.dmg"
  name "Balcony"
  desc "Monitor and interact with Claude Code sessions from your iPhone"
  homepage "https://github.com/allthingsclaude/balcony"

  app "Balcony.app"
  binary "#{appdir}/Balcony.app/Contents/Resources/balcony-cli"

  zap trash: [
    "~/Library/Preferences/com.balcony.mac.plist",
  ]
end
