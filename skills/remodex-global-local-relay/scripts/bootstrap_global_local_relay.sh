#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
UPGRADE_SCRIPT="${ROOT_DIR}/skills/remodex-global-local-relay/scripts/upgrade_global_remodex.sh"
ENABLE_SCRIPT="${ROOT_DIR}/skills/remodex-global-local-relay/scripts/enable_global_local_relay.sh"
GENERATE_MODULE_SCRIPT="${ROOT_DIR}/skills/remodex-global-local-relay/scripts/generate_shadowrocket_direct_module.sh"

HOSTNAME_VALUE=""
PACKAGE_SPEC="remodex@latest"
GLOBAL_REMODEX_ROOT=""
MODULE_OUTPUT=""
SKIP_UPGRADE="false"
SKIP_MODULE="false"
SKIP_PAIR="false"

log() {
  echo "[bootstrap-global-local-relay] $*"
}

die() {
  echo "[bootstrap-global-local-relay] $*" >&2
  exit 1
}

usage() {
  cat <<'EOF'
用法:
  ./skills/remodex-global-local-relay/scripts/bootstrap_global_local_relay.sh --hostname 192.168.1.105

说明:
  一步完成：
  1. 可选升级全局 remodex
  2. 切全局默认本地 relay
  3. 生成 Shadowrocket DIRECT 模块
  4. 默认直接打印新的二维码 / pairing code

参数:
  --hostname HOSTNAME           iPhone 可访问到的局域网 IP 或 .local 主机名
  --package-spec SPEC          要安装的 npm 包版本，默认 remodex@latest
  --global-remodex-root PATH   显式指定全局 remodex 安装目录
  --module-output PATH         指定生成的 Shadowrocket 模块输出路径
  --skip-upgrade               跳过 npm install -g，只做本地 relay 固化 + 模块生成 + 配对
  --skip-module                跳过 Shadowrocket 模块生成
  --skip-pair                  不打印新的二维码 / pairing code
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
      --module-output)
        require_value "--module-output" "$#"
        MODULE_OUTPUT="$2"
        shift 2
        ;;
      --skip-upgrade)
        SKIP_UPGRADE="true"
        shift
        ;;
      --skip-module)
        SKIP_MODULE="true"
        shift
        ;;
      --skip-pair)
        SKIP_PAIR="true"
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
  [[ -x "${UPGRADE_SCRIPT}" ]] || die "缺少可执行脚本: ${UPGRADE_SCRIPT}"
  [[ -x "${ENABLE_SCRIPT}" ]] || die "缺少可执行脚本: ${ENABLE_SCRIPT}"
  [[ -x "${GENERATE_MODULE_SCRIPT}" ]] || die "缺少可执行脚本: ${GENERATE_MODULE_SCRIPT}"
}

relay_url() {
  printf 'ws://%s:9000/relay\n' "${HOSTNAME_VALUE}"
}

run_upgrade_or_enable() {
  local cmd

  if [[ "${SKIP_UPGRADE}" == "true" ]]; then
    cmd=("${ENABLE_SCRIPT}" "--hostname" "${HOSTNAME_VALUE}")
    if [[ -n "${GLOBAL_REMODEX_ROOT}" ]]; then
      cmd+=("--global-remodex-root" "${GLOBAL_REMODEX_ROOT}")
    fi
    log "跳过升级，直接固化全局本地 relay"
  else
    cmd=("${UPGRADE_SCRIPT}" "--hostname" "${HOSTNAME_VALUE}" "--package-spec" "${PACKAGE_SPEC}")
    if [[ -n "${GLOBAL_REMODEX_ROOT}" ]]; then
      cmd+=("--global-remodex-root" "${GLOBAL_REMODEX_ROOT}")
    fi
    log "先升级全局 remodex，再固化全局本地 relay"
  fi

  "${cmd[@]}"
}

# 模块生成单独放在切本地之后执行，保证生成内容一定跟当前 relay 配置一致。
run_generate_module() {
  local cmd
  cmd=("${GENERATE_MODULE_SCRIPT}" "--hostname" "${HOSTNAME_VALUE}")

  if [[ -n "${MODULE_OUTPUT}" ]]; then
    cmd+=("--output" "${MODULE_OUTPUT}")
  fi

  log "开始生成 Shadowrocket DIRECT 模块"
  "${cmd[@]}"
}

pair_now() {
  local target_relay
  target_relay="$(relay_url)"

  log "现在开始打印新的二维码 / pairing code"
  exec env REMODEX_RELAY="${target_relay}" remodex up
}

main() {
  parse_args "$@"

  [[ -n "${HOSTNAME_VALUE}" ]] || die "必须传 --hostname，填写 iPhone 能访问到的局域网 IP 或 .local 主机名。"

  require_command remodex
  verify_paths

  run_upgrade_or_enable

  if [[ "${SKIP_MODULE}" != "true" ]]; then
    run_generate_module
  fi

  if [[ "${SKIP_PAIR}" != "true" ]]; then
    pair_now
  fi

  log "完成。"
  log "目标 relay: $(relay_url)"
  if [[ "${SKIP_MODULE}" != "true" ]]; then
    log "Shadowrocket 模块已生成。"
  fi
}

main "$@"
