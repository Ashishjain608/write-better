#!/bin/bash
#
# make-icons.sh — regenerate every image in WriteBetter's asset catalog.
#
# Everything here is derived from scripts/artwork.swift, which is in turn a
# literal transcription of the "Caret Ascend" geometry in DESIGN-BRIEF §2.2.
# Re-running this script is idempotent: it rewrites the same bytes.
#
# The three asset names are contracted with the app code — do not rename them:
#   AppIcon      the macOS app icon
#   MenuBarIcon  monochrome template image for the NSStatusItem
#   LogoMark     full-colour glyph for the panel header / Settings / onboarding
#
# Usage: ./scripts/make-icons.sh
#
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ASSETS="$REPO_ROOT/WriteBetter/WriteBetter/Assets.xcassets"
ARTWORK="$REPO_ROOT/scripts/artwork.swift"

echo "==> Regenerating asset catalog at $ASSETS"

# ---------------------------------------------------------------- AppIcon ----
APPICON="$ASSETS/AppIcon.appiconset"
rm -rf "$APPICON"
mkdir -p "$APPICON"
swift "$ARTWORK" appicon "$APPICON"

{
  printf '{\n  "images" : [\n'
  first=1
  for spec in "16 1" "16 2" "32 1" "32 2" "128 1" "128 2" "256 1" "256 2" "512 1" "512 2"; do
    set -- $spec
    pt=$1
    scale=$2
    if [ "$scale" = "1" ]; then file="icon_${pt}x${pt}.png"; else file="icon_${pt}x${pt}@2x.png"; fi
    [ $first -eq 1 ] || printf ',\n'
    first=0
    printf '    {\n      "filename" : "%s",\n      "idiom" : "mac",\n      "scale" : "%sx",\n      "size" : "%sx%s"\n    }' \
      "$file" "$scale" "$pt" "$pt"
  done
  printf '\n  ],\n  "info" : {\n    "author" : "writebetter/scripts/make-icons.sh",\n    "version" : 1\n  }\n}\n'
} >"$APPICON/Contents.json"

# ------------------------------------------------------------ MenuBarIcon ----
# Template rendering intent: macOS tints this for light/dark menu bars and for
# the highlighted (menu-open) state, so it must be pure black + alpha.
MENUBAR="$ASSETS/MenuBarIcon.imageset"
rm -rf "$MENUBAR"
mkdir -p "$MENUBAR"
swift "$ARTWORK" menubar "$MENUBAR"

cat >"$MENUBAR/Contents.json" <<'JSON'
{
  "images" : [
    {
      "filename" : "menubar-18.png",
      "idiom" : "universal",
      "scale" : "1x"
    },
    {
      "filename" : "menubar-36.png",
      "idiom" : "universal",
      "scale" : "2x"
    }
  ],
  "info" : {
    "author" : "writebetter/scripts/make-icons.sh",
    "version" : 1
  },
  "properties" : {
    "template-rendering-intent" : "template"
  }
}
JSON

# --------------------------------------------------------------- LogoMark ----
LOGOMARK="$ASSETS/LogoMark.imageset"
rm -rf "$LOGOMARK"
mkdir -p "$LOGOMARK"
swift "$ARTWORK" logomark "$LOGOMARK"

cat >"$LOGOMARK/Contents.json" <<'JSON'
{
  "images" : [
    {
      "filename" : "logomark-256.png",
      "idiom" : "universal",
      "scale" : "1x"
    },
    {
      "filename" : "logomark-512.png",
      "idiom" : "universal",
      "scale" : "2x"
    }
  ],
  "info" : {
    "author" : "writebetter/scripts/make-icons.sh",
    "version" : 1
  },
  "properties" : {
    "template-rendering-intent" : "original"
  }
}
JSON

# ------------------------------------------------------------- AccentColor ---
# DESIGN-BRIEF §3: accent #7C6BFF on dark, #5B45E0 on light.
ACCENT="$ASSETS/AccentColor.colorset"
mkdir -p "$ACCENT"
cat >"$ACCENT/Contents.json" <<'JSON'
{
  "colors" : [
    {
      "color" : {
        "color-space" : "srgb",
        "components" : {
          "alpha" : "1.000",
          "blue" : "0xE0",
          "green" : "0x45",
          "red" : "0x5B"
        }
      },
      "idiom" : "universal"
    },
    {
      "appearances" : [
        {
          "appearance" : "luminosity",
          "value" : "dark"
        }
      ],
      "color" : {
        "color-space" : "srgb",
        "components" : {
          "alpha" : "1.000",
          "blue" : "0xFF",
          "green" : "0x6B",
          "red" : "0x7C"
        }
      },
      "idiom" : "universal"
    }
  ],
  "info" : {
    "author" : "writebetter/scripts/make-icons.sh",
    "version" : 1
  }
}
JSON

echo "==> Done. AppIcon / MenuBarIcon / LogoMark / AccentColor regenerated."
