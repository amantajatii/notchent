import AppKit
import Combine
import SwiftUI
import IslandCore

/// Follows the playing track's cover and publishes its accent colours, used to tint the level meter.
@MainActor final class ArtworkPaletteStore: ObservableObject {
    @Published private(set) var palette: ArtworkPalette?
    private var loadedURL: URL?
    private var task: Task<Void, Never>?
    private var subscription: AnyCancellable?

    func follow(_ spotify: SpotifyStore) {
        subscription = spotify.$snapshot
            .map(\.artworkURL)
            .removeDuplicates()
            .sink { [weak self] url in self?.load(url) }
    }

    private func load(_ url: URL?) {
        guard url != loadedURL else { return }
        loadedURL = url
        task?.cancel()
        guard let url else { palette = nil; return }
        task = Task { [weak self] in
            let data = await SpotifyArtworkCache.shared.imageData(for: url)
            guard !Task.isCancelled, let self, self.loadedURL == url else { return }
            // Keep the previous colours when a cover fails to load.
            guard let data, let image = NSImage(data: data),
                  let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return }
            // A black-and-white cover has no colour worth tinting with; the meter stays white.
            self.palette = ArtworkPalette.extract(from: cgImage).flatMap { $0.isColorful ? $0 : nil }
        }
    }
}

extension ArtworkPalette {
    /// False for the neutral fallback that grey or monochrome covers produce.
    var isColorful: Bool { [primary, secondary].contains { $0.chroma > 0.15 } }
}

extension PaletteColor {
    var chroma: Double { max(red, green, blue) - min(red, green, blue) }
    var color: Color { Color(.sRGB, red: red, green: green, blue: blue) }
}
