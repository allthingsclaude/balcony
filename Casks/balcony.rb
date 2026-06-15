cask "balcony" do
  version "0.1.38"
  sha256 "026b2f0e34ce939ea2e21a8065f2e8c35b59d68221d51bd0d4667cbfd4bdd4ef"

  url "https://github.com/allthingsclaude/balcony/releases/download/v0.1.38/Balcony-0.1.38.dmg"
  name "Balcony"
  desc "Monitor and interact with Claude Code sessions from your iPhone"
  homepage "https://github.com/allthingsclaude/balcony"

  app "Balcony.app"
  binary "#{appdir}/Balcony.app/Contents/Resources/balcony-cli"

  zap trash: [
    "~/Library/Preferences/com.balcony.mac.plist",
  ]
end
