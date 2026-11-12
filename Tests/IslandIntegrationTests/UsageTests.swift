import Foundation
import AppKit
import SwiftUI
import IslandCore
import Testing
@testable import IslandMac

private let liveUsage = ProcessInfo.processInfo.environment["ISLAND_CODEX_USAGE_LIVE"] == "1"

struct CodexUsageTests {
    @Test func selectsCodexBucketAndConvertsUsedToRemaining() throws {
        let data = Data(#"{"rateLimits":{"limitId":"other","primary":{"usedPercent":99}},"rateLimitsByLimitId":{"codex":{"primary":{"usedPercent":25,"windowDurationMins":300,"resetsAt":1900000000},"secondary":{"usedPercent":82,"windowDurationMins":10080}}}}"#.utf8)
        let usage = try CodexUsageDecoder.decode(data)
        #expect(usage.primary?.remainingPercent == 75)
        #expect(usage.primary?.durationMinutes == 300)
        #expect(usage.primary?.resetsAt == Date(timeIntervalSince1970: 1900000000))
        #expect(usage.secondary?.remainingPercent == 18)
    }

    @Test func legacyMissingAndOverdrawnWindowsStayHonest() throws {
        let usage = try CodexUsageDecoder.decode(Data(#"{"rateLimits":{"primary":null,"secondary":{"usedPercent":115}}}"#.utf8))
        #expect(usage.primary == nil)
        #expect(usage.secondary?.remainingPercent == 0)
        for json in [#"{}"#, #"{"rateLimits":{"primary":null,"secondary":null}}"#, #"{"rateLimits":{"limitId":"other","primary":{"usedPercent":10}}}"#, #"{"rateLimits":{"primary":{"usedPercent":-1}}}"#, #"{"rateLimits":{"primary":{"usedPercent":true}}}"#] {
            #expect(throws: (any Error).self) { try CodexUsageDecoder.decode(Data(json.utf8)) }
        }
    }

    @Test func executableSearchCoversGUIPathGapsWithoutDuplicates() {
        let home = URL(fileURLWithPath: "/Users/someone")
        let directories = CodexExecutable.searchDirectories(home: home, path: "/usr/bin:/opt/homebrew/bin::/custom/bin")
        #expect(directories.first == "/Users/someone/.local/bin")
        #expect(directories.contains("/Users/someone/.npm-global/bin"))
        #expect(directories.contains("/custom/bin"))
        #expect(directories.filter { $0 == "/opt/homebrew/bin" }.count == 1)
        #expect(!directories.contains(""))
    }

    @Test func untrustedOrMissingControlSocketIsIgnored() throws {
        let home = FileManager.default.temporaryDirectory.appendingPathComponent("CodexHome-\(UUID())")
        defer { try? FileManager.default.removeItem(at: home) }
        #expect(CodexControlSocket.trustedPath(codexHome: home) == nil)
        let folder = home.appendingPathComponent("app-server-control")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try Data().write(to: folder.appendingPathComponent("app-server-control.sock"))
        #expect(CodexControlSocket.trustedPath(codexHome: home) == nil)
    }

    @Test(.enabled(if: liveUsage, "Read-only local Codex account limits"))
    func readsRealAccountWithoutOpeningThreads() async throws {
        let usage = try await NativeCodexUsageClient().read()
        #expect(!usage.windows.isEmpty)
        print("Live Codex limits remaining: " + usage.windows.map { "\($0.remainingPercent)%" }.joined(separator: ", "))
    }
}

struct ClaudeUsageClientTests {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func client(_ record: ClaudeUsageRecord?) throws -> (NativeClaudeUsageClient, URL) {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("ClaudeUsage-\(UUID())")
        let relay = ClaudeUsageRelay(directory: directory)
        if let record { try relay.write(record) }
        let now = self.now
        return (NativeClaudeUsageClient(relay: relay, now: { now }), directory)
    }

    @Test func missingRelayFileMeansNotConfigured() async throws {
        let (client, directory) = try client(nil)
        defer { try? FileManager.default.removeItem(at: directory) }
        await #expect(throws: UsageError.notConfigured) { try await client.read() }
    }

    @Test func mapsWindowsToFiveHourAndSevenDay() async throws {
        let record = ClaudeUsageRecord(fiveHour: .init(usedPercentage: 23.5, resetsAt: now.addingTimeInterval(600)),
                                       sevenDay: .init(usedPercentage: 41.2, resetsAt: now.addingTimeInterval(9000)),
                                       observedAt: now.addingTimeInterval(-30))
        let (client, directory) = try client(record)
        defer { try? FileManager.default.removeItem(at: directory) }
        let usage = try await client.read()
        #expect(usage.primary?.remainingPercent == 76)
        #expect(usage.primary?.durationMinutes == 300)
        #expect(usage.secondary?.remainingPercent == 59)
        #expect(usage.secondary?.durationMinutes == 10_080)
        #expect(usage.observedAt == now.addingTimeInterval(-30))
    }

    @Test func fullyResetRecordIsNotShownAsCurrent() async throws {
        let record = ClaudeUsageRecord(fiveHour: .init(usedPercentage: 99, resetsAt: now.addingTimeInterval(-1)),
                                       sevenDay: nil, observedAt: now.addingTimeInterval(-7200))
        let (client, directory) = try client(record)
        defer { try? FileManager.default.removeItem(at: directory) }
        await #expect(throws: UsageError.invalidResponse) { try await client.read() }
    }
}

struct UsageScheduleTests {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    @Test func waitsTheIntervalWithoutAnUpcomingReset() {
        #expect(UsageSchedule.nextDelay(after: nil, now: now) == 300)
        let past = UsageSnapshot(primary: UsageWindow(usedPercent: 10, durationMinutes: 300, resetsAt: now.addingTimeInterval(-5)), secondary: nil)
        #expect(UsageSchedule.nextDelay(after: past, now: now) == 300)
        #expect(UsageSchedule.nextDelay(after: nil, now: now, interval: 30) == 30)
    }

    @Test func refreshesJustAfterTheNextReset() {
        let snapshot = UsageSnapshot(primary: UsageWindow(usedPercent: 10, durationMinutes: 300, resetsAt: now.addingTimeInterval(120)),
                                     secondary: UsageWindow(usedPercent: 10, durationMinutes: 10080, resetsAt: now.addingTimeInterval(60)))
        #expect(UsageSchedule.nextDelay(after: snapshot, now: now) == 65)
    }

    @Test func remainingPercentIsClamped() {
        #expect(UsageWindow(usedPercent: 115, durationMinutes: nil, resetsAt: nil).remainingPercent == 0)
        #expect(UsageWindow(usedPercent: 0.4, durationMinutes: nil, resetsAt: nil).remainingPercent == 100)
        #expect(UsageWindow(usedPercent: 23.5, durationMinutes: nil, resetsAt: nil).remainingPercent == 76)
    }
}

@MainActor struct UsageStoreTests {
    @Test func failedRefreshClearsPreviousQuotaRatherThanShowingItAsCurrent() async {
        let store = UsageStore(client: UsageFixtureClient(results: [.success(25), .failure(.invalidResponse)]))
        await store.refresh()
        #expect(store.snapshot?.primary?.remainingPercent == 75)
        #expect(store.failure == nil)
        await store.refresh()
        #expect(store.snapshot == nil)
        #expect(store.failure == .invalidResponse)
        #expect(!store.refreshing)
    }

    @Test func setupFailureIsReportedDistinctly() async {
        let store = UsageStore(client: UsageFixtureClient(results: [.failure(.notConfigured), .success(50)]))
        await store.refresh()
        #expect(store.failure == .notConfigured)
        await store.refresh()
        #expect(store.failure == nil)
        #expect(store.snapshot?.primary?.remainingPercent == 50)
    }
}

private actor UsageFixtureClient: UsageClient {
    private var results: [Result<Double, UsageError>]
    init(results: [Result<Double, UsageError>]) { self.results = results }
    func read() async throws -> UsageSnapshot {
        let used = try results.removeFirst().get()
        return UsageSnapshot(primary: UsageWindow(usedPercent: used, durationMinutes: 300, resetsAt: nil), secondary: nil)
    }
}

@MainActor struct UsageHomeTests {
    @Test(.enabled(if: liveUsage, "Native Home with live account limits"))
    func rendersLiveLimitsInHome() async throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let bundle = Bundle(url: root.appendingPathComponent(".build/apps/Notchent.app")) ?? .main
        let shell = IslandShell(store: SettingsStore(url: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)), localizations: bundle)
        await shell.codexUsage.refresh()
        await shell.claudeUsage.refresh()
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
        #expect(measured.height < 380)
        if ProcessInfo.processInfo.environment["ISLAND_UI_CAPTURE"] == "1" {
            let bitmap = try #require(host.bitmapImageRepForCachingDisplay(in: host.bounds))
            host.cacheDisplay(in: host.bounds, to: bitmap)
            let destination = FileManager.default.temporaryDirectory.appendingPathComponent("notchent-home-live-usage.png")
            try #require(bitmap.representation(using: .png, properties: [:])).write(to: destination)
            print("Native Home with live limits: " + destination.path)
        }
    }
}

struct UsageDurationTests {
    @Test func showsTheTwoLargestUnits() {
        #expect(UsageDuration.compact(2 * 86_400 + 17 * 3600 + 120) == "2d 17h")
        #expect(UsageDuration.compact(3 * 86_400) == "3d")
        #expect(UsageDuration.compact(3600 + 38 * 60 + 30) == "1h 38m")
        #expect(UsageDuration.compact(2 * 3600) == "2h")
        #expect(UsageDuration.compact(12 * 60) == "12m")
        #expect(UsageDuration.compact(20) == "<1m")
        #expect(UsageDuration.compact(-5) == "<1m")
    }
}
