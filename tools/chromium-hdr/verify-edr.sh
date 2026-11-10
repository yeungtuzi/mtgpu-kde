#!/bin/bash
# Verify that the built Chromium reports the compositor's real headroom.
set -uo pipefail

CHROME="${1:-/opt/chromium-hdr/chrome}"
LOG="${2:-$HOME/chromium-build/edr-run.log}"

[ -x "$CHROME" ] || { echo "missing $CHROME" >&2; exit 1; }

CHROME_EDR_DEBUG=1 "$CHROME" \
  --ozone-platform=wayland \
  --enable-features=UseDisplaySDRMaxLuminanceNits \
  --no-first-run --no-default-browser-check \
  --user-data-dir="$HOME/.cache/chromium-hdr-profile" \
  "$HOME/build/kwin-hdr/tools/hdr-bars.mp4" >"$LOG" 2>&1 &
PID=$!
echo "chrome pid $PID, log $LOG"
echo "watch:  grep '\\[EDR\\]' $LOG | tail"
echo "compare with: edr-pattern (2.5x headroom reference)"
wait $PID
