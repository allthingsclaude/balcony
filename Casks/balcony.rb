cask "balcony" do
  version "0.1.23"
  sha256 "a85a5d2869b9cce9d5e399eda47d53e825a206d655fc2f43e4469f45426a1a37"

  url "https://github.com/allthingsclaude/balcony/releases/download/v0.1.23/Balcony-0.1.23.dmg"
  name "Balcony"
  desc "Monitor and interact with Claude Code sessions from your iPhone"
  homepage "https://github.com/allthingsclaude/balcony"

  app "Balcony.app"
  binary "#{appdir}/Balcony.app/Contents/Resources/balcony-cli"

  zap trash: [
    "~/Library/Preferences/com.balcony.mac.plist",
  ]
end
