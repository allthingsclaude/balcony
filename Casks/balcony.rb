cask "balcony" do
  version "0.1.19"
  sha256 "96a09652c97c44c3d7b04a34360d3d343e31f4bb0d52406757c35161f58d3a97"

  url "https://github.com/allthingsclaude/balcony/releases/download/v0.1.19/Balcony-0.1.19.dmg"
  name "Balcony"
  desc "Monitor and interact with Claude Code sessions from your iPhone"
  homepage "https://github.com/allthingsclaude/balcony"

  app "Balcony.app"
  binary "#{appdir}/Balcony.app/Contents/Resources/balcony-cli"

  zap trash: [
    "~/Library/Preferences/com.balcony.mac.plist",
  ]
end
