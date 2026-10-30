#!/usr/bin/env bash
# 05-full-docs.sh —— 关掉 dpkg 的 path-exclude，让 man 手册 / 文档 / 翻译真正落盘
#
# 背景：Ubuntu 的最小化镜像（ubuntu-base、cloud image 等）里带着
#     /etc/dpkg/dpkg.cfg.d/excludes
# 内容形如：
#     path-exclude=/usr/share/man/*
#     path-exclude=/usr/share/doc/*
#     path-include=/usr/share/doc/*/copyright
#     path-exclude=/usr/share/locale/*/LC_MESSAGES/*.mo
# dpkg 在**解包时**按这些规则把文件直接丢掉，所以：
#   * 它只影响"之后安装的包"，对已经装好的包无效；
#   * 想让已装包补回内容只能 `apt-get install --reinstall`（官方 unminimize 就是这么做的）。
# 因此本脚本必须排在所有 apt 安装之前（workflow 里排在 10-base.sh 之前）。
#
# 注意：删掉这个文件是安全的 —— 它是 dpkg 的 conffile，dpkg 不会因为升级/重装
# 而把它"补回来"（补回缺失 conffile 需要显式 --force-confmiss）。
#
# 环境变量：
#   FULL_DOCS=true|false（默认 false = 什么都不做，对应 rootfs-full-docs.yml 的 full_docs 开关）
#     只有显式 true 才会删 excludes。默认关闭是为了让 rootfs.yml（不传该变量）完全不受影响。
#   RESTORE_BASE_DOCS=true|false（默认 true，仅在 FULL_DOCS=true 时生效）
#     引导阶段（ubuntu-base tarball / mmdebstrap）已经装好的基础包，其 man/doc/locale
#     在解包时就被丢掉了，需要重装一遍才能补回。关掉可省一次 apt update + 重装。
#
# 在 chroot 内执行:
#   chroot "$MOUNT" /root/sheng-build/in-chroot/05-full-docs.sh
#   FULL_DOCS=true chroot "$MOUNT" ...   # 手动跑时需显式打开
set -euo pipefail

BUILD_DIR="${BUILD_DIR:-/root/sheng-build}"
# shellcheck source=/dev/null
source "$BUILD_DIR/common/distro-env.sh"
# shellcheck source=/dev/null
source "$BUILD_DIR/in-chroot/lib-apt.sh"

# 开关（rootfs-full-docs.yml 的 full_docs，经 build.env 注入）；未设置时保持原样不动
if [[ "${FULL_DOCS:-false}" != "true" ]]; then
  log "FULL_DOCS=${FULL_DOCS:-<未设置>}：保留 dpkg 的 path-exclude（man/文档/翻译不安装），跳过"
  exit 0
fi

CFG_DIR=/etc/dpkg/dpkg.cfg.d
RESTORE_BASE_DOCS="${RESTORE_BASE_DOCS:-true}"

# 不写死文件名：Ubuntu 上叫 excludes，Debian 系衍生镜像里可能叫 01_nodoc / nodoc，
# 统一按"文件里是否含 path-exclude 指令"判定。第一遍删除，第二遍用于清理
# 重装基础包时可能被复现的配置。
strip_excludes() {
  local f hit=0
  [[ -d "$CFG_DIR" ]] || return 0
  while IFS= read -r -d '' f; do
    grep -qE '^[[:space:]]*path-(exclude|include)' "$f" 2>/dev/null || continue
    log "删除 ${f}（原内容如下）"
    sed 's/^/    /' "$f" 2>/dev/null || true
    rm -f "$f"
    # 函数在 if 里被调用，errexit 不生效 —— 这里显式判定是否真的删掉了
    [[ -e "$f" ]] || hit=1
  done < <(find "$CFG_DIR" -maxdepth 1 -type f -print0 2>/dev/null)
  [[ "$hit" -eq 1 ]]
}

log "关闭 dpkg 的 path-exclude（${CFG_DIR}）"
if strip_excludes; then
  log "已删除 path-exclude 配置"
else
  warn "${CFG_DIR} 下没有可删除的 path-exclude 配置（引导方式可能是 mmdebstrap，本来就没有；也可能是删除失败，见下一条断言）"
fi

# 最小化镜像还会把 man 二进制 divert 成 /usr/bin/man.REAL 并放一个打印
# "This system has been minimized" 的假 /usr/bin/man（与官方 unminimize 的处理一致）
if command -v dpkg-divert >/dev/null 2>&1 \
   && [[ "$(dpkg-divert --truename /usr/bin/man 2>/dev/null || true)" == "/usr/bin/man.REAL" ]]; then
  log "移除 /usr/bin/man 的 divert（还原真正的 man）"
  rm -f /usr/bin/man
  dpkg-divert --quiet --remove --rename /usr/bin/man || warn "移除 man 的 divert 失败（不致命）"
fi

# 已装包补内容：引导阶段的包在解包时就已经被丢过一遍文件了
if [[ "$RESTORE_BASE_DOCS" == "true" ]]; then
  prepare_apt
  apt_update
  mapfile -t installed < <(
    dpkg-query -W -f='${db:Status-Abbrev}\t${Package}\n' 2>/dev/null \
      | awk -F'\t' '$1 ~ /^ii/ {print $2}' | sort -u
  )
  if [[ "${#installed[@]}" -eq 0 ]]; then
    warn "读不到已装包列表，跳过重装"
  else
    log "重装 ${#installed[@]} 个已装包以补回 man/doc/locale（RESTORE_BASE_DOCS=$RESTORE_BASE_DOCS）"
    # 分批：一次几百个包名会撞 ARG_MAX，也会让单个失败拖垮整批
    for ((i = 0; i < ${#installed[@]}; i += 50)); do
      apt_install --reinstall "${installed[@]:i:50}" \
        || warn "重装第 $((i / 50 + 1)) 批失败（已忽略，该批包的文档会缺失）"
    done
  fi
  # 重装过程中若某个包的 conffile 被复现，这里再清一遍
  strip_excludes >/dev/null || true
fi

# 硬断言：残留任何 path-exclude 都会让后面的安装静默丢文件
leftover=0
if [[ -d "$CFG_DIR" ]]; then
  while IFS= read -r -d '' f; do
    if grep -qE '^[[:space:]]*path-exclude' "$f" 2>/dev/null; then
      printf '    %s\n' "$f"
      leftover=1
    fi
  done < <(find "$CFG_DIR" -maxdepth 1 -type f -print0 2>/dev/null)
fi
[[ "$leftover" -eq 0 ]] || die "仍存在 path-exclude 配置，man/文档/翻译会被丢弃"

log "dpkg path-exclude 已关闭（之后的包会正常安装 man/文档/翻译）"
