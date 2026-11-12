cask "etherdot" do
  version "1.0.1"
  sha256 "af042d8ea3599936fc4b5448cadb8f40feb8e03cde5bbf9ea76fbd9701bb3515"

  url "https://github.com/tfig-dev/EtherDot/releases/download/v#{version}/EtherDot-#{version}.dmg"
  name "EtherDot"
  desc "Menu bar indicator for Ethernet and Wi-Fi connections"
  homepage "https://github.com/tfig-dev/EtherDot"

  livecheck do
    url :url
    strategy :github_latest
  end

  auto_updates true
  depends_on macos: :ventura

  app "EtherDot.app"

  zap trash: [
    "~/Library/Caches/com.tfigueiredo.EtherDot",
    "~/Library/HTTPStorages/com.tfigueiredo.EtherDot",
    "~/Library/Preferences/com.tfigueiredo.EtherDot.plist",
  ]
end
