#!/bin/bash
label=$1; shift
export XDG_RUNTIME_DIR=/run/user/1000 WAYLAND_DISPLAY=wayland-1 DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/1000/bus LIBVA_DRIVER_NAME=mtgpu
cd /home/lf/chromium-build/src/out/hdr
for pair in h264:/home/lf/h264.html hevc:/home/lf/edr-hevc.html vp9:/home/lf/vp9.html av1:/home/lf/av1.html; do
  name=${pair%%:*}; url=${pair#*:}
  pkill -x chrome 2>/dev/null; sleep 2
  timeout 40 ./chrome --ozone-platform=wayland --no-sandbox --allow-file-access-from-files \
    --window-size=900,600 --autoplay-policy=no-user-gesture-required "$@" \
    --user-data-dir=$(mktemp -d) "file://$url" >/dev/null 2>&1 &
  sleep 12
  peak=0; nz=0
  for i in $(seq 1 8); do
    d=$(mthreads-gmi -q 2>/dev/null | sed -n '/Utilization/,+5p' | grep Decoder | grep -oE '[0-9.]+' | head -1)
    if [ -n "$d" ]; then
      awk -v a="$peak" -v b="$d" 'BEGIN{exit !(b>a)}' && peak=$d
      awk -v b="$d" 'BEGIN{exit !(b>0)}' && nz=$((nz+1))
    fi
    sleep 2
  done
  echo "$label $name vpu_peak=$peak% nonzero=$nz/8"
done
pkill -x chrome 2>/dev/null
