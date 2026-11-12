import SwiftUI

struct CodexUsageView: View {
    @ObservedObject var store: CodexUsageStore
    @ObservedObject var shell: IslandShell

    var body: some View {
        HStack(spacing: 20) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Codex").font(.system(size: 12, weight: .semibold))
                Text(shell.text("usageRemaining")).font(.system(size: 10)).foregroundStyle(Color(white: 0.65))
            }.frame(width: 62, alignment: .leading)
            if let usage = store.snapshot {
                if let window = usage.primary { windowView(window) }
                if let window = usage.secondary { windowView(window) }
            } else {
                Text(shell.text(store.refreshing ? "usageLoading" : "usageUnavailable"))
                    .font(.system(size: 11)).foregroundStyle(Color(white: 0.65))
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            Button { Task { await store.refresh() } } label: {
                Image(systemName: "arrow.clockwise").font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Color(white: 0.7)).frame(width: 28, height: 28)
            }.accessibilityLabel(shell.text("usageRefresh")).help(shell.text("usageRefresh"))
                .disabled(store.refreshing).opacity(store.refreshing ? 0.4 : 1)
        }.frame(minHeight: 38)
    }

    private func windowView(_ window: CodexUsageSnapshot.Window) -> some View {
        TimelineView(.periodic(from: .now, by: 1)) { timeline in
            let expired = window.resetsAt.map { $0 <= timeline.date } ?? false
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(windowLabel(window)).foregroundStyle(Color(white: 0.7))
                    Spacer(minLength: 4)
                    Text(expired ? shell.text("usageUpdating") : "\(window.remainingPercent)%")
                        .monospacedDigit().foregroundStyle(.white)
                }.font(.system(size: 11, weight: .medium))
                GeometryReader { geometry in
                    Capsule().fill(Color(white: 0.16))
                        .overlay(alignment: .leading) {
                            Capsule().fill(window.remainingPercent <= 10 ? Color.orange : Color.white)
                                .frame(width: expired ? 0 : geometry.size.width * CGFloat(window.remainingPercent) / 100)
                        }
                }.frame(height: 3).accessibilityHidden(true)
                if let reset = window.resetsAt, !expired {
                    Text("\(shell.text("usageResetIn")) \(reset, style: .relative)")
                        .font(.system(size: 10)).monospacedDigit()
                        .foregroundStyle(Color(white: 0.65)).lineLimit(1)
                }
            }.frame(maxWidth: .infinity)
                .help(window.resetsAt.map { shell.text("usageReset") + " " + $0.formatted(date: .abbreviated, time: .shortened) } ?? "")
                .accessibilityElement(children: .combine)
        }
    }

    private func windowLabel(_ window: CodexUsageSnapshot.Window) -> String {
        guard let minutes = window.windowDurationMins else { return shell.text("usageWindow") }
        if minutes.isMultiple(of: 1440) { return "\(minutes / 1440)d" }
        if minutes.isMultiple(of: 60) { return "\(minutes / 60)h" }
        return "\(minutes)m"
    }
}
