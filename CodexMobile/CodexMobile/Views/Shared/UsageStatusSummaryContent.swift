// FILE: UsageStatusSummaryContent.swift
// Purpose: Shared usage + rate-limit summary used by status, settings, and context popovers.
// Layer: View Component
// Exports: UsageStatusSummaryContent, UsageStatusRefreshControl
// Depends on: SwiftUI, ContextWindowUsage, CodexRateLimitStatus

import SwiftUI

struct UsageStatusRefreshControl {
    let title: String
    let systemImage: String
    let isRefreshing: Bool
    let action: () -> Void

    init(
        title: String,
        systemImage: String = "arrow.clockwise",
        isRefreshing: Bool,
        action: @escaping () -> Void
    ) {
        self.title = title
        self.systemImage = systemImage
        self.isRefreshing = isRefreshing
        self.action = action
    }
}

struct UsageStatusSummaryContent: View {
    enum ContextPlacement {
        case top
        case bottom
    }

    let contextWindowUsage: ContextWindowUsage?
    let showsContextWindowSection: Bool
    let rateLimitBuckets: [CodexRateLimitBucket]
    let isLoadingRateLimits: Bool
    let rateLimitsErrorMessage: String?
    let contextPlacement: ContextPlacement
    let showsRateLimitHeader: Bool
    let leadingControl: UsageStatusRefreshControl?
    let refreshControl: UsageStatusRefreshControl?

