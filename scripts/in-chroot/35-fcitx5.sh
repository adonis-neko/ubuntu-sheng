#!/usr/bin/env bash
# 35-fcitx5.sh —— 可选：安装 Fcitx5 中文输入法，并配好"能起来"所需的自启动与环境变量
#
# 由 rootfs-extend.yml 的 fcitx5 开关控制（经 /root/build.env 注入 FCITX5），
# 未设置或不为 true 时直接跳过，因此不影响 rootfs.yml 的构建结果。
#
# 本脚本**只负责装包 + 让输入法能在登录后自动跑起来**；输入法组/候选词/快捷键
# 等个性化设置留给用户进桌面用 fcitx5-configtool 自己配，不在镜像里预置 profile。
#
# 为什么这两步非做不可（以下事实均已在 26.04/resolute 的 deb 上实测）：
#   1) fcitx5 包**不含** /etc/xdg/autostart 项（解开 fcitx5_5.1.19-1 只有
#      /usr/share/applications/{org.fcitx.Fcitx5,fcitx5-configtool,fcitx5-wayland-launcher}.desktop）
#      —— 不自己写一份的话，登录进桌面后输入法根本不会启动；
#   2) 输入法变量必须在**会话启动前**就位：systemd 会话读 /etc/environment.d，
#      greetd / 传统 X 会话读 PAM 的 /etc/environment，两处都写才覆盖全部启动路径。
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
# 1) 安装
# ---------------------------------------------------------------------------
log "安装 Fcitx5（必需项）"
apt_update
apt_install_list "$BUILD_DIR/lists/fcitx5.list"

log "安装 Fcitx5 可选组件（frontend / 配置工具，缺失只告警）"
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

[[ -x /usr/bin/fcitx5 ]] || die "缺少 /usr/bin/fcitx5（Fcitx5 未安装成功）"
dpkg-query -W -f='${Status}' fcitx5-chinese-addons 2>/dev/null | grep -q "install ok installed" \
  || die "缺少 fcitx5-chinese-addons（没有拼音/中文输入能力）"
log "Fcitx5 版本: $(dpkg-query -W -f='${Version}' fcitx5 2>/dev/null || echo '未知')"

# ---------------------------------------------------------------------------
# 2) 输入法环境变量（会话启动前生效）
# ---------------------------------------------------------------------------
# Wayland 原生客户端走 text-input 协议，不依赖这些变量；它们主要服务
# X11 / XWayland 应用（firefox、旧版 GTK 程序等），所以四个都写上是安全且必要的。
log "写入输入法环境变量（/etc/environment.d + /etc/environment）"
install -d /etc/environment.d
cat > /etc/environment.d/90-fcitx5.conf <<'EOF'
# 由 ubuntu-sheng 的 35-fcitx5.sh 写入：把输入法指向 fcitx5
XMODIFIERS=@im=fcitx
QT_IM_MODULE=fcitx
GTK_IM_MODULE=fcitx
SDL_IM_MODULE=fcitx
EOF

# /etc/environment 由 PAM（pam_env）读取，覆盖 greetd / X11 这类不经 systemd user
# manager 的会话；用标记块包起来，重复执行不会叠加。
if ! grep -q '^# >>> ubuntu-sheng fcitx5 >>>$' /etc/environment 2>/dev/null; then
  {
    printf '\n# >>> ubuntu-sheng fcitx5 >>>\n'
    printf 'XMODIFIERS=@im=fcitx\n'
    printf 'QT_IM_MODULE=fcitx\n'
    printf 'GTK_IM_MODULE=fcitx\n'
    printf 'SDL_IM_MODULE=fcitx\n'
    printf '# <<< ubuntu-sheng fcitx5 <<<\n'
  } >> /etc/environment
fi

# ---------------------------------------------------------------------------
# 3) 自启动（fcitx5 包不带 autostart 项，必须自己写）
# ---------------------------------------------------------------------------
if [[ -e /etc/xdg/autostart/fcitx5.desktop ]]; then
  log "已有 /etc/xdg/autostart/fcitx5.desktop（由包提供），不覆盖"
else
  log "写入 /etc/xdg/autostart/fcitx5.desktop"
  install -d /etc/xdg/autostart
  cat > /etc/xdg/autostart/fcitx5.desktop <<'EOF'
[Desktop Entry]
Type=Application
Name=Fcitx 5
Name[zh_CN]=Fcitx 5 输入法
Comment=Start Input Method
Comment[zh_CN]=启动输入法
Exec=fcitx5 -d --replace
Icon=org.fcitx.Fcitx5
Terminal=false
NoDisplay=true
X-GNOME-Autostart-Phase=Applications
X-GNOME-AutoRestart=false
X-KDE-autostart-after=panel
EOF
fi

# ---------------------------------------------------------------------------
# 4) 自检
# ---------------------------------------------------------------------------
[[ -e /etc/xdg/autostart/fcitx5.desktop ]] || die "autostart 项缺失（登录后输入法不会启动）"
[[ -e /etc/environment.d/90-fcitx5.conf ]] || die "输入法环境变量未写入"
command -v fcitx5-remote >/dev/null 2>&1 || warn "fcitx5-remote 不存在（不影响输入，只是排查时少个工具）"

log "Fcitx5 安装完成（已配置 autostart + 环境变量）"
log "输入法组与拼音请在桌面里用 fcitx5-configtool 自行添加（镜像不预置 profile）"
