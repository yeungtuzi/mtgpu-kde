#!/bin/sh
# Generate Plymouth sprite assets from the KDE ksplash theme (org.aibook.splash).
#
# Plymouth cannot scale images at runtime, and it auto-enables HiDPI
# (device_scale=2) on panels >= HIDPI_MIN_WIDTH/HEIGHT.  On this machine the
# 2880x1800 panel is reported as a logical 1440x900 surface, so the ksplash
# icon size min(W/4, H/2) = 360 logical => 720 physical.  aibook.script
# therefore uses the 360 px assets; 720 px ones are generated for scale=1.
#
# Usage: gen-assets.sh <ksplash-images-dir> <output-dir>
set -eu
SRC=${1:?ksplash images dir (org.aibook.splash/contents/splash/images)}
OUT=${2:?output dir}
mkdir -p "$OUT"
for size in 360 720; do
    for name in icon-gray q-tl q-tr q-br q-bl; do
        convert "$SRC/$name.png" -resize "${size}x${size}" -strip "$OUT/$name-$size.png"
    done
done
