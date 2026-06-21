cask "balcony" do
  version "0.1.46"
  sha256 "781bc39762414a961d381f2b029ff676e5d9bdabebb346c8708381f015d75222"

  url "https://github.com/allthingsclaude/balcony/releases/download/v0.1.46/Balcony-0.1.46.dmg"
  name "Balcony"
  desc "Monitor and interact with Claude Code sessions from your iPhone"
  homepage "https://github.com/allthingsclaude/balcony"

  app "Balcony.app"
  binary "#{appdir}/Balcony.app/Contents/Resources/balcony-cli"

  zap trash: [
    "~/Library/Preferences/com.balcony.mac.plist",
  ]
end
