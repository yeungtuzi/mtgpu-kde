#!/usr/bin/env python3
"""Generate the mtgpu-kde wallpapers from the four sdmm splash frames.

Outputs:
  rabbit-4color-alpha.png  four-colour rabbit (all four corners lit), rounded alpha
  aibook-abstract-4k.png   navy/cyan "Abstract + BlueFeathers" style wallpaper
  aibook-topography3.jpg   Cachy_Topography3 with the CachyOS "C" replaced by the rabbit
                           (only when --topography is given)

Requires: pillow; opencv-python (cv2) only for --topography.

Usage:
  gen-wallpapers.py --out tools/wallpapers
  gen-wallpapers.py --out /tmp/x --topography /usr/share/wallpapers/cachyos-wallpapers/Cachy_Topography3.jpg
"""
import argparse
import math
import random
from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter


def four_colour_rabbit(frames_dir: Path) -> Image.Image:
    frames = [Image.open(frames_dir / f"frame-0{i}.png").convert("RGBA") for i in range(4)]
    import numpy as np

    a = np.maximum.reduce([np.array(f) for f in frames])
    combo = Image.fromarray(a, "RGBA")
    mask = Image.new("L", combo.size, 0)
    w, h = combo.size
    inset = max(2, w // 60)
    ImageDraw.Draw(mask).rounded_rectangle(
        [inset, inset, w - 1 - inset, h - 1 - inset], radius=w // 6, fill=255)
    mask = mask.filter(ImageFilter.GaussianBlur(1.2))
    combo.putalpha(mask)
    return combo


def abstract_wallpaper(rabbit: Image.Image, width=3840, height=2160, seed=7) -> Image.Image:
    random.seed(seed)
    W, H = width, height
    img = Image.new("RGB", (W, H), (3, 6, 12))
    d = ImageDraw.Draw(img)
    for y in range(H):
        t = y / H
        d.line([(0, y), (W, y)],
               fill=(int(12 * (1 - t) + 2 * t), int(28 * (1 - t) + 4 * t), int(50 * (1 - t) + 9 * t)))
    glow = Image.new("RGB", (W, H), (0, 0, 0))
    gd = ImageDraw.Draw(glow)
    cx, cy = int(W * 0.5), int(H * 0.42)
    for i in range(80):
        rad = int(max(W, H) * 0.62 * (1 - i / 80)) + 40
        gd.ellipse([cx - rad, cy - int(rad * 0.6), cx + rad, cy + int(rad * 0.6)], fill=(5, 38, 58))
    glow = glow.filter(ImageFilter.GaussianBlur(160))
    img = Image.blend(img, glow, 0.65)

    strokes = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    sd = ImageDraw.Draw(strokes)
    for _ in range(1400):
        x0 = random.uniform(-0.2 * W, 1.2 * W)
        y0 = random.uniform(-0.2 * H, 1.2 * H)
        ang = random.uniform(0, 2 * math.pi)
        ln = random.uniform(0.06, 0.4)
        dx, dy = math.cos(ang) * ln * W, math.sin(ang) * ln * H
        pts = [(x0 + dx * t / 40, y0 + dy * t / 40 + math.sin(t / 40 * math.pi * 2) * random.uniform(0, 20))
               for t in range(41)]
        sd.line(pts, fill=(48, 155, 195, random.randint(8, 42)),
                width=random.choice([1, 1, 2, 2, 3]), joint="curve")
    strokes = strokes.filter(ImageFilter.GaussianBlur(1.6))
    img = img.convert("RGBA")
    img.alpha_composite(strokes)

    m = Image.new("L", (W, H), 0)
    ImageDraw.Draw(m).ellipse([-W * 0.3, -H * 0.3, W * 1.3, H * 1.3], fill=255)
    m = m.filter(ImageFilter.GaussianBlur(300))
    img = Image.composite(img, Image.new("RGBA", (W, H), (0, 0, 0, 255)), m)

    size = 620
    r = rabbit.resize((size, size), Image.LANCZOS)
    halo = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    ImageDraw.Draw(halo).ellipse([(W - size) // 2 - 90, (H - size) // 2 - 90,
                                  (W + size) // 2 + 90, (H + size) // 2 + 90],
                                 fill=(28, 135, 185, 80))
    halo = halo.filter(ImageFilter.GaussianBlur(100))
    img.alpha_composite(halo)
    sh = Image.new("L", (W, H), 0)
    ImageDraw.Draw(sh).rounded_rectangle([(W - size) // 2 + 16, (H - size) // 2 + 36,
                                          (W + size) // 2 + 16, (H + size) // 2 + 36],
                                         radius=int(size * 0.18), fill=180)
    sh = sh.filter(ImageFilter.GaussianBlur(40))
    img.paste(Image.new("RGBA", (W, H), (0, 0, 0, 255)), (0, 0), sh)
    img.paste(r, ((W - size) // 2, (H - size) // 2), r)
    return img.convert("RGB")


def topography_wallpaper(src: Path, rabbit: Image.Image) -> Image.Image:
    import cv2
    import numpy as np

    im = Image.open(src).convert("RGB")
    a = np.array(im)
    g = a[:, :, 0].astype(np.int32)
    region = np.zeros(g.shape, np.uint8)
    region[450:1000, 1400:2150] = 1
    bright = ((g > 112) & (region == 1)).astype(np.uint8)
    bright = cv2.morphologyEx(bright, cv2.MORPH_CLOSE, np.ones((3, 3), np.uint8))
    n, lab, stats, _ = cv2.connectedComponentsWithStats(bright)
    if n < 2:
        raise SystemExit("could not locate the CachyOS logo")
    idx = max(range(1, n), key=lambda i: stats[i, cv2.CC_STAT_AREA])
    x, y, w, h, _ = stats[idx]
    mask = (lab == idx).astype(np.uint8) * 255
    mask = cv2.dilate(mask, np.ones((9, 9), np.uint8))
    out = cv2.inpaint(cv2.cvtColor(a, cv2.COLOR_RGB2BGR), mask, 3, cv2.INPAINT_TELEA)
    base = Image.fromarray(cv2.cvtColor(out, cv2.COLOR_BGR2RGB)).convert("RGBA")
    size = int(h * 1.15)
    r = rabbit.resize((size, size), Image.LANCZOS)
    pos = (x + w // 2 - size // 2, y + h // 2 - size // 2)
    W, H = base.size
    sh = Image.new("L", (W, H), 0)
    ImageDraw.Draw(sh).rounded_rectangle([pos[0] + 6, pos[1] + 14, pos[0] + size + 6, pos[1] + size + 14],
                                         radius=int(size * 0.2), fill=140)
    sh = sh.filter(ImageFilter.GaussianBlur(16))
    base.paste(Image.new("RGBA", (W, H), (0, 0, 0, 255)), (0, 0), sh)
    base.paste(r, pos, r)
    return base.convert("RGB")


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--frames", type=Path, default=Path(__file__).resolve().parents[1] / "sddm" / "theme-mtgpu-kde")
    ap.add_argument("--out", type=Path, default=Path(__file__).resolve().parent)
    ap.add_argument("--topography", type=Path, help="Cachy_Topography3.jpg to re-badge")
    args = ap.parse_args()
    args.out.mkdir(parents=True, exist_ok=True)

    rabbit = four_colour_rabbit(args.frames)
    rabbit.save(args.out / "rabbit-4color-alpha.png")
    print("wrote rabbit-4color-alpha.png", rabbit.size)

    abstract_wallpaper(rabbit).save(args.out / "aibook-abstract-4k.png")
    print("wrote aibook-abstract-4k.png")

    if args.topography:
        topography_wallpaper(args.topography, rabbit).save(args.out / "aibook-topography3.jpg", quality=95)
        print("wrote aibook-topography3.jpg")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
