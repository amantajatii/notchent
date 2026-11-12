import SwiftUI

/// Remaining Codex and Claude plan limits as a row of open arcs, like the activity arcs in a
/// Live Activity: the arc fills with what is left, its colour says whether that is healthy.
struct UsageSection: View {
    @ObservedObject var shell: IslandShell

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            UsageGroup(service: "Codex", setupKey: "usageCodexMissing", store: shell.codexUsage, shell: shell)
            UsageGroup(service: "Claude", setupKey: "usageClaudeSetup", store: shell.claudeUsage, shell: shell)
        }
    }
}

enum UsageStyle {
    static let criticalRemaining = 10
    static let lowRemaining = 25
    static let arcSize: CGFloat = 54
    static let arcWidth: CGFloat = 6
    /// An open 270° arc with its gap at the bottom.
    static let arcSweep = 0.75

    /// Batteries-widget colours: green while healthy, orange when low, red when nearly gone.
    static func tint(remaining: Int) -> Color {
        if remaining <= criticalRemaining { return IslandDesign.danger }
        if remaining <= lowRemaining { return IslandDesign.warning }
        return IslandDesign.success
    }
}

/// One service: its two windows (5h, 7d) as arcs, or a status line when no numbers are available.
struct UsageGroup: View {
    let service: String
    /// Shown when the data source has not been set up on this Mac.
    let setupKey: String
    @ObservedObject var store: UsageStore
    @ObservedObject var shell: IslandShell

    var body: some View {
        let windows = store.snapshot?.windows ?? []
        Button { Task { await store.refresh() } } label: {
            HStack(alignment: .top, spacing: 0) {
                if windows.isEmpty {
                    UsageArc(service: service, window: nil, status: shell.text(statusKey), shell: shell)
                } else {
                    ForEach(Array(windows.enumerated()), id: \.offset) { _, window in
                        UsageArc(service: service, window: window, status: nil, shell: shell)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .opacity(store.refreshing ? 0.6 : 1)
            .animation(IslandDesign.spring, value: store.snapshot)
        }
        .buttonStyle(PressableStyle())
        .disabled(store.refreshing)
        .help(helpText)
        .accessibilityHint(shell.text("usageRefresh"))
    }

    private var statusKey: String {
        // Only the first read shows "loading"; later polls keep the last message steady.
        if store.refreshing && store.failure == nil { return "usageLoading" }
        return store.failure == .notConfigured ? setupKey : "usageUnavailable"
    }

    private var helpText: String {
        var lines = [shell.text("usageRefresh")]
        if let observed = store.snapshot?.observedAt {
            lines.append(shell.text("usageObserved") + " " + observed.formatted(date: .omitted, time: .shortened))
        }
        return lines.joined(separator: "\n")
    }
}

/// An open arc gauge with the window inside, the remaining percentage below in its status colour,
/// and the service and reset countdown as captions.
private struct UsageArc: View {
    let service: String
    let window: UsageWindow?
    /// Replaces the value when there is no window (not configured, unavailable, loading).
    let status: String?
    @ObservedObject var shell: IslandShell

    var body: some View {
        TimelineView(.periodic(from: .now, by: 30)) { timeline in
            let expired = window?.resetsAt.map { $0 <= timeline.date } ?? false
            let remaining = (window == nil || expired) ? 0 : window?.remainingPercent ?? 0
            let tint = window == nil || expired ? IslandDesign.tertiary : UsageStyle.tint(remaining: remaining)
            VStack(spacing: 6) {
                ZStack {
                    arc(fraction: 1).stroke(IslandDesign.fill, style: stroke)
                    arc(fraction: CGFloat(remaining) / 100).stroke(tint, style: stroke)
                    Text(windowLabel).font(.system(size: 11, weight: .semibold, design: .rounded))
                        .foregroundStyle(IslandDesign.secondary)
                }
                .frame(width: UsageStyle.arcSize, height: UsageStyle.arcSize)
                VStack(spacing: 1) {
                    if let status {
                        Text(service).islandLabel()
                        Text(status).font(IslandDesign.footnote).foregroundStyle(IslandDesign.secondary)
                            .multilineTextAlignment(.center).lineLimit(3).frame(maxWidth: 200)
                    } else {
                        Text(expired ? "–" : "\(remaining)%")
                            .font(.system(size: 15, weight: .bold, design: .rounded)).monospacedDigit()
                            .foregroundStyle(tint).contentTransition(.numericText())
                        Text(service).islandLabel()
                        Text(resetText(now: timeline.date, expired: expired))
                            .font(IslandDesign.footnote).monospacedDigit().foregroundStyle(IslandDesign.tertiary)
                    }
                }
            }
            .frame(maxWidth: .infinity)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(accessibilityText(remaining: remaining, expired: expired, now: timeline.date))
        }
    }

    private var stroke: StrokeStyle { StrokeStyle(lineWidth: UsageStyle.arcWidth, lineCap: .round) }

    /// The arc opens at the bottom: it starts at 135° and sweeps clockwise.
    private func arc(fraction: CGFloat) -> some Shape {
        Circle().trim(from: 0, to: UsageStyle.arcSweep * max(0, min(1, fraction)))
            .rotation(.degrees(135))
    }

    private var windowLabel: String {
        guard let minutes = window?.durationMinutes else { return "–" }
        if minutes.isMultiple(of: 1440) { return "\(minutes / 1440)d" }
        if minutes.isMultiple(of: 60) { return "\(minutes / 60)h" }
        return "\(minutes)m"
    }

    private func resetText(now: Date, expired: Bool) -> String {
        if expired { return shell.text("usageUpdating") }
        guard let reset = window?.resetsAt else { return " " }
        return UsageDuration.compact(reset.timeIntervalSince(now))
    }

    private func accessibilityText(remaining: Int, expired: Bool, now: Date) -> String {
        if let status { return "\(service), \(status)" }
        let reset = expired ? shell.text("usageUpdating") : "\(shell.text("usageResetIn")) \(resetText(now: now, expired: false))"
        return "\(service) \(windowLabel), \(remaining)% \(shell.text("usageRemaining")), \(reset)"
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
