---
name: remodex-public-relay-recovery
description: Use when a Mac should stop using a LAN/private relay and return to a public reachable relay, especially on a company Mac that has no Remodex menu bar app. Covers daemon-config cleanup, relay override inspection, published-package default relay behavior, and restart commands that work from a terminal-only setup.
---

# Remodex Public Relay Recovery

用于把某台 Mac 从 `192.168.x.x` / `10.x.x.x` / 自定义本地 relay 状态，恢复到公网可达 relay。

这个 skill 适合：

- 公司 Mac 没有 Remodex 菜单栏 app
- 只能登录终端
- 之前把 relay 固定到了本地 / 私网地址
- 现在希望手机在外网也能重连这台 Mac

如果问题是多台 Mac 切换、trusted reconnect 逻辑、长期 relay 与局域网 relay 的架构修复，优先看
`skills/remodex-connection-strategy/SKILL.md`。

## 重要前提

- `10.x.x.x`、`192.168.x.x`、`.local` 都是私网/本地网络地址。
- 手机在外面用 `5G + 普通代理` 不能直接到这些地址。
- 公司 Mac 想让手机长期可达，必须满足下面之一：
  - 使用发布包自带的公网默认 relay
  - 显式设置一个公网可达的 `wss://.../relay`
  - 改成 `Tailscale/VPN` 可达的长期 relay

## 菜单栏 app 不存在时的原则

- 不要假设有 `com.emanueledipietro.RemodexMenuBar`
- 不要把 `defaults delete ... relayOverride` 当成必做项
- 终端-only 场景主要改的是：
  - `~/.remodex/daemon-config.json`
  - 启动命令环境里的 `REMODEX_RELAY`
  - 可能存在的用户自定义 `launch agent` / shell 包装脚本

## 一步一步执行

先在公司 Mac 上运行下面这些命令，按顺序来。

### 1. 看当前到底绑到了哪个 relay

```bash
cat ~/.remodex/daemon-config.json 2>/dev/null || true
remodex status --json 2>/dev/null || true
env | rg '^REMODEX_RELAY=' || true
launchctl list | rg remodex || true
```

如果 `daemon-config.json` 或 `status --json` 里出现：

- `ws://192.168...`
- `ws://10....`
- `*.local`

那说明这台 Mac 现在就是私网 relay 状态。

### 2. 清掉终端会话里的临时 relay 覆盖

```bash
unset REMODEX_RELAY
unset REMODEX_PUSH_SERVICE_URL
```

### 3. 备份并删除旧的 daemon 配置

```bash
mkdir -p ~/.remodex/backup
cp ~/.remodex/daemon-config.json ~/.remodex/backup/daemon-config.json.$(date +%Y%m%d-%H%M%S) 2>/dev/null || true
rm -f ~/.remodex/daemon-config.json
```

### 4. 如果之前做过“全局固定本地 relay”，一并停掉它

```bash
launchctl unload ~/Library/LaunchAgents/com.remodex.local-relay.plist 2>/dev/null || true
rm -f ~/Library/LaunchAgents/com.remodex.local-relay.plist
```

如果不存在，直接忽略。

### 5. 重启 bridge，不带任何本地 relay 覆盖

优先：

```bash
remodex restart
remodex status --json
```

如果 `restart` 不可用，再用：

```bash
remodex up
```

## 结果判断

### 情况 A：你装的是“带默认公网 relay 的已发布包”

如果 `remodex status --json` 里新的 `relayUrl` 不再是：

- `192.168.x.x`
- `10.x.x.x`
- `.local`

而是一个公网可达的 `wss://.../relay`，说明已经恢复成功。

这种情况下，让 iPhone 重新连这台 Mac 即可。

### 情况 B：你跑的是 source checkout / 开源本地版本

如果清掉配置后仍然没有公网 relay，或者直接报“source checkout 需要自己提供 relay”，这不是失败，而是说明：

- 这个环境本来就没有 baked-in 的 hosted relay
- 只靠“删除本地配置”不会自动变回公网 relay

这时只能二选一：

1. 安装带默认公网 relay 的发布版 `remodex`
2. 显式指定你自己的公网 relay：

```bash
REMODEX_RELAY="wss://your-public-relay.example/relay" remodex up
```

## 最短排障结论

如果你只想最快确认“公司 Mac 能不能回公网 relay”，运行：

```bash
unset REMODEX_RELAY
rm -f ~/.remodex/daemon-config.json
remodex restart
remodex status --json
```

然后看 `relayUrl`：

- 变成公网 `wss://...`：成功
- 还是私网 `192.168/10.x`：还有别的本地覆盖没清掉
- 没有公网默认值，或提示 source checkout：这台机器本身就不带 hosted relay，需要换发布版或手动指定公网 relay

## 不要做的事

- 不要继续把公司 Mac 固定在 `10.x.x.x` 上，还期待手机外网能重连
- 不要把“普通代理能出网”误当成“手机能进公司私网”
- 不要在没有公网 relay / Tailscale / VPN 的前提下，继续把问题归到 iPhone WebSocket 代码
