#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
STATE_DIR="${REMODEX_DEVICE_STATE_DIR:-${HOME}/.remodex}"
DEFAULT_CONFIG_PATH="${STATE_DIR}/daemon-config.json"
REFERENCES_DIR="${ROOT_DIR}/skills/remodex-global-local-relay/references"

HOSTNAME_VALUE=""
RELAY_URL_VALUE=""
OUTPUT_PATH=""

log() {
  echo "[generate-shadowrocket-direct-module] $*"
}

die() {
  echo "[generate-shadowrocket-direct-module] $*" >&2
  exit 1
}

usage() {
  cat <<'EOF'
用法:
  ./skills/remodex-global-local-relay/scripts/generate_shadowrocket_direct_module.sh
  ./skills/remodex-global-local-relay/scripts/generate_shadowrocket_direct_module.sh --hostname 192.168.1.105
  ./skills/remodex-global-local-relay/scripts/generate_shadowrocket_direct_module.sh --relay-url ws://192.168.1.105:9000/relay

说明:
  按当前 Remodex 本地 relay 自动生成 Shadowrocket DIRECT 模块。

参数:
  --hostname HOSTNAME    直接指定 relay 主机名或 IP
  --relay-url URL        直接指定完整 relay 地址，例如 ws://192.168.1.105:9000/relay
  --output PATH          指定输出文件路径；默认写到 skills/remodex-global-local-relay/references/
  --help, -h             显示帮助
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
      --relay-url)
        require_value "--relay-url" "$#"
        RELAY_URL_VALUE="$2"
        shift 2
        ;;
      --output)
        require_value "--output" "$#"
        OUTPUT_PATH="$2"
        shift 2
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

