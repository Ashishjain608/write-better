#!/bin/bash
#
# make-appcast.sh — write a one-item Sparkle appcast for a released DMG.
#
#   SPARKLE_ED_PRIVATE_KEY=<key> scripts/make-appcast.sh <tag> <versioned.dmg> <sign_update> > appcast.xml
#
# The feed only ever needs the newest release: Sparkle offers an update when
# sparkle:version (CFBundleVersion) is higher than the running app's. The
# private key arrives in the environment, is written to a mode-600 temp file for
# sign_update, and is removed on exit. It is never printed.
#
set -euo pipefail

TAG="${1:?tag, e.g. v1.1.0}"
DMG="${2:?path to WriteBetter-X.Y.Z.dmg}"
SIGN_UPDATE="${3:?path to sign_update from Sparkle}"
: "${SPARKLE_ED_PRIVATE_KEY:?SPARKLE_ED_PRIVATE_KEY is not set}"

REPO="Ashishjain608/write-better"
VERSION="${TAG#v}"
ASSET="$(basename "$DMG")"

# Short and build versions come from the app inside the DMG, not from the tag,
# so the feed can never disagree with what Sparkle finds after installing.
MNT="$(mktemp -d)"
KEY_FILE="$(mktemp)"
cleanup() {
  hdiutil detach "$MNT" -quiet 2>/dev/null || true
  rm -rf "$MNT"
  rm -f "$KEY_FILE"
}
trap cleanup EXIT
hdiutil attach "$DMG" -readonly -nobrowse -noautoopen -mountpoint "$MNT" >/dev/null
PLIST="$MNT/WriteBetter.app/Contents/Info.plist"
SHORT="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$PLIST")"
BUILD="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$PLIST")"
MINOS="$(/usr/libexec/PlistBuddy -c 'Print :LSMinimumSystemVersion' "$PLIST")"
[ "$SHORT" = "$VERSION" ] || { echo "tag $TAG does not match app version $SHORT" >&2; exit 1; }

umask 077
printf '%s' "$SPARKLE_ED_PRIVATE_KEY" > "$KEY_FILE"
SIG_ATTRS="$("$SIGN_UPDATE" --ed-key-file "$KEY_FILE" "$DMG")"   # sparkle:edSignature="…" length="…"
case "$SIG_ATTRS" in *edSignature=*length=*) ;; *) echo "sign_update gave no signature" >&2; exit 1 ;; esac

cat <<EOF
<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">
  <channel>
    <title>WriteBetter</title>
    <item>
      <title>Version ${SHORT}</title>
      <pubDate>$(LC_ALL=C date -u '+%a, %d %b %Y %H:%M:%S +0000')</pubDate>
      <sparkle:version>${BUILD}</sparkle:version>
      <sparkle:shortVersionString>${SHORT}</sparkle:shortVersionString>
      <sparkle:minimumSystemVersion>${MINOS}</sparkle:minimumSystemVersion>
      <sparkle:releaseNotesLink>https://github.com/${REPO}/releases/tag/${TAG}</sparkle:releaseNotesLink>
      <enclosure url="https://github.com/${REPO}/releases/download/${TAG}/${ASSET}" type="application/octet-stream" ${SIG_ATTRS} />
    </item>
  </channel>
</rss>
EOF
