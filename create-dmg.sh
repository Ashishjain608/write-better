#!/bin/bash
#
# create-dmg.sh — build, sign and package WriteBetter as a distributable DMG.
#
# Two stages, separately runnable:
#   ./create-dmg.sh                     build from source, then package
#   ./create-dmg.sh --app <path.app>    package an existing bundle (no compile)
#
# Signing degrades gracefully. If a "Developer ID Application" identity is in
# the keychain the app is hardened-signed, notarized and stapled, and the DMG
# opens with no warnings. If not, the app is ad-hoc signed and the DMG says so
# — in words, on the background art — instead of pretending everything is fine.
#
# Everything lives under ./build (gitignored). Nothing is written outside the
# repo, and no `cd` happens after the one at the top.
#
set -euo pipefail

# --------------------------------------------------------------- constants --

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$REPO_ROOT"

APP_NAME="WriteBetter"
VOLUME_NAME="WriteBetter"
XCODEPROJ="$REPO_ROOT/WriteBetter/WriteBetter.xcodeproj"
ENTITLEMENTS="$REPO_ROOT/WriteBetter/WriteBetter/WriteBetter.entitlements"

BUILD_DIR="$REPO_ROOT/build"
DERIVED_DATA="$BUILD_DIR/DerivedData"
STAGE_DIR="$BUILD_DIR/stage"
ART_DIR="$BUILD_DIR/art"
VENV_DIR="$BUILD_DIR/.venv"

DMG_OUT="$REPO_ROOT/dist/${APP_NAME}-Installer.dmg"
MOUNT_POINT=""

# Notarization credentials. Either a stored keychain profile:
#   xcrun notarytool store-credentials WriteBetterNotary --key … --key-id … --issuer …
#   export WRITEBETTER_NOTARY_PROFILE=WriteBetterNotary
# or a raw App Store Connect API key:
#   export WRITEBETTER_NOTARY_KEY=/path/AuthKey_XXXX.p8
#   export WRITEBETTER_NOTARY_KEY_ID=XXXXXXXXXX
#   export WRITEBETTER_NOTARY_ISSUER=<issuer-uuid>
NOTARY_PROFILE="${WRITEBETTER_NOTARY_PROFILE:-}"
NOTARY_KEY="${WRITEBETTER_NOTARY_KEY:-}"
NOTARY_KEY_ID="${WRITEBETTER_NOTARY_KEY_ID:-}"
NOTARY_ISSUER="${WRITEBETTER_NOTARY_ISSUER:-}"

PREBUILT_APP=""
SKIP_NOTARIZE=0
OFFLINE=0

# ------------------------------------------------------------------- chrome --

BOLD=$'\033[1m'; DIM=$'\033[2m'; RED=$'\033[31m'; YELLOW=$'\033[33m'
GREEN=$'\033[32m'; RESET=$'\033[0m'
[ -t 1 ] || { BOLD=""; DIM=""; RED=""; YELLOW=""; GREEN=""; RESET=""; }

step()  { printf '\n%s==> %s%s\n' "$BOLD" "$*" "$RESET"; }
info()  { printf '    %s\n' "$*"; }
note()  { printf '    %s%s%s\n' "$DIM" "$*" "$RESET"; }
warn()  { printf '%s !! %s%s\n' "$YELLOW" "$*" "$RESET" >&2; }
fail()  { printf '%s !! %s%s\n' "$RED" "$*" "$RESET" >&2; exit 1; }
good()  { printf '    %s✓ %s%s\n' "$GREEN" "$*" "$RESET"; }

banner() {
  printf '%s\n' "$YELLOW"
  printf '  ┌────────────────────────────────────────────────────────────────┐\n'
  while IFS= read -r line; do printf '  │ %-62s │\n' "$line"; done
  printf '  └────────────────────────────────────────────────────────────────┘\n'
  printf '%s\n' "$RESET"
}

# ------------------------------------------------------------------ cleanup --

cleanup() {
  local status=$?
  if [ -n "$MOUNT_POINT" ] && [ -d "$MOUNT_POINT" ]; then
    note "detaching $MOUNT_POINT"
    for _ in 1 2 3 4 5; do
      hdiutil detach "$MOUNT_POINT" -quiet 2>/dev/null && break
      sleep 1
    done
    hdiutil detach "$MOUNT_POINT" -force -quiet 2>/dev/null || true
  fi
  return $status
}
trap cleanup EXIT INT TERM

