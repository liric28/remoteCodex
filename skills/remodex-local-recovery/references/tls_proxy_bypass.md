# Remodex TLS / Proxy Bypass

这个文件只回答一个问题：

“之前 `wss://` / TLS 在 iPhone 上老是被 Shadowrocket、系统代理或 WebSocket 路径带坏，今天到底是怎么绕过去的？”

结论：

- 不是写死 `api.phodex`
- 不是写死固定 IP
- 不是关闭证书校验
- 不是给某个域名做特殊兜底

真正做的是：**对局域网 / 私网 / Tailscale 这类地址，切到 direct transport，避开 iOS 那条更容易受代理影响的 WebSocket/CFNetwork 路径。**

## 关键实现

### 1. 识别哪些地址应该走 direct transport

文件：

- `CodexMobile/CodexMobile/Services/CodexService+Connection.swift`

函数：

- `prefersDirectRelayTransport(for:)`

会命中的地址：

- `192.168.x.x`
- `10.x.x.x`
- `172.16.0.0/12`
- `100.64.0.0/10`
- `*.local`
- `*.ts.net`
- 本地 IPv6

目的：

- 这些地址本质上都更接近“本地/私网/overlay 网络”
- 不应该优先走容易被系统代理、VPN、Shadowrocket 接管的那条 WebSocket 路径

### 2. direct transport 走的是手动 socket + 手动 WebSocket 握手

文件：

- `CodexMobile/CodexMobile/Services/CodexService+Transport.swift`

函数：

- `establishManualTCPWebSocketConnection`

这里不是普通 `URLSessionWebSocketTask`，而是：

- `NWConnection`
- 手动做 WebSocket handshake

这一步的意义：

- 绕开 iOS 常规 WebSocket/CFNetwork 代理链路
- 避免 Shadowrocket 或系统代理把直连 relay 流量带到错误的出口

### 3. `wss://` 也不是回到旧路径，而是 direct TLS socket

同样在：

- `CodexMobile/CodexMobile/Services/CodexService+Transport.swift`

关键逻辑：

```swift
let parameters = NWParameters(
    tls: (endpoint.scheme == "wss") ? NWProtocolTLS.Options() : nil,
    tcp: NWProtocolTCP.Options()
)
```

意思是：

- `ws://` => direct TCP
- `wss://` => direct TCP + TLS

所以“TLS 能用了”不是因为 TLS 本身被修好，而是因为 **TLS 不再走之前那条容易被代理干扰的网络栈**。

### 4. trusted session resolve 的 HTTP 请求也禁用代理

文件：

- `CodexMobile/CodexMobile/Services/CodexService+SecureTransport.swift`

函数：

- `trustedSessionResolveURLSession(for:)`

对 direct relay：

```swift
configuration.connectionProxyDictionary = [:]
```

作用：

- `/v1/trusted/session/resolve` 这种 HTTP 请求也不再走系统代理
- 避免“WebSocket 直连了，但 resolve 还被代理带偏”

## 实际判断

如果用户说：

- “公司里开着 Shadowrocket，`wss://` 一直连不上”
- “家里 Tailscale 地址能 ping，但 Remodex TLS 就是不通”
- “同一个 relay，Mac 正常，iPhone 不通”

先判断是不是这类问题：

1. relay 地址是不是私网 / overlay 地址
2. iPhone 上是不是开了代理 / VPN / 分流工具
3. 当前是不是还在走普通 WebSocket / URLSession 路径

如果是，就优先复用这套思路，而不是先查证书。

## 一句话总结

这套修复的本质不是“修 TLS”，而是：

**把 `wss://` 从容易被代理影响的 iOS WebSocket 路径，切到 direct socket + TLS。**