is_ipv4() {
  [[ "$1" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]
}

is_private_ipv4() {
  local ip="$1"
  local o1 o2 o3 o4

  is_ipv4 "${ip}" || return 1

  IFS='.' read -r o1 o2 o3 o4 <<< "${ip}"

  if (( o1 == 10 )); then
    return 0
  fi

  if (( o1 == 172 && o2 >= 16 && o2 <= 31 )); then
    return 0
  fi

  if (( o1 == 192 && o2 == 168 )); then
    return 0
  fi

  if (( o1 == 169 && o2 == 254 )); then
    return 0
  fi

  if (( o1 == 100 && o2 >= 64 && o2 <= 127 )); then
    return 0
  fi

  return 1
}

is_local_hostname() {
  local hostname="$1"
  [[ "${hostname}" == *.local ]] \
    || [[ "${hostname}" == *.ts.net ]] \
    || [[ "${hostname}" == *.beta.tailscale.net ]]
}

validate_hostname_for_direct_module() {
  local hostname="$1"

  if is_private_ipv4 "${hostname}"; then
    return
  fi

  if is_local_hostname "${hostname}"; then
    return
  fi

  die "当前 relay 主机不是局域网 / Tailscale / .local 地址：${hostname}。先切到本地 relay，或显式传 --hostname <LAN_IP>。"
}

resolve_relay_url_from_state() {
  if [[ ! -f "${DEFAULT_CONFIG_PATH}" ]]; then
    return
  fi

  node -e '
const fs = require("node:fs");
const configPath = process.argv[1];
try {
  const parsed = JSON.parse(fs.readFileSync(configPath, "utf8"));
  process.stdout.write(typeof parsed?.relayUrl === "string" ? parsed.relayUrl.trim() : "");
} catch {
  process.stdout.write("");
}
' "${DEFAULT_CONFIG_PATH}"
}

resolve_relay_url_from_status() {
  if ! command -v remodex >/dev/null 2>&1; then
    return
  fi

  remodex status --json 2>/dev/null | node -e '
let raw = "";
process.stdin.setEncoding("utf8");
process.stdin.on("data", (chunk) => { raw += chunk; });
process.stdin.on("end", () => {
  try {
    const parsed = JSON.parse(raw);
    const relay =
      parsed?.daemonConfig?.relayUrl
      || parsed?.pairingSession?.pairingPayload?.relay
      || "";
    process.stdout.write(typeof relay === "string" ? relay.trim() : "");
  } catch {
    process.stdout.write("");
  }
});
'
}

# 优先读当前已持久化的 relay，这样生成出来的模块总是跟 Remodex 现状一致。
resolve_effective_relay_url() {
  if [[ -n "${RELAY_URL_VALUE}" ]]; then
    printf '%s\n' "${RELAY_URL_VALUE}"
    return
  fi

  local from_state
  from_state="$(resolve_relay_url_from_state || true)"
  if [[ -n "${from_state}" ]]; then
    printf '%s\n' "${from_state}"
    return
  fi

  local from_status
  from_status="$(resolve_relay_url_from_status || true)"
  if [[ -n "${from_status}" ]]; then
    printf '%s\n' "${from_status}"
    return
  fi

  printf '\n'
}

extract_hostname_from_relay_url() {
  local relay_url="$1"

  node -e '
const relayUrl = process.argv[1];
try {
  const parsed = new URL(relayUrl);
  process.stdout.write(parsed.hostname || "");
} catch {
  process.stdout.write("");
}
' "${relay_url}"
}

normalize_output_filename() {
  local hostname="$1"

  node -e '
const value = process.argv[1];
process.stdout.write(value.replace(/[^a-zA-Z0-9._-]+/g, "_"));
' "${hostname}"
}

resolve_hostname() {
  if [[ -n "${HOSTNAME_VALUE}" ]]; then
    printf '%s\n' "${HOSTNAME_VALUE}"
    return
  fi

  local effective_relay
  effective_relay="$(resolve_effective_relay_url)"
  [[ -n "${effective_relay}" ]] || die "无法自动解析当前 relay；请显式传 --hostname 或 --relay-url。"

  local relay_host
  relay_host="$(extract_hostname_from_relay_url "${effective_relay}")"
  [[ -n "${relay_host}" ]] || die "无法从 relay URL 解析主机名: ${effective_relay}"

  printf '%s\n' "${relay_host}"
}

resolve_output_path() {
  local hostname="$1"

  if [[ -n "${OUTPUT_PATH}" ]]; then
    printf '%s\n' "${OUTPUT_PATH}"
    return
  fi

  local normalized_name
  normalized_name="$(normalize_output_filename "${hostname}")"
  printf '%s/remodex_shadowrocket_direct_%s.sgmodule\n' "${REFERENCES_DIR}" "${normalized_name}"
}

write_module() {
  local hostname="$1"
  local output_path="$2"
  local exact_rule=""
  local exact_domain_rule=""

  mkdir -p "$(dirname "${output_path}")"

  if is_ipv4 "${hostname}"; then
    exact_rule="IP-CIDR,${hostname}/32,DIRECT,no-resolve"
  else
    exact_domain_rule="DOMAIN,${hostname},DIRECT"
  fi

  cat > "${output_path}" <<EOF
#!name=Remodex Local Direct ${hostname}
#!desc=让当前 Remodex 本地 relay（${hostname}:9000）和常见局域网地址直连，避免被 Shadowrocket 代理带偏。

[Rule]
${exact_rule}
${exact_domain_rule}
IP-CIDR,192.168.0.0/16,DIRECT,no-resolve
IP-CIDR,10.0.0.0/8,DIRECT,no-resolve
IP-CIDR,172.16.0.0/12,DIRECT,no-resolve
IP-CIDR,169.254.0.0/16,DIRECT,no-resolve
IP-CIDR,100.64.0.0/10,DIRECT,no-resolve
IP-CIDR6,fc00::/7,DIRECT,no-resolve
IP-CIDR6,fe80::/10,DIRECT,no-resolve
DOMAIN-SUFFIX,local,DIRECT
DOMAIN-SUFFIX,ts.net,DIRECT
DOMAIN-SUFFIX,beta.tailscale.net,DIRECT
EOF
}

main() {
  parse_args "$@"

  require_command node

  local hostname
  local output_path

  hostname="$(resolve_hostname)"
  output_path="$(resolve_output_path "${hostname}")"
  validate_hostname_for_direct_module "${hostname}"

  if ! is_ipv4 "${hostname}"; then
    log "当前 hostname 不是 IPv4；已写入 DOMAIN 精确规则。若要更精确的 IP-CIDR 规则，建议传 --hostname <LAN_IP>。"
  fi

  write_module "${hostname}" "${output_path}"

  log "已生成模块: ${output_path}"
  log "建议把这份模块分别导入手机和 Mac 的 Shadowrocket，并放在默认代理规则前面。"
}

main "$@"
