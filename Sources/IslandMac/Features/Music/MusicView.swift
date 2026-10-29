import AppKit
import SwiftUI
import IslandCore

struct MusicView: View {
    @ObservedObject var shell: IslandShell
    @ObservedObject var spotify: SpotifyStore

    var body: some View {
        VStack(spacing: 12) {
            HStack(spacing: 14) {
                SpotifyArtwork(url: spotify.snapshot.artworkURL, size: 56)
                VStack(alignment: .leading, spacing: 4) {
                    Text(spotify.snapshot.title ?? shell.text("music"))
                        .font(.system(size: 17, weight: .semibold)).lineLimit(1).contentTransition(.opacity)
                    if let artist = spotify.snapshot.artist {
                        Text(artist).font(.system(size: 12)).foregroundStyle(Color(white: 0.64)).lineLimit(1)
                    }
                    if spotify.snapshot.availability != .available || spotify.snapshot.playback == .stopped {
                        Text(status).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                    }
                }.frame(maxWidth: .infinity, alignment: .leading)
                if spotify.snapshot.availability == .requiresConsent {
                    Button(shell.text("spotifyConnect")) { Task { await spotify.connect() } }
                        .font(.caption.weight(.semibold)).padding(.horizontal, 12).padding(.vertical, 7)
                        .background(.white.opacity(0.1), in: Capsule())
                } else if spotify.snapshot.availability == .error {
                    Button(shell.text("spotifyRetry")) { Task { await spotify.refresh() } }.font(.caption)
                }
            }
            if spotify.snapshot.availability == .available {
                if let position = spotify.snapshot.position, let duration = spotify.snapshot.duration,
                   position.isFinite, duration.isFinite, duration > 0 {
                    SpotifyProgressLine(position: position, duration: duration / 1000)
                }
                SpotifyTransportControls(shell: shell, spotify: spotify)
                    .frame(maxWidth: .infinity)
            }
            if spotify.commandError != nil {
                Text(shell.text("spotifyCommandFailed")).font(.caption2).foregroundStyle(.orange)
            }
        }.frame(width: 520, alignment: .leading)
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
}

private struct SpotifyProgressLine: View {
    let position: Double
    let duration: Double
    var body: some View {
        HStack(spacing: 10) {
            Text(time(position))
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Capsule().fill(.white.opacity(0.12))
                    Capsule().fill(.white.opacity(0.65))
                        .frame(width: geometry.size.width * min(1, max(0, position / duration)))
                }
            }.frame(height: 3)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("\(time(position)) / \(time(duration))")
            Text("−" + time(max(0, duration - position)))
        }.font(.system(size: 10, weight: .medium)).monospacedDigit().foregroundStyle(Color(white: 0.6))
    }
    private func time(_ value: Double) -> String {
        let seconds = Int(min(36_000_000, max(0, value)))
        return String(format: "%d:%02d", seconds / 60, seconds % 60)
    }
}

struct SpotifyTransportControls: View {
    @ObservedObject var shell: IslandShell
    @ObservedObject var spotify: SpotifyStore
    var compact = false
    var body: some View {
        HStack(spacing: compact ? 8 : 14) {
            control("backward.end.fill", command: .previous, label: shell.text("spotifyPrevious"))
            control(spotify.snapshot.playback == .playing ? "pause.fill" : "play.fill", command: .toggle,
                    label: shell.text(spotify.snapshot.playback == .playing ? "spotifyPause" : "spotifyPlay"), primary: true)
            control("forward.end.fill", command: .next, label: shell.text("spotifyNext"))
        }
    }
    private func control(_ symbol: String, command: SpotifyCommand, label: String, primary: Bool = false) -> some View {
        Button { Task { await spotify.perform(command) } } label: {
            Image(systemName: symbol).font(.system(size: compact ? 11 : 13, weight: .semibold))
                .foregroundStyle(primary ? Color.black : Color.white)
                .frame(width: compact ? 28 : 34, height: compact ? 28 : 34)
                .background(primary ? Color.white : .clear, in: Circle())
                .contentShape(Circle())
        }.accessibilityLabel(label).help(label)
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
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .contentTransition(.opacity)
        .task(id: url) { await loader.load(url) }
    }
}

@MainActor private final class SpotifyArtworkLoader: ObservableObject {
    @Published var image: NSImage?
    func load(_ url: URL?) async {
        guard let url else { image = nil; return }
        let data = await SpotifyArtworkCache.shared.imageData(for: url)
        guard !Task.isCancelled else { return }
        withAnimation(NSWorkspace.shared.accessibilityDisplayShouldReduceMotion ? nil : .easeOut(duration: 0.18)) {
            image = data.flatMap(NSImage.init(data:))
        }
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
