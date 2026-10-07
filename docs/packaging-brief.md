# WriteBetter DMG: Research Brief (2026)

Machine facts verified during research (2026-08-05): macOS 26.5.2 "Tahoe" (build 25F84), full Xcode.app installed (`xcode-select -p` → `/Applications/Xcode.app/Contents/Developer`), `xcrun notarytool` present, `python3` 3.12 with **Pillow 12.1.1 already installed**, `pip3` present but **`dmgbuild` NOT installed**, stock tools `iconutil`, `sips`, `tiffutil`, `SetFile`, `bless`, `hdiutil` all present, `node`/`npm` present, **`create-dmg` NOT installed** (brew or npm), **ImageMagick NOT installed**, `security find-identity -v -p codesigning` → **0 valid identities** (no Developer ID cert, no Apple Developer Program membership loaded on this machine).

---

## Recommendation (do this, in order)

1. **Buy the $99/yr Apple Developer Program membership.** This is the one blocker that actually matters. Everything else (styled DMG, background art, drag-arrow) is cosmetic; the lack of a Developer ID certificate is the reason every user who downloads `WriteBetter.dmg` today will hit a **"WriteBetter is damaged and can't be opened, move it to Trash"** dialog on macOS 15/26 (ad-hoc/unsigned quarantined app + Gatekeeper, not a real corruption — see §4). Without a paid account there is no code path to a normal install experience for a menu-bar utility that needs Accessibility + network permissions; every alternative is a support burden shifted onto the user (`xattr -dr`, `spctl --master-disable`, multi-click System Settings dance). [swissmacuser.ch](https://swissmacuser.ch/fix-macos-tahoe-app-is-damaged-and-cant-be-opened-move-trash/), [eclecticlight.co](https://eclecticlight.co/2024/10/01/living-without-notarization/), [developer.apple.com/news](https://developer.apple.com/news/?id=saqachfa)

2. **Rewrite `create-dmg.sh` as a graceful-degradation build script** (design in §5) that:
   - Runs `security find-identity -v -p codesigning` at build time.
   - If a `Developer ID Application: ...` identity exists → sign every nested binary inside-out with `--options runtime --timestamp`, notarize with `xcrun notarytool submit --wait`, staple with `xcrun stapler staple`, and ship a DMG that opens with zero warnings.
   - If not → ad-hoc sign (`codesign -s -`) so the app at least runs locally and passes `codesign --verify`, and **stop lying about it**: put real, version-specific instructions for the current fallback state into the DMG (README + on-screen text), not generic "drag to Applications" copy that omits the Gatekeeper hurdle the user is about to hit.

3. **Delete the shell-script "Install WriteBetter.app" bundle from the DMG.** A `.app` whose payload is a shell script is exactly the Shlayer-malware pattern (unsigned/script payload inside a DMG that bypasses the checks Gatekeeper does on real Mach-O binaries) — see §1. Ship the plain drag-to-Applications pattern instead; it is both the universal convention for utilities like this (Rectangle, CleanShot X, Raycast, VLC, IINA) and strictly safer.

4. **Build the styled DMG with `dmgbuild` (pip-installed) driving Python/PIL for the art**, not a Finder-AppleScript pipeline. Rationale: `dmgbuild` never touches Finder or `.DS_Store` races, needs no Automation/TCC permission grant, is 100% scriptable from a CI runner with no GUI session, and this machine already has Pillow. This is the dependency-light, CI-safe choice given `create-dmg` and ImageMagick aren't installed and you don't want to hand-roll AppleScript reliability problems (§2, §3). Full recipe below.

5. **Skip Sparkle for now.** WriteBetter is a small utility distributed as a manual DMG download; Sparkle's value (background auto-update) doesn't pay for its cost (EdDSA key management, appcast hosting, extra entitlements, extra attack surface) until there's a real user base and a release cadence to automate. Revisit once (a) notarization is working and (b) there's more than one download channel to keep in sync. In the meantime, a simple "check GitHub Releases" link is enough (§6).

6. **Once notarized, submit a Homebrew Cask.** It is free distribution, install/upgrade/uninstall is one `brew` command, and — notably — Homebrew's own acceptance docs do **not** require code signing/notarization for a cask to be merged (§6), but you should still ship a properly signed+notarized `.app` because `brew install --cask` inherits the same Gatekeeper checks as a manual download; an unsigned cask just means users hit the same "damaged" dialog `brew` can't fix for them.

---

## 1. What a production-grade macOS DMG looks like today

The near-universal convention for a single-app utility (which is WriteBetter's category) is: **a plain drag-to-Applications DMG** — app icon on the left, arrow, `/Applications` alias on the right, branded background, custom volume icon, no visible toolbar/sidebar/status bar, auto-opens in a Finder window sized to the artwork. This is what Rectangle, CleanShot X, Raycast, VLC, and IINA all ship. Rectangle in particular publishes exactly this pattern and is also distributed via `brew install --cask rectangle`. [rectangleapp.com](https://rectangleapp.com), [github.com/Shaunmak1214/Rectangle](https://github.com/Shaunmak1214/Rectangle)

Heavier products diverge:
- **Docker Desktop** ships *both* a `.dmg` (drag-to-Applications, in-app auto-update works) and a **`.pkg`** for MDM/fleet deployment (in-app updates are deliberately disabled when installed via pkg, so IT can pin versions). The pkg path exists specifically because Docker needs a privileged helper installed at a fixed system path — a plain drag-in-DMG can't do that. [docs.docker.com](https://docs.docker.com/desktop/setup/install/mac-install/)
- Apps that need a **privileged component** (kernel extension, system extension, launch daemon, VPN/network extension) generally need `.pkg` + `installer`, because only a `.pkg` can run a signed, notarized `postinstall` script with elevated rights in a way Gatekeeper is happy with. WriteBetter (menu-bar app, Accessibility + network client, no privileged helper) does **not** need this — plain DMG is correct and matches its peer set.
- Browsers/large suites (Arc, historically) and chat apps (Slack) commonly ship via **Squirrel-style self-updating installers** bundled as a `.zip`/`.dmg` that self-installs into `~/Applications` or `/Applications` with a lightweight in-app updater — overkill for a single-binary menu-bar utility.

**Why a shell-script "installer app" inside a DMG is bad practice.** This is precisely the technique real macOS malware uses: Gatekeeper's code-signature/notarization checks apply to Mach-O executables and script interpreters differently, and campaigns like **Shlayer** shipped a DMG whose visible "Install" icon was a shell/AppleScript wrapper that, once double-clicked (an action Gatekeeper treats as "user launched it, therefore consented"), downloaded and executed a second-stage payload with checks bypassed. Security researchers explicitly flag "double-clicking the install icon executes the script and bypasses Gatekeeper" as the mechanism. Even when your own script is benign, (a) it is *unsigned* by definition — a shell script has no code signature to check — so Gatekeeper either blocks it outright on a hardened system or trains your users to click through a scary warning for what looks like exactly the malware pattern; (b) it damages user trust ("why does this app need a script to install itself?"); (c) it can't be notarized as a unit the way an app bundle can. The fix is always the same: **just be a plain file the user drags**, or a **signed, notarized `.pkg`** if you truly need installer logic. [bleepingcomputer.com — Shlayer](https://www.bleepingcomputer.com/news/security/shlayer-malware-disables-macos-gatekeeper-to-run-unsigned-payloads/), [jamf.com — Shlayer](https://www.jamf.com/blog/shlayer-malware-abusing-gatekeeper-bypass-on-macos/), [cedowens.medium.com — Gatekeeper Bypass 2021](https://cedowens.medium.com/macos-gatekeeper-bypass-2021-edition-5256a2955508)

---

## 2. Tooling comparison

| Tool | Install | Invocation | Pros | Cons | CI/unattended? |
|---|---|---|---|---|---|
| **sindresorhus/create-dmg** (npm) | `npm install --global create-dmg` (Node ≥20) | `create-dmg MyApp.app [dest]` | Zero-config, "opinionated and simple," attempts codesign automatically, generates a DMG icon from the app icon, detects a `license.txt`/`.rtf` and adds a license panel | **Fixed, non-customizable layout** — no background art, no custom window size/icon position; author intentionally omitted config. Does not notarize (you must staple yourself). Requires Node 20+, macOS ≥10.13 output. Not currently installed on this machine. | Yes — no Finder GUI dependency documented; straightforward in CI once Node is present. |
| **create-dmg/create-dmg** (shell, different project, historically forked from `andreyvit/create-dmg`) | `brew install create-dmg`, or `make install` from source, or run in place | `create-dmg --volname ... --window-size W H --icon-size N --icon App.app X Y --app-drop-link X Y --background bg.png out.dmg src/` | Full control over window size/position, icon size/position, background, volume icon, hide-extension, `--eula`; has `--codesign` and `--notarize` flags built in | Internally still drives **hdiutil + AppleScript + `bless`/`SetFile`**, so it inherits every Finder-scripting flakiness gotcha in §3 (`Resource busy` on detach is a recurring open issue). Needs `--skip-jenkins`/`--sandbox-safe` flags to behave in CI, and even then layout can silently fail (missing background/wrong icon positions reported by users). | Partially — ships explicit CI flags, but multiple open GitHub issues (`create-dmg/create-dmg#143`, `#115`) show `hdiutil` race conditions surface intermittently even with those flags. |
| **dmgbuild** (PyPI, `al45tair/dmgbuild`) | `pip3 install dmgbuild` (not yet installed on this machine; Pillow *is* already present) | Python `settings.py` file + `dmgbuild -s settings.py "Volume Name" out.dmg`, or import and call as a library | **Does not use Finder or AppleScript at all** — writes the `.DS_Store` and alias records directly via the bundled `ds_store`/`mac_alias` Python modules. Fully deterministic, fully scriptable, safe in a headless SSH/CI session, no TCC/Automation permission prompt possible because Finder is never invoked. Supports background image, window rect, icon size, icon locations, badge icon, license, symlinks. | Python-only tooling; requires learning its settings-file schema; less "famous" than create-dmg so fewer blog examples. | **Yes, cleanly** — this is the one option explicitly designed to work without a GUI session. |
| **appdmg / node-appdmg** (npm, `LinusU/node-appdmg`) | `npm i -g appdmg` | JSON spec file → `appdmg spec.json out.dmg` | JSON-driven, supports `@2x` background auto-detection, contents array for icon positions and Applications symlink | **macOS-only, and internally also shells out to hdiutil/Finder-adjacent native code** — same `hdiutil: couldn't unmount ... Resource busy` failure class reported in its issue tracker (`node-appdmg#161`). Project is in relatively low-maintenance mode. | Mostly, with the same intermittent unmount races as the shell-based tools. |
| **Raw `hdiutil` + AppleScript** | none (stock macOS) | See §3 | No dependencies at all; total control | Most fragile of all options: Finder is "busy doing other things," scripting it is explicitly documented as flaky (missing background / wrong icon size / stale `.DS_Store` are common failure modes), and **requires driving Finder via `osascript`, which needs Automation/TCC consent** the first time — a prompt that cannot be granted non-interactively over SSH/CI. | Works interactively; unreliable/blocked headlessly unless Automation permission was pre-granted in a GUI session. |

**Recommendation given this machine's constraints:** `dmgbuild`. It is the only option in the table that is simultaneously (a) not already-missing-and-annoying to install (`pip3 install dmgbuild` is one line, and the hard dependency — Pillow — is already there), (b) fully scriptable without Finder/AppleScript, and (c) unaffected by the `hdiutil detach: Resource busy` class of bugs that every Finder-driving tool in this table has an open issue for.

Sources: [github.com/create-dmg/create-dmg](https://github.com/create-dmg/create-dmg), [github.com/sindresorhus/create-dmg](https://github.com/sindresorhus/create-dmg), [dmgbuild.readthedocs.io](https://dmgbuild.readthedocs.io/en/latest/), [github.com/dmgbuild/dmgbuild](https://github.com/dmgbuild/dmgbuild), [github.com/LinusU/node-appdmg](https://github.com/LinusU/node-appdmg), [github.com/sindresorhus/create-dmg/issues/46](https://github.com/sindresorhus/create-dmg/issues/46), [github.com/create-dmg/create-dmg/issues/143](https://github.com/create-dmg/create-dmg/issues/143), [github.com/create-dmg/create-dmg/issues/115](https://github.com/create-dmg/create-dmg/issues/115), [github.com/LinusU/node-appdmg/issues/161](https://github.com/LinusU/node-appdmg/issues/161)

---

## 3. The raw recipe, in full (for reference / if you ever need dependency-free)

This is the classic hdiutil+AppleScript pipeline, reconstructed from the `create-dmg/create-dmg` source and corroborating write-ups. **We recommend `dmgbuild` over this (§2, §4-recipe below) specifically to avoid the gotchas listed after the recipe** — but it's included because the brief asked for it and because it's useful for debugging what `dmgbuild`/`create-dmg` are doing under the hood.

```bash
#!/bin/bash
set -euo pipefail

APP="WriteBetter.app"
VOLNAME="WriteBetter"
STAGE="dmg-stage"
DMG_TMP="pack.dmg"
DMG_FINAL="WriteBetter.dmg"
WINX=200 WINY=120 WINW=660 WINH=400
ICON_SIZE=128

rm -rf "$STAGE"; mkdir -p "$STAGE/.background"
cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"
cp background.tiff "$STAGE/.background/background.tiff"   # see §7 for @2x tiff creation
cp VolumeIcon.icns "$STAGE/.VolumeIcon.icns"

# 1. Build a read-write image sized to fit contents
hdiutil create -srcfolder "$STAGE" -volname "$VOLNAME" -fs HFS+ \
  -fsargs "-c c=64,a=16,e=16" -format UDRW -ov "$DMG_TMP"

# 2. Mount it WITHOUT -nobrowse (Finder needs to see it to script it)
MOUNT_DIR="/Volumes/$VOLNAME"
hdiutil attach "$DMG_TMP" -readwrite -noverify -noautoopen

# 3. Mark the volume icon as "custom icon" and hide dotfiles
SetFile -c icnC "$MOUNT_DIR/.VolumeIcon.icns"
SetFile -a C "$MOUNT_DIR"          # sets the "custom icon" bit on the volume itself

# 4. Drive Finder via AppleScript: window bounds, icon size/positions, hide toolbar
osascript <<EOF
tell application "Finder"
  tell disk "$VOLNAME"
    open
    set current view of container window to icon view
    set toolbar visible of container window to false
    set statusbar visible of container window to false
    set the bounds of container window to {$WINX, $WINY, $WINX+$WINW, $WINY+$WINH}
    set theViewOptions to the icon view options of container window
    set arrangement of theViewOptions to not arranged
    set icon size of theViewOptions to $ICON_SIZE
    set background picture of theViewOptions to file ".background:background.tiff"
    set position of item "$APP" of container window to {180, 190}
    set position of item "Applications" of container window to {480, 190}
    close
    open
    update without registering applications
    delay 2
  end tell
end tell
EOF

# 5. Force .DS_Store to flush to disk before detaching
sync

# 6. Detach — retry, because hdiutil races Finder for the mount
for i in 1 2 3 4 5; do
  hdiutil detach "$MOUNT_DIR" && break
  sleep 2
done

# 7. Convert to compressed, read-only, distributable format
hdiutil convert "$DMG_TMP" -format UDZO -imagekey zlib-level=9 -o "$DMG_FINAL"
rm -f "$DMG_TMP"
```

### Exact gotchas

- **`.DS_Store` persistence / silent failure.** Finder writes window-layout state to `.DS_Store` lazily and asynchronously. If you `hdiutil detach` before Finder has flushed it, you ship a DMG with no background, default icon size, or icons piled in the top-left corner. The community-standard workaround is `update without registering applications` + a `delay` of 1–2s inside the AppleScript, plus retry-wrapping the detach itself. There is no fully reliable synchronous "flush now" API. [medium.com/@itsuki.enjoy](https://medium.com/@itsuki.enjoy/macos-create-a-little-cooler-dmg-38b91619e6ce)
- **`hdiutil detach` race conditions ("Resource busy").** Finder (or Spotlight indexing, or a lingering QuickLook thumbnail process) can still hold the mount open a moment after your AppleScript's `close` returns. This is a well-known, still-open class of flakiness — see the open issues cited in §2 — and the standard mitigation is a retry loop (`for i in 1..5; hdiutil detach ... && break; sleep 2; done`), falling back to `diskutil eject` if `hdiutil detach` keeps failing. [github.com/create-dmg/create-dmg/issues/143](https://github.com/create-dmg/create-dmg/issues/143), [copyprogramming.com — resource busy 2026 guide](https://copyprogramming.com/howto/can-t-unmount-dmg-keep-getting-resource-busy)
- **Finder Automation permission (TCC) in non-interactive shells.** The first time any process sends Apple Events to Finder (`osascript ... tell application "Finder"`), macOS must show a one-time consent dialog ("Terminal wants access to control Finder"), recorded in **System Settings → Privacy & Security → Automation**. Over SSH, in a LaunchAgent, or in a CI runner with no logged-in GUI session, **that dialog cannot be answered**, and the call fails with error **`-1743` "Not authorized to send Apple events to Finder"**. There is no way to pre-authorize this non-interactively short of granting it once in an interactive session first (or shipping a signed helper binary with `NSAppleEventsUsageDescription` in its `Info.plist` and the `com.apple.security.automation.apple-events` entitlement, which is itself only relevant if *your own app* is sandboxed and needs to script other apps — not applicable to a build script). This is the core reason `dmgbuild` (§2) is the safer default for CI. [developer.apple.com/forums/thread/677087](https://developer.apple.com/forums/thread/677087), [scriptingosx.com — Avoiding AppleScript Security Requests](https://scriptingosx.com/2020/09/avoiding-applescript-security-and-privacy-requests/)
- **Retina backgrounds via `@2x` in a `.tiff`.** Finder's icon-view background renderer looks for a single multi-representation TIFF, not two separate PNGs. Build it with the stock `tiffutil` (present on this machine at `/usr/bin/tiffutil`):
  ```bash
  tiffutil -cathidpicheck background.png background@2x.png -out background.tiff
  ```
  `-cathidpicheck` also validates that the `@2x` file is exactly double the pixel dimensions of the 1x file and will warn if it isn't. [manpagez.com/man/1/tiffutil](https://www.manpagez.com/man/1/tiffutil/), [developer.apple.com — Optimizing for High Resolution](https://developer.apple.com/library/archive/documentation/GraphicsAnimation/Conceptual/HighResolutionOSX/Optimizing/Optimizing.html)
- **`SetFile -a C` / `.VolumeIcon.icns`.** A custom volume icon requires two things together: the icon file saved as `.VolumeIcon.icns` at the volume root, its resource fork tagged via `SetFile -c icnC .VolumeIcon.icns`, **and** the volume's "has custom icon" Finder flag set via `SetFile -a C /Volumes/VolName`. Skipping either half silently gives you the generic disk icon.
- **`hdiutil attach -nobrowse` breaks Finder scripting.** `-nobrowse` explicitly tells Finder *not* to mount/display the volume in a window — it exists for headless/background mounts (e.g., installers reading files off a DMG without disturbing the user's Finder). If you pass it, `tell application "Finder" to tell disk "VolName"` has nothing to address, and every subsequent AppleScript command either errors or silently no-ops. Always mount **without** `-nobrowse` when you intend to AppleScript the layout, and only add `-nobrowse` for purely programmatic mounts (e.g., reading files back out for verification).
- **Convert format choices.** `UDZO` (zlib) is the standard "compressed, read-only" distribution format and what nearly every app ships. `UDBZ` (bzip2) compresses tighter but is markedly slower to build and to mount, rarely worth it for an app this size. `ULFO` (LZFSE) is faster to decompress and a reasonable modern alternative to UDZO if minimum macOS version isn't a concern (LZFSE needs a relatively recent macOS to mount) — for broad compatibility, stick with `UDZO -imagekey zlib-level=9`.

---

## 4. Signing and notarization end to end (2026)

### Signing order and flags

**Do not use `codesign --deep` to sign.** Apple's own TN2206 says explicitly: *"While the `--deep` option can be applied to a signing operation, this is not recommended... Signing with `--deep` is for emergency repairs and temporary adjustments only."* The correct approach — and what Xcode itself does — is to **sign inside-out**: sign any embedded frameworks/XPC services/helper `.app`s first, copy them into the outer bundle, then sign the outer bundle last. `--deep` is fine for *verification* (`codesign --verify --deep --strict --verbose=2`) since that's read-only. [developer.apple.com/library/archive/technotes/tn2206](https://developer.apple.com/library/archive/technotes/tn2206/_index.html), [github.com/beeware/briefcase/issues/1221](https://github.com/beeware/briefcase/issues/1221)

```bash
IDENTITY="Developer ID Application: Your Name (TEAMID)"
ENTITLEMENTS="WriteBetter/WriteBetter.entitlements"

# 1. Sign any embedded frameworks/plugins first (WriteBetter appears to have none,
#    but if it ever embeds e.g. Sparkle.framework, sign it here first)
find "WriteBetter.app/Contents/Frameworks" -name "*.framework" -maxdepth 1 2>/dev/null | while read -r fw; do
  codesign --force --options runtime --timestamp --sign "$IDENTITY" "$fw"
done

# 2. Sign the main bundle last, with hardened runtime + secure timestamp
codesign --force --options runtime --timestamp \
  --entitlements "$ENTITLEMENTS" \
  --sign "$IDENTITY" \
  "WriteBetter.app"

# 3. Verify
codesign --verify --deep --strict --verbose=2 "WriteBetter.app"
spctl -a -vvv -t exec "WriteBetter.app"      # NOT "-t install" — that's for .pkg, not .app
```

`--options runtime` = **hardened runtime**, mandatory for notarization regardless of whether the app is sandboxed. `--timestamp` embeds a **secure/trusted timestamp** from Apple's timestamp server so the signature remains valid after the certificate itself expires — also required for notarization to accept the binary. [developer.apple.com/documentation/security/hardened-runtime](https://developer.apple.com/documentation/security/hardened-runtime), [developer.apple.com/documentation/xcode/configuring-the-hardened-runtime](https://developer.apple.com/documentation/xcode/configuring-the-hardened-runtime)

### Entitlements for a non-sandboxed menu-bar app

Because WriteBetter is **not sandboxed** (a plain Developer-ID-distributed app, not from the Mac App Store), it does **not** need App Sandbox entitlements like `com.apple.security.network.client` — those only govern what a *sandboxed* process may do; a non-sandboxed hardened-runtime app can already make network calls and read the Accessibility API by default. Confirmed by community guidance: *"Apps that aren't sandboxed, only hardened and notarized, will only have entitlements if they need to access privacy-protected features, or use restricted features."* For WriteBetter specifically:
- **Accessibility** (used by `HotkeyManager`/`TextExtractor` to read/replace text in other apps) is a **TCC permission**, not a code-signing entitlement — it's requested at runtime and the user approves it once in System Settings → Privacy & Security → Accessibility. No entitlement is required to *ask* for it as a non-sandboxed app.
- **Network calls** to your AI backend need no entitlement outside the sandbox.
- The six **hardened-runtime opt-out entitlements** (`allow-jit`, `allow-unsigned-executable-memory`, `allow-dyld-environment-variables`, `disable-library-validation`, `disable-executable-page-protection`, `cs.debugger`) exist to *loosen* hardened-runtime restrictions for apps that need them (e.g., JIT compilers, plugin hosts loading third-party code). **WriteBetter needs none of these** unless it dynamically loads unsigned code, which it doesn't appear to. Keep the entitlements file minimal/empty rather than copy-pasting a boilerplate list. [eclecticlight.co — Notarization: the hardened runtime](https://eclecticlight.co/2021/01/07/notarization-the-hardened-runtime/), [eclecticlight.co — What are app entitlements](https://eclecticlight.co/2025/03/24/what-are-app-entitlements-and-what-do-they-do/)

### Notarization with `notarytool`

```bash
# One-time: store an App Store Connect API key as a reusable keychain profile
xcrun notarytool store-credentials "WriteBetterNotary" \
  --key "/path/to/AuthKey_XXXXXXXXXX.p8" \
  --key-id "XXXXXXXXXX" \
  --issuer "YOUR-ISSUER-UUID"

# Zip (or use the .dmg directly) and submit, waiting synchronously for the result
ditto -c -k --keepParent "WriteBetter.app" "WriteBetter.zip"
xcrun notarytool submit "WriteBetter.zip" --keychain-profile "WriteBetterNotary" --wait

# Staple the ticket so Gatekeeper can verify offline (staple the .app, then re-build
# the DMG around the stapled .app, then ALSO staple the .dmg itself)
xcrun stapler staple "WriteBetter.app"
# ... build the dmg from the stapled .app (§ recipe) ...
xcrun stapler staple "WriteBetter.dmg"

# Verify end to end
spctl -a -vvv -t exec WriteBetter.app
spctl -a -vvv -t open --context context:primary-signature WriteBetter.dmg
```

The App Store Connect **API key** method (`--key`/`--key-id`/`--issuer`) is the current recommended auth path — it's what Apple's own docs and every current guide use — versus the legacy Apple ID + app-specific-password method, which still works but is considered the older/less preferred flow. `notarytool` has fully replaced `altool` for notarization (`altool` submission for notarization was sunset in late 2023). Both the `.app` (recommended, so it's valid however it's later repackaged — zip, dmg, pkg) and the `.dmg` should be stapled if you're distributing the DMG directly, since `spctl` on the mounted volume checks the outer container too. [Apple's official notarization doc exists at developer.apple.com/documentation/security/notarizing-macos-software-before-distribution — **could not fetch full body text (two attempts returned only the page title / a truncation notice); the command sequence above is corroborated by multiple independent secondary sources (Scripting OS X, Reverse Society blog, GuillaumeFalourd/notary-tools) and is consistent with Apple's stated flow, but flagging that I could not directly quote Apple's own page text.] [scriptingosx.com — Notarize a Command Line Tool with notarytool](https://scriptingosx.com/2021/07/notarize-a-command-line-tool-with-notarytool/), [tonygo.tech — Complete Guide to Notarizing macOS Apps](https://tonygo.tech/blog/2023/notarization-for-macos-app-with-notarytool)

`spctl -a -t install` is for `.pkg` installer packages, not `.app` bundles — use `-t exec` for an app and `-t open` for a mounted disk image / downloaded file, per direct testing reported by developers on Apple's forums. [developer.apple.com/forums/thread/728267](https://developer.apple.com/forums/thread/728267)

### What actually changed in macOS 15 Sequoia (confirmed, Apple's own words) and macOS 26 Tahoe (same behavior, confirmed)

Apple's own developer-news post (dated **August 6, 2024**, still the operative behavior through Sequoia and into Tahoe/macOS 26 per current 2026 secondary coverage) states the change plainly: *"In macOS Sequoia, users will no longer be able to Control-click to override Gatekeeper when opening software that isn't signed correctly or notarized,"* and recommends: *"If you distribute software outside of the Mac App Store, we recommend that you submit your software to be notarized."* [developer.apple.com/news/?id=saqachfa](https://developer.apple.com/news/?id=saqachfa)

Concretely, this means:
- **The old "right-click → Open → confirm Open" one-shot bypass is gone** for apps that aren't from an identified/notarized developer. It still exists for *signed-and-notarized* apps as a lighter first-launch confirmation, but it no longer functions as a Gatekeeper override for unsigned/ad-hoc apps.
- Opening a non-notarized app (unsigned or ad-hoc-signed — either way it's not "from an identified developer") now typically surfaces **"[App] is damaged and can't be opened. You should move it to the Trash"** — a genuinely misleading message, since the file usually isn't corrupted at all; it's the quarantine flag + failed Gatekeeper assessment being reported this way. [swissmacuser.ch](https://swissmacuser.ch/fix-macos-tahoe-app-is-damaged-and-cant-be-opened-move-trash/)
- The user must go to **System Settings → Privacy & Security**, scroll to the Security section at the bottom, click **"Open Anyway"** next to the blocked app, then confirm again and authenticate with an admin password. This only has to be done once per app version. [idownloadblog.com](https://www.idownloadblog.com/2024/08/07/apple-macos-sequoia-gatekeeper-change-install-unsigned-apps-mac/), [macrumors.com](https://www.macrumors.com/2024/08/06/macos-sequoia-gatekeeper-security-change/)
- Two **Terminal-based workarounds still function as of 2026** (verified independently by multiple 2026 sources) but are explicitly discouraged by security writers as they disable a real protection layer, not just a UX inconvenience:
  - `xattr -r -d com.apple.quarantine /path/to/App.app` — strips the quarantine attribute Gatekeeper keys off of, so the app is treated as already-approved. Still works technically, but eclecticlight.co calls it "a potentially dangerous workaround" since it also disables the malware-scan step quarantine triggers, not just the "who signed this" check. [eclecticlight.co — Living without notarization](https://eclecticlight.co/2024/10/01/living-without-notarization/)
  - `sudo spctl --master-disable` — restores the old "Anywhere" option in System Settings → Privacy & Security → "Allow applications from," which Apple hid from the GUI starting with Catalina but which this command still re-exposes as of Tahoe per current how-to coverage. This is a **system-wide** Gatekeeper downgrade, not per-app, and is a much bigger ask of a user than either "Open Anyway" or `xattr`. [swissmacuser.ch](https://swissmacuser.ch/fix-macos-tahoe-app-is-damaged-and-cant-be-opened-move-trash/)
- **Verified: macOS 26 Tahoe behaves the same as Sequoia here** — multiple 2026 sources describe the identical "System Settings → Privacy & Security → Open Anyway" flow for both OS versions, with no further tightening found in this research beyond what shipped in Sequoia 15.1. I could not find an Apple changelog entry specific to macOS 26 that alters Gatekeeper further; flagging this as based on consistent secondary-source reporting rather than a primary Apple release-note citation for macOS 26 specifically.

**Bottom line for our fallback (ad-hoc, unnotarized) case:** the honest instruction to ship is *"macOS will say WriteBetter is damaged — open System Settings → Privacy & Security, scroll to the bottom, click Open Anyway next to WriteBetter, then click Open Anyway again to confirm."* Do **not** tell users to run `xattr -dr com.apple.quarantine` as a first-line instruction — it works, but it's the kind of shell-command-off-a-webpage that security tooling (and cautious users) rightly treat as a red flag, exactly the trust problem in §1.

---

## 5. Recommended build-script design (graceful degradation)

```bash
#!/bin/bash
set -euo pipefail

IDENTITY=$(security find-identity -v -p codesigning 2>/dev/null \
  | grep "Developer ID Application" | head -1 | sed -E 's/.*"(.+)"/\1/' || true)

if [[ -n "$IDENTITY" ]]; then
  echo "==> Developer ID found: $IDENTITY — will sign, notarize, staple."
  MODE="full"
else
  echo "==> No Developer ID Application identity installed."
  echo "    Falling back to ad-hoc signing. The shipped app will NOT pass"
  echo "    Gatekeeper cleanly; README will carry explicit Open-Anyway instructions."
  MODE="adhoc"
fi

# ... build .app with xcodebuild as today ...

if [[ "$MODE" == "full" ]]; then
  codesign --force --options runtime --timestamp --entitlements WriteBetter.entitlements \
    --sign "$IDENTITY" "$APP_PATH"
  ditto -c -k --keepParent "$APP_PATH" notarize.zip
  xcrun notarytool submit notarize.zip --keychain-profile "WriteBetterNotary" --wait
  xcrun stapler staple "$APP_PATH"
else
  codesign --force --options runtime --sign - "$APP_PATH"   # ad-hoc, no identity
fi

# ... build DMG with dmgbuild (§ below), always sign the DMG container too if MODE=full ...

if [[ "$MODE" == "full" ]]; then
  codesign --force --sign "$IDENTITY" "$DMG_FINAL"
  xcrun stapler staple "$DMG_FINAL"
  README_NOTE="WriteBetter is signed and notarized by Apple. Just drag it to Applications and open it — no warnings."
else
  README_NOTE="This build is NOT notarized (no Apple Developer account configured on the build machine).
macOS will show 'WriteBetter is damaged and can't be opened.' This is expected, not real corruption.
Fix: System Settings > Privacy & Security > scroll to Security > click 'Open Anyway' next to WriteBetter,
then click 'Open Anyway' again to confirm. You only need to do this once."
fi

echo "$README_NOTE" > "$DMG_STAGE/README.txt"
```

This mirrors the pattern strongly implied by Apple's own recommendation ("if you distribute outside the App Store, we recommend notarizing") while not pretending the fallback path is fine — the DMG and its README should say, in plain language, which of the two states the download is in, and give the *exact* remaining steps for that state rather than generic boilerplate.

---

## 6. Sparkle / auto-update, and Homebrew Cask

**Sparkle.** Free/open-source, the de facto standard for macOS auto-update outside the App Store (used by huge swaths of the indie/pro-app ecosystem). Costs to actually run it:
- Generate an **EdDSA keypair** once via Sparkle's `./bin/generate_keys` — private key lives in your login Keychain, never on the distribution server; every release must be signed with `generate_appcast`, which needs Keychain access to that key. This means your release pipeline needs to run somewhere that can reach that private key (or you accept doing signing locally by hand each release). [sparkle-project.org/documentation](https://sparkle-project.org/documentation/), [sparkle-project.org/documentation/publishing](https://sparkle-project.org/documentation/publishing/)
- Needs an **appcast** (an RSS-like XML feed) hosted somewhere reachable by the app (`SUFeedURL` in `Info.plist`). GitHub Pages / GitHub Releases is a free, common hosting choice, but it's still one more moving part to keep in sync with every release. [hobbyworker.me — Sparkle signing key](https://hobbyworker.me/en/dev/2026-05-15-distribute-macos-app-2-sparkle-signing-key/)
- Requires the app to embed `Sparkle.framework`, which then itself needs to be code-signed inside-out as part of your bundle (another nested-code signing step, see TN2206 guidance in §4).

**Recommendation: skip it for now.** For a single-maintainer utility with an occasional manual DMG release, Sparkle's ongoing cost (key custody, appcast maintenance, extra signed framework, extra thing that can silently break and leave users on a stale build with no error) outweighs the benefit versus just posting new DMGs to GitHub Releases and pointing users there. Revisit once there's a real release cadence and either (a) a CI pipeline that can hold the Sparkle private key safely, or (b) enough users that manual re-downloads become a real support cost.

**Homebrew Cask as the practical alternative.** `brew install --cask writebetter` gives users install/upgrade/uninstall for free without any auto-update code in your app at all — Homebrew itself polls for new versions via its normal `brew upgrade` cadence. Concretely, to submit:
- Read `Cask Cookbook` for the token/stanza rules (a cask is a short Ruby DSL block: `url`, `version`, `sha256`, `app "WriteBetter.app"`, plus `uninstall`/`zap` stanzas as needed).
- The download must come from **a URL the developer publishes or explicitly endorses** (GitHub Releases works fine) — not a mirror, not behind a login wall, not a forum post link.
- Test locally: `HOMEBREW_NO_INSTALL_FROM_API=1 brew install --cask writebetter && brew uninstall --cask writebetter && brew audit --new --cask writebetter && brew style --fix --cask writebetter`.
- Homebrew's **Acceptable Casks** doc does *not* mandate code signing or notarization as a merge requirement — but it does say a cask "must not require System Integrity Protection or Gatekeeper to be disabled or bypassed," which in practice means shipping an unsigned/ad-hoc app to Homebrew still leaves your users hitting the exact "damaged" dialog from §4; `brew` doesn't route around Gatekeeper for you. So notarization is still the practical prerequisite even though it isn't a literal submission-checklist item. [docs.brew.sh/Acceptable-Casks](https://docs.brew.sh/Acceptable-Casks), [docs.brew.sh/Adding-Software-to-Homebrew](https://docs.brew.sh/Adding-Software-to-Homebrew), [github.com/Homebrew/homebrew-cask/CONTRIBUTING.md](https://github.com/Homebrew/homebrew-cask/blob/main/CONTRIBUTING.md)

---

## 7. DMG background art conventions (for the Python/PIL generation step)

- **Canonical window size:** roughly **660×400 pt** to **540×380 pt** depending on how much branding you want visible; 660×400 is the more common modern default and leaves comfortable margins around a 128px icon size. [github.com/qaid/look-ma-no-hands#295](https://github.com/qaid/look-ma-no-hands/issues/295) corroborates this window-size range as what a real branded-DMG implementation used.
- **Background image dimensions:** design at **1x = window size** (e.g. 660×400 px) and export a **@2x = exactly double** (1320×800 px) for Retina — Finder auto-selects the right one from a combined TIFF (built via `tiffutil -cathidpicheck`, §3) based on the display. The `-cathidpicheck` flag itself enforces the "exactly double" relationship and warns if you get it wrong.
- **Icon placement:** app icon and the `/Applications` alias sit at the **same vertical y-coordinate** (visually centered in the window, roughly window-height/2), horizontally split with generous margin from the edges — typical values are roughly **x≈170–200** for the app and **x≈480–490** for Applications in a 660-wide window, i.e., a gap of ~300px between them so the eye reads "drag from here to there." Never draw the icons themselves into the background PNG — Finder overlays the *real* file/alias icons on top at those coordinates, so a background with icons baked in either doubles up or shows through misaligned. [github.com/qaid/look-ma-no-hands#295](https://github.com/qaid/look-ma-no-hands/issues/295)
- **Safe margins / what to actually draw into the background:** an arrow (or chevron) between the two icon slots is the single most common "premium" visual cue (Rectangle, CleanShot X, and most Sketch/Figma-style installer backgrounds use it) — it silently communicates the drag gesture without needing on-image instructional text, which ages badly if you ever change layout. Keep a **~40–60px margin** from all four window edges free of any content so the icon labels ("WriteBetter", "Applications") aren't visually cramped against the frame; icon label text is rendered by Finder itself below each icon, not part of the background.
- **What separates premium from amateur:** consistent brand color/typography with the app's actual icon and marketing site (not a generic gradient), a background **DPI normalized correctly** (PIL: `img.save(path, dpi=(144,144))` for the @2x variant so the embedded resolution metadata matches what Finder expects — mismatched DPI metadata is a common cause of a background rendering at the wrong physical size even though pixel dimensions are correct), a custom **volume icon** (not the generic hard-disk icon), hidden toolbar/sidebar/status bar (a raw Finder chrome around your art reads as unfinished), and icon size large enough (100–128px) to look intentional rather than the Finder default.
- **PIL/CoreGraphics constraint to note:** Pillow can produce the PNG art at both resolutions and set DPI metadata directly (`Image.new(...)`, draw with `ImageDraw`, `save(..., dpi=(144,144))`), but **cannot itself produce the final multi-resolution `.tiff`** Finder consumes for a background — that combination step still needs the stock `tiffutil -cathidpicheck` binary (present on this machine) run as a subprocess after PIL exports the two PNGs. Likewise, PIL can produce `.icns`-source PNGs at the required sizes (16/32/128/256/512, plus @2x variants) but the actual `.icns` container must be built with the stock `iconutil -c icns MyIcon.iconset` (also present) — there is no pure-Python path to a valid `.icns` without shelling out to `iconutil`. Both tools are confirmed present on this machine, so this is a non-issue here, just worth noting as a dependency the pure-PIL approach doesn't eliminate.

Sources: [github.com/qaid/look-ma-no-hands/issues/295](https://github.com/qaid/look-ma-no-hands/issues/295), [manpagez.com/man/1/tiffutil](https://www.manpagez.com/man/1/tiffutil/), [developer.apple.com — Optimizing for High Resolution](https://developer.apple.com/library/archive/documentation/GraphicsAnimation/Conceptual/HighResolutionOSX/Optimizing/Optimizing.html)

---

## Flags / things I could not fully verify

- Apple's own **Notarizing macOS Software Before Distribution** doc (`developer.apple.com/documentation/security/notarizing-macos-software-before-distribution`) would not return body text to WebFetch on two attempts (got only a title / truncation notice both times). The notarytool/staple/spctl workflow above is cross-corroborated by several independent secondary sources instead (Scripting OS X, Reverse Society, GuillaumeFalourd/notary-tools, Apple's own developer-news post which *does* link to that doc) and matches consistent, unchanged Apple guidance since notarytool's introduction in Xcode 13 (2021) — but I did not get to read Apple's primary-source text directly.
- I found **no evidence of a 2026-specific tightening** of notarization requirements beyond the Sequoia-15/Tahoe-26 Gatekeeper UX change already covered in §4 (removal of the Control-click override, "Open Anyway" flow). Searches for "2026 notarization changes" mostly returned unrelated results about legal/document notarization (a homograph collision with Apple's use of the term), so I can't rule out a change I simply didn't surface — but nothing in Apple's own developer-news feed or the security-blog corpus I checked (Eclectic Light Co., Scripting OS X, MacRumors, idownloadblog) suggested anything changed in the core signing/notarization mechanics since 2021–2024.
- The `hobbyworker.me` two-part DMG design series (cited in §7 for window-size/icon-position conventions) returned a 403 on direct fetch for part 2; the figures quoted come from the WebSearch result snippet, not a full read of the article — treat the specific pixel numbers as indicative/commonly-cited rather than a verified single authoritative source.
- I did not find a citable primary source giving Apple's **exact current price** for the Developer ID Application certificate beyond the well-established $99/year Apple Developer Program membership figure (consistent across multiple secondary sources); Apple's own enrollment page wasn't fetched directly in this research pass.
