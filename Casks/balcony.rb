cask "balcony" do
  version "0.1.22"
  sha256 "b9833645107af057d4ce0a761befc707139e9183e3caac858e12a08dbf5a6b98"

  url "https://github.com/allthingsclaude/balcony/releases/download/v0.1.22/Balcony-0.1.22.dmg"
  name "Balcony"
  desc "Monitor and interact with Claude Code sessions from your iPhone"
  homepage "https://github.com/allthingsclaude/balcony"

  app "Balcony.app"
  binary "#{appdir}/Balcony.app/Contents/Resources/balcony-cli"

  zap trash: [
    "~/Library/Preferences/com.balcony.mac.plist",
  ]
end
