import AppKit
import SwiftUI
import IslandCore

struct MusicView: View {
    @ObservedObject var shell: IslandShell
    @ObservedObject var spotify: SpotifyStore

    var body: some View {
        HStack(alignment: .center, spacing: 16) {
            SpotifyArtwork(url: spotify.snapshot.artworkURL, size: 76)
            VStack(alignment: .leading, spacing: 5) {
                Text(spotify.snapshot.title ?? shell.text("spotifyNoTrack"))
                    .font(.headline).lineLimit(1)
                if let artist = spotify.snapshot.artist { Text(artist).font(.caption).foregroundStyle(.secondary).lineLimit(1) }
                if spotify.snapshot.availability != .available || spotify.snapshot.playback == .stopped {
                    Text(status).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                }
                if spotify.snapshot.availability == .available {
                    HStack(spacing: 20) {
                        control("backward.end.fill", command: .previous, label: shell.text("spotifyPrevious"))
                        control(spotify.snapshot.playback == .playing ? "pause.fill" : "play.fill", command: .toggle,
                                label: shell.text(spotify.snapshot.playback == .playing ? "spotifyPause" : "spotifyPlay"))
                        control("forward.end.fill", command: .next, label: shell.text("spotifyNext"))
                    }.padding(.top, 3)
                } else if spotify.snapshot.availability == .requiresConsent {
                    Button(shell.text("spotifyConnect")) { Task { await spotify.connect() } }
                        .font(.caption.bold()).padding(.top, 4)
                } else if spotify.snapshot.availability == .error {
                    Button(shell.text("spotifyRetry")) { Task { await spotify.refresh() } }
                        .font(.caption.bold()).padding(.top, 4)
                }
                if spotify.commandError != nil { Text(shell.text("spotifyCommandFailed")).font(.caption2).foregroundStyle(.orange) }
            }.frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(width: 520, alignment: .leading)
    }

    private var status: String {
        switch spotify.snapshot.availability {
        case .unavailable: shell.text("spotifyNotRunning")
        case .requiresConsent: shell.text("spotifyNeedsConsent")
        case .denied: shell.text("spotifyDenied")
        case .available: shell.text("spotifyStopped")
        case .error: shell.text("spotifyReadFailed")
        }
    }
    private func control(_ symbol: String, command: SpotifyCommand, label: String) -> some View {
        Button { Task { await spotify.perform(command) } } label: { Image(systemName: symbol).frame(width: 24, height: 24) }
            .accessibilityLabel(label)
    }
}

struct SpotifyArtwork: View {
    let url: URL?
    let size: CGFloat
    @StateObject private var loader = SpotifyArtworkLoader()
    var body: some View {
        Group {
            if let image = loader.image { Image(nsImage: image).resizable().scaledToFill() }
            else { Image(systemName: "music.note").font(.title).foregroundStyle(.secondary) }
        }
        .frame(width: size, height: size).background(.white.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .task(id: url) { await loader.load(url) }
    }
}

@MainActor private final class SpotifyArtworkLoader: ObservableObject {
    @Published var image: NSImage?
    func load(_ url: URL?) async {
        image = nil
        guard let url, let data = await SpotifyArtworkCache.shared.imageData(for: url), !Task.isCancelled else { return }
        image = NSImage(data: data)
    }
}

/// Keeps at most eight small covers and four MiB of downloaded source data.
actor SpotifyArtworkCache {
    static let shared = SpotifyArtworkCache()
    private var entries: [(URL, Data)] = []
    private let maximumBytes = 4 * 1024 * 1024
    private let maximumImageBytes = 512 * 1024
    func imageData(for url: URL) async -> Data? {
        guard url.scheme == "https" else { return nil }
        if let index = entries.firstIndex(where: { $0.0 == url }) { return entries[index].1 }
        guard let (bytes, response) = try? await URLSession.shared.bytes(from: url) else { return nil }
        defer { bytes.task.cancel() }
        guard let http = response as? HTTPURLResponse, http.statusCode == 200,
              response.expectedContentLength < 0 || response.expectedContentLength <= maximumImageBytes else { return nil }
        var data = Data()
        data.reserveCapacity(min(max(0, Int(response.expectedContentLength)), maximumImageBytes))
        do {
            for try await byte in bytes {
                guard !Task.isCancelled, data.count < maximumImageBytes else { return nil }
                data.append(byte)
            }
        } catch { return nil }
        entries.append((url, data))
        while entries.count > 8 || entries.reduce(0, { $0 + $1.1.count }) > maximumBytes { entries.removeFirst() }
        return data
    }
}
