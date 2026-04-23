// FILE: SettingsView.swift
// Purpose: Settings for Local Mode (Codex runs on user's Mac, relay WebSocket).
// Layer: View
// Exports: SettingsView

import SwiftUI
import UIKit

private extension AppFont.Style {
    var settingsTitle: String {
        switch self {
        case .system:
            return L("System", "系统")
        case .geist:
            return "Geist"
        case .geistMono:
            return "Geist Mono"
        case .jetBrainsMono:
            return "JetBrains Mono"
        }
    }

    var settingsSubtitle: String {
        switch self {
        case .system:
            return L(
                "Use the native iOS font for regular text. Code stays monospaced.",
                "普通文本使用 iOS 原生字体，代码仍保持等宽字体。"
            )
        case .geist:
            return L(
                "Use Geist for regular text. Code stays monospaced.",
                "普通文本使用 Geist，代码仍保持等宽字体。"
            )
        case .geistMono:
            return L(
                "Use Geist Mono for regular text and code.",
                "普通文本和代码都使用 Geist Mono。"
            )
        case .jetBrainsMono:
            return L(
                "Use JetBrains Mono for regular text and code.",
                "普通文本和代码都使用 JetBrains Mono。"
            )
        }
    }
}

struct SettingsView: View {
    @Environment(CodexService.self) private var codex

    @AppStorage("codex.appFontStyle") private var appFontStyleRawValue = AppFont.defaultStoredStyleRawValue
    @AppStorage(AppLanguage.storageKey) private var appLanguageRawValue = AppLanguage.system.rawValue
    @AppStorage(CodexService.streamAssistantDeltasInBatchesDefaultsKey) private var streamAssistantDeltasInBatches = true
    @State private var isShowingMacNameSheet = false

