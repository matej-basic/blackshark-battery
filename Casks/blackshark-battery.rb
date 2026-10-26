cask "blackshark-battery" do
  version "0.1.0"
  sha256 "0000000000000000000000000000000000000000000000000000000000000000"

  url "https://github.com/matej-basic/blackshark-battery/releases/download/v#{version}/BlackSharkBattery-#{version}.zip"
  name "BlackShark Battery"
  desc "Menu bar app that shows Razer BlackShark V2 Pro headset battery"
  homepage "https://github.com/matej-basic/blackshark-battery"

  livecheck do
    url :url
    strategy :github_latest
  end

  depends_on macos: :sonoma

  app "BlackSharkBattery.app"

  # Ad-hoc signed, not notarized: drop the quarantine flag Homebrew sets on cask
  # downloads, otherwise Gatekeeper blocks the first launch.
  postflight_steps do
    run "/usr/bin/xattr",
        args: ["-dr", "com.apple.quarantine", "{{appdir}}/BlackSharkBattery.app"]
  end

  zap trash: "~/Library/Preferences/com.matejbasic.BlackSharkBattery.plist"
end
