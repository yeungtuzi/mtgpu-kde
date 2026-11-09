#!/bin/bash
# Build the Plasma 6.8.2 core pieces into /opt/kde6, including the local
# EDR peak-luminance patch for kwin.
#
#   ./tools/build-core-final.sh
#
# Expects KDEPREFIX (/opt/kde6) and source trees under $HOME/kde6/src.
set -euo pipefail
source "${KDEPREFIX:-/opt/kde6}/env.sh"
HERE=$(cd "$(dirname "$0")" && pwd)
ROOT=${SRCROOT:-$HOME/kde6}
L=$ROOT/logs
mkdir -p "$L"

run() {
  local n=$1
  shift
  echo "=== $n $(date +%H:%M:%S)"
  "$HERE/build-one.sh" "$@" > "$L/final-$n.log" 2>&1
  echo "=== $n EXIT=$?"
}

# local patches must be applied before kwin is configured
"$HERE/apply-kwin-edr.sh" "$ROOT/src/kwin-6.8.2"

run kirigami-addons "$ROOT/src/kirigami-addons-1.16.0"
run knighttime "$ROOT/src/knighttime-6.8.2"
run kwin "$ROOT/src/kwin-6.8.2"
run kpipewire "$ROOT/src/kpipewire-6.8.2"
run plasma-workspace "$ROOT/src/plasma-workspace-6.8.2"
run powerdevil "$ROOT/src/powerdevil-6.8.2"
run plasma-desktop "$ROOT/src/plasma-desktop-6.8.2"
run ksystemstats "$ROOT/src/ksystemstats-6.8.2"
echo CORE_FINAL_DONE
