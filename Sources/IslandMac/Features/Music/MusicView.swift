import AppKit
import SwiftUI
import IslandCore

struct MusicView: View {
    @ObservedObject var shell: IslandShell
    @ObservedObject var spotify: SpotifyStore

    var body: some View {
        VStack(spacing: IslandDesign.gap) {
            if spotify.snapshot.availability == .available { nowPlaying } else { unavailable }
            if spotify.commandError != nil {
                Text(shell.text("spotifyCommandFailed")).font(IslandDesign.caption).foregroundStyle(.orange)
            }
        }.frame(width: IslandDesign.contentWidth, alignment: .leading)
    }

    private var nowPlaying: some View {
        VStack(spacing: IslandDesign.gap) {
            HStack(spacing: 14) {
                SpotifyArtwork(url: spotify.snapshot.artworkURL, size: 64)
                    .shadow(color: .black.opacity(0.45), radius: 8, y: 3)
                VStack(alignment: .leading, spacing: 3) {
                    Text(spotify.snapshot.title ?? shell.text("music"))
                        .font(IslandDesign.largeTitle).lineLimit(1).contentTransition(.opacity)
                    if let artist = spotify.snapshot.artist {
                        Text(artist).font(IslandDesign.callout).foregroundStyle(IslandDesign.secondary).lineLimit(1)
                    }
                    if spotify.snapshot.playback == .stopped {
                        Text(status).font(IslandDesign.caption).foregroundStyle(IslandDesign.tertiary).lineLimit(1)
                    }
                }.frame(maxWidth: .infinity, alignment: .leading)
                if spotify.snapshot.playback == .playing {
                    Image(systemName: "waveform").font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(IslandTint.music)
                        .symbolEffect(.variableColor.iterative, isActive: !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion)
                        .accessibilityHidden(true)
                }
                SpotifyTransportControls(shell: shell, spotify: spotify)
            }
            if let position = spotify.snapshot.position, let duration = spotify.snapshot.duration,
               position.isFinite, duration.isFinite, duration > 0 {
                SpotifyProgressLine(position: position, duration: duration / 1000)
            }
        }.islandCard()
    }

    private var unavailable: some View {
        HStack(spacing: 14) {
            SpotifyArtwork(url: nil, size: 48)
            VStack(alignment: .leading, spacing: 3) {
                Text(spotify.snapshot.title ?? shell.text("music")).font(IslandDesign.largeTitle).lineLimit(1)
                Text(status).font(IslandDesign.callout).foregroundStyle(IslandDesign.secondary).lineLimit(2)
            }.frame(maxWidth: .infinity, alignment: .leading)
            if spotify.snapshot.availability == .requiresConsent {
                Button(shell.text("spotifyConnect")) { Task { await spotify.connect() } }
                    .buttonStyle(IslandPillButtonStyle(emphasis: .filled, tint: spotifyGreen))
            } else if spotify.snapshot.availability == .error {
                Button(shell.text("spotifyRetry")) { Task { await spotify.refresh() } }
                    .buttonStyle(IslandPillButtonStyle(emphasis: .tinted, tint: IslandDesign.warning))
            }
        }.islandCard()
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

private let spotifyGreen = Color(red: 0.12, green: 0.84, blue: 0.38)

private struct SpotifyProgressLine: View {
    let position: Double
    let duration: Double
    var body: some View {
        HStack(spacing: 10) {
            Text(time(position))
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Capsule().fill(IslandDesign.fill)
                    Capsule().fill(IslandDesign.primary)
                        .frame(width: geometry.size.width * min(1, max(0, position / duration)))
                }
            }.frame(height: 3)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("\(time(position)) / \(time(duration))")
            Text("−" + time(max(0, duration - position)))
        }.font(.system(size: 10, weight: .medium, design: .rounded)).monospacedDigit().foregroundStyle(IslandDesign.secondary)
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
        HStack(spacing: compact ? 6 : 10) {
            control("backward.fill", command: .previous, label: shell.text("spotifyPrevious"))
            control(spotify.snapshot.playback == .playing ? "pause.fill" : "play.fill", command: .toggle,
                    label: shell.text(spotify.snapshot.playback == .playing ? "spotifyPause" : "spotifyPlay"), primary: true)
            control("forward.fill", command: .next, label: shell.text("spotifyNext"))
        }
    }
    private func control(_ symbol: String, command: SpotifyCommand, label: String, primary: Bool = false) -> some View {
        let base: CGFloat = compact ? 26 : 30
        return Button { Task { await spotify.perform(command) } } label: {
            Image(systemName: symbol)
        }
        .buttonStyle(IslandIconButtonStyle(size: primary ? base + (compact ? 6 : 14) : base,
                                           emphasis: primary ? .tinted : .plain, tint: IslandTint.music))
        .accessibilityLabel(label).help(label)
    }
}

struct SpotifyArtwork: View {
    let url: URL?
    let size: CGFloat
    @StateObject private var loader = SpotifyArtworkLoader()
    var body: some View {
        Group {
            if let image = loader.image { Image(nsImage: image).resizable().scaledToFill() }
            else { Image(systemName: "music.note").font(.system(size: max(14, size * 0.4), weight: .semibold)).foregroundStyle(IslandTint.music) }
        }
        .frame(width: size, height: size).background(IslandTint.music.opacity(0.16))
        .clipShape(RoundedRectangle(cornerRadius: max(6, size * 0.16), style: .continuous))
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
