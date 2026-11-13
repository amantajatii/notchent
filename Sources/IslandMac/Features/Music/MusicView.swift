import AppKit
import SwiftUI
import IslandCore

struct MusicView: View {
    @ObservedObject var shell: IslandShell
    @ObservedObject var spotify: SpotifyStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let snapshot = spotify.snapshot
        VStack(spacing: 16) {
            header(snapshot)
            if snapshot.availability == .available {
                if let progress = snapshot.progress {
                    SpotifyProgressLine(playback: progress)
                }
                SpotifyTransportControls(shell: shell, spotify: spotify).frame(maxWidth: .infinity)
            }
            if spotify.commandError != nil {
                Text(shell.text("spotifyCommandFailed")).font(IslandDesign.caption).foregroundStyle(IslandDesign.warning)
            }
        }
        .padding(.horizontal, 4)
        .frame(width: IslandDesign.contentWidth, alignment: .leading)
        .animation(reduceMotion ? nil : IslandDesign.spring, value: snapshot.availability)
    }

    private func header(_ snapshot: SpotifySnapshot) -> some View {
        HStack(spacing: 14) {
            SpotifyArtwork(url: snapshot.artworkURL, size: 64)
            VStack(alignment: .leading, spacing: 2) {
                Text(snapshot.title ?? shell.text("music")).font(IslandDesign.largeTitle).lineLimit(1)
                    .contentTransition(.opacity)
                Text(snapshot.artist ?? status).font(IslandDesign.body).foregroundStyle(IslandDesign.secondary).lineLimit(2)
            }.frame(maxWidth: .infinity, alignment: .leading)
            if snapshot.availability == .available, snapshot.playback == .playing {
                Image(systemName: "waveform").font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(IslandDesign.primary)
                    .symbolEffect(.variableColor.iterative, isActive: !reduceMotion)
                    .accessibilityHidden(true)
            }
            if snapshot.availability == .requiresConsent {
                Button(shell.text("spotifyConnect")) { Task { await spotify.connect() } }
                    .buttonStyle(IslandPillButtonStyle(emphasis: .filled, tint: spotifyGreen))
            } else if snapshot.availability == .error {
                Button(shell.text("spotifyRetry")) { Task { await spotify.refresh() } }
                    .buttonStyle(IslandPillButtonStyle())
            }
        }
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
    let playback: SpotifyProgress
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        let progress = playback.fraction
        HStack(spacing: 10) {
            Text(time(playback.elapsed))
            GeometryReader { geometry in
                Capsule().fill(IslandDesign.fill)
                    .overlay(alignment: .leading) {
                        Capsule().fill(IslandDesign.primary).frame(width: geometry.size.width * progress)
                    }
            }.frame(height: 4)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("\(time(playback.elapsed)) / \(time(playback.duration))")
            Text("-" + time(playback.remaining))
        }
        .font(IslandDesign.caption).monospacedDigit().foregroundStyle(IslandDesign.secondary)
        .animation(reduceMotion ? nil : .linear(duration: 0.5), value: progress)
    }
    private func time(_ value: Double) -> String {
        let seconds = Int(min(36_000_000, max(0, value)))
        return String(format: "%d:%02d", seconds / 60, seconds % 60)
    }
}

/// Glyph-only transport, like the Live Activity: no circles, white symbols, press-down feedback.
struct SpotifyTransportControls: View {
    @ObservedObject var shell: IslandShell
    @ObservedObject var spotify: SpotifyStore
    var compact = false
    var body: some View {
        HStack(spacing: compact ? 6 : 36) {
            control("backward.fill", command: .previous, label: shell.text("spotifyPrevious"), size: compact ? 13 : 22)
            control(spotify.snapshot.playback == .playing ? "pause.fill" : "play.fill", command: .toggle,
                    label: shell.text(spotify.snapshot.playback == .playing ? "spotifyPause" : "spotifyPlay"),
                    size: compact ? 17 : 30)
            control("forward.fill", command: .next, label: shell.text("spotifyNext"), size: compact ? 13 : 22)
        }
    }
    private func control(_ symbol: String, command: SpotifyCommand, label: String, size: CGFloat) -> some View {
        Button { Task { await spotify.perform(command) } } label: {
            Image(systemName: symbol).font(.system(size: size, weight: .semibold))
                .foregroundStyle(IslandDesign.primary)
                .frame(width: max(size + 12, 30), height: max(size + 12, 30))
                .contentShape(Rectangle())
        }
        .buttonStyle(PressableStyle())
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
            else { Image(systemName: "music.note").font(.system(size: max(14, size * 0.4), weight: .semibold)).foregroundStyle(IslandDesign.secondary) }
        }
        .frame(width: size, height: size).background(IslandDesign.fill)
        .clipShape(RoundedRectangle(cornerRadius: size * 0.22, style: .continuous))
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
