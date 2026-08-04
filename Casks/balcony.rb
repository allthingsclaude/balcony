cask "balcony" do
  version "0.1.58"
  sha256 "c9d3f723fd567052972c63fa65deca565cd4fe46f65f2948e7dd3bb4575e6e94"

  url "https://github.com/allthingsclaude/balcony/releases/download/v0.1.58/Balcony-0.1.58.dmg"
  name "Balcony"
  desc "Monitor and interact with Claude Code sessions from your iPhone"
  homepage "https://github.com/allthingsclaude/balcony"

  app "Balcony.app"
  binary "#{appdir}/Balcony.app/Contents/Resources/balcony-cli"

  zap trash: [
    "~/Library/Preferences/com.balcony.mac.plist",
  ]
end
