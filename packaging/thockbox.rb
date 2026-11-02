# Homebrew cask for ThockBox. It lives in the tap repository
# Bruno-Alumn/homebrew-thockbox (Casks/thockbox.rb); this copy is the source.
# `make cask` sets the version and sha256 from the release disk image.
cask "thockbox" do
  version "1.2.1"
  sha256 "1b00fb6f0339fad83b785603df229ff86b5e54a8b97f24f2eede17f998ad7665"

  url "https://github.com/Bruno-Alumn/ThockBox/releases/download/v#{version}/ThockBox-#{version}.dmg"
  name "ThockBox"
  desc "Mechanical keyboard sounds for every key you type"
  homepage "https://github.com/Bruno-Alumn/ThockBox"

  # The app updates itself from GitHub releases.
  auto_updates true
  depends_on macos: :ventura

  app "ThockBox.app"

  uninstall quit: "io.github.bruno-alumn.thockbox"

  zap trash: [
    "~/Library/Application Support/ThockBox",
    "~/Library/Caches/io.github.bruno-alumn.thockbox",
    "~/Library/HTTPStorages/io.github.bruno-alumn.thockbox",
    "~/Library/Preferences/io.github.bruno-alumn.thockbox.plist",
  ]

  caveats <<~EOS
    ThockBox isn't notarized by Apple. The first time you open it, macOS
    asks whether to open it: choose Open, or allow it in System Settings →
    Privacy & Security → Open Anyway.

    ThockBox needs Accessibility access to hear key presses. It asks on
    first launch.
  EOS
end
