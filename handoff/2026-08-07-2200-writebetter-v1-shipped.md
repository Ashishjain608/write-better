# WriteBetter v1.0.0 — shipped, unsigned, unproven against a live API

**Written:** 2026-08-07 22:00 IST · **Supersedes:** nothing (first handoff in this repo)

---

## TL;DR

v1.0.0 is committed (`0a5aac0`), built, installed at `/Applications/WriteBetter.app`, and a styled
DMG exists at `dist/`. The app went from a single-provider Anthropic clipboard tool to a three-provider
(Anthropic / OpenAI / Gemini) menu-bar app with Keychain-backed keys, a rebuilt UI, and a real
packaging pipeline. **Two things are unproven: no request has ever succeeded against a live API
through the app, and there is no Developer ID, so nobody else can install it without a scary dialog.**
Next step is 30 seconds of manual testing (below), then decide on the $99/yr Apple membership.

---

## Current state (verify before trusting)

Everything here came from a command run at handoff time. Re-run before relying on it.

| Thing | State | How to re-check |
|---|---|---|
| Branch / HEAD | `main` @ `0a5aac0` | `git log --oneline -2` |
| Working tree | Clean at commit time; `docs/` + this handoff added after | `git status --short` |
| Installed app | `/Applications/WriteBetter.app` v1.0.0, min macOS 14.0 | `plutil -p /Applications/WriteBetter.app/Contents/Info.plist` |
| Running | Yes, PID was 67888 | `pgrep -fl /Applications/WriteBetter.app` |
| DMG | `dist/WriteBetter-Installer.dmg`, 4.4 MB, ad-hoc signed | `ls -lh dist/` |
| Code signing | **0 valid identities on this Mac** | `security find-identity -v -p codesigning` |
| API keys | Anthropic only, in login keychain, service `com.aj.WriteBetter.apikeys` | `security find-generic-password -s com.aj.WriteBetter.apikeys` |
| Legacy key migration | Done — `didMigrateLegacyAnthropicKey = true`, UserDefaults entry deleted | `defaults read com.aj.WriteBetter` |

There is **no remote** on this repo and nothing is pushed or PR'd — `main` is the only branch and
the only place this exists.

---

## ⚠️ CONTINUE HERE

### 1. Prove it actually works (5 minutes, blocks everything else)

No API call has ever completed through the app. The wire shapes are asserted by 162 offline
self-checks and confirmed against provider docs, but never exercised end to end.

```bash
printf 'this sentance have some erors and it dont read very good' | pbcopy
# then press Cmd+Shift+Space
```

Expect: panel appears at the cursor, streams a corrected rewrite, `Enter` copies and closes.
If it fails, the error card names the cause (invalid key / offline / rate limit / quota) — that
taxonomy is the thing to trust; it is not a generic string.

**Anthropic is the only provider with a key.** OpenAI and Gemini paths are doc-confirmed but
completely unexercised — model IDs, auth header names, SSE delta shapes, and error JSON are all
unproven. To test: Settings → Providers → paste a key → **Test key** (hits each provider's models
endpoint, costs no tokens, proves auth only — not that the account has credit).

### 2. Blocking decision: Apple Developer Program ($99/yr)

This is the single thing standing between the current DMG and something shareable.

- **Without it (today):** macOS 15+ shows *"WriteBetter is damaged and can't be opened."* Apple
  removed the Control-click override in Sequoia, so the only sanctioned path is System Settings →
  Privacy & Security → Open Anyway. `create-dmg.sh` prints this honestly and the README documents it.
- **With it:** `./create-dmg.sh` already auto-detects a `Developer ID Application` identity and
  switches to sign → `xcrun notarytool submit --wait` → `stapler staple` (app *and* dmg) → verify.
  Both auth styles are wired (`--keychain-profile` and `--key/--key-id/--issuer`). **No code change
  needed** — this path is correct-by-construction but has never run.

Options: (a) buy the membership and run the signed path, (b) ship unsigned and accept the support
burden, (c) distribute via Homebrew Cask — note Homebrew does *not* route around Gatekeeper, so it
still needs (a) to be a good experience.

### 3. Known-imperfect, deliberately left

- **Tab order deviates from spec.** `docs/design-brief.md` §7.1 wants
  `provider chip → result canvas → quick actions → prompt → Replace → Copy → close`. The result canvas
  is now focusable (`Views/PanelCards.swift`, `ResultCanvas.body`, `.focusable()`), but the close
  button still lands 2nd instead of last because it's declared inside `header` in
  `Views/ImprovementView.swift:57-73`. The fix is to move `closeButton` out of the header `HStack`
  and render it as a `.overlay(alignment: .topTrailing)` on the root `VStack` so it's last in the
  view tree — **but** verifying tab order needs Full Keyboard Access + UI scripting, which is blocked
  without an Accessibility grant. Don't reshuffle blind; grant permission first, then verify.
- **No real Liquid Glass.** `.glassEffect` / `GlassEffectContainer` are genuinely **not in the
  MacOSX26.1 SDK** (verified by grepping the SwiftUI `.swiftinterface`). `Views/Surfaces.swift`
  `GlassSurface` approximates it with `NSVisualEffectView`, isolated to one type for a one-line swap
  later. The SDK *does* ship `GlassButtonStyle` / `GlassProminentButtonStyle` — unadopted, because
  stock glass buttons would clash with the custom control set.
