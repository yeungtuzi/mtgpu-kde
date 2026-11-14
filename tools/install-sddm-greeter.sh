#!/bin/bash
# 安装 SDDM（/opt/sddm）+ mtgpu-kde 主题 + Plymouth 交接单元。
# 前提：SDDM 0.21.0 已按 docs/sddm-greeter.md 编译安装到 /opt/sddm，且打了 fastpath 补丁。
set -euo pipefail

SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SDDM_PREFIX="${SDDM_PREFIX:-/opt/sddm}"
KDE_PREFIX="${KDE_PREFIX:-/opt/kde6}"

[[ $(id -u) -eq 0 ]] || { echo "请用 root 运行" >&2; exit 1; }
[[ -x "$SDDM_PREFIX/bin/sddm" ]] || { echo "找不到 $SDDM_PREFIX/bin/sddm（先编译安装 SDDM）" >&2; exit 1; }

echo "==> greeter 入口链接（Qt6 构建只有 sddm-greeter-qt6）"
ln -sf sddm-greeter-qt6 "$SDDM_PREFIX/bin/sddm-greeter"

echo "==> 安装主题 mtgpu-kde"
install -d -m 755 "$SDDM_PREFIX/share/sddm/themes"
rm -rf "$SDDM_PREFIX/share/sddm/themes/mtgpu-kde"
cp -a "$SRC/sddm/theme-mtgpu-kde" "$SDDM_PREFIX/share/sddm/themes/"
chown -R root:root "$SDDM_PREFIX/share/sddm/themes/mtgpu-kde"
chmod -R a+rX "$SDDM_PREFIX/share/sddm/themes/mtgpu-kde"

echo "==> 会话清单：Plasma 6.8 (默认) / GNOME / Plasma failsafe"
install -d -m 755 /usr/share/mtgpu-kde/wayland-sessions /usr/share/mtgpu-kde/xsessions
ln -sf /usr/share/wayland-sessions/plasma6-kde6.desktop \
       /usr/share/mtgpu-kde/wayland-sessions/plasma6-kde6.desktop
install -m 644 "$SRC/sddm/sessions/gnome.desktop" /usr/share/mtgpu-kde/wayland-sessions/gnome.desktop
install -m 644 "$SRC/sddm/sessions/plasma6-kde6-failsafe.desktop" \
       /usr/share/mtgpu-kde/wayland-sessions/plasma6-kde6-failsafe.desktop

echo "==> 配置 /etc/sddm.conf.d/10-mtgpu.conf"
install -d -m 755 /etc/sddm.conf.d
if [[ -f /etc/sddm.conf.d/10-mtgpu.conf ]]; then
    cp -a /etc/sddm.conf.d/10-mtgpu.conf "/etc/sddm.conf.d/10-mtgpu.conf.bak-$(date +%Y%m%d%H%M%S)" || true
fi
install -m 644 "$SRC/sddm/10-mtgpu.conf" /etc/sddm.conf.d/10-mtgpu.conf
# SDDM 会读取目录下所有文件，备份不能留在这里
find /etc/sddm.conf.d -maxdepth 1 -name '*.bak*' -exec mv {} /root/ \;

echo "==> Plymouth 交接单元"
install -m 755 "$SRC/sddm/plymouth-handoff" "$KDE_PREFIX/libexec/plymouth-handoff"
install -m 644 "$SRC/sddm/plymouth-handoff.service" /etc/systemd/system/plymouth-handoff.service
install -m 644 "$SRC/sddm/sddm.service" /etc/systemd/system/sddm.service
install -d -m 755 /etc/systemd/system/plymouth-quit.service.d
systemctl mask plymouth-quit.service >/dev/null 2>&1 || true

systemctl daemon-reload
systemctl enable sddm.service plymouth-handoff.service
ln -sf /etc/systemd/system/sddm.service /etc/systemd/system/display-manager.service

cat <<'EOF'

完成。还需要（手动/按需）：
  1) 关闭 ksplash（避免兔头播两遍）：
       systemctl --user mask plasma-ksplash.service
  2) 下次启动/重启后生效；回退见 docs/sddm-greeter.md 末尾。
EOF
