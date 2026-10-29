import SwiftUI
import IslandCore

struct HomeView: View {
    @ObservedObject var shell: IslandShell
    @ObservedObject var spotify: SpotifyStore
    var body: some View {
        HStack(alignment: .center, spacing: 20) {
            VStack(alignment: .leading, spacing: 14) {
                Button { shell.dispatch?(.show(.music)) } label: {
                    HStack(spacing: 14) {
                        SpotifyArtwork(url: spotify.snapshot.artworkURL, size: 62)
                        VStack(alignment: .leading, spacing: 5) {
                            Text(spotify.snapshot.title ?? shell.text("music"))
                                .font(.system(size: 17, weight: .semibold)).lineLimit(1)
                            Text(spotify.snapshot.artist ?? musicStatus)
                                .font(.system(size: 12)).foregroundStyle(Color(white: 0.66)).lineLimit(2)
                        }.frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                HStack {
                    Image(systemName: spotify.snapshot.playback == .playing ? "waveform" : "music.note")
                        .font(.system(size: 10, weight: .semibold)).foregroundStyle(Color(white: 0.6))
                    Text("Spotify").font(.system(size: 11, weight: .medium)).foregroundStyle(Color(white: 0.6))
                    Spacer()
                    if spotify.snapshot.availability == .available {
                        SpotifyTransportControls(shell: shell, spotify: spotify, compact: true)
                    } else if spotify.snapshot.availability == .requiresConsent {
                        Button(shell.text("spotifyConnect")) { Task { await spotify.connect() } }
                            .font(.system(size: 11, weight: .semibold)).padding(.horizontal, 11).padding(.vertical, 6)
                            .background(.white.opacity(0.1), in: Capsule())
                    } else if spotify.snapshot.availability == .error {
                        Button(shell.text("spotifyRetry")) { Task { await spotify.refresh() } }.font(.caption)
                    }
                }.frame(height: 30)
                if spotify.commandError != nil { Text(shell.text("spotifyCommandFailed")).font(.caption2).foregroundStyle(.orange) }
            }.frame(width: 330)
            Rectangle().fill(.white.opacity(0.08)).frame(width: 1, height: 94)
            VStack(alignment: .leading, spacing: 6) {
                Button { shell.dispatch?(.show(.agents)) } label: {
                    HomeAgentSummary(registry: shell.agents, shell: shell)
                        .padding(.horizontal, 8).padding(.vertical, 6)
                }
                Button { shell.dispatch?(.show(.files)) } label: {
                    if let summary = shell.fileSummaryView {
                        summary.padding(.horizontal, 10).padding(.vertical, 8)
                    }
                }
            }.font(.system(size: 12, weight: .medium))
                .frame(width: 149, alignment: .leading)
        }.frame(width: 520, alignment: .leading)
    }
    private var musicStatus: String {
        switch spotify.snapshot.availability {
        case .unavailable: shell.text("spotifyNotRunning")
        case .requiresConsent: shell.text("spotifyNeedsConsent")
        case .denied: shell.text("spotifyDenied")
        case .available: shell.text("spotifyNoTrack")
        case .error: shell.text("spotifyReadFailed")
        }
    }
}

private struct HomeAgentSummary: View {
    @ObservedObject var registry: AgentRegistry
    @ObservedObject var shell: IslandShell
    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Label(shell.text("agents"), systemImage: "square.3.layers.3d")
            Text(registry.agents.isEmpty ? shell.text("noAgentSessions") : "\(registry.agents.count) \(shell.text("agents"))")
                .font(.system(size: 11)).foregroundStyle(Color(white: 0.6)).lineLimit(2)
        }.frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
    }
}
