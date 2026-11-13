#!/bin/bash
# mtgpu-kde 安装器：检查环境 → 安装 deb → 建立系统软链 → 验证 → 给出回退方法。
#
#   ./install-kde6-mtgpu.sh                 # 安装当前目录下的 kde6-mtgpu-*.deb
#   ./install-kde6-mtgpu.sh --debs DIR      # 指定 deb 目录
#   ./install-kde6-mtgpu.sh --check         # 只做环境/依赖检查，不安装
#   ./install-kde6-mtgpu.sh --purge-kde5    # 安装前清理 Plasma 5/KF5（先 dry-run 确认）
#   ./install-kde6-mtgpu.sh --install-deps  # 缺失的系统依赖用 apt 安装（默认只警告）
#
# 原则：只把文件装进 /opt/kde6，系统里只创建软链；不碰 /usr 的库。
set -euo pipefail

DEBDIR=$(pwd)
DO_CHECK=0
DO_PURGE=0
DO_DEPS=0

while [ $# -gt 0 ]; do
  case $1 in
    --debs) DEBDIR=$2; shift 2 ;;
    --check) DO_CHECK=1; shift ;;
    --purge-kde5) DO_PURGE=1; shift ;;
    --install-deps) DO_DEPS=1; shift ;;
    -h|--help) sed -n '2,12p' "$0"; exit 0 ;;
    *) echo "unknown option: $1"; exit 1 ;;
  esac
done

say()  { printf '\033[1m== %s\033[0m\n' "$*"; }
warn() { printf '\033[1;33m[warn]\033[0m %s\n' "$*"; }
err()  { printf '\033[1;31m[err]\033[0m %s\n' "$*"; }
ok()   { printf '\033[1;32m[ok]\033[0m %s\n' "$*"; }

fatal=0
need_pkg() { # <deb-package> <human name> <install cmd>
  local p=$1 name=$2 cmd=$3
  if dpkg -s "$p" >/dev/null 2>&1; then
    ok "$name ($p)"
  else
    warn "缺少 $name ($p)  ->  sudo apt install $cmd"
    fatal=1
  fi
}

all_missing=()
check_pkg_lenient() { # 运行时组件：缺了只是功能缺失，不阻止安装
  local p=$1 name=$2 cmd=$3
  if dpkg -s "$p" >/dev/null 2>&1; then
    ok "$name ($p)"
  else
    warn "缺少 $name ($p)（对应托盘功能会不可用） -> sudo apt install $cmd"
    all_missing+=("$cmd")
  fi
}

say "1) 系统环境"
case "$(uname -m)" in aarch64|arm64) ok "arch $(uname -m)";; *) err "需要 arm64，当前 $(uname -m)"; fatal=1;; esac
. /etc/os-release 2>/dev/null || true
if [ "${VERSION_ID:-}" = "24.04" ]; then ok "Ubuntu $VERSION_ID"; else warn "建议 Ubuntu 24.04，当前 ${VERSION_ID:-unknown}"; fi
if [ -e /dev/dri/card0 ]; then ok "DRM 设备存在"; else warn "未发现 /dev/dri/card0（MTT 驱动没加载？）"; fi
[ -d /opt/kde6 ] && ok "/opt/kde6 已存在" || warn "/opt/kde6 不存在（安装后创建）"
free_kb=$(df -Pk /opt 2>/dev/null | awk 'NR==2{print $4}')
[ -n "$free_kb" ] && [ "$free_kb" -gt 4194304 ] && ok "/opt 剩余空间 $((free_kb/1024)) MiB" || warn "/opt 剩余空间不足 4 GiB"

say "2) 必需的系统组件"
need_pkg dbus "D-Bus" "dbus"
need_pkg polkitd "polkit" "polkitd"
need_pkg network-manager "NetworkManager" "network-manager"
if systemctl is-active --quiet gdm3 2>/dev/null || systemctl is-enabled --quiet gdm3 2>/dev/null; then
  ok "显示管理器 gdm3"
else
  warn "没有启用 gdm3（KDE6 的 wayland session 需要显示管理器来拉起）"
fi

