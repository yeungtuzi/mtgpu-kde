#!/usr/bin/env python3
"""Render the aibook Plymouth splash frames from the KDE ksplash sprites.

Plymouth's script plugin cannot scale images at runtime, and gdm deactivates
Plymouth at an arbitrary moment, freezing whatever frame is on screen.  A
smooth sin() fade therefore can stop mid-transition (two corners half lit),
which looks like a rendering bug.  So we render four discrete frames - exactly
one coloured corner at a time, in the same order as the ksplash phase
(bottom-left -> top-left -> top-right -> bottom-right) - and the stopped frame
always looks intentional.

Plymouth auto-enables device_scale=2 on this 2880x1800 panel, so Window.GetWidth
is logical 1440 and ksplash's min(W/4, H/2) == 360 logical pixels.

Usage: gen-frames.py <ksplash-images-dir> <output-dir>
"""
import os
import subprocess
import sys

# Plymouth runs the DRM renderer at device_scale=2 on this panel: a 180 px
# image is scanned out as 360 px, matching the ksplash icon size.
SIZE = 180
# order matches ksplash: phase 0 lights bottom-left, then +90 degrees each step
CORNERS = ("q-bl", "q-tl", "q-tr", "q-br")


def main() -> int:
    src = sys.argv[1] if len(sys.argv) > 1 else \
        "/opt/kde6/share/plasma/look-and-feel/org.aibook.splash/contents/splash/images"
    out = sys.argv[2] if len(sys.argv) > 2 else "frames"
    os.makedirs(out, exist_ok=True)
    for name in ("icon-gray",) + CORNERS:
        subprocess.run(["convert", os.path.join(src, name + ".png"),
                        "-resize", f"{SIZE}x{SIZE}", "-strip",
                        f"PNG32:{os.path.join(out, 'base-' + name + '.png')}"],
                       check=True)
    for idx, corner in enumerate(CORNERS):
        subprocess.run(["convert",
                        os.path.join(out, "base-icon-gray.png"),
                        os.path.join(out, "base-" + corner + ".png"),
                        "-compose", "over", "-composite",
                        f"PNG32:{os.path.join(out, f'frame-{idx:02d}.png')}"],
                       check=True)
    for name in ("icon-gray",) + CORNERS:
        os.unlink(os.path.join(out, "base-" + name + ".png"))
    print(f"rendered {len(CORNERS)} discrete corner frames ({SIZE}x{SIZE}) into {out}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
