#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
ENABLE_SCRIPT="${ROOT_DIR}/skills/remodex-global-local-relay/scripts/enable_global_local_relay.sh"

HOSTNAME_VALUE=""
PACKAGE_SPEC="remodex@latest"
PAIR_AFTER_SWITCH="false"
GLOBAL_REMODEX_ROOT=""

log() {
  echo "[upgrade-global-remodex] $*"
}

die() {
  echo "[upgrade-global-remodex] $*" >&2
  exit 1
}

usage() {
  cat <<'EOF'
用法:
  ./skills/remodex-global-local-relay/scripts/upgrade_global_remodex.sh --hostname 192.168.1.105 [--pair]

说明:
  先升级全局 remodex，再自动重打“全局默认本地 relay”配置。

参数:
  --hostname HOSTNAME           iPhone 可访问到的局域网 IP 或 .local 主机名
  --package-spec SPEC          要安装的 npm 包版本，默认 remodex@latest
  --global-remodex-root PATH   升级后显式传给 enable_global_local_relay.sh 的全局安装目录
  --pair                       升级和切换完成后，直接打印新的二维码/配对码
  --help, -h                   显示帮助
EOF
}

require_value() {
  local flag_name="$1"
  local remaining_args="$2"
  [[ "${remaining_args}" -ge 2 ]] || die "${flag_name} 需要一个值。"
}

parse_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --hostname)
        require_value "--hostname" "$#"
        HOSTNAME_VALUE="$2"
        shift 2
        ;;
      --package-spec)
        require_value "--package-spec" "$#"
        PACKAGE_SPEC="$2"
        shift 2
        ;;
      --global-remodex-root)
        require_value "--global-remodex-root" "$#"
        GLOBAL_REMODEX_ROOT="$2"
        shift 2
        ;;
      --pair)
        PAIR_AFTER_SWITCH="true"
        shift
        ;;
      --help|-h)
        usage
        exit 0
        ;;
      *)
        usage >&2
        die "未知参数: $1"
        ;;
    esac
  done
}

require_command() {
  local command_name="$1"
  command -v "${command_name}" >/dev/null 2>&1 || die "缺少命令: ${command_name}"
}

verify_paths() {
  [[ -x "${ENABLE_SCRIPT}" ]] || die "缺少可执行脚本: ${ENABLE_SCRIPT}"
}

upgrade_global_remodex() {
  log "开始升级全局 remodex: ${PACKAGE_SPEC}"
  npm install -g "${PACKAGE_SPEC}"
  log "全局 remodex 升级完成"
}

reapply_global_local_relay() {
  local cmd
  cmd=("${ENABLE_SCRIPT}" "--hostname" "${HOSTNAME_VALUE}")

  if [[ -n "${GLOBAL_REMODEX_ROOT}" ]]; then
    cmd+=("--global-remodex-root" "${GLOBAL_REMODEX_ROOT}")
  fi

  if [[ "${PAIR_AFTER_SWITCH}" == "true" ]]; then
    cmd+=("--pair")
  fi

  log "开始重打全局本地 relay 配置"
  exec "${cmd[@]}"
}

main() {
  parse_args "$@"

  [[ -n "${HOSTNAME_VALUE}" ]] || die "必须传 --hostname，填写 iPhone 能访问到的局域网 IP 或 .local 主机名。"

  require_command npm
  verify_paths

  # 升级会覆盖全局 node_modules；随后必须立刻重新执行本地 relay 固化逻辑。
  upgrade_global_remodex
  reapply_global_local_relay
}

main "$@"
