#!/bin/bash
# 把 /opt/kde6 里需要被系统组件读取的文件软链到系统路径。
#
# 系统里只允许"链接/启动脚本"：polkitd 只读 /usr/share/polkit-1/actions，
# dbus-daemon 只读 /usr/share/dbus-1/system.d，systemd 用户单元与 wayland
# session 入口同理。KDE6 全部装在 /opt/kde6，必须显式软链。
#
#   ./kde6-integration-symlinks.sh            # 幂等执行
#
# 典型症状（缺这些链接时）：
#   * 托盘亮度滑块消失、EDR 亮度失效：
#     backlighthelper: Connection ... is not allowed to own the service
#   * 系统设置里缺 KDE6 的提权操作（kio.admin / kf6auth 等）
set -euo pipefail

PREFIX=${KDEPREFIX:-/opt/kde6}

# postinst 里以 root 运行，用户手动跑时才需要 sudo；干净 chroot 里没有 sudo。
if [ "$(id -u)" -eq 0 ]; then SUDO=(); else SUDO=(sudo); fi
run() { "${SUDO[@]}" "$@"; }

link_dir() { # <src-dir> <dst-dir> <glob>
  local src=$1 dst=$2 pat=$3 f b
  [ -d "$src" ] || return 0
  run mkdir -p "$dst"
  for f in "$src"/$pat; do
    [ -e "$f" ] || continue
    b=$(basename "$f")
    if [ -e "$dst/$b" ] && [ ! -L "$dst/$b" ]; then
      echo "  keep real file: $dst/$b"
      continue
    fi
    [ -L "$dst/$b" ] || run ln -s "$f" "$dst/$b"
  done
}

echo "== polkit actions"
link_dir "$PREFIX/share/polkit-1/actions" /usr/share/polkit-1/actions '*.policy'

echo "== dbus system policies"
link_dir "$PREFIX/share/dbus-1/system.d" /usr/share/dbus-1/system.d '*.conf'
run systemctl reload dbus 2>/dev/null || true

echo "== systemd user units"
link_dir "$PREFIX/lib/systemd/user" /usr/lib/systemd/user '*.service'
link_dir "$PREFIX/lib/systemd/user" /usr/lib/systemd/user '*.target'

echo "== wayland session entry"
# session 包会直接安装 /usr/share/wayland-sessions/plasma6-kde6.desktop；
# 这里只做兜底：若包没装但 /opt 有同名文件，则软链过去。
if [ ! -e /usr/share/wayland-sessions/plasma6-kde6.desktop ] && \
   [ -f "$PREFIX/share/wayland-sessions/plasma6-kde6.desktop" ]; then
  run mkdir -p /usr/share/wayland-sessions
  run ln -sf "$PREFIX/share/wayland-sessions/plasma6-kde6.desktop" \
              /usr/share/wayland-sessions/plasma6-kde6.desktop
fi

echo "done; 如亮度仍未恢复: systemctl --user restart plasma-powerdevil.service"
