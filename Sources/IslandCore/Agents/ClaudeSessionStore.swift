import Foundation

/// Recognises a Claude Code process from its executable path alone (no argv).
public enum ClaudeExecutable {
    public static func matches(_ path: String) -> Bool {
        // ClaudeCode.app's `claude --bg-pty-host` only hosts a terminal; the real session is its child.
        guard !path.contains("/ClaudeCode.app/") else { return false }
        let url = URL(fileURLWithPath: path)
        if url.lastPathComponent == "claude" { return true }
        // Native installs run the binary straight from ~/.local/share/claude/versions/<version>.
        let versions = url.deletingLastPathComponent()
        return versions.lastPathComponent == "versions" && versions.deletingLastPathComponent().lastPathComponent == "claude"
    }
}

/// What Notchent keeps about one Claude Code session, written by the `claude-hook` helper.
/// Prompts, tool input and transcripts are never stored; the last reply is cut to a short preview.
public struct ClaudeSessionRecord: Codable, Equatable, Sendable {
    public enum State: String, Codable, Sendable { case idle, working, waiting, done }
    public var sessionID: String
    public var cwd: String
    public var state: State
    public var updatedAt: Date
    public var completedAt: Date?
    public var lastMessage: String?
    /// The Claude Code process that ran the hook, so the app can tie the session to a live process.
    public var pid: Int32?
    public var birth: UInt64?
}

public struct ClaudeSessionStore: Sendable {
    public static let messageLimit = 300
    public static let maximumInputBytes = 262_144
    public let root: URL

    public init(root: URL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("IslandMac/Claude", isDirectory: true)) {
        self.root = root
    }

    /// Applies one hook payload. Unknown events and malformed input change nothing.
    public func apply(payload: Data, process: (pid: Int32, birth: UInt64)?, now: Date = Date()) throws {
        guard payload.count <= Self.maximumInputBytes,
              let json = try? JSONSerialization.jsonObject(with: payload) as? [String: Any],
              let event = json["hook_event_name"] as? String,
              let sessionID = json["session_id"] as? String, Self.isSafeID(sessionID) else { return }
        let file = url(for: sessionID)
        if event == "SessionEnd" { try? FileManager.default.removeItem(at: file); return }
        let existing = read(file)
        guard var record = Self.next(existing, event: event, json: json, sessionID: sessionID, now: now) else { return }
        if let process { record.pid = process.pid; record.birth = process.birth }
        guard record != existing else { return }
        try write(record, to: file)
    }

    /// Sessions updated within `maxAge`, newest first.
    public func load(now: Date = Date(), maxAge: TimeInterval = 12 * 3600) -> [ClaudeSessionRecord] {
        let files = (try? FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)) ?? []
        return files.filter { $0.pathExtension == "json" }
            .compactMap(read)
            .filter { now.timeIntervalSince($0.updatedAt) <= maxAge }
            .sorted { $0.updatedAt > $1.updatedAt }
    }

    static func next(_ existing: ClaudeSessionRecord?, event: String, json: [String: Any],
                     sessionID: String, now: Date) -> ClaudeSessionRecord? {
        let cwd = (json["cwd"] as? String).flatMap { $0.hasPrefix("/") ? $0 : nil } ?? existing?.cwd ?? ""
        var record = existing ?? ClaudeSessionRecord(sessionID: sessionID, cwd: cwd, state: .idle, updatedAt: now)
        record.cwd = cwd
        switch event {
        case "SessionStart":
            if existing == nil { record.state = .idle }
        case "UserPromptSubmit":
            record.state = .working; record.completedAt = nil; record.lastMessage = nil
        case "Notification":
            // The idle reminder arrives a minute after a finished turn; it is not a new question.
            guard json["notification_type"] as? String != "idle_prompt" else { return existing }
            record.state = .waiting
        case "PostToolUse":
            guard record.state == .waiting else { return existing }
            record.state = .working
        case "Stop":
            record.state = .done; record.completedAt = now
            record.lastMessage = (json["last_assistant_message"] as? String).map(Self.preview)
        default:
            return existing
        }
        record.updatedAt = now
        return record
    }

    static func preview(_ text: String) -> String {
        let flat = text.split(whereSeparator: \.isNewline).joined(separator: " ").trimmingCharacters(in: .whitespaces)
        return String(flat.prefix(messageLimit))
    }

    static func isSafeID(_ id: String) -> Bool {
        !id.isEmpty && id.count <= 128 && id.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-" || $0 == "_") }
    }

    private func url(for sessionID: String) -> URL { root.appendingPathComponent(sessionID + ".json") }

    private func read(_ url: URL) -> ClaudeSessionRecord? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? Self.decoder.decode(ClaudeSessionRecord.self, from: data)
    }

    private func write(_ record: ClaudeSessionRecord, to url: URL) throws {
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        try Self.encoder.encode(record).write(to: url, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }

    private static let encoder: JSONEncoder = { let e = JSONEncoder(); e.dateEncodingStrategy = .secondsSince1970; return e }()
    private static let decoder: JSONDecoder = { let d = JSONDecoder(); d.dateDecodingStrategy = .secondsSince1970; return d }()
}
