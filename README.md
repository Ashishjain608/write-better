# WriteBetter

A menu-bar utility for macOS that rewrites whatever text you have on hand.
Copy something, press `⇧⌘Space`, and a floating panel streams a better version
back at you — then you copy it or paste it straight back where it came from.

No Dock icon, no window to manage, no account. Your API key stays in your Mac's
Keychain and the text goes to the provider you chose and nowhere else.

---

## What it does

- **Three providers, your key.** Anthropic (Claude), OpenAI (GPT) and Google
  Gemini. Add a key for any or all of them in Settings and switch between them
  from the panel.
- **Streaming.** The first words appear while the rest is still being written.
  `esc` cancels the request for real, and you keep whatever arrived.
- **Quick actions.** Fix Grammar, Clarify, Shorten, Professional, Friendly —
  one click or `⌘1`…`⌘5`.
- **Free-form prompts.** `⌘K`, tell it what you actually want, `⌘↩`.
- **Clipboard-first capture.** By default WriteBetter reads your clipboard, so
  it needs no permissions at all: copy with `⌘C`, then hit the hotkey.
- **Optional Accessibility upgrade.** Grant Accessibility and two extra things
  become possible: capturing the current selection without you pressing `⌘C`,
  and *Replace in place* (`⌘↩`) which pastes the result back into the app you
  came from. Both are optional; the app is fully usable without them.

## Requirements

- macOS **14.0** (Sonoma) or later, Apple Silicon or Intel.
- An API key from at least one of:
  [Anthropic](https://console.anthropic.com/settings/keys) ·
  [OpenAI](https://platform.openai.com/api-keys) ·
  [Google AI Studio](https://aistudio.google.com/apikey)

Keys are billed by the provider, per token. WriteBetter has no server, no
account and no telemetry.

## Install

Download the DMG from
[Releases](https://github.com/ashishjain/write-better/releases), open it, and
drag **WriteBetter** to **Applications**. Launch it — the caret icon appears in
your menu bar. Click it → **Settings…** → paste a key → **Test**.

> **If macOS says "WriteBetter is damaged and can't be opened":** it isn't. That
> is what macOS 15+ says about an app that has not been notarized by Apple, and
> the old right-click → Open override no longer works. Open
> **System Settings → Privacy & Security**, scroll to **Security**, click
> **Open Anyway** next to WriteBetter, and confirm. Once per version.
>
> (Do not run `xattr -dr com.apple.quarantine` on it. It works, but it also
> switches off the malware scan that quarantine triggers, and pasting shell
> commands off a web page to make a security warning go away is a habit worth
> not having.)

## Using it

| Key | Does |
|---|---|
| `⇧⌘Space` | Open the panel on whatever text is available |
| `⌘1`…`⌘5` | Run a quick action |
| `⌘K` | Focus the prompt field |
| `⌘R` | Regenerate |
| `↩` | Copy the result and close |
| `⌘↩` | Replace in place (needs Accessibility) |
| `esc` | Cancel the stream, or close the panel |
| `⌘,` | Settings |

### Permissions

Nothing is requested at launch. The Accessibility prompt only appears if you
turn on **auto-capture** or use **Replace**, from
**Settings → General**. If you change the setting in System Settings while the
app is running, WriteBetter picks it up within a second — no restart.

## Privacy

- Your text is sent to the provider you selected, over TLS, and to nobody else.
- API keys live in the macOS Keychain (`com.aj.WriteBetter.apikeys`), not in a
  plist and not in a `.env` file.
- Nothing is logged to disk. No analytics.

---

## Building from source

```bash
git clone https://github.com/ashishjain/write-better.git
cd write-better
open WriteBetter/WriteBetter.xcodeproj      # then ⌘R
```

Or from the command line:

```bash
xcodebuild -project WriteBetter/WriteBetter.xcodeproj \
           -scheme WriteBetter -configuration Release \
           -derivedDataPath build/DerivedData build
```

Requirements: Xcode 16 or later. Zero third-party dependencies — no SPM
packages, no CocoaPods, nothing to install first.

The Xcode project uses a **file-system-synchronized group**: any `.swift` file
you drop under `WriteBetter/WriteBetter/` is compiled automatically. You do not
edit `project.pbxproj` to add sources.

See [SETUP.md](SETUP.md) for the project layout, the build settings that matter,
and how the artwork and installer are generated.

## Releasing

```bash
./create-dmg.sh                        # build, sign, package, verify
./create-dmg.sh --app /path/to/App.app # package an existing bundle only
```

The script writes `dist/WriteBetter-Installer.dmg`: a plain drag-to-Applications
disk image with branded background art, a custom volume icon and no Finder
chrome. It always tells you which of the two signing worlds you are in.

**Release checklist**

1. `MARKETING_VERSION` and `CURRENT_PROJECT_VERSION` bumped in
   `WriteBetter.xcodeproj` (they flow into `Info.plist` automatically).
2. `./scripts/make-icons.sh` if the mark changed.
3. `./create-dmg.sh` — it must end with `layout verified against the .DS_Store`.
4. Mount the DMG and look at it: background, arrow, both icons at the same
   height, app icon on the volume.
5. Install from the DMG on a clean account and check the hotkey, one improvement
   per provider, and the Accessibility flow.
6. Upload to GitHub Releases with the version in the tag.
7. If the build was not notarized, say so in the release notes and repeat the
   "Open Anyway" instructions there.

### If you get a Developer ID

This is the one thing standing between the current build and a normal install
experience. Once you have an Apple Developer Program membership ($99/yr) and a
**Developer ID Application** certificate in your login keychain, `create-dmg.sh`
picks it up automatically — `security find-identity -v -p codesigning` is all it
looks at. Then:

```bash
# once: store an App Store Connect API key as a notarytool keychain profile
xcrun notarytool store-credentials WriteBetterNotary \
  --key ~/keys/AuthKey_XXXXXXXXXX.p8 --key-id XXXXXXXXXX --issuer <issuer-uuid>

export WRITEBETTER_NOTARY_PROFILE=WriteBetterNotary
./create-dmg.sh
```

The script will then sign with `--options runtime --timestamp`, submit to
`notarytool` and wait, staple the ticket to the app, rebuild the DMG around the
stapled app, sign and staple the DMG too, and verify with `codesign --verify
--deep --strict` and `spctl`. The Gatekeeper warning disappears from the DMG
background art on its own, because the art is generated per build.

If you prefer raw API-key credentials over a keychain profile, set
`WRITEBETTER_NOTARY_KEY`, `WRITEBETTER_NOTARY_KEY_ID` and
`WRITEBETTER_NOTARY_ISSUER` instead; both paths are supported.

After that, a [Homebrew Cask](https://docs.brew.sh/Adding-Software-to-Homebrew)
becomes worth doing — `brew install --cask writebetter` gives users
install/upgrade/uninstall for free. It is not worth submitting before
notarization works, because `brew` cannot route around Gatekeeper either.

## Licence

MIT.
