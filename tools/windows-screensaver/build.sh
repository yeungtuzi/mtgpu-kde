#!/bin/bash
# Cross-build rabbit.scr with MinGW-w64.  Requires: gcc-mingw-w64-x86-64, python3-pil.
set -euo pipefail
cd "$(dirname "$0")"
CC=${CC:-x86_64-w64-mingw32-g++}
WINDRES=${WINDRES:-x86_64-w64-mingw32-windres}
FRAMES=../ksplash-aibook/org.aibook.splash/contents/splash/images
mkdir -p build

python3 - "$FRAMES" <<'PY'
import sys
from PIL import Image, ImageDraw, ImageFilter
src = sys.argv[1]
for i in range(4):
    im = Image.open(f"{src}/frame-0{i}.png").convert("RGBA")
    # 768 px so a 6K panel still gets a 12.5%-of-width sprite (no tiny rabbit)
    target = 768
    if im.width != target:
        im = im.resize((target, target), Image.LANCZOS)
    size = im.width
    mask = Image.new("L", im.size, 0)
    inset = max(2, size // 60)
    ImageDraw.Draw(mask).rounded_rectangle(
        [inset, inset, size - 1 - inset, size - 1 - inset],
        radius=size // 6, fill=255)
    mask = mask.filter(ImageFilter.GaussianBlur(max(1.0, size / 400)))
    im.putalpha(mask)
    im.save(f"build/frame-0{i}.png")
print("frames -> build/frame-0*.png (rounded alpha)")
PY
cp assets/background.png build/background.png
cp rabbit.manifest build/rabbit.manifest

cat > build/rabbit.rc <<'RC'
1 24 "rabbit.manifest"
200 RCDATA "background.png"
201 RCDATA "frame-00.png"
202 RCDATA "frame-01.png"
203 RCDATA "frame-02.png"
204 RCDATA "frame-03.png"
RC

$WINDRES -I build -i build/rabbit.rc -O coff -o build/rabbit.res
$CC -O2 -Wall -Wextra -mwindows -DUNICODE -D_UNICODE -static -static-libgcc -static-libstdc++ \
    src/rabbit.cpp build/rabbit.res \
    -o build/rabbit.scr \
    -lgdiplus -ldwmapi -lgdi32 -lmsimg32 -lole32 -luser32 -lshell32
cp build/rabbit.scr ./rabbit.scr
ls -la rabbit.scr
