# Security policy

## Supported versions

Security fixes go into the latest release only.

## Reporting a vulnerability

Please report vulnerabilities privately, **not** as a public issue. Use GitHub's
[private vulnerability reporting](https://github.com/Ashishjain608/write-better/security/advisories/new)
(the repository's **Security** tab → **Report a vulnerability**) and include:

- the app version (Settings → About) and your macOS version
- steps to reproduce, and what an attacker gains

The maintainer aims to acknowledge reports within a week. Once a fix ships, the advisory is published
with credit to you unless you'd rather stay anonymous.

## Scope

WriteBetter has no server and no account. It sends the text you ask it to rewrite to the AI provider
you picked, with your API key, and to nobody else. Keys live in the macOS Keychain. The most relevant
reports are about:

- an API key leaving the Keychain other than in the request to its own provider (logs, crash reports,
  the clipboard, another provider's endpoint)
- your text reaching anyone other than the provider you selected
- Replace in place typing or pasting into a different app or window than the one you came from
- the update feed or the downloaded update being accepted without a valid signature
