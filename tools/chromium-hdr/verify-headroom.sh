#!/bin/bash
# Compare the headroom Chromium derives with and without the panel-peak patch.
#
# Run it on the target machine with a KDE Wayland session:
#   ./verify-headroom.sh [build-dir]
# It prints the values reported by the compositor (edr-probe) next to the ones
# Chromium logs with CHROME_EDR_DEBUG=1 at 100 % and 40 % brightness.
set -u

BUILD=${1:-$HOME/chromium-build/src/out/hdr}
PROBE=${PROBE:-$HOME/build/kwin-hdr/tools/edr-probe}
KS=${KS:-/opt/kde6/bin/kscreen-doctor}
export XDG_RUNTIME_DIR=${XDG_RUNTIME_DIR:-/run/user/1000}
export WAYLAND_DISPLAY=${WAYLAND_DISPLAY:-wayland-1}
export DBUS_SESSION_BUS_ADDRESS=${DBUS_SESSION_BUS_ADDRESS:-unix:path=/run/user/1000/bus}

page=$(mktemp --suffix=.html)
cat > "$page" <<'EOF'
<!doctype html><meta charset=utf-8><body style="margin:0;background:#111">
<h1 style="color:#fff;font:48px sans-serif">headroom probe</h1></body>
EOF

run() {  # brightness label
  local b=$1 label=$2 log
  "$KS" output.1.brightness."$b" >/dev/null 2>&1
  sleep 2
  log=$(mktemp)
  ( cd "$BUILD" && CHROME_EDR_DEBUG=1 timeout 12 ./chrome \
      --ozone-platform=wayland --no-sandbox \
      --user-data-dir="$(mktemp -d)" "$page" >"$log" 2>&1 ) || true
  echo "--- brightness ${b}% ($label)"
  "$PROBE" 2>/dev/null | grep -E "LUMINANCES|TARGET_LUM" | sed 's/^/  compositor: /'
  grep -a "\[EDR\] wp_image_description" "$log" | head -2 |
      sed 's/.*\[EDR\]/  chromium: [EDR]/'
  grep -a "\[EDR\] swap" "$log" | head -1 | sed 's/.*\[EDR\]/  chromium: [EDR]/'
  rm -f "$log"
}

run 100 "peak available"
run 40  "slider low, peak must stay"
rm -f "$page"
