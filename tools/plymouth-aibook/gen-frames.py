#!/usr/bin/env python3
"""Render the KDE ksplash (org.aibook.splash) animation into Plymouth frames.

The ksplash QML draws a grey icon with four coloured quadrant sprites whose
opacities follow sin(phase - offset); this script reproduces that composition
with ImageMagick so the Plymouth theme only has to cycle pre-rendered images.

Plymouth auto-enables device_scale=2 on this 2880x1800 panel, so Window.GetWidth
is logical 1440 and the ksplash size min(W/4, H/2) == 360 logical pixels.
Frames are therefore rendered at 360x360.

Usage: gen-frames.py <ksplash-images-dir> <output-dir>
"""
import math
import os
import subprocess
import sys

FRAMES = 24
SIZE = 360
NAMES = ("icon-gray", "q-tl", "q-tr", "q-br", "q-bl")


def main() -> int:
    src = sys.argv[1] if len(sys.argv) > 1 else \
        "/opt/kde6/share/plasma/look-and-feel/org.aibook.splash/contents/splash/images"
    out = sys.argv[2] if len(sys.argv) > 2 else "frames"
    os.makedirs(out, exist_ok=True)
    for name in NAMES:
        subprocess.run(["convert", os.path.join(src, name + ".png"),
                        "-resize", f"{SIZE}x{SIZE}", "-strip",
                        f"PNG32:{os.path.join(out, 'base-' + name + '.png')}"],
                       check=True)
    for i in range(FRAMES):
        phase = 2.0 * math.pi * i / FRAMES
        ops = {
            "q-tl": max(0.0, math.sin(phase)),
            "q-tr": max(0.0, math.sin(phase - math.pi / 2)),
            "q-br": max(0.0, math.sin(phase - math.pi)),
            "q-bl": max(0.0, math.sin(phase - 3 * math.pi / 2)),
        }
        args = ["convert", os.path.join(out, "base-icon-gray.png")]
        for name, opacity in ops.items():
            if opacity > 0.001:
                args += ["(", os.path.join(out, "base-" + name + ".png"),
                         "-alpha", "set", "-channel", "A",
                         "-evaluate", "multiply", f"{opacity:.4f}", "+channel",
                         ")", "-compose", "over", "-composite"]
        args.append(f"PNG32:{os.path.join(out, f'frame-{i:02d}.png')}")
        subprocess.run(args, check=True)
    for name in NAMES:
        os.unlink(os.path.join(out, "base-" + name + ".png"))
    print(f"rendered {FRAMES} frames ({SIZE}x{SIZE}) into {out}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
