#!/usr/bin/env python3
"""Retired generator for the unofficial Agent Bar app icon.

The official icon is the confirmed single-symbol artwork checked in at
icon/icon_1024.png, icon/AppIcon.iconset/, and AppIcon.icns (Lu Zhengyang,
2026-11-19). This file used to draw a notch, mascots, and cards with Pillow
and then overwrite those paths, including a fresh resize of the 1024 master
that would discard the hand-tuned 16 and 32 glyphs.

Running it must not recreate that artwork or replace the confirmed files.
AppIcon.icns was produced with iconutil on a Mac from icon/AppIcon.iconset.
Do not regenerate or recompress it here.
"""

import sys


def main() -> int:
    sys.stderr.write(
        "tools/make_icon.py is retired.\n"
        "The confirmed Agent Bar app icon is already checked in "
        "(icon/icon_1024.png, icon/AppIcon.iconset/, AppIcon.icns).\n"
        "This script no longer draws or writes an icon.\n"
    )
    return 1


if __name__ == "__main__":
    raise SystemExit(main())
