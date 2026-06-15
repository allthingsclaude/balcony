cask "balcony" do
  version "0.1.36"
  sha256 "4cabe97598cf28eec85f64486eb2473954cb0219d4327bd1ad985cc0408fb77d"

  url "https://github.com/allthingsclaude/balcony/releases/download/v0.1.36/Balcony-0.1.36.dmg"
  name "Balcony"
  desc "Monitor and interact with Claude Code sessions from your iPhone"
  homepage "https://github.com/allthingsclaude/balcony"

  app "Balcony.app"
  binary "#{appdir}/Balcony.app/Contents/Resources/balcony-cli"

  zap trash: [
    "~/Library/Preferences/com.balcony.mac.plist",
  ]
end
