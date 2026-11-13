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

link_dir() { # <src-dir> <dst-dir> <glob>
  local src=$1 dst=$2 pat=$3 f b
  [ -d "$src" ] || return 0
  sudo mkdir -p "$dst"
  for f in "$src"/$pat; do
    [ -e "$f" ] || continue
    b=$(basename "$f")
    if [ -e "$dst/$b" ] && [ ! -L "$dst/$b" ]; then
      echo "  keep real file: $dst/$b"
      continue
    fi
    [ -L "$dst/$b" ] || sudo ln -s "$f" "$dst/$b"
  done
}

echo "== polkit actions"
link_dir "$PREFIX/share/polkit-1/actions" /usr/share/polkit-1/actions '*.policy'

echo "== dbus system policies"
link_dir "$PREFIX/share/dbus-1/system.d" /usr/share/dbus-1/system.d '*.conf'
sudo systemctl reload dbus 2>/dev/null || true

echo "== systemd user units"
link_dir "$PREFIX/lib/systemd/user" /usr/lib/systemd/user '*.service'
link_dir "$PREFIX/lib/systemd/user" /usr/lib/systemd/user '*.target'

echo "== wayland session entry"
if [ -f "$PREFIX/share/wayland-sessions/plasma6-kde6.desktop" ]; then
  sudo mkdir -p /usr/share/wayland-sessions
  sudo ln -sf "$PREFIX/share/wayland-sessions/plasma6-kde6.desktop" \
              /usr/share/wayland-sessions/plasma6-kde6.desktop
fi

echo "done; 如亮度仍未恢复: systemctl --user restart plasma-powerdevil.service"
