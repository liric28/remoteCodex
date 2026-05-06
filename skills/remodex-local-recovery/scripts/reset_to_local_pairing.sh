#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
BRIDGE_DIR="${ROOT_DIR}/phodex-bridge"
RUN_LOCAL_SCRIPT="${ROOT_DIR}/run-local-remodex.sh"
MENU_BAR_DEFAULTS_DOMAIN="com.emanueledipietro.RemodexMenuBar"
MENU_BAR_RELAY_KEY="remodex.menuBar.relayOverride"

HOSTNAME_VALUE=""

usage() {
  cat <<'EOF'
用法:
  ./skills/remodex-local-recovery/scripts/reset_to_local_pairing.sh --hostname 192.168.1.23

说明:
  清掉 Mac 端旧 pairing 和菜单栏 relay override，然后用新的局域网地址启动本地 relay。
EOF
}

require_value() {
  local flag_name="$1"
  local remaining_args="$2"
  [[ "${remaining_args}" -ge 2 ]] || {
    echo "[remodex-local-recovery] ${flag_name} 需要一个值。" >&2
    exit 1
  }
}

parse_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --hostname)
        require_value "--hostname" "$#"
        HOSTNAME_VALUE="$2"
        shift 2
        ;;
      --help|-h)
        usage
        exit 0
        ;;
      *)
        echo "[remodex-local-recovery] 未知参数: $1" >&2
        usage >&2
        exit 1
        ;;
    esac
  done
}

require_file() {
  local path="$1"
  [[ -e "${path}" ]] || {
    echo "[remodex-local-recovery] 缺少文件: ${path}" >&2
    exit 1
  }
}

reset_pairing() {
  echo "[remodex-local-recovery] 清理 Mac 端 pairing 状态..."
  if command -v remodex >/dev/null 2>&1; then
    remodex reset-pairing
    return
  fi

  (cd "${BRIDGE_DIR}" && node ./bin/remodex.js reset-pairing)
}

clear_menu_bar_override() {
  echo "[remodex-local-recovery] 清理菜单栏 relay override..."
  defaults delete "${MENU_BAR_DEFAULTS_DOMAIN}" "${MENU_BAR_RELAY_KEY}" >/dev/null 2>&1 || true
}

start_local_relay() {
  echo "[remodex-local-recovery] 使用 ${HOSTNAME_VALUE} 启动本地 relay..."
  cd "${ROOT_DIR}"
  exec "${RUN_LOCAL_SCRIPT}" --hostname "${HOSTNAME_VALUE}"
}

main() {
  parse_args "$@"

  if [[ -z "${HOSTNAME_VALUE}" ]]; then
    echo "[remodex-local-recovery] 必须传 --hostname，填写 iPhone 在家里能访问到的局域网 IP 或 .local 主机名。" >&2
    exit 1
  fi

  require_file "${RUN_LOCAL_SCRIPT}"
  require_file "${BRIDGE_DIR}/bin/remodex.js"

  reset_pairing
  clear_menu_bar_override

  echo "[remodex-local-recovery] 下一步:"
  echo "  1. 脚本启动后，在 iPhone 里手动点一次 Forget Pair / 忘记配对。"
  echo "  2. 扫描这次新生成的二维码。"
  echo "  3. 不要继续使用旧二维码。"

  start_local_relay
}

main "$@"
