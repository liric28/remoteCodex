# Remodex 连接失败排查时间线（2026-04-24）

这份记录保留的是这次排查里“做了多少努力、为什么最后收敛到当前方案”的完整过程。

它不是主流程文档，而是调试档案。

## 背景

现象不是单一的“连接不上”，而是混合了几类问题：

- 自定义 relay / Tailscale / 本地 relay 之间状态混在一起
- iPhone 端会记住旧 relay URL 和 trusted Mac
- Shadowrocket / Shadowsocks / VPN 可能介入网络链路
- `wss://` / TLS 在 iPhone 上表现出“应该能通但实际不通”
- 用户对“到底是网络问题、TLS 问题、域名问题，还是 App 代码问题”没有稳定结论

这次排查的目标不是写一堆 workaround，而是把问题拆开，找到一条稳定、可复用的解释和落地方案。

## 第一阶段：先排除“是不是写死了官方 relay / 特殊域名”

### 怀疑

最先怀疑的是：

- App 里是不是内置了某个私有 relay，例如 `api.phodex`
- 出现成功连接，是不是因为代码偷偷回退到了官方域名
- 有没有固定 IP 或生产默认值在 source checkout 里生效

### 验证

查了这些位置：

- `CodexMobile/CodexMobile/Services/AppEnvironment.swift`
- `phodex-bridge/src/codex-desktop-refresher.js`
- `phodex-bridge/src/bridge.js`
- `run-local-remodex.sh`
- `README.md`
- `Docs/self-hosting.md`

### 结论

排除掉了。

开源仓库里的事实是：

- iOS 默认 relay 是空字符串，不会自动回退到私有 hosted relay
- source checkout 也要求显式提供 relay，或者运行本地 launcher
- 本地 launcher 生成的是 `ws://<host>:9000/relay`
- 没看到“固定官方域名 + 自动兜底”这类逻辑

所以“今天能连上”不是因为代码写死了某个官方后门地址。

## 第二阶段：确认是不是“旧状态污染”而不是实时网络本身

### 怀疑

另一条明显可能性是：

- iPhone 记住了旧的 relay URL
- trusted Mac 记录还指向旧地址
- 菜单栏 app 里保存了 relay override
- 用户以为已经切换链路，实际上连接还在打旧地址

### 验证

查了这些位置：

- `CodexMobile/CodexMobile/Services/CodexService.swift`
- `CodexMobile/CodexMobile/Services/CodexService+SecureTransport.swift`
- `CodexMobile/CodexMobile/Services/CodexService+Connection.swift`
- `CodexMobile/RemodexMenuBar/BridgeMenuBarStore.swift`
- `CodexMobile/RemodexMenuBar/BridgeControlService.swift`
- `phodex-bridge/bin/remodex.js`

### 结论

这条是成立的，而且影响很大。

代码里能看到：

- iPhone 会优先复用保存下来的 relay session / trusted Mac relay URL
- 菜单栏 companion 还会单独保存 `relay override`
- Mac bridge 也有自己的 pairing state / daemon config

因此只改一头不够，必须把：

- iPhone pairing
- Mac pairing
- 菜单栏 relay override

一起清掉，才能确保真的换到新链路。

这一步形成了后来 `remodex-local-recovery` skill 的骨架。

## 第三阶段：把“本地链路是否可用”和“TLS / 代理问题”拆开

### 怀疑

如果所有问题都堆在一起看，会出现典型误判：

- 以为 TLS 坏了，其实是旧 relay 状态
- 以为 relay 坏了，其实是 Shadowrocket 分流
- 以为 Tailscale 不通，其实是 iOS 端走错 transport

所以必须先建立一个最简单的 baseline：

- 本地 relay
- 新二维码
- `ws://`
- 不经过 TLS
- 不经过代理

### 处理

做法是：

1. 清理旧 pairing
2. 清理菜单栏 relay override
3. 用 `run-local-remodex.sh` 起本地 relay
4. 重新扫码
5. 要求先不要走 Shadowrocket / TLS

### 结论

这一步不是“最终方案”，但它非常关键，因为它把问题拆成了两层：

- **基线链路是否能通**
- **在此基础上，TLS/代理链路为什么失效**

只要基线链路能通，就说明：

- 基本 pairing 流程没坏
- bridge / relay / iPhone app 主体没坏
- 更可能是 transport 路径和代理干扰的问题

## 第四阶段：重新聚焦到 iOS transport，而不是继续怀疑 relay 域名

### 怀疑

在“本地 baseline 可用”之后，剩下最值得怀疑的是：

- iOS 在不同 host 类型下，是否走了不同 transport
- 某些 transport 是否天然更容易被系统代理、VPN、Shadowrocket 影响
- `wss://` 在私网 / overlay 场景下是不是走错了网络栈

### 验证

重点查了：

- `CodexMobile/CodexMobile/Services/CodexService+Connection.swift`
- `CodexMobile/CodexMobile/Services/CodexService+Transport.swift`
- `CodexMobile/CodexMobile/Services/CodexService+SecureTransport.swift`

### 发现 1：代码本来就区分 direct relay host

`prefersDirectRelayTransport(for:)` 这段逻辑不是临时编出来的，而是项目里已经存在的设计：

- 私网 IPv4
- Tailscale 100.x
- `.local`
- `.ts.net`
- 本地 IPv6

都被归入“direct relay”。

