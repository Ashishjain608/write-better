# Contributing

Thanks for helping out. Security problems go through [`SECURITY.md`](SECURITY.md), never a public issue.

## Before you start

- **Bugs and ideas** go through the [issue forms](https://github.com/Ashishjain608/write-better/issues/new/choose).
- **Open an issue first** for anything non-trivial (a new provider, a behaviour change, UI flow changes),
  and wait for a go before building. Typo fixes, small obvious bug fixes and new self-checks can go
  straight to a pull request.
- WriteBetter stays small, native and private: no server, no telemetry, and no dependency the
  standard library or the platform already covers.

## Development setup

Xcode 26 or later on macOS 14+. No packages to install first; Xcode resolves the one Swift package
(Sparkle) on first build.

```bash
open WriteBetter/WriteBetter.xcodeproj        # then ⌘R

# or from the command line
xcodebuild -project WriteBetter/WriteBetter.xcodeproj -scheme WriteBetter \
           -configuration Debug -derivedDataPath build/DerivedData build
build/DerivedData/Build/Products/Debug/WriteBetter.app/Contents/MacOS/WriteBetter --self-check
```

`--self-check` runs the offline checks (request shapes for every provider, SSE parsing, prompt
construction) with no network and no key. Debug and Release builds must be warning-free.

[`SETUP.md`](SETUP.md) covers the project layout and the build settings that matter.
[`docs/design-brief.md`](docs/design-brief.md) is the UI spec; code comments cite it by section (`§7.1`).

## Making a change

Fork, branch from `main`, keep each PR to one change. Commit titles are imperative and sentence case,
72 characters or less, no `feat:`/`fix:` prefixes. Explain *why* in the body. Add a line to
[`CHANGELOG.md`](CHANGELOG.md) under `## [Unreleased]` for anything a user would notice.

AI-assisted contributions are welcome, as long as a human has run and understood every change and
says so in the PR when a substantial part was generated.

## Releasing (maintainers)

1. Bump `MARKETING_VERSION` and `CURRENT_PROJECT_VERSION` in the Xcode project.
2. Move the `[Unreleased]` entries in `CHANGELOG.md` under a new `## [x.y.z] - YYYY-MM-DD` heading.
3. Merge that PR, then `git tag vX.Y.Z && git push origin vX.Y.Z`.

The Release workflow builds, signs with the maintainer's Developer ID, notarizes, publishes the DMG
and the update feed. Tags with a `-` (for example `v1.1.0-rc.1`) publish as prereleases, which never
reach the update feed or the download link. The secrets it reads are listed in
[`release.yml`](.github/workflows/release.yml).

## License

By contributing, you agree your contributions are licensed under the [MIT license](LICENSE).
