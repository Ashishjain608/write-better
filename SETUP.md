# SETUP.md — building, packaging and maintaining WriteBetter

For what the app *does*, see [README.md](README.md). This file is about the
project itself.

---

> Cutting a release? Jump to [§7 Releasing and auto-update](#7-releasing-and-auto-update): push a `vX.Y.Z` tag.

## 1. Get it building

```bash
git clone https://github.com/Ashishjain608/write-better.git
cd write-better
open WriteBetter/WriteBetter.xcodeproj
```

Xcode 26+ (the app uses the macOS 26 SDK; the deployment target is 14). One
dependency, **Sparkle 2** (auto-update), pinned to an exact version as a Swift
Package that Xcode resolves on first open. No `.env` file, no generated code.
Press `⌘R`.

There is no API key in the repo and none is needed to build. Keys are entered in
the app's Settings window at runtime and stored in the macOS Keychain
(`kSecClassGenericPassword`, service `com.aj.WriteBetter.apikeys`, account =
provider id). If you have an old `ANTHROPIC_API_KEY` sitting in
`UserDefaults` from a previous build, the app migrates it into the Keychain on
first launch and deletes it.

## 2. Layout

```
write-better/
├── create-dmg.sh                    build + sign + package + verify, one command
├── .github/workflows/               ci.yml (build + self-check), release.yml (tag → DMG → appcast)
├── packaging/homebrew/writebetter.rb  cask for the personal tap
├── scripts/
│   ├── make-appcast.sh              signs the DMG and writes appcast.xml (CI only)
│   ├── dmg-requirements.txt         hash-pinned dmgbuild
│   ├── artwork.swift                every raster asset, from one set of geometry
│   ├── make-icons.sh                regenerates Assets.xcassets
│   ├── dmg_settings.py              dmgbuild layout for the installer window
│   └── verify_dmg.py                asserts the built DMG's .DS_Store is correct
└── WriteBetter/
    ├── WriteBetter.xcodeproj
    └── WriteBetter/
        ├── Info.plist               the real one — see §3
        ├── WriteBetter.entitlements
        ├── Assets.xcassets/         generated; do not hand-edit
        ├── WriteBetterApp.swift
        ├── Managers/                hotkey, capture, replace, accessibility, Updater (Sparkle)
        ├── Models/                  QuickAction, ImprovementRequest
        ├── Services/                one client per provider + the SSE plumbing
        ├── Utils/                   AIProvider, SettingsStore, Keychain
        └── Views/                   the floating panel, Settings, onboarding
```

The target uses a **`PBXFileSystemSynchronizedRootGroup`**. Any `.swift` file
placed anywhere under `WriteBetter/WriteBetter/` is compiled automatically —
never edit `project.pbxproj` to register a source file. The only two files
excluded from that automatic membership are `Info.plist` and
`WriteBetter.entitlements` (via a `PBXFileSystemSynchronizedBuildFileExceptionSet`),
because they are consumed as build inputs rather than copied in as resources.

## 3. Info.plist and entitlements

`WriteBetter/WriteBetter/Info.plist` **is** the shipped `Info.plist`:
`INFOPLIST_FILE` points at it and `GENERATE_INFOPLIST_FILE = NO`.

Do not add `INFOPLIST_KEY_*` build settings. With generation off they are
ignored, and mixing the two mechanisms is how this project previously shipped a
bundle with no usage-description strings and a copyright field containing a file
path. One file, one source of truth.

Version numbers are the exception: `CFBundleShortVersionString` and
`CFBundleVersion` are `$(MARKETING_VERSION)` / `$(CURRENT_PROJECT_VERSION)`, so
they are still bumped in build settings (or by `agvtool`) in one place.

Keys that matter:

| Key | Why |
|---|---|
| `LSUIElement` | Menu-bar-only. Set here, not with `NSApp.setActivationPolicy(.accessory)` at runtime — doing it at runtime flashes a Dock icon before it takes effect. |
| `LSMinimumSystemVersion` | `$(MACOSX_DEPLOYMENT_TARGET)` = **14.0**. |
| `LSApplicationCategoryType` | `public.app-category.productivity`. |
| `NSAccessibilityUsageDescription` | Shown when the user opts into auto-capture or Replace. Written to be honest that both are optional. |
| `SUFeedURL` | `https://github.com/Ashishjain608/write-better/releases/latest/download/appcast.xml`: a release asset, so it always points at the newest non-prerelease. |
| `SUPublicEDKey` | Public half of the Sparkle EdDSA key. Every update DMG is verified against it. |
| `SUEnableAutomaticChecks` | Default on; users can turn it off in About. |

`WriteBetter.entitlements` is deliberately tiny: sandbox **off**, network client
**on**. Nothing else. There is no Apple Events entitlement or usage string:
Replace-in-place uses `NSRunningApplication.activate` and `CGEvent.post`, and
neither sends Apple Events.

The app **must stay unsandboxed**. Inside the sandbox `AXIsProcessTrusted()`
always returns false and the Accessibility prompt never appears, so auto-capture
and Replace-in-place could not exist.

## 4. Build settings you should know about

| Setting | Value | Note |
|---|---|---|
| `MACOSX_DEPLOYMENT_TARGET` | `14.0` | Anything newer must sit behind `if #available`. |
| `ENABLE_HARDENED_RUNTIME` | `YES` | Required for notarization, sandboxed or not. |
| `ENABLE_APP_SANDBOX` | `NO` | See above. |
| `CODE_SIGN_INJECT_BASE_ENTITLEMENTS` | `NO` (Release) | Stops Xcode injecting `com.apple.security.get-task-allow`, a debug entitlement that must never ship. `create-dmg.sh` fails the build if it finds it anyway. |
| `CODE_SIGN_IDENTITY` | `-` (Release) | Release builds are ad-hoc signed by Xcode; `create-dmg.sh` re-signs afterwards with a Developer ID when one exists. Debug stays on automatic signing so the debugger works. |
| `SWIFT_VERSION` | `5.0` | |

## 5. Artwork

Everything visual is generated. `scripts/artwork.swift` is a literal
transcription of the "Caret Ascend" geometry from the design brief, drawn once
with Core Graphics and emitted at every size the product needs. Nothing is
hand-drawn and nothing is checked in that the script cannot rebuild byte for
byte.

```bash
./scripts/make-icons.sh     # rewrites WriteBetter/WriteBetter/Assets.xcassets
```

That produces three asset names the app code depends on — **do not rename them**:

| Asset | What |
|---|---|
| `AppIcon` | Full `.appiconset`, 16/32/128/256/512 at 1x and 2x, on the macOS squircle. Below 32pt the spark is dropped and the caret thickens so the mark survives. |
| `MenuBarIcon` | Monochrome **template** image, 18×18 + 36×36. macOS tints it for light/dark menu bars and for the menu-open state. |
| `LogoMark` | Full-colour glyph, 256/512, for the panel header, Settings and onboarding. |

The DMG background comes out of the same file (`artwork.swift dmgbg`) so the
installer, the icon and the app are unmistakably the same product. The window
size and icon coordinates are duplicated in exactly two places —
`artwork.swift` (`dmgWindow`, `dmgIconY`) and `scripts/dmg_settings.py`
(`window_rect`, `icon_locations`). If you change one, change the other;
`scripts/verify_dmg.py` will catch you if you don't.

## 6. Packaging

```bash
./create-dmg.sh                          # build from source, then package
./create-dmg.sh --app /path/to/App.app   # package an existing bundle
./create-dmg.sh --output /tmp/out.dmg   # default: dist/WriteBetter.dmg
./create-dmg.sh --offline                # never touch the network for tooling
```

The two stages are separable on purpose: `--app` lets you exercise the whole
packaging pipeline without compiling, which is what you want when the Swift side
is mid-change.

What it does, in order:

1. Looks for a `Developer ID Application` identity and picks a mode.
2. Builds (or copies) the app into `build/stage/`. Your original is never
   touched.
3. Signs inside-out — Sparkle's XPC services, `Autoupdate` and `Updater.app`,
   then the framework, then the app, all with `--options runtime --timestamp`
   and the identity chosen by SHA-1 hash. Never
   `codesign --deep`; per TN2206 that is for emergency repairs, not for signing
   something you intend to ship. `--deep` is used only for *verification*.
4. Fails hard if the signed bundle carries `get-task-allow`.
5. Notarizes and staples, if there is an identity *and* credentials. It reads
   `notarytool`'s JSON and requires `Accepted` (`submit --wait` exits 0 even on
   `Invalid`); otherwise it prints Apple's log and fails. Credentials, first
   match wins: `WRITEBETTER_NOTARY_PROFILE` (keychain profile);
   `WRITEBETTER_NOTARY_APPLE_ID` + `_PASSWORD` (app-specific) + `_TEAM_ID`;
   `WRITEBETTER_NOTARY_KEY` + `_KEY_ID` + `_ISSUER` (API key).
