cask "balcony" do
  version "0.1.21"
  sha256 "b055141bd0cfa63abc9b59e66f53ad83f987df2f3a32284af9f590a8f9cfd5dc"

  url "https://github.com/allthingsclaude/balcony/releases/download/v0.1.21/Balcony-0.1.21.dmg"
  name "Balcony"
  desc "Monitor and interact with Claude Code sessions from your iPhone"
  homepage "https://github.com/allthingsclaude/balcony"

  app "Balcony.app"
  binary "#{appdir}/Balcony.app/Contents/Resources/balcony-cli"

  zap trash: [
    "~/Library/Preferences/com.balcony.mac.plist",
  ]
end
