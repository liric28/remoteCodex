---
name: remodex-local-recovery
description: Use when the user wants to clear stale Remodex relay state, undo a Tailscale or custom relay setup, reset saved pairing on the Mac, clear the menu bar relay override, and return to local LAN pairing with run-local-remodex.sh.
---

# Remodex Local Recovery

用于把 Mac 端从旧的 Tailscale / 自定义 relay 状态恢复到本地局域网配对。

优先处理这些场景：

- “在家里一直连不上，想改回本地 relay / 局域网”
- “之前配过 Tailscale，现在想还原”
- “之前开过 Shadowrocket / Shadowsocks，怀疑代理把连接带歪了”
- “iPhone 老是走旧 relay 地址”
- “清掉 Remodex 旧配对，重新扫本地二维码”
- “之前一直试 TLS / wss 连不上，现在想先恢复到能用的本地链路”

## 工作流

1. 确认仓库根目录存在 `run-local-remodex.sh`，并且 `phodex-bridge/bin/remodex.js` 可用。
2. 在 Mac 端清理旧状态：
   - 停掉 bridge 并重置 pairing：`remodex reset-pairing`
   - 如果全局 `remodex` 不可用，退回到 `node ./phodex-bridge/bin/remodex.js reset-pairing`
3. 清理菜单栏 app 保存的 relay override：
   - `defaults delete com.emanueledipietro.RemodexMenuBar remodex.menuBar.relayOverride`
4. 用新的局域网地址启动本地 relay：
   - `./run-local-remodex.sh --hostname <LAN_IP_OR_HOSTNAME>`
5. 明确提醒用户：
   - iPhone 端还需要手动点一次 `Forget Pair / 忘记配对`
   - 必须扫描这次新生成的二维码，不要复用旧二维码
   - 如果 iPhone 开着 Shadowrocket / Shadowsocks / 其他代理或 VPN，先关掉，至少在首次恢复配对时不要让 Remodex 流量走代理

## Shadowrocket / Shadowsocks 处理

本地恢复链路固定按下面理解：

- `run-local-remodex.sh` 启动的是本地 relay
- 生成的地址默认是 `ws://<局域网IP或.local>:9000/relay`
- 这条链路是局域网直连，不是 `wss://`
- 目标是先恢复“可连接”，不是先折腾 TLS

因此处理原则是：

1. 本地恢复时，不要要求 TLS。
2. 本地恢复时，不要让代理接管 Remodex 的局域网流量。
3. 如果用户开着 Shadowrocket / Shadowsocks：
   - 最稳妥做法：首次恢复配对时直接关闭代理/VPN。
   - 次优做法：给 Remodex 目标地址加 `DIRECT` 规则，至少覆盖：
     - `192.168.0.0/16`
     - `10.0.0.0/8`
     - `172.16.0.0/12`
     - `100.64.0.0/10`（Tailscale 常见地址）
     - `*.local`
     - `*.ts.net`
   - 如果用户不想手动配置规则，直接导入：
     - `references/remodex_shadowrocket_direct.sgmodule`
   - 如果 iPhone 和 Mac 都开着 Shadowrocket，建议两端都导入同一份模块。
     - iPhone 侧：避免 Remodex 连接 relay / resolve 时被代理接管
     - Mac 侧：避免本地 relay、Tailscale、`.local` 访问和回环链路被错误分流
4. 如果用户说“TLS 连不上”：
   - 对本地恢复，直接改回 `ws://`，不要继续排 `wss://`
   - `wss://` 只留给真正有反向代理和有效证书的自建公网 relay

只有在下面条件同时满足时，才建议 `wss://`：

- relay 前面有 Nginx / Caddy / Traefik 之类的反代
- 证书有效，iPhone 信任该证书
- WebSocket Upgrade 正常转发
- 路径转发正确，最终 Node relay 仍收到 `/relay/...`

如果用户问的是“之前公司里那个 TLS / 代理问题到底是怎么绕过去的”，读
`references/tls_proxy_bypass.md`。

如果用户要看这次 Remodex 连接失败排查的完整过程、错误方向、排除项和最终收敛过程，读
`references/debug_timeline_2026-04-24.md`。

## 直接执行

优先用脚本：

```bash
./skills/remodex-local-recovery/scripts/reset_to_local_pairing.sh --hostname 192.168.1.23
```

如果用户没给 `--hostname`，先提示他填写家里这台 Mac 在局域网里的可达 IP 或 `.local` 主机名；不要默默猜。

## 结果判断

成功标准：

- 旧 pairing 已清掉
- 菜单栏 relay override 已清掉
- 本地 relay 已启动
- 终端已经打印新的二维码 / pairing code
- iPhone 没有再被 Shadowrocket / Shadowsocks 代理链路干扰
- 用户只剩 iPhone 端一次手动 `Forget Pair` + 重新扫码

## 注意

- 不要使用旧二维码。
- 不要把 `localhost` 当成给 iPhone 用的地址。
- 如果 `run-local-remodex.sh` 报主机名不属于当前 Mac，改用局域网 IP。
- 如果用户仍然要走 Tailscale，就不要运行这个 skill；那是另一条链路。
- 如果目标是“先恢复能连”，优先 `ws://局域网地址:9000/relay`，不要先折腾 TLS。
