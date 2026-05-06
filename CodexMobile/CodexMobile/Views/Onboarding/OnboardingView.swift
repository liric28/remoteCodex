// FILE: OnboardingView.swift
// Purpose: Split onboarding flow — swipeable pages with fixed bottom bar.
// Layer: View
// Exports: OnboardingView
// Depends on: SwiftUI, OnboardingWelcomePage, OnboardingFeaturesPage, OnboardingStepPage

import SwiftUI

struct OnboardingView: View {
    let onContinue: () -> Void
    @State private var currentPage = 0
    @State private var isShowingCodexInstallReminder = false

    private let pageCount = 5
    private let codexInstallStepIndex = 2
    private let codexInstallCommand = "npm install -g @openai/codex@latest"

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VStack(spacing: 0) {
                TabView(selection: $currentPage) {
                    OnboardingWelcomePage()
                        .tag(0)

                    OnboardingFeaturesPage()
                        .tag(1)

                    OnboardingStepPage(
                        stepNumber: 1,
                        icon: "terminal",
                        title: L("Install Codex CLI", "安装 Codex CLI"),
                        description: L("The AI coding agent that lives in your terminal. Remodex connects to it from your iPhone.", "运行在终端里的 AI 编码代理。Remodex 会从 iPhone 连接到它。"),
                        command: codexInstallCommand
                    )
                    .tag(2)

                    OnboardingStepPage(
                        stepNumber: 2,
                        icon: "link",
                        title: L("Install the Bridge", "安装桥接"),
                        description: L("A lightweight relay that securely connects your Mac to your iPhone.", "一个轻量级中继，用于安全连接你的 Mac 和 iPhone。"),
                        command: "npm install -g remodex@latest",
                        commandCaption: L("Remodex uses macOS caffeinate by default while the bridge is running so your Mac stays reachable even if the display turns off. You can change this later in Settings.", "桥接运行时，Remodex 默认使用 macOS caffeinate，让 Mac 即使关闭显示器也保持可连接。你之后可以在设置中修改。")
                    )
                    .tag(3)

                    OnboardingStepPage(
                        stepNumber: 3,
                        icon: "qrcode.viewfinder",
                        title: L("Start Pairing", "开始配对"),
                        description: L("Run this on your Mac. A QR code will appear in your terminal — scan it next.", "在 Mac 上运行此命令。终端中会出现二维码，下一步扫描它。"),
                        command: "remodex up"
                    )
                    .tag(4)
                }
                .tabViewStyle(.page(indexDisplayMode: .never))

                bottomBar
            }
        }
        .preferredColorScheme(.dark)
        .alert("Install Codex CLI First", isPresented: $isShowingCodexInstallReminder) {
            Button("Stay Here", role: .cancel) {}
            Button("Continue Anyway") {
                advanceToNextPage()
            }
        } message: {
            Text("Copy and paste \"\(codexInstallCommand)\" on your Mac before moving on. Remodex will not work until Codex CLI is installed and available in your PATH.")
        }
    }

    // MARK: - Bottom bar

    private var bottomBar: some View {
        VStack(spacing: 20) {
            // Animated pill dots
            HStack(spacing: 8) {
                ForEach(0..<pageCount, id: \.self) { i in
                    Capsule()
                        .fill(i == currentPage ? Color.white : Color.white.opacity(0.18))
                        .frame(width: i == currentPage ? 24 : 8, height: 8)
                }
            }
            .animation(.spring(response: 0.35, dampingFraction: 0.8), value: currentPage)

            // CTA button
            PrimaryCapsuleButton(
                title: buttonTitle,
                systemImage: currentPage == pageCount - 1 ? "qrcode" : nil,
                action: handleContinue
            )

            OpenSourceBadge(style: .light)
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 12)
        .background(
            LinearGradient(
                colors: [.clear, .black.opacity(0.6), .black],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: 50)
            .offset(y: -50),
            alignment: .top
        )
    }

    // MARK: - State

    private var buttonTitle: String {
        switch currentPage {
        case 0: return L("Get Started", "开始使用")
        case 1: return L("Set Up", "开始设置")
        case pageCount - 1: return L("Scan QR Code", "扫描二维码")
        default: return L("Continue", "继续")
        }
    }

    private func handleContinue() {
        // The CLI install step is a hard requirement, so warn before advancing.
        if currentPage == codexInstallStepIndex {
            isShowingCodexInstallReminder = true
            return
        }

        if currentPage < pageCount - 1 {
            advanceToNextPage()
        } else {
            onContinue()
        }
    }

    private func advanceToNextPage() {
        withAnimation(.easeInOut(duration: 0.3)) {
            currentPage += 1
        }
    }
}

// MARK: - Previews

#Preview("Full Flow") {
    OnboardingView {
        print("Continue tapped")
    }
}

#Preview("Light Override") {
    OnboardingView {
        print("Continue tapped")
    }
    .preferredColorScheme(.light)
}
