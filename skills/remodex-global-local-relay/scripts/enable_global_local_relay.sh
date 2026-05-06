#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
STATE_DIR="${REMODEX_DEVICE_STATE_DIR:-${HOME}/.remodex}"
LOGS_DIR="${STATE_DIR}/logs"
LAUNCH_AGENTS_DIR="${HOME}/Library/LaunchAgents"
LOCAL_RELAY_LABEL="com.remodex.local-relay"
LOCAL_RELAY_PLIST="${LAUNCH_AGENTS_DIR}/${LOCAL_RELAY_LABEL}.plist"
MENU_BAR_DEFAULTS_DOMAIN="com.emanueledipietro.RemodexMenuBar"
MENU_BAR_RELAY_KEY="remodex.menuBar.relayOverride"

HOSTNAME_VALUE=""
GLOBAL_REMODEX_ROOT=""
PAIR_AFTER_SWITCH="false"

log() {
  echo "[remodex-global-local-relay] $*"
}

die() {
  echo "[remodex-global-local-relay] $*" >&2
  exit 1
}

usage() {
  cat <<'EOF'
用法:
  ./skills/remodex-global-local-relay/scripts/enable_global_local_relay.sh --hostname 192.168.1.105 [--pair]

说明:
  把 Remodex 固定成全局默认本地 relay，并让后续裸 remodex up / remodex restart 默认继承本地 relay。

参数:
  --hostname HOSTNAME           iPhone 可访问到的局域网 IP 或 .local 主机名
  --global-remodex-root PATH    指定全局 remodex 安装根目录；默认自动从 `command -v remodex` 推导
  --pair                        最后直接执行 `remodex up` 打印新的二维码/配对码
  --help, -h                    显示帮助
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

require_file() {
  local target_path="$1"
  [[ -f "${target_path}" ]] || die "缺少文件: ${target_path}"
}

resolve_realpath() {
  local target_path="$1"
  node -p 'require("node:fs").realpathSync(process.argv[1])' "${target_path}"
}

# 优先从当前 shell 里的全局 remodex 解析安装根目录，避免把补丁写到错误版本。
resolve_global_remodex_root() {
  if [[ -n "${GLOBAL_REMODEX_ROOT}" ]]; then
    return
  fi

  require_command remodex

  local remodex_bin
  local remodex_real

  remodex_bin="$(command -v remodex)"
  remodex_real="$(resolve_realpath "${remodex_bin}")"
  GLOBAL_REMODEX_ROOT="$(cd "$(dirname "${remodex_real}")/.." && pwd)"
}

verify_paths() {
  require_file "${ROOT_DIR}/relay/server.js"
  require_file "${ROOT_DIR}/phodex-bridge/src/codex-desktop-refresher.js"
  require_file "${GLOBAL_REMODEX_ROOT}/src/codex-desktop-refresher.js"
}

# 先校验用户给的 LAN IP / .local 确实指向这台 Mac，避免把错误地址写进全局 relay 配置。
ensure_hostname_belongs_to_this_mac() {
  node -e '
const dns = require("node:dns");
const os = require("node:os");

const hostname = process.argv[1];
const localAddresses = new Set(["127.0.0.1", "::1"]);
for (const addresses of Object.values(os.networkInterfaces())) {
  for (const address of addresses || []) {
    if (address && typeof address.address === "string" && address.address) {
      localAddresses.add(address.address);
    }
  }
}

dns.lookup(hostname, { all: true }, (error, records) => {
  if (error || !Array.isArray(records) || records.length === 0) {
    process.exit(1);
    return;
  }

  const isLocal = records.some((record) => localAddresses.has(record.address));
  process.exit(isLocal ? 0 : 1);
});
' "${HOSTNAME_VALUE}" || die "hostname 不属于当前这台 Mac: ${HOSTNAME_VALUE}。请改用实际局域网 IP 或能解析到本机的 .local 主机名。"
}

relay_url() {
  printf 'ws://%s:9000/relay\n' "${HOSTNAME_VALUE}"
}

write_local_relay_plist() {
  local node_path
  node_path="$(command -v node)"

  mkdir -p "${LAUNCH_AGENTS_DIR}" "${LOGS_DIR}"

  cat > "${LOCAL_RELAY_PLIST}" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key>
  <string>${LOCAL_RELAY_LABEL}</string>
  <key>ProgramArguments</key>
  <array>
    <string>${node_path}</string>
    <string>${ROOT_DIR}/relay/server.js</string>
  </array>
  <key>RunAtLoad</key>
  <true/>
  <key>KeepAlive</key>
  <dict>
    <key>SuccessfulExit</key>
    <false/>
  </dict>
  <key>WorkingDirectory</key>
  <string>${ROOT_DIR}/relay</string>
  <key>EnvironmentVariables</key>
  <dict>
    <key>HOME</key>
    <string>${HOME}</string>
    <key>PORT</key>
    <string>9000</string>
  </dict>
  <key>StandardOutPath</key>
  <string>${LOGS_DIR}/local-relay.stdout.log</string>
  <key>StandardErrorPath</key>
  <string>${LOGS_DIR}/local-relay.stderr.log</string>
</dict>
</plist>
EOF

  log "已写入 ${LOCAL_RELAY_PLIST}"
}

reload_local_relay_launch_agent() {
  local launch_domain
  launch_domain="gui/$(id -u)"

  launchctl bootout "${launch_domain}" "${LOCAL_RELAY_PLIST}" >/dev/null 2>&1 || true
  launchctl bootstrap "${launch_domain}" "${LOCAL_RELAY_PLIST}"
  launchctl kickstart -k "${launch_domain}/${LOCAL_RELAY_LABEL}"

  log "本地 relay LaunchAgent 已重载"
}

persist_menu_bar_override() {
  local target_relay
  target_relay="$(relay_url)"

  defaults write "${MENU_BAR_DEFAULTS_DOMAIN}" "${MENU_BAR_RELAY_KEY}" "${target_relay}"
  log "菜单栏 relay override 已设置为 ${target_relay}"
}

# 让全局 CLI 复用仓库里的持久化 relay 逻辑，这样裸 remodex up 不会再退回 hosted relay。
sync_global_cli_logic() {
  install -m 0644 \
    "${ROOT_DIR}/phodex-bridge/src/codex-desktop-refresher.js" \
    "${GLOBAL_REMODEX_ROOT}/src/codex-desktop-refresher.js"

  log "已同步全局 remodex 的 relay 默认逻辑"
}

restart_bridge_with_local_relay() {
  local target_relay
  target_relay="$(relay_url)"

  REMODEX_RELAY="${target_relay}" remodex restart
  log "bridge 已切换到 ${target_relay}"
}

verify_switch_result() {
  local target_relay
  target_relay="$(relay_url)"

  log "验证菜单栏 override..."
  defaults read "${MENU_BAR_DEFAULTS_DOMAIN}" "${MENU_BAR_RELAY_KEY}"

  log "验证 bridge 状态..."
  remodex status --json

  log "验证本地 relay 监听..."
  lsof -nP -iTCP:9000 -sTCP:LISTEN

  log "验证完成；目标 relay=${target_relay}"
}

pair_after_switch() {
  local target_relay
  target_relay="$(relay_url)"

  log "现在直接执行 remodex up 打印新的二维码/配对码..."
  exec env REMODEX_RELAY="${target_relay}" remodex up
}

main() {
  parse_args "$@"

  [[ -n "${HOSTNAME_VALUE}" ]] || die "必须传 --hostname，填写 iPhone 能访问到的局域网 IP 或 .local 主机名。"

  require_command node
  require_command launchctl
  require_command defaults
  require_command install
  require_command lsof

  resolve_global_remodex_root
  verify_paths
  ensure_hostname_belongs_to_this_mac

  log "仓库根目录: ${ROOT_DIR}"
  log "全局 remodex 根目录: ${GLOBAL_REMODEX_ROOT}"
  log "目标 relay: $(relay_url)"

  write_local_relay_plist
  reload_local_relay_launch_agent
  persist_menu_bar_override
  sync_global_cli_logic
  restart_bridge_with_local_relay
  verify_switch_result

  if [[ "${PAIR_AFTER_SWITCH}" == "true" ]]; then
    pair_after_switch
  fi

  log "完成。以后裸 remodex up / remodex restart 会默认继承这条本地 relay。"
  log "如果 iPhone 还保留旧 hosted relay，会话层面仍建议先 Forget Pair 再重扫。"
}

main "$@"
