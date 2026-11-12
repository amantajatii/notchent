import SwiftUI

/// Remaining plan limits for each supported agent, shown on Home as widget-style cards.
struct UsageSection: View {
    @ObservedObject var shell: IslandShell

    var body: some View {
        HStack(spacing: 12) {
            UsageCard(title: "Codex", symbol: "chevron.left.forwardslash.chevron.right", setupKey: "usageCodexMissing",
                      store: shell.codexUsage, shell: shell)
            UsageCard(title: "Claude", symbol: "sparkle", setupKey: "usageClaudeSetup",
                      store: shell.claudeUsage, shell: shell)
        }
    }
}

private enum UsageStyle {
    static let cardRadius: CGFloat = 18
    static let cardHeight: CGFloat = 118
    static let ringSize: CGFloat = 46
    static let ringWidth: CGFloat = 5
    static let lowRemaining = 25
    static let criticalRemaining = 10
    static let secondary = Color(white: 0.6)
    static let card = Color(white: 1, opacity: 0.07)
    static let track = Color(white: 1, opacity: 0.12)

    static func tint(remaining: Int) -> Color {
        if remaining <= criticalRemaining { return .red }
        if remaining <= lowRemaining { return .orange }
        return .green
    }
}

struct UsageCard: View {
    let title: String
    let symbol: String
    /// Shown when the data source has not been set up on this Mac.
    let setupKey: String
    @ObservedObject var store: UsageStore
    @ObservedObject var shell: IslandShell

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header
            if let usage = store.snapshot, !usage.windows.isEmpty {
                HStack(spacing: 0) {
                    ForEach(Array(usage.windows.enumerated()), id: \.offset) { _, window in
                        UsageRing(window: window, shell: shell).frame(maxWidth: .infinity)
                    }
                }
            } else {
                emptyState
            }
        }.padding(14)
            .frame(maxWidth: .infinity, minHeight: UsageStyle.cardHeight, alignment: .topLeading)
            .background(UsageStyle.card, in: RoundedRectangle(cornerRadius: UsageStyle.cardRadius, style: .continuous))
            .help(observedHelp)
            .animation(.smooth, value: store.snapshot)
    }

    private var header: some View {
        HStack(spacing: 6) {
            Image(systemName: symbol).font(.system(size: 11, weight: .semibold)).foregroundStyle(UsageStyle.secondary)
            Text(title).font(.system(size: 13, weight: .semibold))
            Spacer(minLength: 4)
            Text(shell.text("usageRemaining")).font(.system(size: 10, weight: .medium)).foregroundStyle(UsageStyle.secondary)
            Button { Task { await store.refresh() } } label: {
                Image(systemName: "arrow.clockwise").font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(UsageStyle.secondary).frame(width: 20, height: 20)
                    .rotationEffect(.degrees(store.refreshing ? 360 : 0))
                    .animation(store.refreshing ? .linear(duration: 0.8).repeatForever(autoreverses: false) : .default, value: store.refreshing)
            }.buttonStyle(.plain).contentShape(Circle())
                .accessibilityLabel(shell.text("usageRefresh") + " " + title).help(shell.text("usageRefresh"))
                .disabled(store.refreshing)
        }
    }

    private var emptyState: some View {
        Text(shell.text(statusKey)).font(.system(size: 11)).foregroundStyle(UsageStyle.secondary)
            .lineLimit(3).fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }

    private var statusKey: String {
        // Only the first read shows "loading"; later polls keep the last message steady.
        if store.refreshing && store.failure == nil { return "usageLoading" }
        return store.failure == .notConfigured ? setupKey : "usageUnavailable"
    }

    private var observedHelp: String {
        guard let observed = store.snapshot?.observedAt else { return "" }
        return shell.text("usageObserved") + " " + observed.formatted(date: .omitted, time: .shortened)
    }
}

/// A capacity ring in the style of the system Batteries widget.
private struct UsageRing: View {
    let window: UsageWindow
    @ObservedObject var shell: IslandShell

    var body: some View {
        TimelineView(.periodic(from: .now, by: 30)) { timeline in
            let expired = window.resetsAt.map { $0 <= timeline.date } ?? false
            let remaining = expired ? 0 : window.remainingPercent
            VStack(spacing: 6) {
                ZStack {
                    Circle().stroke(UsageStyle.track, lineWidth: UsageStyle.ringWidth)
                    Circle().trim(from: 0, to: CGFloat(remaining) / 100)
                        .stroke(UsageStyle.tint(remaining: remaining), style: StrokeStyle(lineWidth: UsageStyle.ringWidth, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                    Text(expired ? "–" : "\(remaining)%")
                        .font(.system(size: 12, weight: .semibold, design: .rounded)).monospacedDigit()
                        .minimumScaleFactor(0.7)
                }.frame(width: UsageStyle.ringSize, height: UsageStyle.ringSize)
                VStack(spacing: 1) {
                    Text(windowLabel).font(.system(size: 11, weight: .semibold))
                    Text(resetText(now: timeline.date, expired: expired))
                        .font(.system(size: 10)).monospacedDigit().foregroundStyle(UsageStyle.secondary).lineLimit(1)
                }
            }.accessibilityElement(children: .ignore)
                .accessibilityLabel("\(windowLabel), \(remaining)% \(shell.text("usageRemaining")), "
                    + (expired ? shell.text("usageUpdating") : "\(shell.text("usageResetIn")) \(resetText(now: timeline.date, expired: false))"))
                .help(window.resetsAt.map { shell.text("usageReset") + " " + $0.formatted(date: .abbreviated, time: .shortened) } ?? "")
        }
    }

    private var windowLabel: String {
        guard let minutes = window.durationMinutes else { return shell.text("usageWindow") }
        if minutes.isMultiple(of: 1440) { return "\(minutes / 1440)d" }
        if minutes.isMultiple(of: 60) { return "\(minutes / 60)h" }
        return "\(minutes)m"
    }

    private func resetText(now: Date, expired: Bool) -> String {
        if expired { return shell.text("usageUpdating") }
        guard let reset = window.resetsAt else { return " " }
        return UsageDuration.compact(reset.timeIntervalSince(now))
    }
}

enum UsageDuration {
    /// "2d 17h", "1h 38m", "12m", "<1m": the two largest units, like system widgets.
    static func compact(_ interval: TimeInterval) -> String {
        let minutes = Int(max(0, interval) / 60)
        let days = minutes / 1440, hours = (minutes % 1440) / 60, rest = minutes % 60
        if days > 0 { return hours > 0 ? "\(days)d \(hours)h" : "\(days)d" }
        if hours > 0 { return rest > 0 ? "\(hours)h \(rest)m" : "\(hours)h" }
        return minutes > 0 ? "\(minutes)m" : "<1m"
    }
}
