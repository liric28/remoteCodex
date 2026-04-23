// FILE: AppLanguage.swift
// Purpose: App-wide language preference and lightweight manual localization helpers.
// Layer: Model
// Exports: AppLanguage, L

import Foundation

enum AppLanguage: String, CaseIterable, Identifiable {
    case system
    case english
    case chinese

    static let storageKey = "codex.appLanguage"

    var id: String { rawValue }

    var locale: Locale {
        switch self {
        case .system:
            return .autoupdatingCurrent
        case .english:
            return Locale(identifier: "en")
        case .chinese:
            return Locale(identifier: "zh-Hans")
        }
    }

    var effectiveLanguage: AppLanguage {
        switch self {
        case .system:
            return Self.preferredSystemLanguage
        case .english, .chinese:
            return self
        }
    }

    var title: String {
        switch self {
        case .system:
            return L("System Language", "系统语言")
        case .english:
            return L("English", "英文")
        case .chinese:
            return L("Chinese", "中文")
        }
    }

    static var current: AppLanguage {
        guard let rawValue = UserDefaults.standard.string(forKey: storageKey),
              let language = AppLanguage(rawValue: rawValue) else {
            return .system
        }

        return language
    }

    private static var preferredSystemLanguage: AppLanguage {
        guard let identifier = Locale.preferredLanguages.first else {
            return .english
        }

        return identifier.hasPrefix("zh") ? .chinese : .english
    }
}

func L(_ en: String, _ zh: String) -> String {
    AppLanguage.current.effectiveLanguage == .chinese ? zh : en
}

func localizedAppMessage(_ message: String) -> String {
    guard AppLanguage.current.effectiveLanguage == .chinese else {
        return message
    }

    let trimmed = message.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else {
        return message
    }

    if let exactMessage = exactLocalizedAppMessages[trimmed] {
        return exactMessage
    }

    if let prefixedMessage = localizedPrefixedAppMessage(trimmed) {
        return prefixedMessage
    }

    let lowered = trimmed.lowercased()
    if lowered.contains("not a git repository")
        || lowered.contains("not in a git repository")
        || lowered.contains("not inside a git repository")
        || lowered.contains("must be run in a work tree") {
        return "当前路径不是 Git 仓库。"
    }

    if lowered.contains("wake your mac display")
        || lowered.contains("wake mac display") {
        return "暂时无法唤醒 Mac 显示器。"
    }

    return message
}