usage() {
  cat <<EOF
Usage: ./create-dmg.sh [options]

  --app <path>            Package this .app instead of compiling one. Lets the
                          packaging stage be exercised while the sources are
                          mid-rewrite.
  --output <path>         Where to write the DMG (default: dist/${APP_NAME}-Installer.dmg)
  --notary-profile <name> notarytool keychain profile to use.
  --no-notarize           Sign with Developer ID but skip notarization.
  --offline               Do not touch the network for tooling; if the venv is
                          missing, go straight to the unstyled fallback.
  -h, --help              This.
EOF
}

while [ $# -gt 0 ]; do
  case "$1" in
    --app)            PREBUILT_APP="${2:?--app needs a path}"; shift 2 ;;
    --output)         DMG_OUT="${2:?--output needs a path}"; shift 2 ;;
    --notary-profile) NOTARY_PROFILE="${2:?--notary-profile needs a name}"; shift 2 ;;
    --no-notarize)    SKIP_NOTARIZE=1; shift ;;
    --offline)        OFFLINE=1; shift ;;
    -h|--help)        usage; exit 0 ;;
    *)                usage >&2; fail "unknown option: $1" ;;
  esac
done

# ============================================================================
# 1. Which signing world are we in?
# ============================================================================

step "Checking for a Developer ID signing identity"

SIGN_IDENTITY="$(security find-identity -v -p codesigning 2>/dev/null \
  | grep 'Developer ID Application' | head -1 | sed -E 's/.*"(.+)".*/\1/' || true)"

if [ -n "$SIGN_IDENTITY" ]; then
  MODE="developer-id"
  good "found: $SIGN_IDENTITY"
else
  MODE="adhoc"
  banner <<'EOF'
NO DEVELOPER ID IDENTITY FOUND.

Falling back to ad-hoc signing. The resulting DMG is fine to run
locally, but anyone who downloads it will be told by macOS that
"WriteBetter is damaged and can't be opened".

That message is Gatekeeper refusing an un-notarized app, not real
corruption. The DMG background spells out the fix (System Settings
> Privacy & Security > Open Anyway).

To ship without that: join the Apple Developer Program ($99/yr),
install a Developer ID Application certificate, and re-run this
script. Everything else is already wired up.
EOF
fi

# ============================================================================
# 2. Get a .app into the staging area
# ============================================================================

rm -rf "$STAGE_DIR"
mkdir -p "$STAGE_DIR" "$ART_DIR" "$(dirname "$DMG_OUT")"
APP_PATH="$STAGE_DIR/$APP_NAME.app"

if [ -n "$PREBUILT_APP" ]; then
  step "Using pre-built app: $PREBUILT_APP"
  [ -d "$PREBUILT_APP" ] || fail "no such app bundle: $PREBUILT_APP"
  ditto "$PREBUILT_APP" "$APP_PATH"
else
  step "Building $APP_NAME (Release)"
  xcodebuild \
    -project "$XCODEPROJ" \
    -scheme "$APP_NAME" \
    -configuration Release \
    -derivedDataPath "$DERIVED_DATA" \
    -destination 'platform=macOS' \
    build | tail -5
  BUILT="$DERIVED_DATA/Build/Products/Release/$APP_NAME.app"
  [ -d "$BUILT" ] || fail "build finished but $BUILT is missing"
  ditto "$BUILT" "$APP_PATH"
fi

VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' \
  "$APP_PATH/Contents/Info.plist" 2>/dev/null || echo 'unknown')"
good "staged $APP_NAME $VERSION"

# ============================================================================
# 3. Sign
# ============================================================================

step "Signing the app"

# Inside-out: nested code first, outer bundle last. TN2206 is explicit that
# `codesign --deep` is for emergency repairs, not for signing a shippable app.
NESTED=()
while IFS= read -r item; do NESTED+=("$item"); done < <(
  find "$APP_PATH/Contents/Frameworks" "$APP_PATH/Contents/XPCServices" \
       "$APP_PATH/Contents/Library" \
       -maxdepth 2 \( -name '*.framework' -o -name '*.xpc' -o -name '*.app' -o -name '*.dylib' \) \
       2>/dev/null || true
)

if [ "$MODE" = "developer-id" ]; then
  for item in "${NESTED[@]:-}"; do
    [ -n "$item" ] || continue
    info "nested: $(basename "$item")"
    codesign --force --options runtime --timestamp --sign "$SIGN_IDENTITY" "$item"
  done
  codesign --force --options runtime --timestamp \
    --entitlements "$ENTITLEMENTS" \
    --sign "$SIGN_IDENTITY" "$APP_PATH"
  good "signed with $SIGN_IDENTITY (hardened runtime + secure timestamp)"
else
  for item in "${NESTED[@]:-}"; do
    [ -n "$item" ] || continue
    codesign --force --options runtime --sign - "$item"
  done
  codesign --force --options runtime \
    --entitlements "$ENTITLEMENTS" \
    --sign - "$APP_PATH"
  warn "ad-hoc signed (no identity) — not distributable without warnings"