say "3) 托盘/功能运行时依赖（缺失只影响对应功能）"
check_pkg_lenient bluez "蓝牙服务" "bluez"
check_pkg_lenient pipewire-pulse "PipeWire PulseAudio" "pipewire-pulse"
check_pkg_lenient libcanberra0 "canberra 音效" "libcanberra0"
check_pkg_lenient fcitx5 "输入法框架" "fcitx5 fcitx5-chinese-addons fcitx5-frontend-qt6"
check_pkg_lenient xdg-desktop-portal "XDG portal" "xdg-desktop-portal"

say "4) Plasma 5 / KF5 污染检查"
kf5=$(dpkg -l 2>/dev/null | awk '/^ii/ {print $2}' | grep -cE '^(libkf5|kf5|plasma-|kwin-|breeze)' || true)
plasmoids5=$(ls /usr/share/plasma/plasmoids 2>/dev/null | wc -l)
if [ "$kf5" -eq 0 ] && [ "$plasmoids5" -eq 0 ]; then
  ok "未发现 Plasma 5/KF5 残留"
else
  warn "发现 KF5 包 $kf5 个、/usr/share/plasma/plasmoids 条目 $plasmoids5 个"
  warn "这些 5.27 的 plasmoid 会让 KDE6 托盘项消失，建议运行: $0 --purge-kde5"
fi

if [ "$DO_PURGE" = 1 ]; then
  say "5) 清理 Plasma 5/KF5（先 dry-run）"
  "$(dirname "$0")/purge-plasma5.sh" || true
fi

if [ "$DO_DEPS" = 1 ] && [ ${#all_missing[@]} -gt 0 ]; then
  say "6) 安装缺失的可选依赖"
  sudo apt-get install -y "${all_missing[@]}"
fi

if [ "$DO_CHECK" = 1 ]; then
  say "仅检查模式，结束"
  [ "$fatal" = 0 ] || { err "有空缺的必需组件"; exit 1; }
  exit 0
fi

shopt -s nullglob
debs=("$DEBDIR"/kde6-mtgpu-*.deb)
shopt -u nullglob
[ ${#debs[@]} -gt 0 ] || { err "$DEBDIR 下没有 kde6-mtgpu-*.deb"; exit 1; }

if [ "$fatal" != 0 ]; then
  err "必需组件不满足，先补齐再安装（或加 --install-deps 自动装可选依赖）"
  exit 1
fi

say "安装 ${#debs[@]} 个 deb"
sudo dpkg -i "${debs[@]}" || sudo apt-get -f install -y

say "建立系统软链（session / systemd / polkit / dbus）"
sudo "$(dirname "$0")/kde6-integration-symlinks.sh"

say "验证"
[ -f /usr/share/wayland-sessions/plasma6-kde6.desktop ] && ok "wayland session 入口" || warn "缺 wayland session 入口"
[ -e /opt/kde6/qml/org/kde/bluezqt ] && ok "bluezqt QML" || warn "缺 org.kde.bluezqt（蓝牙 applet 会报错）"
[ -e /opt/kde6/plugins/plasma/applets/org.kde.plasma.networkmanagement.so ] && ok "网络 applet" || warn "缺网络 applet"
[ -e /opt/kde6/plugins/plasma/applets/org.kde.plasma.volume.so ] && ok "音量 applet" || warn "缺音量 applet"
[ -e /usr/share/polkit-1/actions/org.kde.powerdevil.backlighthelper.policy ] && ok "背光 polkit 策略" || warn "缺背光 polkit 策略（亮度/EDR 会失效）"
[ -e /usr/share/dbus-1/system.d/org.kde.powerdevil.backlighthelper.conf ] && ok "背光 dbus 策略" || warn "缺背光 dbus 策略（亮度/EDR 会失效）"

say "完成"
cat <<'EOT'
回退方法：
  * 注销后在 GDM 里选 "GNOME" 会话即可用回预装桌面；
  * 卸载：sudo dpkg -r kde6-mtgpu  （meta 包；依赖包可 apt autoremove）
  * 亮度/EDR 异常时：systemctl --user restart plasma-powerdevil，并检查
    /usr/share/polkit-1/actions 与 /usr/share/dbus-1/system.d 下是否有 KDE6 软链。
EOT
