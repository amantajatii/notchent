import Foundation
import Testing
@testable import IslandCore

struct ClaudeSessionStoreTests {
    private func makeStore() -> (ClaudeSessionStore, URL) {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        return (ClaudeSessionStore(root: dir), dir)
    }
    private func payload(_ fields: [String: Any]) -> Data {
        (try? JSONSerialization.data(withJSONObject: fields)) ?? Data()
    }
    private let id = "5032ed76-1c6d-4e75-8973-6f7d1c054ae7"

    @Test func recognisesNativeVersionedBinaryButNotThePtyHost() {
        #expect(ClaudeExecutable.matches("/Users/me/.local/share/claude/versions/2.1.322"))
        #expect(ClaudeExecutable.matches("/opt/homebrew/bin/claude"))
        #expect(!ClaudeExecutable.matches("/Users/me/.local/share/claude/ClaudeCode.app/Contents/MacOS/claude"))
        #expect(!ClaudeExecutable.matches("/usr/local/lib/node_modules/other/versions/1.0"))
    }

    @Test func promptThenStopRecordsCompletionWithShortPreview() throws {
        let (store, dir) = makeStore(); defer { try? FileManager.default.removeItem(at: dir) }
        let start = Date(timeIntervalSince1970: 1_000)
        try store.apply(payload: payload(["hook_event_name": "UserPromptSubmit", "session_id": id, "cwd": "/tmp/project", "prompt": "secret"]),
                        process: (pid: 42, birth: 7), now: start)
        #expect(store.load(now: start).first?.state == .working)
        let long = String(repeating: "word ", count: 200) + "\nnext line"
        try store.apply(payload: payload(["hook_event_name": "Stop", "session_id": id, "cwd": "/tmp/project", "last_assistant_message": long]),
                        process: (pid: 42, birth: 7), now: start.addingTimeInterval(5))
        let record = try #require(store.load(now: start).first)
        #expect(record.state == .done)
        #expect(record.completedAt == start.addingTimeInterval(5))
        #expect((record.lastMessage?.count ?? 0) <= ClaudeSessionStore.messageLimit)
        #expect(record.lastMessage?.contains("\n") == false)
        #expect(record.pid == 42 && record.birth == 7)
        let raw = try String(contentsOf: dir.appendingPathComponent(id + ".json"), encoding: .utf8)
        #expect(!raw.contains("secret"))
    }

    @Test func idleReminderDoesNotTurnAFinishedTurnIntoAQuestion() throws {
        let (store, dir) = makeStore(); defer { try? FileManager.default.removeItem(at: dir) }
        let now = Date()
        try store.apply(payload: payload(["hook_event_name": "Stop", "session_id": id, "cwd": "/tmp/p"]), process: nil, now: now)
        try store.apply(payload: payload(["hook_event_name": "Notification", "session_id": id, "notification_type": "idle_prompt"]), process: nil, now: now)
        #expect(store.load(now: now).first?.state == .done)
        try store.apply(payload: payload(["hook_event_name": "Notification", "session_id": id, "notification_type": "permission_prompt"]), process: nil, now: now)
        #expect(store.load(now: now).first?.state == .waiting)
        try store.apply(payload: payload(["hook_event_name": "PostToolUse", "session_id": id]), process: nil, now: now)
        #expect(store.load(now: now).first?.state == .working)
    }

    @Test func sessionEndRemovesTheRecordAndUnsafeIDsAreIgnored() throws {
        let (store, dir) = makeStore(); defer { try? FileManager.default.removeItem(at: dir) }
        let now = Date()
        try store.apply(payload: payload(["hook_event_name": "UserPromptSubmit", "session_id": id, "cwd": "/tmp/p"]), process: nil, now: now)
        try store.apply(payload: payload(["hook_event_name": "SessionEnd", "session_id": id]), process: nil, now: now)
        #expect(store.load(now: now).isEmpty)
        try store.apply(payload: payload(["hook_event_name": "UserPromptSubmit", "session_id": "../escape", "cwd": "/tmp/p"]), process: nil, now: now)
        try store.apply(payload: Data("not json".utf8), process: nil, now: now)
        #expect(store.load(now: now).isEmpty)
    }

    @Test func staleSessionsAreNotLoaded() throws {
        let (store, dir) = makeStore(); defer { try? FileManager.default.removeItem(at: dir) }
        let then = Date(timeIntervalSince1970: 0)
        try store.apply(payload: payload(["hook_event_name": "UserPromptSubmit", "session_id": id, "cwd": "/tmp/p"]), process: nil, now: then)
        #expect(store.load(now: then.addingTimeInterval(13 * 3600)).isEmpty)
    }
}
