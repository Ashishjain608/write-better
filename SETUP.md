# SETUP.md — building, packaging and maintaining WriteBetter

For what the app *does*, see [README.md](README.md). This file is about the
project itself.

---

## 1. Get it building

```bash
git clone https://github.com/ashishjain/write-better.git
cd write-better
open WriteBetter/WriteBetter.xcodeproj
```

Xcode 16+. Nothing to install: **zero third-party dependencies**, no package
manager, no `.env` file, no generated code. Press `⌘R`.

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
├── scripts/
│   ├── artwork.swift                every raster asset, from one set of geometry
│   ├── make-icons.sh                regenerates Assets.xcassets
│   ├── dmg_settings.py              dmgbuild layout for the installer window
│   └── verify_dmg.py                asserts the built DMG's .DS_Store is correct
└── WriteBetter/
    ├── ExportOptions.plist          for `xcodebuild -exportArchive`, if you use it
    ├── WriteBetter.xcodeproj
    └── WriteBetter/
        ├── Info.plist               the real one — see §3
        ├── WriteBetter.entitlements
        ├── Assets.xcassets/         generated; do not hand-edit
        ├── WriteBetterApp.swift
        ├── Managers/                hotkey, capture, replace, accessibility
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
| `NSAppleEventsUsageDescription` | Replace-in-place hands the improved text back to the app you came from. Missing this string terminates a hardened-runtime app the first time it tries. |

`WriteBetter.entitlements` is deliberately tiny: sandbox **off**, network client
**on**, Apple Events **on**. Nothing else.

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
./create-dmg.sh --output /tmp/out.dmg
./create-dmg.sh --offline                # never touch the network for tooling
```

The two stages are separable on purpose: `--app` lets you exercise the whole
packaging pipeline without compiling, which is what you want when the Swift side
is mid-change.

What it does, in order:

1. Looks for a `Developer ID Application` identity and picks a mode.
2. Builds (or copies) the app into `build/stage/`. Your original is never
   touched.
3. Signs inside-out — nested code first, outer bundle last. Never
   `codesign --deep`; per TN2206 that is for emergency repairs, not for signing
   something you intend to ship. `--deep` is used only for *verification*.
4. Fails hard if the signed bundle carries `get-task-allow`.
5. Notarizes and staples, if there is an identity *and* credentials.
6. Generates the background art and volume icon. The Gatekeeper warning is drawn
   into the background **only** when the build is not notarized, so the art can
   never lie about the build it ships with.
7. Builds the DMG with **`dmgbuild`**, installed into `build/.venv` (gitignored,
   so your global site-packages are left alone). dmgbuild writes the `.DS_Store`
   and alias records directly and never talks to Finder — no AppleScript, no
   Automation/TCC prompt, none of the `hdiutil detach: Resource busy` races that
   every Finder-driving tool has open issues for.
8. Signs and staples the DMG itself, when in Developer ID mode.
9. Mounts the result and runs `scripts/verify_dmg.py`, which reads the
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
- **No Sparkle.** Auto-update costs EdDSA key custody, an appcast to host and an
  extra signed framework to nest. Not worth it until there is a release cadence
  to automate. GitHub Releases is enough.

## 7. Troubleshooting

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
