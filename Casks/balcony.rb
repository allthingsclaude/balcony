cask "balcony" do
  version "0.1.42"
  sha256 "3a090ddb173a585cc7cfbae57ad8e105145a1e3da37dc77de55d883753c49dfd"

  url "https://github.com/allthingsclaude/balcony/releases/download/v0.1.42/Balcony-0.1.42.dmg"
  name "Balcony"
  desc "Monitor and interact with Claude Code sessions from your iPhone"
  homepage "https://github.com/allthingsclaude/balcony"

  app "Balcony.app"
  binary "#{appdir}/Balcony.app/Contents/Resources/balcony-cli"

  zap trash: [
    "~/Library/Preferences/com.balcony.mac.plist",
  ]
end