6. Generates the background art and volume icon. The Gatekeeper warning is drawn
   into the background **only** when the build is not notarized, so the art can
   never lie about the build it ships with.
7. Builds the DMG with **`dmgbuild`**, installed into `build/.venv` from the
   hash-pinned `scripts/dmg-requirements.txt` (gitignored venv, so your global
   site-packages are left alone). dmgbuild writes the `.DS_Store`
   and alias records directly and never talks to Finder — no AppleScript, no
   Automation/TCC prompt, none of the `hdiutil detach: Resource busy` races that
   every Finder-driving tool has open issues for.
8. Signs, notarizes and staples the DMG itself, when in Developer ID mode.
9. In Developer ID mode, `spctl` on the app and DMG and `stapler validate` are
   fatal. Then mounts the result and runs `scripts/verify_dmg.py`, which reads the
   `.DS_Store` back and asserts the window size, hidden chrome, icon size, both
   icon positions and the background reference actually took. A DMG that
   *mounts* proves nothing; this proves the layout.

If `dmgbuild` cannot be installed (no network, no venv) the script falls back to
a plain unstyled `hdiutil` image and says so in a box you cannot miss, with a
`READ ME FIRST.txt` inside. It never downgrades silently.

Everything lands in `build/` and `dist/`, both gitignored.

