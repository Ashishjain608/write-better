# Cask for the personal tap Ashishjain608/homebrew-tap (Casks/writebetter.rb).
# Install:  brew install --cask ashishjain608/tap/writebetter
#
# Per release: bump `version` and `sha256`
#   shasum -a 256 WriteBetter-X.Y.Z.dmg
# WriteBetter updates itself through Sparkle, hence auto_updates.
cask "writebetter" do
  version "1.1.1"
  sha256 "9256afc54f1aad979790a9691593350da6c82a2df04655b47617fc93922e0e0b"

  url "https://github.com/Ashishjain608/write-better/releases/download/v#{version}/WriteBetter-#{version}.dmg"
  name "WriteBetter"
  desc "Menu-bar writing assistant that improves selected text with your own AI key"
  homepage "https://github.com/Ashishjain608/write-better"

  auto_updates true
  depends_on macos: :sonoma

  app "WriteBetter.app"

  # Deliberately not the Keychain: API keys live there and should survive a reinstall.
  zap trash: [
    "~/Library/Caches/com.aj.WriteBetter",
    "~/Library/HTTPStorages/com.aj.WriteBetter",
    "~/Library/Preferences/com.aj.WriteBetter.plist",
  ]
end
