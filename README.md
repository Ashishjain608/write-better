# WriteBetter

A menu-bar utility for macOS that rewrites whatever text you have on hand.
Copy something, press `⇧⌘Space`, and a floating panel shows a better version
— then you copy it or paste it straight back where it came from.

No Dock icon, no window to manage, no account. Your API key stays in your Mac's
Keychain and the text goes to the provider you chose and nowhere else.

---

## What it does

- **Seven providers.** Anthropic (Claude), OpenAI (GPT), Google Gemini, a custom
  OpenAI-compatible endpoint (Ollama, LM Studio, OpenRouter), Apple on-device
  (macOS 26 with Apple Intelligence), and your logged-in Claude Code (`claude`)
  or Codex (`codex`) CLI. Switch between them from the panel.
- **No API key needed for the CLIs.** Claude Code and Codex rewrites run through
  the CLI you already use and are billed to that subscription. The answer
  arrives in one piece, not streamed, and there is an effort picker (`low` by
  default).
- **Streaming.** With the API providers the first words appear while the rest is
  still being written. `esc` cancels the request for real, and you keep whatever
  arrived.
- **Quick actions.** Fix Grammar, Clarify, Shorten, Professional, Friendly —
  one click or `⌘1`…`⌘5`.
- **Saved actions.** Keep up to four of your own prompts on `⌘6`…`⌘9`. Manage
  them in Settings → Actions, or use "Save as action" from `⌘K`.
- **Free-form prompts.** `⌘K`, tell it what you actually want, `⌘↩`.
- **Clipboard-first capture.** By default WriteBetter reads your clipboard, so
  it needs no permissions at all: copy with `⌘C`, then hit the hotkey.
- **Optional Accessibility upgrade.** Grant Accessibility and two extra things
  become possible: capturing the current selection without you pressing `⌘C`,
  and *Replace in place* (`⌘↩`) which pastes the result back into the app you
  came from. Both are optional; the app is fully usable without them.

## Requirements

- macOS **14.0** (Sonoma) or later, Apple Silicon or Intel.
- An API key from at least one of
  [Anthropic](https://console.anthropic.com/settings/keys) ·
  [OpenAI](https://platform.openai.com/api-keys) ·
  [Google AI Studio](https://aistudio.google.com/apikey),
  **or** a custom endpoint, Apple on-device, or a logged-in `claude` or `codex`
  CLI. No API key is needed for those.

API keys are billed by the provider, per token. The CLI providers are billed to
your Claude Code or Codex subscription. WriteBetter has no server, no
account and no telemetry.

## Install

Download `WriteBetter.dmg` from
[Releases](https://github.com/Ashishjain608/write-better/releases), open it, and
drag **WriteBetter** to **Applications**. Or with Homebrew:

```bash
brew install --cask ashishjain608/tap/writebetter
```

Launch it. The caret icon appears in your menu bar. Click it → **Settings…** →
paste a key → **Test**. (For Claude Code or Codex, pick that provider instead;
no key is needed.) WriteBetter checks for updates itself.

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
git clone https://github.com/Ashishjain608/write-better.git
cd write-better
open WriteBetter/WriteBetter.xcodeproj      # then ⌘R
```

Or from the command line:

```bash
xcodebuild -project WriteBetter/WriteBetter.xcodeproj \
           -scheme WriteBetter -configuration Release \
           -derivedDataPath build/DerivedData build
```

Requirements: Xcode 26 or later. One dependency, Sparkle 2, which Xcode fetches
as a Swift package on first open.

The Xcode project uses a **file-system-synchronized group**: any `.swift` file
you drop under `WriteBetter/WriteBetter/` is compiled automatically. You do not
edit `project.pbxproj` to add sources.

See [SETUP.md](SETUP.md) for the project layout, the build settings that matter,
and how the artwork and DMG are generated.

## Releasing

Push a tag like `v1.2.0`; GitHub Actions builds the DMG and publishes the
release. See [SETUP.md](SETUP.md#7-releasing-and-auto-update).

## Licence

MIT.
