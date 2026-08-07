cask "balcony" do
  version "0.1.61"
  sha256 "4ffb710020b3bb22e3a93de091cd39f87b87d7dfed63919fcb1f9e091591a906"

  url "https://github.com/allthingsclaude/balcony/releases/download/v0.1.61/Balcony-0.1.61.dmg"
  name "Balcony"
  desc "Monitor and interact with Claude Code sessions from your iPhone"
  homepage "https://github.com/allthingsclaude/balcony"

  app "Balcony.app"
  binary "#{appdir}/Balcony.app/Contents/Resources/balcony-cli"

  zap trash: [
    "~/Library/Preferences/com.balcony.mac.plist",
  ]
end
