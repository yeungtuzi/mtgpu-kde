#!/bin/bash
# Cross-build rabbit.scr with MinGW-w64.  Requires: gcc-mingw-w64-x86-64, python3-pil.
set -euo pipefail
cd "$(dirname "$0")"
CC=${CC:-x86_64-w64-mingw32-gcc}
WINDRES=${WINDRES:-x86_64-w64-mingw32-windres}
FRAMES=../ksplash-aibook/org.aibook.splash/contents/splash/images
mkdir -p build

python3 - "$FRAMES" <<'PY'
import sys
from PIL import Image
src = sys.argv[1]
for i in range(4):
    im = Image.open(f"{src}/frame-0{i}.png").convert("RGBA")
    bg = Image.new("RGB", im.size, (0, 0, 0))
    bg.paste(im, (0, 0), im)
    bg.save(f"build/frame-0{i}.bmp")
print("frames -> build/frame-0*.bmp")
PY

cat > build/rabbit.rc <<'RC'
101 BITMAP "frame-00.bmp"
102 BITMAP "frame-01.bmp"
103 BITMAP "frame-02.bmp"
104 BITMAP "frame-03.bmp"
RC

$WINDRES -i build/rabbit.rc -O coff -o build/rabbit.res
$CC -O2 -Wall -Wextra -mwindows \
    src/rabbit.c build/rabbit.res \
    -o build/rabbit.scr -lgdi32 -luser32 -lshell32
cp build/rabbit.scr ./rabbit.scr
ls -la rabbit.scr
