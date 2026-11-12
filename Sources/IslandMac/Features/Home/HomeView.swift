import SwiftUI
import IslandCore

/// Home, laid out like an expanded Live Activity: content sits directly on the black surface,
/// the most important values are the largest things on screen, and colour only marks state.
struct HomeView: View {
    @ObservedObject var shell: IslandShell
    @ObservedObject var spotify: SpotifyStore

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            HStack(alignment: .top, spacing: 20) {
                NowPlayingActivity(shell: shell, spotify: spotify).frame(maxWidth: .infinity, alignment: .leading)
                HomeAgentsMetric(registry: shell.agents, shell: shell)
                HomeFilesMetric(access: shell.files, shell: shell)
            }
            UsageSection(shell: shell)
        }
        .padding(.horizontal, 4)
        .frame(width: IslandDesign.contentWidth, alignment: .leading)
    }
}

/// A metric that opens its feature: uppercase caption and hero number, plus a detail line
/// only when something needs attention.
private struct HomeMetric: View {
    static let width: CGFloat = 64

    let label: String
    let value: String
    var detail: String?
    var detailColor: Color = IslandDesign.secondary
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 2) {
                Text(label).islandLabel().lineLimit(1)
                Text(value).islandHero().contentTransition(.numericText())
                if let detail {
                    Text(detail).font(IslandDesign.caption).foregroundStyle(detailColor).lineLimit(1)
                }
            }
            .frame(minWidth: Self.width, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(PressableStyle())
        .accessibilityElement(children: .combine)
    }
}

private struct HomeAgentsMetric: View {
    @ObservedObject var registry: AgentRegistry
    @ObservedObject var shell: IslandShell

    var body: some View {
        let pending = shell.state.pendingCount
        HomeMetric(label: shell.text("agents"), value: "\(registry.agents.count)",
                   detail: pending > 0 ? "\(shell.text("pending")): \(pending)" : nil,
                   detailColor: IslandDesign.warning) {
            shell.dispatch?(.show(.agents))
        }
    }
}

private struct HomeFilesMetric: View {
    @ObservedObject var access: NativeFileAccess
    @ObservedObject var shell: IslandShell

    var body: some View {
        HomeMetric(label: shell.text("files"), value: "\(access.items.count)") {
            shell.dispatch?(.show(.files))
        }
    }
}

/// Now Playing as a music Live Activity: artwork, title, transport, then a scrubber with times.
private struct NowPlayingActivity: View {
    @ObservedObject var shell: IslandShell
    @ObservedObject var spotify: SpotifyStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private static let artworkSize: CGFloat = 52

    var body: some View {
        let snapshot = spotify.snapshot
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                Button { shell.dispatch?(.show(.music)) } label: {
                    HStack(spacing: 12) {
                        SpotifyArtwork(url: snapshot.artworkURL, size: Self.artworkSize)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(snapshot.title ?? shell.text("music")).font(.system(size: 15, weight: .semibold)).lineLimit(1)
                            Text(snapshot.artist ?? status).font(IslandDesign.body).foregroundStyle(IslandDesign.secondary).lineLimit(1)
                        }
                    }.frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
                }.buttonStyle(PressableStyle())
                trailing
            }
            if let position = snapshot.position, let duration = snapshot.duration, duration > 0 {
                scrubber(position: position, duration: duration)
            }
        }
    }

    @ViewBuilder private var trailing: some View {
        switch spotify.snapshot.availability {
        case .available:
            SpotifyTransportControls(shell: shell, spotify: spotify, compact: true)
        case .requiresConsent:
            Button(shell.text("spotifyConnect")) { Task { await spotify.connect() } }
                .buttonStyle(IslandPillButtonStyle(emphasis: .filled, tint: IslandDesign.success))
        case .error:
            Button(shell.text("spotifyRetry")) { Task { await spotify.refresh() } }
                .buttonStyle(IslandPillButtonStyle())
        case .unavailable, .denied:
            EmptyView()
        }
    }

    private func scrubber(position: TimeInterval, duration: TimeInterval) -> some View {
        let progress = min(1, max(0, position / duration))
        return HStack(spacing: 10) {
            Text(Self.clock(position)).font(IslandDesign.caption).monospacedDigit().foregroundStyle(IslandDesign.secondary)
            GeometryReader { geometry in
                Capsule().fill(IslandDesign.fill)
                    .overlay(alignment: .leading) {
                        Capsule().fill(IslandDesign.primary).frame(width: geometry.size.width * progress)
                    }
            }.frame(height: 4).accessibilityHidden(true)
            Text("-" + Self.clock(duration - position)).font(IslandDesign.caption).monospacedDigit().foregroundStyle(IslandDesign.secondary)
        }
        .animation(reduceMotion ? nil : .linear(duration: 0.5), value: progress)
    }

    private var status: String {
        switch spotify.snapshot.availability {
        case .unavailable: shell.text("spotifyNotRunning")
        case .requiresConsent: shell.text("spotifyNeedsConsent")
        case .denied: shell.text("spotifyDenied")
        case .available: shell.text("spotifyNoTrack")
        case .error: shell.text("spotifyReadFailed")
        }
    }

    static func clock(_ seconds: TimeInterval) -> String {
        let total = Int(max(0, seconds).rounded())
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}
