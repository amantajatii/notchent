import SwiftUI

/// Remaining plan limits for each supported agent, shown on Home.
struct UsageSection: View {
    @ObservedObject var shell: IslandShell

    var body: some View {
        VStack(spacing: 12) {
            UsageRow(title: "Codex", setupKey: "usageCodexMissing", store: shell.codexUsage, shell: shell)
            UsageRow(title: "Claude", setupKey: "usageClaudeSetup", store: shell.claudeUsage, shell: shell)
        }
    }
}

struct UsageRow: View {
    let title: String
    /// Shown when the data source has not been set up on this Mac.
    let setupKey: String
    @ObservedObject var store: UsageStore
    @ObservedObject var shell: IslandShell

    private static let lowRemainingPercent = 10
    private let secondary = Color(white: 0.65)

    var body: some View {
        HStack(spacing: 20) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.system(size: 12, weight: .semibold))
                Text(shell.text("usageRemaining")).font(.system(size: 10)).foregroundStyle(secondary)
            }.frame(width: 62, alignment: .leading)
            if let usage = store.snapshot {
                ForEach(Array(usage.windows.enumerated()), id: \.offset) { _, window in windowView(window) }
            } else {
                Text(shell.text(statusKey)).font(.system(size: 11)).foregroundStyle(secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            refreshButton
        }.frame(minHeight: 38)
            .help(observedHelp)
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

    private var refreshButton: some View {
        Button { Task { await store.refresh() } } label: {
            Image(systemName: "arrow.clockwise").font(.system(size: 12, weight: .medium))
                .foregroundStyle(Color(white: 0.7)).frame(width: 28, height: 28)
        }.accessibilityLabel(shell.text("usageRefresh") + " " + title).help(shell.text("usageRefresh"))
            .disabled(store.refreshing).opacity(store.refreshing ? 0.4 : 1)
    }

    private func windowView(_ window: UsageWindow) -> some View {
        TimelineView(.periodic(from: .now, by: 1)) { timeline in
            let expired = window.resetsAt.map { $0 <= timeline.date } ?? false
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(windowLabel(window)).foregroundStyle(Color(white: 0.7))
                    Spacer(minLength: 4)
                    Text(expired ? shell.text("usageUpdating") : "\(window.remainingPercent)%")
                        .monospacedDigit().foregroundStyle(.white)
                }.font(.system(size: 11, weight: .medium))
                bar(remaining: expired ? 0 : window.remainingPercent)
                if let reset = window.resetsAt, !expired {
                    Text("\(shell.text("usageResetIn")) \(reset, style: .relative)")
                        .font(.system(size: 10)).monospacedDigit()
                        .foregroundStyle(secondary).lineLimit(1)
                }
            }.frame(maxWidth: .infinity)
                .help(window.resetsAt.map { shell.text("usageReset") + " " + $0.formatted(date: .abbreviated, time: .shortened) } ?? "")
                .accessibilityElement(children: .combine)
        }
    }

    private func bar(remaining: Int) -> some View {
        GeometryReader { geometry in
            Capsule().fill(Color(white: 0.16))
                .overlay(alignment: .leading) {
                    Capsule().fill(remaining <= Self.lowRemainingPercent ? Color.orange : Color.white)
                        .frame(width: geometry.size.width * CGFloat(remaining) / 100)
                }
        }.frame(height: 3).accessibilityHidden(true)
    }

    private func windowLabel(_ window: UsageWindow) -> String {
        guard let minutes = window.durationMinutes else { return shell.text("usageWindow") }
        if minutes.isMultiple(of: 1440) { return "\(minutes / 1440)d" }
        if minutes.isMultiple(of: 60) { return "\(minutes / 60)h" }
        return "\(minutes)m"
    }
}
