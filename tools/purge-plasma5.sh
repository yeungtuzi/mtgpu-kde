#!/bin/bash
# 清理 Plasma 5 / KF5（会破坏用户机器上依赖 KF5 的 KDE5 应用，务必先读 dry-run 结果）。
#
#   ./purge-plasma5.sh            # 只做 dry-run，打印将移除的包
#   ./purge-plasma5.sh --yes      # 确认后真正 purge
set -euo pipefail

YES=0
[ "${1:-}" = "--yes" ] && YES=1

mapfile -t pkgs < <(dpkg -l 2>/dev/null | awk '/^ii/ {print $2}' | \
  grep -E '^(libkf5|kf5|plasma-|kwin-|breeze|kde-|kscreen|libtaskmanager|libnotificationmanager|libkworkspace|milou|kup|sddm|powerdevil|libpowerdevil)' || true)

if [ ${#pkgs[@]} -eq 0 ]; then
  echo "没有发现 Plasma 5/KF5 包"
else
  echo "将卸载 ${#pkgs[@]} 个包："
  printf '  %s\n' "${pkgs[@]}"
  echo
  LANG=C apt-get -s purge "${pkgs[@]}" 2>&1 | grep -E '^(Purg|Remv|E:)' | head -40 || true
fi

leftover=(/usr/share/plasma /usr/share/kservices5 /usr/share/kservicetypes5)
for d in "${leftover[@]}"; do [ -e "$d" ] && echo "残留目录: $d"; done

if [ "$YES" != 1 ]; then
  echo
  echo "dry-run 结束。确认无误后执行: $0 --yes"
  exit 0
fi

[ ${#pkgs[@]} -eq 0 ] || { apt-mark unhold powerdevil 2>/dev/null || true; DEBIAN_FRONTEND=noninteractive apt-get purge -y "${pkgs[@]}"; }
for d in "${leftover[@]}"; do [ -e "$d" ] && rm -rf "$d"; done
echo "完成；重新登录以让 plasmashell 重新扫描 applet"
