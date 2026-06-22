cask "balcony" do
  version "0.1.47"
  sha256 "c6cf2f6ec5b9ec036c5ff458592901ce10abe80c929a6ded053d47bbbc105676"

  url "https://github.com/allthingsclaude/balcony/releases/download/v0.1.47/Balcony-0.1.47.dmg"
  name "Balcony"
  desc "Monitor and interact with Claude Code sessions from your iPhone"
  homepage "https://github.com/allthingsclaude/balcony"

  app "Balcony.app"
  binary "#{appdir}/Balcony.app/Contents/Resources/balcony-cli"

  zap trash: [
    "~/Library/Preferences/com.balcony.mac.plist",
  ]
end