private let exactLocalizedAppMessages: [String: String] = [
    "Connection already in progress": "正在连接中。",
    "Connection was interrupted. Tap Reconnect to try again.": "连接已中断。点按“重新连接”再试一次。",
    "Could not reconnect. Tap Reconnect to try again.": "无法重新连接。点按“重新连接”再试一次。",
    "Connection timed out. Check server/network.": "连接超时。请检查服务器或网络。",
    "Connection timed out. Retrying...": "连接超时，正在重试...",
    "Connection timed out after 5s": "连接超时，已等待 5 秒。",
    "Could not resolve that pairing code.": "无法解析该配对码。",
    "Enter a valid pairing code.": "请输入有效的配对码。",
    "Trying to wake your Mac display...": "正在尝试唤醒 Mac 显示器...",
    "Trying to wake your Mac display.": "正在尝试唤醒 Mac 显示器。",
    "Could not wake your Mac display right now.": "暂时无法唤醒 Mac 显示器。",
    "Reconnect to your Mac or scan a new QR code first.": "请先重新连接 Mac，或扫描新的二维码。",
    "The Mac bridge rejected this setting update.": "Mac 桥接拒绝了这次设置更新。",
    "The Mac bridge could not save this setting.": "Mac 桥接无法保存此设置。",
    "This relay pairing is no longer valid. Scan a new QR code to reconnect.": "此中继配对已失效。请扫描新的二维码重新连接。",
    "This relay session was replaced by another Mac connection. Scan a new QR code to reconnect.": "此中继会话已被另一台 Mac 连接替换。请扫描新的二维码重新连接。",
    "This device was replaced by a newer connection. Scan a new QR code to reconnect.": "此设备已被新的连接替换。请扫描新的二维码重新连接。",
    "This relay needs a fresh QR scan before trusted reconnect is available.": "此中继需要先重新扫描二维码，才能使用可信重连。",
    "Trying to reach your saved Mac. Remodex will keep retrying. If you restarted the bridge on your Mac, scan the new QR code.": "正在尝试连接已保存的 Mac。Remodex 会继续重试。如果你重启了 Mac 上的桥接，请扫描新的二维码。",
    "Secure reconnect could not be restored from the saved session. Try reconnecting again.": "无法从已保存会话恢复安全重连。请再次尝试重新连接。",
    "No trusted Mac is available to reconnect.": "没有可用于重连的可信 Mac。",
    "This relay does not support trusted reconnect yet.": "此中继暂不支持可信重连。",
    "Reconnecting securely": "正在安全重连",
    "Unable to decode server payload": "无法解码服务器载荷。",
    "The secure Remodex payload could not be verified.": "无法验证安全 Remodex 载荷。",
    "Unable to decrypt the secure Remodex payload.": "无法解密安全 Remodex 载荷。",
    "The secure Remodex session is not ready yet. Try reconnecting.": "安全 Remodex 会话尚未就绪。请尝试重新连接。",
    "A thread payload was too large for the relay connection. This can happen while reopening image-heavy chats even if you didn't press Send.": "会话载荷对中继连接来说过大。重新打开包含大量图片的聊天时，即使没有点发送，也可能发生这种情况。",
    "This payload is too large for the relay connection. Try fewer or smaller images and retry.": "此载荷对中继连接来说过大。请减少图片数量或缩小图片后重试。",
    "This Mac bridge requires a newer Remodex iPhone app. Update the app, then reconnect.": "这台 Mac 桥接需要更新的 Remodex iPhone app。请更新 app 后重新连接。",
    "Remodex cannot open the local relay connection on this iPhone. Check Local Network and the app's Wi-Fi/Cellular access in Settings, then retry.": "Remodex 无法在这台 iPhone 上打开本地中继连接。请在系统设置中检查本地网络和 Wi-Fi/蜂窝网络权限后重试。",
    "The saved relay pairing is incomplete. Scan a fresh QR code to reconnect.": "已保存的中继配对不完整。请扫描新的二维码重新连接。",
    "The initial pairing metadata is missing the Mac identity key. Scan a new QR code to reconnect.": "初始配对元数据缺少 Mac 身份密钥。请扫描新的二维码重新连接。",
    "This bridge is using a different secure transport version. Update the Remodex package on your Mac and try again.": "此桥接使用了不同的安全传输版本。请更新 Mac 上的 Remodex 包后重试。",
    "This bridge is using a different secure transport version. Update Remodex on the iPhone or Mac and try again.": "此桥接使用了不同的安全传输版本。请更新 iPhone 或 Mac 上的 Remodex 后重试。",
    "The secure bridge session ID did not match the saved pairing.": "安全桥接会话 ID 与已保存配对不匹配。",
    "The bridge reported a different Mac identity for this relay session.": "桥接为此中继会话返回了不同的 Mac 身份。",
    "The secure Mac identity key did not match the paired device.": "安全 Mac 身份密钥与已配对设备不匹配。",
    "The secure Mac signature could not be verified.": "无法验证安全 Mac 签名。",
    "This iPhone does not know which relay to ask for that pairing code yet. Scan the QR code instead.": "这台 iPhone 尚不知道该向哪个中继查询此配对码。请改为扫描二维码。",
    "Could not reach the relay for this pairing code. Try again or scan the QR code.": "无法连接此配对码对应的中继。请重试或扫描二维码。",
    "The relay returned an invalid response for this pairing code.": "中继为此配对码返回了无效响应。",
    "This pairing code has expired. Generate a new one from the Mac bridge.": "此配对码已过期。请从 Mac 桥接生成新的配对码。",
    "That pairing code is not available right now. Make sure your Mac bridge is running and try again.": "该配对码当前不可用。请确认 Mac 桥接正在运行后重试。",
    "This relay does not support pairing codes yet. Scan the QR code instead.": "此中继暂不支持配对码。请改为扫描二维码。",
    "The relay could not resolve that pairing code.": "中继无法解析该配对码。",
    "The secure control payload was not valid UTF-8.": "安全控制载荷不是有效的 UTF-8。",
    "The trusted Mac relay URL is invalid.": "可信 Mac 中继 URL 无效。",
    "Could not reach the trusted Mac relay. Check your connection and try again.": "无法连接可信 Mac 中继。请检查网络后重试。",
    "The trusted Mac relay returned an invalid response.": "可信 Mac 中继返回了无效响应。",
    "The trusted Mac relay returned malformed session data.": "可信 Mac 中继返回了格式错误的会话数据。",
    "This iPhone is no longer trusted by the Mac. Scan a new QR code to reconnect.": "这台 iPhone 已不再被 Mac 信任。请扫描新的二维码重新连接。",
    "The trusted reconnect request expired. Try reconnecting again.": "可信重连请求已过期。请再次尝试重新连接。",
    "The trusted Mac relay could not resolve the current bridge session.": "可信 Mac 中继无法解析当前桥接会话。",
    "Camera is not available on this device.": "此设备不可使用相机。",
    "Clear text, files, skills, and images before starting a code review.": "开始代码审查前，请先清空文本、文件、技能和图片。",
    "Wait for the current run to finish before starting a code review.": "请等待当前运行结束后再开始代码审查。",
    "Your 5 free messages are over. Unlock Remodex Pro to keep chatting.": "你的 5 条免费消息已用完。解锁 Remodex Pro 后继续聊天。",
    "Subscriptions are unavailable right now.": "订阅服务当前不可用。",
    "Purchase pending approval.": "购买正在等待批准。"
]