    init(
        contextWindowUsage: ContextWindowUsage?,
        showsContextWindowSection: Bool = true,
        rateLimitBuckets: [CodexRateLimitBucket],
        isLoadingRateLimits: Bool,
        rateLimitsErrorMessage: String?,
        contextPlacement: ContextPlacement = .top,
        showsRateLimitHeader: Bool = true,
        leadingControl: UsageStatusRefreshControl? = nil,
        refreshControl: UsageStatusRefreshControl? = nil
    ) {
        self.contextWindowUsage = contextWindowUsage
        self.showsContextWindowSection = showsContextWindowSection
        self.rateLimitBuckets = rateLimitBuckets
        self.isLoadingRateLimits = isLoadingRateLimits
        self.rateLimitsErrorMessage = rateLimitsErrorMessage
        self.contextPlacement = contextPlacement
        self.showsRateLimitHeader = showsRateLimitHeader
        self.leadingControl = leadingControl
        self.refreshControl = refreshControl
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if leadingControl != nil || refreshControl != nil {
                actionControlsRow
            }

            if showsContextWindowSection && contextPlacement == .top {
                contextSection
            }

            if showsDividerBeforeRateLimits {
                Divider()
            }

            rateLimitsSection

            if showsContextWindowSection && contextPlacement == .bottom {
                Divider()
                contextSection
            }
        }
    }

    // ─── Shared Sections ────────────────────────────────────────

    private var showsDividerBeforeRateLimits: Bool {
        guard showsContextWindowSection, contextPlacement == .top else { return false }
        return !rateLimitRows.isEmpty || isLoadingRateLimits || !(rateLimitsErrorMessage?.isEmpty ?? true)
    }

    private var rateLimitsSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            if showsRateLimitHeader {
                HStack {
                    Text(L("Rate limits", "速率限制"))
                        .font(AppFont.subheadline(weight: .semibold))

                    Spacer(minLength: 12)

                    if isLoadingRateLimits {
                        ProgressView()
                            .controlSize(.small)
                    }
                }
            }

            if !rateLimitRows.isEmpty {
                VStack(alignment: .leading, spacing: 14) {
                    ForEach(rateLimitRows) { row in
                        rateLimitRow(row)
                    }
                }
            } else if let rateLimitsErrorMessage, !rateLimitsErrorMessage.isEmpty {
                Text(rateLimitsErrorMessage)
                    .font(AppFont.caption())
                    .foregroundStyle(.secondary)
            } else if isLoadingRateLimits {
                Text(L("Loading current limits...", "正在加载当前限制..."))
                    .font(AppFont.caption())
                    .foregroundStyle(.secondary)
            } else {
                Text(L("Rate limits are unavailable for this account.", "当前账号无法获取速率限制。"))
                    .font(AppFont.caption())
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var contextSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(L("Context window", "上下文窗口"))
                .font(AppFont.subheadline(weight: .semibold))

            if let contextWindowUsage {
                metricRow(
                    label: L("Context", "上下文"),
                    value: L("\(contextWindowUsage.percentRemaining)% left", "剩余 \(contextWindowUsage.percentRemaining)%"),
                    detail: "(\(compactTokenCount(contextWindowUsage.tokensUsed)) used / \(compactTokenCount(contextWindowUsage.tokenLimit)))",
                    monospace: true
                )

                progressBar(progress: contextWindowUsage.fractionUsed)
            } else {
                metricRow(
                    label: L("Context", "上下文"),
                    value: L("Unavailable", "不可用"),
                    detail: L("Waiting for token usage", "等待 token 用量数据")
                )
            }
        }
    }

    // ─── Row Rendering ──────────────────────────────────────────

    private var rateLimitRows: [CodexRateLimitDisplayRow] {
        CodexRateLimitBucket.visibleDisplayRows(from: rateLimitBuckets)
    }

    private var actionControlsRow: some View {
        HStack(alignment: .center, spacing: 12) {
            if let leadingControl {
                actionButton(leadingControl, alignment: .leading)
            }

            Spacer(minLength: 0)

            if let refreshControl {
                actionButton(refreshControl, alignment: .trailing)
            }
        }
    }

    private func actionButton(_ control: UsageStatusRefreshControl, alignment: Alignment) -> some View {
        Button(action: control.action) {
            HStack(spacing: 8) {
                if control.isRefreshing {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Image(systemName: control.systemImage)
                        .font(AppFont.system(size: 12, weight: .semibold))
                }

                Text(control.isRefreshing ? L("Refreshing...", "刷新中...") : control.title)
                    .font(AppFont.subheadline(weight: .semibold))
            }
            .frame(maxWidth: .infinity, alignment: alignment)
        }
        .buttonStyle(.plain)
        .disabled(control.isRefreshing)
    }

    private func rateLimitRow(_ row: CodexRateLimitDisplayRow) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(row.label)
                    .font(AppFont.mono(.callout))
                    .foregroundStyle(.secondary)

                Spacer(minLength: 12)

                Text(L("\(row.window.remainingPercent)% left", "剩余 \(row.window.remainingPercent)%"))
                    .font(AppFont.mono(.callout))
                    .foregroundStyle(.primary)

                if let resetText = resetLabel(for: row.window) {
                    Text("(\(resetText))")
                        .font(AppFont.mono(.caption))
                        .foregroundStyle(.secondary)
                }
            }

            progressBar(progress: Double(row.window.clampedUsedPercent) / 100)
        }
    }

    private func metricRow(
        label: String,
        value: String,
        detail: String? = nil,
        monospace: Bool = false
    ) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text("\(label):")
                .font(AppFont.mono(.callout))
                .foregroundStyle(.secondary)

            Spacer(minLength: 12)

            Text(value)
                .font(monospace ? AppFont.mono(.callout) : AppFont.headline(weight: .semibold))
                .foregroundStyle(.primary)

            if let detail {
                Text(detail)
                    .font(AppFont.mono(.caption))
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 0)
        }
    }

    private func progressBar(progress: Double) -> some View {
        let clampedProgress = min(max(progress, 0), 1)

        return GeometryReader { geometry in
            let totalWidth = max(geometry.size.width, 1)

            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.primary.opacity(0.1))

                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.primary)
                    .frame(width: totalWidth * CGFloat(clampedProgress))
            }
        }
        .frame(height: 14)
    }

    // ─── Formatting Helpers ─────────────────────────────────────

    private func compactTokenCount(_ count: Int) -> String {
        switch count {
        case 1_000_000...:
            let value = Double(count) / 1_000_000
            return value.truncatingRemainder(dividingBy: 1) == 0
                ? "\(Int(value))M"
                : String(format: "%.1fM", value)
        case 1_000...:
            let value = Double(count) / 1_000
            return value.truncatingRemainder(dividingBy: 1) == 0
                ? "\(Int(value))K"
                : String(format: "%.1fK", value)
        default:
            return groupedTokenCount(count)
        }
    }

    private func groupedTokenCount(_ count: Int) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        return formatter.string(from: NSNumber(value: count)) ?? "\(count)"
    }

    private func resetLabel(for window: CodexRateLimitWindow) -> String? {
        guard let resetsAt = window.resetsAt else { return nil }

        let calendar = Calendar.current
        let now = Date()

        if calendar.isDate(resetsAt, inSameDayAs: now) {
            let formatter = DateFormatter()
            formatter.dateFormat = "HH:mm"
            return L("resets \(formatter.string(from: resetsAt))", "\(formatter.string(from: resetsAt)) 重置")
        }

        let formatter = DateFormatter()
        formatter.dateFormat = "d MMM HH:mm"
        return L("resets \(formatter.string(from: resetsAt))", "\(formatter.string(from: resetsAt)) 重置")
    }
}
