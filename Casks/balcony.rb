cask "balcony" do
  version "0.1.41"
  sha256 "64688ab2d76588e78b9b577912c74df641f89851bc400165e92dfffce9e6fe4d"

  url "https://github.com/allthingsclaude/balcony/releases/download/v0.1.41/Balcony-0.1.41.dmg"
  name "Balcony"
  desc "Monitor and interact with Claude Code sessions from your iPhone"
  homepage "https://github.com/allthingsclaude/balcony"

  app "Balcony.app"
  binary "#{appdir}/Balcony.app/Contents/Resources/balcony-cli"

  zap trash: [
    "~/Library/Preferences/com.balcony.mac.plist",
  ]
end
