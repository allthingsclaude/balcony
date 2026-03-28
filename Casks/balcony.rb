cask "balcony" do
  version "0.1.17"
  sha256 "ce9f3d2fc278a0b8b2586f4b0966b9176e2ce89b52d0d45dcb93377e656a26e1"

  url "https://github.com/allthingsclaude/balcony/releases/download/v0.1.17/Balcony-0.1.17.dmg"
  name "Balcony"
  desc "Monitor and interact with Claude Code sessions from your iPhone"
  homepage "https://github.com/allthingsclaude/balcony"

  app "Balcony.app"
  binary "#{appdir}/Balcony.app/Contents/Resources/balcony-cli"

  zap trash: [
    "~/Library/Preferences/com.balcony.mac.plist",
  ]
end
