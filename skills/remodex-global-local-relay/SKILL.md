---
name: remodex-global-local-relay
description: Use when the user wants Remodex on macOS to always default to a local LAN relay, keep bare remodex up/restart pinned to ws://<LAN_IP>:9000/relay, persist the menu bar relay override, and keep the global CLI from falling back to the hosted relay.
---

# Remodex Global Local Relay

用于把 Remodex 固定到“全局默认本地 relay”。

这个 skill 处理的是“以后裸 `remodex up` / `remodex restart` 也默认走局域网”的场景，不是一次性的本地恢复配对。

优先处理这些场景：

- “切全局本地 relay”
- “让 remodex up 默认走局域网”
- “菜单栏和全局 CLI 都固定到 `ws://192.168.x.x:9000/relay`”
- “不要一关终端就掉回 hosted relay”
- “全局 `remodex` 又回公用 relay 了”

如果用户只是想清旧 pairing、重新扫本地二维码，优先用 `remodex-local-recovery`，不要用这个 skill 替代。

## 工作流

1. 先要求用户给出这台 Mac 当前局域网里可达的 IP 或 `.local` 主机名；不要默默猜。
2. 确认仓库根目录存在：
   - `relay/server.js`
   - `phodex-bridge/src/codex-desktop-refresher.js`
3. 确认全局 `remodex` 可执行；如果不可执行，先修全局安装。
4. 执行：

```bash
./skills/remodex-global-local-relay/scripts/bootstrap_global_local_relay.sh --hostname 192.168.1.105
```

这是一步到位的总控入口，默认会：

- 升级全局 `remodex`
- 固定全局本地 relay
- 生成 Shadowrocket `DIRECT` 模块
- 打印新的二维码 / pairing code

5. 如果用户只想切本地，不想走总控脚本，改用：

```bash
./skills/remodex-global-local-relay/scripts/enable_global_local_relay.sh --hostname 192.168.1.105
```

6. 如果用户还需要新的二维码或 pairing code，改为：

```bash
./skills/remodex-global-local-relay/scripts/enable_global_local_relay.sh --hostname 192.168.1.105 --pair
```

7. 如果用户刚升级或准备升级全局 `remodex`，优先改用：

```bash
./skills/remodex-global-local-relay/scripts/upgrade_global_remodex.sh --hostname 192.168.1.105
```

8. 如果用户手机和 Mac 都开着 Shadowrocket，并且想自动生成本地 relay 的 `DIRECT` 模块，用：

```bash
./skills/remodex-global-local-relay/scripts/generate_shadowrocket_direct_module.sh
```

如果当前 relay 还没切到本地，先执行第 4 步或第 6 步；不要在 hosted relay 状态下生成模块。

## 这个 skill 会做什么

- 写入用户级 `~/Library/LaunchAgents/com.remodex.local-relay.plist`，让本地 relay 在 macOS 上常驻
- 把菜单栏 app 的 `remodex.menuBar.relayOverride` 固定到本地地址
- 把仓库里的 patched `phodex-bridge/src/codex-desktop-refresher.js` 同步到当前全局 `remodex` 安装
- 用 `REMODEX_RELAY=ws://<LAN_IP>:9000/relay remodex restart` 重写 `~/.remodex/daemon-config.json`
- 校验用户给的 `--hostname` 确实解析回当前这台 Mac，避免把错误 IP 写进全局配置
- 让后续裸 `remodex up` / `remodex restart` 默认继承这份持久化本地 relay，而不是回退到公用 relay
- 可按当前本地 relay 自动生成 Shadowrocket `.sgmodule`，输出到 `references/`

## 结果判断

至少验证下面三项：

- `remodex status --json` 里的 `daemonConfig.relayUrl` 和 `pairingPayload.relay` 都是 `ws://<LAN_IP>:9000/relay`
- `defaults read com.emanueledipietro.RemodexMenuBar remodex.menuBar.relayOverride` 返回同一个本地地址
- `lsof -nP -iTCP:9000 -sTCP:LISTEN` 能看到本地 relay 在监听

## 注意

- 局域网 IP 变了以后，要重新执行一次这个 skill。
- 全局 `remodex` 重新安装或升级后，如果又回到旧逻辑，重新执行一次这个 skill。
- 升级全局 `remodex` 时，优先跑 `scripts/upgrade_global_remodex.sh`，不要手动记两条命令。
- 如果只想切回本地，但这次并没有升级全局 `remodex`，直接跑 `scripts/enable_global_local_relay.sh`，不要多做 `npm install -g`。
- 首次重新配对时，即使两端之后要继续开 Shadowrocket，也建议先在 iPhone 和 Mac 两端临时关掉 Shadowrocket，完成一次稳定配对后再打开。
- 生成 Shadowrocket 模块前，要先确认当前 relay 已经是本地 `ws://<LAN_IP>:9000/relay`；否则脚本会拒绝生成。
- 如果当前 relay 主机是 `.local` 或 `.ts.net`，脚本会写 `DOMAIN,<host>,DIRECT`；如果要更精确的 `IP-CIDR,<LAN_IP>/32`，显式传 `--hostname <LAN_IP>`。
- 从 hosted relay 切到本地 relay 后，iPhone 端通常仍需要 `Forget Pair / 忘记配对`，然后重新扫码。
- 这个 skill 会操作 `launchctl`，运行时通常需要在允许沙箱外执行的环境里完成。
- 如果用户只想临时跑一次本地 relay，不要固定成全局默认，直接用：

```bash
REMODEX_RELAY="ws://192.168.1.105:9000/relay" remodex up
```
