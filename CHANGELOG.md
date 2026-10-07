# Changelog

All notable changes to WriteBetter are recorded here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and versions follow
[Semantic Versioning](https://semver.org/).

## [Unreleased]

## [1.1.0] - 2026-10-07

First public release.

### Added
- Open-source release under the MIT license.
- Claude Sonnet 5.5 and Opus 5.5; GPT-6.1 Sol and GPT-6 Luna; Gemini 3.8 Flash. Any other model id can be typed under "Other…".
- A custom OpenAI-compatible endpoint (Ollama, LM Studio, OpenRouter) and Apple's on-device model (macOS 26 with Apple Intelligence).
- Claude Code and Codex CLI providers: rewrites run through your signed-in `claude` or `codex` CLI, billed to that subscription, with no API key. The answer arrives in one piece (no streaming), and there is an effort picker.
- Up to 4 saved actions on ⌘6–⌘9, managed in Settings → Actions, and "Save as action" from ⌘K.
- In-app updates (Sparkle), a Homebrew cask, and a DMG built by GitHub Actions on each release tag.

### Fixed
- Settings did not open on macOS 14 and later.
- Replace could paste partial or cut-off results.
- Replace could paste into a stale app.
- Replace now waits for the target app to be in front before pasting.
- The clipboard, including images and rich text, is fully restored afterwards.
- Cut-off answers were shown as "Done".
- Rewrites were killed at 60 s.
- A locked Keychain read as "no key".
- A taken ⇧⌘Space failed silently.
- Accessibility status stopped updating after 2 minutes.

### Removed
- The unused Apple Events entitlement.

## [1.0.0] - 2026-08-05

### Added
- Anthropic, OpenAI and Google Gemini providers, each with its own key in the macOS Keychain.
- Streaming rewrites in a floating panel, opened with ⇧⌘Space.
- Quick actions (Fix Grammar, Clarify, Shorten, Professional, Friendly) on ⌘1–⌘5, and a free-form prompt on ⌘K.
- Optional Accessibility upgrade: capture the current selection and Replace in place.
- Drag-to-Applications DMG with a signing and notarization path.
