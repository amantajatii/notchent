import Foundation
import AppKit
import SwiftUI
import IslandCore
import Testing
@testable import IslandMac

struct CodexUsageTests {
    @Test func selectsCodexBucketAndConvertsUsedToRemaining() throws {
        let data = Data(#"{"rateLimits":{"limitId":"other","primary":{"usedPercent":99}},"rateLimitsByLimitId":{"codex":{"primary":{"usedPercent":25,"windowDurationMins":300,"resetsAt":1900000000},"secondary":{"usedPercent":82,"windowDurationMins":10080}}}}"#.utf8)
        let usage = try CodexUsageSnapshot.decode(data)
        #expect(usage.primary?.remainingPercent == 75)
        #expect(usage.primary?.windowDurationMins == 300)
        #expect(usage.primary?.resetsAt == Date(timeIntervalSince1970: 1900000000))
        #expect(usage.secondary?.remainingPercent == 18)
    }
    @Test func legacyMissingAndOverdrawnWindowsStayHonest() throws {
        let usage = try CodexUsageSnapshot.decode(Data(#"{"rateLimits":{"primary":null,"secondary":{"usedPercent":115}}}"#.utf8))
        #expect(usage.primary == nil)
        #expect(usage.secondary?.remainingPercent == 0)
        for json in [#"{}"#, #"{"rateLimits":{"primary":null,"secondary":null}}"#, #"{"rateLimits":{"limitId":"other","primary":{"usedPercent":10}}}"#, #"{"rateLimits":{"primary":{"usedPercent":-1}}}"#, #"{"rateLimits":{"primary":{"usedPercent":true}}}"#] {
            #expect(throws: (any Error).self) { try CodexUsageSnapshot.decode(Data(json.utf8)) }
        }
    }
    @Test(.enabled(if: ProcessInfo.processInfo.environment["ISLAND_CODEX_USAGE_LIVE"] == "1", "Read-only local Codex account limits"))
    func readsRealAccountWithoutOpeningThreads() async throws {
        let usage = try await NativeCodexUsageClient().read()
        #expect(usage.primary != nil || usage.secondary != nil)
        print("Live Codex account limits: primary remaining=\(usage.primary?.remainingPercent.description ?? "unavailable"), secondary remaining=\(usage.secondary?.remainingPercent.description ?? "unavailable")")
    }
}

@MainActor struct CodexUsageStoreTests {
    @Test func failedRefreshClearsPreviousQuotaRatherThanShowingItAsCurrent() async {
        let client = UsageFixtureClient()
        let store = CodexUsageStore(client: client)
        await store.refresh()
        #expect(store.snapshot?.primary?.remainingPercent == 75)
        await store.refresh()
        #expect(store.snapshot == nil)
        #expect(!store.refreshing)
    }
}

private actor UsageFixtureClient: CodexUsageClient {
    private var calls = 0
    func read() async throws -> CodexUsageSnapshot {
        calls += 1
        guard calls == 1 else { throw CocoaError(.fileReadUnknown) }
        return try CodexUsageSnapshot.decode(Data(#"{"rateLimits":{"primary":{"usedPercent":25}}}"#.utf8))
    }
}

@MainActor struct CodexUsageHomeTests {
    @Test(.enabled(if: ProcessInfo.processInfo.environment["ISLAND_CODEX_USAGE_LIVE"] == "1", "Native Home with live account limits"))
    func rendersLiveLimitsInHome() async throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let bundle = Bundle(url: root.appendingPathComponent(".build/apps/Notchent.app")) ?? .main
        let shell = IslandShell(store: SettingsStore(url: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)), localizations: bundle)
        await shell.codexUsage.refresh()
        #expect(shell.codexUsage.snapshot != nil)
        shell.presentedMode = .home
        shell.state.mode = .home
        var measured = CGSize(width: 560, height: 400)
        shell.contentSizeDidChange = { _, size in measured = size }
        let host = NSHostingView(rootView: IslandRootView(shell: shell))
        let window = NSWindow(contentRect: CGRect(x: -10000, y: -10000, width: 560, height: 400), styleMask: [.borderless], backing: .buffered, defer: false)
        window.contentView = host
        window.orderFront(nil)
        defer { window.orderOut(nil) }
        for _ in 0..<6 {
            host.layoutSubtreeIfNeeded()
            try await Task.sleep(for: .milliseconds(40))
            window.setContentSize(measured)
            shell.surface.size = measured
        }
        #expect(abs(measured.width - 560) < 1)
        #expect(measured.height < 340)
        if ProcessInfo.processInfo.environment["ISLAND_UI_CAPTURE"] == "1" {
            let bitmap = try #require(host.bitmapImageRepForCachingDisplay(in: host.bounds))
            host.cacheDisplay(in: host.bounds, to: bitmap)
            let destination = FileManager.default.temporaryDirectory.appendingPathComponent("notchent-home-live-usage.png")
            try #require(bitmap.representation(using: .png, properties: [:])).write(to: destination)
            print("Native Home with live Codex limits: " + destination.path)
        }
    }
}
