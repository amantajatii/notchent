import SwiftUI
import IslandCore

struct HomeView: View {
    @ObservedObject var shell: IslandShell
    @ObservedObject var spotify: SpotifyStore
    var body: some View {
        HStack(alignment: .center, spacing: 18) {
            Button { shell.dispatch?(.show(.music)) } label: {
                HStack(spacing: 12) {
                    SpotifyArtwork(url: spotify.snapshot.artworkURL, size: 68)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Spotify").font(.caption.bold()).foregroundStyle(.secondary)
                        Text(spotify.snapshot.title ?? musicStatus).font(.headline).lineLimit(1)
                        if let artist = spotify.snapshot.artist { Text(artist).font(.caption).foregroundStyle(.secondary).lineLimit(1) }
                    }.frame(maxWidth: .infinity, alignment: .leading)
                }.frame(width: 350, alignment: .leading)
            }.buttonStyle(.plain)
            VStack(alignment: .leading, spacing: 12) {
                Button { shell.dispatch?(.show(.agents)) } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Label(shell.text("agents"), systemImage: "terminal")
                        Text(shell.text("agentsUnavailable")).font(.caption2).foregroundStyle(.secondary).lineLimit(2)
                    }
                }
                Button { shell.dispatch?(.show(.files)) } label: {
                    if let summary = shell.fileSummaryView { summary }
                    else {
                        VStack(alignment: .leading, spacing: 2) {
                            Label(shell.text("files"), systemImage: "square.stack")
                            Text(shell.text("filesUnavailable")).font(.caption2).foregroundStyle(.secondary).lineLimit(2)
                        }
                    }
                }
            }.font(.caption).buttonStyle(.plain).frame(width: 150, alignment: .leading)
        }
        .frame(width: 520, alignment: .leading)
    }
    private var musicStatus: String {
        switch spotify.snapshot.availability {
        case .unavailable: shell.text("spotifyNotRunning")
        case .requiresConsent: shell.text("spotifyNeedsConsent")
        case .denied: shell.text("spotifyDenied")
        case .available: shell.text("spotifyNoTrack")
        }
    }
}
