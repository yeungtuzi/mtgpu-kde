#!/usr/bin/env python3
"""Generate the rabbit-walk screensaver video for macOS.

Background: tools/wallpapers/aibook-abstract-4k.png
Rabbit:     ksplash frame-00..03 (480x480, one coloured corner per frame),
            switched every 0.7 s exactly like org.aibook.splash.
Motion:     closed Catmull-Rom spline through random waypoints, so the video
            loops seamlessly.  The rabbit wanders freely over the background.

Output: rawvideo rgb24 piped into ffmpeg (libx265) -> HEVC .mov.

Usage: gen-video.py [--width 3840] [--height 2160] [--fps 30]
                    [--duration 56] [--out rabbit-walk.mov] [--preview]
"""
import argparse
import math
import random
import subprocess
import sys
from pathlib import Path

import numpy as np
from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
BG = Path(__file__).resolve().parent / "bg-no-rabbit.png"
BG_FALLBACK = ROOT / "wallpapers" / "aibook-abstract-4k.png"
FRAMES_DIR = ROOT / "ksplash-aibook" / "org.aibook.splash" / "contents" / "splash" / "images"

CORNER_SWITCH = 0.7  # seconds per colour frame, same as ksplash Timer interval


def catmull_rom_closed(points, t):
    """t in [0,1) over the closed loop."""
    n = len(points)
    scaled = t * n
    i = int(scaled) % n
    u = scaled - int(scaled)
    p0 = points[(i - 1) % n]
    p1 = points[i]
    p2 = points[(i + 1) % n]
    p3 = points[(i + 2) % n]
    u2, u3 = u * u, u * u * u
    x = 0.5 * ((2 * p1[0]) + (-p0[0] + p2[0]) * u
               + (2 * p0[0] - 5 * p1[0] + 4 * p2[0] - p3[0]) * u2
               + (-p0[0] + 3 * p1[0] - 3 * p2[0] + p3[0]) * u3)
    y = 0.5 * ((2 * p1[1]) + (-p0[1] + p2[1]) * u
               + (2 * p0[1] - 5 * p1[1] + 4 * p2[1] - p3[1]) * u2
               + (-p0[1] + 3 * p1[1] - 3 * p2[1] + p3[1]) * u3)
    return x, y


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--width", type=int, default=3840)
    ap.add_argument("--height", type=int, default=2160)
    ap.add_argument("--fps", type=int, default=30)
    ap.add_argument("--duration", type=float, default=56.0)
    ap.add_argument("--out", type=Path, default=Path("rabbit-walk.mov"))
    ap.add_argument("--preview", action="store_true", help="render 4 s to rabbit-walk-preview.mp4")
    ap.add_argument("--seed", type=int, default=20261122)
    ap.add_argument("--corner-switch", type=float, default=CORNER_SWITCH,
                    help="seconds per colour frame (0.75 gives a seamless 30 s loop)")
    args = ap.parse_args()

    W, H = args.width, args.height
    duration = 4.0 if args.preview else args.duration
    fps = args.fps
    nframes = int(round(duration * fps))

    bg_path = BG if BG.exists() else BG_FALLBACK
    bg = np.array(Image.open(bg_path).convert("RGB").resize((W, H), Image.LANCZOS))
    # scale sprite to 12.5% of the video width, like ksplash
    size = int(W * 0.125)
    from PIL import ImageDraw, ImageFilter
    def rounded(frame_img):
        mask = Image.new("L", (size, size), 0)
        inset = max(2, size // 60)
        ImageDraw.Draw(mask).rounded_rectangle(
            [inset, inset, size - 1 - inset, size - 1 - inset],
            radius=size // 6, fill=255)
        mask = mask.filter(ImageFilter.GaussianBlur(max(1.0, size / 400)))
        out = frame_img.copy()
        out.putalpha(mask)
        return out
    sprites = [np.array(rounded(Image.open(FRAMES_DIR / f"frame-0{i}.png").convert("RGBA")
                                .resize((size, size), Image.LANCZOS)))
               for i in range(4)]

    # waypoints: keep the rabbit comfortably inside the frame
    rng = random.Random(args.seed)
    margin = size * 0.75
    npoints = 7
    # First waypoint is the exact screen centre: macOS uses the video's first
    # frame as the static wallpaper/thumbnail, so the rabbit must start centred.
    pts = [(W / 2.0, H / 2.0)]
    pts += [(rng.uniform(margin, W - margin), rng.uniform(margin, H - margin))
            for _ in range(npoints - 1)]
    # ensure no two consecutive waypoints are too close (avoids jitter)
    for i in range(npoints):
        a, b = pts[i], pts[(i + 1) % npoints]
        if math.dist(a, b) < W * 0.15:
            pts[(i + 1) % npoints] = (rng.uniform(margin, W - margin),
                                      rng.uniform(margin, H - margin))

    cmd = [
        "ffmpeg", "-y", "-nostdin", "-loglevel", "error",
        "-f", "rawvideo", "-pix_fmt", "rgb24", "-s", f"{W}x{H}",
        "-r", str(fps), "-i", "-",
        "-c:v", "libx265", "-preset", "fast", "-crf", "20",
        "-pix_fmt", "yuv420p10le", "-tag:v", "hvc1",
        "-an", str(args.out),
    ]
    proc = subprocess.Popen(cmd, stdin=subprocess.PIPE)
    assert proc.stdin

    for f in range(nframes):
        t = (f / nframes) % 1.0
        x, y = catmull_rom_closed(pts, t)
        idx = int((f / fps) / args.corner_switch) % 4
        sprite = sprites[idx]
        alpha = sprite[:, :, 3:4].astype(np.float32) / 255.0
        rgb = sprite[:, :, :3].astype(np.float32)
        ix, iy = int(x - size / 2), int(y - size / 2)
        ix = max(0, min(W - size, ix))
        iy = max(0, min(H - size, iy))
        region = bg[iy:iy + size, ix:ix + size].astype(np.float32)
        comp = region * (1 - alpha) + rgb * alpha
        frame = bg.copy()
        frame[iy:iy + size, ix:ix + size] = comp.astype(np.uint8)
        proc.stdin.write(frame.tobytes())
        if f % 30 == 0:
            print(f"\r{f}/{nframes}", end="", file=sys.stderr, flush=True)
    proc.stdin.close()
    rc = proc.wait()
    print(f"\ndone rc={rc} -> {args.out} ({duration:.0f}s @ {fps}fps)", file=sys.stderr)
    return rc


if __name__ == "__main__":
    raise SystemExit(main())
