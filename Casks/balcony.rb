cask "balcony" do
  version "0.1.26"
  sha256 "df546e2ae054c02e402a481e052e54d7193e5974b1322b5cfebfcb4cdba1ffee"

  url "https://github.com/allthingsclaude/balcony/releases/download/v0.1.26/Balcony-0.1.26.dmg"
  name "Balcony"
  desc "Monitor and interact with Claude Code sessions from your iPhone"
  homepage "https://github.com/allthingsclaude/balcony"

  app "Balcony.app"
  binary "#{appdir}/Balcony.app/Contents/Resources/balcony-cli"

  zap trash: [
    "~/Library/Preferences/com.balcony.mac.plist",
  ]
end
