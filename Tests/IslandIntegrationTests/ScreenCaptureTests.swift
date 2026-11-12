import Foundation
import AppKit
import SwiftUI
import IslandCore
import Testing
@testable import IslandMac

/// Renders each panel screen to PNG for visual review. Opt in with ISLAND_UI_CAPTURE=1;
/// files go to ISLAND_UI_CAPTURE_DIR (default: the temporary directory).
@MainActor struct ScreenCaptureTests {
    nonisolated private static let enabled = ProcessInfo.processInfo.environment["ISLAND_UI_CAPTURE"] == "1"

    private func render(_ mode: IslandMode, name: String, shell: IslandShell, to directory: URL) async throws {
        shell.presentedMode = mode
        shell.state.mode = mode
        var measured = CGSize(width: 560, height: 400)
        shell.contentSizeDidChange = { _, size in measured = size }
        let host = NSHostingView(rootView: IslandRootView(shell: shell))
        let window = NSWindow(contentRect: CGRect(x: -10000, y: -10000, width: 560, height: 400),
                              styleMask: [.borderless], backing: .buffered, defer: false)
        window.contentView = host
        window.orderFront(nil)
        defer { window.orderOut(nil) }
        for _ in 0..<6 {
            host.layoutSubtreeIfNeeded()
            try await Task.sleep(for: .milliseconds(40))
            window.setContentSize(measured)
            shell.surface.size = measured
        }
        let bitmap = try #require(host.bitmapImageRepForCachingDisplay(in: host.bounds))
        host.cacheDisplay(in: host.bounds, to: bitmap)
        let destination = directory.appendingPathComponent("notchent-\(name).png")
        try #require(bitmap.representation(using: .png, properties: [:])).write(to: destination)
        print("Captured \(name): " + destination.path)
    }

    @Test(.enabled(if: enabled, "Writes PNG captures of every panel screen"))
    func capturesEveryScreen() async throws {
        let environment = ProcessInfo.processInfo.environment
        let directory = environment["ISLAND_UI_CAPTURE_DIR"].map { URL(fileURLWithPath: $0) } ?? FileManager.default.temporaryDirectory
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let bundle = Bundle(url: root.appendingPathComponent(".build/apps/Notchent.app")) ?? .main
        let shell = IslandShell(store: SettingsStore(url: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)),
                                localizations: bundle)
        // Mirror IslandAppDelegate's wiring without starting agent discovery.
        shell.featureViews[.files] = AnyView(FileShelfView(shell: shell, access: shell.files))
        shell.featureViews[.terminal] = AnyView(TerminalFeatureView(store: shell.terminals, shell: shell))
        shell.featureViews[.agents] = AnyView(AgentListView(registry: shell.agents, shell: shell))
        shell.fileSummaryView = AnyView(FileShelfSummary(shell: shell, access: shell.files))
        await shell.codexUsage.refresh()
        await shell.claudeUsage.refresh()
        try await render(.home, name: "home", shell: shell, to: directory)
        for feature in [IslandFeature.agents, .music, .files, .terminal, .settings] {
            try await render(.feature(feature), name: feature.rawValue, shell: shell, to: directory)
        }
        try await render(.drop, name: "drop", shell: shell, to: directory)
    }
}