    private let runtimeAutoValue = "__AUTO__"
    private let runtimeNormalValue = "__NORMAL__"
    private let settingsAccentColor = Color(.plan)

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 24) {
                SettingsArchivedChatsCard()
                SettingsAppearanceCard(
                    appFontStyle: appFontStyleBinding,
                    appLanguage: appLanguageBinding
                )
                SettingsNotificationsCard()
                SettingsGPTAccountCard()
                runtimeDefaultsSection
                chatDisplaySection
                SettingsUsageCard()
                connectionSection
            }
            .padding()
        }
        .id("settings-language-\(appLanguageRawValue)")
        .font(AppFont.body())
        .navigationTitle(L("Settings", "设置"))
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $isShowingMacNameSheet) {
            if let trustedPairPresentation = codex.trustedPairPresentation {
                SettingsMacNameSheet(
                    nickname: sidebarMacNicknameBinding(for: trustedPairPresentation),
                    currentName: trustedPairPresentation.name,
                    systemName: trustedPairPresentation.systemName ?? trustedPairPresentation.name
                )
            }
        }
    }

    private var appFontStyleBinding: Binding<AppFont.Style> {
        Binding(
            get: { AppFont.Style(rawValue: appFontStyleRawValue) ?? AppFont.defaultStyle },
            set: { appFontStyleRawValue = $0.rawValue }
        )
    }

    private var appLanguageBinding: Binding<AppLanguage> {
        Binding(
            get: { AppLanguage(rawValue: appLanguageRawValue) ?? .system },
            set: { appLanguageRawValue = $0.rawValue }
        )
    }

    private var keepMacAwakeWhileBridgeRunsBinding: Binding<Bool> {
        Binding(
            get: { codex.keepMacAwakeWhileBridgeRuns },
            set: { nextValue in
                codex.setKeepMacAwakeWhileBridgeRunsPreference(nextValue)
                Task { @MainActor in
                    await codex.syncBridgeKeepMacAwakePreferenceIfNeeded(showFailureInUI: true)
                }
            }
        )
    }

    // MARK: - Runtime defaults

    @ViewBuilder private var runtimeDefaultsSection: some View {
        SettingsCard(title: L("Runtime defaults", "运行默认值")) {
            HStack {
                Text(L("Model", "模型"))
                Spacer()
                Picker(L("Model", "模型"), selection: runtimeModelSelection) {
                    Text(L("Auto", "自动")).tag(runtimeAutoValue)
                    ForEach(runtimeModelOptions, id: \.id) { model in
                        Text(TurnComposerMetaMapper.modelTitle(for: model))
                            .tag(model.id)
                    }
                }
                .pickerStyle(.menu)
                .labelsHidden()
                .tint(settingsAccentColor)
            }

            HStack {
                Text(L("Reasoning", "推理强度"))
                Spacer()
                Picker(L("Reasoning", "推理强度"), selection: runtimeReasoningSelection) {
                    Text(L("Auto", "自动")).tag(runtimeAutoValue)
                    ForEach(runtimeReasoningOptions, id: \.id) { option in
                        Text(option.title).tag(option.effort)
                    }
                }
                .pickerStyle(.menu)
                .labelsHidden()
                .tint(settingsAccentColor)
                .disabled(runtimeReasoningOptions.isEmpty)
            }

            HStack {
                Text(L("Speed", "速度"))
                Spacer()
                Picker(L("Speed", "速度"), selection: runtimeServiceTierSelection) {
                    Text(L("Normal", "普通")).tag(runtimeNormalValue)
                    ForEach(CodexServiceTier.allCases, id: \.rawValue) { tier in
                        Text(tier.displayName).tag(tier.rawValue)
                    }
                }
                .pickerStyle(.menu)
                .labelsHidden()
                .tint(settingsAccentColor)
            }

            HStack {
                Text(L("Access", "访问权限"))
                Spacer()
                Picker(L("Access", "访问权限"), selection: runtimeAccessSelection) {
                    ForEach(CodexAccessMode.allCases, id: \.self) { mode in
                        Text(mode.displayName).tag(mode)
                    }
                }
                .pickerStyle(.menu)
                .labelsHidden()
                .tint(settingsAccentColor)
            }
        }
    }

    @ViewBuilder private var chatDisplaySection: some View {
        SettingsCard(title: L("Chat Display", "聊天显示")) {
            Toggle(
                L("Batch streaming text", "批量显示流式文本"),
                isOn: $streamAssistantDeltasInBatches
            )
            .tint(settingsAccentColor)

            Text(streamAssistantDeltasInBatches
                 ? L("Assistant replies update in larger chunks for smoother rendering on iPhone.", "助手回复会以更大的片段刷新，让 iPhone 渲染更顺滑。")
                 : L("Assistant replies update every incoming token, matching the previous behavior.", "助手回复会按每个传入 token 刷新，等同之前的行为。"))
                .font(AppFont.caption())
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Connection

    @ViewBuilder private var connectionSection: some View {
        SettingsCard(title: L("Connection", "连接")) {
            if let trustedPairPresentation = codex.trustedPairPresentation {
                SettingsTrustedMacCard(
                    presentation: trustedPairPresentation,
                    connectionStatusLabel: connectionStatusLabel,
                    onEditName: {
                        isShowingMacNameSheet = true
                    }
                )
            } else {
                Text(L("No paired Mac", "未配对 Mac"))
                    .font(AppFont.subheadline(weight: .semibold))
                    .foregroundStyle(.primary)
            }

            if connectionPhaseShowsProgress {
                HStack(spacing: 8) {
                    ProgressView()
                    Text(connectionProgressLabel)
                        .font(AppFont.caption())
                        .foregroundStyle(.secondary)
                }
            }

            if case .retrying(_, let message) = codex.connectionRecoveryState,
               !message.isEmpty {
                Text(localizedAppMessage(message))
                    .font(AppFont.caption())
                    .foregroundStyle(.secondary)
            }

            if let error = codex.lastErrorMessage, !error.isEmpty {
                Text(localizedAppMessage(error))
                    .font(AppFont.caption())
                    .foregroundStyle(isMacBridgeRestartInstructionMessage(error) ? Color(.systemYellow) : .red)
            }

            Divider()

            Toggle(L("Keep Mac reachable", "保持 Mac 可连接"), isOn: keepMacAwakeWhileBridgeRunsBinding)
                .tint(settingsAccentColor)

            Text(codex.keepMacAwakeWhileBridgeRuns
                 ? L("Uses macOS caffeinate while the bridge is running so your Mac stays reachable even if the display turns off. Best while charging.", "桥接运行时使用 macOS caffeinate，让 Mac 即使关闭显示器也保持可连接。充电时使用最佳。")
                 : L("Your Mac can go back to sleeping normally when the bridge is idle.", "桥接空闲时，Mac 可以恢复正常睡眠。"))
                .font(AppFont.caption())
                .foregroundStyle(.secondary)

            if !codex.isConnected {
                Text(L("Saved on this iPhone. It will sync to your Mac the next time the bridge reconnects.", "已保存在这台 iPhone 上，下次桥接重连时会同步到 Mac。"))
                    .font(AppFont.caption())
                    .foregroundStyle(.secondary)
            }

            if codex.isConnected {
                SettingsButton(L("Disconnect", "断开连接"), role: .destructive) {
                    HapticFeedback.shared.triggerImpactFeedback()
                    disconnectRelay()
                }
            } else if codex.hasTrustedMacReconnectCandidate {
                SettingsButton(L("Forget Pair", "忘记配对"), role: .destructive) {
                    HapticFeedback.shared.triggerImpactFeedback()
                    codex.forgetTrustedMac()
                }
            }
        }
    }

    private var connectionPhaseShowsProgress: Bool {
        switch codex.connectionPhase {
        case .connecting, .loadingChats, .syncing:
            return true
        case .offline, .connected:
            return false
        }
    }

    private var connectionStatusLabel: String {
        switch codex.connectionPhase {
        case .offline:
            return L("offline", "离线")
        case .connecting:
            return L("connecting", "连接中")
        case .loadingChats:
            return L("loading chats", "加载会话中")
        case .syncing:
            return L("syncing", "同步中")
        case .connected:
            return L("connected", "已连接")
        }
    }

    private var connectionProgressLabel: String {
        switch codex.connectionPhase {
        case .connecting:
            return L("Connecting to relay...", "正在连接中继...")
        case .loadingChats:
            return L("Loading chats...", "正在加载会话...")
        case .syncing:
            return L("Syncing workspace...", "正在同步工作区...")
        case .offline, .connected:
            return ""
        }
    }

    // MARK: - Actions

    private func disconnectRelay() {
        Task { @MainActor in
            await codex.disconnect()
            codex.clearSavedRelaySession()
        }
    }

    // MARK: - Runtime bindings

    private var runtimeModelOptions: [CodexModelOption] {
        TurnComposerMetaMapper.orderedModels(from: codex.availableModels)
    }

    private var runtimeReasoningOptions: [TurnComposerReasoningDisplayOption] {
        TurnComposerMetaMapper.reasoningDisplayOptions(
            from: codex.supportedReasoningEffortsForSelectedModel().map(\.reasoningEffort)
        )
    }

    private var runtimeModelSelection: Binding<String> {
        Binding(
            get: { codex.selectedModelOption()?.id ?? runtimeAutoValue },
            set: { selection in
                codex.setSelectedModelId(selection == runtimeAutoValue ? nil : selection)
            }
        )
    }

    private var runtimeReasoningSelection: Binding<String> {
        Binding(
            get: { codex.selectedReasoningEffort ?? runtimeAutoValue },
            set: { selection in
                codex.setSelectedReasoningEffort(selection == runtimeAutoValue ? nil : selection)
            }
        )
    }

    private var runtimeAccessSelection: Binding<CodexAccessMode> {
        Binding(
            get: { codex.selectedAccessMode },
            set: { codex.setSelectedAccessMode($0) }
        )
    }

    private var runtimeServiceTierSelection: Binding<String> {
        Binding(
            get: { codex.selectedServiceTier?.rawValue ?? runtimeNormalValue },
            set: { selection in
                codex.setSelectedServiceTier(
                    selection == runtimeNormalValue ? nil : CodexServiceTier(rawValue: selection)
                )
            }
        )
    }

    // Writes nicknames against the active trusted Mac so switching pairs does not reuse the wrong alias.
    private func sidebarMacNicknameBinding(for presentation: CodexTrustedPairPresentation) -> Binding<String> {
        Binding(
            get: { SidebarMacNicknameStore.nickname(for: presentation.deviceId) },
            set: { SidebarMacNicknameStore.setNickname($0, for: presentation.deviceId) }
        )
    }
}

// MARK: - Reusable card / button components

struct SettingsCard<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title.uppercased())
                .font(AppFont.caption(weight: .semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 4)
                .padding(.bottom, 8)
            VStack(alignment: .leading, spacing: 12) {
                content
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .adaptiveGlass(.regular, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        }
    }
}

