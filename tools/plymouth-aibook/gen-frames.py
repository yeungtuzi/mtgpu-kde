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

# On the aibook panel Plymouth's DRM renderer runs at device_scale=2: a 180 px
# image is scanned out as 360 px.  On a plain 4K panel it renders 1:1, so pass
# --size 480 there to keep the same 12.5%-of-screen-width proportion.
DEFAULT_SIZE = 180
# order matches ksplash: phase 0 lights bottom-left, then +90 degrees each step
CORNERS = ("q-bl", "q-tl", "q-tr", "q-br")


def main() -> int:
    import argparse

    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("src", nargs="?", default="/opt/kde6/share/plasma/look-and-feel/org.aibook.splash/contents/splash/images")
    ap.add_argument("out", nargs="?", default="frames")
    ap.add_argument("--size", type=int, default=DEFAULT_SIZE,
                    help="frame edge in px (180 for 2880x1800@2x, 480 for 3840x2160@1x)")
    args = ap.parse_args()
    src, out, SIZE = args.src, args.out, args.size
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
