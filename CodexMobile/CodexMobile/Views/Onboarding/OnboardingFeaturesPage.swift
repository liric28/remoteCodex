// FILE: OnboardingFeaturesPage.swift
// Purpose: Compact feature highlights page shown after the welcome splash.
// Layer: View
// Exports: OnboardingFeaturesPage
// Depends on: SwiftUI, AppFont

import SwiftUI

struct OnboardingFeaturesPage: View {
    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            VStack(spacing: 40) {
                VStack(spacing: 10) {
                    Text("What you get")
                        .font(AppFont.system(size: 28, weight: .bold))
                        .foregroundStyle(.white)

                    Text("Everything runs on your Mac.\nYour phone is the remote.")
                        .font(AppFont.subheadline())
                        .foregroundStyle(.white.opacity(0.45))
                        .multilineTextAlignment(.center)
                        .lineSpacing(3)
                }

                VStack(spacing: 16) {
                    featureRow(
                        icon: "hare.fill",
                        color: .yellow,
                        title: L("Fast mode", "快速模式"),
                        subtitle: L("Lower-latency turns for quick interactions", "低延迟回合，适合快速交互")
                    )
                    featureRow(
                        icon: "arrow.triangle.branch",
                        color: .green,
                        title: L("Git from your phone", "在手机上操作 Git"),
                        subtitle: L("Commit, push, pull, and switch branches", "提交、推送、拉取和切换分支")
                    )
                    featureRow(
                        icon: "lock.shield.fill",
                        color: .cyan,
                        title: L("End-to-end encrypted", "端到端加密"),
                        subtitle: L("The relay never sees your prompts or code", "中继永远看不到你的提示词或代码")
                    )
                    featureRow(
                        icon: "waveform",
                        color: .purple,
                        title: L("Voice mode", "语音模式"),
                        subtitle: L("Talk to Codex with speech-to-text", "用语音转文字和 Codex 对话")
                    )
                    featureRow(
                        icon: "point.3.connected.trianglepath.dotted",
                        color: .orange,
                        title: L("Subagents, skills and /commands", "子代理、技能和 /命令"),
                        subtitle: L("Spawn and monitor parallel agents from your phone", "从手机创建并监控并行代理")
                    )
                }
                .padding(.horizontal, 4)
            }
            .padding(.horizontal, 28)

            Spacer()
        }
    }

    @ViewBuilder
    private func featureRow(icon: String, color: Color, title: String, subtitle: String) -> some View {
        HStack(spacing: 16) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(color)
                .frame(width: 40, height: 40)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(color.opacity(0.12))
                )

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(AppFont.subheadline(weight: .semibold))
                    .foregroundStyle(.white)

                Text(subtitle)
                    .font(AppFont.caption())
                    .foregroundStyle(.white.opacity(0.4))
                    .lineLimit(2)
            }

            Spacer(minLength: 0)
        }
    }
}

#Preview {
    ZStack {
        Color.black.ignoresSafeArea()
        OnboardingFeaturesPage()
    }
    .preferredColorScheme(.dark)
}
