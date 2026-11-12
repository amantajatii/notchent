import SwiftUI
import IslandCore

/// Home: a Control Center-style grid of modules above the plan usage widgets.
struct HomeView: View {
    @ObservedObject var shell: IslandShell
    @ObservedObject var spotify: SpotifyStore

    private static let nowPlayingWidth: CGFloat = 330
    private static let artworkSize: CGFloat = 56

    var body: some View {
        VStack(spacing: IslandDesign.gap) {
            HStack(alignment: .top, spacing: IslandDesign.gap) {
                nowPlaying.frame(width: Self.nowPlayingWidth)
                VStack(spacing: IslandDesign.gap) {
                    Button { shell.dispatch?(.show(.agents)) } label: {
                        HomeAgentSummary(registry: shell.agents, shell: shell)
                    }.buttonStyle(HomeTileStyle())
                    Button { shell.dispatch?(.show(.files)) } label: {
                        shell.fileSummaryView.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                    }.buttonStyle(HomeTileStyle())
                }
            }.fixedSize(horizontal: false, vertical: true)
            UsageSection(shell: shell)
        }.frame(width: IslandDesign.contentWidth)
    }

    private var nowPlaying: some View {
        VStack(alignment: .leading, spacing: 12) {
            Button { shell.dispatch?(.show(.music)) } label: {
                HStack(spacing: 12) {
                    SpotifyArtwork(url: spotify.snapshot.artworkURL, size: Self.artworkSize)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(spotify.snapshot.title ?? shell.text("music")).font(IslandDesign.largeTitle).lineLimit(1)
                        Text(spotify.snapshot.artist ?? musicStatus)
                            .font(IslandDesign.callout).foregroundStyle(IslandDesign.secondary).lineLimit(2)
                    }.frame(maxWidth: .infinity, alignment: .leading)
                }.contentShape(Rectangle())
            }.buttonStyle(.plain)
            Spacer(minLength: 0)
            nowPlayingFooter
        }.islandCard()
    }

    private var nowPlayingFooter: some View {
        HStack(spacing: 6) {
            Image(systemName: spotify.snapshot.playback == .playing ? "waveform" : "music.note")
                .font(.system(size: 10, weight: .semibold)).foregroundStyle(IslandTint.music)
            Text("Spotify").font(IslandDesign.caption.weight(.medium)).foregroundStyle(IslandDesign.secondary)
            Spacer()
            switch spotify.snapshot.availability {
            case .available:
                SpotifyTransportControls(shell: shell, spotify: spotify, compact: true)
            case .requiresConsent:
                Button(shell.text("spotifyConnect")) { Task { await spotify.connect() } }
                    .buttonStyle(IslandPillButtonStyle(emphasis: .filled, tint: IslandDesign.success))
            case .error:
                Button(shell.text("spotifyRetry")) { Task { await spotify.refresh() } }
                    .buttonStyle(IslandPillButtonStyle(emphasis: .tinted, tint: IslandDesign.warning))
            case .unavailable, .denied:
                EmptyView()
            }
        }.frame(height: 30)
            .overlay(alignment: .bottomLeading) {
                if spotify.commandError != nil {
                    Text(shell.text("spotifyCommandFailed")).font(IslandDesign.footnote).foregroundStyle(.orange).offset(y: 14)
                }
            }
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

/// A tappable Home module: a platter that brightens on hover.
private struct HomeTileStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View { Tile(configuration: configuration) }

    private struct Tile: View {
        let configuration: ButtonStyleConfiguration
        @PromptState private var hovering = false

        var body: some View {
            configuration.label
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .padding(IslandDesign.cardPadding)
                .background(hovering ? IslandDesign.cardHover : IslandDesign.card,
                            in: RoundedRectangle(cornerRadius: IslandDesign.cardRadius, style: .continuous))
                .contentShape(RoundedRectangle(cornerRadius: IslandDesign.cardRadius, style: .continuous))
                .scaleEffect(configuration.isPressed ? 0.98 : 1)
                .onHover { hovering = $0 }
                .animation(.easeOut(duration: 0.12), value: hovering)
                .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
        }
    }
}

private struct HomeAgentSummary: View {
    @ObservedObject var registry: AgentRegistry
    @ObservedObject var shell: IslandShell

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 10) {
                IslandGlyph(symbol: "square.3.layers.3d", tint: IslandTint.neutral)
                VStack(alignment: .leading, spacing: 2) {
                    Text(shell.text("agents")).font(IslandDesign.title)
                    Text(registry.agents.isEmpty ? shell.text("noAgentSessions") : "\(registry.agents.count) \(shell.text("agents"))")
                        .font(IslandDesign.caption).foregroundStyle(IslandDesign.secondary).lineLimit(2)
                }
                Spacer(minLength: 0)
                if !registry.agents.isEmpty {
                    Text("\(registry.agents.count)").font(IslandDesign.display).foregroundStyle(IslandDesign.primary).monospacedDigit()
                }
            }
        }
    }
}
