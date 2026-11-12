import Foundation
import IslandCore

/// Reads the limits the `IslandHook claude-statusline` relay saved from Claude Code.
struct NativeClaudeUsageClient: UsageClient {
    static let fiveHourMinutes = 300
    static let sevenDayMinutes = 10_080

    let relay: ClaudeUsageRelay
    let now: @Sendable () -> Date

    init(relay: ClaudeUsageRelay = ClaudeUsageRelay(), now: @escaping @Sendable () -> Date = { Date() }) {
        self.relay = relay
        self.now = now
    }

    func read() async throws -> UsageSnapshot {
        guard let stored = relay.read() else { throw UsageError.notConfigured }
        // Claude Code drops a window once it resets; do the same for the saved copy.
        guard let record = stored.current(at: now()) else { throw UsageError.invalidResponse }
        return Self.snapshot(record)
    }

    static func snapshot(_ record: ClaudeUsageRecord) -> UsageSnapshot {
        func window(_ value: ClaudeUsageRecord.Window?, minutes: Int) -> UsageWindow? {
            value.map { UsageWindow(usedPercent: $0.usedPercentage, durationMinutes: minutes, resetsAt: $0.resetsAt) }
        }
        return UsageSnapshot(primary: window(record.fiveHour, minutes: fiveHourMinutes),
                             secondary: window(record.sevenDay, minutes: sevenDayMinutes),
                             observedAt: record.observedAt)
    }
}