这说明项目本身已经认识到：

> 这类 host 不适合无脑走统一的 WebSocket/URLSession 路径。

### 发现 2：direct relay 走的是更底层的 transport

`CodexService+Transport.swift` 里，direct relay 会走：

- `NWConnection`
- 手动 WebSocket handshake

而不是普通的 `URLSessionWebSocketTask`。

这很关键。

因为这意味着：

- 不是“换个 header”
- 不是“多试几次 TLS”
- 而是 **整条 transport stack 都换了**

### 发现 3：`wss://` 并没有回到旧路径

在 direct transport 里：

- `ws://` => raw TCP
- `wss://` => raw TCP + TLS

也就是说，TLS 仍然有，但它不再跑在之前那条更高层、更容易被代理影响的 WebSocket 路径上。

这是整个排查里最关键的结论之一。

## 第五阶段：确认 HTTP 侧 trusted resolve 也可能被代理链路带偏

### 怀疑

就算 WebSocket 走对了，trusted session resolve 还是 HTTP 请求：

- `/v1/trusted/session/resolve`
- `/v1/pairing/code/resolve`

如果这些请求继续走系统代理，而 WebSocket 走直连，会出现另一种“半好半坏”：

- WebSocket 看起来通了
- 但 trusted reconnect / pairing resolve 还是失败

### 验证

继续查：

- `CodexMobile/CodexMobile/Services/CodexService+SecureTransport.swift`

### 发现

项目里已经有针对 direct relay 的非代理 URLSession：

```swift
configuration.connectionProxyDictionary = [:]
```

这个设计说明：

- 作者已经遇到过类似问题
- 问题不只是 WebSocket
- HTTP resolve 也会被系统代理路径污染

### 结论

这进一步坐实了问题方向：

> 今天这个问题，本质更像“代理/网络栈路径错误”，而不是“TLS 证书本身坏了”。

## 第六阶段：排除掉一些错误方向

这次过程中，有几条方向是看起来合理，但最后被排除了，或者至少没有证据支持。

### 错误方向 1：固定官方域名 / 官方回退

排除了，原因前面已经写过。

### 错误方向 2：固定 IP 或 host override 才能工作

没有证据支持。

能工作的关键不是某个固定 IP，而是：

- 这是不是私网 / overlay 地址
- 它是否命中了 direct transport
- 是否绕开了代理路径

### 错误方向 3：TLS 证书校验逻辑有 bug

这次没有证据表明是这个。

至少从收敛结果来看，更像是：

- 一旦 transport 路径换掉，`wss://` 的问题也跟着消失

如果真是纯证书问题，换 transport 不应该有这么明显的改善。

### 错误方向 4：单纯网络差 / Wi-Fi 差

不能完全排除网络环境影响，但不足以解释全部现象。

尤其当：

- 同一个环境下某些直连链路能通
- 清理旧状态后基线链路可用
- 只有特定 `wss:// + 代理/系统路径` 失败

就更不像是一个泛化的“网络不好”问题。

## 第七阶段：最后收敛出的稳定解释

最后形成的稳定解释是：

1. 一部分失败来自旧 relay / pairing 状态污染。
2. 更深一层的问题是：
   - iPhone 在私网 / overlay / Tailscale 这类地址上
   - 普通 WebSocket / URLSession / 系统代理路径容易把流量带偏
3. 一旦切到 direct transport：
   - WebSocket 不再走那条容易被代理影响的路径
   - `wss://` 也只是 direct socket 上再叠一层 TLS
   - trusted resolve 也可以禁用代理
4. 所以今天“TLS 恢复了”更准确的说法不是“TLS 被修好了”，而是：

> `wss://` 被从错误的网络栈路径里拎出来，改走了 direct socket + TLS。

## 这次沉淀下来的可复用结论

### 结论 1

遇到 Remodex iPhone 连接失败，先把问题拆成：

- 状态污染问题
- transport / proxy 问题

不要一上来就查 TLS。

### 结论 2

对这些 host，要优先考虑 direct transport：

- `192.168.x.x`
- `10.x.x.x`
- `172.16.0.0/12`
- `100.64.0.0/10`
- `*.local`
- `*.ts.net`

### 结论 3

如果用户开着 Shadowrocket / Shadowsocks / VPN：

- 不要假设 `wss://` 一定等于“更稳”
- 先确认这条流量有没有被代理接管

### 结论 4

当用户说“TLS 终于好了”，要警惕这种误解：

- 可能不是 TLS 真修好了
- 只是 transport path 终于对了

## 还没有完全证明的部分

虽然这次已经足够收敛出有效方案，但仍有几件事没有在这轮里做成严格证明：

1. 没把 Shadowrocket 某条具体规则逐条抓包验证。
2. 没对所有失败环境做系统级 CFNetwork / NWConnection 对照实验。
3. 没证明所有 `wss://` 失败都来自同一个代理机制。

所以要注意表达边界：

- “强结论”是：当前最可复用的修复路径是 direct transport + 禁代理。
- “弱结论”是：某个特定环境里一定就是某一条 Shadowrocket 规则造成的。

## 一句话版

这次不是简单修了个 TLS，也不是找到一个神秘官方域名，而是：

**先清掉旧状态，再把私网 / Tailscale / `.local` / `.ts.net` 的 `wss://` 从容易被代理带偏的 iOS WebSocket 路径，切到了 direct socket + TLS。**