fi

codesign --verify --deep --strict --verbose=2 "$APP_PATH" 2>&1 | sed 's/^/    /'

if codesign -d --entitlements - --xml "$APP_PATH" 2>/dev/null \
   | plutil -convert xml1 -o - - 2>/dev/null \
   | grep -q 'get-task-allow'; then
  fail "the signed app carries com.apple.security.get-task-allow — that is a debug entitlement and must never ship"
fi
good "no get-task-allow in the shipped signature"

# ============================================================================
# 4. Notarize + staple the app (Developer ID only)
# ============================================================================

notarytool_auth() {
  if [ -n "$NOTARY_PROFILE" ]; then
    printf '%s\n' --keychain-profile "$NOTARY_PROFILE"
  elif [ -n "$NOTARY_KEY" ] && [ -n "$NOTARY_KEY_ID" ] && [ -n "$NOTARY_ISSUER" ]; then
    printf '%s\n' --key "$NOTARY_KEY" --key-id "$NOTARY_KEY_ID" --issuer "$NOTARY_ISSUER"
  fi
}

NOTARIZED=0
if [ "$MODE" = "developer-id" ] && [ "$SKIP_NOTARIZE" -eq 0 ]; then
  AUTH=()
  while IFS= read -r arg; do [ -n "$arg" ] && AUTH+=("$arg"); done < <(notarytool_auth)

  if [ "${#AUTH[@]}" -eq 0 ]; then
    warn "Developer ID found but no notarization credentials."
    warn "Set WRITEBETTER_NOTARY_PROFILE, or WRITEBETTER_NOTARY_KEY/_KEY_ID/_ISSUER."
    warn "Shipping signed-but-not-notarized: Gatekeeper will still block it."
  else
    step "Notarizing the app"
    ZIP="$BUILD_DIR/$APP_NAME-notarize.zip"
    rm -f "$ZIP"
    ditto -c -k --keepParent "$APP_PATH" "$ZIP"
    xcrun notarytool submit "$ZIP" "${AUTH[@]}" --wait
    xcrun stapler staple "$APP_PATH"
    rm -f "$ZIP"
    NOTARIZED=1
    good "notarized and stapled"
  fi
fi

# ============================================================================
# 5. Artwork
# ============================================================================

step "Generating installer artwork"

# The Gatekeeper note is drawn into the background only when the build actually
# needs it. A notarized build gets clean art.
BG_ARGS=(dmgbg "$ART_DIR")
[ "$NOTARIZED" -eq 1 ] || BG_ARGS+=(--warning)
swift "$REPO_ROOT/scripts/artwork.swift" "${BG_ARGS[@]}" 2>&1 | sed 's/^/    /'

# Finder reads one multi-representation TIFF, not two PNGs. -cathidpicheck also
# validates that the @2x file is exactly double the 1x dimensions.
rm -f "$ART_DIR/background.tiff"
tiffutil -cathidpicheck "$ART_DIR/background.png" "$ART_DIR/background@2x.png" \
  -out "$ART_DIR/background.tiff" >/dev/null
good "background.tiff (1x + @2x)"

# Volume icon: the app icon itself, so the mounted disk is recognisable.
ICONSET="$ART_DIR/$APP_NAME.iconset"
rm -rf "$ICONSET"
mkdir -p "$ICONSET"
swift "$REPO_ROOT/scripts/artwork.swift" iconset "$ICONSET" >/dev/null 2>&1
iconutil -c icns "$ICONSET" -o "$ART_DIR/$APP_NAME.icns"
good "$APP_NAME.icns"

# ============================================================================
# 6. Build the DMG
# ============================================================================

ensure_dmgbuild() {
  if [ -x "$VENV_DIR/bin/dmgbuild" ]; then return 0; fi
  [ "$OFFLINE" -eq 1 ] && return 1
  step "Installing dmgbuild into $VENV_DIR"
  note "a local venv, so the machine's global site-packages are left alone"
  python3 -m venv "$VENV_DIR" >/dev/null 2>&1 || return 1
  "$VENV_DIR/bin/pip" install --quiet --disable-pip-version-check dmgbuild >/dev/null 2>&1 || return 1
  [ -x "$VENV_DIR/bin/dmgbuild" ]
}

rm -f "$DMG_OUT"

