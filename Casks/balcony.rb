cask "balcony" do
  version "0.1.15"
  sha256 "6d61db51d3d9edca0efeb9775944a29360b1982158176ba2fcb6b9db9e6474e1"

  url "https://github.com/allthingsclaude/balcony/releases/download/v0.1.15/Balcony-0.1.15.dmg"
  name "Balcony"
  desc "Monitor and interact with Claude Code sessions from your iPhone"
  homepage "https://github.com/allthingsclaude/balcony"

  app "Balcony.app"
  binary "#{appdir}/Balcony.app/Contents/Resources/balcony-cli"

  zap trash: [
    "~/Library/Preferences/com.balcony.mac.plist",
  ]
end