private func localizedPrefixedAppMessage(_ message: String) -> String? {
    if let suffix = message.removingPrefix("Connection refused by relay server at ") {
        return "中继服务器拒绝连接：\(suffix)"
    }

    if let suffix = message.removingPrefix("Cannot reach relay server at "),
       let relayURL = suffix.removingSuffix(". Check that the iPhone can access the Mac on the local network.") {
        return "无法连接中继服务器：\(relayURL)。请确认 iPhone 可以通过本地网络访问 Mac。"
    }

    if message.hasPrefix("Connection timed out after 5s while opening the direct relay socket.") {
        return "连接中继超时，已等待 5 秒。"
    }

    if message.hasPrefix("Connection timed out after 5s while opening the relay websocket.") {
        return "连接中继超时，已等待 5 秒。"
    }

    if let suffix = message.removingPrefix("Cannot resolve server host ("),
       let code = suffix.removingSuffix("). Check the relay URL.") {
        return "无法解析服务器主机（\(code)）。请检查中继 URL。"
    }

    if let suffix = message.removingPrefix("You can attach up to "),
       let count = suffix.removingSuffix(" images per message.") {
        return "每条消息最多可附加 \(count) 张图片。"
    }

    if let suffix = message.removingPrefix("Only "),
       let count = suffix.removingSuffix(" images are allowed per message.") {
        return "每条消息最多允许 \(count) 张图片。"
    }

    if let suffix = message.removingPrefix("Queue paused: ") {
        return "队列已暂停：\(localizedAppMessage(suffix))"
    }

    if message.hasPrefix("This Mac bridge requires Remodex iPhone ")
        || message.hasPrefix("This Mac bridge is running Remodex ") {
        return "这台 Mac 桥接需要更新的 Remodex iPhone app。请更新 app 后重新连接。"
    }

    if let suffix = message.removingPrefix("Timed out waiting for the secure Remodex "),
       let kind = suffix.removingSuffix(" message.") {
        return "等待安全 Remodex \(kind) 消息超时。"
    }

    return nil
}

private extension String {
    func removingPrefix(_ prefix: String) -> String? {
        guard hasPrefix(prefix) else {
            return nil
        }

        return String(dropFirst(prefix.count))
    }

    func removingSuffix(_ suffix: String) -> String? {
        guard hasSuffix(suffix) else {
            return nil
        }

        return String(dropLast(suffix.count))
    }
}
