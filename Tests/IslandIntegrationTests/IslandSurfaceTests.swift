import AppKit
import SwiftUI
import Testing
import IslandCore
@testable import IslandMac

@MainActor struct IslandSurfaceTests {
    @Test(.enabled(if: ProcessInfo.processInfo.environment["ISLAND_UI_CAPTURE"] == "1", "Manual native UI capture"))
    func captureHomeInBothLanguages() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("island-ui-refinement-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let settingsURL = directory.appendingPathComponent("settings.json")
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let bundle = try #require(Bundle(url: root.appendingPathComponent(".build/apps/Notchent.app")))
        let shell = IslandShell(store: SettingsStore(url: settingsURL), localizations: bundle)
        shell.presentedMode = .home
        shell.state.mode = .home
        shell.surface.size = CGSize(width: 560, height: 194)
        shell.fileSummaryView = AnyView(FileShelfSummary(shell: shell, access: shell.files))
        for language in IslandLanguage.allCases {
            shell.settings.language = language
            #expect(shell.text("home") != "home")
            let renderer = ImageRenderer(content: IslandRootView(shell: shell).frame(width: 560, height: 194))
            renderer.scale = 2
            let image = try #require(renderer.cgImage)
            let pixels = NSBitmapImageRep(cgImage: image)
            let data = try #require(pixels.representation(using: .png, properties: [:]))
            let destination = directory.appendingPathComponent("home-" + language.rawValue + ".png")
            try data.write(to: destination)
            print("Native component capture (initial service state): " + destination.path)
        }
        let preview = SpotifyStore(client: PreviewMusicClient())
        await preview.refresh()
        shell.settings.language = .en
        shell.featureViews[.music] = AnyView(MusicView(shell: shell, spotify: preview))
        shell.presentedMode = .feature(.music)
        shell.state.mode = .feature(.music)
        shell.surface.size = CGSize(width: 560, height: 216)
        let renderer = ImageRenderer(content: IslandRootView(shell: shell).frame(width: 560, height: 216))
        renderer.scale = 2
        let image = try #require(renderer.cgImage)
        let pixels = NSBitmapImageRep(cgImage: image)
        let data = try #require(pixels.representation(using: .png, properties: [:]))
        let destination = directory.appendingPathComponent("music-preview.png")
        try data.write(to: destination)
        print("Native component capture (illustrative music state): " + destination.path)
    }
    @Test func morphUsesOnlyItsOwnFootprintInsideAStableViewport() throws {
        let state = IslandSurfaceState()
        for size in [CGSize(width: 500, height: 240), CGSize(width: 300, height: 100), CGSize(width: 160, height: 26)] {
            state.size = size
            let renderer = ImageRenderer(content: IslandSurface(state: state) { Color.red.frame(width: 300, height: 80).fixedSize() }.frame(width: 560, height: 400))
            renderer.scale = 1
            let image = try #require(renderer.cgImage)
            let pixels = NSBitmapImageRep(cgImage: image)
            let top = try #require(pixels.colorAt(x: 280, y: 10)?.usingColorSpace(.deviceRGB))
            let below = try #require(pixels.colorAt(x: 280, y: Int(size.height) + 20))
            let outside = try #require(pixels.colorAt(x: 5, y: 40))
            #expect(top.redComponent > 0.7 && top.greenComponent < 0.5)
            #expect(below.alphaComponent < 0.01)
            #expect(outside.alphaComponent < 0.01)
        }
        let silhouette = IslandSilhouette().path(in: CGRect(x: 0, y: 0, width: 300, height: 100))
        #expect(silhouette.contains(CGPoint(x: 150, y: 5)))
        #expect(!silhouette.contains(CGPoint(x: 2, y: 95)))
    }
    @Test func resizingKeepsGroupedContentAtItsNaturalScale() throws {
        let state = IslandSurfaceState()
        let content = HStack(spacing: 0) {
            Color.red.frame(width: 200, height: 80)
            Color.green.frame(width: 200, height: 80)
        }.fixedSize()
        for width: CGFloat in [200, 300, 400] {
            state.size = CGSize(width: width, height: 100)
            let renderer = ImageRenderer(content: IslandSurface(state: state) { content }.frame(width: 400, height: 200))
            let pixels = NSBitmapImageRep(cgImage: try #require(renderer.cgImage))
            let left = try #require(pixels.colorAt(x: 170, y: 60)?.usingColorSpace(.deviceRGB))
            let right = try #require(pixels.colorAt(x: 230, y: 60)?.usingColorSpace(.deviceRGB))
            #expect(left.redComponent > 0.7 && right.greenComponent > 0.4,
                    "Resizing must reveal content without zooming or shifting individual elements")
        }
    }
    @Test func emptyPreferenceCannotEraseAValidContentMeasurement() {
        let home = IslandMeasurement(mode: .home, size: CGSize(width: 560, height: 194))
        var measured = home
        IslandContentSize.reduce(value: &measured) { IslandContentSize.defaultValue }
        #expect(measured == home)
        IslandContentSize.reduce(value: &measured) { IslandMeasurement(mode: .hidden, size: CGSize(width: 560, height: 0)) }
        #expect(measured == home)
        var initial = IslandContentSize.defaultValue
        IslandContentSize.reduce(value: &initial) { home }
        #expect(initial == home)
    }
    @Test func equalSizedRoutesRemainDifferentMeasurements() {
        let size = CGSize(width: 560, height: 194)
        let home = IslandMeasurement(mode: .home, size: size)
        let music = IslandMeasurement(mode: .feature(.music), size: size)
        #expect(home != music)
        #expect(home == IslandMeasurement(mode: .home, size: size))
    }
    @Test func shorterContentStaysAtTopOfEveryAnimatedViewport() throws {
        for height: CGFloat in [480, 360, 240, 100] {
            let surface = IslandSurface { Color.red.frame(width: 300, height: 80).fixedSize() }
                .frame(width: 560, height: height)
            let renderer = ImageRenderer(content: surface)
            renderer.scale = 1
            let image = try #require(renderer.cgImage)
            let pixels = NSBitmapImageRep(cgImage: image)
            let top = try #require(pixels.colorAt(x: 280, y: 10)?.usingColorSpace(.deviceRGB))
            let bottom = try #require(pixels.colorAt(x: 280, y: pixels.pixelsHigh - 10)?.usingColorSpace(.deviceRGB))
            #expect(top.redComponent > 0.7 && top.greenComponent < 0.5, "Content must touch the top, viewport height \(height)")
            #expect(bottom.redComponent < 0.1 && bottom.alphaComponent > 0.95, "Backplate must cover the remaining animated viewport")
        }
    }
}

@MainActor private struct PreviewMusicClient: SpotifyClient {
    func snapshot() async throws -> SpotifySnapshot {
        SpotifySnapshot(availability: .available, playback: .paused, title: "Music preview", artist: "Illustrative state", position: 102, duration: 316_000)
    }
    func perform(_ command: SpotifyCommand) async throws { throw SpotifyFailure.unavailable }
}