if ensure_dmgbuild; then
  step "Building the styled DMG with dmgbuild"
  "$VENV_DIR/bin/dmgbuild" \
    -s "$REPO_ROOT/scripts/dmg_settings.py" \
    -D app="$APP_PATH" \
    -D background="$ART_DIR/background.tiff" \
    -D volume_icon="$ART_DIR/$APP_NAME.icns" \
    "$VOLUME_NAME" "$DMG_OUT"
  STYLED=1
  good "styled DMG written"
else
  STYLED=0
  banner <<'EOF'
COULD NOT INSTALL dmgbuild.

No venv and no network, so the styled layout (background art, icon
positions, custom volume icon, hidden Finder chrome) is NOT in this
disk image. It is a plain hdiutil DMG: functional, but it looks
unfinished, and this is NOT what you should publish.

Fix: run this script again with a network connection, or
  python3 -m venv build/.venv && build/.venv/bin/pip install dmgbuild
EOF
  FALLBACK_STAGE="$BUILD_DIR/fallback"
  rm -rf "$FALLBACK_STAGE"
  mkdir -p "$FALLBACK_STAGE"
  ditto "$APP_PATH" "$FALLBACK_STAGE/$APP_NAME.app"
  ln -s /Applications "$FALLBACK_STAGE/Applications"
  if [ "$NOTARIZED" -eq 0 ]; then
    cat >"$FALLBACK_STAGE/READ ME FIRST.txt" <<'EOF'
Installing WriteBetter
======================

1. Drag WriteBetter to the Applications folder.
2. Open it from Applications.

If macOS says "WriteBetter is damaged and can't be opened":
that is not real corruption. It means this build has not been notarized
by Apple, and macOS 15+ no longer offers the old right-click > Open
override.

To open it anyway:
  System Settings > Privacy & Security > scroll down to Security >
  click "Open Anyway" next to WriteBetter > confirm.

You only have to do this once per version.
EOF
  fi
  hdiutil create -volname "$VOLUME_NAME" -srcfolder "$FALLBACK_STAGE" \
    -ov -format UDZO -imagekey zlib-level=9 "$DMG_OUT" >/dev/null
  rm -rf "$FALLBACK_STAGE"
fi

# ============================================================================
# 7. Sign + staple the DMG itself
# ============================================================================

if [ "$MODE" = "developer-id" ]; then
  step "Signing the disk image"
  codesign --force --timestamp --sign "$SIGN_IDENTITY" "$DMG_OUT"
  if [ "$NOTARIZED" -eq 1 ]; then
    AUTH=()
    while IFS= read -r arg; do [ -n "$arg" ] && AUTH+=("$arg"); done < <(notarytool_auth)
    xcrun notarytool submit "$DMG_OUT" "${AUTH[@]}" --wait
    xcrun stapler staple "$DMG_OUT"
    good "DMG notarized and stapled — offline Gatekeeper checks will pass"
  fi
fi

# ============================================================================
# 8. Verify
# ============================================================================

step "Verifying"

info "spctl assessment of the app:"
spctl -a -vvv -t exec "$APP_PATH" 2>&1 | sed 's/^/      /' || true

if [ "$MODE" = "developer-id" ]; then
  info "spctl assessment of the disk image:"
  spctl -a -vvv -t open --context context:primary-signature "$DMG_OUT" 2>&1 | sed 's/^/      /' || true
fi

MOUNT_POINT="$BUILD_DIR/verify-mount"
rm -rf "$MOUNT_POINT"
mkdir -p "$MOUNT_POINT"
hdiutil attach "$DMG_OUT" -readonly -nobrowse -noautoopen -mountpoint "$MOUNT_POINT" >/dev/null
info "mounted at $MOUNT_POINT"
ls -la "$MOUNT_POINT" | sed 's/^/      /'

if [ "$STYLED" -eq 1 ]; then
  if "$VENV_DIR/bin/python" "$REPO_ROOT/scripts/verify_dmg.py" "$MOUNT_POINT" | sed 's/^/      /'; then
    good "layout verified against the .DS_Store"
  else
    fail "the DMG mounted but its layout did not take — see the FAIL lines above"
  fi
fi

hdiutil detach "$MOUNT_POINT" -quiet
rm -rf "$MOUNT_POINT"
MOUNT_POINT=""

# ============================================================================

SIZE="$(du -h "$DMG_OUT" | cut -f1 | tr -d ' ')"
step "Done"
info "$DMG_OUT ($SIZE)"
info "version $VERSION · signing: $MODE · notarized: $([ "$NOTARIZED" -eq 1 ] && echo yes || echo no) · styled: $([ "$STYLED" -eq 1 ] && echo yes || echo no)"
if [ "$NOTARIZED" -eq 0 ]; then
  echo
  warn "This DMG will trip Gatekeeper on other people's Macs."
  warn "See the 'Releasing' section of README.md before you publish it."
fi