### What is deliberately *not* here

- **No "Install WriteBetter.app" shell-script wrapper.** A `.app` whose payload
  is a shell script is the Shlayer malware pattern: it cannot be notarized, it
  has no signature to check, and it trains users to double-click exactly the
  thing they should not. Plain drag-to-Applications is both safer and the
  convention for this class of app.

## 7. Releasing and auto-update

Releases are cut by pushing a tag; `.github/workflows/release.yml` does the rest.

```bash
# bump MARKETING_VERSION and CURRENT_PROJECT_VERSION (Sparkle compares the build number)
git tag v1.2.0 && git push origin v1.2.0
```

The workflow refuses a tag that disagrees with `MARKETING_VERSION`, builds,
signs, notarizes and staples the app and the DMG, and creates the GitHub Release
with `WriteBetter.dmg` (stable name, what the website links) and
`WriteBetter-1.2.0.dmg`. Tags containing `-` (`v1.2.0-rc.1`) are prereleases:
same build, **no appcast**, so nobody is auto-updated to them. Try any change to
signing with an `rc` tag first.

For non-prerelease tags it also uploads `appcast.xml` (one item, EdDSA-signed by
`scripts/make-appcast.sh`). Sparkle in installed apps reads
`releases/latest/download/appcast.xml`, which GitHub resolves to the newest
non-prerelease.

### Repository secrets

Same names as the sibling Notes & Goals app, so the values can be copied.

| Secret | What |
|---|---|
| `APPLE_CERTIFICATE` | base64 of the Developer ID Application `.p12` (`base64 -i cert.p12 \| pbcopy`) |
| `APPLE_CERTIFICATE_PASSWORD` | the `.p12` export password |
| `APPLE_SIGNING_IDENTITY` | the certificate name or SHA-1 hash (`security find-identity -v -p codesigning`) |
| `APPLE_ID` | Apple ID email used for notarization |
| `APPLE_PASSWORD` | app-specific password for that Apple ID |
| `APPLE_TEAM_ID` | `ZC7J54L64J` |
| `SPARKLE_ED_PRIVATE_KEY` | Sparkle EdDSA private key (below) |

The Sparkle private key was generated with Sparkle's `generate_keys` and lives in
the maintainer's login keychain. Never commit or paste it. To set the secret:

```bash
generate_keys -x /tmp/sparkle.key      # from build/DerivedData/SourcePackages/artifacts/sparkle/Sparkle/bin/
gh secret set SPARKLE_ED_PRIVATE_KEY -R Ashishjain608/write-better < /tmp/sparkle.key
rm -P /tmp/sparkle.key
```

Losing this key means existing installs can never verify another update: back it
up somewhere private (a password manager), not in the repo.

### Homebrew

`packaging/homebrew/writebetter.rb` is a cask for a personal tap. One-time setup:

```bash
gh repo create Ashishjain608/homebrew-tap --public
git clone https://github.com/Ashishjain608/homebrew-tap && cd homebrew-tap
mkdir -p Casks && cp ../write-better/packaging/homebrew/writebetter.rb Casks/
# set sha256 to: shasum -a 256 WriteBetter-1.1.0.dmg
git add . && git commit -m "Add writebetter cask" && git push
brew install --cask ashishjain608/tap/writebetter
```

Each release: bump `version` and `sha256` in the tap. `auto_updates true` tells
brew that Sparkle handles upgrades in the app.

## 8. Troubleshooting

**"WriteBetter is damaged and can't be opened"** — the build is not notarized.
System Settings → Privacy & Security → Security → Open Anyway. See README.

**The hotkey does nothing** — another app owns `⇧⌘Space`. The app logs a
registration failure to the console; check for a conflicting Spotlight or input
source shortcut.

**Replace does nothing / auto-capture returns the wrong text** — Accessibility
is not granted, or was granted to a *different copy* of the app. macOS keys the
grant to the code signature and path, so a rebuild in DerivedData is a different
app to TCC than the one in `/Applications`. Remove and re-add it.

**Asset catalog looks stale after `make-icons.sh`** — Xcode caches compiled
assets aggressively. `⇧⌘K` (Clean Build Folder), then rebuild.

**`create-dmg.sh` fails at the verify step** — the layout did not take. Check
that `artwork.swift` and `dmg_settings.py` still agree on the window size and
icon coordinates.