struct SettingsButton: View {
    let title: String
    var role: ButtonRole?
    var isLoading: Bool = false
    let action: () -> Void

    init(_ title: String, role: ButtonRole? = nil, isLoading: Bool = false, action: @escaping () -> Void) {
        self.title = title
        self.role = role
        self.isLoading = isLoading
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            Group {
                if isLoading {
                    ProgressView()
                } else {
                    Text(title)
                }
            }
            .font(AppFont.subheadline(weight: .medium))
            .foregroundStyle(role == .destructive ? .red : (role == .cancel ? .secondary : .primary))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .background(
                (role == .destructive ? Color.red : Color.primary).opacity(0.08),
                in: RoundedRectangle(cornerRadius: 10)
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Extracted independent section views

private struct SettingsUsageCard: View {
    @Environment(CodexService.self) private var codex
    @Environment(\.scenePhase) private var scenePhase

    @State private var isRefreshing = false

    var body: some View {
        SettingsCard(title: L("Usage", "用量")) {
            UsageStatusSummaryContent(
                contextWindowUsage: nil,
                showsContextWindowSection: false,
                rateLimitBuckets: codex.rateLimitBuckets,
                isLoadingRateLimits: codex.isLoadingRateLimits,
                rateLimitsErrorMessage: codex.rateLimitsErrorMessage,
                refreshControl: UsageStatusRefreshControl(
                    title: L("Refresh", "刷新"),
                    isRefreshing: isRefreshing,
                    action: refreshStatus
                )
            )
        }
        .task {
            await refreshStatusIfNeeded()
        }
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active else { return }
            Task {
                await refreshStatusIfNeeded()
            }
        }
    }

    private func refreshStatus() {
        guard !isRefreshing else { return }
        HapticFeedback.shared.triggerImpactFeedback(style: .light)
        isRefreshing = true

        Task {
            await refreshStatusData()
            await MainActor.run {
                isRefreshing = false
            }
        }
    }

    private func refreshStatusIfNeeded() async {
        guard !isRefreshing else { return }
        guard codex.shouldAutoRefreshUsageStatus(threadId: nil) else { return }

        await MainActor.run {
            isRefreshing = true
        }
        await refreshStatusData()
        await MainActor.run {
            isRefreshing = false
        }
    }

    // Settings only needs the account-wide usage windows.
    private func refreshStatusData() async {
        await codex.refreshUsageStatus(threadId: nil)
    }
}

private struct SettingsAppearanceCard: View {
    @Binding var appFontStyle: AppFont.Style
    @Binding var appLanguage: AppLanguage
    @AppStorage("codex.useLiquidGlass") private var useLiquidGlass = true
    private let settingsAccentColor = Color(.plan)

    var body: some View {
        SettingsCard(title: L("Appearance", "外观")) {
            HStack {
                Text(L("Font", "字体"))
                Spacer()
                Picker(L("Font", "字体"), selection: $appFontStyle) {
                    ForEach(AppFont.Style.allCases) { style in
                        Text(style.settingsTitle).tag(style)
                    }
                }
                .pickerStyle(.menu)
                .labelsHidden()
                .tint(settingsAccentColor)
            }

            Text(appFontStyle.settingsSubtitle)
                .font(AppFont.caption())
                .foregroundStyle(.secondary)

            Divider()

            HStack {
                Text(L("Language", "语言"))
                Spacer()
                Picker(L("Language", "语言"), selection: $appLanguage) {
                    ForEach(AppLanguage.allCases) { language in
                        Text(language.title).tag(language)
                    }
                }
                .pickerStyle(.menu)
                .labelsHidden()
                .tint(settingsAccentColor)
            }

            Text(languageSubtitle)
                .font(AppFont.caption())
                .foregroundStyle(.secondary)

            if GlassPreference.isSupported {
                Divider()

                Toggle(L("Liquid Glass", "液态玻璃"), isOn: $useLiquidGlass)
                    .tint(settingsAccentColor)

                Text(useLiquidGlass
                     ? L("Liquid Glass effects are enabled.", "已启用液态玻璃效果。")
                     : L("Using solid material fallback.", "正在使用实体材质降级样式。"))
                    .font(AppFont.caption())
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var languageSubtitle: String {
        switch appLanguage {
        case .system:
            return L("Follow the iPhone system language.", "跟随 iPhone 系统语言。")
        case .english:
            return L("Use English for supported app pages.", "支持的应用页面会显示英文。")
        case .chinese:
            return L("Use Chinese for supported app pages.", "支持的应用页面会显示中文。")
        }
    }
}

private struct SettingsNotificationsCard: View {
    @Environment(CodexService.self) private var codex
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        SettingsCard(title: L("Notifications", "通知")) {
            HStack(spacing: 10) {
                Image(systemName: "bell.badge")
                    .foregroundStyle(.primary)
                Text(L("Status", "状态"))
                Spacer()
                Text(statusLabel)
                    .foregroundStyle(.secondary)
            }

            Text(L("Used for local alerts when a run finishes while the app is in background.", "应用在后台时，用于在任务完成后发送本地提醒。"))
                .font(AppFont.caption())
                .foregroundStyle(.secondary)

            if codex.notificationAuthorizationStatus == .notDetermined {
                SettingsButton(L("Allow notifications", "允许通知")) {
                    HapticFeedback.shared.triggerImpactFeedback()
                    Task {
                        await codex.requestNotificationPermission()
                    }
                }
            }

            if codex.notificationAuthorizationStatus == .denied {
                SettingsButton(L("Open iOS Settings", "打开 iOS 设置")) {
                    HapticFeedback.shared.triggerImpactFeedback()
                    if let url = URL(string: UIApplication.openNotificationSettingsURLString) {
                        UIApplication.shared.open(url)
                    }
                }
            }
        }
        .task {
            await codex.refreshManagedNotificationRegistrationState()
        }
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active else {
                return
            }
            Task {
                await codex.refreshManagedNotificationRegistrationState()
            }
        }
    }

    private var statusLabel: String {
        switch codex.notificationAuthorizationStatus {
        case .authorized: L("Authorized", "已授权")
        case .denied: L("Denied", "已拒绝")
        case .provisional: L("Provisional", "临时授权")
        case .ephemeral: L("Ephemeral", "临时")
        case .notDetermined: L("Not requested", "尚未请求")
        @unknown default: L("Unknown", "未知")
        }
    }
}

private struct SettingsGPTAccountCard: View {
    @State private var isShowingMacLoginInfo = false

    var body: some View {
        SettingsCard(title: L("ChatGPT voice mode", "ChatGPT 语音模式")) {
            Button {
                HapticFeedback.shared.triggerImpactFeedback(style: .light)
                isShowingMacLoginInfo = true
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "info.circle")
                        .font(AppFont.subheadline(weight: .medium))
                    Text(L("Info", "说明"))
                        .font(AppFont.subheadline(weight: .medium))
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(AppFont.caption(weight: .semibold))
                        .foregroundStyle(.tertiary)
                }
                .foregroundStyle(.primary)
                .padding(.vertical, 10)
                .padding(.horizontal, 14)
                .adaptiveGlass(.regular, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            .buttonStyle(.plain)
        }
        .sheet(isPresented: $isShowingMacLoginInfo) {
            GPTVoiceSetupSheet()
        }
    }
}

private struct SettingsArchivedChatsCard: View {
    @Environment(CodexService.self) private var codex

    private var archivedCount: Int {
        codex.threads.filter { $0.syncState == .archivedLocal }.count
    }

    var body: some View {
        SettingsCard(title: L("Archived Chats", "已归档会话")) {
            NavigationLink {
                ArchivedChatsView()
            } label: {
                HStack {
                    Label(L("Archived Chats", "已归档会话"), systemImage: "archivebox")
                        .font(AppFont.subheadline(weight: .medium))
                    Spacer()
                    if archivedCount > 0 {
                        Text("\(archivedCount)")
                            .font(AppFont.caption(weight: .medium))
                            .foregroundStyle(.secondary)
                    }
                    Image(systemName: "chevron.right")
                        .font(AppFont.caption(weight: .semibold))
                        .foregroundStyle(.tertiary)
                }
            }
            .buttonStyle(.plain)
        }
    }
}

private struct SettingsTrustedMacCard: View {
    let presentation: CodexTrustedPairPresentation
    let connectionStatusLabel: String
    let onEditName: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                HStack(spacing: 10) {
                    Image(systemName: "desktopcomputer")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: 32, height: 32)
                        .adaptiveGlass(.regular, in: Circle())

                    VStack(alignment: .leading, spacing: 3) {
                        Text("Mac")
                            .font(AppFont.caption(weight: .semibold))
                            .foregroundStyle(.secondary)

                        Text(presentation.name)
                            .font(AppFont.subheadline(weight: .semibold))
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.85)
                    }
                }

                Spacer(minLength: 8)

                Button(action: onEditName) {
                    Image(systemName: "pencil")
                        .font(AppFont.caption(weight: .semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: 30, height: 30)
                        .adaptiveGlass(.regular, in: Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(L("Edit Mac name", "编辑 Mac 名称"))
            }

            HStack(spacing: 8) {
                SettingsStatusPill(label: connectionStatusLabel)

                if let title = compactTitle {
                    SettingsStatusPill(label: title)
                }
            }

            if let systemName = presentation.systemName,
               !systemName.isEmpty {
                labeledRow(L("System", "系统"), value: systemName)
            }

            if let detail = presentation.detail,
               !detail.isEmpty {
                labeledRow(L("Status", "状态"), value: detail)
            }
        }
        .padding(14)
        .adaptiveGlass(.regular, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private var compactTitle: String? {
        let trimmed = presentation.title.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    @ViewBuilder
    private func labeledRow(_ label: String, value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(label)
                .font(AppFont.caption(weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(width: 48, alignment: .leading)

            Text(value)
                .font(AppFont.subheadline())
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

private struct SettingsStatusPill: View {
    let label: String

    var body: some View {
        Text(label)
            .font(AppFont.caption(weight: .semibold))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .adaptiveGlass(.regular, in: Capsule(style: .continuous))
    }
}

private struct SettingsMacNameSheet: View {
    @Binding var nickname: String
    let currentName: String
    let systemName: String

    @Environment(\.dismiss) private var dismiss
    @State private var draftNickname = ""

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(L("Mac name", "Mac 名称"))
                        .font(AppFont.subheadline(weight: .semibold))
                        .foregroundStyle(.primary)

                    Text(currentName)
                        .font(AppFont.caption())
                        .foregroundStyle(.secondary)
                }

                TextField(systemName, text: $draftNickname)
                    .textInputAutocapitalization(.words)
                    .disableAutocorrection(true)
                    .font(AppFont.subheadline())
                    .padding(.horizontal, 12)
                    .padding(.vertical, 11)
                    .adaptiveGlass(.regular, in: RoundedRectangle(cornerRadius: 12, style: .continuous))

                Text(L("This nickname stays on this iPhone and appears anywhere this Mac is shown.", "这个昵称只保存在这台 iPhone 上，并会显示在所有出现这台 Mac 的地方。"))
                    .font(AppFont.caption())
                    .foregroundStyle(.secondary)

                VStack(spacing: 10) {
                    SettingsButton(L("Use Default", "使用默认名称"), role: .cancel) {
                        nickname = ""
                        dismiss()
                    }
                    .opacity(canResetToDefault ? 1 : 0.5)
                    .disabled(!canResetToDefault)

                    SettingsButton(L("Save", "保存")) {
                        nickname = draftNickname
                        dismiss()
                    }
                    .opacity(canSave ? 1 : 0.5)
                    .disabled(!canSave)
                }

                Spacer(minLength: 0)
            }
            .padding(20)
            .presentationDetents([.height(300)])
            .presentationDragIndicator(.visible)
            .navigationTitle(L("Edit Mac Name", "编辑 Mac 名称"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L("Close", "关闭")) {
                        dismiss()
                    }
                }
            }
            .onAppear {
                draftNickname = nickname
            }
        }
    }

    private var canSave: Bool {
        draftNickname != nickname
    }

    private var canResetToDefault: Bool {
        !nickname.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

#Preview {
    NavigationStack {
        SettingsView()
            .environment(CodexService())
    }
}