- **Stale inert pref.** `NSWindow Frame SwiftUI.EmptyView-1-AppWindow-1` is still in
  `~/Library/Preferences/com.aj.WriteBetter.plist` — leftover from the old `WindowGroup { EmptyView() }`
  stray window. Nothing references it now; harmless.

---

## Source-of-truth docs (read, don't re-derive)

All three were produced by research agents this session and are now committed so the 87 `§`-references
in the Swift comments resolve:

- **`docs/design-brief.md`** (949 lines, 59 cited sources) — the authoritative UI spec. Palette with
  *computed* contrast ratios, type scale, spacing/radii, 22-row motion table, ASCII wireframes, all 11
  panel states, keyboard map, onboarding, accessibility checklist, and §11 "Implementation notes" with
  known SwiftUI/AppKit pitfalls **and their fixes**. Code comments cite it by section — `§7.1`,
  `§9.3`, `§11.2 pitfall 9`, `Appendix A`.
- **`docs/packaging-brief.md`** (309 lines) — DMG/signing/notarization research. Tooling comparison,
  the raw `hdiutil`+AppleScript recipe and its gotchas, exact macOS 15/26 Gatekeeper behavior, the
  graceful-degradation script design, Sparkle vs Homebrew Cask analysis.
- **`docs/architecture-contract.md`** (164 lines) — the P↔U API contract (`AIProvider`,
  `SettingsStore`, `AIServiceFactory`, `AIService`, `AIServiceError`) plus the file-ownership split
  used to parallelize the work. Still accurate; useful if you fan out agents again.
- **`README.md` / `SETUP.md`** — rewritten this session, accurate as of `0a5aac0`. README has the
  Releasing section with the signed-path checklist.
- **Commit `0a5aac0`** — its message is a detailed changelog; `git show --stat 0a5aac0`.

---

## Footguns discovered this session

1. **Opus 5 + `thinking:{"type":"disabled"}` leaks `<thinking>` tags into the visible answer.** The
   API accepts the parameter (at effort ≤ `high`), so there's no error — the tags just appear in
   output that goes straight to the clipboard. `Services/AnthropicService.swift` therefore sends
   `output_config.effort = "low"` for Opus 5 and reserves disabled-thinking for Sonnet 5 / Opus 4.8 /
   Sonnet 4.6. Haiku 4.5 gets neither (predates the param; `effort` would 400). **Always load the
   `claude-api` skill before touching model config — this was invisible to code review.**
2. **`max_tokens` caps thinking + text together.** Raised to 8192 in `Utils/Constants.swift` for
   exactly this reason. Lowering it will truncate Opus 5 answers mid-sentence.
3. **The old `INFOPLIST_KEY_NSHumanReadableCopyright[sdk=*] = WriteBetter/Info.plist`** was a botched
   `INFOPLIST_FILE` edit that set the copyright string to a *file path* and silently dropped every
   usage string from the bundle. If plist keys ever go missing again, check that setting first.
4. **`GENERATE_INFOPLIST_FILE` is now `NO`** with a real `INFOPLIST_FILE`. Adding a plist key via
   `INFOPLIST_KEY_*` build settings will now be **ignored** — edit `WriteBetter/Info.plist` directly.
5. **Never ship a shell script in an `.app` inside a DMG.** That's the Shlayer malware pattern; the
   old `Installer/` was deleted for this reason. Plain drag-to-Applications only.
6. **SourceKit reports phantom "cannot find type in scope" errors** while multiple files are being
   edited — it indexes files in isolation. Only `xcodebuild` output is trustworthy.

---

## Gates

```bash
# Build (both configs must be clean; zero warnings is the current baseline)
cd WriteBetter
xcodebuild -scheme WriteBetter -configuration Debug   build
xcodebuild -scheme WriteBetter -configuration Release build

# 162 offline self-checks: request shapes for all 3 providers, SSE parsing for all
# 3 wire formats (incl. keep-alives, split chunks, mid-stream errors), prompt construction
<DerivedData>/Build/Products/Debug/WriteBetter.app/Contents/MacOS/WriteBetter --self-check
# → "[WriteBetterSelfCheck] 162 checks passed." exit 0

# Full package; asserts DMG layout against the mounted .DS_Store rather than trusting the mount
./create-dmg.sh
./create-dmg.sh --app /path/to/WriteBetter.app   # skip compile, package only
```

Artwork is regenerable and deterministic: `scripts/make-icons.sh` (wraps `scripts/artwork.swift`,
which transcribes design-brief §2.2 into Core Graphics). Re-running produces byte-identical PNGs.

---

## Suggested next-session skills

- `/warmup` — then read this file.
- `claude-api` skill — **mandatory** before any model-config change (see footgun 1).
- `/ponytail-review` — the codebase grew ~9,800 lines in one session across 3 agents; worth a pass
  for over-engineering, especially `Views/` (10 new files) and `Managers/` (7 new files).
- `/security-review` — the app now handles three API keys, Keychain ACLs, synthetic keystrokes, and
  Accessibility permissions. None of that has had a security pass.
