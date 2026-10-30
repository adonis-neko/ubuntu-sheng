#!/usr/bin/env bash
# 36-cjk-fonts.sh —— 可选：给 GNOME 补中文字体
#
# 背景：lists/gnome.list 不用 ubuntu-desktop 元包（它硬依赖 snapd），因此拿不到
# 元包顺带的那批字体。实测 26.04 / 26.10 arm64 的 GNOME 依赖闭包里只有
# fonts-adwaita、fonts-dejavu，**没有任何 CJK 字体** —— LANGUAGE=zh_CN 时
# 界面文字会整片变成方块。KDE 的闭包自带 fonts-noto-cjk，所以本脚本只对 GNOME 生效。
#
# 由 rootfs-extend.yml 的 cjk_fonts 开关控制（经 /root/build.env 注入 CJK_FONTS）。
# 关闭或非 GNOME 时直接跳过，不影响 rootfs.yml 的构建结果。
#
# 环境变量（由 /root/build.env 提供）：
#   CJK_FONTS    true/false（默认 false）
#   DESKTOP      GNOME / KDE Plasma / Lomiri / server
#
# 在 chroot 内执行:
#   chroot "$MOUNT" /root/sheng-build/in-chroot/36-cjk-fonts.sh
set -euo pipefail

BUILD_DIR="${BUILD_DIR:-/root/sheng-build}"
# shellcheck source=/dev/null
source "$BUILD_DIR/common/distro-env.sh"
# shellcheck source=/dev/null
source "$BUILD_DIR/in-chroot/lib-apt.sh"

if [[ "${CJK_FONTS:-false}" != "true" ]]; then
  log "CJK_FONTS=${CJK_FONTS:-<未设置>}：不安装中文字体，跳过"
  exit 0
fi

# KDE / Lomiri / server 不需要：KDE 的闭包已自带 fonts-noto-cjk
if [[ "${DESKTOP:-server}" != "GNOME" ]]; then
  log "DESKTOP=${DESKTOP:-server}：不需要额外中文字体（非 GNOME），跳过"
  exit 0
fi

log "为 GNOME 安装中文字体"
apt_update
apt_install_list "$BUILD_DIR/lists/cjk-fonts.list"

# 校验：字体文件必须真的落地（包"装了"但字体没注册，界面上照样是方块）
if find /usr/share/fonts -iname '*CJK*' -print -quit 2>/dev/null | grep -q .; then
  log "中文字体已就位: $(find /usr/share/fonts -iname '*CJK*' -print -quit 2>/dev/null)"
else
  die "fonts-noto-cjk 已安装但 /usr/share/fonts 下找不到 CJK 字体文件"
fi

# 刷新字体缓存（包 postinst 通常已经做过，这里只兜底；失败不影响结果）
if command -v fc-cache >/dev/null 2>&1; then
  fc-cache -f >/dev/null 2>&1 || warn "fc-cache 执行失败（不影响已安装的字体）"
fi

log "GNOME 中文字体安装完成"
