import Foundation
import Darwin

/// Claude subscription limits relayed from Claude Code's documented status line input.
/// Only `rate_limits` is kept; prompts, paths, and transcript data are never stored.
public struct ClaudeUsageRecord: Codable, Sendable, Equatable {
    public struct Window: Codable, Sendable, Equatable {
        public let usedPercentage: Double
        public let resetsAt: Date
        public init(usedPercentage: Double, resetsAt: Date) {
            self.usedPercentage = usedPercentage; self.resetsAt = resetsAt
        }
    }

    public let fiveHour: Window?
    public let sevenDay: Window?
    public let observedAt: Date

    public init(fiveHour: Window?, sevenDay: Window?, observedAt: Date) {
        self.fiveHour = fiveHour; self.sevenDay = sevenDay; self.observedAt = observedAt
    }

    public static let maximumInputBytes = 262_144

    /// Drops windows that have already reset; their old percentages no longer describe the account.
    public func current(at now: Date) -> Self? {
        let fiveHour = fiveHour.flatMap { $0.resetsAt > now ? $0 : nil }
        let sevenDay = sevenDay.flatMap { $0.resetsAt > now ? $0 : nil }
        guard fiveHour != nil || sevenDay != nil else { return nil }
        return Self(fiveHour: fiveHour, sevenDay: sevenDay, observedAt: observedAt)
    }

    /// Returns nil when the input has no usable `rate_limits` (API-key users, or before the first response).
    public static func extract(statusLineInput data: Data, now: Date = Date()) -> Self? {
        guard data.count <= maximumInputBytes,
              let payload = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let limits = payload["rate_limits"] as? [String: Any] else { return nil }
        let fiveHour = window(limits["five_hour"])
        let sevenDay = window(limits["seven_day"])
        guard fiveHour != nil || sevenDay != nil else { return nil }
        return Self(fiveHour: fiveHour, sevenDay: sevenDay, observedAt: now)
    }

    private static func window(_ value: Any?) -> Window? {
        guard let object = value as? [String: Any],
              let used = number(object["used_percentage"]), used.isFinite, used >= 0,
              let reset = number(object["resets_at"]), reset.isFinite, reset > 0 else { return nil }
        return Window(usedPercentage: used, resetsAt: Date(timeIntervalSince1970: reset))
    }

    private static func number(_ value: Any?) -> Double? {
        guard let number = value as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID() else { return nil }
        return number.doubleValue
    }
}

/// Private on-disk hand-off between the status line helper and the app.
public struct ClaudeUsageRelay: Sendable {
    public let directory: URL
    public var fileURL: URL { directory.appendingPathComponent("claude-rate-limits.json") }

    public init(directory: URL = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Application Support/IslandMac/Usage")) {
        self.directory = directory
    }

    private var mailbox: CodexHookMailbox { CodexHookMailbox(root: directory) }

    public func read() -> ClaudeUsageRecord? {
        guard let data = mailbox.read(fileURL) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        return try? decoder.decode(ClaudeUsageRecord.self, from: data)
    }

    /// Atomically replaces the previous record with an owner-only file.
    public func write(_ record: ClaudeUsageRecord) throws {
        try mailbox.prepare()
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .secondsSince1970
        let data = try encoder.encode(record)
        let temporary = directory.appendingPathComponent(".write-" + UUID().uuidString)
        let fd = open(temporary.path, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC, 0o600)
        guard fd >= 0 else { throw CocoaError(.fileWriteUnknown) }
        defer { unlink(temporary.path) }
        let written = data.withUnsafeBytes { Darwin.write(fd, $0.baseAddress, data.count) }
        close(fd)
        guard written == data.count, rename(temporary.path, fileURL.path) == 0 else { throw CocoaError(.fileWriteUnknown) }
    }
}

/// The text Claude Code shows under the prompt while the relay is installed.
public enum ClaudeStatusLine {
    public static func text(statusLineInput data: Data, record: ClaudeUsageRecord?) -> String {
        let payload = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        let model = (payload?["model"] as? [String: Any])?["display_name"] as? String
        var parts = [model ?? "Claude"]
        if let window = record?.fiveHour { parts.append("5h \(Int(window.usedPercentage.rounded()))%") }
        if let window = record?.sevenDay { parts.append("7d \(Int(window.usedPercentage.rounded()))%") }
        return parts.joined(separator: " · ")
    }
}
