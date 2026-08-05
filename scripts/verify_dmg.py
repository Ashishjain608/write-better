#!/usr/bin/env python3
"""Prove a built DMG actually got the layout we asked for.

Mounting a disk image and eyeballing it is not evidence — Finder silently falls
back to defaults when the .DS_Store did not take. This reads the .DS_Store off
the mounted volume and asserts the window geometry, icon size, icon positions
and background reference are really in there.

Usage: verify_dmg.py <mounted-volume-path>
Exits non-zero (and says which check failed) if anything is off.
"""

import plistlib
import sys
from pathlib import Path

try:
    from ds_store import DSStore
except ImportError:  # pragma: no cover
    print("verify_dmg.py: the `ds_store` module is missing (it ships with dmgbuild)")
    sys.exit(3)

EXPECTED_WINDOW = (660, 400)
EXPECTED_ICON_SIZE = 128
EXPECTED_LOCATIONS = {
    "WriteBetter.app": (165, 196),
    "Applications": (495, 196),
}

failures = []
notes = []


def check(label, ok, detail):
    (notes if ok else failures).append(f"{'ok  ' if ok else 'FAIL'}  {label}: {detail}")


def main(volume: Path) -> int:
    store_path = volume / ".DS_Store"
    if not store_path.exists():
        print(f"FAIL  no .DS_Store on {volume} — the DMG is unstyled")
        return 1

    entries = {}
    with DSStore.open(str(store_path), "r") as store:
        for entry in store:
            entries.setdefault(entry.filename, {})[entry.code] = entry.value

    # ---- window geometry (bwsp = browser window settings, a binary plist)
    bwsp = entries.get(".", {}).get(b"bwsp") or entries.get(".", {}).get("bwsp")
    if isinstance(bwsp, (bytes, bytearray)):
        bwsp = plistlib.loads(bytes(bwsp))
    if bwsp:
        bounds = bwsp.get("WindowBounds", "")
        # "{{x, y}, {w, h}}"
        numbers = [int(n) for n in bounds.replace("{", " ").replace("}", " ").replace(",", " ").split()]
        size = tuple(numbers[2:4]) if len(numbers) >= 4 else None
        check("window size", size == EXPECTED_WINDOW, f"{size} (want {EXPECTED_WINDOW})")
        for key, want in (("ShowStatusBar", False), ("ShowToolbar", False),
                          ("ShowPathbar", False), ("ShowSidebar", False)):
            check(f"chrome {key}", bwsp.get(key) is want, repr(bwsp.get(key)))
    else:
        check("window settings (bwsp)", False, "missing")

    # ---- icon view settings (icvp)
    icvp = entries.get(".", {}).get(b"icvp") or entries.get(".", {}).get("icvp")
    if isinstance(icvp, (bytes, bytearray)):
        icvp = plistlib.loads(bytes(icvp))
    if icvp:
        check("icon size", icvp.get("iconSize") == EXPECTED_ICON_SIZE,
              f"{icvp.get('iconSize')} (want {EXPECTED_ICON_SIZE})")
        has_bg = icvp.get("backgroundType") == 2 and bool(
            icvp.get("backgroundImageAlias") or icvp.get("backgroundImageBookmark"))
        check("background image", has_bg,
              f"backgroundType={icvp.get('backgroundType')} alias={'yes' if icvp.get('backgroundImageAlias') else 'no'}")
        check("arrangeBy none", icvp.get("arrangeBy") in (None, "none"), repr(icvp.get("arrangeBy")))
    else:
        check("icon view settings (icvp)", False, "missing")

    # ---- icon positions. ds_store decodes an Iloc record to an (x, y) tuple;
    #      older/raw stores hand back the 16 raw bytes instead.
    for name, want in EXPECTED_LOCATIONS.items():
        iloc = entries.get(name, {}).get(b"Iloc") or entries.get(name, {}).get("Iloc")
        if iloc is None:
            check(f"position of {name}", False, "no Iloc record")
            continue
        if isinstance(iloc, (bytes, bytearray)):
            got = (int.from_bytes(iloc[0:4], "big"), int.from_bytes(iloc[4:8], "big"))
        else:
            got = (int(iloc[0]), int(iloc[1]))
        check(f"position of {name}", got == want, f"{got} (want {want})")

    # ---- files that must physically exist on the volume
    for relative, label in (
        ("WriteBetter.app", "app bundle"),
        ("Applications", "/Applications symlink"),
        (".VolumeIcon.icns", "custom volume icon"),
    ):
        check(label, (volume / relative).exists(), relative)

    # dmgbuild drops the background as a single hidden file at the volume root
    # (older recipes use a hidden .background/ folder) — accept either.
    background = [p.name for p in volume.glob(".background*")]
    if (volume / ".background").is_dir():
        background = [f".background/{p.name}" for p in (volume / ".background").glob("*")]
    check("background asset on volume", bool(background), ", ".join(background) or "none")

    for line in notes + failures:
        print(line)
    return 1 if failures else 0


if __name__ == "__main__":
    if len(sys.argv) != 2:
        print(__doc__)
        sys.exit(2)
    sys.exit(main(Path(sys.argv[1])))
