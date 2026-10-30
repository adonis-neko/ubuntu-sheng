#!/usr/bin/env bash
# 35-fcitx5.sh —— 可选：安装 Fcitx5 中文输入法（**只装包，不做任何配置**）
#
# 由 rootfs-extend.yml 的 fcitx5 开关控制（经 /root/build.env 注入 FCITX5），
# 未设置或不为 true 时直接跳过，因此不影响 rootfs.yml 的构建结果。
#
# 职责边界：本脚本只负责把包装上并确认装成功。输入法组、候选词、快捷键、
# 自启动等一律留给用户进桌面用 fcitx5-configtool 自己配 —— 镜像里不写
# /etc/environment、不写 /etc/environment.d、不写 XDG autostart、不预置 profile。
#
# 这个取舍的副作用要知道：fcitx5 包**不自带** /etc/xdg/autostart 项
# （实测 fcitx5_5.1.19-1 只有 /usr/share/applications/*.desktop），所以登录后
# 输入法不会自动启动。用户首次需要在桌面里手动启动一次 Fcitx 5，
# 或自己在「设置 → 应用 → 自启动」里加上。
#
# 环境变量（由 /root/build.env 提供）：
#   FCITX5       true/false（默认 false）
#   DESKTOP      GNOME / KDE Plasma / Lomiri / server
#
# 在 chroot 内执行:
#   chroot "$MOUNT" /root/sheng-build/in-chroot/35-fcitx5.sh
set -euo pipefail

BUILD_DIR="${BUILD_DIR:-/root/sheng-build}"
# shellcheck source=/dev/null
source "$BUILD_DIR/common/distro-env.sh"
# shellcheck source=/dev/null
source "$BUILD_DIR/in-chroot/lib-apt.sh"

if [[ "${FCITX5:-false}" != "true" ]]; then
  log "FCITX5=${FCITX5:-<未设置>}：不安装 Fcitx5，跳过"
  exit 0
fi

if [[ "${DESKTOP:-server}" == "server" ]]; then
  warn "desktop=server：仍然安装 Fcitx5（控制台/TTY 下可用，但通常不需要）"
fi

# ---------------------------------------------------------------------------
# 1) 必需项：缺任何一个都算功能缺失，安装失败直接让构建失败
# ---------------------------------------------------------------------------
log "安装 Fcitx5（必需项）"
apt_update
apt_install_list "$BUILD_DIR/lists/fcitx5.list"

# ---------------------------------------------------------------------------
# 2) 可选组件：配置工具与各前端，缺失只告警
# ---------------------------------------------------------------------------
log "安装 Fcitx5 可选组件（配置工具 / 前端，缺失只告警）"
apt_install_list_best_effort "$BUILD_DIR/lists/fcitx5-extra.list"

# 说明：不需要按桌面环境裁剪 Qt 前端 —— fcitx5 的 Recommends 里是 fcitx5-frontend-all，
# 它 Depends gtk3/gtk4/qt5/qt6 四个前端，apt 默认装 Recommends，所以 Qt 前端必然进来。
# kde-config-fcitx5 只是 Suggests（默认不装），且会拖进 KDE Frameworks，故仅 KDE 下显式装。
if [[ "${DESKTOP:-}" == "KDE Plasma" ]]; then
  apt_install_best_effort kde-config-fcitx5
fi

if [[ "${DESKTOP:-}" == "Lomiri" ]]; then
  warn "Lomiri 的文本输入走自己的 Qt IM 链路，Fcitx5 可能只能在部分应用里生效；若不可用请改回 Lomiri 自带输入法"
fi

# ---------------------------------------------------------------------------
# 3) 自检：只验证"包装好了"，不验证任何配置文件（本脚本不写配置）
# ---------------------------------------------------------------------------
[[ -x /usr/bin/fcitx5 ]] || die "缺少 /usr/bin/fcitx5（Fcitx5 未安装成功）"
dpkg-query -W -f='${Status}' fcitx5-chinese-addons 2>/dev/null | grep -q "install ok installed" \
  || die "缺少 fcitx5-chinese-addons（没有拼音/中文输入能力）"

log "Fcitx5 已安装: $(dpkg-query -W -f='${Version}' fcitx5 2>/dev/null || echo '版本未知')"
log "未做任何配置（按需求）：输入法组 / 快捷键 / 自启动请进桌面用 fcitx5-configtool 自行设置"
