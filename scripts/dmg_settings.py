# -*- coding: utf-8 -*-
#
# dmgbuild settings for the WriteBetter installer disk image.
#
# Driven by create-dmg.sh, which passes every path in via -D. dmgbuild writes
# the .DS_Store and alias records itself (via the ds_store / mac_alias Python
# modules) and never talks to Finder, so this is reproducible and works over
# SSH / in CI with no Automation (TCC) grant and none of the
# "hdiutil detach: Resource busy" races that AppleScript-driven tools hit.
#
# Layout constants here MUST stay in sync with scripts/artwork.swift
# (`dmgWindow`, `dmgIconY`) — the background art is drawn to match.

import os.path

application = defines["app"]  # noqa: F821  (dmgbuild injects `defines`)
appname = os.path.basename(application)

# ---------------------------------------------------------------- contents --
files = [application]
symlinks = {"Applications": "/Applications"}

# ------------------------------------------------------------------ format --
format = "UDZO"
size = None

# ------------------------------------------------------------ volume icon ---
# A real custom icon, not the generic removable-disk graphic.
icon = defines["volume_icon"]  # noqa: F821

# ---------------------------------------------------------------- window ----
# 660x400 content area. The background TIFF carries a 1x and a @2x
# representation, so Finder picks the right one per display.
background = defines["background"]  # noqa: F821

window_rect = ((200, 180), (660, 400))
default_view = "icon-view"

show_status_bar = False
show_tab_view = False
show_toolbar = False
show_pathbar = False
show_sidebar = False
sidebar_width = 180
show_icon_preview = False

include_icon_view_settings = "auto"
include_list_view_settings = "auto"

# ----------------------------------------------------------------- icons ----
arrange_by = None
grid_offset = (0, 0)
grid_spacing = 100
scroll_position = (0, 0)
label_pos = "bottom"
text_size = 12
icon_size = 128

icon_locations = {
    appname: (165, 196),
    "Applications": (495, 196),
}

hide_extension = [appname]
