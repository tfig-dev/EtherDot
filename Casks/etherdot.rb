cask "etherdot" do
  version "1.0.0"
  sha256 "1f7005803e5dc11e46c11a1356b74c358938af8257e57c9ecb17ff936f9a7562"

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
